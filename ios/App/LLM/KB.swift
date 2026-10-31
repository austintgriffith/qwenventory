import Foundation
import SQLite3

/// Read-only access to the notes (`Brain.db`, built by `tools/build_kb.py`
/// from data/). Retrieval runs on the phone via SQLite FTS5 and never
/// touches the network. Mirrored by `tools/ask.py`, keep in sync.
enum KB {

    struct Chunk: Identifiable, Hashable {
        let id: Int
        let doc: String
        let docTitle: String
        let heading: String
        let body: String
    }

    struct KBFile: Identifiable, Hashable {
        let file: String
        let title: String
        var id: String { file }
        /// Pushed copy in Documents/files wins over the bundled one.
        var url: URL? {
            let pushed = KB.documents.appendingPathComponent("files").appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: pushed.path) { return pushed }
            return Bundle.main.resourceURL?.appendingPathComponent("files").appendingPathComponent(file)
        }
    }

    static let chunkLimit = 6
    static let charBudget = 9000

    static let stopwords: Set<String> = Set(
        """
        a an and are am as at be been but by can could did do does doing for from had has have
        having he her here hers him his how i if in into is it its me my mine no nor not of off on or our ours
        out over she should so some such than that the their them then there these they this those to too
        under until up very was we were what when where which while who whom why will with would you your
        yours tell show give get got need know want please about any much many where's what's whats when's
        who's i'm im ive i've
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    // MARK: retrieval

    /// Notes for one question: the 00-index note, today's and tomorrow's
    /// schedule sections, then the best full-text matches, within a budget.
    static func notes(for query: String, now: Date) -> [Chunk] {
        var picked = chunks(where: "doc = ?", bind: "00-index", limit: 20)
        let tomorrow = now.addingTimeInterval(86_400)
        for day in [now, tomorrow] {
            if let chunk = chunks(where: "heading LIKE ?", bind: dayHeading(day) + " %", limit: 1).first,
                !picked.contains(where: { $0.id == chunk.id })
            {
                picked.append(chunk)
            }
        }
        if let expr = ftsExpression(query) {
            for chunk in search(expr) where !picked.contains(where: { $0.id == chunk.id }) {
                picked.append(chunk)
            }
        }
        var out: [Chunk] = []
        var total = 0
        for chunk in picked {
            let size = chunk.heading.count + chunk.body.count + 4
            if total + size > charBudget, !out.isEmpty { continue }
            out.append(chunk)
            total += size
        }
        return out
    }

    static func files(for query: String) -> [KBFile] {
        guard let expr = ftsExpression(query) else { return [] }
        return withDatabase { db in
            let sql = """
                SELECT f.file, f.title FROM files_fts JOIN files f ON f.id = files_fts.rowid
                WHERE files_fts MATCH ? ORDER BY bm25(files_fts) LIMIT 3
                """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, expr, -1, transient)
            var out: [KBFile] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(KBFile(file: column(st, 0), title: column(st, 1)))
            }
            return out
        } ?? []
    }

    static var allFiles: [KBFile] {
        withDatabase { db in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT file, title FROM files ORDER BY id", -1, &st, nil)
                == SQLITE_OK
            else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [KBFile] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(KBFile(file: column(st, 0), title: column(st, 1)))
            }
            return out
        } ?? []
    }

    static var allChunks: [Chunk] {
        chunks(where: "1 = ?", bind: "1", limit: 1000)
    }

    /// Settings from data/brain.json, copied into the db's meta table.
    static func meta(_ key: String) -> String? {
        withDatabase { db in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?", -1, &st, nil)
                == SQLITE_OK
            else { return nil }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, key, -1, transient)
            return sqlite3_step(st) == SQLITE_ROW ? column(st, 0) : nil
        }
    }

    static var builtAt: String { meta("built") ?? "?" }
    static var appName: String { meta("name") ?? "Qwenventory" }
    static var subtitle: String { meta("subtitle") ?? "private · works offline" }
    static var examples: [String] {
        guard let json = meta("examples")?.data(using: .utf8),
            let list = try? JSONDecoder().decode([String].self, from: json)
        else { return [] }
        return list
    }

    /// Where the schedule happens. Schedule headings and times use it.
    static var timeZone: TimeZone {
        meta("timezone").flatMap(TimeZone.init(identifier:)) ?? .current
    }
    /// Optional second clock (home), shown next to the local time.
    static var homeTimeZone: TimeZone? {
        meta("home_timezone").flatMap { $0.isEmpty ? nil : TimeZone(identifier: $0) }
    }

    private static func format(_ date: Date, _ pattern: String, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Tue Nov 3", matches the schedule headings.
    static func dayHeading(_ date: Date) -> String { format(date, "EEE MMM d", timeZone) }

    /// Mirrors tools/ask.py now_text.
    static func nowText(_ date: Date) -> String {
        var s = format(date, "EEE MMM d, yyyy, h:mm a", timeZone) + " (" + timeZone.identifier + ")"
        if let home = homeTimeZone {
            s += ". Home time (" + home.identifier + "): " + format(date, "EEE h:mm a", home)
        }
        return s + ". Today is " + dayHeading(date) + ". Tomorrow is "
            + dayHeading(date.addingTimeInterval(86_400)) + "."
    }

    /// Today's schedule lines from 15 minutes ago on. Mirrors tools/ask.py upcoming().
    static func upcoming(_ date: Date) -> String {
        guard let today = chunks(where: "heading LIKE ?", bind: dayHeading(date) + " %", limit: 1).first
        else { return "(nothing scheduled today)" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.hour, .minute], from: date)
        let cutoff = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) - 15
        let regex = /^~?(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?/
        var out: [String] = []
        for raw in today.body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let m = line.firstMatch(of: regex), var h = Int(m.1), let mi = Int(m.2) else {
                continue
            }
            let ap = m.3.map { $0.uppercased() } ?? ""
            if ap == "PM", h < 12 { h += 12 }
            if ap == "AM", h == 12 { h = 0 }
            if h * 60 + mi >= cutoff { out.append(line) }
        }
        return out.isEmpty ? "(nothing else today)" : out.joined(separator: "\n")
    }

    // MARK: internals

    private static func search(_ expr: String) -> [Chunk] {
        withDatabase { db in
            let sql = """
                SELECT c.id, c.doc, c.doc_title, c.heading, c.body
                FROM chunks_fts JOIN chunks c ON c.id = chunks_fts.rowid
                WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts, 3.0, 1.0) LIMIT ?
                """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, expr, -1, transient)
            sqlite3_bind_int(st, 2, Int32(chunkLimit + 1))
            return rows(st)
        } ?? []
    }

    private static func chunks(where clause: String, bind: String, limit: Int) -> [Chunk] {
        withDatabase { db in
            let sql =
                "SELECT id, doc, doc_title, heading, body FROM chunks WHERE \(clause) ORDER BY id LIMIT \(limit)"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, bind, -1, transient)
            return rows(st)
        } ?? []
    }

    private static func rows(_ st: OpaquePointer?) -> [Chunk] {
        var out: [Chunk] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(
                Chunk(
                    id: Int(sqlite3_column_int(st, 0)), doc: column(st, 1), docTitle: column(st, 2),
                    heading: column(st, 3), body: column(st, 4)))
        }
        return out
    }

    /// Free text -> a safe FTS5 expression: alphanumeric words minus
    /// stopwords, each quoted, OR'd.
    static func ftsExpression(_ query: String) -> String? {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
        guard !words.isEmpty else { return nil }
        return words.prefix(12).map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// A data-only update (tools/push.sh copies Brain.db, prompt.txt and
    /// files/ into Documents over devicectl) wins over the bundled copy, so
    /// new notes need no rebuild or reinstall.
    static func resource(_ name: String, _ ext: String) -> URL? {
        let pushed = documents.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: pushed.path) { return pushed }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static func withDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        guard let path = resource("Brain", "db")?.path else {
            DebugLog.log("Brain.db missing")
            return nil
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        return body(db)
    }

    private static func column(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let text = sqlite3_column_text(st, i) else { return "" }
        return String(cString: text)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
