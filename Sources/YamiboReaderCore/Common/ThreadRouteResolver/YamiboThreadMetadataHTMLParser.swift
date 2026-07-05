import Foundation

public struct YamiboThreadMetadata: Hashable, Sendable {
    public var tid: String?
    public var fid: String?
    public var title: String?
    public var authorID: String?
    public var sectionText: String?

    public init(
        tid: String? = nil,
        fid: String? = nil,
        title: String? = nil,
        authorID: String? = nil,
        sectionText: String? = nil
    ) {
        self.tid = tid?.threadRoutingTrimmedNonEmpty
        self.fid = fid?.threadRoutingTrimmedNonEmpty
        self.title = title?.threadRoutingTrimmedNonEmpty
        self.authorID = authorID?.threadRoutingTrimmedNonEmpty
        self.sectionText = sectionText?.threadRoutingTrimmedNonEmpty
    }
}

public enum YamiboThreadMetadataHTMLParser {
    public static func parse(from html: String, url: URL) throws -> YamiboThreadMetadata {
        if YamiboHTMLPageInspector.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if YamiboHTMLPageInspector.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try KannaSoup.parse(html, baseURL: YamiboDomain.baseURL.absoluteString)
        let title = YamiboHTMLPageInspector.pageTitle(from: html)
        let sectionLink = try? document
            .select("a[href*='mod=forumdisplay'][href*='fid='], a[href*='forum-']")
            .array()
            .first { link in
                let text = ((try? link.text()) ?? "").threadRoutingTrimmedNonEmpty ?? ""
                return !text.isEmpty
            }
        let sectionURL = HTMLTextExtractor.absoluteURL(from: (try? sectionLink?.attr("href")) ?? "")
        let authorLink = try? document.select("a[href*='mod=space'][href*='uid='], a[href*='space-uid-']").first()
        let authorURL = HTMLTextExtractor.absoluteURL(from: (try? authorLink?.attr("href")) ?? "")

        return YamiboThreadMetadata(
            tid: threadID(from: url) ?? threadID(from: html),
            fid: sectionURL.flatMap(forumID(from:)) ?? forumID(from: html),
            title: title,
            authorID: authorURL.flatMap(userID(from:)) ?? userID(from: html),
            sectionText: ((try? sectionLink?.text()) ?? "").threadRoutingTrimmedNonEmpty
        )
    }

    private static func forumID(from url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "fid" })?
            .value?
            .threadRoutingTrimmedNonEmpty {
            return value
        }

        return HTMLTextExtractor.firstMatch(pattern: #"forum-(\d+)-\d+\.html"#, in: url.absoluteString)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func forumID(from text: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"(?:[?&;]fid=|forum-)(\d+)"#, in: text)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func threadID(from url: URL) -> String? {
        YamiboThreadURLCanonicalizer.threadID(from: url)
    }

    private static func threadID(from text: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"(?:[?&;]tid=|thread-)(\d+)"#, in: text)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func userID(from url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "uid" })?
            .value?
            .threadRoutingTrimmedNonEmpty {
            return value
        }

        return HTMLTextExtractor.firstMatch(pattern: #"space-uid-(\d+)"#, in: url.absoluteString)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func userID(from text: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"(?:[?&;]uid=|space-uid-)(\d+)"#, in: text)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }
}
