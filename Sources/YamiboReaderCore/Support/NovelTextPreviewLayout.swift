import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit) || canImport(AppKit)
enum NovelTextPreviewLayout {
    static func textFits(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> Bool {
        let pageSize = layout.readableFrame.size
        guard pageSize.width >= 120,
              pageSize.height >= minimumUsablePageHeight(settings: settings) else {
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

        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(attributedText)

        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.textContainer = textContainer
        layoutManager.ensureLayout(for: contentStorage.documentRange)

        var maxY: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: contentStorage.documentRange.location,
            options: []
        ) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return ceil(maxY)
    }

    private static func minimumUsablePageHeight(
        settings: ReaderAppearanceSettings
    ) -> CGFloat {
        let fontSize = max(
            14,
            ReaderAttributedTextFactory.defaultBaseFontSize * settings.fontScale
        )
        return CGFloat(fontSize * max(settings.lineHeightScale, 1.35) * 2)
    }
}
#endif
