import Foundation

/// The notes, read live from the repo's data/ folder so edits show up without
/// a rebuild. The repo path is baked into Info.plist (`BrainRoot`) at build.
enum Notes {
    static let root = URL(fileURLWithPath:
        Bundle.main.object(forInfoDictionaryKey: "BrainRoot") as? String ?? "")
    static let data = root.appendingPathComponent("data")
    static let notesDir = data.appendingPathComponent("notes")
    static let filesDir = data.appendingPathComponent("files")
    static let promptURL = data.appendingPathComponent("prompt-mac.txt")

    /// data/brain.json, the same settings the phone gets.
    struct Config: Decodable {
        var name: String?
        var subtitle: String?
        var timezone: String?
        var home_timezone: String?
        var examples: [String]?
        var mac_model: String?
    }

    static var config: Config {
        guard let data = try? Data(contentsOf: data.appendingPathComponent("brain.json")),
            let c = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        return c
    }

    static var appName: String { config.name ?? "Qwenventory" }
    static var timeZone: TimeZone { config.timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
    static var homeTimeZone: TimeZone? {
        config.home_timezone.flatMap { $0.isEmpty ? nil : TimeZone(identifier: $0) }
    }

    struct Note: Identifiable, Hashable {
        var id: String { file }
        let file: String
        let title: String
        let body: String
    }

    struct NoteFile: Identifiable, Hashable, Decodable {
        var id: String { file }
        let file: String
        let title: String
        var url: URL { Notes.filesDir.appendingPathComponent(file) }
    }

    static func notes() -> [Note] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let first = body.split(separator: "\n").first { $0.hasPrefix("# ") }
                let title = first.map { String($0.dropFirst(2)) } ?? url.deletingPathExtension().lastPathComponent
                return Note(file: url.lastPathComponent, title: title, body: body)
            }
    }

    static func files() -> [NoteFile] {
        let url = data.appendingPathComponent("files.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([NoteFile].self, from: data)) ?? []
    }

    /// Big and stable, so Ollama can keep it cached between questions.
    static func systemPrompt() -> String {
        let template = (try? String(contentsOf: promptURL, encoding: .utf8)) ?? "{notes}\n\n{files}"
        let notes = notes().map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n\n")
        let files = files().map { "\($0.file) — \($0.title)" }.joined(separator: "\n")
        return template.replacingOccurrences(of: "{notes}", with: notes)
            .replacingOccurrences(of: "{files}", with: files)
    }

    /// The question with the current time in front. Mirrors tools/eval.py.
    static func question(_ q: String, now: Date = Date()) -> String {
        "NOW: \(nowText(now))\nSTILL TO COME TODAY (from the schedule):\n\(upcoming(now))\n\nQUESTION: \(q)"
    }

    private static func format(_ date: Date, _ pattern: String, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Tue Nov 3", the schedule heading style.
    static func dayHeading(_ date: Date) -> String { format(date, "EEE MMM d", timeZone) }

    static func nowText(_ now: Date) -> String {
        var s = format(now, "EEE MMM d, yyyy, h:mm a", timeZone) + " (" + timeZone.identifier + ")"
        if let home = homeTimeZone {
            s += ". Home time (" + home.identifier + "): " + format(now, "EEE h:mm a", home)
        }
        return s + ". Today is " + dayHeading(now) + ". Tomorrow is " + dayHeading(now.addingTimeInterval(86400)) + "."
    }

    /// Today's schedule lines from 15 minutes ago on.
    static func upcoming(_ now: Date) -> String {
        let all = notes().map(\.body).joined(separator: "\n")
        let heading = "## " + dayHeading(now)
        var inToday = false
        var lines: [String] = []
        for line in all.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let rest = line.dropFirst(heading.count)
                inToday = line.hasPrefix(heading) && (rest.isEmpty || rest.first == " ")
                continue
            }
            if inToday { lines.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        guard !lines.isEmpty else { return "(nothing scheduled today)" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.hour, .minute], from: now)
        let cutoff = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) - 15
        let re = try! NSRegularExpression(pattern: #"^~?(\d{1,2}):(\d{2})\s*(AM|PM)?"#, options: .caseInsensitive)
        let out = lines.filter { line in
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                var h = Int(ns.substring(with: m.range(at: 1))), let mi = Int(ns.substring(with: m.range(at: 2)))
            else { return false }
            let ap = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3)).uppercased()
            if ap == "PM" && h < 12 { h += 12 }
            if ap == "AM" && h == 12 { h = 0 }
            return h * 60 + mi >= cutoff
        }
        return out.isEmpty ? "(nothing else today)" : out.joined(separator: "\n")
    }
}
