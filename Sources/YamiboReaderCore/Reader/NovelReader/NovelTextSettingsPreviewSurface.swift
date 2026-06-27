import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit

package final class NovelTextSettingsPreviewSurface {
    private let attributedText: NSAttributedString

    package init(
        text: String,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = ReaderAttributedTextFactory.defaultBaseFontSize,
        textColor: ReaderPlatformColor? = nil
    ) {
        attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: nil,
            startsAtParagraphBoundary: true,
            settings: settings,
            baseFontSize: baseFontSize,
            textColor: textColor
        )
    }

    package func diagnosticParagraphStyle(at location: Int) -> NSParagraphStyle? {
        guard location >= 0, location < attributedText.length else { return nil }
        return attributedText.attribute(
            .paragraphStyle,
            at: location,
            effectiveRange: nil
        ) as? NSParagraphStyle
    }

    package func draw(in context: CGContext, bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0, attributedText.length > 0 else {
            return
        }

        context.saveGState()
        context.clip(to: bounds)
        attributedText.draw(
            with: bounds,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        context.restoreGState()
    }
}
#endif
