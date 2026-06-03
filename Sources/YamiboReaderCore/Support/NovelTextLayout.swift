import CoreGraphics
import Foundation

public enum NovelTextLayout {
    static func renderedTextSlices(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        readingMode: ReaderReadingMode
    ) -> [TextSlice] {
        switch readingMode {
        case .paged:
            return pagedTextSlices(
                text,
                chapterTitle: chapterTitle,
                settings: settings,
                layout: layout
            )
        case .vertical:
            return verticalTextChunks(
                from: text,
                settings: settings,
                layout: layout
            )
        }
    }

    static func textFits(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> Bool {
#if canImport(UIKit)
        ReaderPagedLayoutEngine.textFits(
            text,
            chapterTitle: chapterTitle,
            settings: settings,
            layout: layout
        )
#else
        text.count < 180
#endif
    }

    public static func measuredTextHeight(
        _ text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        width: CGFloat,
        baseFontSize: Double = 22
    ) -> CGFloat {
        guard width > 0 else { return 0 }
#if canImport(UIKit)
        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize
        )
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(boundingRect.height)
#else
        let metrics = textMetrics(settings: settings, baseFontSize: baseFontSize)
        let charsPerLine = max(1, Int(width / max(metrics.characterWidth, 1)))
        let lineCount = max(1, Int(ceil(Double(text.count) / Double(charsPerLine))))
        return ceil(CGFloat(lineCount) * metrics.lineHeight)
#endif
    }

    private static func pagedTextSlices(
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
                    endOffset: currentEndOffset,
                    startsAtParagraphBoundary: true
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
                        endOffset: max(max(paragraph.startOffset, sliceStart), sliceEnd),
                        startsAtParagraphBoundary: start == 0
                    )
                )
            }
            start = end
        }

        return results
    }

    private static func textMetrics(
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = 22
    ) -> ReaderTextMetrics {
        let fontSize = max(14, baseFontSize * settings.fontScale)
        let lineHeight = max(fontSize * settings.lineHeightScale, fontSize * 1.35)
        let characterSpacing = fontSize * settings.characterSpacingScale * 0.45
        let characterWidth = fontSize * settings.fontFamily.paginationWidthFactor + characterSpacing
        return ReaderTextMetrics(
            fontSize: CGFloat(fontSize),
            lineHeight: CGFloat(lineHeight),
            characterWidth: CGFloat(characterWidth)
        )
    }
}

private struct ReaderTextMetrics {
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let characterWidth: CGFloat
}

struct TextSlice {
    let text: String
    let startOffset: Int
    let endOffset: Int
    let startsAtParagraphBoundary: Bool

    init(
        text: String,
        startOffset: Int,
        endOffset: Int,
        startsAtParagraphBoundary: Bool = true
    ) {
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.startsAtParagraphBoundary = startsAtParagraphBoundary
    }
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
