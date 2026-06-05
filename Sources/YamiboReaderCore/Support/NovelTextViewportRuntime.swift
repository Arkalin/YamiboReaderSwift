import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

public struct NovelTextViewportRuntimeDiagnostics: Equatable, Sendable {
    public var contentStorageCount: Int
    public var activeLayoutManagerCount: Int
    public var perPageTextKitDocumentCount: Int
    public var semanticAttributedDocumentCacheCount: Int
    public var viewportControllerCount: Int
    public var currentActivePlusCandidateGraphCount: Int
    public var peakActivePlusCandidateGraphCount: Int
    public var postCommitFullLayoutCount: Int
    public var viewportUpdateCount: Int
    public var rematerializedSurfaceCount: Int

    public init(
        contentStorageCount: Int,
        activeLayoutManagerCount: Int,
        perPageTextKitDocumentCount: Int,
        semanticAttributedDocumentCacheCount: Int = 0,
        viewportControllerCount: Int? = nil,
        currentActivePlusCandidateGraphCount: Int? = nil,
        peakActivePlusCandidateGraphCount: Int? = nil,
        postCommitFullLayoutCount: Int = 0,
        viewportUpdateCount: Int = 0,
        rematerializedSurfaceCount: Int = 0
    ) {
        self.contentStorageCount = max(0, contentStorageCount)
        self.activeLayoutManagerCount = max(0, activeLayoutManagerCount)
        self.perPageTextKitDocumentCount = max(0, perPageTextKitDocumentCount)
        self.semanticAttributedDocumentCacheCount = max(0, semanticAttributedDocumentCacheCount)
        self.viewportControllerCount = max(0, viewportControllerCount ?? activeLayoutManagerCount)
        self.currentActivePlusCandidateGraphCount = max(0, currentActivePlusCandidateGraphCount ?? contentStorageCount)
        self.peakActivePlusCandidateGraphCount = max(0, peakActivePlusCandidateGraphCount ?? contentStorageCount)
        self.postCommitFullLayoutCount = max(0, postCommitFullLayoutCount)
        self.viewportUpdateCount = max(0, viewportUpdateCount)
        self.rematerializedSurfaceCount = max(0, rematerializedSurfaceCount)
    }
}

public struct NovelTextViewportRuntimeTransactionDiagnostics: Equatable, Sendable {
    public var committedTransactionCount: Int
    public var semanticAttributedDocumentBuildCount: Int
    public var semanticAttributedDocumentReuseCount: Int
    public var candidateIndexingPassCount: Int
    public var postIndexCompactionCount: Int
    public var geometryDeviationCount: Int

    public init(
        committedTransactionCount: Int = 0,
        semanticAttributedDocumentBuildCount: Int = 0,
        semanticAttributedDocumentReuseCount: Int = 0,
        candidateIndexingPassCount: Int? = nil,
        postIndexCompactionCount: Int? = nil,
        geometryDeviationCount: Int = 0
    ) {
        self.committedTransactionCount = max(0, committedTransactionCount)
        self.semanticAttributedDocumentBuildCount = max(0, semanticAttributedDocumentBuildCount)
        self.semanticAttributedDocumentReuseCount = max(0, semanticAttributedDocumentReuseCount)
        self.candidateIndexingPassCount = max(0, candidateIndexingPassCount ?? committedTransactionCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount ?? committedTransactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
    }
}

@MainActor
struct NovelTextLayoutRuntimeAdapterInput {
    var result: NovelTextLayoutResult
    var settings: ReaderAppearanceSettings
    var layout: ReaderContainerLayout
    var cachedSemanticAttributedDocument: NSAttributedString?
}

@MainActor
final class NovelTextLayoutRuntimeCandidate {
    let semanticAttributedDocument: NSAttributedString?
    let reusedSemanticAttributedDocument: Bool
    let fullDocumentLayoutPassCount: Int
    let postIndexCompactionCount: Int
    let geometryDeviationCount: Int

#if canImport(UIKit)
    let textContentStorage: NSTextContentStorage?
    let textLayoutManager: NSTextLayoutManager?
    let textContainer: NSTextContainer?
#endif

    init(
        semanticAttributedDocument: NSAttributedString? = nil,
        reusedSemanticAttributedDocument: Bool = false,
        fullDocumentLayoutPassCount: Int = 1,
        postIndexCompactionCount: Int = 1,
        geometryDeviationCount: Int = 0
    ) {
        self.semanticAttributedDocument = semanticAttributedDocument
        self.reusedSemanticAttributedDocument = reusedSemanticAttributedDocument
        self.fullDocumentLayoutPassCount = max(0, fullDocumentLayoutPassCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
#endif
    }

#if canImport(UIKit)
    init(
        semanticAttributedDocument: NSAttributedString? = nil,
        reusedSemanticAttributedDocument: Bool = false,
        fullDocumentLayoutPassCount: Int = 1,
        postIndexCompactionCount: Int = 1,
        geometryDeviationCount: Int = 0,
        textContentStorage: NSTextContentStorage?,
        textLayoutManager: NSTextLayoutManager?,
        textContainer: NSTextContainer?
    ) {
        self.semanticAttributedDocument = semanticAttributedDocument
        self.reusedSemanticAttributedDocument = reusedSemanticAttributedDocument
        self.fullDocumentLayoutPassCount = max(0, fullDocumentLayoutPassCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
        self.textContentStorage = textContentStorage
        self.textLayoutManager = textLayoutManager
        self.textContainer = textContainer
    }
#endif
}

private extension NovelTextLayoutRuntimeCandidate {
    var textKitGraphCount: Int {
#if canImport(UIKit)
        textContentStorage == nil ? 0 : 1
#else
        0
#endif
    }
}

@MainActor
protocol NovelTextLayoutRuntimeAdapter: AnyObject {
    func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate
}

@MainActor
final class DefaultNovelTextLayoutRuntimeAdapter: NovelTextLayoutRuntimeAdapter {
    func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate {
#if canImport(UIKit)
        let reusesSemanticDocument = input.cachedSemanticAttributedDocument != nil
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let contentWidth = max(input.layout.readableFrame.width, 1)
        let container = NSTextContainer(
            size: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        let attributedDocument: NSAttributedString
        if reusesSemanticDocument, let cached = input.cachedSemanticAttributedDocument {
            attributedDocument = cached
        } else {
#if canImport(UIKit)
            attributedDocument = ReaderAttributedTextFactory.makeAttributedText(
                text: input.result.viewportContext.document.text,
                chapterTitle: nil,
                settings: input.settings
            )
#else
            attributedDocument = NSAttributedString(string: input.result.viewportContext.document.text)
#endif
        }
        contentStorage.textStorage?.setAttributedString(attributedDocument)
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        return NovelTextLayoutRuntimeCandidate(
            semanticAttributedDocument: attributedDocument,
            reusedSemanticAttributedDocument: reusesSemanticDocument,
            fullDocumentLayoutPassCount: 1,
            postIndexCompactionCount: 1,
            textContentStorage: contentStorage,
            textLayoutManager: layoutManager,
            textContainer: container
        )
#else
        return NovelTextLayoutRuntimeCandidate()
#endif
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
#if canImport(UIKit)
        runtimeOwner?.viewportSample(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            referencePoint: referencePoint
        )
#else
        nil
#endif
    }

    public func referenceY(segmentIndex: Int, segmentOffset: Int) -> CGFloat? {
#if canImport(UIKit)
        runtimeOwner?.referenceY(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            segmentIndex: segmentIndex,
            segmentOffset: segmentOffset
        )
#else
        nil
#endif
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
    private enum State {
        case pending
        case committed
        case superseded
    }

    let generation: UInt64
    let result: NovelTextLayoutResult
    let settings: ReaderAppearanceSettings
    let layout: ReaderContainerLayout
    private(set) var semanticAttributedDocument: NSAttributedString?
    let reusedSemanticAttributedDocument: Bool
    let fullDocumentLayoutPassCount: Int
    let postIndexCompactionCount: Int
    let geometryDeviationCount: Int
    private var state = State.pending

#if canImport(UIKit)
    private(set) var textContentStorage: NSTextContentStorage?
    private(set) var textLayoutManager: NSTextLayoutManager?
    private(set) var textContainer: NSTextContainer?
#endif

    init(
        generation: UInt64,
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        candidate: NovelTextLayoutRuntimeCandidate
    ) {
        self.generation = generation
        self.result = result
        self.settings = settings
        self.layout = layout
        semanticAttributedDocument = candidate.semanticAttributedDocument
        reusedSemanticAttributedDocument = candidate.reusedSemanticAttributedDocument
        fullDocumentLayoutPassCount = candidate.fullDocumentLayoutPassCount
        postIndexCompactionCount = candidate.postIndexCompactionCount
        geometryDeviationCount = candidate.geometryDeviationCount
#if canImport(UIKit)
        textContentStorage = candidate.textContentStorage
        textLayoutManager = candidate.textLayoutManager
        textContainer = candidate.textContainer
#endif
    }

    func markCommitted() -> Bool {
        guard case .pending = state else { return false }
        state = .committed
        return true
    }

    func supersede() {
        guard case .pending = state else { return }
        state = .superseded
        semanticAttributedDocument = nil
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
#endif
    }
}

private extension NovelTextViewportRuntimeTransaction {
    var textKitGraphCount: Int {
#if canImport(UIKit)
        textContentStorage == nil ? 0 : 1
#else
        0
#endif
    }
}

@MainActor
final class NovelTextViewportRuntimeOwner {
    private var activeGeneration: UInt64 = 0
    private var nextGeneration: UInt64 = 1
    private var result: NovelTextLayoutResult?
    private var settings = ReaderAppearanceSettings()
    private var layout = ReaderContainerLayout(width: 1, height: 1)
    private var visiblePageIdentities = Set<Int>()
    private var semanticAttributedDocumentCache: NSAttributedString?
    private var transactionDiagnostics = NovelTextViewportRuntimeTransactionDiagnostics()
    private var peakActivePlusCandidateGraphCount = 0
    private var viewportUpdateCount = 0
    private var rematerializedSurfaceCount = 0
    private let adapter: any NovelTextLayoutRuntimeAdapter
    private var pendingTransaction: NovelTextViewportRuntimeTransaction?

#if canImport(UIKit)
    private var textContentStorage: NSTextContentStorage?
    private var textLayoutManager: NSTextLayoutManager?
    private var textContainer: NSTextContainer?
#endif

    init(adapter: any NovelTextLayoutRuntimeAdapter = DefaultNovelTextLayoutRuntimeAdapter()) {
        self.adapter = adapter
    }

    var diagnostics: NovelTextViewportRuntimeDiagnostics {
#if canImport(UIKit)
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: textContentStorage == nil ? 0 : 1,
            activeLayoutManagerCount: textLayoutManager == nil ? 0 : 1,
            perPageTextKitDocumentCount: 0,
            semanticAttributedDocumentCacheCount: semanticAttributedDocumentCache == nil ? 0 : 1,
            currentActivePlusCandidateGraphCount: activeTextKitGraphCount + pendingTextKitGraphCount,
            peakActivePlusCandidateGraphCount: peakActivePlusCandidateGraphCount,
            postCommitFullLayoutCount: 0,
            viewportUpdateCount: viewportUpdateCount,
            rematerializedSurfaceCount: rematerializedSurfaceCount
        )
#else
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: 0,
            activeLayoutManagerCount: 0,
            perPageTextKitDocumentCount: 0,
            semanticAttributedDocumentCacheCount: semanticAttributedDocumentCache == nil ? 0 : 1,
            currentActivePlusCandidateGraphCount: pendingTextKitGraphCount,
            peakActivePlusCandidateGraphCount: peakActivePlusCandidateGraphCount,
            postCommitFullLayoutCount: 0,
            viewportUpdateCount: viewportUpdateCount,
            rematerializedSurfaceCount: rematerializedSurfaceCount
        )
#endif
    }

    var runtimeTransactionDiagnostics: NovelTextViewportRuntimeTransactionDiagnostics {
        transactionDiagnostics
    }

    var currentGeneration: UInt64 {
        activeGeneration
    }

    private var activeTextKitGraphCount: Int {
#if canImport(UIKit)
        textContentStorage == nil ? 0 : 1
#else
        0
#endif
    }

    private var pendingTextKitGraphCount: Int {
        pendingTransaction?.textKitGraphCount ?? 0
    }

    func commit(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws {
        guard let transaction = try prepareTransaction(
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
    ) throws -> NovelTextViewportRuntimeTransaction? {
        guard self.result != result || self.settings != settings || self.layout != layout else {
            return nil
        }

        pendingTransaction?.supersede()
        pendingTransaction = nil
        let generation = nextGeneration
        nextGeneration &+= 1
        let candidate = try adapter.prepareCandidate(
            input: NovelTextLayoutRuntimeAdapterInput(
                result: result,
                settings: settings,
                layout: layout,
                cachedSemanticAttributedDocument: reusableSemanticAttributedDocument(
                    for: result,
                    settings: settings
                )
            )
        )
        peakActivePlusCandidateGraphCount = max(
            peakActivePlusCandidateGraphCount,
            activeTextKitGraphCount + candidate.textKitGraphCount
        )
        let transaction = NovelTextViewportRuntimeTransaction(
            generation: generation,
            result: result,
            settings: settings,
            layout: layout,
            candidate: candidate
        )
        pendingTransaction = transaction
        return transaction
    }

    func commit(_ transaction: NovelTextViewportRuntimeTransaction) {
        guard pendingTransaction === transaction,
              transaction.markCommitted() else { return }
        pendingTransaction = nil
        activeGeneration = transaction.generation
        result = transaction.result
        settings = transaction.settings
        layout = transaction.layout
        semanticAttributedDocumentCache = transaction.semanticAttributedDocument
#if canImport(UIKit)
        textContentStorage = transaction.textContentStorage
        textLayoutManager = transaction.textLayoutManager
        textContainer = transaction.textContainer
#endif
        transactionDiagnostics.committedTransactionCount += 1
        if transaction.reusedSemanticAttributedDocument {
            transactionDiagnostics.semanticAttributedDocumentReuseCount += 1
        } else if transaction.semanticAttributedDocument != nil {
            transactionDiagnostics.semanticAttributedDocumentBuildCount += 1
        }
        transactionDiagnostics.candidateIndexingPassCount += transaction.fullDocumentLayoutPassCount
        transactionDiagnostics.postIndexCompactionCount += transaction.postIndexCompactionCount
        transactionDiagnostics.geometryDeviationCount += transaction.geometryDeviationCount
        peakActivePlusCandidateGraphCount = max(peakActivePlusCandidateGraphCount, activeTextKitGraphCount)
    }

    private func reusableSemanticAttributedDocument(
        for result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings
    ) -> NSAttributedString? {
        guard self.result?.viewportContext.document == result.viewportContext.document,
              self.settings == settings else {
            return nil
        }
        return semanticAttributedDocumentCache
    }

    func release() {
        pendingTransaction?.supersede()
        pendingTransaction = nil
        result = nil
        visiblePageIdentities.removeAll(keepingCapacity: false)
        semanticAttributedDocumentCache = nil
        peakActivePlusCandidateGraphCount = 0
        viewportUpdateCount = 0
        rematerializedSurfaceCount = 0
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
#endif
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
            generation: activeGeneration,
            documentView: page.documentView,
            pageIdentity: page.pageIndex
        )
    }

    func displayReference(for surfaceIdentity: NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference? {
        guard surfaceIdentity.generation == activeGeneration else {
            return nil
        }
        return displayReference(for: surfaceIdentity.ordinal)
    }

    func updateVisiblePageIdentities(_ pageIdentities: [Int]) {
        visiblePageIdentities = Set(pageIdentities.filter { pageIdentity in
            result?.viewportIndex.pages.contains(where: { $0.pageIndex == pageIdentity }) == true
        })
    }

    func updateVisibleSurfaceIdentities(_ surfaceIdentities: [NovelReaderSurfaceIdentity]) {
        let visibleOrdinals = Set<Int>(surfaceIdentities.compactMap { surfaceIdentity -> Int? in
            guard surfaceIdentity.generation == activeGeneration,
                  result?.viewportIndex.pages.contains(where: { $0.pageIndex == surfaceIdentity.ordinal }) == true else {
                return nil
            }
            return surfaceIdentity.ordinal
        })
        visiblePageIdentities = preheatedPageIdentities(around: visibleOrdinals)
        viewportUpdateCount += 1
        rematerializedSurfaceCount = visiblePageIdentities.count
    }

    private func preheatedPageIdentities(around visibleOrdinals: Set<Int>) -> Set<Int> {
        guard let pages = result?.viewportIndex.pages, !visibleOrdinals.isEmpty else { return [] }
        let validOrdinals = Set(pages.map(\.pageIndex))
        var preheated = visibleOrdinals.intersection(validOrdinals)
        if let first = visibleOrdinals.min(), validOrdinals.contains(first - 1) {
            preheated.insert(first - 1)
        }
        if let last = visibleOrdinals.max(), validOrdinals.contains(last + 1) {
            preheated.insert(last + 1)
        }
        return preheated
    }

    func isCurrent(generation: UInt64, documentView: Int, pageIdentity: Int) -> Bool {
        guard generation == activeGeneration,
              let page = result?.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }) else {
            return false
        }
        return page.documentView == documentView
    }

#if canImport(UIKit)
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
        if let frozenGeometry = page.frozenGeometry {
            return frozenGeometry.pageLocalOriginY
        }
        guard let firstRange = page.ranges.first,
              let documentRange = result.viewportContext.document.textRangesBySegment[firstRange.segmentIndex],
              let pageLocation = textContentStorage.location(
                textContentStorage.documentRange.location,
                offsetBy: documentRange.startOffset + firstRange.startOffset
              ),
              let firstFragment = textLayoutManager.textLayoutFragment(for: pageLocation) else {
            return nil
        }
        guard let firstLineFragment = firstFragment.textLineFragment(
            for: pageLocation,
            isUpstreamAffinity: false
        ) else {
            return firstFragment.layoutFragmentFrame.minY
        }
        return firstFragment.layoutFragmentFrame.minY + firstLineFragment.typographicBounds.minY
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
        let pageLocation = pageStartLocation(
            page: page,
            result: result,
            textContentStorage: textContentStorage
        ) else {
            return
        }
        let clipMaxY = page.frozenGeometry?.documentClipMaxY ?? pageOriginY + bounds.height

        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.minX, y: bounds.minY - pageOriginY)
        textLayoutManager.enumerateTextLayoutFragments(
            from: pageLocation,
            options: [.ensuresLayout]
        ) { fragment in
            guard fragment.layoutFragmentFrame.minY < clipMaxY else {
                return false
            }
            guard fragment.layoutFragmentFrame.maxY >= pageOriginY else {
                return true
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
        context.restoreGState()
    }

    private func pageStartLocation(
        page: NovelTextViewportIndexPage,
        result: NovelTextLayoutResult,
        textContentStorage: NSTextContentStorage
    ) -> NSTextLocation? {
        if let frozenGeometry = page.frozenGeometry {
            return textContentStorage.location(
                textContentStorage.documentRange.location,
                offsetBy: frozenGeometry.documentStartOffset
            )
        }
        guard let firstRange = page.ranges.first,
              let documentRange = result.viewportContext.document.textRangesBySegment[firstRange.segmentIndex] else {
            return nil
        }
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: documentRange.startOffset + firstRange.startOffset
        )
    }
#endif
}
