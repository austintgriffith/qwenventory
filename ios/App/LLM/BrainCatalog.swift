import Foundation

/// The on-device models. All run locally via MLX with no signal; `id` is the
/// Hugging Face repo. Tested with tools/ask.py (Oct 2026): Qwen3.5 4B 8-bit
/// was best on an iPhone 17 Pro (12 GB). 9B ran out of memory loading. Gemma
/// 4 E2B/E4B scored lower and missed items in lists.
///
/// To add a model: add a row here, copy it to the phone with
/// tools/copy-model.sh, then rebuild.
struct BrainModel: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let sizeText: String
    /// 1...6, rendered as that many 🧠.
    let brains: Int
    let recommended: Bool

    var brainRating: String { String(repeating: "🧠", count: max(1, brains)) }
}

enum BrainCatalog {
    static let all: [BrainModel] = [
        BrainModel(
            id: "mlx-community/Qwen3.5-4B-MLX-8bit",
            name: "Qwen3.5 4B 8-bit",
            sizeText: "~5.1 GB",
            brains: 5,
            recommended: true
        ),
        // Same model, more compressed. For phones with less memory.
        BrainModel(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            name: "Qwen3.5 4B 4-bit",
            sizeText: "~3 GB",
            brains: 4,
            recommended: false
        ),
    ]

    static let defaultID: String = all[0].id

    static func model(for id: String) -> BrainModel {
        all.first { $0.id == id } ?? all[0]
    }

    static func displayName(for id: String) -> String {
        model(for: id).name
    }
}
