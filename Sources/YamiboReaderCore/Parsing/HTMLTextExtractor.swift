import Foundation

enum HTMLTextExtractor {
    static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.dotMatchesLineSeparators, .caseInsensitive]
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { result in
            (0 ..< result.numberOfRanges).compactMap { index in
                let range = result.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }
        }
    }

    static func firstMatch(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.dotMatchesLineSeparators, .caseInsensitive]
    ) -> [String]? {
        matches(pattern: pattern, in: text, options: options).first
    }

    static func stripTags(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var value = text
        let replacements = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (source, target) in replacements {
            value = value.replacingOccurrences(of: source, with: target)
        }
        return value
    }

    static func absoluteURL(from href: String, baseURL: URL = YamiboRoute.baseURL) -> URL? {
        URL(string: href, relativeTo: baseURL)?.absoluteURL
    }
}
