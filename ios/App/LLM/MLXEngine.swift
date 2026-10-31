#if !targetEnvironment(simulator)

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// On-device backend: loads the model from the Hugging Face cache on the
/// phone (copied over USB, or downloaded once), then runs on the GPU via MLX
/// with no network. Each turn: retrieve notes for the question (KB), put
/// them in the system prompt, answer greedily.
///
/// A fresh ChatSession per turn with replayed history (KV-cache reuse
/// across turns was broken in mlx-swift-lm 3.31.x).
@MainActor
final class MLXEngine: LLMEngine {
    private var modelID = BrainCatalog.defaultID
    private var container: ModelContainer?
    /// Last few user/assistant turns, so "and their phone number?" works.
    private var history: [Chat.Message] = []
    /// Previous question, folded into retrieval for follow-ups.
    private var lastQuestion = ""

    var modelName: String { BrainCatalog.displayName(for: modelID) }

    private static func configuration(for id: String) -> ModelConfiguration {
        let eos: Set<String> =
            id.contains("Qwen") ? ["<|im_end|>"]
            : id.lowercased().contains("gemma") ? ["<end_of_turn>", "<turn|>"] : []
        return ModelConfiguration(id: id, extraEOSTokens: eos)
    }

    func setModel(_ id: String) {
        guard id != modelID else { return }
        modelID = id
        container = nil
        reset()
    }

    func load(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard container == nil else { return }
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        DebugLog.log("load() starting, model: \(modelID)")
        container = try await #huggingFaceLoadModelContainer(
            configuration: Self.configuration(for: modelID),
            progressHandler: { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in onProgress(fraction) }
            }
        )
        DebugLog.log("model loaded")
    }

    func reset() {
        history = []
        lastQuestion = ""
    }

    func respond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let container else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notLoaded) }
        }
        let system = Prompt.system(for: lastQuestion + " " + prompt)
        DebugLog.log("system prompt \(system.count) chars")
        let session = ChatSession(
            container,
            instructions: system,
            // Greedy: this app copies numbers and codes; sampling and a
            // repetition penalty both corrupt them (tools/ask.py suite).
            generateParameters: GenerateParameters(
                maxTokens: 400, temperature: 0, repetitionPenalty: nil),
            // Qwen3.5 thinks by default; answers here are lookups, not puzzles.
            additionalContext: ["enable_thinking": false]
        )
        let conversation = history.suffix(4) + [Chat.Message.user(prompt)]
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var reply = ""
                do {
                    for try await chunk in session.streamResponse(to: Array(conversation)) {
                        reply += chunk
                        continuation.yield(chunk)
                    }
                    let clean = Self.stripThinking(reply)
                    self.history += [.user(prompt), .assistant(clean)]
                    self.lastQuestion = prompt
                    continuation.finish()
                } catch {
                    DebugLog.log("stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func stripThinking(_ text: String) -> String {
        var s = text
        while let start = s.range(of: "<think>") {
            guard let end = s.range(of: "</think>", range: start.upperBound..<s.endIndex) else {
                s.removeSubrange(start.lowerBound..<s.endIndex)
                break
            }
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum EngineError: LocalizedError {
        case notLoaded
        var errorDescription: String? { "The model is not loaded yet." }
    }
}

#endif
