import CoreGraphics
import Foundation
import YamiboReaderCore

enum NovelTextDisplaySurface: Equatable {
    case settingsPreview
    case novelReadingSessionTextBlock
}

enum NovelTextDisplayBackend: Equatable {
    case textKit2DisplayAdapter
}

enum NovelTextDisplayColor: Equatable {
    case primaryReaderText
    case settingsPreviewPrimaryText
}

struct NovelTextDisplayStyle: Equatable {
    var fontScale: Double
    var fontFamily: ReaderFontFamily
    var pointSize: Double
    var lineHeightScale: Double
    var characterSpacingScale: Double
    var indentsParagraphFirstLine: Bool
    var usesJustifiedText: Bool
    var baseFontSize: Double
    var textColor: NovelTextDisplayColor
    var includesChapterTitle: Bool
}

struct NovelTextDisplayPlan: Equatable {
    var surface: NovelTextDisplaySurface
    var backend: NovelTextDisplayBackend
    var measurementBackend: NovelTextDisplayBackend
    var text: String
    var chapterTitle: String?
    var startsAtParagraphBoundary: Bool
    var style: NovelTextDisplayStyle
}

enum NovelTextDisplayAdapter {
    static func displayPlan(
        surface: NovelTextDisplaySurface,
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double,
        textColor: NovelTextDisplayColor
    ) -> NovelTextDisplayPlan {
        NovelTextDisplayPlan(
            surface: surface,
            backend: .textKit2DisplayAdapter,
            measurementBackend: .textKit2DisplayAdapter,
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            style: NovelTextDisplayStyle(
                fontScale: settings.fontScale,
                fontFamily: settings.fontFamily,
                pointSize: baseFontSize * settings.fontScale,
                lineHeightScale: settings.lineHeightScale,
                characterSpacingScale: settings.characterSpacingScale,
                indentsParagraphFirstLine: settings.indentsParagraphFirstLine,
                usesJustifiedText: settings.usesJustifiedText,
                baseFontSize: baseFontSize,
                textColor: textColor,
                includesChapterTitle: chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
        )
    }
}

enum ReaderBlockTextDisplayPlanner {
    static func displayPlan(
        for block: ReaderRenderedBlock,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = 22
    ) -> NovelTextDisplayPlan? {
        guard case let .text(text, chapterTitle, startsAtParagraphBoundary) = block else {
            return nil
        }
        return NovelTextDisplayAdapter.displayPlan(
            surface: .novelReadingSessionTextBlock,
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize,
            textColor: .primaryReaderText
        )
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

extension NovelTextDisplayAdapter {
    static func measuredHeight(
        width: CGFloat,
        attributedText: NSAttributedString,
        displayView: NovelTextKit2DisplayUIView
    ) -> CGFloat {
        displayView.measuredHeight(width: width, attributedText: attributedText)
    }
}

struct NativeNovelTextDisplayView: UIViewRepresentable {
    let surface: NovelTextDisplaySurface
    let text: String
    let chapterTitle: String?
    var startsAtParagraphBoundary: Bool = true
    let settings: ReaderAppearanceSettings
    let baseFontSize: Double
    let textColor: UIColor
    let textColorToken: NovelTextDisplayColor
    var titleWeight: UIFont.Weight = .regular

    var displayPlan: NovelTextDisplayPlan {
        NovelTextDisplayAdapter.displayPlan(
            surface: surface,
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize,
            textColor: textColorToken
        )
    }

    func makeUIView(context: Context) -> NovelTextKit2DisplayUIView {
        let view = NovelTextKit2DisplayUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: NovelTextKit2DisplayUIView, context: Context) {
        uiView.update(attributedText: makeAttributedText())
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NovelTextKit2DisplayUIView,
        context: Context
    ) -> CGSize? {
        let targetWidth = proposal.width ?? UIScreen.main.bounds.width
        let height = NovelTextDisplayAdapter.measuredHeight(
            width: targetWidth,
            attributedText: makeAttributedText(),
            displayView: uiView
        )
        return CGSize(width: targetWidth, height: height)
    }

    private func makeAttributedText() -> NSAttributedString {
        ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
    }
}

final class NovelTextKit2DisplayUIView: UIView {
    private let textContentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var attributedText = NSAttributedString()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureTextKit2()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextKit2()
    }

    func update(attributedText: NSAttributedString) {
        guard self.attributedText != attributedText else { return }
        self.attributedText = attributedText
        textContentStorage.textStorage?.setAttributedString(attributedText)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    func measuredHeight(width: CGFloat, attributedText: NSAttributedString) -> CGFloat {
        guard width > 0, attributedText.length > 0 else { return 0 }
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textContentStorage.textStorage?.setAttributedString(attributedText)
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

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: []
        ) { fragment in
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
    }

    private func configureTextKit2() {
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
    }
}
#endif
