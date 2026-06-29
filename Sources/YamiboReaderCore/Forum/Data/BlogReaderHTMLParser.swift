import Foundation
import SwiftSoup

public enum BlogReaderHTMLParser {
    public static func parsePage(from html: String, blogID: String, uidHint: String? = nil, titleHint: String? = nil) throws -> BlogReaderPage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let title = firstNonBlank([
            try? document.select(".blog_tit, .mtit, .bm_h h1, .vw .ph, h1").first()?.text(),
            titleHint,
            try? document.title().replacingOccurrences(of: "-  百合会", with: "")
        ]) ?? L10n.string("blog_reader.title")
        let root = rootBlogElement(in: document)
        let content = contentElement(in: root, document: document)
        let contentHTML = ((try? content?.html()) ?? "").nilIfBlank ?? ((try? root?.html()) ?? "")
        let contentText = ((try? content?.text()) ?? (try? root?.text()) ?? "").normalizedBlogText
        let pageText = ((try? document.body()?.text()) ?? "").normalizedBlogText

        guard !contentText.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.blog_reader"))
        }

        return BlogReaderPage(
            blogID: blogID,
            title: title,
            author: author(in: root, document: document, uidHint: uidHint),
            postedAtText: firstDateText(in: root) ?? firstDateText(in: document.body()),
            contentHTML: contentHTML,
            contentText: contentText,
            viewCount: intAfterAny(labels: ["查看", "浏览", "瀏覽", "阅读", "閱讀"], in: pageText),
            replyCount: intAfterAny(labels: ["回复", "回復", "评论", "評論"], in: pageText),
            collectURL: actionURL(in: document, keywords: ["收藏"]),
            shareURL: actionURL(in: document, keywords: ["分享"]),
            inviteURL: actionURL(in: document, keywords: ["邀请", "邀請"]),
            comments: parseComments(in: document),
            pageNavigation: parsePageNavigation(in: document)
        )
    }

    public static func parseCommentResult(from html: String) throws -> String {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let message = firstNonBlank([
            try? document.select(".jump_c, .alert_info, .messagetext, .showmessage, .wp, body").first()?.text()
        ])

        guard let message else {
            throw YamiboError.parsingFailed(context: L10n.string("context.blog_reader"))
        }
        if message.contains("失败") || message.contains("失敗") || message.contains("错误") || message.contains("錯誤") {
            throw YamiboError.underlying(message)
        }
        return message
    }

    private static func validate(_ html: String) throws {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }
    }

    private static func rootBlogElement(in document: Document) -> Element? {
        firstElement(in: document, selectors: [
            "#blog_article",
            ".blog_article",
            ".blogcontent",
            ".blog .content",
            ".vw .d",
            ".postmessage",
            ".message",
            ".bm_c"
        ]) ?? document.body()
    }

    private static func contentElement(in root: Element?, document: Document) -> Element? {
        if let root {
            for selector in [".blogcontent", ".blog_article", ".content", ".postmessage", ".message", "td.t_f"] {
                if let element = try? root.select(selector).first() {
                    return element
                }
            }
        }
        return rootBlogElement(in: document)
    }

    private static func parseComments(in document: Document) -> [BlogReaderComment] {
        let containers = commentContainers(in: document)
        var comments: [BlogReaderComment] = []
        var seen = Set<String>()

        for container in containers {
            let text = ((try? container.text()) ?? "").normalizedBlogText
            guard !text.isEmpty, !looksLikeRootBlog(container) else { continue }
            let commentID = commentID(in: container)
            let user = author(in: container, document: document, uidHint: nil)
            let content = commentContentElement(in: container) ?? container
            let contentHTML = ((try? content.html()) ?? "").nilIfBlank ?? ((try? container.html()) ?? "")
            let contentText = ((try? content.text()) ?? "").normalizedBlogText
            guard !contentText.isEmpty else { continue }
            let key = commentID ?? "\(user.uid ?? "")|\(user.name)|\(contentText)"
            guard seen.insert(key).inserted else { continue }
            comments.append(
                BlogReaderComment(
                    commentID: commentID,
                    author: user,
                    postedAtText: firstDateText(in: container),
                    contentHTML: contentHTML,
                    contentText: contentText,
                    replyURL: replyURL(in: container)
                )
            )
        }

        return comments
    }

    private static func commentContainers(in document: Document) -> Elements {
        let scoped = (try? document.select("#comment_ul li, .commentlist li, .blog_comment li, li[id^=comment_], dl[id^=comment_], .cmt .ptm, .comment")) ?? Elements()
        if !scoped.isEmpty {
            return scoped
        }
        return (try? document.select("li, dl")) ?? Elements()
    }

    private static func commentContentElement(in container: Element) -> Element? {
        for selector in [".comment_content", ".content", ".message", ".xg1 + div", "dd", "blockquote"] {
            if let element = try? container.select(selector).last() {
                return element
            }
        }
        return nil
    }

    private static func looksLikeRootBlog(_ element: Element) -> Bool {
        let id = (try? element.attr("id")) ?? ""
        let className = (try? element.className()) ?? ""
        return id.localizedCaseInsensitiveContains("blog_article")
            || className.localizedCaseInsensitiveContains("blog_article")
            || className.localizedCaseInsensitiveContains("blogcontent")
    }

    private static func author(in element: Element?, document: Document, uidHint: String?) -> BlogReaderUser {
        let link = firstUserLink(in: element) ?? firstUserLink(in: document)
        let href = (try? link?.attr("href")).flatMap { HTMLTextExtractor.absoluteURL(from: $0) }
        let uid = href.flatMap(userID(from:)) ?? uidHint?.nilIfBlank
        let name = firstNonBlank([
            try? link?.text(),
            try? element?.select(".author, .username, .mmc, .muser").first()?.text(),
            try? document.select(".author, .username, .mmc, .muser").first()?.text()
        ]) ?? L10n.string("user_space.unknown_user")
        return BlogReaderUser(
            uid: uid,
            name: name,
            avatarURL: firstImageURL(in: element, selectors: ["img[src*='avatar']", ".avatar img[src]", ".mimg img[src]", "img[src]"])
                ?? firstImageURL(in: document, selectors: ["img[src*='avatar']", ".avatar img[src]", ".mimg img[src]"])
        )
    }

    private static func firstUserLink(in element: Element?) -> Element? {
        guard let element else { return nil }
        return try? element.select("a[href*='uid='], a[href*='space-uid-']").first()
    }

    private static func firstUserLink(in document: Document) -> Element? {
        try? document.select("a[href*='uid='], a[href*='space-uid-']").first()
    }

    private static func firstElement(in document: Document, selectors: [String]) -> Element? {
        for selector in selectors {
            if let element = try? document.select(selector).first() {
                return element
            }
        }
        return nil
    }

    private static func firstImageURL(in element: Element?, selectors: [String]) -> URL? {
        guard let element else { return nil }
        for selector in selectors {
            if let href = try? element.select(selector).first()?.attr("src"),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
        }
        return nil
    }

    private static func firstImageURL(in document: Document, selectors: [String]) -> URL? {
        for selector in selectors {
            if let href = try? document.select(selector).first()?.attr("src"),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
        }
        return nil
    }

    private static func actionURL(in document: Document, keywords: [String]) -> URL? {
        let links = (try? document.select("a[href]")) ?? Elements()
        for link in links {
            let text = ((try? link.text()) ?? "").normalizedBlogText
            guard keywords.contains(where: { text.contains($0) }) else { continue }
            if let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? "") {
                return url
            }
        }
        return nil
    }

    private static func replyURL(in element: Element) -> URL? {
        let links = (try? element.select("a[href]")) ?? Elements()
        for link in links {
            let text = ((try? link.text()) ?? "").normalizedBlogText
            guard text.contains("回复") || text.contains("回復") || text.contains("回覆") else { continue }
            if let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? "") {
                return url
            }
        }
        return nil
    }

    private static func parsePageNavigation(in document: Document) -> ForumPageNavigation? {
        guard let pager = try? document.select(".pg").first() else { return nil }
        let currentText = ((try? pager.select("strong").first()?.text()) ?? "").normalizedBlogText
        let currentPage = Int(currentText) ?? 1
        let pagerText = ((try? pager.text()) ?? "").normalizedBlogText
        let totalPages = HTMLTextExtractor.firstMatch(pattern: #"共\s*(\d+)\s*页"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
            ?? HTMLTextExtractor.matches(pattern: #"page=(\d+)"#, in: (try? pager.html()) ?? "")
            .compactMap { $0.dropFirst().first.flatMap(Int.init) }
            .max()
        return ForumPageNavigation(currentPage: currentPage, totalPages: totalPages)
    }

    private static func commentID(in element: Element) -> String? {
        let id = (try? element.attr("id")) ?? ""
        return HTMLTextExtractor.firstMatch(pattern: #"comment[_-]?(\d+)"#, in: id)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func userID(from url: URL) -> String? {
        queryValue("uid", in: url)
            ?? HTMLTextExtractor.firstMatch(pattern: #"space-uid-(\d+)"#, in: url.absoluteString)?.dropFirst().first
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value?
            .nilIfBlank
    }

    private static func firstDateText(in element: Element?) -> String? {
        let text = ((try? element?.text()) ?? "").normalizedBlogText
        return HTMLTextExtractor.firstMatch(pattern: #"\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:\s+\d{1,2}:\d{2})?"#, in: text)?
            .first?
            .nilIfBlank
    }

    private static func intAfterAny(labels: [String], in text: String) -> Int? {
        for label in labels {
            if let value = HTMLTextExtractor.firstMatch(pattern: #"\#(label)\s*[:：]\s*(\d+)"#, in: text)?
                .dropFirst()
                .last
                .flatMap(Int.init) {
                return value
            }
        }
        return nil
    }

    private static func firstNonBlank(_ values: [String?]) -> String? {
        values.compactMap { $0?.normalizedBlogText.nilIfBlank }.first
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedBlogText: String {
        HTMLTextExtractor.decodeHTMLEntities(self)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
