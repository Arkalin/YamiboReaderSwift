import Foundation
import SwiftSoup

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

    public static func findTagIDsMobile(in html: String) -> [String] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }
        let links = (try? document.select("a[href*='mod=tag']")) ?? Elements()
        return Array(Set(links.compactMap { element in
            let href = (try? element.attr("href")) ?? ""
            return HTMLTextExtractor.firstMatch(pattern: #"id=(\d+)"#, in: href)?.dropFirst().first
        }))
        .sorted()
    }

    public static func extractSamePageLinks(from html: String) -> [MangaChapter] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }
        guard let message = try? document.select(".message").first() else { return [] }
        let links = (try? message.select("a[href*='tid='], a[href*='thread-']")) ?? Elements()
        return links.compactMap { link in
            let href = (try? link.attr("href")) ?? ""
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let tid = MangaTitleCleaner.extractTid(from: href),
                let url = HTMLTextExtractor.absoluteURL(from: href)
            else {
                return nil
            }

            return MangaChapter(
                tid: tid,
                rawTitle: title,
                chapterNumber: MangaTitleCleaner.extractChapterNumber(title),
                url: YamiboRoute.thread(url: url, page: 1, authorID: nil).url
            )
        }
    }

    public static func extractSectionName(from html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        let selectors = [
            ".header h2 a",
            ".z a",
            ".nvhm a:last-child"
        ]
        for selector in selectors {
            if let name = try? document.select(selector).first()?.text(),
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func isAllowedMangaSection(_ sectionName: String?) -> Bool {
        guard let sectionName, !sectionName.isEmpty else { return false }
        let allowed = ["中文百合漫画区", "貼圖區", "贴图区", "原创图作区", "百合漫画图源区"]
        return allowed.contains(where: { sectionName.contains($0) })
    }

    public static func isAnnouncement(from html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html) else { return false }
        let label = (try? document.select(".view_tit em").text()) ?? ""
        return label.contains("公告")
    }

    public static func extractImageURLs(from html: String, baseURL: URL = YamiboRoute.baseURL) -> [URL] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }
        let images = (try? document.select(".img_one img, .message img:not([src*='smiley'])")) ?? Elements()
        var urls: [URL] = []
        var seen = Set<String>()

        for image in images {
            let raw = ((try? image.attr("zsrc")) ?? "").nilIfEmpty
                ?? ((try? image.attr("src")) ?? "").nilIfEmpty
            guard let raw else { continue }
            guard let url = URL(string: raw, relativeTo: baseURL)?.absoluteURL else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    public static func extractThreadTitle(from html: String) -> String? {
        if let title = ReaderHTMLParser.extractPageTitle(from: html), !title.isEmpty {
            return title
        }
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        let text = (try? document.select(".view_tit").text()) ?? ""
        return text.nilIfEmpty
    }

    public static func isLoginPage(_ html: String) -> Bool {
        let markers = [
            "请先登录",
            "登录后",
            "<title>登录 -",
            "member.php?mod=logging&action=login",
            "id=\"member_login\"",
            "class=\"pg_logging\""
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    public static func isLikelyMangaThread(title: String?, html: String) -> Bool {
        if isLoginPage(html) || isFloodControlOrError(html) || isAnnouncement(from: html) {
            return false
        }

        if isAllowedMangaSection(extractSectionName(from: html)) {
            return true
        }

        if let title, isAllowedMangaSection(title) {
            return true
        }

        return !extractImageURLs(from: html).isEmpty
            || !extractSamePageLinks(from: html).isEmpty
            || !findTagIDsMobile(in: html).isEmpty
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
