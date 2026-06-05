import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NovelTextViewportRuntimeDiagnostics: Equatable, Sendable {
    public var contentStorageCount: Int
    public var activeLayoutManagerCount: Int
    public var perPageTextKitDocumentCount: Int
    public var semanticAttributedDocumentCacheCount: Int

    public init(
        contentStorageCount: Int,
        activeLayoutManagerCount: Int,
        perPageTextKitDocumentCount: Int,
        semanticAttributedDocumentCacheCount: Int = 0
    ) {
        self.contentStorageCount = max(0, contentStorageCount)
        self.activeLayoutManagerCount = max(0, activeLayoutManagerCount)
        self.perPageTextKitDocumentCount = max(0, perPageTextKitDocumentCount)
        self.semanticAttributedDocumentCacheCount = max(0, semanticAttributedDocumentCacheCount)
    }
}

public struct NovelTextViewportRuntimeTransactionDiagnostics: Equatable, Sendable {
    public var committedTransactionCount: Int
    public var semanticAttributedDocumentBuildCount: Int
    public var semanticAttributedDocumentReuseCount: Int

    public init(
        committedTransactionCount: Int = 0,
        semanticAttributedDocumentBuildCount: Int = 0,
        semanticAttributedDocumentReuseCount: Int = 0
    ) {
        self.committedTransactionCount = max(0, committedTransactionCount)
        self.semanticAttributedDocumentBuildCount = max(0, semanticAttributedDocumentBuildCount)
        self.semanticAttributedDocumentReuseCount = max(0, semanticAttributedDocumentReuseCount)
    }
}

@MainActor
public final class NovelTextViewportDisplayReference {
    public let generation: UInt64
    public let documentView: Int
    public let pageIdentity: Int

    private weak var runtimeOwner: NovelTextViewportRuntimeOwner?

    init(
        runtimeOwner: NovelTextViewportRuntimeOwner,
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int
    ) {
        self.runtimeOwner = runtimeOwner
        self.generation = generation
        self.documentView = documentView
        self.pageIdentity = pageIdentity
    }

    public var isStale: Bool {
        guard let runtimeOwner else { return true }
        return !runtimeOwner.isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        )
    }

    public func viewportSample(referencePoint: CGPoint) -> NovelTextViewportSample? {
        runtimeOwner?.viewportSample(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            referencePoint: referencePoint
        )
    }

    public func referenceY(segmentIndex: Int, segmentOffset: Int) -> CGFloat? {
        runtimeOwner?.referenceY(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            segmentIndex: segmentIndex,
            segmentOffset: segmentOffset
        )
    }

#if canImport(UIKit)
    public func draw(in context: CGContext, bounds: CGRect) {
        runtimeOwner?.draw(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            in: context,
            bounds: bounds
        )
    }
#endif
}

@MainActor
final class NovelTextViewportRuntimeTransaction {
    let result: NovelTextLayoutResult
    let settings: ReaderAppearanceSettings
    let layout: ReaderContainerLayout
    let semanticAttributedDocument: NSAttributedString?
    let reusedSemanticAttributedDocument: Bool

#if canImport(UIKit) || canImport(AppKit)
    let textContentStorage: NSTextContentStorage
    let textLayoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer

    init(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        semanticAttributedDocument: NSAttributedString?,
        reusedSemanticAttributedDocument: Bool,
        textContentStorage: NSTextContentStorage,
        textLayoutManager: NSTextLayoutManager,
        textContainer: NSTextContainer
    ) {
        self.result = result
        self.settings = settings
        self.layout = layout
        self.semanticAttributedDocument = semanticAttributedDocument
        self.reusedSemanticAttributedDocument = reusedSemanticAttributedDocument
        self.textContentStorage = textContentStorage
        self.textLayoutManager = textLayoutManager
        self.textContainer = textContainer
    }
#else
    init(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) {
        self.result = result
        self.settings = settings
        self.layout = layout
        semanticAttributedDocument = nil
        reusedSemanticAttributedDocument = false
    }
#endif
}

@MainActor
final class NovelTextViewportRuntimeOwner {
    private var generation: UInt64 = 0
    private var result: NovelTextLayoutResult?
    private var settings = ReaderAppearanceSettings()
    private var layout = ReaderContainerLayout(width: 1, height: 1)
    private var visiblePageIdentities = Set<Int>()
    private var semanticAttributedDocumentCache: NSAttributedString?
    private var transactionDiagnostics = NovelTextViewportRuntimeTransactionDiagnostics()

#if canImport(UIKit) || canImport(AppKit)
    private var textContentStorage: NSTextContentStorage?
    private var textLayoutManager: NSTextLayoutManager?
    private var textContainer: NSTextContainer?
#endif

    var diagnostics: NovelTextViewportRuntimeDiagnostics {
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: textContentStorage == nil ? 0 : 1,
            activeLayoutManagerCount: textLayoutManager == nil ? 0 : 1,
            perPageTextKitDocumentCount: 0,
            semanticAttributedDocumentCacheCount: semanticAttributedDocumentCache == nil ? 0 : 1
        )
    }

    var runtimeTransactionDiagnostics: NovelTextViewportRuntimeTransactionDiagnostics {
        transactionDiagnostics
    }

    func commit(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) {
        guard let transaction = prepareTransaction(
            result: result,
            settings: settings,
            layout: layout
        ) else { return }
        commit(transaction)
    }

    func prepareTransaction(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> NovelTextViewportRuntimeTransaction? {
        guard self.result != result || self.settings != settings || self.layout != layout else {
            return nil
        }

#if canImport(UIKit) || canImport(AppKit)
        let reusesSemanticDocument =
            self.result?.viewportContext.document == result.viewportContext.document &&
            self.settings == settings &&
            semanticAttributedDocumentCache != nil
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let contentWidth = max(layout.readableFrame.width - settings.horizontalPadding * 2, 1)
        let container = NSTextContainer(
            size: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        let attributedDocument: NSAttributedString
        if reusesSemanticDocument, let semanticAttributedDocumentCache {
            attributedDocument = semanticAttributedDocumentCache
        } else {
#if canImport(UIKit)
            attributedDocument = ReaderAttributedTextFactory.makeAttributedText(
                text: result.viewportContext.document.text,
                chapterTitle: nil,
                settings: settings
            )
#else
            attributedDocument = NSAttributedString(string: result.viewportContext.document.text)
#endif
        }
        contentStorage.textStorage?.setAttributedString(attributedDocument)
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        return NovelTextViewportRuntimeTransaction(
            result: result,
            settings: settings,
            layout: layout,
            semanticAttributedDocument: attributedDocument,
            reusedSemanticAttributedDocument: reusesSemanticDocument,
            textContentStorage: contentStorage,
            textLayoutManager: layoutManager,
            textContainer: container
        )
#else
        return NovelTextViewportRuntimeTransaction(
            result: result,
            settings: settings,
            layout: layout
        )
#endif
    }

    func commit(_ transaction: NovelTextViewportRuntimeTransaction) {
        result = transaction.result
        settings = transaction.settings
        layout = transaction.layout
        semanticAttributedDocumentCache = transaction.semanticAttributedDocument
#if canImport(UIKit) || canImport(AppKit)
        textContentStorage = transaction.textContentStorage
        textLayoutManager = transaction.textLayoutManager
        textContainer = transaction.textContainer
#endif
        generation &+= 1
        transactionDiagnostics.committedTransactionCount += 1
        if transaction.reusedSemanticAttributedDocument {
            transactionDiagnostics.semanticAttributedDocumentReuseCount += 1
        } else if transaction.semanticAttributedDocument != nil {
            transactionDiagnostics.semanticAttributedDocumentBuildCount += 1
        }
    }

    func release() {
        result = nil
        visiblePageIdentities.removeAll(keepingCapacity: false)
        semanticAttributedDocumentCache = nil
#if canImport(UIKit) || canImport(AppKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
#endif
        generation &+= 1
    }

    func handleMemoryPressure() {
        // The live TextKit graph owns everything needed to keep the current
        // generation drawable. This extra attributed document is rebuildable.
        semanticAttributedDocumentCache = nil
    }

    func displayReference(for pageIdentity: Int) -> NovelTextViewportDisplayReference? {
        guard let page = result?.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }) else {
            return nil
        }
        return NovelTextViewportDisplayReference(
            runtimeOwner: self,
            generation: generation,
            documentView: page.documentView,
            pageIdentity: page.pageIndex
        )
    }

    func updateVisiblePageIdentities(_ pageIdentities: [Int]) {
        visiblePageIdentities = Set(pageIdentities.filter { pageIdentity in
            result?.viewportIndex.pages.contains(where: { $0.pageIndex == pageIdentity }) == true
        })
    }

    func isCurrent(generation: UInt64, documentView: Int, pageIdentity: Int) -> Bool {
        guard generation == self.generation,
              let page = result?.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }) else {
            return false
        }
        return page.documentView == documentView
    }

#if canImport(UIKit) || canImport(AppKit)
    func viewportSample(
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int,
        referencePoint: CGPoint
    ) -> NovelTextViewportSample? {
        guard isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        ),
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }),
        let pageOriginY = pageOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let fragment = closestLayoutFragment(
            to: CGPoint(x: referencePoint.x, y: pageOriginY + referencePoint.y),
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ) else {
            return nil
        }

        let documentStart = textContentStorage.documentRange.location
        let fragmentStart = textContentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
        guard fragmentStart != NSNotFound else { return nil }
        let fragmentPoint = CGPoint(
            x: referencePoint.x - fragment.layoutFragmentFrame.minX,
            y: pageOriginY + referencePoint.y - fragment.layoutFragmentFrame.minY
        )
        let lineOffset: Int
        if let lineFragment = fragment.textLineFragment(
            forVerticalOffset: fragmentPoint.y,
            requiresExactMatch: false
        ) {
            let linePoint = CGPoint(
                x: fragmentPoint.x - lineFragment.typographicBounds.minX,
                y: fragmentPoint.y - lineFragment.typographicBounds.minY
            )
            lineOffset = min(
                max(lineFragment.characterIndex(for: linePoint), lineFragment.characterRange.location),
                lineFragment.characterRange.location + lineFragment.characterRange.length
            )
        } else {
            lineOffset = 0
        }
        let documentOffset = fragmentStart + lineOffset
        guard let segmentRange = result.viewportContext.document.textRangesBySegment
            .first(where: { _, range in
                documentOffset >= range.startOffset && documentOffset <= range.endOffset
            }) else {
            return nearestTextSample(
                documentOffset: documentOffset,
                page: page,
                result: result
            )
        }
        return NovelTextViewportSample(
            documentView: documentView,
            pageIndex: pageIdentity,
            segmentIndex: segmentRange.key,
            segmentOffset: documentOffset - segmentRange.value.startOffset
        )
    }

    func referenceY(
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int,
        segmentIndex: Int,
        segmentOffset: Int
    ) -> CGFloat? {
        guard isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        ),
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }),
        let segmentRange = result.viewportContext.document.textRangesBySegment[segmentIndex],
        let pageOriginY = pageOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let location = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: segmentRange.startOffset + min(max(segmentOffset, 0), segmentRange.length)
        ),
        let fragment = textLayoutManager.textLayoutFragment(for: location),
        let lineFragment = fragment.textLineFragment(for: location, isUpstreamAffinity: true) else {
            return nil
        }
        return fragment.layoutFragmentFrame.minY + lineFragment.typographicBounds.midY - pageOriginY
    }

    private func pageOriginY(
        page: NovelTextViewportIndexPage,
        result: NovelTextLayoutResult,
        textContentStorage: NSTextContentStorage,
        textLayoutManager: NSTextLayoutManager
    ) -> CGFloat? {
        guard let firstRange = page.ranges.first,
              let documentRange = result.viewportContext.document.textRangesBySegment[firstRange.segmentIndex],
              let pageLocation = textContentStorage.location(
                textContentStorage.documentRange.location,
                offsetBy: documentRange.startOffset + firstRange.startOffset
              ),
              let firstFragment = textLayoutManager.textLayoutFragment(for: pageLocation) else {
            return nil
        }
        return firstFragment.layoutFragmentFrame.minY
    }

    private func closestLayoutFragment(
        to point: CGPoint,
        textContentStorage: NSTextContentStorage,
        textLayoutManager: NSTextLayoutManager
    ) -> NSTextLayoutFragment? {
        if let fragment = textLayoutManager.textLayoutFragment(for: point) {
            return fragment
        }
        var best: (distance: CGFloat, fragment: NSTextLayoutFragment)?
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: []
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = hypot(dx, dy)
            if best == nil || distance < best!.distance {
                best = (distance, fragment)
            }
            return true
        }
        return best?.fragment
    }

    private func nearestTextSample(
        documentOffset: Int,
        page: NovelTextViewportIndexPage,
        result: NovelTextLayoutResult
    ) -> NovelTextViewportSample? {
        let candidates = page.ranges.compactMap { range -> (distance: Int, sample: NovelTextViewportSample)? in
            guard let documentRange = result.viewportContext.document.textRangesBySegment[range.segmentIndex] else {
                return nil
            }
            let start = documentRange.startOffset + range.startOffset
            let end = documentRange.startOffset + range.endOffset
            let nearestOffset = min(max(documentOffset, start), end)
            return (
                abs(documentOffset - nearestOffset),
                NovelTextViewportSample(
                    documentView: page.documentView,
                    pageIndex: page.pageIndex,
                    segmentIndex: range.segmentIndex,
                    segmentOffset: nearestOffset - documentRange.startOffset
                )
            )
        }
        return candidates.min { $0.distance < $1.distance }?.sample
    }
#endif

#if canImport(UIKit)
    func draw(
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int,
        in context: CGContext,
        bounds: CGRect
    ) {
        guard isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        ),
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }),
        let pageOriginY = pageOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let firstRange = page.ranges.first,
        let documentRange = result.viewportContext.document.textRangesBySegment[firstRange.segmentIndex],
        let pageLocation = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: documentRange.startOffset + firstRange.startOffset
        ) else {
            return
        }

        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.minX, y: bounds.minY - pageOriginY)
        textLayoutManager.enumerateTextLayoutFragments(
            from: pageLocation,
            options: [.ensuresLayout]
        ) { fragment in
            guard fragment.layoutFragmentFrame.minY < pageOriginY + bounds.height else {
                return false
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
        context.restoreGState()
    }
#endif
}
