import Foundation
import CoreGraphics

public enum ReaderPaginator {
    public static func paginate(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> ReaderPaginationResult {
        let annotatedSegments = annotatedSegments(from: document.segments, settings: settings)

        switch settings.readingMode {
        case .paged:
            return paginate(
                annotatedSegments: annotatedSegments,
                documentView: document.view,
                settings: settings,
                layout: layout,
                chunker: { annotatedSegment, settings, layout in
                    paginateText(
                        annotatedSegment.textContent,
                        chapterTitle: annotatedSegment.chapterTitle,
                        settings: settings,
                        layout: layout
                    )
                }
            )
        case .vertical:
            return paginate(
                annotatedSegments: annotatedSegments,
                documentView: document.view,
                settings: settings,
                layout: layout,
                chunker: { annotatedSegment, settings, layout in
                    verticalTextChunks(
                        from: annotatedSegment.textContent,
                        settings: settings,
                        layout: layout
                    )
                }
            )
        }
    }

    private static func paginate(
        annotatedSegments: [AnnotatedSegment],
        documentView: Int,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        chunker: (AnnotatedSegment, ReaderAppearanceSettings, ReaderContainerLayout) -> [TextSlice]
    ) -> ReaderPaginationResult {
        var pages: [ReaderRenderedPage] = []
        var chapters: [ReaderChapter] = []
        var seenChapterOrdinals = Set<Int>()

        for annotatedSegment in annotatedSegments {
            switch annotatedSegment.segment {
            case let .text(text, chapterTitle):
                let slices = chunker(annotatedSegment, settings, layout)
                for slice in slices where !slice.text.isEmpty {
                    if settings.readingMode == .paged,
                       appendTextSliceToPreviousPageIfPossible(
                           slice,
                           chapterTitle: chapterTitle,
                           annotatedSegment: annotatedSegment,
                           settings: settings,
                           layout: layout,
                           pages: &pages
                       ) {
                        continue
                    }

                    let page = ReaderRenderedPage(
                        index: pages.count,
                        blocks: [.text(slice.text, chapterTitle: chapterTitle)],
                        documentView: documentView,
                        chapterOrdinal: annotatedSegment.chapterOrdinal,
                        chapterTitle: annotatedSegment.chapterTitle,
                        segmentIndex: annotatedSegment.index,
                        segmentStartOffset: slice.startOffset,
                        segmentEndOffset: slice.endOffset,
                        textRanges: [
                            ReaderRenderedTextRange(
                                segmentIndex: annotatedSegment.index,
                                startOffset: slice.startOffset,
                                endOffset: slice.endOffset
                            )
                        ]
                    )
                    if let chapterOrdinal = annotatedSegment.chapterOrdinal,
                       let chapterTitle = annotatedSegment.chapterTitle,
                       seenChapterOrdinals.insert(chapterOrdinal).inserted {
                        chapters.append(
                            ReaderChapter(
                                ordinal: chapterOrdinal,
                                title: chapterTitle,
                                startIndex: page.index
                            )
                        )
                    }
                    pages.append(page)
                }

                if pages.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pages.append(
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [.text(text, chapterTitle: chapterTitle)],
                            documentView: documentView,
                            chapterOrdinal: annotatedSegment.chapterOrdinal,
                            chapterTitle: annotatedSegment.chapterTitle,
                            segmentIndex: annotatedSegment.index,
                            segmentStartOffset: 0,
                            segmentEndOffset: text.count,
                            textRanges: [
                                ReaderRenderedTextRange(
                                    segmentIndex: annotatedSegment.index,
                                    startOffset: 0,
                                    endOffset: text.count
                                )
                            ]
                        )
                    )
                }
            case let .image(url, chapterTitle):
                let page = ReaderRenderedPage(
                    index: pages.count,
                    blocks: [.image(url, chapterTitle: chapterTitle)],
                    documentView: documentView,
                    chapterOrdinal: annotatedSegment.chapterOrdinal,
                    chapterTitle: annotatedSegment.chapterTitle,
                    segmentIndex: annotatedSegment.index,
                    segmentStartOffset: 0,
                    segmentEndOffset: 0
                )
                if let chapterOrdinal = annotatedSegment.chapterOrdinal,
                   let chapterTitle = annotatedSegment.chapterTitle,
                   seenChapterOrdinals.insert(chapterOrdinal).inserted {
                    chapters.append(
                        ReaderChapter(
                            ordinal: chapterOrdinal,
                            title: chapterTitle,
                            startIndex: page.index
                        )
                    )
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages = [ReaderRenderedPage(index: 0, blocks: [.footer(L10n.string("reader.empty_content"))], documentView: documentView)]
        }

        return ReaderPaginationResult(pages: pages, chapters: chapters)
    }

    private static func appendTextSliceToPreviousPageIfPossible(
        _ slice: TextSlice,
        chapterTitle: String?,
        annotatedSegment: AnnotatedSegment,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        pages: inout [ReaderRenderedPage]
    ) -> Bool {
        guard !pages.isEmpty else { return false }
        let previousIndex = pages.count - 1
        var previousPage = pages[previousIndex]
        guard previousPage.documentView > 0,
              previousPage.chapterOrdinal == annotatedSegment.chapterOrdinal,
              previousPage.chapterTitle == annotatedSegment.chapterTitle,
              previousPage.blocks.allSatisfy(\.isTextBlock) else {
            return false
        }

        let combinedText = (previousPage.blocks.compactMap(\.textContent) + [slice.text])
            .joined(separator: "\n\n")

#if canImport(UIKit)
        guard ReaderPagedLayoutEngine.textFits(
            combinedText,
            chapterTitle: previousPage.chapterTitle,
            settings: settings,
            layout: layout
        ) else {
            return false
        }
#else
        guard combinedText.count < 180 else { return false }
#endif

        previousPage.blocks.append(.text(slice.text, chapterTitle: chapterTitle))
        previousPage.textRanges.append(
            ReaderRenderedTextRange(
                segmentIndex: annotatedSegment.index,
                startOffset: slice.startOffset,
                endOffset: slice.endOffset
            )
        )
        previousPage.segmentEndOffset = max(previousPage.segmentEndOffset, slice.endOffset)
        pages[previousIndex] = previousPage
        return true
    }

    private static func annotatedSegments(
        from segments: [ReaderSegment],
        settings: ReaderAppearanceSettings
    ) -> [AnnotatedSegment] {
        let transformedSegments = transformedSegments(from: segments, settings: settings)
        var results: [AnnotatedSegment] = []
        var currentChapterTitle: String?
        var currentChapterOrdinal: Int?
        var nextChapterOrdinal = 0

        for (index, segment) in transformedSegments.enumerated() {
            let explicitChapterTitle = segment.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let explicitChapterTitle, !explicitChapterTitle.isEmpty {
                if currentChapterTitle != explicitChapterTitle {
                    currentChapterTitle = explicitChapterTitle
                    currentChapterOrdinal = nextChapterOrdinal
                    nextChapterOrdinal += 1
                }
            }

            results.append(
                AnnotatedSegment(
                    index: index,
                    segment: segment,
                    chapterOrdinal: currentChapterOrdinal,
                    chapterTitle: currentChapterTitle
                )
            )
        }

        return results
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

    private static func paginateText(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
#if canImport(UIKit)
        let slices = ReaderPagedLayoutEngine.paginateText(
            text,
            chapterTitle: chapterTitle,
            settings: settings,
            layout: layout
        )
        if !slices.isEmpty {
            return slices
        }
#endif
        let metrics = textMetrics(settings: settings)
        let readableFrame = layout.readableFrame
        let charsPerLine = max(10, Int(readableFrame.width / max(metrics.characterWidth, 1)))
        let linesPerPage = max(6, Int(readableFrame.height / max(metrics.lineHeight, 1)))
        let charsPerPage = max(120, charsPerLine * linesPerPage)
        return textSlices(in: text, limit: charsPerPage)
    }

    private static func verticalTextChunks(
        from text: String,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
        let metrics = textMetrics(settings: settings)
        let readableFrame = layout.readableFrame
        let charsPerLine = max(10, Int(readableFrame.width / max(metrics.characterWidth, 1)))
        let linesPerChunk = max(10, Int((readableFrame.height * 1.8) / max(metrics.lineHeight, 1)))
        let chunkLimit = max(220, charsPerLine * linesPerChunk)
        return textSlices(in: text, limit: chunkLimit)
    }

    private static func textSlices(in text: String, limit: Int) -> [TextSlice] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let paragraphs = paragraphSlices(in: normalized)
        guard !paragraphs.isEmpty else {
            return [TextSlice(text: normalized, startOffset: 0, endOffset: normalized.count)]
        }

        var results: [TextSlice] = []
        var currentText = ""
        var currentStartOffset: Int?
        var currentEndOffset = 0

        func flushCurrent() {
            guard let currentStartOffset, !currentText.isEmpty else { return }
            results.append(
                TextSlice(
                    text: currentText,
                    startOffset: currentStartOffset,
                    endOffset: currentEndOffset
                )
            )
            currentText = ""
            selfResetCurrent()
        }

        func selfResetCurrent() {
            currentStartOffset = nil
            currentEndOffset = 0
        }

        for paragraph in paragraphs {
            if paragraph.text.count > limit {
                flushCurrent()
                for slice in longParagraphSlices(paragraph, limit: limit) {
                    results.append(slice)
                }
                continue
            }

            let separator = currentText.isEmpty ? "" : "\n\n"
            let candidateCount = currentText.count + separator.count + paragraph.text.count
            if candidateCount > limit, !currentText.isEmpty {
                flushCurrent()
            }

            if currentStartOffset == nil {
                currentStartOffset = paragraph.startOffset
            }
            currentText += (currentText.isEmpty ? "" : "\n\n") + paragraph.text
            currentEndOffset = paragraph.endOffset
        }

        flushCurrent()
        return results.isEmpty
            ? [TextSlice(text: normalized, startOffset: 0, endOffset: normalized.count)]
            : results
    }

    private static func paragraphSlices(in normalizedText: String) -> [ParagraphSlice] {
        let paragraphs = normalizedText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var searchStart = normalizedText.startIndex
        var slices: [ParagraphSlice] = []

        for paragraph in paragraphs {
            guard let range = normalizedText.range(of: paragraph, range: searchStart ..< normalizedText.endIndex) else {
                continue
            }
            let startOffset = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
            let endOffset = normalizedText.distance(from: normalizedText.startIndex, to: range.upperBound)
            slices.append(
                ParagraphSlice(
                    text: paragraph,
                    startOffset: startOffset,
                    endOffset: endOffset
                )
            )
            searchStart = range.upperBound
        }

        return slices
    }

    private static func longParagraphSlices(_ paragraph: ParagraphSlice, limit: Int) -> [TextSlice] {
        let characters = Array(paragraph.text)
        guard !characters.isEmpty else { return [] }

        var results: [TextSlice] = []
        var start = 0

        while start < characters.count {
            let end = min(start + limit, characters.count)
            let chunk = String(characters[start ..< end])
            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedChunk.isEmpty {
                let leadingTrimCount = chunk.prefix { $0.isWhitespaceOrNewline }.count
                let trailingTrimCount = chunk.reversed().prefix { $0.isWhitespaceOrNewline }.count
                let sliceStart = paragraph.startOffset + start + leadingTrimCount
                let sliceEnd = paragraph.startOffset + end - trailingTrimCount
                results.append(
                    TextSlice(
                        text: trimmedChunk,
                        startOffset: max(paragraph.startOffset, sliceStart),
                        endOffset: max(max(paragraph.startOffset, sliceStart), sliceEnd)
                    )
                )
            }
            start = end
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

private struct AnnotatedSegment {
    let index: Int
    let segment: ReaderSegment
    let chapterOrdinal: Int?
    let chapterTitle: String?

    var textContent: String {
        guard case let .text(text, _) = segment else { return "" }
        return text
    }
}

struct TextSlice {
    let text: String
    let startOffset: Int
    let endOffset: Int
}

private struct ParagraphSlice {
    let text: String
    let startOffset: Int
    let endOffset: Int
}

private extension Character {
    var isWhitespaceOrNewline: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
