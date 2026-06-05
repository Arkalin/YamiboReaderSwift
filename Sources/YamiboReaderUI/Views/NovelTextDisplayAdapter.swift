import CoreGraphics
import Foundation
@_spi(NovelTextAttributedDocument) import YamiboReaderCore

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

#if canImport(UIKit)
import SwiftUI
import UIKit

extension NovelTextDisplayAdapter {
    static func measuredHeight(
        width: CGFloat,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double
    ) throws -> CGFloat {
        try NovelTextLayout.measuredDisplayHeight(
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
        NovelTextLayout.makeDisplayView()
    }

    func updateUIView(_ uiView: NovelTextViewportDisplayUIView, context: Context) {
        NovelTextLayout.updateDisplayView(
            uiView,
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
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

extension NovelTextLayout {
    static func measuredDisplayHeight(
        displayValue: NovelTextDisplayValue,
        width: CGFloat,
        baseFontSize: Double
    ) throws -> CGFloat {
        try measuredTextHeight(
            displayValue: displayValue,
            width: width,
            baseFontSize: baseFontSize
        )
    }

    @MainActor
    static func makeDisplayView() -> NovelTextViewportDisplayUIView {
        let view = NovelTextViewportDisplayUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    @MainActor
    static func updateDisplayView(
        _ displayView: NovelTextViewportDisplayUIView,
        displayValue: NovelTextDisplayValue,
        baseFontSize: Double,
        textColor: UIColor,
        titleWeight: UIFont.Weight
    ) {
        displayView.update(attributedText: makeAttributedText(
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        ))
    }

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

@MainActor
final class NovelTextLayoutLiveSurfaceStore {
    private var textSurfaces: [NovelTextLayoutLiveSurfaceIdentity: NovelTextLayoutLiveSurface] = [:]
    private var surfaceAccessOrder: [NovelTextLayoutLiveSurfaceIdentity] = []
    private let surfaceCapacity = 48

    func measuredHeight(
        displayValue: NovelTextDisplayValue,
        width: CGFloat,
        baseFontSize: Double
    ) throws -> CGFloat {
        try NovelTextDisplayAdapter.measuredHeight(
            width: width,
            displayValue: displayValue,
            baseFontSize: baseFontSize
        )
    }

    func textSurface(
        identity: NovelTextLayoutLiveSurfaceIdentity,
        displayValue: NovelTextDisplayValue,
        width: CGFloat,
        baseFontSize: Double,
        textColor: UIColor,
        titleWeight: UIFont.Weight = .regular,
        fallbackHeight: CGFloat
    ) -> NovelTextLayoutLiveSurface {
        if let cachedSurface = textSurfaces[identity] {
            markRecentlyUsed(identity)
            cachedSurface.prepareForDisplay(size: CGSize(width: width, height: cachedSurface.height))
            return cachedSurface
        }

        let height = (try? measuredHeight(
            displayValue: displayValue,
            width: width,
            baseFontSize: baseFontSize
        )) ?? fallbackHeight
        let displayView = NovelTextLayout.makeDisplayView()
        displayView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        NovelTextLayout.updateDisplayView(
            displayView,
            displayValue: displayValue,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
        let surface = NovelTextLayoutLiveSurface(
            identity: identity,
            displayValue: displayValue,
            displayView: displayView,
            height: height
        )
        surface.prepareForDisplay(size: CGSize(width: width, height: height))
        textSurfaces[identity] = surface
        markRecentlyUsed(identity)
        trimSurfacesIfNeeded()
        return surface
    }

    func removeAllTextSurfaces() {
        textSurfaces.removeAll()
        surfaceAccessOrder.removeAll()
    }

    private func markRecentlyUsed(_ identity: NovelTextLayoutLiveSurfaceIdentity) {
        surfaceAccessOrder.removeAll { $0 == identity }
        surfaceAccessOrder.append(identity)
    }

    private func trimSurfacesIfNeeded() {
        while textSurfaces.count > surfaceCapacity, let identity = surfaceAccessOrder.first {
            surfaceAccessOrder.removeFirst()
            textSurfaces[identity] = nil
        }
    }
}

struct NovelTextLayoutLiveSurfaceIdentity: Hashable {
    let documentView: Int
    let pageIndex: Int
    let blockIndex: Int
    let displayValue: NovelTextDisplayValue
    let widthBucket: Int
    let baseFontSizeBucket: Int
    let titleWeightBucket: Int
    let textColorSignature: Int

    init(
        documentView: Int,
        pageIndex: Int,
        blockIndex: Int,
        displayValue: NovelTextDisplayValue,
        width: CGFloat,
        baseFontSize: Double,
        titleWeight: UIFont.Weight = .regular,
        textColorSignature: Int
    ) {
        self.documentView = documentView
        self.pageIndex = pageIndex
        self.blockIndex = blockIndex
        self.displayValue = displayValue
        self.widthBucket = Int((max(width, 0) * 100).rounded())
        self.baseFontSizeBucket = Int((max(baseFontSize, 0) * 100).rounded())
        self.titleWeightBucket = Int((titleWeight.rawValue * 1000).rounded())
        self.textColorSignature = textColorSignature
    }
}

@MainActor
final class NovelTextLayoutLiveSurface {
    let identity: NovelTextLayoutLiveSurfaceIdentity
    let displayValue: NovelTextDisplayValue
    let view: UIView
    let height: CGFloat
    private let displayView: NovelTextViewportDisplayUIView

    init(
        identity: NovelTextLayoutLiveSurfaceIdentity,
        displayValue: NovelTextDisplayValue,
        displayView: NovelTextViewportDisplayUIView,
        height: CGFloat
    ) {
        self.identity = identity
        self.displayValue = displayValue
        self.displayView = displayView
        self.view = displayView
        self.height = height
    }

    func prepareForDisplay(size: CGSize) {
        displayView.prepareForDisplay(size: size)
    }

    func viewportSample(
        referencePoint: CGPoint,
        documentView: Int,
        pageIndex: Int
    ) -> NovelTextViewportSample? {
        guard let displayOffset = displayView.closestTextOffset(to: referencePoint) else {
            return nil
        }
        return ReaderVerticalViewportTextOffsetMapper.sample(
            displayOffset: displayOffset,
            displayValue: displayValue,
            documentView: documentView,
            pageIndex: pageIndex
        )
    }

    func referenceY(for anchor: ReaderVerticalTextAnchor) -> CGFloat? {
        guard let displayOffset = ReaderVerticalViewportTextOffsetMapper.displayOffset(
            for: anchor,
            displayValue: displayValue
        ) else {
            return nil
        }
        return displayView.textFragmentReferenceY(containingDisplayOffset: displayOffset)
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
        guard let fragment = closestLayoutFragment(to: point),
              let fragmentStart = displayOffset(for: fragment.rangeInElement.location, from: documentStart) else {
            return nil
        }
        let fragmentPoint = CGPoint(
            x: point.x - fragment.layoutFragmentFrame.minX,
            y: point.y - fragment.layoutFragmentFrame.minY
        )
        guard let lineFragment = fragment.textLineFragment(
            forVerticalOffset: fragmentPoint.y,
            requiresExactMatch: false
        ) else {
            return fragmentStart
        }
        let linePoint = CGPoint(
            x: fragmentPoint.x - lineFragment.typographicBounds.minX,
            y: fragmentPoint.y - lineFragment.typographicBounds.minY
        )
        let lineCharacterIndex = lineFragment.characterIndex(for: linePoint)
        let localCharacterOffset = min(
            max(lineCharacterIndex, lineFragment.characterRange.location),
            lineFragment.characterRange.location + lineFragment.characterRange.length
        )
        return min(max(fragmentStart + localCharacterOffset, 0), attributedText.length)
    }

    func textFragmentReferenceY(containingDisplayOffset displayOffset: Int) -> CGFloat? {
        guard bounds.width > 0, attributedText.length > 0 else { return nil }
        updateTextContainerSizeForCurrentBounds()
        textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
        let documentStart = textContentStorage.documentRange.location
        let normalizedOffset = min(max(displayOffset, 0), attributedText.length)
        guard let location = textContentStorage.location(documentStart, offsetBy: normalizedOffset),
              let fragment = textLayoutManager.textLayoutFragment(for: location),
              let lineFragment = fragment.textLineFragment(for: location, isUpstreamAffinity: true) else {
            return nil
        }
        return fragment.layoutFragmentFrame.minY + lineFragment.typographicBounds.midY
    }

    private func closestLayoutFragment(to point: CGPoint) -> NSTextLayoutFragment? {
        if let fragment = textLayoutManager.textLayoutFragment(for: point) {
            return fragment
        }

        let documentStart = textContentStorage.documentRange.location
        var best: (distance: CGFloat, fragment: NSTextLayoutFragment)?
        textLayoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            options: []
        ) { fragment in
            let distance = Self.distance(from: point, to: fragment.layoutFragmentFrame)
            if best == nil || distance < best!.distance {
                best = (distance, fragment)
            }
            return true
        }
        return best?.fragment
    }

    private func displayOffset(
        for location: NSTextLocation,
        from documentStart: NSTextLocation
    ) -> Int? {
        let offset = textContentStorage.offset(from: documentStart, to: location)
        guard offset != NSNotFound else { return nil }
        return offset
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
