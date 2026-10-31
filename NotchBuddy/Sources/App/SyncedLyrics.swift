import Foundation

/// Time-synced lyrics read from LRC text ("[01:02.34] A line").
/// Pure Foundation, so tests/SyncedLyricsTests.swift compiles it on its own.
struct SyncedLyrics: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        let time: Double   // seconds
        let text: String   // empty for an instrumental break
    }

    let lines: [Line]

    /// nil when the text holds no timed line. Metadata tags ([ar:…], [offset:…]) are skipped,
    /// a line with several timestamps ("[00:12.00][01:30.00] Chorus") appears at each of them.
    init?(lrc: String) {
        var parsed: [Line] = []
        for raw in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(raw).trimmingCharacters(in: .whitespaces)[...]
            var times: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let t = Self.seconds(tag) else { break }
                times.append(t)
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            var text = rest.trimmingCharacters(in: .whitespaces)
            // LRCLIB marks instrumental parts with a lone "♪": a break, like an empty line
            if text.allSatisfy({ "♪♫♬ ".contains($0) }) { text = "" }
            parsed += times.map { Line(time: $0, text: text) }
        }
        guard !parsed.isEmpty else { return nil }
        lines = parsed.sorted { $0.time < $1.time }
    }

    /// The line being sung at `position` (seconds): nil before the first line and during breaks.
    func line(at position: Double) -> String? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= position { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let text = lines[low - 1].text
        return text.isEmpty ? nil : text
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss:xx" → seconds.
    private static func seconds(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        let secondsText = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsText), seconds >= 0, seconds < 60,
              secondsText.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(minutes) * 60 + seconds
    }
}
