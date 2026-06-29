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

        let context = try ReaderHTMLDOMParser.parse(html: html)
        let canonicalThreadURL = canonicalThreadURL(from: request.threadURL)
        let parsed = parseSegments(
            from: context,
            threadURL: canonicalThreadURL,
            view: request.view,
            contentSource: contentSource
        )
        let segments = parsed.segments
        guard !segments.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.novel_body"))
        }

        return ReaderPageDocument(
            threadURL: canonicalThreadURL,
            view: request.view,
            maxView: (try? ReaderHTMLDOMParser.parseMaxView(in: context, request: request)) ?? max(1, request.view),
            resolvedAuthorID: extractAuthorID(from: html) ?? request.authorID,
            contentSource: contentSource,
            retainedChapterCount: parsed.retainedChapterCount,
            filteredChapterCandidateCount: parsed.filteredChapterCandidateCount,
            segments: segments,
            segmentSources: parsed.segmentSources,
            segmentSemantics: parsed.segmentSemantics
        )
    }

    public static func parseSegments(from html: String) -> ReaderParsedContent {
        guard let context = try? ReaderHTMLDOMParser.parse(html: html) else {
            return ReaderParsedContent()
        }
        return parseSegments(
            from: context,
            threadURL: URL(string: "yamibo-reader://parsed-content")!,
            view: 1,
            contentSource: .allPostsPage
        )
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
            "请登录后",
            "您需要先登录",
            "需要登录后才能",
            "登录后才能继续",
            "登录后才能查看"
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    public static func extractMaxView(from html: String, request: ReaderPageRequest) -> Int {
        guard let context = try? ReaderHTMLDOMParser.parse(html: html) else {
            return max(1, request.view)
        }
        return (try? ReaderHTMLDOMParser.parseMaxView(in: context, request: request)) ?? max(1, request.view)
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
        guard let context = try? ReaderHTMLDOMParser.parse(html: html) else {
            return nil
        }
        return try? ReaderHTMLDOMParser.parseOnlyAuthorID(in: context, request: request)
    }

    public static func extractPageTitle(from html: String) -> String? {
        if let context = try? ReaderHTMLDOMParser.parse(html: html),
           let title = try? ReaderHTMLDOMParser.parseTitle(in: context) {
            return title
        }

        guard let raw = HTMLTextExtractor.firstMatch(
            pattern: #"<title[^>]*>(.*?)</title>"#,
            in: html
        )?.dropFirst().first else {
            return nil
        }

        let title = HTMLTextExtractor.stripTags(raw)
        return title.isEmpty ? nil : title
    }

    private static func parseSegments(
        from context: ReaderHTMLDOMParser.Context,
        threadURL: URL,
        view: Int,
        contentSource: ReaderContentSource
    ) -> ReaderParsedContent {
        let messages = (try? ReaderHTMLDOMParser.parseMessages(in: context)) ?? []
        var sourceOccurrence = 0
        var textOccurrenceByChapter: [NovelChapterIdentity: Int] = [:]
        return messages.reduce(into: ReaderParsedContent()) { partial, message in
            let chapterIdentity = chapterIdentity(
                message: message,
                threadURL: threadURL,
                view: view,
                contentSource: contentSource,
                sourceOccurrence: sourceOccurrence
            )
            if message.ownerPostID == nil, chapterIdentity != nil {
                sourceOccurrence += 1
            }
            partial.segments.append(contentsOf: message.segments)
            let segmentSource = ReaderSegmentSource(
                ownerPostID: message.ownerPostID,
                isAuthorReplyToOther: message.isReplyToOther && (contentSource.isAuthorFiltered || message.isOwnerPost)
            )
            partial.segmentSources.append(
                contentsOf: Array(
                    repeating: segmentSource,
                    count: message.segments.count
                )
            )
            partial.segmentSemantics.append(
                contentsOf: message.segments.indices.map { index in
                    segmentSemantics(
                        segment: message.segments[index],
                        chapterIdentity: chapterIdentity,
                        inlineTextStyles: message.segmentInlineStyles[index],
                        blockTextStyles: message.segmentBlockStyles[index],
                        textOccurrenceByChapter: &textOccurrenceByChapter
                    )
                }
            )
            partial.retainedChapterCount += message.chapterTitle == nil ? 0 : 1
        }
    }

    private static func chapterIdentity(
        message: ReaderHTMLDOMParser.ParsedMessage,
        threadURL: URL,
        view: Int,
        contentSource: ReaderContentSource,
        sourceOccurrence: Int
    ) -> NovelChapterIdentity? {
        guard message.chapterTitle != nil else { return nil }
        if let ownerPostID = message.ownerPostID, !ownerPostID.isEmpty {
            return NovelChapterIdentity(rawValue: "post:\(ownerPostID)#chapter:0")
        }
        return NovelChapterIdentity(
            rawValue: "document:\(threadURL.absoluteString)#view:\(max(1, view))#source:\(contentSource.rawValue)#chapter:\(sourceOccurrence)"
        )
    }

    private static func segmentSemantics(
        segment: ReaderSegment,
        chapterIdentity: NovelChapterIdentity?,
        inlineTextStyles: [ReaderInlineTextStyleRange],
        blockTextStyles: [ReaderBlockTextStyleRange],
        textOccurrenceByChapter: inout [NovelChapterIdentity: Int]
    ) -> ReaderSegmentSemantics? {
        guard let chapterIdentity else { return nil }
        switch segment {
        case let .text(text, chapterTitle):
            let textOccurrence = textOccurrenceByChapter[chapterIdentity] ?? 0
            textOccurrenceByChapter[chapterIdentity] = textOccurrence + 1
            return ReaderSegmentSemantics(
                chapterIdentity: chapterIdentity,
                textSegmentIdentity: NovelTextSegmentIdentity(rawValue: "\(chapterIdentity.rawValue)#text:\(textOccurrence)"),
                chapterTitleRange: chapterTitleRange(chapterTitle: chapterTitle, text: text),
                inlineTextStyles: inlineTextStyles,
                blockTextStyles: blockTextStyles
            )

        case .image:
            return ReaderSegmentSemantics(chapterIdentity: chapterIdentity)
        }
    }

    private static func chapterTitleRange(chapterTitle: String?, text: String) -> ReaderCharacterRange? {
        guard let chapterTitle = ReaderChapterTitleNormalizer.normalize(chapterTitle),
              !chapterTitle.isEmpty,
              text.hasPrefix(chapterTitle) else {
            return nil
        }
        return ReaderCharacterRange(location: 0, length: chapterTitle.count)
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
    public var segmentSources: [ReaderSegmentSource?]
    public var segmentSemantics: [ReaderSegmentSemantics?]
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int

    public init(
        segments: [ReaderSegment] = [],
        segmentSources: [ReaderSegmentSource?] = [],
        segmentSemantics: [ReaderSegmentSemantics?] = [],
        retainedChapterCount: Int = 0,
        filteredChapterCandidateCount: Int = 0
    ) {
        self.segments = segments
        self.segmentSources = segmentSources
        self.segmentSemantics = segmentSemantics
        self.retainedChapterCount = retainedChapterCount
        self.filteredChapterCandidateCount = filteredChapterCandidateCount
    }
}
