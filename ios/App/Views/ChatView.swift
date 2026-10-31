import QuickLook
import SwiftUI

struct RootView: View {
    let store: ChatStore

    var body: some View {
        TabView {
            ChatView(store: store)
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
            NotesView()
                .tabItem { Label("Notes", systemImage: "list.bullet.rectangle") }
            FilesView()
                .tabItem { Label("Files", systemImage: "folder") }
        }
    }
}

struct ChatView: View {
    let store: ChatStore
    @State private var draft = ""
    @State private var speech = SpeechRecognizer()
    @State private var draftBeforeDictation = ""
    @State private var preview: URL?
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// From data/brain.json.
    private let examples = KB.examples

    var body: some View {
        VStack(spacing: 0) {
            header
            BrainView(store: store)
                .padding(.top, 2)
                .padding(.bottom, 8)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .quickLookPreview($preview)
        // Back from the background, maybe after tools/copy-model.sh ran.
        .onChange(of: scenePhase) {
            if scenePhase == .active { store.activate() }
        }
        .task {
            store.activate()
            // Headless test hook: devicectl ... --environment-variables '{"BRAIN_ASK":"..."}'
            if let ask = ProcessInfo.processInfo.environment["BRAIN_ASK"], !ask.isEmpty,
                store.messages.isEmpty
            {
                while true {
                    if case .ready = store.modelState { break }
                    if case .failed = store.modelState { return }
                    if case .missing = store.modelState { return }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                store.send(ask)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(KB.appName)
                    .font(.title.bold())
                Text(KB.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.messages.isEmpty {
                Button {
                    store.clear()
                } label: {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch store.modelState {
        case .ready:
            VStack(spacing: 0) {
                messageList
                composer
            }
        case .idle, .downloading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(
                    store.isDownloaded(store.currentModelID)
                        ? "Waking up \(store.modelName)…" : "Downloading \(store.modelName)…"
                )
                .font(.headline)
                Text("Works with no signal. Notes and Files tabs work right now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                Spacer()
            }
        case .missing:
            VStack(spacing: 16) {
                Spacer()
                Text("\(store.modelName) isn't on this phone yet").font(.headline)
                Text(
                    "Plug into your Mac and run tools/copy-model.sh, then come back to this app. Or download it here on Wi-Fi (\(store.currentModel.sizeText))."
                )
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Download on Wi-Fi") { store.downloadModel(store.currentModelID) }
                    .buttonStyle(.bordered)
                Text("Notes and Files tabs still work.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
        case .failed(let message):
            VStack(spacing: 16) {
                Spacer()
                Text("Couldn't load \(store.modelName)").font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Retry") { store.downloadModel(store.currentModelID) }
                    .buttonStyle(.borderedProminent)
                Text("Notes and Files tabs still work.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.messages.isEmpty {
                        VStack(spacing: 8) {
                            Text("Ask anything about your notes")
                                .font(.title3.bold())
                                .padding(.top, 24)
                            ForEach(examples, id: \.self) { example in
                                Button {
                                    store.send(example)
                                } label: {
                                    Text(example)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            .fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            working: store.isGenerating && message.id == store.messages.last?.id,
                            openFile: { preview = $0.url }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: store.messages.last?.text) {
                if let last = store.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onTapGesture { inputFocused = false }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                speech.isRecording ? "Listening…" : "Ask a question", text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 18))
            .focused($inputFocused)
            .onChange(of: speech.transcript) {
                guard speech.isRecording else { return }
                draft =
                    draftBeforeDictation.isEmpty
                    ? speech.transcript : draftBeforeDictation + " " + speech.transcript
            }

            Button {
                if !speech.isRecording { draftBeforeDictation = draft }
                speech.toggle()
            } label: {
                Image(systemName: speech.isRecording ? "mic.circle.fill" : "mic.circle")
                    .font(.title)
                    .foregroundStyle(speech.isRecording ? .red : .accentColor)
            }

            if store.isGenerating {
                Button {
                    store.stopGenerating()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
            } else {
                Button {
                    if speech.isRecording { speech.stop() }
                    store.send(draft)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
