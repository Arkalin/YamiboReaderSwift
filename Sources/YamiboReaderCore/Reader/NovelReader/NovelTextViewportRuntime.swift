import CoreGraphics
import Foundation

struct NovelTextSurfaceLayoutFragment: Equatable {
    let characterRange: NSRange
    let rect: CGRect
}

struct NovelTextSurfaceLayoutSlice: Equatable {
    let characterRange: NSRange
    let clipRect: CGRect
}

package struct NovelTextSelectionAnchor: Hashable, Sendable {
    public var generation: UInt64
    public var documentOffset: Int

    public init(generation: UInt64, documentOffset: Int) {
        self.generation = generation
        self.documentOffset = max(0, documentOffset)
    }
}

package struct NovelTextSelectionRange: Hashable, Sendable {
    public var generation: UInt64
    public var lowerBound: Int
    public var upperBound: Int

    public init?(generation: UInt64, lowerBound: Int, upperBound: Int) {
        let normalizedLower = max(0, min(lowerBound, upperBound))
        let normalizedUpper = max(0, max(lowerBound, upperBound))
        guard normalizedUpper > normalizedLower else { return nil }
        self.generation = generation
        self.lowerBound = normalizedLower
        self.upperBound = normalizedUpper
    }

    public var range: Range<Int> {
        lowerBound..<upperBound
    }
}

enum NovelTextSurfaceFragmentPartitioner {
    static func partition(
        _ segments: [NovelTextSurfaceLayoutFragment],
        surfaceHeight: CGFloat,
        breakOffsets: Set<Int> = []
    ) -> [NovelTextSurfaceLayoutSlice] {
        guard surfaceHeight > 0 else { return [] }
        var surfaces: [NovelTextSurfaceLayoutSlice] = []
        var currentRange: NSRange?
        var currentClipRect: CGRect?
        for segment in segments {
            guard let existingRange = currentRange,
                  let existingClipRect = currentClipRect else {
                currentRange = segment.characterRange
                currentClipRect = segment.rect
                continue
            }
            if breakOffsets.contains(where: { breakOffset in
                breakOffset > existingRange.location &&
                    breakOffset <= segment.characterRange.location
            }) {
                surfaces.append(
                    NovelTextSurfaceLayoutSlice(
                        characterRange: existingRange,
                        clipRect: existingClipRect
                    )
                )
                currentRange = segment.characterRange
                currentClipRect = segment.rect
                continue
            }
            if segment.characterRange.location < existingRange.location + existingRange.length {
                guard segment.characterRange.location + segment.characterRange.length > existingRange.location + existingRange.length else {
                    continue
                }
                currentRange = existingRange.union(segment.characterRange)
                currentClipRect = existingClipRect.union(segment.rect)
                continue
            }
            let candidateClipRect = existingClipRect.union(segment.rect)
            if candidateClipRect.height > surfaceHeight {
                surfaces.append(
                    NovelTextSurfaceLayoutSlice(
                        characterRange: existingRange,
                        clipRect: existingClipRect
                    )
                )
                currentRange = segment.characterRange
                currentClipRect = segment.rect
            } else {
                currentRange = existingRange.union(segment.characterRange)
                currentClipRect = candidateClipRect
            }
        }
        if let currentRange, let currentClipRect {
            surfaces.append(
                NovelTextSurfaceLayoutSlice(
                    characterRange: currentRange,
                    clipRect: currentClipRect
                )
            )
        }
        return surfaces
    }
}

enum NovelTextViewportDrawingGeometry {
    static func clipRect(
        bounds: CGRect,
        surfaceOriginY: CGFloat,
        documentClipMaxY: CGFloat?
    ) -> CGRect {
        guard let documentClipMaxY else { return bounds }
        let clipHeight = min(
            max(documentClipMaxY - surfaceOriginY, 0),
            max(bounds.height, 0)
        )
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: clipHeight
        )
    }

    static func fragmentStartsInDocumentRange(
        fragmentStart: Int,
        fragmentEnd: Int,
        documentRange: Range<Int>
    ) -> Bool {
        guard fragmentStart != NSNotFound,
              fragmentEnd != NSNotFound,
              fragmentEnd > fragmentStart else {
            return false
        }
        return fragmentStart >= documentRange.lowerBound &&
            fragmentStart < documentRange.upperBound
    }
}

#if canImport(UIKit)
import UIKit
#endif

package struct NovelTextViewportRuntimeDiagnostics: Equatable, Sendable {
    public var contentStorageCount: Int
    public var activeLayoutManagerCount: Int
    public var perSurfaceTextKitDocumentCount: Int
    public var semanticAttributedDocumentCacheCount: Int
    public var viewportControllerCount: Int
    public var currentActivePlusCandidateGraphCount: Int
    public var peakActivePlusCandidateGraphCount: Int
    public var postCommitFullLayoutCount: Int
    public var viewportUpdateCount: Int
    public var rematerializedSurfaceCount: Int
    public var drawingAccessCount: Int
    public var staleDrawingAttemptCount: Int
    public var lastDrawnSurfaceIdentity: NovelReaderSurfaceIdentity?
    public var lastDrawnDocumentRange: Range<Int>?

    public init(
        contentStorageCount: Int,
        activeLayoutManagerCount: Int,
        perSurfaceTextKitDocumentCount: Int,
        semanticAttributedDocumentCacheCount: Int = 0,
        viewportControllerCount: Int? = nil,
        currentActivePlusCandidateGraphCount: Int? = nil,
        peakActivePlusCandidateGraphCount: Int? = nil,
        postCommitFullLayoutCount: Int = 0,
        viewportUpdateCount: Int = 0,
        rematerializedSurfaceCount: Int = 0,
        drawingAccessCount: Int = 0,
        staleDrawingAttemptCount: Int = 0,
        lastDrawnSurfaceIdentity: NovelReaderSurfaceIdentity? = nil,
        lastDrawnDocumentRange: Range<Int>? = nil
    ) {
        self.contentStorageCount = max(0, contentStorageCount)
        self.activeLayoutManagerCount = max(0, activeLayoutManagerCount)
        self.perSurfaceTextKitDocumentCount = max(0, perSurfaceTextKitDocumentCount)
        self.semanticAttributedDocumentCacheCount = max(0, semanticAttributedDocumentCacheCount)
        self.viewportControllerCount = max(0, viewportControllerCount ?? activeLayoutManagerCount)
        self.currentActivePlusCandidateGraphCount = max(0, currentActivePlusCandidateGraphCount ?? contentStorageCount)
        self.peakActivePlusCandidateGraphCount = max(0, peakActivePlusCandidateGraphCount ?? contentStorageCount)
        self.postCommitFullLayoutCount = max(0, postCommitFullLayoutCount)
        self.viewportUpdateCount = max(0, viewportUpdateCount)
        self.rematerializedSurfaceCount = max(0, rematerializedSurfaceCount)
        self.drawingAccessCount = max(0, drawingAccessCount)
        self.staleDrawingAttemptCount = max(0, staleDrawingAttemptCount)
        self.lastDrawnSurfaceIdentity = lastDrawnSurfaceIdentity
        self.lastDrawnDocumentRange = lastDrawnDocumentRange
    }
}

package struct NovelTextViewportRuntimeTransactionDiagnostics: Equatable, Sendable {
    public var committedTransactionCount: Int
    public var supersededTransactionCount: Int
    public var failedTransactionCount: Int
    public var lastFailureStage: NovelTextLayoutFailureStage?
    public var semanticAttributedDocumentBuildCount: Int
    public var semanticAttributedDocumentReuseCount: Int
    public var candidateIndexingPassCount: Int
    public var postIndexCompactionCount: Int
    public var geometryDeviationCount: Int

    public init(
        committedTransactionCount: Int = 0,
        supersededTransactionCount: Int = 0,
        failedTransactionCount: Int = 0,
        lastFailureStage: NovelTextLayoutFailureStage? = nil,
        semanticAttributedDocumentBuildCount: Int = 0,
        semanticAttributedDocumentReuseCount: Int = 0,
        candidateIndexingPassCount: Int? = nil,
        postIndexCompactionCount: Int? = nil,
        geometryDeviationCount: Int = 0
    ) {
        self.committedTransactionCount = max(0, committedTransactionCount)
        self.supersededTransactionCount = max(0, supersededTransactionCount)
        self.failedTransactionCount = max(0, failedTransactionCount)
        self.lastFailureStage = lastFailureStage
        self.semanticAttributedDocumentBuildCount = max(0, semanticAttributedDocumentBuildCount)
        self.semanticAttributedDocumentReuseCount = max(0, semanticAttributedDocumentReuseCount)
        self.candidateIndexingPassCount = max(0, candidateIndexingPassCount ?? committedTransactionCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount ?? committedTransactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
    }
}

@MainActor
package struct NovelTextLayoutRuntimeAdapterInput {
    var preparedInput: NovelTextLayoutPreparedInput
    var precomputedResult: NovelTextLayoutResult?
    var settings: ReaderAppearanceSettings
    var layout: ReaderContainerLayout
    var cachedSemanticAttributedDocument: NSAttributedString?

    init(
        preparedInput: NovelTextLayoutPreparedInput,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        cachedSemanticAttributedDocument: NSAttributedString?,
        precomputedResult: NovelTextLayoutResult? = nil
    ) {
        self.preparedInput = preparedInput
        self.precomputedResult = precomputedResult
        self.settings = settings
        self.layout = layout
        self.cachedSemanticAttributedDocument = cachedSemanticAttributedDocument
    }
}

@MainActor
package final class NovelTextLayoutRuntimeCandidate {
    let result: NovelTextLayoutResult?
    let semanticAttributedDocument: NSAttributedString?
    let reusedSemanticAttributedDocument: Bool
    let fullDocumentLayoutPassCount: Int
    let postIndexCompactionCount: Int
    let geometryDeviationCount: Int
    let ownsAuthoritativeIndex: Bool

#if canImport(UIKit)
    let textContentStorage: NSTextContentStorage?
    let textLayoutManager: NSTextLayoutManager?
    let textContainer: NSTextContainer?
    let textViewportLayoutController: NSTextViewportLayoutController?
    let textViewportLayoutDelegate: NovelTextViewportLayoutDelegate?
#endif

    init(
        result: NovelTextLayoutResult? = nil,
        semanticAttributedDocument: NSAttributedString? = nil,
        reusedSemanticAttributedDocument: Bool = false,
        fullDocumentLayoutPassCount: Int = 1,
        postIndexCompactionCount: Int = 1,
        geometryDeviationCount: Int = 0,
        ownsAuthoritativeIndex: Bool = false
    ) {
        self.result = result
        self.semanticAttributedDocument = semanticAttributedDocument
        self.reusedSemanticAttributedDocument = reusedSemanticAttributedDocument
        self.fullDocumentLayoutPassCount = max(0, fullDocumentLayoutPassCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
        self.ownsAuthoritativeIndex = ownsAuthoritativeIndex
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
        textViewportLayoutController = nil
        textViewportLayoutDelegate = nil
#endif
    }

#if canImport(UIKit)
    init(
        result: NovelTextLayoutResult? = nil,
        semanticAttributedDocument: NSAttributedString? = nil,
        reusedSemanticAttributedDocument: Bool = false,
        fullDocumentLayoutPassCount: Int = 1,
        postIndexCompactionCount: Int = 1,
        geometryDeviationCount: Int = 0,
        ownsAuthoritativeIndex: Bool = false,
        textContentStorage: NSTextContentStorage?,
        textLayoutManager: NSTextLayoutManager?,
        textContainer: NSTextContainer?,
        textViewportLayoutController: NSTextViewportLayoutController?,
        textViewportLayoutDelegate: NovelTextViewportLayoutDelegate?
    ) {
        self.result = result
        self.semanticAttributedDocument = semanticAttributedDocument
        self.reusedSemanticAttributedDocument = reusedSemanticAttributedDocument
        self.fullDocumentLayoutPassCount = max(0, fullDocumentLayoutPassCount)
        self.postIndexCompactionCount = max(0, postIndexCompactionCount)
        self.geometryDeviationCount = max(0, geometryDeviationCount)
        self.ownsAuthoritativeIndex = ownsAuthoritativeIndex
        self.textContentStorage = textContentStorage
        self.textLayoutManager = textLayoutManager
        self.textContainer = textContainer
        self.textViewportLayoutController = textViewportLayoutController
        self.textViewportLayoutDelegate = textViewportLayoutDelegate
    }
#endif
}

#if canImport(UIKit)
@MainActor
final class NovelTextViewportLayoutDelegate: NSObject, NSTextViewportLayoutControllerDelegate {
    nonisolated(unsafe) private var viewportBounds: CGRect

    init(viewportBounds: CGRect) {
        self.viewportBounds = viewportBounds
    }

    func updateViewportBounds(_ viewportBounds: CGRect) {
        self.viewportBounds = viewportBounds
    }

    nonisolated func viewportBounds(
        for textViewportLayoutController: NSTextViewportLayoutController
    ) -> CGRect {
        viewportBounds
    }

    nonisolated func textViewportLayoutController(
        _ textViewportLayoutController: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        _ = textLayoutFragment
    }
}
#endif

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
package protocol NovelTextLayoutRuntimeAdapter: AnyObject {
    func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate
}

@MainActor
package final class DefaultNovelTextLayoutRuntimeAdapter: NovelTextLayoutRuntimeAdapter {
    package func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate {
#if canImport(UIKit)
        let viewportContext = input.preparedInput.viewportContextSeed
        guard !viewportContext.document.text.isEmpty else {
            let result = try input.precomputedResult ?? NovelTextLayout.result(
                from: input.preparedInput,
                surfaceRanges: []
            )
            return NovelTextLayoutRuntimeCandidate(
                result: result,
                fullDocumentLayoutPassCount: 0,
                postIndexCompactionCount: 1,
                ownsAuthoritativeIndex: input.precomputedResult == nil
            )
        }
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
            attributedDocument = ReaderAttributedTextFactory.makeAttributedDocument(
                from: input.preparedInput
            )
        }
        guard attributedDocument.string == viewportContext.document.text else {
            throw NovelTextLayoutFailure.offsetMapping
        }
        contentStorage.textStorage?.setAttributedString(attributedDocument)
        let surfaceSize: CGSize = if input.settings.readingMode == .vertical {
            CGSize(
                width: contentWidth,
                height: max(input.layout.readableFrame.height, 1)
            )
        } else {
            CGSize(
                width: contentWidth,
                height: max(input.layout.readableFrame.height, 1)
            )
        }
        var surfaceRanges = try Self.indexSurfaceRanges(
            attributedDocument: attributedDocument,
            contentStorage: contentStorage,
            layoutManager: layoutManager,
            surfaceSize: surfaceSize,
            semanticBreakOffsets: input.settings.readingMode == .paged
                ? Self.semanticSurfaceBreakOffsets(for: input.preparedInput)
                : []
        )
        if input.settings.readingMode == .vertical {
            surfaceRanges = Self.splitSurfaceRangesAtSemanticBreaks(
                surfaceRanges,
                breakOffsets: Self.semanticSurfaceBreakOffsets(for: input.preparedInput),
                attributedDocument: attributedDocument,
                contentStorage: contentStorage,
                layoutManager: layoutManager
            )
        }
        var result = try input.precomputedResult ?? NovelTextLayout.result(
            from: input.preparedInput,
            surfaceRanges: surfaceRanges
        )
        result.fingerprints.font = ReaderAttributedTextFactory.resolvedFontFingerprint(
            settings: input.settings
        )
        let platformName = "UIKit"
        result.fingerprints.platform = [
            ProcessInfo.processInfo.operatingSystemVersionString,
            platformName,
        ].joined(separator: "|")
        result.fingerprints.textKitImplementation = "NSTextLayoutManager-TextKit2-v1"
        let initialClipRect = surfaceRanges
            .prefix(2)
            .compactMap(\.frozenGeometry)
            .reduce(CGRect.null) { partial, geometry in
                partial.union(
                    CGRect(
                        x: 0,
                        y: geometry.documentClipMinY,
                        width: contentWidth,
                        height: geometry.documentClipMaxY - geometry.documentClipMinY
                    )
                )
            }
        let viewportLayoutController = layoutManager.textViewportLayoutController
        let viewportLayoutDelegate = NovelTextViewportLayoutDelegate(
            viewportBounds: initialClipRect.isNull
                ? CGRect(
                    origin: .zero,
                    size: CGSize(
                        width: contentWidth,
                        height: max(input.layout.readableFrame.height * 2, 1)
                    )
                )
                : initialClipRect
        )
        viewportLayoutController.delegate = viewportLayoutDelegate
        let geometryDeviationCount = try Self.validateRematerializedGeometry(
            surfaceRanges: Array(surfaceRanges.prefix(2)),
            attributedDocument: attributedDocument,
            contentStorage: contentStorage,
            layoutManager: layoutManager
        )
        guard geometryDeviationCount == 0 else {
            throw NovelTextLayoutFailure.geometryValidation
        }
        return NovelTextLayoutRuntimeCandidate(
            result: result,
            semanticAttributedDocument: attributedDocument,
            reusedSemanticAttributedDocument: reusesSemanticDocument,
            fullDocumentLayoutPassCount: 1,
            postIndexCompactionCount: 1,
            geometryDeviationCount: geometryDeviationCount,
            ownsAuthoritativeIndex: input.precomputedResult == nil,
            textContentStorage: contentStorage,
            textLayoutManager: layoutManager,
            textContainer: container,
            textViewportLayoutController: viewportLayoutController,
            textViewportLayoutDelegate: viewportLayoutDelegate
        )
#else
        let result = input.precomputedResult
        ?? NovelTextLayoutResult(
            viewportContext: input.preparedInput.viewportContextSeed,
            viewportIndex: NovelTextViewportIndex(
                documentView: input.preparedInput.document.view,
                readingMode: input.settings.readingMode,
                surfaces: [],
                chapters: []
            )
        )
        return NovelTextLayoutRuntimeCandidate(result: result)
#endif
    }

#if canImport(UIKit)
    private static func indexSurfaceRanges(
        attributedDocument: NSAttributedString,
        contentStorage: NSTextContentStorage,
        layoutManager: NSTextLayoutManager,
        surfaceSize: CGSize,
        semanticBreakOffsets: Set<Int> = []
    ) throws -> [NovelTextViewportDocumentSurfaceRange] {
        guard surfaceSize.width >= 120, surfaceSize.height > 0 else {
            throw NovelTextLayoutFailure.textKitIndexing
        }
        let documentRange = contentStorage.documentRange
        layoutManager.ensureLayout(for: documentRange)

        var segments: [NovelTextSurfaceLayoutFragment] = []
        let documentStart = contentStorage.documentRange.location
        layoutManager.enumerateTextLayoutFragments(
            from: documentRange.location,
            options: []
        ) { fragment in
            let fragmentStart = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard fragmentStart != NSNotFound else { return true }
            for lineFragment in fragment.textLineFragments {
                let characterRange = NSRange(
                    location: fragmentStart + lineFragment.characterRange.location,
                    length: lineFragment.characterRange.length
                )
                guard characterRange.location >= 0,
                      characterRange.length > 0,
                      characterRange.location < attributedDocument.length,
                      !lineTextIsPaginationWhitespace(
                          attributedDocument: attributedDocument,
                          characterRange: characterRange
                      ) else {
                    continue
                }
                let lineBounds = lineFragment.typographicBounds
                let rect = CGRect(
                    x: fragment.layoutFragmentFrame.minX + lineBounds.minX,
                    y: fragment.layoutFragmentFrame.minY + lineBounds.minY,
                    width: lineBounds.width,
                    height: lineBounds.height
                ).insetBy(dx: 0, dy: -1)
                guard rect.origin.x.isFinite,
                      rect.origin.y.isFinite,
                      rect.width.isFinite,
                      rect.height.isFinite,
                      rect.height > 0 else {
                    continue
                }
                segments.append(
                    NovelTextSurfaceLayoutFragment(
                        characterRange: characterRange,
                        rect: rect
                    )
                )
            }
            return true
        }

        let breakOffsets = Set(
            semanticBreakOffsets.compactMap {
                utf16Offset(in: attributedDocument.string, characterOffset: $0)
            }
        )
        let ranges = NovelTextSurfaceFragmentPartitioner.partition(
            segments,
            surfaceHeight: surfaceSize.height,
            breakOffsets: breakOffsets
        ).compactMap { page in
            viewportDocumentPageRange(
                from: attributedDocument,
                range: page.characterRange,
                clipRect: page.clipRect
            )
        }
        guard attributedDocument.length == 0 || !ranges.isEmpty else {
            throw NovelTextLayoutFailure.textKitIndexing
        }
        return ranges
    }

    private static func semanticSurfaceBreakOffsets(
        for input: NovelTextLayoutPreparedInput
    ) -> Set<Int> {
        var breakOffsets = Set<Int>()
        var previousTextSegment: NovelAnnotatedSegment?
        var sawImageSincePreviousText = false
        let viewportDocument = input.viewportContextSeed.document

        for annotatedSegment in input.annotatedSegments {
            switch annotatedSegment.segment {
            case .image:
                if previousTextSegment != nil {
                    sawImageSincePreviousText = true
                }

            case .text:
                defer {
                    previousTextSegment = annotatedSegment
                    sawImageSincePreviousText = false
                }
                guard let previousTextSegment else { continue }
                let chapterChanged = previousTextSegment.chapterOrdinal != annotatedSegment.chapterOrdinal ||
                    previousTextSegment.chapterTitle != annotatedSegment.chapterTitle
                guard sawImageSincePreviousText || chapterChanged,
                      let range = viewportDocument.textRangesBySegment[annotatedSegment.index],
                      range.startOffset > 0 else {
                    continue
                }
                breakOffsets.insert(range.startOffset)
            }
        }

        return breakOffsets
    }

    private static func splitSurfaceRangesAtSemanticBreaks(
        _ surfaceRanges: [NovelTextViewportDocumentSurfaceRange],
        breakOffsets: Set<Int>,
        attributedDocument: NSAttributedString,
        contentStorage: NSTextContentStorage,
        layoutManager: NSTextLayoutManager
    ) -> [NovelTextViewportDocumentSurfaceRange] {
        guard !surfaceRanges.isEmpty, !breakOffsets.isEmpty else { return surfaceRanges }
        var splitRanges: [NovelTextViewportDocumentSurfaceRange] = []

        for surfaceRange in surfaceRanges {
            let cuts = ([surfaceRange.startOffset] + breakOffsets.filter {
                $0 > surfaceRange.startOffset && $0 < surfaceRange.endOffset
            }.sorted() + [surfaceRange.endOffset])
            guard cuts.count > 2 else {
                splitRanges.append(surfaceRange)
                continue
            }

            for index in 0..<(cuts.count - 1) {
                let startOffset = cuts[index]
                let endOffset = cuts[index + 1]
                guard let clipRect = lineClipRect(
                    startOffset: startOffset,
                    endOffset: endOffset,
                    attributedDocument: attributedDocument,
                    contentStorage: contentStorage,
                    layoutManager: layoutManager
                ),
                    let splitRange = viewportDocumentPageRange(
                        from: attributedDocument,
                        range: NSRange(location: startOffset, length: endOffset - startOffset),
                        clipRect: clipRect
                    ) else {
                    continue
                }
                splitRanges.append(splitRange)
            }
        }

        return splitRanges.isEmpty ? surfaceRanges : splitRanges
    }

    private static func lineClipRect(
        startOffset: Int,
        endOffset: Int,
        attributedDocument: NSAttributedString,
        contentStorage: NSTextContentStorage,
        layoutManager: NSTextLayoutManager
    ) -> CGRect? {
        guard startOffset >= 0, endOffset > startOffset,
              let startLocation = contentStorage.location(
                contentStorage.documentRange.location,
                offsetBy: startOffset
              ) else {
            return nil
        }

        let documentStart = contentStorage.documentRange.location
        var clipRect = CGRect.null
        layoutManager.enumerateTextLayoutFragments(
            from: startLocation,
            options: []
        ) { fragment in
            let fragmentStart = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard fragmentStart != NSNotFound else { return false }
            var shouldContinue = true
            for lineFragment in fragment.textLineFragments {
                let lineStart = fragmentStart + lineFragment.characterRange.location
                let lineEnd = lineStart + lineFragment.characterRange.length
                if lineStart >= endOffset {
                    shouldContinue = false
                    break
                }
                guard lineStart >= startOffset, lineEnd > lineStart else {
                    continue
                }
                guard !lineTextIsPaginationWhitespace(
                    attributedDocument: attributedDocument,
                    characterRange: NSRange(location: lineStart, length: lineFragment.characterRange.length)
                ) else {
                    continue
                }
                let lineBounds = lineFragment.typographicBounds
                let rect = CGRect(
                    x: fragment.layoutFragmentFrame.minX + lineBounds.minX,
                    y: fragment.layoutFragmentFrame.minY + lineBounds.minY,
                    width: lineBounds.width,
                    height: lineBounds.height
                ).insetBy(dx: 0, dy: -1)
                guard rect.origin.x.isFinite,
                      rect.origin.y.isFinite,
                      rect.width.isFinite,
                      rect.height.isFinite,
                      rect.height > 0 else {
                    continue
                }
                clipRect = clipRect.union(rect)
            }
            return shouldContinue
        }
        return clipRect.isNull ? nil : clipRect
    }

    fileprivate static func validateRematerializedGeometry(
        surfaceRanges: [NovelTextViewportDocumentSurfaceRange],
        attributedDocument: NSAttributedString,
        contentStorage: NSTextContentStorage,
        layoutManager: NSTextLayoutManager
    ) throws -> Int {
        let documentStart = contentStorage.documentRange.location
        var deviationCount = 0
        for surfaceRange in surfaceRanges {
            guard let geometry = surfaceRange.frozenGeometry,
                  let utf16Range = utf16Range(
                      in: attributedDocument.string,
                      characterStart: surfaceRange.startOffset,
                      characterEnd: surfaceRange.endOffset
                  ),
                  let start = contentStorage.location(
                      documentStart,
                      offsetBy: utf16Range.location
                  ),
                  let end = contentStorage.location(
                      start,
                      offsetBy: utf16Range.length
                  ),
                  let textRange = NSTextRange(location: start, end: end) else {
                throw NovelTextLayoutFailure.geometryValidation
            }
            var rematerializedRect = CGRect.null
            layoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: []
            ) { _, rect, _, _ in
                if rect.width.isFinite, rect.height.isFinite, rect.height > 0 {
                    rematerializedRect = rematerializedRect.union(rect)
                }
                return true
            }
            let tolerance: CGFloat = 1
            if rematerializedRect.isNull ||
                rematerializedRect.minY < geometry.documentClipMinY - tolerance ||
                rematerializedRect.maxY - geometry.documentClipMaxY > tolerance {
                deviationCount += 1
            }
        }
        return deviationCount
    }

    private static func utf16Range(
        in text: String,
        characterStart: Int,
        characterEnd: Int
    ) -> NSRange? {
        guard characterStart >= 0,
              characterEnd >= characterStart,
              let start = text.index(text.startIndex, offsetBy: characterStart, limitedBy: text.endIndex),
              let end = text.index(text.startIndex, offsetBy: characterEnd, limitedBy: text.endIndex) else {
            return nil
        }
        return NSRange(
            location: text.utf16.distance(from: text.utf16.startIndex, to: start.samePosition(in: text.utf16)!),
            length: text.utf16.distance(from: start.samePosition(in: text.utf16)!, to: end.samePosition(in: text.utf16)!)
        )
    }

    private static func utf16Offset(
        in text: String,
        characterOffset: Int
    ) -> Int? {
        guard characterOffset >= 0,
              let index = text.index(text.startIndex, offsetBy: characterOffset, limitedBy: text.endIndex),
              let utf16Index = index.samePosition(in: text.utf16) else {
            return nil
        }
        return text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
    }

    private static func nsRange(
        for textRange: NSTextRange,
        in contentManager: NSTextContentManager
    ) -> NSRange? {
        let documentStart = contentManager.documentRange.location
        let start = contentManager.offset(from: documentStart, to: textRange.location)
        let end = contentManager.offset(from: documentStart, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func viewportDocumentPageRange(
        from attributedText: NSAttributedString,
        range: NSRange,
        clipRect: CGRect
    ) -> NovelTextViewportDocumentSurfaceRange? {
        let text = attributedText.string
        let textLength = text.utf16.count
        let pageCharacterStart = max(0, min(range.location, textLength))
        let nextCharacterEnd = min(range.location + range.length, textLength)
        let trimmedEnd = max(
            trimmedUTF16Boundary(in: text, from: pageCharacterStart, to: nextCharacterEnd),
            pageCharacterStart
        )
        guard trimmedEnd > pageCharacterStart else { return nil }

        let candidateText = attributedText.attributedSubstring(
            from: NSRange(location: pageCharacterStart, length: trimmedEnd - pageCharacterStart)
        ).string
        let trimmedLeadingText = trimmingLeadingPaginationWhitespace(candidateText)
        let leadingTrimmed = candidateText.utf16.count - trimmedLeadingText.utf16.count
        let effectiveStart = pageCharacterStart + leadingTrimmed
        guard effectiveStart < trimmedEnd,
              let characterStart = characterOffset(in: text, fromUTF16Offset: effectiveStart),
              let characterEnd = characterOffset(in: text, fromUTF16Offset: trimmedEnd),
              characterEnd > characterStart else {
            return nil
        }

        return NovelTextViewportDocumentSurfaceRange(
            startOffset: characterStart,
            endOffset: characterEnd,
            frozenGeometry: NovelTextViewportFrozenGeometry(
                documentStartOffset: characterStart,
                documentEndOffset: characterEnd,
                documentClipMinY: clipRect.minY,
                documentClipMaxY: clipRect.maxY,
                contentHeight: NovelTextViewportFrozenGeometry.surfaceContentHeight(
                    forDocumentClipRect: clipRect
                )
            )
        )
    }

    private static func lineTextIsPaginationWhitespace(
        attributedDocument: NSAttributedString,
        characterRange: NSRange
    ) -> Bool {
        let safeRange = NSRange(
            location: max(0, min(characterRange.location, attributedDocument.length)),
            length: max(0, min(characterRange.length, attributedDocument.length - max(0, min(characterRange.location, attributedDocument.length))))
        )
        guard safeRange.length > 0 else { return true }
        return attributedDocument.attributedSubstring(from: safeRange)
            .string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func trimmedUTF16Boundary(
        in text: String,
        from start: Int,
        to candidateEnd: Int
    ) -> Int {
        guard candidateEnd > start else { return start }
        let nsText = text as NSString
        var end = candidateEnd
        while end > start {
            let character = nsText.substring(with: NSRange(location: end - 1, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func characterOffset(in text: String, fromUTF16Offset offset: Int) -> Int? {
        guard offset >= 0, offset <= text.utf16.count,
              let utf16Index = text.utf16.index(
                  text.utf16.startIndex,
                  offsetBy: offset,
                  limitedBy: text.utf16.endIndex
              ),
              let stringIndex = String.Index(utf16Index, within: text) else {
            return nil
        }
        return text.distance(from: text.startIndex, to: stringIndex)
    }

    private static func trimmingLeadingPaginationWhitespace(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text[...]
        while let first = result.first, first.isWhitespace {
            result.removeFirst()
        }
        return String(result)
    }
#endif
}

@MainActor
public final class NovelTextViewportDisplayReference {
    public let surfaceIdentity: NovelReaderSurfaceIdentity
    package var surfaceOrdinal: Int { surfaceIdentity.ordinal }
    public var generation: UInt64 { surfaceIdentity.generation }

    private weak var runtimeOwner: NovelTextViewportRuntimeOwner?

    init(
        runtimeOwner: NovelTextViewportRuntimeOwner,
        surfaceIdentity: NovelReaderSurfaceIdentity
    ) {
        self.runtimeOwner = runtimeOwner
        self.surfaceIdentity = surfaceIdentity
    }

    public var isStale: Bool {
        guard let runtimeOwner else { return true }
        return !runtimeOwner.isCurrent(surfaceIdentity)
    }

    package func viewportSample(referencePoint: CGPoint) -> NovelTextViewportSample? {
#if canImport(UIKit)
        runtimeOwner?.viewportSample(
            surfaceIdentity: surfaceIdentity,
            referencePoint: referencePoint
        )
#else
        nil
#endif
    }

    package func referenceY(for position: ReaderResumePoint) -> CGFloat? {
#if canImport(UIKit)
        runtimeOwner?.referenceY(
            surfaceIdentity: surfaceIdentity,
            position: position
        )
#else
        nil
#endif
    }

    package func selectionAnchor(at referencePoint: CGPoint) -> NovelTextSelectionAnchor? {
#if canImport(UIKit)
        runtimeOwner?.selectionAnchor(
            surfaceIdentity: surfaceIdentity,
            referencePoint: referencePoint
        )
#else
        nil
#endif
    }

    package func expandedSelectionRange(
        around anchor: NovelTextSelectionAnchor
    ) -> NovelTextSelectionRange? {
        runtimeOwner?.expandedSelectionRange(around: anchor)
    }

    package func selectionRange(
        from start: NovelTextSelectionAnchor,
        to end: NovelTextSelectionAnchor
    ) -> NovelTextSelectionRange? {
        runtimeOwner?.selectionRange(from: start, to: end)
    }

    package func selectionRects(
        for selectionRange: NovelTextSelectionRange
    ) -> [CGRect] {
#if canImport(UIKit)
        runtimeOwner?.selectionRects(
            for: selectionRange,
            surfaceIdentity: surfaceIdentity
        ) ?? []
#else
        []
#endif
    }

    package func selectedText(
        for selectionRange: NovelTextSelectionRange
    ) -> String? {
        runtimeOwner?.selectedText(for: selectionRange)
    }

#if canImport(UIKit)
    public func draw(in context: CGContext, bounds: CGRect) {
        drawBlockBackgrounds(in: context, bounds: bounds)
        drawText(in: context, bounds: bounds)
    }

    public func drawBlockBackgrounds(in context: CGContext, bounds: CGRect) {
        runtimeOwner?.drawBlockBackgrounds(
            surfaceIdentity: surfaceIdentity,
            in: context,
            bounds: bounds
        )
    }

    public func drawText(in context: CGContext, bounds: CGRect) {
        runtimeOwner?.draw(
            surfaceIdentity: surfaceIdentity,
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
    let document: NovelReaderProjection?
    let settings: ReaderAppearanceSettings
    let layout: ReaderContainerLayout
    private(set) var semanticAttributedDocument: NSAttributedString?
    let reusedSemanticAttributedDocument: Bool
    let fullDocumentLayoutPassCount: Int
    let postIndexCompactionCount: Int
    private(set) var geometryDeviationCount: Int
    let ownsAuthoritativeIndex: Bool
    private var state = State.pending

#if canImport(UIKit)
    private(set) var textContentStorage: NSTextContentStorage?
    private(set) var textLayoutManager: NSTextLayoutManager?
    private(set) var textContainer: NSTextContainer?
    private(set) var textViewportLayoutController: NSTextViewportLayoutController?
    private(set) var textViewportLayoutDelegate: NovelTextViewportLayoutDelegate?
#endif

    init(
        generation: UInt64,
        result: NovelTextLayoutResult,
        document: NovelReaderProjection?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        candidate: NovelTextLayoutRuntimeCandidate
    ) {
        self.generation = generation
        self.result = result
        self.document = document
        self.settings = settings
        self.layout = layout
        semanticAttributedDocument = candidate.semanticAttributedDocument
        reusedSemanticAttributedDocument = candidate.reusedSemanticAttributedDocument
        fullDocumentLayoutPassCount = candidate.fullDocumentLayoutPassCount
        postIndexCompactionCount = candidate.postIndexCompactionCount
        geometryDeviationCount = candidate.geometryDeviationCount
        ownsAuthoritativeIndex = candidate.ownsAuthoritativeIndex
#if canImport(UIKit)
        textContentStorage = candidate.textContentStorage
        textLayoutManager = candidate.textLayoutManager
        textContainer = candidate.textContainer
        textViewportLayoutController = candidate.textViewportLayoutController
        textViewportLayoutDelegate = candidate.textViewportLayoutDelegate
#endif
    }

    func markCommitted() -> Bool {
        guard case .pending = state else { return false }
        state = .committed
        return true
    }

    func supersede() -> Bool {
        guard case .pending = state else { return false }
        state = .superseded
        semanticAttributedDocument = nil
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
        textViewportLayoutController = nil
        textViewportLayoutDelegate = nil
#endif
        return true
    }

    fileprivate func prepareInitialViewport(around surfaceOrdinal: Int) throws {
#if canImport(UIKit)
        guard ownsAuthoritativeIndex else { return }
        _ = surfaceOrdinal
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
    private var document: NovelReaderProjection?
    private var settings = ReaderAppearanceSettings()
    private var layout = ReaderContainerLayout(width: 1, height: 1)
    private var visibleSurfaceOrdinals = Set<Int>()
    private var semanticAttributedDocumentCache: NSAttributedString?
    private var transactionDiagnostics = NovelTextViewportRuntimeTransactionDiagnostics()
    private var peakActivePlusCandidateGraphCount = 0
    private var viewportUpdateCount = 0
    private var rematerializedSurfaceCount = 0
    private var drawingAccessCount = 0
    private var staleDrawingAttemptCount = 0
    private var lastDrawnSurfaceIdentity: NovelReaderSurfaceIdentity?
    private var lastDrawnDocumentRange: Range<Int>?
    private let adapter: any NovelTextLayoutRuntimeAdapter
    private var pendingTransaction: NovelTextViewportRuntimeTransaction?

#if canImport(UIKit)
    private var textContentStorage: NSTextContentStorage?
    private var textLayoutManager: NSTextLayoutManager?
    private var textContainer: NSTextContainer?
    private var textViewportLayoutController: NSTextViewportLayoutController?
    private var textViewportLayoutDelegate: NovelTextViewportLayoutDelegate?
#endif

    init(adapter: any NovelTextLayoutRuntimeAdapter = DefaultNovelTextLayoutRuntimeAdapter()) {
        self.adapter = adapter
    }

    var diagnostics: NovelTextViewportRuntimeDiagnostics {
#if canImport(UIKit)
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: textContentStorage == nil ? 0 : 1,
            activeLayoutManagerCount: textLayoutManager == nil ? 0 : 1,
            perSurfaceTextKitDocumentCount: 0,
            semanticAttributedDocumentCacheCount: semanticAttributedDocumentCache == nil ? 0 : 1,
            currentActivePlusCandidateGraphCount: activeTextKitGraphCount + pendingTextKitGraphCount,
            peakActivePlusCandidateGraphCount: peakActivePlusCandidateGraphCount,
            postCommitFullLayoutCount: 0,
            viewportUpdateCount: viewportUpdateCount,
            rematerializedSurfaceCount: rematerializedSurfaceCount,
            drawingAccessCount: drawingAccessCount,
            staleDrawingAttemptCount: staleDrawingAttemptCount,
            lastDrawnSurfaceIdentity: lastDrawnSurfaceIdentity,
            lastDrawnDocumentRange: lastDrawnDocumentRange
        )
#else
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: 0,
            activeLayoutManagerCount: 0,
            perSurfaceTextKitDocumentCount: 0,
            semanticAttributedDocumentCacheCount: semanticAttributedDocumentCache == nil ? 0 : 1,
            currentActivePlusCandidateGraphCount: pendingTextKitGraphCount,
            peakActivePlusCandidateGraphCount: peakActivePlusCandidateGraphCount,
            postCommitFullLayoutCount: 0,
            viewportUpdateCount: viewportUpdateCount,
            rematerializedSurfaceCount: rematerializedSurfaceCount,
            drawingAccessCount: drawingAccessCount,
            staleDrawingAttemptCount: staleDrawingAttemptCount,
            lastDrawnSurfaceIdentity: lastDrawnSurfaceIdentity,
            lastDrawnDocumentRange: lastDrawnDocumentRange
        )
#endif
    }

    var runtimeTransactionDiagnostics: NovelTextViewportRuntimeTransactionDiagnostics {
        transactionDiagnostics
    }

    var currentResult: NovelTextLayoutResult? {
        result
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

    func prepareTransaction(
        preparedInput: NovelTextLayoutPreparedInput
    ) throws -> NovelTextViewportRuntimeTransaction {
        supersedePendingTransaction()
        pendingTransaction = nil
        let generation = nextGeneration
        nextGeneration &+= 1
        let candidate: NovelTextLayoutRuntimeCandidate
        do {
            candidate = try adapter.prepareCandidate(
                input: NovelTextLayoutRuntimeAdapterInput(
                    preparedInput: preparedInput,
                    settings: preparedInput.settings,
                    layout: preparedInput.layout,
                    cachedSemanticAttributedDocument: reusableSemanticAttributedDocument(
                        for: preparedInput
                    )
                )
            )
        } catch let failure as NovelTextLayoutFailure {
            recordFailure(failure)
            throw failure
        } catch {
            let failure = NovelTextLayoutFailure.textKitIndexing
            recordFailure(failure)
            throw failure
        }
        guard let result = candidate.result else {
            let failure = NovelTextLayoutFailure.textKitIndexing
            recordFailure(failure)
            throw failure
        }
        peakActivePlusCandidateGraphCount = max(
            peakActivePlusCandidateGraphCount,
            activeTextKitGraphCount + candidate.textKitGraphCount
        )
        let transaction = NovelTextViewportRuntimeTransaction(
            generation: generation,
            result: result,
            document: preparedInput.document,
            settings: preparedInput.settings,
            layout: preparedInput.layout,
            candidate: candidate
        )
        pendingTransaction = transaction
        return transaction
    }

    @discardableResult
    func commit(_ transaction: NovelTextViewportRuntimeTransaction) -> Bool {
        guard pendingTransaction === transaction,
              transaction.markCommitted() else { return false }
        pendingTransaction = nil
        activeGeneration = transaction.generation
        result = transaction.result
        document = transaction.document
        settings = transaction.settings
        layout = transaction.layout
        semanticAttributedDocumentCache = transaction.semanticAttributedDocument
#if canImport(UIKit)
        textContentStorage = transaction.textContentStorage
        textLayoutManager = transaction.textLayoutManager
        textContainer = transaction.textContainer
        textViewportLayoutController = transaction.textViewportLayoutController
        textViewportLayoutDelegate = transaction.textViewportLayoutDelegate
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
        return true
    }

    func prepareInitialViewport(
        for transaction: NovelTextViewportRuntimeTransaction,
        around surfaceOrdinal: Int
    ) throws {
        guard pendingTransaction === transaction else { return }
        do {
            try transaction.prepareInitialViewport(around: surfaceOrdinal)
        } catch let failure as NovelTextLayoutFailure {
            _ = transaction.supersede()
            pendingTransaction = nil
            recordFailure(failure)
            throw failure
        } catch {
            _ = transaction.supersede()
            pendingTransaction = nil
            let failure = NovelTextLayoutFailure.geometryValidation
            recordFailure(failure)
            throw failure
        }
    }

    private func reusableSemanticAttributedDocument(
        for preparedInput: NovelTextLayoutPreparedInput
    ) -> NSAttributedString? {
        guard result?.viewportContext.document == preparedInput.viewportContextSeed.document,
              settings == preparedInput.settings else {
            return nil
        }
        return semanticAttributedDocumentCache
    }

    func release() {
        supersedePendingTransaction()
        pendingTransaction = nil
        result = nil
        document = nil
        visibleSurfaceOrdinals.removeAll(keepingCapacity: false)
        semanticAttributedDocumentCache = nil
        peakActivePlusCandidateGraphCount = 0
        viewportUpdateCount = 0
        rematerializedSurfaceCount = 0
        drawingAccessCount = 0
        staleDrawingAttemptCount = 0
        lastDrawnSurfaceIdentity = nil
        lastDrawnDocumentRange = nil
#if canImport(UIKit)
        textContentStorage = nil
        textLayoutManager = nil
        textContainer = nil
        textViewportLayoutController = nil
        textViewportLayoutDelegate = nil
#endif
    }

    private func supersedePendingTransaction() {
        guard pendingTransaction?.supersede() == true else { return }
        transactionDiagnostics.supersededTransactionCount += 1
    }

    private func recordFailure(_ failure: NovelTextLayoutFailure) {
        transactionDiagnostics.failedTransactionCount += 1
        transactionDiagnostics.lastFailureStage = failure.stage
    }

    func handleMemoryPressure() {
        supersedePendingTransaction()
        pendingTransaction = nil
        semanticAttributedDocumentCache = nil
    }

    func displayReference(for surfaceIdentity: NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference? {
        guard isCurrent(surfaceIdentity) else {
            return nil
        }
        return NovelTextViewportDisplayReference(
            runtimeOwner: self,
            surfaceIdentity: surfaceIdentity
        )
    }

    func updateVisibleSurfaceIdentities(_ surfaceIdentities: [NovelReaderSurfaceIdentity]) {
        let visibleOrdinals = Set<Int>(surfaceIdentities.compactMap { surfaceIdentity -> Int? in
            guard surfaceIdentity.generation == activeGeneration,
                  result?.viewportIndex.surfaces.contains(where: { $0.surfaceOrdinal == surfaceIdentity.ordinal }) == true else {
                return nil
            }
            return surfaceIdentity.ordinal
        })
        let nextVisibleSurfaceOrdinals = preheatedSurfaceOrdinals(around: visibleOrdinals)
        guard visibleSurfaceOrdinals != nextVisibleSurfaceOrdinals else { return }
        visibleSurfaceOrdinals = nextVisibleSurfaceOrdinals
        viewportUpdateCount += 1
        rematerializedSurfaceCount = visibleSurfaceOrdinals.count
#if canImport(UIKit)
        updateTextKitViewport()
#endif
    }

    private func preheatedSurfaceOrdinals(around visibleOrdinals: Set<Int>) -> Set<Int> {
        guard let pages = result?.viewportIndex.surfaces, !visibleOrdinals.isEmpty else { return [] }
        let validOrdinals = Set(pages.map(\.surfaceOrdinal))
        var preheated = visibleOrdinals.intersection(validOrdinals)
        if let first = visibleOrdinals.min(), validOrdinals.contains(first - 1) {
            preheated.insert(first - 1)
        }
        if let last = visibleOrdinals.max(), validOrdinals.contains(last + 1) {
            preheated.insert(last + 1)
        }
        return preheated
    }

#if canImport(UIKit)
    private func updateTextKitViewport() {
    }

    private func prepareSurfaceForDrawing(_ surfaceOrdinal: Int) {
        if !visibleSurfaceOrdinals.contains(surfaceOrdinal) {
            visibleSurfaceOrdinals = preheatedSurfaceOrdinals(around: [surfaceOrdinal])
            viewportUpdateCount += 1
            rematerializedSurfaceCount = visibleSurfaceOrdinals.count
        }
        updateTextKitViewport()
    }
#endif

    func isCurrent(_ surfaceIdentity: NovelReaderSurfaceIdentity) -> Bool {
        surfaceIdentity.generation == activeGeneration &&
            result?.viewportIndex.surfaces.contains(where: {
                $0.surfaceOrdinal == surfaceIdentity.ordinal
            }) == true
    }

#if canImport(UIKit)
    func viewportSample(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        referencePoint: CGPoint
    ) -> NovelTextViewportSample? {
        let surfaceOrdinal = surfaceIdentity.ordinal
        guard isCurrent(surfaceIdentity),
        let result,
        let document,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceOrdinal }),
        let surfaceOriginY = surfaceOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let fragment = closestLayoutFragment(
            to: CGPoint(x: referencePoint.x, y: surfaceOriginY + referencePoint.y),
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
            y: surfaceOriginY + referencePoint.y - fragment.layoutFragmentFrame.minY
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
        guard let sample = result.viewportContext.document.sample(
            containingDocumentOffset: documentOffset,
            surfaceIdentity: surfaceIdentity,
            documentView: page.documentView,
            in: document
        ) else {
            return nearestTextSample(
                documentOffset: documentOffset,
                page: page,
                result: result,
                document: document
            )
        }
        return sample
    }

    func referenceY(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        position: ReaderResumePoint
    ) -> CGFloat? {
        let surfaceOrdinal = surfaceIdentity.ordinal
        guard isCurrent(surfaceIdentity),
        let result,
        let document,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceOrdinal }),
        let documentOffset = result.viewportContext.document.documentOffset(for: position, in: document),
        let surfaceOriginY = surfaceOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let location = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: documentOffset
        ),
        let fragment = textLayoutManager.textLayoutFragment(for: location),
        let lineFragment = fragment.textLineFragment(for: location, isUpstreamAffinity: true) else {
            return nil
        }
        if let frozenGeometry = page.frozenGeometry,
           (documentOffset < frozenGeometry.documentStartOffset || documentOffset >= frozenGeometry.documentEndOffset) {
            return nil
        }
        return fragment.layoutFragmentFrame.minY + lineFragment.typographicBounds.midY - surfaceOriginY
    }

    private func surfaceOriginY(
        page: NovelTextViewportIndexSurface,
        result: NovelTextLayoutResult,
        textContentStorage: NSTextContentStorage,
        textLayoutManager: NSTextLayoutManager
    ) -> CGFloat? {
        if let frozenGeometry = page.frozenGeometry {
            return frozenGeometry.pageLocalOriginY
        }
        guard let firstRange = page.ranges.first,
              let documentOffset = result.viewportContext.document.documentOffset(forSurfaceRange: firstRange),
              let pageLocation = textContentStorage.location(
                textContentStorage.documentRange.location,
                offsetBy: documentOffset
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
        page: NovelTextViewportIndexSurface,
        result: NovelTextLayoutResult,
        document: NovelReaderProjection
    ) -> NovelTextViewportSample? {
        page.nearestTextSample(
            toDocumentOffset: documentOffset,
            surfaceIdentity: NovelReaderSurfaceIdentity(
                generation: activeGeneration,
                ordinal: page.surfaceOrdinal
            ),
            viewportDocument: result.viewportContext.document,
            sourceDocument: document
        )
    }

    func selectionAnchor(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        referencePoint: CGPoint
    ) -> NovelTextSelectionAnchor? {
        guard let documentOffset = characterDocumentOffset(
            surfaceIdentity: surfaceIdentity,
            referencePoint: referencePoint
        ) else {
            return nil
        }
        return NovelTextSelectionAnchor(
            generation: surfaceIdentity.generation,
            documentOffset: documentOffset
        )
    }

    func selectionRects(
        for selectionRange: NovelTextSelectionRange,
        surfaceIdentity: NovelReaderSurfaceIdentity
    ) -> [CGRect] {
        guard selectionRange.generation == activeGeneration,
              isCurrent(surfaceIdentity),
              let result,
              let textContentStorage,
              let textLayoutManager,
              let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceIdentity.ordinal }),
              !page.ranges.isEmpty,
              let pageCharacterRange = characterRange(for: page, result: result),
              let intersection = intersection(selectionRange.range, pageCharacterRange),
              let utf16Range = utf16Range(in: result.viewportContext.document.text, characterRange: intersection),
              let start = textContentStorage.location(textContentStorage.documentRange.location, offsetBy: utf16Range.location),
              let end = textContentStorage.location(start, offsetBy: utf16Range.length),
              let textRange = NSTextRange(location: start, end: end),
              let surfaceOriginY = surfaceOriginY(
                  page: page,
                  result: result,
                  textContentStorage: textContentStorage,
                  textLayoutManager: textLayoutManager
              ) else {
            return []
        }

        let documentClipRange = page.frozenGeometry.map {
            CGRect(
                x: 0,
                y: $0.documentClipMinY,
                width: max(layout.readableFrame.width, 1),
                height: max($0.documentClipMaxY - $0.documentClipMinY, 1)
            )
        }
        var rects: [CGRect] = []
        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: []
        ) { _, rect, _, _ in
            var clippedRect = rect
            if let documentClipRange {
                clippedRect = clippedRect.intersection(documentClipRange)
            }
            guard !clippedRect.isNull,
                  clippedRect.width.isFinite,
                  clippedRect.height.isFinite,
                  clippedRect.width > 0,
                  clippedRect.height > 0 else {
                return true
            }
            rects.append(
                CGRect(
                    x: clippedRect.minX,
                    y: clippedRect.minY - surfaceOriginY,
                    width: clippedRect.width,
                    height: clippedRect.height
                )
            )
            return true
        }
        return rects
    }
#endif

    func expandedSelectionRange(
        around anchor: NovelTextSelectionAnchor
    ) -> NovelTextSelectionRange? {
        guard anchor.generation == activeGeneration,
              let text = result?.viewportContext.document.text,
              !text.isEmpty,
              let characterRange = selectableCharacterRange(around: anchor.documentOffset, in: text) else {
            return nil
        }
        return NovelTextSelectionRange(
            generation: anchor.generation,
            lowerBound: characterRange.lowerBound,
            upperBound: characterRange.upperBound
        )
    }

    func selectionRange(
        from start: NovelTextSelectionAnchor,
        to end: NovelTextSelectionAnchor
    ) -> NovelTextSelectionRange? {
        guard start.generation == activeGeneration,
              end.generation == activeGeneration,
              let text = result?.viewportContext.document.text else {
            return nil
        }
        let lowerBound = min(start.documentOffset, end.documentOffset)
        let upperBound = max(start.documentOffset, end.documentOffset)
        return NovelTextSelectionRange(
            generation: start.generation,
            lowerBound: min(max(lowerBound, 0), text.count),
            upperBound: min(max(upperBound, 0), text.count)
        )
    }

    func selectedText(for selectionRange: NovelTextSelectionRange) -> String? {
        guard selectionRange.generation == activeGeneration,
              let text = result?.viewportContext.document.text,
              let start = text.index(text.startIndex, offsetBy: selectionRange.lowerBound, limitedBy: text.endIndex),
              let end = text.index(text.startIndex, offsetBy: selectionRange.upperBound, limitedBy: text.endIndex),
              start < end else {
            return nil
        }
        return String(text[start..<end])
    }

#if canImport(UIKit)
    private func characterDocumentOffset(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        referencePoint: CGPoint
    ) -> Int? {
        let surfaceOrdinal = surfaceIdentity.ordinal
        guard isCurrent(surfaceIdentity),
              let result,
              let textContentStorage,
              let textLayoutManager,
              let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceOrdinal }),
              !page.ranges.isEmpty,
              let pageCharacterRange = characterRange(for: page, result: result),
              let surfaceOriginY = surfaceOriginY(
                  page: page,
                  result: result,
                  textContentStorage: textContentStorage,
                  textLayoutManager: textLayoutManager
              ),
              let fragment = closestLayoutFragment(
                  to: CGPoint(x: referencePoint.x, y: surfaceOriginY + referencePoint.y),
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
            y: surfaceOriginY + referencePoint.y - fragment.layoutFragmentFrame.minY
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
        let utf16Offset = fragmentStart + lineOffset
        guard let characterOffset = characterOffset(
            in: result.viewportContext.document.text,
            fromUTF16Offset: utf16Offset
        ) else {
            return nil
        }
        return min(max(characterOffset, pageCharacterRange.lowerBound), pageCharacterRange.upperBound)
    }
#endif

    private func characterRange(
        for page: NovelTextViewportIndexSurface,
        result: NovelTextLayoutResult
    ) -> Range<Int>? {
        if let frozenGeometry = page.frozenGeometry,
           frozenGeometry.documentEndOffset > frozenGeometry.documentStartOffset {
            return frozenGeometry.documentStartOffset..<frozenGeometry.documentEndOffset
        }
        let ranges = page.ranges.compactMap {
            result.viewportContext.document.documentOffsets(forSurfaceRange: $0)
        }
        guard let lowerBound = ranges.map(\.lowerBound).min(),
              let upperBound = ranges.map(\.upperBound).max(),
              upperBound > lowerBound else {
            return nil
        }
        return lowerBound..<upperBound
    }

    private func intersection(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Range<Int>? {
        let lowerBound = max(lhs.lowerBound, rhs.lowerBound)
        let upperBound = min(lhs.upperBound, rhs.upperBound)
        guard upperBound > lowerBound else { return nil }
        return lowerBound..<upperBound
    }

    private func selectableCharacterRange(
        around documentOffset: Int,
        in text: String
    ) -> Range<Int>? {
        let clampedOffset = min(max(documentOffset, 0), text.count)
        let effectiveOffset = clampedOffset == text.count ? max(text.count - 1, 0) : clampedOffset
        guard let index = text.index(text.startIndex, offsetBy: effectiveOffset, limitedBy: text.endIndex),
              index < text.endIndex,
              !text[index].isWhitespace else {
            return nil
        }

        let wordCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if text[index].unicodeScalars.allSatisfy({ wordCharacterSet.contains($0) }) {
            var start = index
            while start > text.startIndex {
                let previous = text.index(before: start)
                guard text[previous].unicodeScalars.allSatisfy({ wordCharacterSet.contains($0) }) else {
                    break
                }
                start = previous
            }
            var end = text.index(after: index)
            while end < text.endIndex,
                  text[end].unicodeScalars.allSatisfy({ wordCharacterSet.contains($0) }) {
                end = text.index(after: end)
            }
            return text.distance(from: text.startIndex, to: start)..<text.distance(from: text.startIndex, to: end)
        }

        let end = text.index(after: index)
        return effectiveOffset..<text.distance(from: text.startIndex, to: end)
    }

    private func characterOffset(in text: String, fromUTF16Offset offset: Int) -> Int? {
        guard offset >= 0,
              let utf16Index = text.utf16.index(
                  text.utf16.startIndex,
                  offsetBy: offset,
                  limitedBy: text.utf16.endIndex
              ),
              let stringIndex = String.Index(utf16Index, within: text) else {
            return nil
        }
        return text.distance(from: text.startIndex, to: stringIndex)
    }

    private func utf16Range(in text: String, characterRange: Range<Int>) -> NSRange? {
        guard characterRange.lowerBound >= 0,
              characterRange.upperBound >= characterRange.lowerBound,
              let start = text.index(text.startIndex, offsetBy: characterRange.lowerBound, limitedBy: text.endIndex),
              let end = text.index(text.startIndex, offsetBy: characterRange.upperBound, limitedBy: text.endIndex),
              let utf16Start = start.samePosition(in: text.utf16),
              let utf16End = end.samePosition(in: text.utf16) else {
            return nil
        }
        return NSRange(
            location: text.utf16.distance(from: text.utf16.startIndex, to: utf16Start),
            length: text.utf16.distance(from: utf16Start, to: utf16End)
        )
    }

#if canImport(UIKit)
    func drawBlockBackgrounds(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        in context: CGContext,
        bounds: CGRect
    ) {
        let surfaceOrdinal = surfaceIdentity.ordinal
        guard isCurrent(surfaceIdentity) else {
            staleDrawingAttemptCount += 1
            return
        }
        prepareSurfaceForDrawing(surfaceOrdinal)
        guard
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceOrdinal }),
        let surfaceOriginY = surfaceOriginY(
            page: page,
            result: result,
            textContentStorage: textContentStorage,
            textLayoutManager: textLayoutManager
        ),
        let pageCharacterRange = characterRange(for: page, result: result)
        else {
            return
        }

        let documentClipRange = page.frozenGeometry.map {
            CGRect(
                x: 0,
                y: $0.documentClipMinY,
                width: max(layout.readableFrame.width, 1),
                height: max($0.documentClipMaxY - $0.documentClipMinY, 1)
            )
        }
        let clipMaxY = page.frozenGeometry.map {
            surfaceOriginY + $0.contentHeight
        } ?? surfaceOriginY + bounds.height
        let pageClipRect = NovelTextViewportDrawingGeometry.clipRect(
            bounds: bounds,
            surfaceOriginY: surfaceOriginY,
            documentClipMaxY: clipMaxY
        )

        context.saveGState()
        context.clip(to: pageClipRect)
        context.translateBy(x: bounds.minX, y: bounds.minY - surfaceOriginY)
        context.setFillColor(quoteBlockBackgroundColor().cgColor)
        for blockStyle in result.viewportContext.document.blockTextStyles where blockStyle.style == .quote {
            let quoteRange = blockStyle.range.location..<blockStyle.range.upperBound
            guard let visibleQuoteRange = intersection(quoteRange, pageCharacterRange),
                  let utf16Range = utf16Range(in: result.viewportContext.document.text, characterRange: visibleQuoteRange),
                  let start = textContentStorage.location(
                    textContentStorage.documentRange.location,
                    offsetBy: utf16Range.location
                  ),
                  let end = textContentStorage.location(start, offsetBy: utf16Range.length),
                  let textRange = NSTextRange(location: start, end: end) else {
                continue
            }

            var backgroundRect: CGRect?
            textLayoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: []
            ) { _, rect, _, _ in
                var clippedRect = rect
                if let documentClipRange {
                    clippedRect = clippedRect.intersection(documentClipRange)
                }
                guard !clippedRect.isNull,
                      clippedRect.width.isFinite,
                      clippedRect.height.isFinite,
                      clippedRect.width > 0,
                      clippedRect.height > 0 else {
                    return true
                }
                let paddedRect = clippedRect.insetBy(dx: -10, dy: -6)
                backgroundRect = backgroundRect.map { $0.union(paddedRect) } ?? paddedRect
                return true
            }

            guard let backgroundRect,
                  backgroundRect.width > 0,
                  backgroundRect.height > 0 else {
                continue
            }
            let path = UIBezierPath(
                roundedRect: backgroundRect,
                cornerRadius: min(8, max(backgroundRect.height / 2, 0))
            ).cgPath
            context.addPath(path)
            context.fillPath()
        }
        context.restoreGState()
    }

    func draw(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        in context: CGContext,
        bounds: CGRect
    ) {
        let surfaceOrdinal = surfaceIdentity.ordinal
        guard isCurrent(surfaceIdentity) else {
            staleDrawingAttemptCount += 1
            return
        }
        prepareSurfaceForDrawing(surfaceOrdinal)
        guard
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.surfaces.first(where: { $0.surfaceOrdinal == surfaceOrdinal }),
        let surfaceOriginY = surfaceOriginY(
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
        let documentRange = page.frozenGeometry.map {
            $0.documentStartOffset..<$0.documentEndOffset
        }
        let clipMaxY = page.frozenGeometry.map {
            surfaceOriginY + $0.contentHeight
        } ?? surfaceOriginY + bounds.height
        let pageClipRect = NovelTextViewportDrawingGeometry.clipRect(
            bounds: bounds,
            surfaceOriginY: surfaceOriginY,
            documentClipMaxY: clipMaxY
        )
        context.saveGState()
        context.clip(to: pageClipRect)
        context.translateBy(x: bounds.minX, y: bounds.minY - surfaceOriginY)
        let documentStart = textContentStorage.documentRange.location
        textLayoutManager.enumerateTextLayoutFragments(
            from: pageLocation,
            options: []
        ) { fragment in
            let fragmentStart = textContentStorage.offset(
                from: documentStart,
                to: fragment.rangeInElement.location
            )
            guard fragmentStart != NSNotFound else { return false }
            guard fragment.layoutFragmentFrame.minY < clipMaxY else {
                return false
            }
            guard fragment.layoutFragmentFrame.maxY >= surfaceOriginY else {
                return true
            }
            if let documentRange {
                var shouldContinue = true
                for lineFragment in fragment.textLineFragments {
                    let lineStart = fragmentStart + lineFragment.characterRange.location
                    let lineEnd = lineStart + lineFragment.characterRange.length
                    if lineStart >= documentRange.upperBound {
                        shouldContinue = false
                        break
                    }
                    guard NovelTextViewportDrawingGeometry.fragmentStartsInDocumentRange(
                        fragmentStart: lineStart,
                        fragmentEnd: lineEnd,
                        documentRange: documentRange
                    ) else {
                        continue
                    }
                    let lineBounds = lineFragment.typographicBounds
                    let lineRect = CGRect(
                        x: fragment.layoutFragmentFrame.minX + lineBounds.minX,
                        y: fragment.layoutFragmentFrame.minY + lineBounds.minY,
                        width: max(lineBounds.width, 1),
                        height: max(lineBounds.height, 1)
                    ).insetBy(dx: 0, dy: -1)
                    context.saveGState()
                    context.clip(to: lineRect)
                    fragment.draw(
                        at: fragment.layoutFragmentFrame.origin,
                        in: context
                    )
                    context.restoreGState()
                }
                return shouldContinue
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
        context.restoreGState()
        drawingAccessCount += 1
        lastDrawnSurfaceIdentity = surfaceIdentity
        lastDrawnDocumentRange = documentRange
    }

    private func quoteBlockBackgroundColor() -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(white: 1, alpha: 0.10)
            }

            switch self.settings.backgroundStyle {
            case .system:
                return UIColor(white: 1, alpha: 0.58)
            case .paper:
                return UIColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.68)
            case .mint:
                return UIColor(white: 1, alpha: 0.62)
            case .sakura:
                return UIColor(white: 1, alpha: 0.60)
            }
        }
    }

    private func pageStartLocation(
        page: NovelTextViewportIndexSurface,
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
              let documentOffset = result.viewportContext.document.documentOffset(forSurfaceRange: firstRange) else {
            return nil
        }
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: documentOffset
        )
    }
#endif
}
