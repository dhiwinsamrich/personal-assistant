import Foundation

@main
enum SyncedLyricsTests {
    static func main() {
        let lrc = """
        [ar:Someone]
        [ti:A Song]
        [00:12.50] First line
        [00:15.00]Second line
        [00:20.00]
        [00:25:30] Third line
        [00:40.00][01:30.00] Chorus
        not a timed line
        """
        guard let lyrics = SyncedLyrics(lrc: lrc) else { preconditionFailure("parse failed") }

        // Metadata and untimed lines skipped, the chorus appears twice, sorted by time
        precondition(lyrics.lines.count == 6)
        precondition(lyrics.lines.map(\.time) == [12.5, 15, 20, 25.3, 40, 90])

        // Current line at a position
        precondition(lyrics.line(at: 0) == nil)            // before the first line
        precondition(lyrics.line(at: 12.49) == nil)
        precondition(lyrics.line(at: 12.5) == "First line")
        precondition(lyrics.line(at: 14.9) == "First line")
        precondition(lyrics.line(at: 15) == "Second line")
        precondition(lyrics.line(at: 21) == nil)           // instrumental break
        precondition(lyrics.line(at: 26) == "Third line")  // mm:ss:xx form
        precondition(lyrics.line(at: 41) == "Chorus")
        precondition(lyrics.line(at: 95) == "Chorus")
        precondition(lyrics.line(at: 10_000) == "Chorus")  // after the last line

        // Nothing timed, or broken timestamps: no lyrics
        precondition(SyncedLyrics(lrc: "") == nil)
        precondition(SyncedLyrics(lrc: "Just plain lyrics\nwith no times") == nil)
        precondition(SyncedLyrics(lrc: "[ar:Only metadata]") == nil)
        precondition(SyncedLyrics(lrc: "[00:75.00] seconds out of range") == nil)
        precondition(SyncedLyrics(lrc: "[-1:00.00] negative") == nil)

        // Windows line endings
        precondition(SyncedLyrics(lrc: "[00:01.00] A\r\n[00:02.00] B")?.line(at: 2.5) == "B")

        print("Synced lyrics: 18 cases passed")
    }
}
