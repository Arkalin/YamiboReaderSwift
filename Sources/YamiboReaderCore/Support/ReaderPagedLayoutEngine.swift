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
        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
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

        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        var slices: [TextSlice] = []
        var previousCharacterEnd = 0
        let textLength = attributedText.string.count

        while previousCharacterEnd < textLength || slices.isEmpty {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            container.lineBreakMode = .byWordWrapping
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let pageCharacterStart = max(previousCharacterEnd, min(characterRange.location, textLength))
            let nextCharacterEnd = min(characterRange.location + characterRange.length, textLength)
            let trimmedEnd = max(
                trimmedCharacterBoundary(in: attributedText.string, from: pageCharacterStart, to: nextCharacterEnd),
                pageCharacterStart
            )

            if trimmedEnd > pageCharacterStart {
                let candidateText = attributedText.attributedSubstring(
                    from: NSRange(location: pageCharacterStart, length: trimmedEnd - pageCharacterStart)
                ).string
                if !candidateText.isEmpty {
                    let trimmedLeadingText = candidateText.trimmingLeadingPaginationWhitespace()
                    let leadingTrimmed = candidateText.count - trimmedLeadingText.count
                    let effectiveStart = pageCharacterStart + leadingTrimmed
                    let sliceText = effectiveStart < trimmedEnd ? attributedText.attributedSubstring(
                        from: NSRange(location: effectiveStart, length: trimmedEnd - effectiveStart)
                    ).string : ""
                    guard !sliceText.isEmpty else {
                        previousCharacterEnd = max(nextCharacterEnd, previousCharacterEnd + 1)
                        continue
                    }
                    slices.append(
                        TextSlice(
                            text: sliceText,
                            startOffset: effectiveStart,
                            endOffset: trimmedEnd
                        )
                    )
                }
            }

            previousCharacterEnd = max(nextCharacterEnd, previousCharacterEnd + 1)
            if nextCharacterEnd >= textLength {
                break
            }
        }

        return slices
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
