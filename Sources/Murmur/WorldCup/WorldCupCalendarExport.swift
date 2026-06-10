import AppKit
import Foundation

/// Generates an .ics file for one or more matches and opens it, which hands
/// off to Calendar.app's import flow. No EventKit, no permissions — the
/// user confirms the import in Calendar themselves.
enum WorldCupCalendarExport {
    static func export(_ matches: [WorldCupMatch]) {
        guard !matches.isEmpty else { return }
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Murmur//World Cup 2026//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
        ]
        for match in matches {
            lines += event(for: match)
        }
        lines.append("END:VCALENDAR")

        let ics = lines.joined(separator: "\r\n")
        let name = matches.count == 1
            ? "\(matches[0].home.abbrev)-vs-\(matches[0].away.abbrev).ics"
            : "world-cup-2026-fixtures.ics"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            // Best-effort — nothing actionable to surface beyond the click not working.
        }
    }

    private static func event(for match: WorldCupMatch) -> [String] {
        [
            "BEGIN:VEVENT",
            "UID:wc2026-\(match.id)@murmur",
            "DTSTAMP:\(utc.string(from: Date()))",
            "DTSTART:\(utc.string(from: match.date))",
            // Regulation + buffer; knockouts may run longer but a 2h block
            // is the conventional calendar footprint.
            "DTEND:\(utc.string(from: match.date.addingTimeInterval(2 * 3600)))",
            "SUMMARY:⚽ \(escape("\(match.home.name) vs \(match.away.name)"))",
            "LOCATION:\(escape(match.venue))",
            "DESCRIPTION:\(escape("\(match.stage) · World Cup 2026 · open in Murmur: murmur://worldcup?match=\(match.id)"))",
            "END:VEVENT",
        ]
    }

    /// RFC 5545 text escaping for commas/semicolons/newlines.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
