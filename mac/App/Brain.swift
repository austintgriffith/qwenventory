import AppKit
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    /// What was actually sent (the question with NOW in front). User turns only.
    var sent: String?
}

struct LocalModel: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: Int64
    let params: String
    var sizeText: String { String(format: "%.0f GB", Double(size) / 1e9) }
}

/// Talks to Ollama on this Mac. Only local models are listed, so it works with no internet.
@Observable
@MainActor
final class Brain {
    enum Status: Equatable {
        case starting
        case noOllama(String)
        case warming
        case ready
    }

    static var defaultModel: String { Notes.config.mac_model ?? "qwen3.8:27b" }
    private static let modelKey = "brain.model"
    private let base = URL(string: "http://127.0.0.1:11434")!

    private(set) var status: Status = .starting
    private(set) var models: [LocalModel] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var lastSeconds: Double?
    var model: String {
        didSet {
            guard model != oldValue else { return }
            UserDefaults.standard.set(model, forKey: Self.modelKey)
            warm()
        }
    }

    private var task: Task<Void, Never>?

    init() {
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
    }

    func start() async {
        status = .starting
        if !(await ping()) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                if await ping() { break }
            }
        }
        guard await ping() else {
            status = .noOllama("Ollama isn't running. Open the Ollama app, then press Retry.")
            return
        }
        await loadModels()
        if !models.contains(where: { $0.name == model }) {
            model = models.first(where: { $0.name == Self.defaultModel })?.name ?? models.first?.name ?? model
        }
        warm()
    }

    private func ping() async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/version"))
        req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    func loadModels() async {
        struct Tags: Decodable {
            struct M: Decodable {
                struct D: Decodable { let parameter_size: String? }
                let name: String
                let size: Int64
                let remote_host: String?
                let details: D?
            }
            let models: [M]
        }
        guard let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("api/tags")),
            let tags = try? JSONDecoder().decode(Tags.self, from: data)
        else { return }
        models = tags.models
            .filter { $0.remote_host == nil && $0.size > 0 && !$0.name.contains("embed") }
            .map { LocalModel(name: $0.name, size: $0.size, params: $0.details?.parameter_size ?? "") }
            .sorted { $0.name < $1.name }
    }

    /// Load the model and read the notes once, so the first real question is fast.
    func warm() {
        guard status != .starting || !models.isEmpty else { return }
        task?.cancel()
        status = .warming
        let model = model
        task = Task {
            _ = try? await chat(model: model, messages: [["role": "user", "content": Notes.question("hi")]],
                                maxTokens: 1) { _ in }
            if !Task.isCancelled, self.model == model { status = .ready }
        }
    }

    func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isGenerating else { return }
        messages.append(ChatMessage(role: .user, text: q, sent: Notes.question(q)))
        messages.append(ChatMessage(role: .assistant, text: ""))
        // Last 4 turns + this question. The notes already fill up to half the
        // 32k context; a long chat must not push them out.
        let history = messages.dropLast().suffix(9).map { ["role": $0.role.rawValue, "content": $0.sent ?? $0.text] }
        let model = model
        isGenerating = true
        lastSeconds = nil
        let started = Date()
        task?.cancel()
        task = Task {
            do {
                try await chat(model: model, messages: Array(history), maxTokens: 800) { piece in
                    self.messages[self.messages.count - 1].text += piece
                }
            } catch is CancellationError {
            } catch {
                if self.messages[self.messages.count - 1].text.isEmpty {
                    self.messages[self.messages.count - 1].text = "Error: \(error.localizedDescription)"
                }
            }
            if self.messages[self.messages.count - 1].text.isEmpty {
                self.messages[self.messages.count - 1].text = "(stopped)"
            }
            lastSeconds = Date().timeIntervalSince(started)
            isGenerating = false
            status = .ready
        }
    }

    func stop() { task?.cancel() }

    func clear() {
        stop()
        messages = []
        lastSeconds = nil
    }

    private func chat(model: String, messages: [[String: String]], maxTokens: Int,
                      onPiece: @escaping (String) -> Void) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 900
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "think": false,
            "keep_alive": "60m",
            "options": ["temperature": 0, "num_ctx": 32768, "num_predict": maxTokens],
            "messages": [["role": "system", "content": Notes.systemPrompt()]] + messages,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var text = ""
            for try await line in bytes.lines { text += line }
            throw NSError(domain: "Ollama", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let err = obj["error"] as? String {
                throw NSError(domain: "Ollama", code: 0, userInfo: [NSLocalizedDescriptionKey: err])
            }
            if let msg = obj["message"] as? [String: Any], let piece = msg["content"] as? String, !piece.isEmpty {
                onPiece(piece)
            }
        }
    }
}
