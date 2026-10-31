import QuickLook
import SwiftUI

/// Every bundled file. Works with no model at all.
struct FilesView: View {
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            List(KB.allFiles) { file in
                Button {
                    preview = file.url
                } label: {
                    Label(file.title, systemImage: "doc.fill")
                }
            }
            .navigationTitle("Files")
            .quickLookPreview($preview)
        }
    }
}

/// Every note, grouped by document. The fallback if the model ever misbehaves.
struct NotesView: View {
    @State private var search = ""

    private var chunks: [KB.Chunk] {
        let all = KB.allChunks
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.heading.localizedCaseInsensitiveContains(search)
                || $0.body.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.chunks) { chunk in
                            NavigationLink(chunk.heading) {
                                ScrollView {
                                    Text(chunk.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                }
                                .navigationTitle(chunk.heading)
                                .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                    }
                }
                Section {
                    Text("Notes built \(KB.builtAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $search)
            .navigationTitle("Notes")
        }
    }

    private var groups: [(title: String, chunks: [KB.Chunk])] {
        var order: [String] = []
        var map: [String: [KB.Chunk]] = [:]
        for chunk in chunks {
            if map[chunk.docTitle] == nil { order.append(chunk.docTitle) }
            map[chunk.docTitle, default: []].append(chunk)
        }
        return order.map { ($0, map[$0]!) }
    }
}
