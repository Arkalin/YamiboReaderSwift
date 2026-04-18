import Foundation

public enum ReaderHTMLParser {
    public static func parseDocument(
        html: String,
        request: ReaderPageRequest,
        contentSource: ReaderContentSource = .allPostsPage
    ) throws -> ReaderPageDocument {
        if isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let parsed = parseSegments(from: html)
        let segments = parsed.segments
        guard !segments.isEmpty else {
            throw YamiboError.parsingFailed(context: "小说正文")
        }

        return ReaderPageDocument(
            threadURL: canonicalThreadURL(from: request.threadURL),
            view: request.view,
            maxView: extractMaxView(from: html, request: request),
            resolvedAuthorID: extractAuthorID(from: html) ?? request.authorID,
            contentSource: contentSource,
            retainedChapterCount: parsed.retainedChapterCount,
            filteredChapterCandidateCount: parsed.filteredChapterCandidateCount,
            segments: segments
        )
    }

    public static func parseSegments(from html: String) -> ReaderParsedContent {
        extractMessageBlocks(from: html).reduce(into: ReaderParsedContent()) { partial, block in
            let parsed = parseSegments(fromMessageHTML: block)
            partial.segments.append(contentsOf: parsed.segments)
            partial.retainedChapterCount += parsed.retainedChapterCount
            partial.filteredChapterCandidateCount += parsed.filteredChapterCandidateCount
        }
    }

    public static func isFloodControlOrError(_ html: String) -> Bool {
        let markers = [
            "防灌水",
            "灌水预防机制",
            "抱歉，指定的主题不存在或已被删除",
            "您需要先登录才能继续本操作",
            "Sorry, no permission"
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    public static func isNotAuthenticated(_ html: String) -> Bool {
        let markers = [
            "请先登录",
            "登录后",
            "您需要先登录",
            "需要登录后才能"
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    public static func extractMaxView(from html: String, request: ReaderPageRequest) -> Int {
        let fallback = max(1, request.view)
        guard let threadID = extractThreadID(from: request.threadURL) else {
            return fallback
        }

        let hrefMatches = HTMLTextExtractor.matches(
            pattern: #"<a[^>]+href=["']([^"']*(?:viewthread|thread-)[^"']*)["'][^>]*>"#,
            in: html
        )

        let pages = hrefMatches
            .compactMap { $0.dropFirst().first }
            .map(HTMLTextExtractor.decodeHTMLEntities)
            .compactMap { href -> Int? in
                if href.contains("thread-\(threadID)-") {
                    let pattern = #"thread-\#(threadID)-(\d+)-\d+\.html"#
                    return HTMLTextExtractor.firstMatch(pattern: pattern, in: href)?
                        .dropFirst()
                        .first
                        .flatMap(Int.init)
                }

                guard href.localizedCaseInsensitiveContains("viewthread"),
                      href.contains("tid=\(threadID)") else {
                    return nil
                }
                return URLComponents(string: href)?
                    .queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init)
            }

        return max(fallback, pages.max() ?? fallback)
    }

    public static func extractAuthorID(from html: String) -> String? {
        let patterns = [
            #"authorid=(\d+)"#,
            #"space-uid-(\d+)\.html"#,
            #"uid=(\d+)"#
        ]
        for pattern in patterns {
            if let value = HTMLTextExtractor.firstMatch(pattern: pattern, in: html)?.dropFirst().first {
                return value
            }
        }
        return nil
    }

    public static func extractOnlyAuthorID(from html: String, request: ReaderPageRequest) -> String? {
        guard let threadID = extractThreadID(from: request.threadURL) else { return nil }

        let hrefMatches = HTMLTextExtractor.matches(
            pattern: #"<a[^>]+href=["']([^"']*viewthread[^"']*tid=\d+[^"']*authorid=\d+[^"']*)["'][^>]*>"#,
            in: html
        )

        for groups in hrefMatches where groups.count >= 2 {
            let href = HTMLTextExtractor.decodeHTMLEntities(groups[1])
            guard href.contains("tid=\(threadID)") else { continue }
            if let authorID = HTMLTextExtractor.firstMatch(
                pattern: #"authorid=(\d+)"#,
                in: href
            )?.dropFirst().first {
                return authorID
            }
        }

        return nil
    }

    public static func extractPageTitle(from html: String) -> String? {
        guard let raw = HTMLTextExtractor.firstMatch(
            pattern: #"<title[^>]*>(.*?)</title>"#,
            in: html
        )?.dropFirst().first else {
            return nil
        }

        let title = HTMLTextExtractor.stripTags(raw)
        return title.isEmpty ? nil : title
    }

    private static func parseSegments(fromMessageHTML html: String) -> ReaderParsedContent {
        let text = readableText(from: html)
        let rawChapterTitle = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .map { String($0.prefix(30)) }
        let chapterTitle = ReaderChapterTitleNormalizer.normalize(rawChapterTitle)

        var segments: [ReaderSegment] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(text, chapterTitle: chapterTitle))
        }

        let imageMatches = HTMLTextExtractor.matches(
            pattern: #"<img[^>]+(?:zoomfile|file|src)=["']([^"']+)["'][^>]*>"#,
            in: html
        )

        for match in imageMatches {
            guard let raw = match.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !raw.localizedCaseInsensitiveContains("smiley/"),
                  let url = HTMLTextExtractor.absoluteURL(from: raw) else {
                continue
            }
            segments.append(.image(url, chapterTitle: chapterTitle))
        }

        return ReaderParsedContent(
            segments: segments,
            retainedChapterCount: chapterTitle == nil ? 0 : 1,
            filteredChapterCandidateCount: 0
        )
    }

    private static func extractMessageBlocks(from html: String) -> [String] {
        let patterns = [
            #"<(?:div|td)[^>]*class=["'][^"']*\bmessage\b[^"']*["'][^>]*>(.*?)</(?:div|td)>"#,
            #"<(?:div|td)[^>]*id=["'][^"']*postmessage[^"']*["'][^>]*>(.*?)</(?:div|td)>"#
        ]

        for pattern in patterns {
            let matches = HTMLTextExtractor.matches(pattern: pattern, in: html)
            let blocks = matches.compactMap { $0.dropFirst().first }
            if !blocks.isEmpty {
                return blocks
            }
        }
        return []
    }

    private static func readableText(from html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: #"(?i)<i[^>]*>.*?</i>"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)</div>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)</li>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "• ", options: .regularExpression)
        value = HTMLTextExtractor.decodeHTMLEntities(value)
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "\r", with: "\n")
        value = value.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalThreadURL(from url: URL) -> URL {
        var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false)
        if components?.host == nil {
            components = URLComponents(url: URL(string: url.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL ?? url, resolvingAgainstBaseURL: false)
        }

        guard var components else { return url }
        let preservedNames = Set(["mod", "tid", "extra", "authorid"])
        let retained = (components.queryItems ?? []).filter { preservedNames.contains($0.name) }
        if !retained.contains(where: { $0.name == "mod" }) {
            components.queryItems = retained + [.init(name: "mod", value: "viewthread")]
        } else {
            components.queryItems = retained
        }
        return components.url ?? url
    }

    static func extractThreadID(from url: URL) -> String? {
        if let value = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tid" })?
            .value,
           !value.isEmpty {
            return value
        }

        return HTMLTextExtractor.firstMatch(
            pattern: #"thread-(\d+)-\d+-\d+\.html"#,
            in: url.absoluteString
        )?
        .dropFirst()
        .first
    }
}

public struct ReaderParsedContent: Hashable, Sendable {
    public var segments: [ReaderSegment]
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int

    public init(
        segments: [ReaderSegment] = [],
        retainedChapterCount: Int = 0,
        filteredChapterCandidateCount: Int = 0
    ) {
        self.segments = segments
        self.retainedChapterCount = retainedChapterCount
        self.filteredChapterCandidateCount = filteredChapterCandidateCount
    }
}
