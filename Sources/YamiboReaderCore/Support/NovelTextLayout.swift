import CoreGraphics
import Foundation

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

typealias NovelPagedTextLayout = @Sendable (
    _ text: String,
    _ chapterTitle: String?,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) -> [TextSlice]

typealias NovelVerticalTextLayout = @Sendable (
    _ text: String,
    _ chapterTitle: String?,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) -> [TextSlice]

public enum NovelTextLayout {
    static func renderedTextSlices(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        readingMode: ReaderReadingMode
    ) -> [TextSlice] {
        (try? renderedTextSlices(
            text,
            chapterTitle: chapterTitle,
            settings: settings,
            layout: layout,
            readingMode: readingMode,
            requiresAuthoritativePagedLayout: false
        )) ?? []
    }

    static func renderedTextSlices(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        readingMode: ReaderReadingMode,
        requiresAuthoritativePagedLayout: Bool,
        requiresAuthoritativeVerticalLayout: Bool = false,
        pagedLayout: NovelPagedTextLayout? = nil,
        verticalLayout: NovelVerticalTextLayout? = nil
    ) throws -> [TextSlice] {
        switch readingMode {
        case .paged:
            return try pagedTextSlices(
                text,
                chapterTitle: chapterTitle,
                settings: settings,
                layout: layout,
                requiresAuthoritativeLayout: requiresAuthoritativePagedLayout,
                pagedLayout: pagedLayout
            )
        case .vertical:
            return try verticalTextChunks(
                text,
                chapterTitle: chapterTitle,
                settings: settings,
                layout: layout,
                requiresAuthoritativeLayout: requiresAuthoritativeVerticalLayout,
                verticalLayout: verticalLayout
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
#elseif canImport(AppKit)
        AppKitNovelTextLayoutAdapter.textFits(
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
#elseif canImport(AppKit)
        let attributedText = AppKitNovelTextLayoutAdapter.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize
        )
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
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
        layout: ReaderContainerLayout,
        requiresAuthoritativeLayout: Bool,
        pagedLayout: NovelPagedTextLayout?
    ) throws -> [TextSlice] {
#if canImport(UIKit)
        let authoritativeLayout = pagedLayout ?? ReaderPagedLayoutEngine.paginateText
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#elseif canImport(AppKit)
        let authoritativeLayout = pagedLayout ?? AppKitNovelTextLayoutAdapter.paginateText
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#else
        if let pagedLayout {
            let slices = pagedLayout(text, chapterTitle, settings, layout)
            if !slices.isEmpty {
                return slices
            }
        }
#endif
        if requiresAuthoritativeLayout {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        let metrics = textMetrics(settings: settings)
        let readableFrame = layout.readableFrame
        let charsPerLine = max(10, Int(readableFrame.width / max(metrics.characterWidth, 1)))
        let linesPerPage = max(6, Int(readableFrame.height / max(metrics.lineHeight, 1)))
        let charsPerPage = max(120, charsPerLine * linesPerPage)
        return textSlices(in: text, limit: charsPerPage)
    }

    private static func verticalTextChunks(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        requiresAuthoritativeLayout: Bool,
        verticalLayout: NovelVerticalTextLayout?
    ) throws -> [TextSlice] {
#if canImport(UIKit)
        let authoritativeLayout = verticalLayout ?? ReaderPagedLayoutEngine.verticalTextChunks
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#elseif canImport(AppKit)
        let authoritativeLayout = verticalLayout ?? AppKitNovelTextLayoutAdapter.verticalTextChunks
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#else
        if let verticalLayout {
            let slices = verticalLayout(text, chapterTitle, settings, layout)
            if !slices.isEmpty {
                return slices
            }
        }
#endif
        if requiresAuthoritativeLayout {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
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

#if canImport(AppKit) && !canImport(UIKit)
private enum AppKitNovelTextLayoutAdapter {
    private static let defaultBaseFontSize: Double = 22

    static func textFits(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> Bool {
        let pageSize = layout.readableFrame.size
        guard pageSize.width >= 120, pageSize.height >= minimumUsablePageHeight(settings: settings) else {
            return false
        }

        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(boundingRect.height) <= pageSize.height
    }

    static func paginateText(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
        let pageSize = layout.readableFrame.size
        guard pageSize.width > 0, pageSize.height > 0 else {
            return []
        }
        guard pageSize.width >= 120, pageSize.height >= minimumUsablePageHeight(settings: settings) else {
            return []
        }

        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        return paginateTextWithTextKit2(attributedText, pageSize: pageSize)
    }

    static func verticalTextChunks(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
        let readableFrame = layout.readableFrame
        let chunkSize = CGSize(width: readableFrame.width, height: readableFrame.height * 1.8)
        guard chunkSize.width > 0, chunkSize.height > 0 else {
            return []
        }
        guard chunkSize.width >= 120, readableFrame.height >= minimumUsablePageHeight(settings: settings) else {
            return []
        }

        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        return paginateTextWithTextKit2(attributedText, pageSize: chunkSize)
    }

    static func makeAttributedText(
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = defaultBaseFontSize,
        textColor: NSColor = .labelColor,
        titleWeight: NSFont.Weight = .regular
    ) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let segments = ReaderChapterTextComponents.split(text: text, chapterTitle: chapterTitle)
        let pointSize = baseFontSize * settings.fontScale
        let firstBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: startsAtParagraphBoundary
        )
        let laterBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: true
        )
        let titleParagraphStyle = makeParagraphStyle(settings: settings, pointSize: pointSize, appliesFirstLineIndent: false)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.appKitFont(size: pointSize, weight: .regular),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: firstBodyParagraphStyle,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.appKitFont(size: pointSize, weight: titleWeight),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: titleParagraphStyle,
        ]

        if let title = segments.title {
            rendered.append(NSAttributedString(string: title, attributes: titleAttributes))
            if let body = segments.body {
                appendBody(
                    body,
                    to: rendered,
                    attributes: bodyAttributes,
                    laterParagraphStyle: laterBodyParagraphStyle,
                    startsAtParagraphBoundary: startsAtParagraphBoundary
                )
            }
        } else {
            appendBody(
                text,
                to: rendered,
                attributes: bodyAttributes,
                laterParagraphStyle: laterBodyParagraphStyle,
                startsAtParagraphBoundary: startsAtParagraphBoundary
            )
        }

        return rendered
    }

    private static func paginateTextWithTextKit2(_ attributedText: NSAttributedString, pageSize: CGSize) -> [TextSlice] {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.textStorage?.setAttributedString(attributedText)

        let textContainer = NSTextContainer(size: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textLayoutManager.textContainer = textContainer

        let documentRange = textContentStorage.documentRange
        textLayoutManager.ensureLayout(for: documentRange)

        var pageRanges: [Int: NSRange] = [:]
        textLayoutManager.enumerateTextSegments(
            in: documentRange,
            type: .standard,
            options: []
        ) { textRange, rect, _, _ in
            guard let textRange,
                  let characterRange = nsRange(for: textRange, in: textContentStorage),
                  characterRange.length > 0,
                  rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite,
                  rect.height > 0 else {
                return true
            }
            let pageIndex = max(0, Int(floor(rect.midY / pageSize.height)))
            if let existingRange = pageRanges[pageIndex] {
                pageRanges[pageIndex] = existingRange.union(characterRange)
            } else {
                pageRanges[pageIndex] = characterRange
            }
            return true
        }

        if let lastPageIndex = pageRanges.keys.max(),
           let lastRange = pageRanges[lastPageIndex] {
            let textLength = attributedText.string.count
            let coveredEnd = min(lastRange.location + lastRange.length, textLength)
            if coveredEnd < textLength {
                pageRanges[lastPageIndex] = lastRange.union(
                    NSRange(location: coveredEnd, length: textLength - coveredEnd)
                )
            }
        }

        return pageRanges.keys.sorted().compactMap { pageIndex in
            guard let pageRange = pageRanges[pageIndex] else { return nil }
            return textSlice(
                from: attributedText,
                range: pageRange,
                isFirstPage: pageIndex == 0
            )
        }
    }

    private static func makeParagraphStyle(
        settings: ReaderAppearanceSettings,
        pointSize: Double,
        appliesFirstLineIndent: Bool
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6 * settings.lineHeightScale
        style.alignment = settings.usesJustifiedText ? .justified : .natural
        style.lineBreakMode = .byWordWrapping
        if settings.indentsParagraphFirstLine, appliesFirstLineIndent {
            style.firstLineHeadIndent = CGFloat(pointSize * 2)
        }
        return style
    }

    private static func appendBody(
        _ body: String,
        to rendered: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        laterParagraphStyle: NSParagraphStyle,
        startsAtParagraphBoundary: Bool
    ) {
        let bodyStartLocation = rendered.length
        rendered.append(NSAttributedString(string: body, attributes: attributes))
        guard !startsAtParagraphBoundary else { return }

        for range in ReaderParagraphIndentPlanner.indentedParagraphRangesAfterFirst(in: body) {
            let location = body.distance(from: body.startIndex, to: range.lowerBound)
            let length = body.distance(from: range.lowerBound, to: range.upperBound)
            guard length > 0 else { continue }
            rendered.addAttribute(
                .paragraphStyle,
                value: laterParagraphStyle,
                range: NSRange(location: bodyStartLocation + location, length: length)
            )
        }
    }

    private static func nsRange(for textRange: NSTextRange, in contentManager: NSTextContentManager) -> NSRange? {
        let documentStart = contentManager.documentRange.location
        let start = contentManager.offset(from: documentStart, to: textRange.location)
        let end = contentManager.offset(from: documentStart, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func textSlice(from attributedText: NSAttributedString, range: NSRange, isFirstPage: Bool) -> TextSlice? {
        let textLength = attributedText.string.count
        let pageCharacterStart = max(0, min(range.location, textLength))
        let nextCharacterEnd = min(range.location + range.length, textLength)
        let trimmedEnd = max(
            trimmedCharacterBoundary(in: attributedText.string, from: pageCharacterStart, to: nextCharacterEnd),
            pageCharacterStart
        )
        guard trimmedEnd > pageCharacterStart else { return nil }

        let candidateText = attributedText.attributedSubstring(
            from: NSRange(location: pageCharacterStart, length: trimmedEnd - pageCharacterStart)
        ).string
        guard !candidateText.isEmpty else { return nil }

        let trimmedLeadingText = candidateText.trimmingLeadingPaginationWhitespace()
        let leadingTrimmed = candidateText.count - trimmedLeadingText.count
        let effectiveStart = pageCharacterStart + leadingTrimmed
        let sliceText = effectiveStart < trimmedEnd ? attributedText.attributedSubstring(
            from: NSRange(location: effectiveStart, length: trimmedEnd - effectiveStart)
        ).string : ""
        guard !sliceText.isEmpty else { return nil }

        return TextSlice(
            text: sliceText,
            startOffset: effectiveStart,
            endOffset: trimmedEnd,
            startsAtParagraphBoundary: isFirstPage || isParagraphBoundary(in: attributedText.string, at: effectiveStart)
        )
    }

    private static func trimmedCharacterBoundary(in text: String, from start: Int, to candidateEnd: Int) -> Int {
        guard candidateEnd > start else { return start }
        let nsText = text as NSString
        var end = candidateEnd
        while end > start {
            let character = nsText.substring(with: NSRange(location: end - 1, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end -= 1
                continue
            }
            break
        }
        return max(end, start)
    }

    private static func minimumUsablePageHeight(settings: ReaderAppearanceSettings) -> CGFloat {
        let fontSize = max(14, defaultBaseFontSize * settings.fontScale)
        return CGFloat(fontSize * max(settings.lineHeightScale, 1.35) * 2)
    }

    private static func isParagraphBoundary(in text: String, at offset: Int) -> Bool {
        guard offset > 0, offset <= text.count else { return false }
        let nsText = text as NSString
        var index = offset - 1
        var newlineCount = 0

        while index >= 0 {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "\n" || character == "\r" {
                newlineCount += 1
                if newlineCount >= 2 {
                    return true
                }
            } else if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index -= 1
                continue
            } else {
                return false
            }
            index -= 1
        }

        return false
    }
}

private extension ReaderFontFamily {
    func appKitFont(size: Double, weight: NSFont.Weight) -> NSFont {
        let pointSize = CGFloat(size)
        switch self {
        case .systemSans:
            return preferredFamilyFont(familyName: "PingFang SC", size: pointSize, weight: weight)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .systemSerif:
            return preferredFamilyFont(familyName: "Songti SC", size: pointSize, weight: weight)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .rounded:
            let descriptor = NSFont.systemFont(ofSize: pointSize, weight: weight).fontDescriptor
            let roundedDescriptor = descriptor.withDesign(.rounded) ?? descriptor
            return NSFont(descriptor: roundedDescriptor, size: pointSize) ?? .systemFont(ofSize: pointSize, weight: weight)
        }
    }

    func kerning(size: Double, scale: Double) -> CGFloat {
        CGFloat(size * scale * 0.55)
    }

    private func preferredFamilyFont(familyName: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let fontManager = NSFontManager.shared
        return fontManager.font(
            withFamily: familyName,
            traits: [],
            weight: fontManagerWeight(for: weight),
            size: size
        )
    }

    private func fontManagerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: 2
        case .thin: 3
        case .light: 4
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 10
        case .black: 12
        default: 5
        }
    }
}

private extension String {
    func trimmingLeadingPaginationWhitespace() -> String {
        guard !isEmpty else { return self }
        var result = self[...]
        while let first = result.first, first.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            result.removeFirst()
        }
        return String(result)
    }
}
#endif

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
