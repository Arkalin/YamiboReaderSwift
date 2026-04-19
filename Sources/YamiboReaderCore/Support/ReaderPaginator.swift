import Foundation

public enum ReaderPaginator {
    public static func paginate(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> ReaderPaginationResult {
        let usableLayout = normalizedLayout(layout, padding: settings.horizontalPadding)
        let transformedSegments = transformedSegments(from: document.segments, settings: settings)

        switch settings.readingMode {
        case .paged:
            return paginatePaged(segments: transformedSegments, settings: settings, layout: usableLayout)
        case .vertical:
            return paginateVertical(segments: transformedSegments, settings: settings, layout: usableLayout)
        }
    }

    private static func paginatePaged(
        segments: [ReaderSegment],
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> ReaderPaginationResult {
        let metrics = textMetrics(settings: settings)

        var pages: [ReaderRenderedPage] = []
        var chapters: [ReaderChapter] = []
        var seenTitles = Set<String>()

        for segment in segments {
            switch segment {
            case let .text(text, chapterTitle):
                let slices = paginateText(
                    text,
                    width: layout.width,
                    height: layout.height,
                    settings: settings,
                    metrics: metrics
                )
                for slice in slices where !slice.isEmpty {
                    let page = ReaderRenderedPage(
                        index: pages.count,
                        blocks: [.text(slice, chapterTitle: chapterTitle)]
                    )
                    if let chapterTitle, seenTitles.insert(chapterTitle).inserted {
                        chapters.append(ReaderChapter(title: chapterTitle, startIndex: page.index))
                    }
                    pages.append(page)
                }
            case let .image(url, chapterTitle):
                let page = ReaderRenderedPage(
                    index: pages.count,
                    blocks: [.image(url, chapterTitle: chapterTitle)]
                )
                if let chapterTitle, seenTitles.insert(chapterTitle).inserted {
                    chapters.append(ReaderChapter(title: chapterTitle, startIndex: page.index))
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages = [ReaderRenderedPage(index: 0, blocks: [.footer("暂无可显示内容")])]
        }

        return ReaderPaginationResult(pages: pages, chapters: chapters)
    }

    private static func paginateVertical(
        segments: [ReaderSegment],
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> ReaderPaginationResult {
        var pages: [ReaderRenderedPage] = []
        var chapters: [ReaderChapter] = []
        var seenTitles = Set<String>()

        for segment in segments {
            switch segment {
            case let .text(text, chapterTitle):
                let chunks = verticalTextChunks(from: text, settings: settings, layout: layout)
                for chunk in chunks where !chunk.isEmpty {
                    let page = ReaderRenderedPage(
                        index: pages.count,
                        blocks: [.text(chunk, chapterTitle: chapterTitle)]
                    )
                    if let chapterTitle, seenTitles.insert(chapterTitle).inserted {
                        chapters.append(ReaderChapter(title: chapterTitle, startIndex: page.index))
                    }
                    pages.append(page)
                }
            case let .image(url, chapterTitle):
                let page = ReaderRenderedPage(
                    index: pages.count,
                    blocks: [.image(url, chapterTitle: chapterTitle)]
                )
                if let chapterTitle, seenTitles.insert(chapterTitle).inserted {
                    chapters.append(ReaderChapter(title: chapterTitle, startIndex: page.index))
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages = [ReaderRenderedPage(index: 0, blocks: [.footer("暂无可显示内容")])]
        }

        return ReaderPaginationResult(pages: pages, chapters: chapters)
    }

    private static func transformedSegments(
        from segments: [ReaderSegment],
        settings: ReaderAppearanceSettings
    ) -> [ReaderSegment] {
        segments.compactMap { segment in
            switch segment {
            case let .text(text, chapterTitle):
                let transformed = ReaderTextTransformer.transform(text, mode: settings.translationMode)
                return .text(transformed, chapterTitle: chapterTitle)
            case let .image(url, chapterTitle):
                return settings.loadsInlineImages ? .image(url, chapterTitle: chapterTitle) : nil
            }
        }
    }

    private static func normalizedLayout(_ layout: ReaderContainerLayout, padding: Double) -> ReaderContainerLayout {
        let width = max(180, layout.width - (padding * 2))
        let height = max(260, layout.height - 120)
        return ReaderContainerLayout(width: width, height: height)
    }

    private static func paginateText(
        _ text: String,
        width: CGFloat,
        height: CGFloat,
        settings: ReaderAppearanceSettings,
        metrics: ReaderTextMetrics
    ) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let charsPerLine = max(10, Int(width / max(metrics.characterWidth, 1)))
        let linesPerPage = max(6, Int(height / max(metrics.lineHeight, 1)))
        let charsPerPage = max(120, charsPerLine * linesPerPage)

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var pages: [String] = []
        var current = ""

        for paragraph in paragraphs {
            if paragraph.count > charsPerPage {
                if !current.isEmpty {
                    pages.append(current)
                    current = ""
                }

                var startIndex = paragraph.startIndex
                while startIndex < paragraph.endIndex {
                    let endIndex = paragraph.index(startIndex, offsetBy: charsPerPage, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    let chunk = String(paragraph[startIndex ..< endIndex]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !chunk.isEmpty {
                        pages.append(chunk)
                    }
                    startIndex = endIndex
                }
                continue
            }

            let candidate = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            if candidate.count > charsPerPage, !current.isEmpty {
                pages.append(current)
                current = paragraph
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            pages.append(current)
        }

        return pages.isEmpty ? [normalized] : pages
    }

    private static func verticalTextChunks(
        from text: String,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [String] {
        let metrics = textMetrics(settings: settings)
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return [text]
        }

        var results: [String] = []
        var current = ""
        let charsPerLine = max(10, Int(layout.width / max(metrics.characterWidth, 1)))
        let linesPerChunk = max(10, Int((layout.height * 1.8) / max(metrics.lineHeight, 1)))
        let chunkLimit = max(220, charsPerLine * linesPerChunk)

        for paragraph in paragraphs {
            let separator = current.isEmpty ? "" : "\n\n"
            if (current + separator + paragraph).count > chunkLimit {
                if !current.isEmpty {
                    results.append(current)
                    current = ""
                }
                if paragraph.count > chunkLimit {
                    var remainder = paragraph[...]
                    while remainder.count > chunkLimit {
                        let splitIndex = remainder.index(remainder.startIndex, offsetBy: chunkLimit)
                        results.append(String(remainder[..<splitIndex]))
                        remainder = remainder[splitIndex...]
                    }
                    current = String(remainder)
                } else {
                    current = paragraph
                }
            } else {
                current += separator + paragraph
            }
        }

        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    private static func textMetrics(settings: ReaderAppearanceSettings) -> ReaderTextMetrics {
        let fontSize = max(14, 22 * settings.fontScale)
        let lineHeight = max(fontSize * settings.lineHeightScale, fontSize * 1.35)
        let characterSpacing = fontSize * settings.characterSpacingScale * 0.45
        let characterWidth = fontSize * settings.fontFamily.paginationWidthFactor + characterSpacing
        return ReaderTextMetrics(
            fontSize: fontSize,
            lineHeight: lineHeight,
            characterWidth: characterWidth
        )
    }
}

private struct ReaderTextMetrics {
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let characterWidth: CGFloat
}
