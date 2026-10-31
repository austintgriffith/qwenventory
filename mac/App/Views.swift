import Quartz
import SwiftUI

enum Section: Hashable {
    case ask
    case note(String)
    case file(String)
}

struct RootView: View {
    @State private var brain = Brain()
    @State private var section: Section? = .ask
    @State private var notes = Notes.notes()
    @State private var files = Notes.files()
    @State private var search = ""

    private var shownNotes: [Notes.Note] {
        search.isEmpty ? notes : notes.filter { $0.body.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Ask", systemImage: "bubble.left.and.text.bubble.right").tag(Section.ask)
                SwiftUI.Section("Notes") {
                    ForEach(shownNotes) { note in
                        Label(note.title, systemImage: "doc.text").tag(Section.note(note.file))
                    }
                }
                SwiftUI.Section("Files") {
                    ForEach(files) { file in
                        Label(file.title, systemImage: "doc.fill").tag(Section.file(file.file))
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search notes")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            switch section {
            case .note(let file):
                if let note = notes.first(where: { $0.file == file }) {
                    NoteView(note: note, highlight: search)
                }
            case .file(let file):
                if let f = files.first(where: { $0.file == file }) {
                    FileView(file: f)
                }
            default:
                ChatView(brain: brain, files: files) { section = .file($0.file) }
            }
        }
        .task { await brain.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notes = Notes.notes()
            files = Notes.files()
        }
    }
}

struct ChatView: View {
    let brain: Brain
    let files: [Notes.NoteFile]
    let openFile: (Notes.NoteFile) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let examples = Notes.config.examples ?? []

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            composer
        }
        .navigationTitle(Notes.appName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Picker("Model", selection: Binding(get: { brain.model }, set: { brain.model = $0 })) {
                    ForEach(brain.models) { m in
                        Text("\(m.name)  ·  \(m.sizeText)").tag(m.name)
                    }
                }
                .frame(minWidth: 260)
                .help("Local models in Ollama. All run offline.")
            }
            ToolbarItem {
                Button { brain.clear() } label: { Label("New chat", systemImage: "square.and.pencil") }
                    .disabled(brain.messages.isEmpty)
                    .keyboardShortcut("n")
            }
        }
        .onAppear { focused = true }
    }

    private var subtitle: String {
        switch brain.status {
        case .starting: return "Starting Ollama…"
        case .noOllama: return "Ollama not running"
        case .warming: return "Loading \(brain.model) and reading notes…"
        case .ready:
            if brain.isGenerating { return "Thinking…" }
            if let s = brain.lastSeconds { return String(format: "Offline · last answer %.0fs", s) }
            return "Offline · ready"
        }
    }

    @ViewBuilder
    private var messageList: some View {
        if case .noOllama(let msg) = brain.status {
            VStack(spacing: 12) {
                Text(msg).foregroundStyle(.secondary)
                Button("Retry") { Task { await brain.start() } }.buttonStyle(.borderedProminent)
                Text("Notes and Files in the sidebar still work.").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if brain.messages.isEmpty { emptyState }
                        ForEach(brain.messages) { m in
                            Bubble(message: m, files: matchedFiles(m), openFile: openFile).id(m.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: brain.messages.last?.text) {
                    if let last = brain.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask anything about your notes").font(.title2.bold()).padding(.top, 30)
            Text("Runs on this Mac with no internet. Dictate with Fn Fn.")
                .foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(examples, id: \.self) { ex in
                Button { brain.send(ex) } label: {
                    Text(ex).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(brain.status != .ready && brain.status != .warming)
            }
        }
    }

    /// Files the answer names, shown as buttons under it.
    private func matchedFiles(_ m: ChatMessage) -> [Notes.NoteFile] {
        guard m.role == .assistant, !(brain.isGenerating && m.id == brain.messages.last?.id) else { return [] }
        return files.filter { m.text.localizedCaseInsensitiveContains($0.file) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a question", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.body)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                .focused($focused)
                .onSubmit(submit)
            if brain.isGenerating {
                Button { brain.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                    .buttonStyle(.plain)
            } else {
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard !brain.isGenerating else { return }
        brain.send(draft)
        draft = ""
    }
}

struct Bubble: View {
    let message: ChatMessage
    let files: [Notes.NoteFile]
    let openFile: (Notes.NoteFile) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 8) {
                if message.text.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message.text.trimmingCharacters(in: .whitespacesAndNewlines)).textSelection(.enabled)
                }
                ForEach(files) { f in
                    Button { openFile(f) } label: {
                        Label(f.title, systemImage: "doc.fill").font(.callout.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(message.role == .user ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}

/// A note, with headings and bullets drawn. Search matches are highlighted.
struct NoteView: View {
    let note: Notes.Note
    let highlight: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(note.body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    row(line)
                }
            }
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(note.title)
        .navigationSubtitle(note.file)
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(marked(String(line.dropFirst(2)))).font(.title.bold())
        } else if line.hasPrefix("## ") {
            Text(marked(String(line.dropFirst(3)))).font(.title3.bold()).padding(.top, 10)
        } else if line.hasPrefix("### ") {
            Text(marked(String(line.dropFirst(4)))).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(marked(String(line.dropFirst(2))))
            }
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(marked(line))
        }
    }

    private func marked(_ s: String) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        guard !highlight.isEmpty else { return a }
        var start = a.startIndex
        while start < a.endIndex, let r = a[start...].range(of: highlight, options: .caseInsensitive) {
            a[r].backgroundColor = .yellow.opacity(0.5)
            start = r.upperBound
        }
        return a
    }
}

struct FileView: View {
    let file: Notes.NoteFile

    var body: some View {
        QuickLook(url: file.url)
            .navigationTitle(file.title)
            .navigationSubtitle(file.file)
            .toolbar {
                ToolbarItem {
                    Button { NSWorkspace.shared.open(file.url) } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                }
                ToolbarItem {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
            }
    }
}

struct QuickLook: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.autostarts = true
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? URL) != url { v.previewItem = url as NSURL }
    }
}
