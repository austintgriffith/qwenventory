import Foundation

/// Generation backend: MLX + Qwen on device, a canned stand-in in the
/// simulator (no Metal GPU there).
@MainActor
protocol LLMEngine {
    var modelName: String { get }
    func load(onProgress: @escaping @MainActor (Double) -> Void) async throws
    func setModel(_ id: String)
    func reset()
    func respond(to prompt: String) -> AsyncThrowingStream<String, Error>
}

/// Builds the system prompt both engines (and tools/ask.py) use.
enum Prompt {
    static func system(for query: String, now: Date = Date()) -> String {
        let template =
            KB.resource("prompt", "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "{notes}"
        let notes = KB.notes(for: query, now: now)
            .map { "## \($0.heading)\n\($0.body)" }
            .joined(separator: "\n\n")
        let files = KB.files(for: query).map { "\($0.file) — \($0.title)" }
        return template
            .replacingOccurrences(of: "{now}", with: KB.nowText(now))
            .replacingOccurrences(of: "{upcoming}", with: KB.upcoming(now))
            .replacingOccurrences(of: "{notes}", with: notes.isEmpty ? "(no matching notes)" : notes)
            .replacingOccurrences(
                of: "{files}", with: files.isEmpty ? "(none)" : files.joined(separator: "\n"))
    }
}

@MainActor
final class MockEngine: LLMEngine {
    private var modelID = BrainCatalog.defaultID
    var modelName: String { BrainCatalog.displayName(for: modelID) }
    func setModel(_ id: String) { modelID = id }
    func load(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(60))
            onProgress(Double(step) / 10)
        }
    }
    func reset() {}
    func respond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let notes = KB.notes(for: prompt, now: Date())
            continuation.yield(
                "Simulator (no model). Top notes:\n"
                    + notes.prefix(3).map { "• \($0.heading)" }.joined(separator: "\n"))
            continuation.finish()
        }
    }
}
