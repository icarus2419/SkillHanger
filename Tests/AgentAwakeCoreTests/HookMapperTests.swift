import Foundation
import Testing
@testable import AgentAwakeCore

@Test func mapsClaudeTurnWithoutKeepingPromptOrTranscript() throws {
    let payload = Data(#"{"session_id":"abc","hook_event_name":"UserPromptSubmit","prompt":"private request","transcript_path":"/private/chat.jsonl"}"#.utf8)
    let event = try #require(try HookMapper.event(provider: .claude, payload: payload))
    #expect(event.taskID == "abc")
    #expect(event.state == .running)
    #expect(event.beginsTurn)
    let record = TaskRecord.apply(event, to: nil)
    let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
    #expect(!encoded.contains("private request"))
    #expect(!encoded.contains("chat.jsonl"))
}

@Test func mapsStopsWaitsAndInterruptions() throws {
    func state(_ provider: Provider, _ name: String, extra: String = "") throws -> TaskState? {
        let payload = Data("{\"session_id\":\"s\",\"hook_event_name\":\"\(name)\"\(extra)}".utf8)
        return try HookMapper.event(provider: provider, payload: payload)?.state
    }
    #expect(try state(.codex, "Stop") == .completed)
    #expect(try state(.codex, "Interrupt") == .cancelled)
    #expect(try state(.claude, "StopFailure", extra: ",\"error\":\"rate_limit\"") == .failed)
    #expect(try state(.codex, "StopFailure") == nil)
    #expect(try state(.claude, "Notification", extra: ",\"notification_type\":\"permission_prompt\"") == .waiting)
    #expect(try state(.claude, "PostToolUse") == .running)
    let tool = try HookMapper.event(provider: .claude, payload: Data(#"{"session_id":"s","hook_event_name":"PostToolUse"}"#.utf8))
    #expect(tool?.milestone == true)
    #expect(tool?.beginsTurn == false)
    #expect(try state(.codex, "UnknownEvent") == nil)
}

@Test func mapsOnlyRealUsageFields() throws {
    let payload = Data(#"{"session_id":"s","hook_event_name":"PostToolUse","usage":{"input_tokens":33,"output_tokens":4},"prompt":"do not save"}"#.utf8)
    let event = try #require(try HookMapper.event(provider: .codex, payload: payload))
    #expect(event.usage == TokenUsage(input: 33, output: 4))
    let absent = Data(#"{"session_id":"s","hook_event_name":"PostToolUse"}"#.utf8)
    #expect(try HookMapper.event(provider: .codex, payload: absent)?.usage == nil)
}
