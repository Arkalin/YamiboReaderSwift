import Foundation

public enum MangaHTMLParser {
    public static func findTagIDs(in html: String) -> [String] {
        let matches = HTMLTextExtractor.matches(pattern: #"href=["'][^"']*mod=tag[^"']*id=(\d+)[^"']*["']"#, in: html)
        return Array(Set(matches.compactMap { $0.dropFirst().first })).sorted()
    }

    public static func extractSearchID(from html: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"searchid=(\d+)"#, in: html)?.dropFirst().first
    }

    public static func extractTotalPages(from html: String) -> Int {
        let optionValues = HTMLTextExtractor.matches(pattern: #"<option[^>]*value=["'](\d+)["']"#, in: html)
            .compactMap { Int($0.dropFirst().first ?? "") }
        if let max = optionValues.max() {
            return max
        }

        let titlePage = HTMLTextExtractor.firstMatch(pattern: #"title=["'][^"']*(\d+)[^"']*["']"#, in: html)?
            .dropFirst()
            .compactMap(Int.init)
            .max()
        if let titlePage {
            return titlePage
        }

        let linkedPages = HTMLTextExtractor.matches(pattern: #">(\d+)</a>"#, in: html)
            .compactMap { Int($0.dropFirst().first ?? "") }
        return linkedPages.max() ?? 1
    }

    public static func isFloodControlOrError(_ html: String) -> Bool {
        guard !html.contains("没有找到匹配结果") else { return false }
        return html.contains("只能进行一次搜索")
            || html.contains("防灌水")
            || html.contains("指定的搜索词长度")
    }

    public static func parseListHTML(_ html: String, groupIndex: Int = 0) -> [MangaChapter] {
        parsePCList(html, groupIndex: groupIndex) + parseMobileSearchList(html, groupIndex: groupIndex)
    }

    private static func parsePCList(_ html: String, groupIndex: Int) -> [MangaChapter] {
        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        return HTMLTextExtractor.matches(pattern: rowPattern, in: html).compactMap { row in
            guard let rowHTML = row.first else { return nil }
            guard let link = HTMLTextExtractor.firstMatch(pattern: #"<th[^>]*>.*?<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, in: rowHTML) else {
                return nil
            }
            let href = link[1]
            let title = HTMLTextExtractor.stripTags(link[2])
            guard
                let tid = MangaTitleCleaner.extractTid(from: href),
                let url = HTMLTextExtractor.absoluteURL(from: href)
            else {
                return nil
            }

            let authorHref = HTMLTextExtractor.firstMatch(pattern: #"<cite>\s*<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, in: rowHTML)
            let authorURL = authorHref?[1] ?? ""
            let authorName = authorHref.map { HTMLTextExtractor.stripTags($0[2]) }
            let dateText = HTMLTextExtractor.firstMatch(pattern: #"<em(?:\s+[^>]*)?>.*?(\d{4}-\d{2}-\d{2}).*?</em>"#, in: rowHTML)?
                .dropFirst()
                .first

            return MangaChapter(
                tid: tid,
                rawTitle: title,
                chapterNumber: MangaTitleCleaner.extractChapterNumber(title),
                url: url,
                authorUID: extractUID(from: authorURL),
                authorName: authorName,
                groupIndex: groupIndex,
                publishTime: parseDate(dateText)
            )
        }
    }

    private static func parseMobileSearchList(_ html: String, groupIndex: Int) -> [MangaChapter] {
        let itemPattern = #"<li[^>]*class=["'][^"']*list[^"']*["'][^>]*>(.*?)</li>"#
        return HTMLTextExtractor.matches(pattern: itemPattern, in: html).compactMap { item in
            guard let block = item.first else { return nil }
            guard let link = HTMLTextExtractor.firstMatch(pattern: #"<a[^>]*href=["']([^"']*tid=\d+[^"']*)["'][^>]*>(.*?)</a>"#, in: block) else {
                return nil
            }
            let href = link[1]
            let title = HTMLTextExtractor.stripTags(link[2])
            guard
                let tid = MangaTitleCleaner.extractTid(from: href),
                let url = HTMLTextExtractor.absoluteURL(from: href)
            else {
                return nil
            }

            let authorMatch = HTMLTextExtractor.firstMatch(pattern: #"<h3>\s*<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, in: block)
            return MangaChapter(
                tid: tid,
                rawTitle: title,
                chapterNumber: MangaTitleCleaner.extractChapterNumber(title),
                url: url,
                authorUID: extractUID(from: authorMatch?[1] ?? ""),
                authorName: authorMatch.map { HTMLTextExtractor.stripTags($0[2]) },
                groupIndex: groupIndex
            )
        }
    }

    private static func extractUID(from url: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"uid=(\d+)"#, in: url)?.dropFirst().first
            ?? HTMLTextExtractor.firstMatch(pattern: #"uid-(\d+)"#, in: url)?.dropFirst().first
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
