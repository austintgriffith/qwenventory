import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var working: Bool = false
    var openFile: (KB.KBFile) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                if message.displayText.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message.displayText)
                        .textSelection(.enabled)
                }
                if message.role == .assistant, !message.files.isEmpty, !working {
                    ForEach(message.files) { file in
                        Button {
                            openFile(file)
                        } label: {
                            Label(file.title, systemImage: "doc.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}
