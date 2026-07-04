import Foundation

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

public enum NovelReaderProjectionBuilder {
    public static func build(
        from page: ForumThreadPage,
        request: ReaderPageRequest,
        authorID: String,
        projectionSourceFingerprint: String = "",
        projectionSchemaVersion: Int = 0
    ) throws -> NovelReaderProjection {
        let normalizedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAuthorID.isEmpty else {
            throw YamiboError.parsingFailed(context: "小说作者范围")
        }

        let parsed = try parseContent(
            from: page,
            threadID: request.threadID,
            view: request.view,
            contentSource: .authorFilteredPage
        )
        guard !parsed.segments.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.novel_body"))
        }

        return NovelReaderProjection(
            threadID: request.threadID,
            view: request.view,
            maxView: max(
                request.view,
                page.pageNavigation?.totalPages ?? page.pageNavigation?.currentPage ?? request.view
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

    private static func parseContent(
        from page: ForumThreadPage,
        threadID: String,
        view: Int,
        contentSource: ReaderContentSource
    ) throws -> ReaderParsedContent {
        var result = ReaderParsedContent()
        var sourceOccurrence = 0
        var textOccurrenceByChapter: [NovelChapterIdentity: Int] = [:]

        for post in page.posts {
            let blocks = try readerBlocks(for: post)
            let chapterTitle = ReaderChapterTitleNormalizer.normalize(firstNonEmptyLine(in: blocks))
            let projected = NovelPostContentProjector.project(
                post: post,
                blocks: blocks,
                chapterTitle: chapterTitle
            )
            guard !projected.segments.isEmpty else { continue }

            let chapterIdentity = chapterIdentity(
                postID: post.postID,
                chapterTitle: chapterTitle,
                threadID: threadID,
                view: view,
                contentSource: contentSource,
                sourceOccurrence: sourceOccurrence
            )
            if post.postID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               chapterIdentity != nil {
                sourceOccurrence += 1
            }

            result.segments.append(contentsOf: projected.segments)
            let source = ReaderSegmentSource(
                ownerPostID: post.postID,
                isAuthorReplyToOther: projected.isReplyToOther && contentSource.isAuthorFiltered
            )
            result.segmentSources.append(contentsOf: Array(repeating: source, count: projected.segments.count))
            result.segmentSemantics.append(
                contentsOf: projected.segments.indices.map { index in
                    segmentSemantics(
                        segment: projected.segments[index],
                        chapterIdentity: chapterIdentity,
                        inlineTextStyles: projected.inlineTextStyles[index],
                        blockTextStyles: projected.blockTextStyles[index],
                        textOccurrenceByChapter: &textOccurrenceByChapter
                    )
                }
            )
            result.retainedChapterCount += chapterTitle == nil ? 0 : 1
        }

        return result
    }

    private static func readerBlocks(for post: ForumThreadPost) throws -> [ForumThreadContentBlock] {
        if !post.contentBlocks.isEmpty {
            return post.contentBlocks
        }
        if !post.contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let blocks = try ForumThreadHTMLBlockParser.parseBlocks(fromHTML: post.contentHTML)
            if !blocks.isEmpty {
                return blocks
            }
        }
        guard !post.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [
            ForumThreadContentBlock(
                id: "fallback-text",
                kind: .text(ForumThreadTextBlock(text: ForumThreadHTMLBlockParser.normalizeCommittedText(post.contentText)))
            )
        ]
    }

    private static func chapterIdentity(
        postID: String,
        chapterTitle: String?,
        threadID: String,
        view: Int,
        contentSource: ReaderContentSource,
        sourceOccurrence: Int
    ) -> NovelChapterIdentity? {
        guard chapterTitle != nil else { return nil }
        let normalizedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPostID.isEmpty {
            return NovelChapterIdentity(rawValue: "post:\(normalizedPostID)#chapter:0")
        }
        return NovelChapterIdentity(
            rawValue: "thread:\(threadID)#view:\(max(1, view))#source:\(contentSource.rawValue)#chapter:\(sourceOccurrence)"
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

    private static func firstNonEmptyLine(in blocks: [ForumThreadContentBlock]) -> String? {
        let text = NovelPostContentProjector.readableText(in: blocks, excludingDiscuzQuotes: false)
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .map { String($0.prefix(30)) }
    }
}

private enum NovelPostContentProjector {
    fileprivate struct ProjectedPost {
        var segments: [ReaderSegment] = []
        var inlineTextStyles: [[ReaderInlineTextStyleRange]] = []
        var blockTextStyles: [[ReaderBlockTextStyleRange]] = []
        var isReplyToOther = false
    }

    private struct TextBuffer {
        var text = ""
        var inlineTextStyles: [ReaderInlineTextStyleRange] = []
        var blockTextStyles: [ReaderBlockTextStyleRange] = []

        var isEmpty: Bool {
            text.isEmpty
        }

        mutating func append(_ value: String, inlineStyles: [ReaderInlineTextStyleRange], isQuote: Bool) {
            guard !value.isEmpty else { return }
            let start = text.count
            text += value
            inlineTextStyles.append(
                contentsOf: inlineStyles.map { style in
                    ReaderInlineTextStyleRange(
                        style: style.style,
                        range: ReaderCharacterRange(
                            location: start + style.range.location,
                            length: style.range.length
                        )
                    )
                }
            )
            if isQuote {
                blockTextStyles.append(
                    ReaderBlockTextStyleRange(
                        style: .quote,
                        range: ReaderCharacterRange(location: start, length: value.count)
                    )
                )
            }
        }

        mutating func appendPlain(_ value: String, isQuote: Bool) {
            append(value, inlineStyles: [], isQuote: isQuote)
        }

        mutating func ensureLineBreak(isQuote: Bool) {
            guard !text.isEmpty, text.last != "\n" else { return }
            appendPlain("\n", isQuote: isQuote)
        }

        mutating func normalizeAndDrain() -> (text: String, inlineTextStyles: [ReaderInlineTextStyleRange], blockTextStyles: [ReaderBlockTextStyleRange])? {
            let characters = Array(text)
            let start = characters.firstIndex { !isTrimmable($0) } ?? characters.count
            let end = characters.lastIndex { !isTrimmable($0) }.map { $0 + 1 } ?? start
            guard start < end else {
                text = ""
                inlineTextStyles = []
                blockTextStyles = []
                return nil
            }
            let trimmed = String(characters[start ..< end])
            let maxLength = trimmed.count
            let inline = inlineTextStyles.compactMap { adjustedRange($0, trimStart: start, maxLength: maxLength) }
            let block = blockTextStyles.compactMap { adjustedRange($0, trimStart: start, maxLength: maxLength) }
            text = ""
            inlineTextStyles = []
            blockTextStyles = []
            return (trimmed, inline, block)
        }

        private func adjustedRange(
            _ style: ReaderInlineTextStyleRange,
            trimStart: Int,
            maxLength: Int
        ) -> ReaderInlineTextStyleRange? {
            let start = max(style.range.location - trimStart, 0)
            let end = min(style.range.upperBound - trimStart, maxLength)
            guard end > start else { return nil }
            return ReaderInlineTextStyleRange(
                style: style.style,
                range: ReaderCharacterRange(location: start, length: end - start)
            )
        }

        private func adjustedRange(
            _ style: ReaderBlockTextStyleRange,
            trimStart: Int,
            maxLength: Int
        ) -> ReaderBlockTextStyleRange? {
            let start = max(style.range.location - trimStart, 0)
            let end = min(style.range.upperBound - trimStart, maxLength)
            guard end > start else { return nil }
            return ReaderBlockTextStyleRange(
                style: style.style,
                range: ReaderCharacterRange(location: start, length: end - start)
            )
        }

        private func isTrimmable(_ character: Character) -> Bool {
            character == " " || character == "\t" || character == "\n" || character == "\r"
        }
    }

    static func project(
        post: ForumThreadPost,
        blocks: [ForumThreadContentBlock],
        chapterTitle: String?
    ) -> ProjectedPost {
        var projected = ProjectedPost()
        var buffer = TextBuffer()
        var emittedImageURLs = Set<String>()
        append(blocks, to: &projected, buffer: &buffer, chapterTitle: chapterTitle, isQuote: false, emittedImageURLs: &emittedImageURLs)
        flush(&buffer, into: &projected, chapterTitle: chapterTitle)
        appendMissingAttachmentImages(
            post.images,
            contentHTML: post.contentHTML,
            to: &projected,
            chapterTitle: chapterTitle,
            emittedImageURLs: &emittedImageURLs
        )
        projected.isReplyToOther = isReplyToOther(blocks)
        return projected
    }

    fileprivate static func readableText(
        in blocks: [ForumThreadContentBlock],
        excludingDiscuzQuotes: Bool
    ) -> String {
        let text = blocks.flatMap { readableTextFragments(in: $0, excludingDiscuzQuotes: excludingDiscuzQuotes) }
            .joined(separator: "\n")
        return ForumThreadHTMLBlockParser.normalizeCommittedText(text)
    }

    private static func append(
        _ blocks: [ForumThreadContentBlock],
        to projected: inout ProjectedPost,
        buffer: inout TextBuffer,
        chapterTitle: String?,
        isQuote: Bool,
        emittedImageURLs: inout Set<String>
    ) {
        for block in blocks {
            append(
                block,
                to: &projected,
                buffer: &buffer,
                chapterTitle: chapterTitle,
                isQuote: isQuote,
                emittedImageURLs: &emittedImageURLs
            )
        }
    }

    private static func append(
        _ block: ForumThreadContentBlock,
        to projected: inout ProjectedPost,
        buffer: inout TextBuffer,
        chapterTitle: String?,
        isQuote: Bool,
        emittedImageURLs: inout Set<String>
    ) {
        switch block.kind {
        case let .text(textBlock):
            buffer.append(
                textBlock.text,
                inlineStyles: boldRanges(in: textBlock),
                isQuote: isQuote
            )

        case let .image(image):
            guard !image.isEmoticon else { return }
            flush(&buffer, into: &projected, chapterTitle: chapterTitle)
            appendImage(image.url, to: &projected, chapterTitle: chapterTitle, emittedImageURLs: &emittedImageURLs)

        case let .attachment(attachment):
            buffer.appendPlain(attachment.fileName, isQuote: isQuote)

        case let .quote(blocks):
            buffer.ensureLineBreak(isQuote: isQuote)
            append(blocks, to: &projected, buffer: &buffer, chapterTitle: chapterTitle, isQuote: true, emittedImageURLs: &emittedImageURLs)
            buffer.ensureLineBreak(isQuote: isQuote)

        case let .code(text):
            buffer.appendPlain(text, isQuote: isQuote)

        case .horizontalRule:
            break

        case let .collapse(title, contentBlocks):
            if let title {
                buffer.ensureLineBreak(isQuote: isQuote)
                buffer.appendPlain(title, isQuote: isQuote)
                buffer.ensureLineBreak(isQuote: isQuote)
            }
            append(contentBlocks, to: &projected, buffer: &buffer, chapterTitle: chapterTitle, isQuote: isQuote, emittedImageURLs: &emittedImageURLs)

        case let .locked(_, contentBlocks):
            append(contentBlocks, to: &projected, buffer: &buffer, chapterTitle: chapterTitle, isQuote: isQuote, emittedImageURLs: &emittedImageURLs)

        case let .table(rows):
            let text = rows.map { row in
                row.map { cell in readableText(in: cell.blocks, excludingDiscuzQuotes: false) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            buffer.ensureLineBreak(isQuote: isQuote)
            buffer.appendPlain(text, isQuote: isQuote)
            buffer.ensureLineBreak(isQuote: isQuote)
        }
    }

    private static func flush(
        _ buffer: inout TextBuffer,
        into projected: inout ProjectedPost,
        chapterTitle: String?
    ) {
        guard let normalized = buffer.normalizeAndDrain() else { return }
        projected.segments.append(.text(normalized.text, chapterTitle: chapterTitle))
        projected.inlineTextStyles.append(normalized.inlineTextStyles)
        projected.blockTextStyles.append(normalized.blockTextStyles)
    }

    private static func appendImage(
        _ url: URL,
        to projected: inout ProjectedPost,
        chapterTitle: String?,
        emittedImageURLs: inout Set<String>
    ) {
        let lowercased = url.absoluteString.lowercased()
        guard !lowercased.contains("smiley/"),
              emittedImageURLs.insert(url.absoluteString).inserted else {
            return
        }
        projected.segments.append(.image(url, chapterTitle: chapterTitle))
        projected.inlineTextStyles.append([])
        projected.blockTextStyles.append([])
    }

    private static func appendMissingAttachmentImages(
        _ images: [ForumThreadPostImage],
        contentHTML: String,
        to projected: inout ProjectedPost,
        chapterTitle: String?,
        emittedImageURLs: inout Set<String>
    ) {
        for image in images {
            guard !contentHTML.contains(image.url) else { continue }
            guard let url = HTMLTextExtractor.absoluteURL(from: image.url) else { continue }
            appendImage(url, to: &projected, chapterTitle: chapterTitle, emittedImageURLs: &emittedImageURLs)
        }
    }

    private static func boldRanges(in textBlock: ForumThreadTextBlock) -> [ReaderInlineTextStyleRange] {
        textBlock.styleRuns.compactMap { run in
            guard run.style.isBold, run.length > 0 else { return nil }
            return ReaderInlineTextStyleRange(
                style: .bold,
                range: ReaderCharacterRange(location: run.start, length: run.length)
            )
        }
    }

    private static func isReplyToOther(_ blocks: [ForumThreadContentBlock]) -> Bool {
        guard blocks.contains(where: containsDiscuzReplyQuote) else { return false }
        return !readableText(in: blocks, excludingDiscuzQuotes: true).isEmpty
    }

    private static func containsDiscuzReplyQuote(_ block: ForumThreadContentBlock) -> Bool {
        switch block.kind {
        case let .quote(blocks):
            return containsDiscuzQuoteHeader(readableText(in: blocks, excludingDiscuzQuotes: false))
                || blocks.contains(where: containsDiscuzReplyQuote)
        case let .collapse(_, blocks), let .locked(_, blocks):
            return blocks.contains(where: containsDiscuzReplyQuote)
        case let .table(rows):
            return rows.flatMap { $0 }.contains { $0.blocks.contains(where: containsDiscuzReplyQuote) }
        default:
            return false
        }
    }

    private static func readableTextFragments(
        in block: ForumThreadContentBlock,
        excludingDiscuzQuotes: Bool
    ) -> [String] {
        switch block.kind {
        case let .text(text):
            return [text.text]
        case let .attachment(attachment):
            return [attachment.fileName]
        case let .quote(blocks):
            if excludingDiscuzQuotes,
               containsDiscuzQuoteHeader(readableText(in: blocks, excludingDiscuzQuotes: false)) {
                return []
            }
            return blocks.flatMap { readableTextFragments(in: $0, excludingDiscuzQuotes: excludingDiscuzQuotes) }
        case let .code(text):
            return [text]
        case let .collapse(title, blocks):
            return [title].compactMap { $0 }
                + blocks.flatMap { readableTextFragments(in: $0, excludingDiscuzQuotes: excludingDiscuzQuotes) }
        case let .locked(_, blocks):
            return blocks.flatMap { readableTextFragments(in: $0, excludingDiscuzQuotes: excludingDiscuzQuotes) }
        case let .table(rows):
            return rows.flatMap { row in
                row.flatMap { cell in
                    cell.blocks.flatMap { readableTextFragments(in: $0, excludingDiscuzQuotes: excludingDiscuzQuotes) }
                }
            }
        case .image, .horizontalRule:
            return []
        }
    }

    private static func containsDiscuzQuoteHeader(_ text: String) -> Bool {
        let markers = ["发表于", "發表於", "發表于", "发表於"]
        return markers.contains { text.contains($0) }
    }
}
