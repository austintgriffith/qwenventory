import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    /// Files matching the question, shown as tappable chips under the answer.
    var files: [KB.KBFile] = []

    /// Qwen 3.x can emit `<think>…</think>`; hide it.
    var displayText: String {
        var s = text
        while let start = s.range(of: "<think>") {
            if let end = s.range(of: "</think>", range: start.upperBound..<s.endIndex) {
                s.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                s.removeSubrange(start.lowerBound..<s.endIndex)
                break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
