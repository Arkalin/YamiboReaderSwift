import Foundation
import XCTest
@testable import YamiboReaderCore

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
        let page = try XCTUnwrap(state.snapshot.viewportIndex?.pages.first)
        let reference = try XCTUnwrap(workflow.displayReference(for: page.pageIndex))

        XCTAssertEqual(reference.pageIdentity, page.pageIndex)
        XCTAssertEqual(reference.documentView, page.documentView)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 1,
                activeLayoutManagerCount: 1,
                perPageTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 1
            )
        )
    }

    func testNovelReadingSessionRemainsPlatformIndependentPureValueState() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingSession.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("import UIKit"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("NSTextContentStorage"))
        XCTAssertFalse(source.contains("NSTextLayoutManager"))
        XCTAssertTrue(source.contains("public struct NovelReadingSession: Sendable"))
    }

    func testWorkflowCommitsRuntimeWithIndexTransactionLayout() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingWorkflow.swift"),
            encoding: .utf8
        )

        let preparedTransactionCommitCount = source
            .components(separatedBy: "layout: result.viewportContext.identity.layout")
            .count - 1
        XCTAssertEqual(preparedTransactionCommitCount, 2)
        XCTAssertTrue(source.contains("layout: viewportContext.identity.layout"))
        XCTAssertFalse(
            source.contains(
                """
                viewportRuntime.prepareTransaction(
                                result: result,
                                settings: settings,
                                layout: layout
                """
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
        let pageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        let oldReference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))

        _ = try workflow.updateSettings(
            ReaderAppearanceSettings(fontScale: 1.15, readingMode: .vertical)
        )
        let currentReference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))

        XCTAssertTrue(oldReference.isStale)
        XCTAssertFalse(currentReference.isStale)
        XCTAssertNotEqual(oldReference.generation, currentReference.generation)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 1,
                activeLayoutManagerCount: 1,
                perPageTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 1
            )
        )
    }

    func testVerticalDisplayReferencePositionsLaterChunkStartNearSurfaceTop() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9188&mobile=2")!
        let text = String(repeating: "最终得出的结论，利用对方的体重来刺穿喉咙是最有效率的。", count: 160)
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 1,
                resolvedAuthorID: "author-1",
                contentSource: .authorFilteredPage,
                segments: [.text(text, chapterTitle: "第一章")]
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
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 393, height: 852, readingMode: .vertical),
            repository: repository
        )

        let state = try await workflow.start(initial: NovelReadingInitialPosition())
        let laterPage = try XCTUnwrap(state.snapshot.viewportIndex?.pages.dropFirst().first)
        let firstRange = try XCTUnwrap(laterPage.ranges.first)
        let reference = try XCTUnwrap(workflow.displayReference(for: laterPage.pageIndex))
        let startY = try XCTUnwrap(
            reference.referenceY(
                segmentIndex: firstRange.segmentIndex,
                segmentOffset: firstRange.startOffset
            )
        )

        XCTAssertLessThan(startY, 100)
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
        let spread = try XCTUnwrap(state.snapshot.pagedSpreads.first(where: { $0.rightPageIndex != nil }))
        let rightPageIdentity = try XCTUnwrap(spread.rightPageIndex)
        let leftReference = try XCTUnwrap(workflow.displayReference(for: spread.leftPageIndex))
        let rightReference = try XCTUnwrap(workflow.displayReference(for: rightPageIdentity))

        XCTAssertEqual(leftReference.generation, rightReference.generation)
        XCTAssertNotEqual(leftReference.pageIdentity, rightReference.pageIdentity)
        XCTAssertFalse(leftReference.isStale)
        XCTAssertFalse(rightReference.isStale)
    }

    func testPrefetchDoesNotCreateASecondViewportRuntime() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9181&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let pageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        let reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        let diagnostics = workflow.runtimeDiagnostics

        _ = await workflow.prefetchIfNeeded(
            forPageIndex: max(initialState.snapshot.pages.count - 2, 0)
        )

        XCTAssertEqual(workflow.runtimeDiagnostics, diagnostics)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(workflow.displayReference(for: pageIdentity)?.generation, reference.generation)
    }

    func testCloseReleasesRuntimeAndAllowsWorkflowToReopen() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9182&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
        ])
        let workflow = makeWorkflow(threadURL: threadURL, repository: repository)

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let pageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        let oldReference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))

        workflow.close()

        XCTAssertNil(workflow.state)
        XCTAssertNil(workflow.displayReference(for: pageIdentity))
        XCTAssertTrue(oldReference.isStale)
        XCTAssertEqual(
            workflow.runtimeDiagnostics,
            NovelTextViewportRuntimeDiagnostics(
                contentStorageCount: 0,
                activeLayoutManagerCount: 0,
                perPageTextKitDocumentCount: 0,
                semanticAttributedDocumentCacheCount: 0
            )
        )

        let reopenedState = try await workflow.start(initial: NovelReadingInitialPosition())
        let reopenedPageIdentity = try XCTUnwrap(reopenedState.snapshot.viewportIndex?.pages.first?.pageIndex)
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
        let pageIdentity = try XCTUnwrap(state.snapshot.viewportIndex?.pages.first?.pageIndex)
        let reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        XCTAssertEqual(workflow.runtimeDiagnostics.semanticAttributedDocumentCacheCount, 1)

        workflow.handleMemoryPressure()

        XCTAssertEqual(workflow.runtimeDiagnostics.semanticAttributedDocumentCacheCount, 0)
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 1)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(workflow.displayReference(for: pageIdentity)?.generation, reference.generation)
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
            let pageIdentity = try XCTUnwrap(state.snapshot.viewportIndex?.pages.first?.pageIndex)
            reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        }

        XCTAssertNil(weakWorkflow)
        XCTAssertTrue(try XCTUnwrap(reference).isStale)
    }

    func testStartUsesStoredResumePointBeforeLaunchPage() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9101&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            3: makeNovelDocument(threadURL: threadURL, view: 3, maxView: 5, authorID: "resume-author")
        ])
        let resumePoint = ReaderResumePoint(
            view: 3,
            chapterOrdinal: 1,
            chapterTitle: "第三章",
            segmentIndex: 0,
            segmentOffset: 0,
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
                initialPage: 4,
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
        XCTAssertEqual(state.currentAuthorID, "resume-author")
        XCTAssertEqual(state.snapshot.currentPageIndex, 0)
    }

    func testStartUsesLaunchPageAndFavoriteAuthorWhenNoResumePoint() async throws {
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
                initialPage: 1,
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
        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.currentAuthorID, "favorite-author")
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
                    throw NovelTextLayoutFailure.unableToLayoutText
                }
                return try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let pageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        let reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        let initialPosition = workflow.currentProgressPosition()
        let initialTransactions = workflow.runtimeTransactionDiagnostics

        do {
            _ = try workflow.updateSettings(
                ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged)
            )
            XCTFail("Expected Novel Text Layout failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .unableToLayoutText)
        }

        XCTAssertEqual(workflow.state, initialState)
        XCTAssertEqual(workflow.currentProgressPosition(), initialPosition)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics, initialTransactions)
        XCTAssertEqual(workflow.displayReference(for: pageIdentity)?.generation, reference.generation)
        XCTAssertFalse(reference.isStale)
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
        let pageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        var reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics,
            NovelTextViewportRuntimeTransactionDiagnostics(
                committedTransactionCount: 1,
                semanticAttributedDocumentBuildCount: 1,
                semanticAttributedDocumentReuseCount: 0
            )
        )

        let rotatedState = try XCTUnwrap(
            workflow.updateLayout(
                ReaderContainerLayout(width: 568, height: 320, readingMode: .paged)
            )
        )
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: rotatedState.snapshot.currentPageIndex))
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 2)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentBuildCount, 1)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentReuseCount, 1)

        let fontState = try XCTUnwrap(
            workflow.updateSettings(
                ReaderAppearanceSettings(
                    fontScale: 1.15,
                    fontFamily: .systemSerif,
                    lineHeightScale: 1.6,
                    showsTwoPagesInLandscapeOnPad: true,
                    readingMode: .paged
                )
            )
        )
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: fontState.snapshot.currentPageIndex))
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 3)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.semanticAttributedDocumentBuildCount, 2)

        let spreadState = try XCTUnwrap(workflow.updatePagedPresentationEnvironment(isPad: true))
        XCTAssertTrue(reference.isStale)
        reference = try XCTUnwrap(workflow.displayReference(for: spreadState.snapshot.currentPageIndex))
        XCTAssertFalse(spreadState.snapshot.pagedSpreads.isEmpty)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics.committedTransactionCount, 4)

        let verticalState = try XCTUnwrap(
            workflow.updateSettings(
                ReaderAppearanceSettings(
                    fontScale: 1.15,
                    fontFamily: .systemSerif,
                    lineHeightScale: 1.6,
                    showsTwoPagesInLandscapeOnPad: true,
                    readingMode: .vertical
                )
            )
        )
        XCTAssertTrue(reference.isStale)
        let verticalReference = try XCTUnwrap(
            workflow.displayReference(for: verticalState.snapshot.currentPageIndex)
        )
        XCTAssertFalse(verticalReference.isStale)
        XCTAssertEqual(verticalState.snapshot.viewportIndex?.readingMode, .vertical)
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
        XCTAssertEqual(latestState?.snapshot.viewportContext?.identity.appearance, latestUpdate.settings)
        XCTAssertEqual(latestState?.snapshot.viewportContext?.identity.layout, latestUpdate.layout)
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
                throw NovelTextLayoutFailure.unableToLayoutText
            }
            XCTFail("Expected semantic preparation failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .unableToLayoutText)
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
            preferredPage: 0,
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

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "author-1"),
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-1")
        ])
        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertNil(state.snapshot.prefetchedStartIndex)
        XCTAssertEqual(Set(state.snapshot.pages.map(\.documentView)), [1])
    }

    func testVerticalViewportSampleUpdatesSessionBackedNovelReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9111&mobile=2")!
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
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.25)
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.snapshot.currentPageIntraProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.segmentIndex, 2)
        XCTAssertEqual(resumePoint.segmentOffset, 50)
        XCTAssertEqual(resumePoint.authorID, "author-1")
        XCTAssertEqual(resumePoint.readingModeHint, .vertical)
    }

    func testVerticalViewportSampleUsesTextKitIndexPositionInsteadOfFrameProgress() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9153&mobile=2")!
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
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.25)

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(
                sample: NovelTextViewportSample(
                    documentView: 1,
                    pageIndex: 1,
                    segmentIndex: 2,
                    segmentOffset: 68
                )
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.snapshot.currentPageIntraProgress, 0.7, accuracy: 0.001)
        XCTAssertEqual(resumePoint.segmentIndex, 2)
        XCTAssertEqual(resumePoint.segmentOffset, 68)
        XCTAssertNotEqual(resumePoint.segmentOffset, 50)
    }

    func testVerticalViewportSamplePreservesExactOffsetInsideMultiRangePage() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9157&mobile=2")!
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
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: ranges
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                documentView: 1,
                pageIndex: 0,
                segmentIndex: 16,
                segmentOffset: 1_256
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(resumePoint.segmentIndex, 16)
        XCTAssertEqual(resumePoint.segmentOffset, 1_256)
        XCTAssertNotEqual(resumePoint.segmentOffset, 1_101)
    }

    func testExternalBlockViewportMovementPreservesTextOnlyResumeUntilNextTextSample() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9154&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
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
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 30)
                                ]
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: []
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 2,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 0, segmentIndex: 0, segmentOffset: 15)
        )
        let beforeImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.5)
        let onImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 2, segmentIndex: 2, segmentOffset: 64)
        )
        let afterImage = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(beforeImage.segmentIndex, 0)
        XCTAssertEqual(beforeImage.segmentOffset, 15)
        XCTAssertEqual(onImage.segmentIndex, 0)
        XCTAssertEqual(onImage.segmentOffset, 15)
        XCTAssertEqual(afterImage.segmentIndex, 2)
        XCTAssertEqual(afterImage.segmentOffset, 64)
    }

    func testNoTextReaderPageDocumentPreservesPreviousTextOnlyResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9254&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 2,
                resolvedAuthorID: "author-1",
                segments: [
                    .text("有正文的网页", chapterTitle: "第一章")
                ]
            ),
            2: ReaderPageDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 2,
                resolvedAuthorID: "author-1",
                segments: [
                    .image(URL(string: "https://example.com/only-image.jpg")!, chapterTitle: "第二章")
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
                            pages: [
                                NovelTextViewportIndexPage(
                                    pageIndex: 0,
                                    documentView: document.view,
                                    chapterOrdinal: 0,
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 40)
                                    ]
                                )
                            ],
                            chapters: [
                                NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
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
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 0, segmentIndex: 0, segmentOffset: 24)
        )

        _ = try await workflow.loadView(2, preferredPage: 0, preferredResumePoint: nil, forceRefresh: false)
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())
        let progressPosition = workflow.currentProgressPosition()

        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.segmentIndex, 0)
        XCTAssertEqual(resumePoint.segmentOffset, 24)
        XCTAssertEqual(progressPosition.view, 2)
        XCTAssertEqual(progressPosition.page, 0)
        XCTAssertEqual(progressPosition.resumePoint?.view, 1)
        XCTAssertEqual(progressPosition.resumePoint?.segmentOffset, 24)
    }

    func testCurrentProgressPositionUsesSessionBackedResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9112&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 3, authorID: "author-2")
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
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 1,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 20, endOffset: 60)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0),
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startPageIndex: 1)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.5)

        let position = workflow.currentProgressPosition()

        XCTAssertEqual(position.threadURL, threadURL)
        XCTAssertEqual(position.view, 2)
        XCTAssertEqual(position.page, 1)
        XCTAssertEqual(position.chapterTitle, "第二章")
        XCTAssertEqual(position.authorID, "author-2")
        XCTAssertEqual(position.resumePoint?.view, 2)
        XCTAssertEqual(position.resumePoint?.chapterOrdinal, 1)
        XCTAssertEqual(position.resumePoint?.chapterTitle, "第二章")
        XCTAssertEqual(position.resumePoint?.segmentIndex, 1)
        XCTAssertEqual(position.resumePoint?.segmentOffset, 40)
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

        _ = workflow.jumpToRenderedPage(1)
        let navigatedPosition = workflow.currentProgressPosition()

        XCTAssertEqual(navigatedPosition.threadURL, threadURL)
        XCTAssertEqual(navigatedPosition.view, 1)
        XCTAssertEqual(navigatedPosition.page, 1)
        XCTAssertEqual(navigatedPosition.chapterTitle, "第一章")
        XCTAssertEqual(navigatedPosition.authorID, "author-1")
        XCTAssertEqual(navigatedPosition.resumePoint?.segmentOffset, 100)

        _ = try workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.25, readingMode: .paged))
        let settingsPosition = workflow.currentProgressPosition()

        XCTAssertEqual(settingsPosition.resumePoint?.segmentOffset, 100)
        XCTAssertEqual(settingsPosition.page, 1)

        _ = try workflow.updateLayout(ReaderContainerLayout(width: 390, height: 844, readingMode: .paged))
        let layoutPosition = workflow.currentProgressPosition()

        XCTAssertEqual(layoutPosition.resumePoint?.segmentOffset, 100)
        XCTAssertEqual(layoutPosition.page, 1)
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
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentIndex: 1,
            segmentOffset: 10,
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
            pageIndex: 2,
            intraPageProgress: Double("0123456789".count) / Double("0123456789第三段预览".count)
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
        let initialPageIdentity = try XCTUnwrap(initialState.snapshot.viewportIndex?.pages.first?.pageIndex)
        let initialReference = try XCTUnwrap(workflow.displayReference(for: initialPageIdentity))
        let initialTransactionCount = workflow.runtimeTransactionDiagnostics.committedTransactionCount
        _ = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))

        let promotedStateOptional = try await workflow.promotePrefetchedDocument(preferredPage: 0, resumePoint: nil)
        let promotedState = try XCTUnwrap(promotedStateOptional)
        let promotedReference = try XCTUnwrap(
            workflow.displayReference(for: promotedState.snapshot.currentPageIndex)
        )

        XCTAssertEqual(promotedState.snapshot.currentView, 2)
        XCTAssertEqual(promotedState.snapshot.currentPageIndex, 0)
        XCTAssertEqual(Set(promotedState.snapshot.pages.map(\.documentView)), [2])
        XCTAssertEqual(promotedState.snapshot.viewportContext?.identity.documentView, 2)
        XCTAssertEqual(promotedState.snapshot.viewportIndex?.documentView, 2)
        XCTAssertTrue(initialReference.isStale)
        XCTAssertFalse(promotedReference.isStale)
        XCTAssertEqual(
            workflow.runtimeTransactionDiagnostics.committedTransactionCount,
            initialTransactionCount + 1
        )
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 1)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 1)
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
                    throw NovelTextLayoutFailure.unableToLayoutText
                }
                return try NovelTextLayout.layout(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.jumpToRenderedPage(max(initialState.snapshot.pages.count - 1, 0))
        let currentState = try XCTUnwrap(workflow.state)
        let pageIdentity = currentState.snapshot.currentPageIndex
        let reference = try XCTUnwrap(workflow.displayReference(for: pageIdentity))
        let position = workflow.currentProgressPosition()
        let transactions = workflow.runtimeTransactionDiagnostics
        _ = await workflow.prefetchIfNeeded(
            forPageIndex: max(currentState.snapshot.pages.count - 2, 0)
        )

        do {
            _ = try await workflow.promotePrefetchedDocument(preferredPage: 0, resumePoint: nil)
            XCTFail("Expected prefetched promotion to fail")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .unableToLayoutText)
        }

        XCTAssertEqual(workflow.state?.snapshot, currentState.snapshot)
        XCTAssertEqual(workflow.currentProgressPosition(), position)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics, transactions)
        XCTAssertEqual(workflow.displayReference(for: pageIdentity)?.generation, reference.generation)
        XCTAssertFalse(reference.isStale)
        XCTAssertEqual(workflow.state?.prefetchedDocument?.view, 2)
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
            forPageIndex: max(initialState.snapshot.pages.count - 2, 0)
        )
        _ = try await workflow.promotePrefetchedDocument(preferredPage: 0, resumePoint: nil)
        let committedTransactions = workflow.runtimeTransactionDiagnostics

        let repeatedPromotion = try await workflow.promotePrefetchedDocument(
            preferredPage: 0,
            resumePoint: nil
        )
        XCTAssertNil(repeatedPromotion)
        XCTAssertEqual(workflow.runtimeTransactionDiagnostics, committedTransactions)

        workflow.close()

        let closedPromotion = try await workflow.promotePrefetchedDocument(
            preferredPage: 0,
            resumePoint: nil
        )
        XCTAssertNil(closedPromotion)
        XCTAssertEqual(workflow.runtimeDiagnostics.contentStorageCount, 0)
        XCTAssertEqual(workflow.runtimeDiagnostics.activeLayoutManagerCount, 0)
    }

    func testPromotionUsesCandidateSessionAndPreparedRuntimeTransaction() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingWorkflow.swift"),
            encoding: .utf8
        )
        let promotionBody = try XCTUnwrap(
            workflowFunctionBody(named: "promotePrefetchedDocument", in: source)
        )

        XCTAssertTrue(promotionBody.contains("var candidateSession"))
        XCTAssertTrue(promotionBody.contains("viewportRuntime.prepareTransaction"))
        XCTAssertTrue(promotionBody.contains("viewportRuntime.commit"))
        XCTAssertFalse(promotionBody.contains("previousDocument"))
        XCTAssertFalse(promotionBody.contains("previousPrefetchedDocument"))
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

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertNil(state.snapshot.prefetchedStartIndex)
        XCTAssertEqual(Set(state.snapshot.pages.map(\.documentView)), [1])
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
        let nearEndPage = max(initialState.snapshot.pages.count - 2, 0)

        _ = await workflow.prefetchIfNeeded(forPageIndex: nearEndPage)
        _ = await workflow.prefetchIfNeeded(forPageIndex: nearEndPage)

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

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
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

        _ = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))

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
            chapterTitles: chapterTitles,
            currentPageIndex: 0,
            currentChapterTitle: "第1章"
        )
        XCTAssertEqual(initialState.snapshot.pages.filter { !$0.ranges.isEmpty }.count, 6)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.indexBuildCount, 1)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.visibleLayoutPassCount, 0)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.compatibilityTextDisplayValueCount, 0)

        let movedState = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(pageIndex: 4, intraPageProgress: 0.5)
        )
        assertLongCurrentWebpageViewportState(
            movedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
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
        XCTAssertEqual(resumePoint.segmentIndex, 4)
        XCTAssertEqual(resumePoint.segmentOffset, fifthChapterLength / 2)
        XCTAssertEqual(resumePoint.authorID, "author-152")
        XCTAssertEqual(resumePoint.readingModeHint, .paged)

        let appearanceState = try XCTUnwrap(
            workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged))
        )
        assertLongCurrentWebpageViewportState(
            appearanceState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let rotatedState = try XCTUnwrap(
            workflow.updateLayout(ReaderContainerLayout(width: 568, height: 320, readingMode: .paged))
        )
        assertLongCurrentWebpageViewportState(
            rotatedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let verticalState = try XCTUnwrap(
            workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical))
        )
        assertLongCurrentWebpageViewportState(
            verticalState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let translatedState = try XCTUnwrap(
            workflow.updateSettings(
                ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical, translationMode: .simplified)
            )
        )
        assertLongCurrentWebpageViewportState(
            translatedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )
        XCTAssertEqual(translatedState.snapshot.viewportIndex?.pages[4].ranges.first?.segmentIndex, 4)
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
        repository: repository
    )
}

private func workflowFunctionBody(named name: String, in source: String) -> String? {
    guard let signatureRange = source.range(of: "public func \(name)("),
          let openingBrace = source[signatureRange.lowerBound...].firstIndex(of: "{") else {
        return nil
    }
    var depth = 0
    for index in source.indices[openingBrace...] {
        switch source[index] {
        case "{":
            depth += 1
        case "}":
            depth -= 1
            if depth == 0 {
                return String(source[openingBrace...index])
            }
        default:
            break
        }
    }
    return nil
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

private func layoutResult(
    pages: [NovelTextViewportIndexPage],
    chapters: [ReaderChapter],
    viewportIndex: NovelTextViewportIndex? = nil,
    viewportContext: NovelTextViewportContext? = nil
) -> NovelTextLayoutResult {
    let index = viewportIndex ?? NovelTextViewportIndex(
        documentView: pages.first?.documentView ?? 1,
        readingMode: viewportContext?.identity.appearance.readingMode ?? .paged,
        pages: pages.map { page in
            NovelTextViewportIndexPage(
                pageIndex: page.pageIndex,
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
                startPageIndex: $0.startIndex
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
) -> NovelTextViewportIndexPage {
    let ranges = blocks.flatMap { block -> [ReaderRenderedTextRange] in
        if case let .text(_, _, ranges) = block {
            return ranges
        }
        return []
    }
    let externalBlocks = blocks.compactMap { block -> NovelTextViewportExternalBlock? in
        guard case let .image(url, imageChapterTitle) = block else { return nil }
        return NovelTextViewportExternalBlock(
            segmentIndex: index,
            url: url,
            chapterOrdinal: chapterOrdinal,
            chapterTitle: imageChapterTitle ?? chapterTitle,
            chapterCommentTarget: chapterCommentTarget
        )
    }
    return NovelTextViewportIndexPage(
        pageIndex: index,
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
    layoutResult(
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
            pages: document.segments.enumerated().map { index, segment in
                let text: String
                if case let .text(value, _) = segment {
                    text = value
                } else {
                    text = ""
                }
                return NovelTextViewportIndexPage(
                    pageIndex: index,
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
                    startPageIndex: index
                )
            }
        )
    )
}

private func workflowRepaginationRanges(
    defaultRanges: [Range<Int>],
    repaginatedRanges: [Range<Int>]
) -> NovelTextPagination {
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
                pages: ranges.enumerated().map { index, range in
                    NovelTextViewportIndexPage(
                        pageIndex: index,
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
                    NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
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
        viewportPageLayout: { context, _, _ in
            [NovelTextViewportDocumentPageRange(startOffset: 0, endOffset: context.document.text.count)]
        },
        usesViewportIndexCache: false
    )
}

private func assertLongCurrentWebpageViewportState(
    _ state: NovelReadingWorkflowState,
    chapterTitles: [String],
    currentPageIndex: Int,
    currentChapterTitle: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(state.snapshot.pages.count, chapterTitles.count, file: file, line: line)
    XCTAssertTrue(state.snapshot.pages.allSatisfy { !$0.ranges.isEmpty }, file: file, line: line)
    XCTAssertEqual(state.snapshot.chapters.map(\.title), chapterTitles, file: file, line: line)
    XCTAssertEqual(state.snapshot.chapters.map(\.startIndex), Array(chapterTitles.indices), file: file, line: line)
    XCTAssertEqual(state.snapshot.currentPageIndex, currentPageIndex, file: file, line: line)
    XCTAssertEqual(state.snapshot.currentChapterTitle, currentChapterTitle, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.identity.documentView, 1, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.diagnostics.indexBuildCount, 1, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.diagnostics.visibleLayoutPassCount, 0, file: file, line: line)
    XCTAssertEqual(
        state.snapshot.viewportContext?.diagnostics.compatibilityTextDisplayValueCount,
        0,
        file: file,
        line: line
    )
    XCTAssertEqual(state.snapshot.viewportIndex?.pages.count, chapterTitles.count, file: file, line: line)
    XCTAssertEqual(
        state.snapshot.viewportIndex?.pages[currentPageIndex].ranges.first?.segmentIndex,
        currentPageIndex,
        file: file,
        line: line
    )
}
