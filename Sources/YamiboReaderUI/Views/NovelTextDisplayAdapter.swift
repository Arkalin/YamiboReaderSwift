import CoreGraphics
import Foundation
import YamiboReaderCore

enum NovelTextDisplaySurface: Equatable {
    case settingsPreview
    case novelReadingSessionTextBlock
}

enum NovelTextDisplayBackend: Equatable {
    case textKit2DisplayAdapter
    case novelTextLayoutMeasurement
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

struct NovelTextDisplayMaterialization: Equatable {
    var surface: NovelTextDisplaySurface
    var backend: NovelTextDisplayBackend
    var measurementBackend: NovelTextDisplayBackend
    var text: String
    var chapterTitle: String?
    var startsAtParagraphBoundary: Bool
    var style: NovelTextDisplayStyle
}

enum NovelTextDisplayAdapter {
    static func materialization(
        surface: NovelTextDisplaySurface,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: NovelTextDisplayColor
    ) -> NovelTextDisplayMaterialization {
        let semantics = displayValue.semantics
        return NovelTextDisplayMaterialization(
            surface: surface,
            backend: .textKit2DisplayAdapter,
            measurementBackend: .novelTextLayoutMeasurement,
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

enum ReaderBlockNovelTextDisplayMaterializer {
    static func materialization(
        for block: ReaderRenderedBlock,
        settings _: ReaderAppearanceSettings,
        baseFontSize: Double = 22
    ) -> NovelTextDisplayMaterialization? {
        guard let displayValue = block.novelTextDisplayValue else {
            return nil
        }
        return NovelTextDisplayAdapter.materialization(
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
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double
    ) throws -> CGFloat {
        try NovelTextLayout.measuredTextHeight(
            displayValue: displayValue,
            width: width,
            baseFontSize: baseFontSize
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

    var materialization: NovelTextDisplayMaterialization {
        NovelTextDisplayAdapter.materialization(
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
        uiView.update(attributedText: NovelTextKit2PlatformAdapter.makeAttributedText(
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        ))
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NovelTextKit2DisplayUIView,
        context: Context
    ) -> CGSize? {
        let targetWidth = proposal.width ?? UIScreen.main.bounds.width
        guard let height = try? NovelTextDisplayAdapter.measuredHeight(
            width: targetWidth,
            displayValue: displayValue,
            baseFontSize: baseFontSize
        ) else {
            return nil
        }
        return CGSize(width: targetWidth, height: height)
    }
}

enum NovelTextKit2PlatformAdapter {
    static func makeAttributedText(
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: UIColor,
        titleWeight: UIFont.Weight
    ) -> NSAttributedString {
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
