import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit

enum ReaderPagedLayoutEngine {
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
        let height = measuredTextHeight(
            text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: true,
            settings: settings,
            width: pageSize.width,
            baseFontSize: ReaderAttributedTextFactory.defaultBaseFontSize
        )
        return height > 0 && height <= pageSize.height
    }

    static func measuredTextHeight(
        _ text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool,
        settings: ReaderAppearanceSettings,
        width: CGFloat,
        baseFontSize: Double
    ) -> CGFloat {
        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize
        )
        guard width > 0, attributedText.length > 0 else { return 0 }
        return measuredTextHeightWithTextKit2(attributedText, width: width)
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

        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
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

        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        return paginateTextWithTextKit2(attributedText, pageSize: chunkSize)
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

        return pageRanges.keys.sorted().compactMap { pageIndex in
            guard let pageRange = pageRanges[pageIndex] else { return nil }
            return textSlice(
                from: attributedText,
                range: pageRange,
                isFirstPage: pageIndex == 0
            )
        }
    }

    private static func measuredTextHeightWithTextKit2(_ attributedText: NSAttributedString, width: CGFloat) -> CGFloat {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.textStorage?.setAttributedString(attributedText)

        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textLayoutManager.textContainer = textContainer

        textLayoutManager.ensureLayout(for: textContentStorage.documentRange)

        var maxY: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: []
        ) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return ceil(maxY)
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
        let fontSize = max(14, ReaderAttributedTextFactory.defaultBaseFontSize * settings.fontScale)
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
