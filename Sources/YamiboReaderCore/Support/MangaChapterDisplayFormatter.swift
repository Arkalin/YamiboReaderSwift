import Foundation

public enum MangaChapterDisplayFormatter {
    private static let specialChapterPattern = #"番外|特典|附录|SP|卷后附|卷彩页|小剧场|小漫画"#
    private static let latestExclusionPattern = #"番外|特典|附录|SP|卷后附|卷彩页"#
    private static let zeroMarkerPattern = #"0|零|〇"#

    public static func displayNumber(for chapter: MangaChapter) -> String {
        displayNumber(rawTitle: chapter.rawTitle, chapterNumber: chapter.chapterNumber)
    }

    public static func displayNumber(rawTitle: String, chapterNumber: Double) -> String {
        if rawTitle.range(of: specialChapterPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return "SP"
        }
        if chapterNumber == 999 {
            return L10n.string("manga.chapter.final")
        }
        if chapterNumber < 1,
           rawTitle.range(of: zeroMarkerPattern, options: .regularExpression) == nil {
            return "Ex"
        }

        let safe = formattedNumber(chapterNumber)
        guard safe.contains(".") else { return safe }
        let parts = safe.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return safe }
        if parts[1].count >= 3 {
            return "Ex"
        }
        return "\(parts[0])-\(parts[1].trimmingLeadingZeros)"
    }

    public static func isLatestCandidate(_ chapter: MangaChapter) -> Bool {
        if chapter.rawTitle.range(of: latestExclusionPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return decimalPlaces(in: chapter.chapterNumber) < 3
    }

    public static func latestChapter(in chapters: [MangaChapter]) -> MangaChapter? {
        chapters.filter(isLatestCandidate(_:)).max { lhs, rhs in
            lhs.chapterNumber < rhs.chapterNumber
        }
    }

    private static func formattedNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private static func decimalPlaces(in number: Double) -> Int {
        let formatted = formattedNumber(number)
        guard let decimalPart = formatted.split(separator: ".", maxSplits: 1).last,
              formatted.contains(".")
        else {
            return 0
        }
        return decimalPart.count
    }
}

private extension String {
    var trimmingLeadingZeros: String {
        let trimmed = drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}
