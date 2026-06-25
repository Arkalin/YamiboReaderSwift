import Foundation
import CoreGraphics
import XCTest
@testable import YamiboReaderCore

#if canImport(UIKit)
private typealias NovelTextLayoutFixture = (
    ReaderPageDocument,
    ReaderAppearanceSettings,
    ReaderContainerLayout
) throws -> NovelTextLayoutResult

@MainActor
private extension NovelReadingWorkflow {
    func displayReference(for surfaceOrdinal: Int) -> NovelTextViewportDisplayReference? {
        guard let presentation = state?.presentation,
              let identity = presentation.surfaces.first(where: {
                  $0.identity.ordinal == surfaceOrdinal
              })?.identity else {
            return nil
        }
        return displayReference(for: identity)
    }

    @discardableResult
    func selectSurface(_ surfaceIndex: Int) -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              presentation.surfaces.indices.contains(surfaceIndex) else {
            return nil
        }
        return selectSurface(
            presentation.surfaces[surfaceIndex].identity,
            presentationRevision: presentation.revision
        )
    }

    @discardableResult
    func updateVerticalViewportPosition(
        surfaceIndex: Int,
        intraSurfaceProgress: Double
    ) -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              presentation.surfaces.indices.contains(surfaceIndex) else {
            return nil
        }
        return updateVerticalViewportPosition(
            surfaceIdentity: presentation.surfaces[surfaceIndex].identity,
            intraSurfaceProgress: intraSurfaceProgress,
            presentationRevision: presentation.revision
        )
    }

    @discardableResult
    func prefetchIfNeeded(nearSurfaceOrdinal surfaceOrdinal: Int) async -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              let identity = presentation.surfaces.first(where: {
                  $0.identity.ordinal == surfaceOrdinal
              })?.identity else {
            return nil
        }
        return await prefetchIfNeeded(near: identity)
    }

    @discardableResult
    func requestRuntimeUpdate(
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool = false
    ) async throws -> NovelReadingWorkflowState? {
        try await requestRuntimeUpdate(
            NovelReadingWorkflowRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            )
        )
    }
}

@MainActor
private extension NovelTextViewportRuntimeOwner {
    func displayReference(for surfaceOrdinal: Int) -> NovelTextViewportDisplayReference? {
        displayReference(
            for: NovelReaderSurfaceIdentity(
                generation: currentGeneration,
                ordinal: surfaceOrdinal
            )
        )
    }
}

@MainActor
final class NovelReadingWorkflowTests: XCTestCase {
    func testStartCreatesOneWorkflowOwnedViewportRuntimeAndPublishesPagedDisplayReference() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9178&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let page = try XCTUnwrap(workflow.debugState.viewportSurfaces.first)
        let surfaceIdentity = try XCTUnwrap(state.presentation?.surfaces.first?.identity)
        let reference = try XCTUnwrap(workflow.displayReference(for: surfaceIdentity))

        XCTAssertEqual(reference.surfaceOrdinal, page.surfaceOrdinal)
        XCTAssertEqual(reference.surfaceIdentity, surfaceIdentity)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 1,
                activeLayoutManagerCount: 1,
                perSurfaceTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 1
            )
        )
    }

    func testVerticalDisplayReferenceBecomesStaleAfterRuntimeGenerationChanges() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9179&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .vertical),
            repository: repository
        )

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        let oldReference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))

        _ = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.15, readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .vertical)
        )
        let currentReference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))

        XCTAssertTrue(oldReference.isStale)
        XCTAssertFalse(currentReference.isStale)
        XCTAssertNotEqual(oldReference.generation, currentReference.generation)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 1,
                activeLayoutManagerCount: 1,
                perSurfaceTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 1,
                peakActivePlusCandidateGraphCount: 2
            )
        )
    }

    func testVerticalDisplayReferencePositionsLaterChunkStartNearSurfaceTop() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9188&mobile=2")!
        let text = String(repeating: "最终得出的结论，利用对方的体重来刺穿喉咙是最有效率的。", count: 160)
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [.text(text, chapterTitle: "第一章")]
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: document
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 393, height: 852, readingMode: .vertical),
            repository: repository
        )

        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        let laterPage = try XCTUnwrap(workflow.debugState.viewportSurfaces.dropFirst().first)
        let firstRange = try XCTUnwrap(laterPage.ranges.first)
        let reference = try XCTUnwrap(workflow.displayReference(for: laterPage.surfaceOrdinal))
#if canImport(UIKit)
        let referencePosition = ReaderResumePoint(
            view: laterPage.documentView,
            textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: firstRange.segmentIndex)?.textSegmentIdentity),
            displayedTextOffset: firstRange.startOffset,
            chapterOrdinal: try XCTUnwrap(laterPage.chapterOrdinal),
            chapterTitle: laterPage.chapterTitle,
            segmentProgress: 0,
            authorID: document.resolvedAuthorID,
            readingModeHint: .vertical
        )
        let startY = try XCTUnwrap(
            reference.referenceY(for: referencePosition)
        )

        XCTAssertLessThan(startY, 100)
#else
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(firstRange.startOffset, laterPage.ranges.first?.startOffset)
#endif
    }

    func testVerticalPresentationUsesFrozenChunkHeightsAndOnlySpacesExternalBlocks() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9196&mobile=2")!
        let imageURL = URL(string: "https://example.com/image.jpg")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("第一段第二段第三段", chapterTitle: "第一章"),
                .image(imageURL, chapterTitle: "插图"),
                .text("第四段第五段第六段", chapterTitle: "第二章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let layout = ReaderContainerLayout(width: 320, height: 500, readingMode: .vertical)
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: layout,
            repository: repository,
            pagination: { document, settings, layout in
                try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout,
                    viewportSurfaceLayout: { _, _, _ in
                        [
                            NovelTextViewportDocumentSurfaceRange(
                                startOffset: 0,
                                endOffset: 6,
                                frozenGeometry: NovelTextViewportFrozenGeometry(
                                    documentStartOffset: 0,
                                    documentEndOffset: 6,
                                    documentClipMinY: 0,
                                    documentClipMaxY: 180,
                                    contentHeight: 180
                                )
                            ),
                            NovelTextViewportDocumentSurfaceRange(
                                startOffset: 6,
                                endOffset: 12,
                                frozenGeometry: NovelTextViewportFrozenGeometry(
                                    documentStartOffset: 6,
                                    documentEndOffset: 12,
                                    documentClipMinY: 180,
                                    documentClipMaxY: 420,
                                    contentHeight: 240
                                )
                            )
                        ]
                    },
                )
            }
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let presentation = try XCTUnwrap(state.presentation)
        let surfaces = presentation.surfaces

        XCTAssertEqual(surfaces.map(\.kind), [.text, .text, .externalBlock, .text])
        XCTAssertEqual(surfaces[0].presentationSize.height, 180)
        XCTAssertEqual(surfaces[1].presentationSize.height, 240)
        XCTAssertEqual(surfaces[2].presentationSize.height, layout.readableFrame.height)
        XCTAssertEqual(surfaces[0].presentationSpacingAfter, 0)
        XCTAssertEqual(surfaces[1].presentationSpacingAfter, 14)
        XCTAssertEqual(surfaces[2].presentationSpacingAfter, 14)
        XCTAssertEqual(surfaces[3].presentationSpacingAfter, 0)
    }

    func testRuntimeDiagnosticsRecordCompactionAndSurfaceIdentityPreheat() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9197&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("第一章正文", chapterTitle: "第一章"),
                .text("第二章正文", chapterTitle: "第二章"),
                .text("第三章正文", chapterTitle: "第三章"),
                .text("第四章正文", chapterTitle: "第四章"),
                .text("第五章正文", chapterTitle: "第五章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .vertical),
            repository: repository,
            pagination: { document, settings, layout in
                try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout,
                    viewportSurfaceLayout: { context, _, _ in
                        context.document.textRangesBySegment.values
                            .sorted { $0.startOffset < $1.startOffset }
                            .map {
                                NovelTextViewportDocumentSurfaceRange(
                                    startOffset: $0.startOffset,
                                    endOffset: $0.endOffset,
                                    frozenGeometry: NovelTextViewportFrozenGeometry(
                                        documentStartOffset: $0.startOffset,
                                        documentEndOffset: $0.endOffset,
                                        documentClipMinY: CGFloat($0.startOffset * 10),
                                        documentClipMaxY: CGFloat($0.endOffset * 10),
                                        contentHeight: 120
                                    )
                                )
                            }
                    },
                )
            }
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaces = try XCTUnwrap(state.presentation?.surfaces)
        let initialRuntimeDiagnostics = workflow.runtimeDiagnostics
        let initialTransactionDiagnostics = workflow.runtimeTransactionDiagnostics

        XCTAssertEqual(initialRuntimeDiagnostics.viewportControllerCount, 1)
        XCTAssertEqual(initialRuntimeDiagnostics.currentActivePlusCandidateGraphCount, 1)
        XCTAssertEqual(initialRuntimeDiagnostics.peakActivePlusCandidateGraphCount, 1)
        XCTAssertEqual(initialRuntimeDiagnostics.postCommitFullLayoutCount, 0)
        XCTAssertEqual(initialTransactionDiagnostics.candidateIndexingPassCount, 1)
        XCTAssertEqual(initialTransactionDiagnostics.postIndexCompactionCount, 1)
        XCTAssertEqual(initialTransactionDiagnostics.geometryDeviationCount, 0)

        workflow.updateVisibleSurfaceIdentities(Array(surfaces[1...2].map(\.identity)))
        let updatedDiagnostics = workflow.runtimeDiagnostics

        XCTAssertEqual(updatedDiagnostics.viewportUpdateCount, 1)
        XCTAssertEqual(updatedDiagnostics.rematerializedSurfaceCount, 4)

        workflow.updateVisibleSurfaceIdentities(Array(surfaces[1...2].map(\.identity)))
        XCTAssertEqual(workflow.runtimeDiagnostics.viewportUpdateCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.rematerializedSurfaceCount, 4)

        workflow.updateVisibleSurfaceIdentities([
            NovelReaderSurfaceIdentity(generation: surfaces[1].identity.generation - 1, ordinal: 1)
        ])

        XCTAssertEqual(workflow.runtimeDiagnostics.viewportUpdateCount, 2)
        XCTAssertEqual(workflow.runtimeDiagnostics.rematerializedSurfaceCount, 0)
    }

    func testRepeatedVerticalViewportSampleDoesNotPublishPresentationRevision() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9222&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            segments: [
                .text(
                    String(repeating: "同一个阅读位置不应该反复发布新的展示修订。", count: 160),
                    chapterTitle: "第一章"
                )
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .vertical),
            repository: repository
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let surface: NovelTextViewportIndexSurface = try XCTUnwrap(workflow.debugState.viewportSurfaces.dropFirst().first { !$0.ranges.isEmpty })
        let range: ReaderRenderedTextRange = try XCTUnwrap(surface.ranges.first)
        let segmentIdentity = try XCTUnwrap(document.semantics(forSegmentIndex: range.segmentIndex)?.textSegmentIdentity)
        let surfaceIdentity = try XCTUnwrap(state.presentation?.surfaces.first(where: {
            $0.identity.ordinal == surface.surfaceOrdinal
        })?.identity)
        let sample = NovelTextViewportSample(
            surfaceIdentity: surfaceIdentity,
            documentView: surface.documentView,
            textSegmentIdentity: segmentIdentity,
            displayedTextOffset: range.startOffset
        )

        let firstUpdate: NovelReadingWorkflowState = try XCTUnwrap(workflow.updateVerticalViewportPosition(sample: sample))
        let revisionAfterFirstUpdate = try XCTUnwrap(firstUpdate.presentation?.revision)
        let repeatedUpdate = workflow.updateVerticalViewportPosition(sample: sample)

        XCTAssertNil(repeatedUpdate)
        XCTAssertEqual(workflow.state?.presentation?.revision, revisionAfterFirstUpdate)
    }

    func testTwoPageSpreadReferencesShareRuntimeGeneration() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9180&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: (0..<4).map { index in
                .text("第\(index + 1)章正文", chapterTitle: "第\(index + 1)章")
            }
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            ),
            layout: ReaderContainerLayout(width: 1024, height: 768, readingMode: .paged),
            repository: repository,
            usesPadPresentation: true,
            pagination: currentWebpageViewportPagination
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let spread = try XCTUnwrap(state.presentation?.spreads.first(where: { $0.rightSurfaceIdentity != nil }))
        let rightPageIdentity = try XCTUnwrap(spread.rightSurfaceIdentity?.ordinal)
        let leftReference = try XCTUnwrap(workflow.displayReference(for: spread.leftSurfaceIdentity.ordinal))
        let rightReference = try XCTUnwrap(workflow.displayReference(for: rightPageIdentity))

        XCTAssertEqual(leftReference.generation, rightReference.generation)
        XCTAssertNotEqual(leftReference.surfaceOrdinal, rightReference.surfaceOrdinal)
        XCTAssertFalse(leftReference.isStale)
        XCTAssertFalse(rightReference.isStale)
    }

    func testWorkflowPublishesPresentationWithGenerationScopedSurfaceIdentities() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9192&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let initialPresentation = try XCTUnwrap(initialState.presentation)
        let initialSurface = try XCTUnwrap(initialPresentation.selectedSurfaceIdentity)
        let initialReference = try XCTUnwrap(workflow.displayReference(for: initialSurface))

        XCTAssertEqual(initialPresentation.generation, initialSurface.generation)
        XCTAssertEqual(initialPresentation.revision, 0)
        XCTAssertEqual(initialPresentation.surfaces.map(\.identity.ordinal), workflow.debugState.viewportSurfaces.map(\.surfaceOrdinal))
        XCTAssertEqual(initialReference.generation, initialPresentation.generation)
        XCTAssertFalse(initialReference.isStale)

        let navigated = try XCTUnwrap(workflow.jumpRelativeSurface(1)?.state)
        let navigatedPresentation = try XCTUnwrap(navigated.presentation)

        XCTAssertEqual(navigatedPresentation.generation, initialPresentation.generation)
        XCTAssertEqual(navigatedPresentation.revision, initialPresentation.revision + 1)
        XCTAssertEqual(workflow.displayReference(for: initialSurface)?.generation, initialPresentation.generation)

        let replacement = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.1, readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
        )
        let replacementState = try XCTUnwrap(replacement)
        let replacementPresentation = try XCTUnwrap(replacementState.presentation)

        XCTAssertGreaterThan(replacementPresentation.generation, initialPresentation.generation)
        XCTAssertEqual(replacementPresentation.revision, 0)
        XCTAssertNotEqual(replacementPresentation.surfaces.first?.identity, initialPresentation.surfaces.first?.identity)
        XCTAssertNil(workflow.displayReference(for: initialSurface))
    }

    func testNovelReaderPresentationResolvesSelectedSurfaceIndexByIdentityOrdinal() throws {
        let generation: UInt64 = 7
        let surfaces = (0..<800).map { index in
            NovelReaderSurface(
                identity: NovelReaderSurfaceIdentity(generation: generation, ordinal: index),
                presentationIndex: index,
                kind: .text,
                documentView: 1,
                chapterTitle: "第\(index + 1)章",
                presentationSize: CGSize(width: 320, height: 44)
            )
        }
        let selectedIdentity = surfaces[777].identity
        let presentation = NovelReaderPresentation(
            generation: generation,
            revision: 0,
            surfaces: surfaces,
            selectedSurfaceIdentity: selectedIdentity,
            spreads: [],
            chapters: [],
            committedSettings: ReaderAppearanceSettings(readingMode: .vertical),
            readingState: NovelReaderReadingState(
                currentView: 1,
                maxView: 1,
                currentChapterTitle: "第778章",
                authorID: nil,
                currentSurfaceIntraProgress: 0
            ),
            currentContentSource: .fallbackUnfilteredPage,
            retainedChapterCount: 800,
            filteredChapterCandidateCount: 800,
            selectedSurfaceIndex: 777
        )

        XCTAssertEqual(presentation.selectedSurfaceIndex, 777)
        XCTAssertEqual(presentation.surfaceIndex(for: selectedIdentity), 777)
        XCTAssertNil(presentation.surfaceIndex(for: NovelReaderSurfaceIdentity(generation: generation + 1, ordinal: 777)))
    }

    func testPrefetchDoesNotCreateASecondViewportRuntime() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9181&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        let reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        let diagnostics = workflow.runtimeDiagnostics

        _ = await workflow.prefetchIfNeeded(
            nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0)
        )

        XCTAssertEqual(workflow.runtimeDiagnostics, diagnostics)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(workflow.displayReference(for: surfaceOrdinal)?.generation, reference.generation)
    }

    func testCloseReleasesRuntimeAndAllowsWorkflowToReopen() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9182&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        let oldReference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))

        workflow.close()

        XCTAssertNil(workflow.state)
        XCTAssertNil(workflow.displayReference(for: surfaceOrdinal))
        XCTAssertTrue(oldReference.isStale)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 0,
                activeLayoutManagerCount: 0,
                perSurfaceTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 0
            )
        )

        let reopenedState = try await workflow.start(initial: NovelReadingInitialPosition())
        let reopenedPageIdentity = try firstSurfaceOrdinal(in: reopenedState)
        let reopenedReference = try XCTUnwrap(workflow.displayReference(for: reopenedPageIdentity))

        XCTAssertFalse(reopenedReference.isStale)
        XCTAssertNotEqual(reopenedReference.generation, oldReference.generation)
    }

    func testMemoryPressureClearsSemanticCacheWithoutInvalidatingCurrentGeneration() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9183&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: state)
        let reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        XCTAssertEqual(workflow.runtimeDiagnostics.semanticAttributedDocumentCacheCount, 1)

        workflow.handleMemoryPressure()

        XCTAssertEqual(workflow.runtimeDiagnostics.semanticAttributedDocumentCacheCount, 0)
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 1)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(workflow.displayReference(for: surfaceOrdinal)?.generation, reference.generation)
    }

    func testWorkflowDeinitDoesNotRetainRuntimeThroughDisplayReferences() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9184&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        weak var weakWorkflow: NovelReadingWorkflow?
        var reference: NovelTextViewportDisplayReference?

        do {
            let workflow = makeWorkflow(threadURL: threadURL, repository: repository)
            weakWorkflow = workflow
            let state = try await workflow.start(initial: NovelReadingInitialPosition())
            let surfaceOrdinal = try firstSurfaceOrdinal(in: state)
            reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        }

        XCTAssertNil(weakWorkflow)
        XCTAssertTrue(try XCTUnwrap(reference).isStale)
    }

    func testStartUsesStoredResumePointBeforeLaunchDefaults() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9101&mobile=2")!
        let resumeDocument = makeNovelDocument(threadURL: threadURL, view: 3, maxView: 5, authorID: "resume-author")
        let repository = RecordingNovelReadingRepository(documents: [
            3: resumeDocument
        ])
        let resumePoint = ReaderResumePoint(
            view: 3,
            textSegmentIdentity: try XCTUnwrap(resumeDocument.semantics(forSegmentIndex: 0)?.textSegmentIdentity),
            displayedTextOffset: 0,
            chapterOrdinal: 1,
            chapterTitle: "第三章",
            segmentProgress: 0,
            authorID: "resume-author",
            readingModeHint: .vertical
        )
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(
            initial: NovelReadingInitialPosition(
                resumePoint: resumePoint,
                favoriteAuthorID: "favorite-author"
            )
        )

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 3, authorID: "resume-author")
        ])
        XCTAssertEqual(state.snapshot.currentView, 3)
        XCTAssertEqual(state.presentation?.readingState.authorID, "resume-author")
        XCTAssertEqual(state.snapshot.selectedSurfaceOrdinal, 0)
    }

    func testStartUsesFirstSurfaceAndFavoriteAuthorWhenNoResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9108&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 5, authorID: "favorite-author")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(
            initial: NovelReadingInitialPosition(favoriteAuthorID: "favorite-author")
        )

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "favorite-author")
        ])
        XCTAssertEqual(state.snapshot.currentView, 2)
        XCTAssertEqual(state.snapshot.selectedSurfaceOrdinal, 0)
        XCTAssertEqual(state.presentation?.readingState.authorID, "favorite-author")
    }

    func testUpdatingSettingsThrowsWhenViewportLayoutFailsAndKeepsSnapshot() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9110&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, settings, layout in
                if settings.fontScale > 1 {
                    throw NovelTextLayoutFailure.textKitIndexing
                }
                return try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        let reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        let initialPosition = workflow.currentProgressPosition()
        let initialTransactions = workflow.runtimeTransactionDiagnostics

        do {
            _ = try await workflow.requestRuntimeUpdate(
                settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
            )
            XCTFail("Expected Novel Text Layout failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .textKitIndexing)
        }

        XCTAssertEqual(workflow.state, initialState)
        XCTAssertEqual(workflow.currentProgressPosition(), initialPosition)
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.failedTransactionCount,
            initialTransactions.failedTransactionCount + 1
        )
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.lastFailureStage,
            .textKitIndexing
        )
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.committedTransactionCount,
            initialTransactions.committedTransactionCount
        )
        XCTAssertEqual(workflow.displayReference(for: surfaceOrdinal)?.generation, reference.generation)
        XCTAssertFalse(reference.isStale)
    }

    func testRuntimeAdapterFailureConsumesGenerationAndKeepsActiveWorkflowState() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9191&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let runtimeAdapter = TestNovelTextLayoutRuntimeAdapter()
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            runtimeAdapter: runtimeAdapter
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        let initialReference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))

        runtimeAdapter.failNextCandidate(with: NovelTextLayoutFailure.textKitIndexing)
        do {
            _ = try await workflow.requestRuntimeUpdate(
                settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
            )
            XCTFail("Expected runtime adapter failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .textKitIndexing)
        }

        XCTAssertEqual(workflow.state, initialState)
        XCTAssertFalse(initialReference.isStale)
        XCTAssertEqual(workflow.displayReference(for: surfaceOrdinal)?.generation, initialReference.generation)

        let replacementUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.3, readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
        )
        let replacementState = try XCTUnwrap(replacementUpdate)
        let replacementIdentity = try firstSurfaceOrdinal(in: replacementState)
        let replacementReference = try XCTUnwrap(workflow.displayReference(for: replacementIdentity))

        XCTAssertTrue(initialReference.isStale)
        XCTAssertEqual(replacementReference.generation, initialReference.generation + 2)
        XCTAssertEqual(runtimeAdapter.preparedCandidateCount, 3)
    }

    func testRuntimePreparedTransactionsAreSingleUseAndSupersededByNewerCandidates() throws {
        let runtimeAdapter = TestNovelTextLayoutRuntimeAdapter()
        let runtimeOwner = NovelTextViewportRuntimeOwner(adapter: runtimeAdapter)
        let document = ReaderPageDocument(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9190&mobile=2")!,
            view: 1,
            maxView: 1,
            segments: [
                .text("第一章\n正文", chapterTitle: "第一章")
            ]
        )
        func preparedInput(fontScale: Double = 1) throws -> NovelTextLayoutPreparedInput {
            try NovelTextLayout.prepareInput(
                document: document,
                settings: ReaderAppearanceSettings(fontScale: fontScale, readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568)
            )
        }

        let initialTransaction = try XCTUnwrap(
            try runtimeOwner.prepareTransaction(
                preparedInput: preparedInput()
            )
        )
        runtimeOwner.commit(initialTransaction)
        runtimeOwner.commit(initialTransaction)
        let initialReference = try XCTUnwrap(runtimeOwner.displayReference(for: 0))
        XCTAssertEqual(initialReference.generation, 1)
        XCTAssertEqual(runtimeOwner.runtimeTransactionDiagnostics.committedTransactionCount, 1)

        let supersededTransaction = try XCTUnwrap(
            try runtimeOwner.prepareTransaction(
                preparedInput: preparedInput(fontScale: 1.1)
            )
        )
        let replacementTransaction = try XCTUnwrap(
            try runtimeOwner.prepareTransaction(
                preparedInput: preparedInput(fontScale: 1.2)
            )
        )

        runtimeOwner.commit(supersededTransaction)
        XCTAssertFalse(initialReference.isStale)
        XCTAssertEqual(runtimeOwner.displayReference(for: 0)?.generation, 1)

        runtimeOwner.commit(replacementTransaction)
        let replacementReference = try XCTUnwrap(runtimeOwner.displayReference(for: 0))
        XCTAssertTrue(initialReference.isStale)
        XCTAssertEqual(replacementReference.generation, 3)
        XCTAssertEqual(runtimeOwner.runtimeTransactionDiagnostics.committedTransactionCount, 2)
        XCTAssertEqual(runtimeAdapter.preparedCandidateCount, 3)
    }

    func testAppearanceLayoutSpreadAndModeUpdatesCommitOneRuntimeTransaction() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9185&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged),
            repository: repository,
            usesPadPresentation: false,
            pagination: currentWebpageViewportPagination
        )

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let surfaceOrdinal = try firstSurfaceOrdinal(in: initialState)
        var reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics,
            NovelTextViewportRuntimeTransactionDiagnostics(
                committedTransactionCount: 1,
                semanticAttributedDocumentBuildCount: 1,
                semanticAttributedDocumentReuseCount: 0
            )
        )

        let rotatedLayout = ReaderContainerLayout(width: 568, height: 320, readingMode: .paged)
        let rotatedUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: rotatedLayout
        )
        let rotatedState = try XCTUnwrap(rotatedUpdate)
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: rotatedState.snapshot.selectedSurfaceOrdinal))
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 2)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentBuildCount, 1)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentReuseCount, 1)

        let fontSettings = ReaderAppearanceSettings(
            fontScale: 1.15,
            fontFamily: .systemSerif,
            lineHeightScale: 1.6,
            showsTwoPagesInLandscapeOnPad: true,
            readingMode: .paged
        )
        let fontUpdate = try await workflow.requestRuntimeUpdate(
            settings: fontSettings,
            layout: rotatedLayout
        )
        let fontState = try XCTUnwrap(fontUpdate)
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: fontState.snapshot.selectedSurfaceOrdinal))
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 3)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentBuildCount, 2)

        let spreadUpdate = try await workflow.requestRuntimeUpdate(
            settings: fontSettings,
            layout: rotatedLayout,
            usesPadPresentation: true
        )
        let spreadState = try XCTUnwrap(spreadUpdate)
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: spreadState.snapshot.selectedSurfaceOrdinal))
        XCTAssertFalse(try XCTUnwrap(spreadState.presentation).spreads.isEmpty)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 4)

        let verticalUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(
                fontScale: 1.15,
                fontFamily: .systemSerif,
                lineHeightScale: 1.6,
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .vertical
            ),
            layout: ReaderContainerLayout(width: 568, height: 320, readingMode: .vertical),
            usesPadPresentation: true
        )
        let verticalState = try XCTUnwrap(verticalUpdate)
        XCTAssertTrue(reference.isStale)
        let verticalReference = try XCTUnwrap(
            workflow.displayReference(for: verticalState.snapshot.selectedSurfaceOrdinal)
        )
        XCTAssertFalse(verticalReference.isStale)
        XCTAssertEqual(verticalState.presentation?.committedSettings.readingMode, .vertical)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 5)
    }

    func testRuntimeUpdateRequestsAreLatestWinsWhenPreparationCompletesOutOfOrder() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9188&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        let initialTransactionCount = workflow.runtimeTransactionDiagnostics.committedTransactionCount
        let firstUpdate = NovelReadingWorkflowRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.1, readingMode: .paged),
            layout: ReaderContainerLayout(width: 390, height: 844, readingMode: .paged),
            usesPadPresentation: false
        )
        let latestUpdate = NovelReadingWorkflowRuntimeUpdate(
            settings: ReaderAppearanceSettings(
                fontScale: 1.3,
                lineHeightScale: 1.7,
                readingMode: .vertical
            ),
            layout: ReaderContainerLayout(width: 844, height: 390, readingMode: .vertical),
            usesPadPresentation: true
        )
        let preparationGate = RuntimeUpdatePreparationGate()

        let firstTask = Task {
            try? await workflow.requestRuntimeUpdate(firstUpdate) { update in
                await preparationGate.wait()
                return update
            }
        }
        await preparationGate.waitUntilSuspended()
        let latestState = try await workflow.requestRuntimeUpdate(latestUpdate) { update in
            await Task.yield()
            return update
        }
        await preparationGate.resume()
        _ = await firstTask.value

        XCTAssertEqual(workflow.runtimeUpdateRequestSequence, 2)
        XCTAssertEqual(latestState?.presentation?.committedSettings, latestUpdate.settings)
        XCTAssertEqual(latestState?.presentation?.surfaces.first?.presentationSize.width, latestUpdate.layout.readableFrame.width)
        XCTAssertEqual(workflow.state, latestState)
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.committedTransactionCount,
            initialTransactionCount + 1
        )
    }

    func testLatestRuntimeUpdateFailureDoesNotCommitSupersededOrFailedRequest() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9189&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let initialTransactions = workflow.runtimeTransactionDiagnostics
        let preparationGate = RuntimeUpdatePreparationGate()
        let firstTask = Task {
            try? await workflow.requestRuntimeUpdate(
                NovelReadingWorkflowRuntimeUpdate(
                    settings: ReaderAppearanceSettings(fontScale: 1.1, readingMode: .paged),
                    layout: ReaderContainerLayout(width: 390, height: 844),
                    usesPadPresentation: false
                )
            ) { update in
                await preparationGate.wait()
                return update
            }
        }
        await preparationGate.waitUntilSuspended()

        do {
            _ = try await workflow.requestRuntimeUpdate(
                NovelReadingWorkflowRuntimeUpdate(
                    settings: ReaderAppearanceSettings(fontScale: 1.4, readingMode: .vertical),
                    layout: ReaderContainerLayout(width: 844, height: 390, readingMode: .vertical),
                    usesPadPresentation: true
                )
            ) { _ in
                throw NovelTextLayoutFailure.textKitIndexing
            }
            XCTFail("Expected semantic preparation failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .textKitIndexing)
        }
        await preparationGate.resume()
        _ = await firstTask.value

        XCTAssertEqual(workflow.state, initialState)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics, initialTransactions)
    }

    func testWorkflowCloseRejectsLateRuntimeUpdatePreparation() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9190&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        let preparationGate = RuntimeUpdatePreparationGate()
        let updateTask = Task {
            try? await workflow.requestRuntimeUpdate(
                NovelReadingWorkflowRuntimeUpdate(
                    settings: ReaderAppearanceSettings(fontScale: 1.5, readingMode: .vertical),
                    layout: ReaderContainerLayout(width: 844, height: 390, readingMode: .vertical),
                    usesPadPresentation: true
                )
            ) { update in
                await preparationGate.wait()
                return update
            }
        }
        await preparationGate.waitUntilSuspended()

        workflow.close()
        await preparationGate.resume()
        _ = await updateTask.value

        XCTAssertNil(workflow.state)
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 0)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 0)
    }

    func testLoadCurrentForceRefreshDeletesOnlyCurrentVariantAndReloadsIgnoringCache() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9102&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 4,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                authorID: "author-2"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = try await workflow.loadCurrent(
            preferredSurfaceOrdinal: 0,
            preferredResumePoint: nil,
            forceRefresh: true
        )

        XCTAssertEqual(repository.deletedViews, [
            RecordingNovelReadingRepository.DeletedViews(
                views: [2],
                threadURL: threadURL,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        XCTAssertEqual(repository.ignoringCacheRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-2")
        ])
    }

    func testPrefetchNearEndLoadsNextViewWithoutMergingInVerticalMode() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9103&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "author-1"),
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-1")
        ])
        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertEqual(documentViews(in: state), [1])
    }

    func testVerticalViewportSampleUpdatesSessionBackedNovelReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9111&mobile=2")!
        let document = makeSegmentedNovelDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            authorID: "author-1",
            segmentCount: 3
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: document
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第一页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        viewportTestPage(
                            index: 1,
                            blocks: [
                                .text(
                                    "第二页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        surfaces: [
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.25)
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.selectedSurfaceOrdinal, 1)
        XCTAssertEqual(state.snapshot.currentSurfaceIntraProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity))
        XCTAssertEqual(resumePoint.displayedTextOffset, 50)
        XCTAssertEqual(resumePoint.authorID, "author-1")
        XCTAssertEqual(resumePoint.readingModeHint, .vertical)
    }

    func testVerticalViewportSampleUsesTextKitIndexPositionInsteadOfFrameProgress() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9153&mobile=2")!
        let document = makeSegmentedNovelDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            authorID: "author-1",
            segmentCount: 3
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: document
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第一页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        viewportTestPage(
                            index: 1,
                            blocks: [
                                .text(
                                    "第二页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        surfaces: [
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.25)

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(
                sample: NovelTextViewportSample(
                    surfaceIdentity: NovelReaderSurfaceIdentity(generation: 0, ordinal: 1),
                    documentView: 1,
                    textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity),
                    displayedTextOffset: 68
                )
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.selectedSurfaceOrdinal, 1)
        XCTAssertEqual(state.snapshot.currentSurfaceIntraProgress, 0.7, accuracy: 0.001)
        XCTAssertEqual(resumePoint.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity))
        XCTAssertEqual(resumePoint.displayedTextOffset, 68)
        XCTAssertNotEqual(resumePoint.displayedTextOffset, 50)
    }

    func testVerticalViewportSamplePreservesExactOffsetInsideMultiRangePage() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9157&mobile=2")!
        let document = makeSegmentedNovelDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            authorID: "author-1",
            segmentCount: 17
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: document
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                let ranges = [
                    ReaderRenderedTextRange(segmentIndex: 15, startOffset: 0, endOffset: 2_000),
                    ReaderRenderedTextRange(segmentIndex: 16, startOffset: 1_101, endOffset: 2_000)
                ]
                return layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第六十页",
                                    chapterTitle: "第二章",
                                    ranges: ranges
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        surfaces: [
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 0,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: ranges
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startSurfaceOrdinal: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                surfaceIdentity: NovelReaderSurfaceIdentity(generation: 0, ordinal: 0),
                documentView: 1,
                textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: 16)?.textSegmentIdentity),
                displayedTextOffset: 1_256
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(resumePoint.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 16)?.textSegmentIdentity))
        XCTAssertEqual(resumePoint.displayedTextOffset, 1_256)
        XCTAssertNotEqual(resumePoint.displayedTextOffset, 1_101)
    }

    func testExternalBlockViewportMovementPreservesTextOnlyResumeUntilNextTextSample() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9154&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            segments: [
                .text("前文正文", chapterTitle: "第一章"),
                .image(URL(string: "https://example.com/image.jpg")!, chapterTitle: "第一章"),
                .text("后文正文", chapterTitle: "第一章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: document
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "前文正文",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 30)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        viewportTestPage(
                            index: 1,
                            blocks: [
                                .image(URL(string: "https://example.com/image.jpg")!, chapterTitle: "第一章")
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        viewportTestPage(
                            index: 2,
                            blocks: [
                                .text(
                                    "后文正文",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        surfaces: [
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 30)
                                ]
                            ),
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: []
                            ),
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 2,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                surfaceIdentity: NovelReaderSurfaceIdentity(generation: 0, ordinal: 0),
                documentView: 1,
                textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: 0)?.textSegmentIdentity),
                displayedTextOffset: 15
            )
        )
        let beforeImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.5)
        let onImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                surfaceIdentity: NovelReaderSurfaceIdentity(generation: 0, ordinal: 2),
                documentView: 1,
                textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity),
                displayedTextOffset: 64
            )
        )
        let afterImage = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(beforeImage.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 0)?.textSegmentIdentity))
        XCTAssertEqual(beforeImage.displayedTextOffset, 15)
        XCTAssertEqual(onImage.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 0)?.textSegmentIdentity))
        XCTAssertEqual(onImage.displayedTextOffset, 15)
        XCTAssertEqual(afterImage.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity))
        XCTAssertEqual(afterImage.displayedTextOffset, 64)
    }

    func testNoTextReaderPageDocumentPreservesPreviousTextOnlyResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9254&mobile=2")!
        let firstDocument = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 2,
            resolvedAuthorID: "author-1",
            segments: [
                .text("有正文的网页", chapterTitle: "第一章")
            ]
        )
        let secondDocument = ReaderPageDocument(
            threadURL: threadURL,
            view: 2,
            maxView: 2,
            resolvedAuthorID: "author-1",
            segments: [
                .image(URL(string: "https://example.com/only-image.jpg")!, chapterTitle: "第二章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [
            1: firstDocument,
            2: secondDocument
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                if document.view == 1 {
                    return layoutResult(
                        pages: [
                            viewportTestPage(
                                index: 0,
                                blocks: [
                                    .text(
                                        "有正文的网页",
                                        chapterTitle: "第一章",
                                        ranges: [
                                            ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 40)
                                        ]
                                    )
                                ],
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章"
                            )
                        ],
                        chapters: [
                            ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                        ],
                        viewportIndex: NovelTextViewportIndex(
                            documentView: document.view,
                            readingMode: .vertical,
                            surfaces: [
                                NovelTextViewportIndexSurface(
                                    surfaceOrdinal: 0,
                                    documentView: document.view,
                                    chapterOrdinal: 0,
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 40)
                                    ]
                                )
                            ],
                            chapters: [
                                NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0)
                            ]
                        )
                    )
                }
                return layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .image(URL(string: "https://example.com/only-image.jpg")!, chapterTitle: "第二章")
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 0)
                    ]
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                surfaceIdentity: NovelReaderSurfaceIdentity(generation: 0, ordinal: 0),
                documentView: 1,
                textSegmentIdentity: try XCTUnwrap(firstDocument.semantics(forSegmentIndex: 0)?.textSegmentIdentity),
                displayedTextOffset: 24
            )
        )

        _ = try await workflow.loadView(2, preferredSurfaceOrdinal: 0, preferredResumePoint: nil, forceRefresh: false)
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())
        let progressPosition = workflow.currentProgressPosition()

        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.textSegmentIdentity, try XCTUnwrap(firstDocument.semantics(forSegmentIndex: 0)?.textSegmentIdentity))
        XCTAssertEqual(resumePoint.displayedTextOffset, 24)
        XCTAssertEqual(progressPosition.view, 2)
        XCTAssertEqual(progressPosition.resumePoint?.view, 1)
        XCTAssertEqual(progressPosition.resumePoint?.displayedTextOffset, 24)
    }

    func testCurrentProgressPositionUsesSessionBackedResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9112&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeSegmentedNovelDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 3,
                authorID: "author-2",
                segmentCount: 2
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 2,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                layoutResult(
                    pages: [
                        viewportTestPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第一页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        viewportTestPage(
                            index: 1,
                            blocks: [
                                .text(
                                    "第二页",
                                    chapterTitle: "第二章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 1, startOffset: 20, endOffset: 60)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0),
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 1)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        surfaces: [
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexSurface(
                                surfaceOrdinal: 1,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 20, endOffset: 60)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0),
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startSurfaceOrdinal: 1)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.5)

        let position = workflow.currentProgressPosition()

        XCTAssertEqual(position.threadURL, threadURL)
        XCTAssertEqual(position.view, 2)
        XCTAssertEqual(position.chapterTitle, "第二章")
        XCTAssertEqual(position.authorID, "author-2")
        XCTAssertEqual(position.resumePoint?.view, 2)
        XCTAssertEqual(position.resumePoint?.chapterOrdinal, 1)
        XCTAssertEqual(position.resumePoint?.chapterTitle, "第二章")
        XCTAssertEqual(position.resumePoint?.displayedTextOffset, 40)
    }

    func testCurrentProgressPositionSurvivesNavigationSettingsAndLayoutChanges() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9115&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 1,
                resolvedAuthorID: "author-1",
                contentSource: .authorFilteredPage,
                segments: [
                    .text(String(repeating: "第一章 内容。", count: 120), chapterTitle: "第一章")
                ]
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: workflowRepaginationRanges(
                defaultRanges: [0 ..< 100, 100 ..< 200, 200 ..< 300],
                repaginatedRanges: [0 ..< 60, 60 ..< 120, 120 ..< 180, 180 ..< 240, 240 ..< 300]
            )
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.selectSurface(1)
        let navigatedPosition = workflow.currentProgressPosition()

        XCTAssertEqual(navigatedPosition.threadURL, threadURL)
        XCTAssertEqual(navigatedPosition.view, 1)
        XCTAssertEqual(navigatedPosition.chapterTitle, "第一章")
        XCTAssertEqual(navigatedPosition.authorID, "author-1")
        XCTAssertEqual(navigatedPosition.resumePoint?.displayedTextOffset, 100)

        _ = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.25, readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
        )
        let settingsPosition = workflow.currentProgressPosition()

        XCTAssertEqual(settingsPosition.resumePoint?.displayedTextOffset, 100)

        _ = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.25, readingMode: .paged),
            layout: ReaderContainerLayout(width: 390, height: 844, readingMode: .paged)
        )
        let layoutPosition = workflow.currentProgressPosition()

        XCTAssertEqual(layoutPosition.resumePoint?.displayedTextOffset, 100)
    }

    func testPreviewSourceTextStartsAtRestoredNovelReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9113&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("前文不应进入预览", chapterTitle: "第一章"),
                .text("0123456789目标预览文本", chapterTitle: "第二章"),
                .text("后续段落", chapterTitle: "第二章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: previewSourcePagination
        )
        let resumePoint = ReaderResumePoint(
            view: 1,
            textSegmentIdentity: try XCTUnwrap(document.semantics(forSegmentIndex: 1)?.textSegmentIdentity),
            displayedTextOffset: 10,
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentProgress: 0,
            authorID: "author-1",
            readingModeHint: .vertical
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition(resumePoint: resumePoint))

        let previewText = workflow.currentPreviewSourceText()

        XCTAssertTrue(previewText.hasPrefix("目标预览文本"))
        XCTAssertTrue(previewText.contains("后续段落"))
        XCTAssertFalse(previewText.contains("前文不应进入预览"))
    }

    func testPreviewSourceTextFollowsVerticalViewportMovement() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9114&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("第一段预览", chapterTitle: "第一章"),
                .text("第二段预览", chapterTitle: "第一章"),
                .text("0123456789第三段预览", chapterTitle: "第一章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: previewSourcePagination
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            surfaceIndex: 2,
            intraSurfaceProgress: Double("0123456789".count) / Double("0123456789第三段预览".count)
        )
        let previewText = workflow.currentPreviewSourceText()

        XCTAssertTrue(previewText.hasPrefix("第三段预览"))
        XCTAssertFalse(previewText.contains("第一段预览"))
        XCTAssertFalse(previewText.contains("第二段预览"))
    }

    func testPromotingPrefetchedViewPublishesRequestedPageImmediately() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9109&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let initialPageIdentity = try firstSurfaceOrdinal(in: initialState)
        let initialReference = try XCTUnwrap(workflow.displayReference(for: initialPageIdentity))
        let initialTransactionCount = workflow.runtimeTransactionDiagnostics.committedTransactionCount
        _ = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0))

        let promotedStateOptional = try await workflow.promotePrefetchedDocument(preferredSurfaceOrdinal: 0, resumePoint: nil)
        let promotedState = try XCTUnwrap(promotedStateOptional)
        let promotedReference = try XCTUnwrap(
            workflow.displayReference(for: promotedState.snapshot.selectedSurfaceOrdinal)
        )

        XCTAssertEqual(promotedState.snapshot.currentView, 2)
        XCTAssertEqual(promotedState.snapshot.selectedSurfaceOrdinal, 0)
        XCTAssertEqual(documentViews(in: promotedState), [2])
        XCTAssertEqual(promotedState.snapshot.currentView, 2)
        XCTAssertEqual(promotedState.presentation?.surfaces.first?.documentView, 2)
        XCTAssertTrue(initialReference.isStale)
        XCTAssertFalse(promotedReference.isStale)
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.committedTransactionCount,
            initialTransactionCount + 1
        )
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 1)
    }

    func testPureExternalBlockDocumentPublishesFrozenExternalBlockSurfacesWithoutTextResume() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9193&mobile=2")!
        let imageURL = URL(string: "https://example.com/only-image.jpg")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 1,
                resolvedAuthorID: "author-1",
                contentSource: .authorFilteredPage,
                segments: [.image(imageURL, chapterTitle: "插图")]
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let presentation = try XCTUnwrap(state.presentation)
        let surface = try XCTUnwrap(presentation.surfaces.first)
        let externalBlock = try XCTUnwrap(surface.externalBlocks.first)
        let frame = try XCTUnwrap(externalBlock.frame)

        XCTAssertEqual(surface.kind, .externalBlock)
        XCTAssertEqual(externalBlock.url, imageURL)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertNil(workflow.captureNovelReadingPosition())
    }

    func testFailedPrefetchedPromotionKeepsCurrentRuntimeAndReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9186&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, settings, layout in
                guard document.view == 1 else {
                    throw NovelTextLayoutFailure.textKitIndexing
                }
                return try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.selectSurface(max(try surfaceCount(in: initialState) - 1, 0))
        let currentState = try XCTUnwrap(workflow.state)
        let surfaceOrdinal = currentState.snapshot.selectedSurfaceOrdinal
        let reference = try XCTUnwrap(workflow.displayReference(for: surfaceOrdinal))
        let position = workflow.currentProgressPosition()
        let transactions = workflow.runtimeTransactionDiagnostics
        _ = await workflow.prefetchIfNeeded(
            nearSurfaceOrdinal: max(try surfaceCount(in: currentState) - 2, 0)
        )

        do {
            _ = try await workflow.promotePrefetchedDocument(preferredSurfaceOrdinal: 0, resumePoint: nil)
            XCTFail("Expected prefetched promotion to fail")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .textKitIndexing)
        }

        XCTAssertEqual(workflow.state?.snapshot, currentState.snapshot)
        XCTAssertEqual(workflow.currentProgressPosition(), position)
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.failedTransactionCount,
            transactions.failedTransactionCount + 1
        )
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.lastFailureStage,
            .textKitIndexing
        )
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.committedTransactionCount,
            transactions.committedTransactionCount
        )
        XCTAssertEqual(workflow.displayReference(for: surfaceOrdinal)?.generation, reference.generation)
        XCTAssertFalse(reference.isStale)
        XCTAssertTrue(workflow.canPromotePrefetchedDocument(forView: 2))
    }

    func testRepeatedPromotionAndCloseDoNotCreateAdditionalRuntimeGenerations() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9187&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = await workflow.prefetchIfNeeded(
            nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0)
        )
        _ = try await workflow.promotePrefetchedDocument(preferredSurfaceOrdinal: 0, resumePoint: nil)
        let committedTransactions = workflow.runtimeTransactionDiagnostics

        let repeatedPromotion = try await workflow.promotePrefetchedDocument(
            preferredSurfaceOrdinal: 0,
            resumePoint: nil
        )
        XCTAssertNil(repeatedPromotion)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics, committedTransactions)

        workflow.close()

        let closedPromotion = try await workflow.promotePrefetchedDocument(
            preferredSurfaceOrdinal: 0,
            resumePoint: nil
        )
        XCTAssertNil(closedPromotion)
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 0)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 0)
    }

    func testPrefetchNearEndDoesNotMergeNextViewInPagedMode() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9104&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertEqual(documentViews(in: state), [1])
    }

    func testRepeatedPrefetchDoesNotReloadAlreadyPrefetchedNextView() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9105&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let nearEndPage = max(try surfaceCount(in: initialState) - 2, 0)

        _ = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: nearEndPage)
        _ = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: nearEndPage)

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "author-1"),
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-1")
        ])
    }

    func testPrefetchFailureKeepsCurrentSnapshot() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9106&mobile=2")!
        let repository = RecordingNovelReadingRepository(
            documents: [
                1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1")
            ],
            failingViews: [2]
        )
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0))
        let currentState = workflow.state

        XCTAssertNil(prefetchState)
        XCTAssertEqual(currentState, initialState)
    }

    func testCacheContextSeparatesCurrentFallbackAndPrefetchedAuthorFilteredVariants() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9107&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 2,
                authorID: nil,
                contentSource: .fallbackUnfilteredPage
            ),
            2: makeNovelDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 2,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: nil
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = await workflow.prefetchIfNeeded(nearSurfaceOrdinal: max(try surfaceCount(in: initialState) - 2, 0))

        let currentContext = workflow.cacheContext(forView: 1)
        let prefetchedContext = workflow.cacheContext(forView: 2)

        XCTAssertEqual(currentContext, NovelReadingCacheContext(authorID: nil, contentSource: .fallbackUnfilteredPage))
        XCTAssertEqual(prefetchedContext, NovelReadingCacheContext(authorID: "author-2", contentSource: .authorFilteredPage))
    }

    func testLongCurrentWebpageViewportPublishesExactIndexAndRestoresAcrossReaderChanges() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1520&mobile=2")!
        let chapterTitles = (1...6).map { "第\($0)章" }
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-152",
            contentSource: .fallbackUnfilteredPage,
            segments: chapterTitles.map { title in
                .text(String(repeating: "\(title) 长篇当前页正文。", count: 50), chapterTitle: title)
            }
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "测试线程",
                source: .forum,
                initialView: 1,
                authorID: "author-152"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: currentWebpageViewportPagination
        )

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        assertLongCurrentWebpageViewportState(
            initialState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 0,
            currentChapterTitle: "第1章"
        )
        XCTAssertEqual(workflow.debugState.viewportSurfaces.filter { !$0.ranges.isEmpty }.count, 6)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.candidateIndexingPassCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.postCommitFullLayoutCount, 0)

        let movedState = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(surfaceIndex: 4, intraSurfaceProgress: 0.5)
        )
        assertLongCurrentWebpageViewportState(
            movedState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 4,
            currentChapterTitle: "第5章"
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())
        let fifthChapterLength: Int
        if case let .text(text, _) = document.segments[4] {
            fifthChapterLength = text.count
        } else {
            throw XCTSkip("Expected text segment")
        }
        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 4)
        XCTAssertEqual(resumePoint.chapterTitle, "第5章")
        XCTAssertEqual(resumePoint.displayedTextOffset, fifthChapterLength / 2)
        XCTAssertEqual(resumePoint.authorID, "author-152")
        XCTAssertEqual(resumePoint.readingModeHint, .paged)

        let appearanceUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: .paged)
        )
        let appearanceState = try XCTUnwrap(appearanceUpdate)
        assertLongCurrentWebpageViewportState(
            appearanceState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 4,
            currentChapterTitle: "第5章"
        )

        let rotatedUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged),
            layout: ReaderContainerLayout(width: 568, height: 320, readingMode: .paged)
        )
        let rotatedState = try XCTUnwrap(rotatedUpdate)
        assertLongCurrentWebpageViewportState(
            rotatedState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 4,
            currentChapterTitle: "第5章"
        )

        let verticalUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical),
            layout: ReaderContainerLayout(width: 568, height: 320, readingMode: .vertical)
        )
        let verticalState = try XCTUnwrap(verticalUpdate)
        assertLongCurrentWebpageViewportState(
            verticalState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 4,
            currentChapterTitle: "第5章"
        )

        let translatedUpdate = try await workflow.requestRuntimeUpdate(
            settings: ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical, translationMode: .simplified),
            layout: ReaderContainerLayout(width: 568, height: 320, readingMode: .vertical)
        )
        let translatedState = try XCTUnwrap(translatedUpdate)
        assertLongCurrentWebpageViewportState(
            translatedState,
            workflow: workflow,
            chapterTitles: chapterTitles,
            selectedSurfaceOrdinal: 4,
            currentChapterTitle: "第5章"
        )
        XCTAssertEqual(workflow.debugState.viewportSurfaces[4].ranges.first?.segmentIndex, 4)
    }
}

@MainActor
private func makeWorkflow(
    threadURL: URL,
    repository: RecordingNovelReadingRepository
) -> NovelReadingWorkflow {
    NovelReadingWorkflow(
        context: ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "Thread",
            source: .forum,
            initialView: 1,
            authorID: "author-1"
        ),
        settings: ReaderAppearanceSettings(readingMode: .paged),
        layout: ReaderContainerLayout(width: 320, height: 568),
        repository: repository,
        pagination: previewSourcePagination
    )
}

private actor RuntimeUpdatePreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class TestNovelTextLayoutRuntimeAdapter: NovelTextLayoutRuntimeAdapter {
    private var nextFailure: Error?
    private(set) var preparedCandidateCount = 0
    private let implementation = DefaultNovelTextLayoutRuntimeAdapter()

    func failNextCandidate(with error: Error) {
        nextFailure = error
    }

    func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate {
        preparedCandidateCount += 1
        if let nextFailure {
            self.nextFailure = nil
            throw nextFailure
        }
        return try implementation.prepareCandidate(input: input)
    }
}

@MainActor
private final class FixtureNovelTextLayoutRuntimeAdapter: NovelTextLayoutRuntimeAdapter {
    private let fixture: NovelTextLayoutFixture

    init(fixture: @escaping NovelTextLayoutFixture) {
        self.fixture = fixture
    }

    func prepareCandidate(
        input: NovelTextLayoutRuntimeAdapterInput
    ) throws -> NovelTextLayoutRuntimeCandidate {
        let result = try fixture(
            input.preparedInput.document,
            input.preparedInput.settings,
            input.preparedInput.layout
        )
        return try DefaultNovelTextLayoutRuntimeAdapter().prepareCandidate(
            input: NovelTextLayoutRuntimeAdapterInput(
                preparedInput: input.preparedInput,
                settings: input.settings,
                layout: input.layout,
                cachedSemanticAttributedDocument: input.cachedSemanticAttributedDocument,
                precomputedResult: result
            )
        )
    }
}

@MainActor
private extension NovelReadingWorkflow {
    convenience init(
        context: ReaderLaunchContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        repository: any NovelReadingPageRepository,
        usesPadPresentation: Bool = false,
        pagination: @escaping NovelTextLayoutFixture
    ) {
        self.init(
            context: context,
            settings: settings,
            layout: layout,
            repository: repository,
            usesPadPresentation: usesPadPresentation,
            runtimeAdapter: FixtureNovelTextLayoutRuntimeAdapter(fixture: pagination)
        )
    }
}

private final class RecordingNovelReadingRepository: NovelReadingPageRepository, @unchecked Sendable {
    struct DeletedViews: Equatable {
        var views: Set<Int>
        var threadURL: URL
        var authorID: String?
        var contentSource: ReaderContentSource?
    }

    private let documents: [Int: ReaderPageDocument]
    private let failingViews: Set<Int>
    private(set) var loadRequests: [ReaderPageRequest] = []
    private(set) var ignoringCacheRequests: [ReaderPageRequest] = []
    private(set) var deletedViews: [DeletedViews] = []

    init(documents: [Int: ReaderPageDocument], failingViews: Set<Int> = []) {
        self.documents = documents
        self.failingViews = failingViews
    }

    func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        loadRequests.append(request)
        return try document(for: request)
    }

    func loadPageIgnoringCache(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        ignoringCacheRequests.append(request)
        return try document(for: request)
    }

    func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> Set<Int> {
        []
    }

    func deleteCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        deletedViews.append(DeletedViews(
            views: views,
            threadURL: threadURL,
            authorID: authorID,
            contentSource: contentSource
        ))
    }

    private func document(for request: ReaderPageRequest) throws -> ReaderPageDocument {
        if failingViews.contains(request.view) {
            throw URLError(.cannotLoadFromNetwork)
        }
        guard let document = documents[request.view] else {
            throw URLError(.badServerResponse)
        }
        return document
    }
}

private func makeNovelDocument(
    threadURL: URL,
    view: Int,
    maxView: Int,
    authorID: String? = nil,
    contentSource: ReaderContentSource = .authorFilteredPage
) -> ReaderPageDocument {
    ReaderPageDocument(
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: contentSource,
        segments: [
            .text(String(repeating: "第\(view)页正文。", count: 80), chapterTitle: "第\(view)章")
        ]
    )
}

private func makeSegmentedNovelDocument(
    threadURL: URL,
    view: Int,
    maxView: Int,
    authorID: String? = nil,
    segmentCount: Int
) -> ReaderPageDocument {
    ReaderPageDocument(
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: .authorFilteredPage,
        segments: (0..<max(1, segmentCount)).map { index in
            .text(
                String(repeating: "第\(view)页第\(index)段正文。", count: 80),
                chapterTitle: "第\(view)章"
            )
        }
    )
}

private func layoutResult(
    pages: [NovelTextViewportIndexSurface],
    chapters: [ReaderChapter],
    viewportIndex: NovelTextViewportIndex? = nil,
    viewportContext: NovelTextViewportContext? = nil
) -> NovelTextLayoutResult {
    let index = viewportIndex ?? NovelTextViewportIndex(
        documentView: pages.first?.documentView ?? 1,
        readingMode: viewportContext?.identity.appearance.readingMode ?? .paged,
        surfaces: pages.map { page in
            NovelTextViewportIndexSurface(
                surfaceOrdinal: page.surfaceOrdinal,
                documentView: page.documentView,
                chapterOrdinal: page.chapterOrdinal,
                chapterTitle: page.chapterTitle,
                ranges: []
            )
        },
        chapters: chapters.map {
            NovelTextViewportIndexChapter(
                ordinal: $0.ordinal,
                title: $0.title,
                startSurfaceOrdinal: $0.startIndex
            )
        }
    )
    let context = viewportContext ?? NovelTextViewportContext(
        identity: NovelTextViewportIdentity(
            threadURL: URL(string: "https://example.com/thread")!,
            documentView: index.documentView,
            maxView: index.documentView,
            fetchedAt: Date(timeIntervalSince1970: 0),
            contentSource: .fallbackUnfilteredPage,
            appearance: ReaderAppearanceSettings(readingMode: index.readingMode),
            layout: ReaderContainerLayout(width: 320, height: 568, readingMode: index.readingMode)
        ),
        document: NovelTextViewportDocument(
            text: "",
            textRangesBySegment: [:],
            insertedSeparatorRanges: []
        ),
        externalBlocks: [],
        diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
    )
    return NovelTextLayoutResult(
        viewportContext: context,
        viewportIndex: index
    )
}

private enum ViewportTestBlock {
    case text(String, chapterTitle: String?, ranges: [ReaderRenderedTextRange] = [])
    case image(URL, chapterTitle: String?)
}

private func viewportTestPage(
    index: Int,
    blocks: [ViewportTestBlock] = [],
    documentView: Int = 1,
    chapterOrdinal: Int? = nil,
    chapterTitle: String? = nil,
    chapterCommentTarget: ReaderChapterCommentTarget? = nil
) -> NovelTextViewportIndexSurface {
    let ranges = blocks.flatMap { block -> [ReaderRenderedTextRange] in
        if case let .text(_, _, ranges) = block {
            return ranges
        }
        return []
    }
    let externalBlocks = blocks.compactMap { block -> NovelTextViewportExternalBlock? in
        guard case let .image(url, imageChapterTitle) = block else { return nil }
        return NovelTextViewportExternalBlock(
            chapterIdentity: chapterTitle.map { NovelChapterIdentity(rawValue: "fixture.chapter.\($0)") },
            url: url,
            chapterOrdinal: chapterOrdinal,
            chapterTitle: imageChapterTitle ?? chapterTitle,
            chapterCommentTarget: chapterCommentTarget
        )
    }
    return NovelTextViewportIndexSurface(
        surfaceOrdinal: index,
        documentView: documentView,
        chapterOrdinal: chapterOrdinal,
        chapterTitle: chapterTitle,
        ranges: ranges,
        externalBlocks: externalBlocks,
        chapterCommentTarget: chapterCommentTarget
    )
}

private func previewSourcePagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) -> NovelTextLayoutResult {
    var documentText = ""
    var textRangesBySegment: [Int: ReaderRenderedTextRange] = [:]
    for (index, segment) in document.segments.enumerated() {
        guard case let .text(text, _) = segment else { continue }
        if !documentText.isEmpty {
            documentText += "\n\n"
        }
        let startOffset = documentText.count
        documentText += text
        textRangesBySegment[index] = ReaderRenderedTextRange(
            segmentIndex: index,
            startOffset: startOffset,
            endOffset: documentText.count
        )
    }
    let viewportContext = NovelTextViewportContext(
        identity: NovelTextViewportIdentity(
            threadURL: document.threadURL,
            documentView: document.view,
            maxView: document.maxView,
            fetchedAt: document.fetchedAt,
            contentSource: document.contentSource,
            appearance: settings,
            layout: layout
        ),
        document: NovelTextViewportDocument(
            text: documentText,
            textRangesBySegment: textRangesBySegment,
            insertedSeparatorRanges: []
        ),
        externalBlocks: [],
        diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
    )
    return layoutResult(
        pages: document.segments.enumerated().map { index, segment in
            return viewportTestPage(
                index: index,
                blocks: [],
                documentView: document.view,
                chapterOrdinal: index,
                chapterTitle: segment.chapterTitle
            )
        },
        chapters: document.segments.enumerated().map { index, segment in
            ReaderChapter(
                ordinal: index,
                title: segment.chapterTitle ?? "Chapter \(index + 1)",
                startIndex: index
            )
        },
        viewportIndex: NovelTextViewportIndex(
            documentView: document.view,
            readingMode: settings.readingMode,
            surfaces: document.segments.enumerated().map { index, segment in
                let text: String
                if case let .text(value, _) = segment {
                    text = value
                } else {
                    text = ""
                }
                return NovelTextViewportIndexSurface(
                    surfaceOrdinal: index,
                    documentView: document.view,
                    chapterOrdinal: index,
                    chapterTitle: segment.chapterTitle,
                    ranges: text.isEmpty
                        ? []
                        : [ReaderRenderedTextRange(segmentIndex: index, startOffset: 0, endOffset: text.count)]
                )
            },
            chapters: document.segments.enumerated().map { index, segment in
                NovelTextViewportIndexChapter(
                    ordinal: index,
                    title: segment.chapterTitle ?? "Chapter \(index + 1)",
                    startSurfaceOrdinal: index
                )
            }
        ),
        viewportContext: viewportContext
    )
}

private func workflowRepaginationRanges(
    defaultRanges: [Range<Int>],
    repaginatedRanges: [Range<Int>]
) -> NovelTextLayoutFixture {
    { document, settings, layout in
        let ranges = settings.fontScale > 1 || layout.width > 320
            ? repaginatedRanges
            : defaultRanges
        return layoutResult(
            pages: ranges.enumerated().map { index, range in
                viewportTestPage(
                    index: index,
                    blocks: [],
                    documentView: document.view,
                    chapterOrdinal: 0,
                    chapterTitle: "第一章"
                )
            },
            chapters: [
                ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
            ],
            viewportIndex: NovelTextViewportIndex(
                documentView: document.view,
                readingMode: settings.readingMode,
                surfaces: ranges.enumerated().map { index, range in
                    NovelTextViewportIndexSurface(
                        surfaceOrdinal: index,
                        documentView: document.view,
                        chapterOrdinal: 0,
                        chapterTitle: "第一章",
                        ranges: [
                            ReaderRenderedTextRange(
                                segmentIndex: 0,
                                startOffset: range.lowerBound,
                                endOffset: range.upperBound
                            )
                        ]
                    )
                },
                chapters: [
                    NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startSurfaceOrdinal: 0)
                ]
            )
        )
    }
}

private func currentWebpageViewportPagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) throws -> NovelTextLayoutResult {
    try NovelTextLayout.layout(
        document: document,
        settings: settings,
        layout: layout,
        viewportSurfaceLayout: { context, _, _ in
            [NovelTextViewportDocumentSurfaceRange(startOffset: 0, endOffset: context.document.text.count)]
        },
    )
}

@MainActor
private func assertLongCurrentWebpageViewportState(
    _ state: NovelReadingWorkflowState,
    workflow: NovelReadingWorkflow,
    chapterTitles: [String],
    selectedSurfaceOrdinal: Int,
    currentChapterTitle: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let pages = workflow.debugState.viewportSurfaces
    XCTAssertEqual(pages.count, chapterTitles.count, file: file, line: line)
    XCTAssertTrue(pages.allSatisfy { !$0.ranges.isEmpty }, file: file, line: line)
    XCTAssertEqual(state.presentation?.chapters.map(\.title), chapterTitles, file: file, line: line)
    XCTAssertEqual(state.presentation?.chapters.map(\.startIndex), Array(chapterTitles.indices), file: file, line: line)
    XCTAssertEqual(state.snapshot.selectedSurfaceOrdinal, selectedSurfaceOrdinal, file: file, line: line)
    XCTAssertEqual(state.snapshot.currentChapterTitle, currentChapterTitle, file: file, line: line)
    XCTAssertEqual(state.snapshot.currentView, 1, file: file, line: line)
    XCTAssertEqual(state.presentation?.surfaces.count, chapterTitles.count, file: file, line: line)
    XCTAssertEqual(
        pages[selectedSurfaceOrdinal].ranges.first?.segmentIndex,
        selectedSurfaceOrdinal,
        file: file,
        line: line
    )
}

private func firstSurfaceOrdinal(in state: NovelReadingWorkflowState) throws -> Int {
    try XCTUnwrap(state.presentation?.surfaces.first?.identity.ordinal)
}

private func surfaceCount(in state: NovelReadingWorkflowState) throws -> Int {
    try XCTUnwrap(state.presentation).surfaces.count
}

private func documentViews(in state: NovelReadingWorkflowState) -> Set<Int> {
    Set(state.presentation?.surfaces.map(\.documentView) ?? [])
}
#endif
