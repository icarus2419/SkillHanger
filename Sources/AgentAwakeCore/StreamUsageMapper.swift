import Foundation

public enum StreamUsageMapper {
    /// Codex `exec --json` reports observed usage on `turn.completed`.
    /// All message and tool content is ignored.
    public static func codex(line: Data) -> TokenUsage? {
        guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              value["type"] as? String == "turn.completed",
              let usage = value["usage"] as? [String: Any],
              let input = usage["input_tokens"] as? Int,
              let output = usage["output_tokens"] as? Int,
              input >= 0, output >= 0 else { return nil }
        return TokenUsage(input: input, output: output)
    }

    /// Claude `-p --output-format json|stream-json` reports aggregate usage
    /// on its final `result` event. Cached input is counted as input processed.
    /// The result text and all other provider fields are ignored.
    public static func claude(line: Data) -> TokenUsage? {
        guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              value["type"] as? String == "result",
              let usage = value["usage"] as? [String: Any],
              let uncached = usage["input_tokens"] as? Int,
              let output = usage["output_tokens"] as? Int,
              uncached >= 0, output >= 0 else { return nil }
        let created = usage["cache_creation_input_tokens"] as? Int ?? 0
        let read = usage["cache_read_input_tokens"] as? Int ?? 0
        guard created >= 0, read >= 0 else { return nil }
        let (partial, firstOverflow) = uncached.addingReportingOverflow(created)
        let (input, secondOverflow) = partial.addingReportingOverflow(read)
        guard !firstOverflow, !secondOverflow else { return nil }
        return TokenUsage(input: input, output: output)
    }
}
