import Foundation

/// Append-only debug log at `Documents/brain.log`, so an agent can pull
/// it off the device without a console attach:
///
///   xcrun devicectl device copy from --device <udid> \
///     --domain-type appDataContainer --domain-identifier <bundle_id> \
///     --source Documents/brain.log --destination <local>
///
/// (tools/pulllog.sh does this). Rotates to brain.prev.log on each launch.
/// Also mirrors to print() for `devicectl … launch --console` runs.
enum DebugLog {
    private static let queue = DispatchQueue(label: "brain.debuglog")

    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("brain.log")
        let prev = docs.appendingPathComponent("brain.prev.log")
        try? FileManager.default.removeItem(at: prev)
        try? FileManager.default.moveItem(at: url, to: prev)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        print("[Brain] \(message)")
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }
}
