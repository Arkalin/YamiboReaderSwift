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

    static func displayPlan(
        surface: NovelTextDisplaySurface,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: NovelTextDisplayColor
    ) -> NovelTextDisplayPlan {
        let semantics = displayValue.semantics
        return NovelTextDisplayPlan(
            surface: surface,
            backend: .textKit2DisplayAdapter,
            measurementBackend: .textKit2DisplayAdapter,
            text: displayValue.text,
            chapterTitle: displayValue.chapterTitle,
            startsAtParagraphBoundary: displayValue.startsAtParagraphBoundary,
            style: NovelTextDisplayStyle(
                fontScale: semantics.fontScale,
                fontFamily: semantics.fontFamily,
                pointSize: baseFontSize * semantics.fontScale,
                lineHeightScale: semantics.lineHeightScale,
                characterSpacingScale: semantics.characterSpacingScale,
                indentsParagraphFirstLine: semantics.indentsParagraphFirstLine,
                usesJustifiedText: semantics.usesJustifiedText,
                baseFontSize: baseFontSize,
                textColor: textColor,
                includesChapterTitle: displayValue.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
        )
    }
}

enum ReaderBlockTextDisplayPlanner {
    static func displayPlan(
        for block: ReaderRenderedBlock,
        settings _: ReaderAppearanceSettings,
        baseFontSize: Double = 22
    ) -> NovelTextDisplayPlan? {
        guard let displayValue = block.novelTextDisplayValue else {
            return nil
        }
        return NovelTextDisplayAdapter.displayPlan(
            surface: .novelReadingSessionTextBlock,
            displayValue: displayValue,
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
        displayView: NovelTextKit2DisplayUIView,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: UIColor,
        titleWeight: UIFont.Weight
    ) -> CGFloat {
        displayView.measuredHeight(
            width: width,
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
    }
}

struct NativeNovelTextDisplayView: UIViewRepresentable {
    let surface: NovelTextDisplaySurface
    let displayValue: NovelTextDisplayValue
    let baseFontSize: Double
    let textColor: UIColor
    let textColorToken: NovelTextDisplayColor
    var titleWeight: UIFont.Weight = .regular

    init(
        surface: NovelTextDisplaySurface,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: UIColor,
        textColorToken: NovelTextDisplayColor,
        titleWeight: UIFont.Weight = .regular
    ) {
        self.surface = surface
        self.displayValue = displayValue
        self.baseFontSize = baseFontSize
        self.textColor = textColor
        self.textColorToken = textColorToken
        self.titleWeight = titleWeight
    }

    init(
        surface: NovelTextDisplaySurface,
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double,
        textColor: UIColor,
        textColorToken: NovelTextDisplayColor,
        titleWeight: UIFont.Weight = .regular
    ) {
        self.init(
            surface: surface,
            displayValue: NovelTextDisplayValue(
                text: text,
                chapterTitle: chapterTitle,
                startsAtParagraphBoundary: startsAtParagraphBoundary,
                settings: settings
            ),
            baseFontSize: baseFontSize,
            textColor: textColor,
            textColorToken: textColorToken,
            titleWeight: titleWeight
        )
    }

    var displayPlan: NovelTextDisplayPlan {
        NovelTextDisplayAdapter.displayPlan(
            surface: surface,
            displayValue: displayValue,
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
            displayView: uiView,
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
        return CGSize(width: targetWidth, height: height)
    }

    private func makeAttributedText() -> NSAttributedString {
        ReaderAttributedTextFactory.makeAttributedText(
            text: displayValue.text,
            chapterTitle: displayValue.chapterTitle,
            startsAtParagraphBoundary: displayValue.startsAtParagraphBoundary,
            settings: ReaderAppearanceSettings(displaySemantics: displayValue.semantics),
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

    func measuredHeight(
        width: CGFloat,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: UIColor,
        titleWeight: UIFont.Weight
    ) -> CGFloat {
        let attributedText = ReaderAttributedTextFactory.makeAttributedText(
            text: displayValue.text,
            chapterTitle: displayValue.chapterTitle,
            startsAtParagraphBoundary: displayValue.startsAtParagraphBoundary,
            settings: ReaderAppearanceSettings(displaySemantics: displayValue.semantics),
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
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

private extension ReaderAppearanceSettings {
    init(displaySemantics: NovelTextDisplaySemantics) {
        self.init(
            fontScale: displaySemantics.fontScale,
            fontFamily: displaySemantics.fontFamily,
            lineHeightScale: displaySemantics.lineHeightScale,
            characterSpacingScale: displaySemantics.characterSpacingScale,
            usesJustifiedText: displaySemantics.usesJustifiedText,
            indentsParagraphFirstLine: displaySemantics.indentsParagraphFirstLine
        )
    }
}
#endif
