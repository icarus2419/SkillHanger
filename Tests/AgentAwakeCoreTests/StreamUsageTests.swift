import Foundation
import Testing
@testable import AgentAwakeCore

@Test func codexJSONUsageIsObservedOnlyOnCompletedTurn() throws {
    let done = Data(#"{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"output_tokens":122}}"#.utf8)
    #expect(StreamUsageMapper.codex(line: done) == TokenUsage(input: 24763, output: 122))
    let text = Data(#"{"type":"item.completed","item":{"text":"private answer"}}"#.utf8)
    #expect(StreamUsageMapper.codex(line: text) == nil)
    let failed = Data(#"{"type":"turn.failed","usage":{"input_tokens":10,"output_tokens":2}}"#.utf8)
    #expect(StreamUsageMapper.codex(line: failed) == nil)
}

@Test func claudeResultCountsAllObservedInputWithoutReadingResultText() {
    let done = Data(#"{"type":"result","result":"private answer","usage":{"input_tokens":9,"cache_creation_input_tokens":4478,"cache_read_input_tokens":12306,"output_tokens":149}}"#.utf8)
    #expect(StreamUsageMapper.claude(line: done) == TokenUsage(input: 16793, output: 149))
    let message = Data(#"{"type":"assistant","usage":{"input_tokens":4,"output_tokens":2}}"#.utf8)
    #expect(StreamUsageMapper.claude(line: message) == nil)
    let invalid = Data(#"{"type":"result","usage":{"input_tokens":-1,"output_tokens":2}}"#.utf8)
    #expect(StreamUsageMapper.claude(line: invalid) == nil)
}
