import Foundation

public enum MangaTitleCleaner {
    public static func cleanThreadTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(
                of: #"(?i)\s+[-—–_]+\s+(.*?[区板]\s+[-—–_]+\s+)?(百合会|论坛|手机版|Powered by).*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func cleanBookName(_ rawTitle: String) -> String {
        var clean = cleanThreadTitle(rawTitle)
        let replacements = [
            #"【.*?】|\[.*?\]"#,
            #"(?i)[\(（]?c\d+[\)）]?"#,
            #"\s*[|｜].*$"#,
            #"\s+-\s+.*?(中文百合漫画区|百合会|论坛).*$"#
        ]
        for pattern in replacements {
            clean = clean.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        clean = clean.replacingOccurrences(of: #"[！？\?！!~。，、\.]+$"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"^[\s\-/\)#]+|[\s\-/\(#:]+$"#, with: "", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractTid(from url: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"tid=(\d+)"#, in: url)?.dropFirst().first
            ?? HTMLTextExtractor.firstMatch(pattern: #"thread-(\d+)-"#, in: url)?.dropFirst().first
    }

    public static func extractAuthorPrefix(_ rawTitle: String) -> String {
        if let direct = HTMLTextExtractor.firstMatch(pattern: #"^\s*【(.*?)】"#, in: rawTitle)?.dropFirst().first,
           !direct.isEmpty {
            return direct.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let direct = HTMLTextExtractor.firstMatch(pattern: #"^\s*\[(.*?)\]"#, in: rawTitle)?.dropFirst().first,
           !direct.isEmpty {
            return direct.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let prefix = HTMLTextExtractor.firstMatch(
            pattern: #"^(?:【.*?】|\[.*?\]|[\s\u{00A0}\u{3000}])+"#,
            in: rawTitle
        )?.first else {
            return ""
        }

        let bracketMatches = HTMLTextExtractor.matches(pattern: #"【(.*?)】|\[(.*?)\]"#, in: prefix)
        guard let last = bracketMatches.last else { return "" }
        return last.dropFirst().first(where: { !$0.isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func searchKeyword(_ rawTitle: String) -> String {
        let author = extractAuthorPrefix(rawTitle)
        let cleanName = cleanBookName(rawTitle)
        let combined = [author, cleanName].filter { !$0.isEmpty }.joined(separator: " ")
        return String(combined.prefix(18)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractChapterNumber(_ rawTitle: String) -> Double {
        let cleaned = rawTitle
            .replacingOccurrences(of: #"【.*?】|\[.*?\]|\(.*?\)|（.*?）|「.*?」|《.*?》"#, with: "", options: .regularExpression)

        if cleaned.range(of: #"番外|特典|附录|SP|卷后附|卷彩页|小剧场|小漫画"#, options: .regularExpression) != nil {
            return 0
        }
        if cleaned.range(of: #"最终话|最終話|最终回|最終回|大结局"#, options: .regularExpression) != nil {
            return 999
        }

        let patterns = [
            #"第\s*(\d+(?:\.\d+)?)\s*[-—]\s*(\d+(?:\.\d+)?)"#,
            #"(?:第)?\s*(\d+(?:\.\d+)?)\s*[话話织回章节幕折更]"#,
            #"第\s*(\d+(?:\.\d+)?)"#,
            #"[-—|｜]\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)(?!.*\d)"#
        ]

        for pattern in patterns {
            guard let match = HTMLTextExtractor.firstMatch(pattern: pattern, in: cleaned) else { continue }
            let numbers = match.dropFirst().compactMap(Double.init)
            if numbers.count == 2 {
                return numbers[0] + (numbers[1] / 100)
            }
            if let number = numbers.first {
                return number
            }
        }

        return 0
    }
}
