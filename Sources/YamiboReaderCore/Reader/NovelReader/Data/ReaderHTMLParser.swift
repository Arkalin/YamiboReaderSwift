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

    public static func parseDocument(
        threadPage: ForumThreadPage,
        request: ReaderPageRequest,
        authorID: String
    ) throws -> ReaderPageDocument {
        try parseDocument(
            threadPage: threadPage,
            request: request,
            authorID: authorID,
            projectionSourceFingerprint: "",
            projectionSchemaVersion: 0
        )
    }

    public static func parseDocument(
        threadPage: ForumThreadPage,
        request: ReaderPageRequest,
        authorID: String,
        projectionSourceFingerprint: String,
        projectionSchemaVersion: Int
    ) throws -> ReaderPageDocument {
        let normalizedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAuthorID.isEmpty else {
            throw YamiboError.parsingFailed(context: "小说作者范围")
        }

        let canonicalThreadURL = canonicalThreadURL(from: request.threadURL)
        let html = syntheticReaderHTML(from: threadPage)
        let context = try ReaderHTMLDOMParser.parse(html: html)
        let parsed = parseSegments(
            from: context,
            threadURL: canonicalThreadURL,
            view: request.view,
            contentSource: .authorFilteredPage
        )
        guard !parsed.segments.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.novel_body"))
        }

        return ReaderPageDocument(
            threadURL: canonicalThreadURL,
            view: request.view,
            maxView: max(
                request.view,
                threadPage.pageNavigation?.totalPages ?? threadPage.pageNavigation?.currentPage ?? request.view
            ),
            resolvedAuthorID: normalizedAuthorID,
            contentSource: .authorFilteredPage,
            retainedChapterCount: parsed.retainedChapterCount,
            filteredChapterCandidateCount: parsed.filteredChapterCandidateCount,
            segments: parsed.segments,
            segmentSources: parsed.segmentSources,
            segmentSemantics: parsed.segmentSemantics,
            projectionSourceFingerprint: projectionSourceFingerprint,
            projectionSchemaVersion: projectionSchemaVersion
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

    private static func syntheticReaderHTML(from page: ForumThreadPage) -> String {
        let postFragments: [String] = page.posts.map { post in
            let postID = post.postID.trimmingCharacters(in: .whitespacesAndNewlines)
            let safePostID = postID.isEmpty ? "0" : postID
            let contentHTML = post.contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? escapedReaderHTMLText(from: post.contentText)
                : post.contentHTML
            let attachmentImages = attachmentImageHTML(for: post.images, excludingSourcesIn: post.contentHTML)
            let authorID = post.author.uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let authorLink = authorID.isEmpty
                ? "楼主"
                : #"<a href="home.php?mod=space&amp;uid=\#(escapeHTMLAttribute(authorID))&amp;mobile=2">楼主</a>"#
            return """
            <div class="plc cl" id="pid\(safePostID)">
              <ul class="authi"><li class="mtit">\(authorLink)</li></ul>
              <div class="message" id="postmessage_\(safePostID)">\(contentHTML)</div>
              \(attachmentImages)
            </div>
            """
        }
        let posts = postFragments.joined(separator: "\n")
        return "<html><body>\(posts)</body></html>"
    }

    private static func escapedReaderHTMLText(from text: String) -> String {
        escapeHTMLText(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escapeHTMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func attachmentImageHTML(
        for images: [ForumThreadPostImage],
        excludingSourcesIn html: String
    ) -> String {
        let missingImages = images.filter { image in
            !image.url.isEmpty && !html.contains(image.url)
        }
        guard !missingImages.isEmpty else { return "" }
        let items = missingImages.map { image in
            let alt = image.altText.map(escapeHTMLAttribute) ?? ""
            return #"<li><img src="\#(escapeHTMLAttribute(image.url))" alt="\#(alt)" /></li>"#
        }.joined()
        return #"<ul class="img_one">\#(items)</ul>"#
    }

    private static func escapeHTMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
        YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url)
    }

    static func extractThreadID(from url: URL) -> String? {
        YamiboThreadURLCanonicalizer.threadID(from: url)
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
