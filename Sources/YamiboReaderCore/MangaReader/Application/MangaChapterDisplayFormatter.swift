import Foundation

public enum MangaChapterDisplayFormatter {
    public static func displayNumber(for chapter: MangaChapter) -> String {
        displayNumber(rawTitle: chapter.rawTitle, chapterNumber: chapter.chapterNumber)
    }

    public static func displayNumber(rawTitle: String, chapterNumber: Double) -> String {
        let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTitle.contains("最终") || normalizedTitle.localizedCaseInsensitiveContains("final") {
            return "终"
        }
        if normalizedTitle.contains("番外") || normalizedTitle.localizedCaseInsensitiveContains("special") {
            return "SP"
        }
        if normalizedTitle.contains("特别") || normalizedTitle.localizedCaseInsensitiveContains("extra") {
            return "Ex"
        }

        guard chapterNumber > 0 else { return "-" }
        if chapterNumber == floor(chapterNumber) {
            return String(Int(chapterNumber))
        }
        let formatted = String(format: "%.2f", chapterNumber)
        let parts = formatted.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return formatted }

        var suffix = parts[1]
        while suffix.last == "0" {
            suffix.removeLast()
        }
        while suffix.first == "0" {
            suffix.removeFirst()
        }
        guard !suffix.isEmpty else { return parts[0] }
        return "\(parts[0])-\(suffix)"
    }

    public static func latestChapter(in chapters: [MangaChapter]) -> MangaChapter? {
        chapters.max {
            ($0.chapterNumber, Int64($0.tid) ?? 0) < ($1.chapterNumber, Int64($1.tid) ?? 0)
        }
    }
}
