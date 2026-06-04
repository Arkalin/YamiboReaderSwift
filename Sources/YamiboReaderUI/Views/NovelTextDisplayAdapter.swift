import CoreGraphics
import Foundation
import YamiboReaderCore

enum NovelTextDisplaySurface: Equatable {
    case settingsPreview
    case novelReadingSessionTextBlock
}

enum NovelTextDisplayBackend: Equatable {
    case novelTextViewport
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
            backend: .novelTextViewport,
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

    func makeUIView(context: Context) -> NovelTextViewportDisplayUIView {
        let view = NovelTextViewportDisplayUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: NovelTextViewportDisplayUIView, context: Context) {
        uiView.update(attributedText: NovelTextKit2PlatformAdapter.makeAttributedText(
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        ))
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: NovelTextViewportDisplayUIView,
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

final class NovelTextViewportDisplayUIView: UIView, @MainActor NSTextViewportLayoutControllerDelegate {
    private let textContentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var attributedText = NSAttributedString()
    private var lastLaidOutBoundsSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureTextKit2()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextKit2()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let didUpdateContainerSize = updateTextContainerSizeForCurrentBounds()
        guard didUpdateContainerSize else { return }
        textLayoutManager.textViewportLayoutController.layoutViewport()
        setNeedsDisplay()
    }

    func update(attributedText: NSAttributedString) {
        guard self.attributedText != attributedText else { return }
        self.attributedText = attributedText
        updateTextContainerSizeForCurrentBounds()
        textContentStorage.textStorage?.setAttributedString(attributedText)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    func prepareForDisplay(size: CGSize) {
        if bounds.size != size {
            bounds = CGRect(origin: .zero, size: size)
        }
        updateTextContainerSizeForCurrentBounds()
        textLayoutManager.textViewportLayoutController.layoutViewport()
        setNeedsDisplay()
    }

    func closestTextOffset(to point: CGPoint) -> Int? {
        guard bounds.width > 0, attributedText.length > 0 else { return nil }
        updateTextContainerSizeForCurrentBounds()
        textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
        let documentStart = textContentStorage.documentRange.location
        var best: (distance: CGFloat, offset: Int)?

        textLayoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            options: []
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let distance = Self.distance(from: point, to: frame)
            let range = fragment.rangeInElement
            let rangeStart = textContentStorage.offset(from: documentStart, to: range.location)
            let rangeEnd = textContentStorage.offset(from: documentStart, to: range.endLocation)
            guard rangeStart != NSNotFound, rangeEnd != NSNotFound, rangeEnd >= rangeStart else {
                return true
            }

            let progress: CGFloat = if frame.height > 0 {
                min(max((point.y - frame.minY) / frame.height, 0), 1)
            } else {
                0
            }
            let fragmentLength = max(rangeEnd - rangeStart, 0)
            let offset = rangeStart + min(max(Int((CGFloat(fragmentLength) * progress).rounded(.towardZero)), 0), fragmentLength)
            if best == nil || distance < best!.distance {
                best = (distance, offset)
            }
            return true
        }

        return best?.offset
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        updateTextContainerSizeForCurrentBounds()
        textLayoutManager.textViewportLayoutController.layoutViewport()
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: []
        ) { fragment in
            guard fragment.layoutFragmentFrame.intersects(bounds) else {
                return true
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
    }

    func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        bounds
    }

    func textViewportLayoutController(
        _ textViewportLayoutController: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {}

    private func configureTextKit2() {
        contentMode = .redraw
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textLayoutManager.textViewportLayoutController.delegate = self
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return 0
        }
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }
        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }
        return hypot(dx, dy)
    }

    @discardableResult
    private func updateTextContainerSizeForCurrentBounds() -> Bool {
        let nextSize = CGSize(width: bounds.width, height: max(bounds.height, 1))
        guard nextSize != lastLaidOutBoundsSize || textContainer.size != nextSize else {
            return false
        }
        lastLaidOutBoundsSize = nextSize
        textContainer.size = nextSize
        return true
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
