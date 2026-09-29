import AgentAwakeCore
import Darwin
import Dispatch
import Foundation

private func usage() -> Never {
    fputs("Usage: agent-awake hook <claude|codex> | run <claude|codex> -- <command> [args...] | status\n", stderr)
    exit(2)
}

private func provider(_ string: String) -> Provider {
    guard let value = Provider(rawValue: string) else { usage() }
    return value
}

private func write(_ event: TaskEvent, store: TaskStore) {
    do { try store.apply(event) }
    catch { fputs("Agent Awake: \(error.localizedDescription)\n", stderr) }
}

private func runHook(_ source: Provider, store: TaskStore) {
    let wrapped = ProcessInfo.processInfo.environment["AGENT_AWAKE_WRAPPED_PROVIDER"] == source.rawValue
    let wrappedID = ProcessInfo.processInfo.environment["AGENT_AWAKE_WRAPPED_TASK_ID"]
    // Provider hooks may include prompts. Parse in memory; persist only HookMapper's allowlisted fields.
    let payload = FileHandle.standardInput.readData(ofLength: 8 * 1024 * 1024)
    do {
        if let event = try HookMapper.event(provider: source, payload: payload) {
            if wrapped, let wrappedID {
                try store.apply(TaskEvent(provider: source, taskID: wrappedID, state: event.state,
                                          observedAt: event.observedAt, leaseSeconds: 8, usage: event.usage,
                                          milestone: event.milestone, beginsTurn: event.beginsTurn))
            } else if !wrapped {
                try store.apply(event)
            }
        }
    } catch {
        fputs("Agent Awake: ignored invalid hook payload: \(error.localizedDescription)\n", stderr)
    }
    // Codex Stop hooks expect valid JSON on stdout. Empty output is safest for Claude.
    if source == .codex { print("{}") }
}

private func runCommand(_ source: Provider, command: [String], store: TaskStore) -> Never {
    guard !command.isEmpty else { usage() }
    guard LaunchCommand.isSupported(provider: source, command: command) else {
        fputs("Agent Awake: run supports finite tasks only: codex exec or claude -p. Use hooks for interactive sessions.\n", stderr)
        exit(2)
    }
    let id = UUID().uuidString
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    var childEnvironment = ProcessInfo.processInfo.environment
    childEnvironment["AGENT_AWAKE_WRAPPED_PROVIDER"] = source.rawValue
    childEnvironment["AGENT_AWAKE_WRAPPED_TASK_ID"] = id
    process.environment = childEnvironment
    process.standardInput = FileHandle.standardInput
    let claudeFormat = command.contains("--output-format=json") || command.contains("--output-format=stream-json")
        || command.indices.contains { index in command[index] == "--output-format" && command.indices.contains(index + 1) && ["json", "stream-json"].contains(command[index + 1]) }
    let captureUsage = source == .codex ? command.contains("--json") : claudeFormat
    let outputPipe = captureUsage ? Pipe() : nil
    process.standardOutput = outputPipe ?? FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    let queue = DispatchQueue(label: "AgentAwake.runner.\(id)")
    let timer = DispatchSource.makeTimerSource(queue: queue)
    var cancellationRequested = false
    timer.schedule(deadline: .now() + 2, repeating: 2)
    timer.setEventHandler {
        do { try store.heartbeat(provider: source, id: id) }
        catch { fputs("Agent Awake: \(error.localizedDescription)\n", stderr) }
    }

    do {
        let launchObservedAt = Date()
        try process.run()
        // Keep the wrapper alive long enough to record the child's terminal state.
        // Terminal Ctrl-C reaches both processes; a signal sent only to the wrapper
        // is forwarded to the child as well.
        let childPID = process.processIdentifier
        let signals = [SIGINT, SIGTERM].map { number in
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                cancellationRequested = true
                if process.isRunning { _ = Darwin.kill(childPID, number) }
            }
            source.activate()
            return source
        }
        write(TaskEvent(provider: source, taskID: id, state: .running, observedAt: launchObservedAt,
                        leaseSeconds: 8, beginsTurn: true), store: store)
        timer.activate()
        if let outputPipe {
            var pending = Data()
            while true {
                let chunk = outputPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                FileHandle.standardOutput.write(chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<newline])
                    let usage = source == .codex ? StreamUsageMapper.codex(line: line) : StreamUsageMapper.claude(line: line)
                    if let usage {
                        do { try store.observeUsage(provider: source, id: id, usage: usage) }
                        catch { fputs("Agent Awake: \(error.localizedDescription)\n", stderr) }
                    }
                    pending.removeSubrange(...newline)
                }
                if pending.count > 1_048_576 { pending.removeAll(keepingCapacity: true) }
            }
            let usage = source == .codex ? StreamUsageMapper.codex(line: pending) : StreamUsageMapper.claude(line: pending)
            if let usage {
                do { try store.observeUsage(provider: source, id: id, usage: usage) }
                catch { fputs("Agent Awake: \(error.localizedDescription)\n", stderr) }
            }
        }
        process.waitUntilExit()
        let exitCode = process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus : process.terminationStatus
        queue.sync {
            timer.cancel()
            signals.forEach { $0.cancel() }
            let state: TaskState = cancellationRequested || process.terminationReason == .uncaughtSignal
                ? .cancelled : (process.terminationStatus == 0 ? .completed : .failed)
            do { try store.finish(provider: source, id: id, state: state) }
            catch { fputs("Agent Awake: \(error.localizedDescription)\n", stderr) }
        }
        exit(exitCode)
    } catch {
        try? store.finish(provider: source, id: id, state: .failed)
        fputs("Agent Awake: could not start command: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let store = TaskStore()
guard let action = args.first else { usage() }

switch action {
case "hook":
    guard args.count == 2 else { usage() }
    runHook(provider(args[1]), store: store)
case "run":
    guard args.count >= 4, args[2] == "--" else { usage() }
    runCommand(provider(args[1]), command: Array(args.dropFirst(3)), store: store)
case "status":
    do {
        for task in try store.load() {
            print("\(task.provider.displayName) \(task.id) \(task.effectiveState(at: Date()).rawValue)")
        }
    } catch {
        fputs("Agent Awake: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
default:
    usage()
}
