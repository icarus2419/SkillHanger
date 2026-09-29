import Foundation

public enum HookMapper {
    /// Reads only stable lifecycle metadata. Prompt, transcript and tool payloads are ignored.
    public static func event(provider: Provider, payload: Data, observedAt: Date = Date()) throws -> TaskEvent? {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sessionID = object["session_id"] as? String,
              !sessionID.isEmpty,
              let hookName = object["hook_event_name"] as? String else { return nil }

        let state: TaskState
        switch hookName {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStop":
            state = .running
        case "SessionStart":
            state = .waiting
        case "PermissionRequest":
            state = .waiting
        case "Notification" where provider == .claude:
            guard let type = object["notification_type"] as? String,
                  type == "permission_prompt" || type == "idle_prompt" else { return nil }
            state = .waiting
        case "Stop":
            state = .completed
        case "StopFailure" where provider == .claude:
            state = .failed
        case "Interrupt":
            state = .cancelled
        case "SessionEnd":
            state = (object["reason"] as? String) == "error" ? .failed : .completed
        default:
            return nil
        }

        let usageObject = object["usage"] as? [String: Any]
        let input = usageObject?["input_tokens"] as? Int
        let output = usageObject?["output_tokens"] as? Int
        let usage: TokenUsage? = if let input, let output, input >= 0, output >= 0 {
            TokenUsage(input: input, output: output)
        } else {
            nil
        }

        return TaskEvent(provider: provider, taskID: sessionID, state: state, observedAt: observedAt, usage: usage,
                         milestone: hookName == "PostToolUse", beginsTurn: hookName == "UserPromptSubmit" || hookName == "SessionStart")
    }
}
