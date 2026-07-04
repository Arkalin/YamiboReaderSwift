import Foundation
import CoreGraphics
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

private typealias NovelTextLayoutFixture = @Sendable (
    ReaderPageDocument,
    ReaderAppearanceSettings,
    ReaderContainerLayout
) throws -> NovelTextLayoutResult

final class ReaderContainerModelTests: XCTestCase {
    func testPagedPagerIdentityChangesWhenRotationChangesPagedLayout() {
        let portrait = ReaderContainerLayout(
            containerSize: CGSize(width: 1032, height: 1376),
            readingMode: .paged
        )
        let landscape = ReaderContainerLayout(
            containerSize: CGSize(width: 1376, height: 1032),
            readingMode: .paged
        )

        let portraitIdentity = ReaderPagedPagerIdentity(
            visibleView: 1,
            surfaceCount: 342,
            spreadCount: 342,
            usesTwoPageSpread: false,
            layout: portrait
        )
        let landscapeIdentity = ReaderPagedPagerIdentity(
            visibleView: 1,
            surfaceCount: 342,
            spreadCount: 171,
            usesTwoPageSpread: true,
            layout: landscape
        )

        XCTAssertNotEqual(portraitIdentity, landscapeIdentity)
    }

    func testPagedPagerIdentityIgnoresCurrentPageChanges() {
        let layout = ReaderContainerLayout(
            containerSize: CGSize(width: 1376, height: 1032),
            readingMode: .paged
        )

        let first = ReaderPagedPagerIdentity(
            visibleView: 1,
            surfaceCount: 342,
            spreadCount: 171,
            usesTwoPageSpread: true,
            layout: layout
        )
        let second = ReaderPagedPagerIdentity(
            visibleView: 1,
            surfaceCount: 342,
            spreadCount: 171,
            usesTwoPageSpread: true,
            layout: layout
        )

        XCTAssertEqual(first, second)
    }

    func testChapterTextFormatterSplitsLeadingChapterTitle() {
        let split = ReaderChapterTextComponents.split(
            text: "第一章\n这里是正文",
            chapterTitle: "第一章"
        )

        XCTAssertEqual(split.title, "第一章")
        XCTAssertEqual(split.body, "\n这里是正文")
    }

    func testChapterTextFormatterDoesNotSplitWhenTitleIsNotLeadingLine() {
        let split = ReaderChapterTextComponents.split(
            text: "序章\n第一章",
            chapterTitle: "第一章"
        )

        XCTAssertNil(split.title)
        XCTAssertNil(split.body)
    }

    func testMovesAcrossWebViewBoundaries() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await MainActor.run {
            model.jumpToSurface(model.surfaceCount - 1)
            XCTAssertEqual(model.currentSurfaceNumber, model.surfaceCount)
        }

        await model.jumpRelativeSurface(1)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
        }

        await model.jumpRelativeSurface(-1)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentSurfaceNumber, model.surfaceCount)
        }
    }

    func testWebViewBoundaryNavigationPublishesLoadingOverlayState() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章", "第三章", "第四章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第五章", "第六章"]),
            ]
        )
        let navigationStateRecorder = await MainActor.run {
            let recorder = ReaderNavigationStateRecorder()
            let gate = ReaderNavigationOverlayGate()
            model.readerPageDocumentNavigationOverlayPreparation = {
                await gate.prepare()
            }
            model.readerPageDocumentNavigationStateDidChange = { state in
                recorder.record(state)
            }
            return (recorder, gate)
        }

        let navigationTask = Task {
            await model.jumpToWebView(2)
        }

        try await waitFor {
            await MainActor.run {
                navigationStateRecorder.1.didEnterPreparation
            }
        }

        await MainActor.run {
            XCTAssertTrue(navigationStateRecorder.0.states.contains(true))
            XCTAssertTrue(model.isNavigatingReaderPageDocument)
            XCTAssertEqual(model.currentView, 1)
            navigationStateRecorder.1.release()
        }
        await navigationTask.value

        await MainActor.run {
            XCTAssertEqual(navigationStateRecorder.0.states, [true, false])
            XCTAssertFalse(model.isNavigatingReaderPageDocument)
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
        }
    }

    func testNavigationHistoryRestoresPreviousNovelReadingPositionAcrossWebViews() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertFalse(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }

        await model.jumpToWebView(2)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertTrue(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }

        await model.navigateBack()
        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertFalse(model.canNavigateBack)
            XCTAssertTrue(model.canNavigateForward)
        }

        await model.navigateForward()
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertTrue(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }
    }

    func testNavigationHistoryClearsAfterFiveLinearPagedSurfaceTurns() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ]
        )

        await MainActor.run {
            model.jumpToSurface(1)
            XCTAssertTrue(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }

        for _ in 0..<4 {
            await model.jumpRelativeSurface(1)
        }
        await MainActor.run {
            XCTAssertTrue(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }

        await model.jumpRelativeSurface(1)
        await MainActor.run {
            XCTAssertFalse(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }
    }

    func testNavigationHistoryClearsAfterFiveLinearVerticalSurfaceChanges() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            model.jumpToSurface(1)
            XCTAssertTrue(model.canNavigateBack)
            model.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.2, force: true)
            model.updateVerticalViewportPosition(surfaceIndex: 1, intraSurfaceProgress: 0.5, force: true)
            XCTAssertTrue(model.canNavigateBack)

            for surfaceIndex in 2...5 {
                model.updateVerticalViewportPosition(surfaceIndex: surfaceIndex, intraSurfaceProgress: 0.3, force: true)
            }
            XCTAssertTrue(model.canNavigateBack)

            model.updateVerticalViewportPosition(surfaceIndex: 6, intraSurfaceProgress: 0.3, force: true)
            XCTAssertFalse(model.canNavigateBack)
            XCTAssertFalse(model.canNavigateForward)
        }
    }

    func testNavigationHistoryRestoreDoesNotPresentReaderPageDocumentNavigationOverlay() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"]),
            ]
        )
        let navigationStateRecorder = await MainActor.run {
            let recorder = ReaderNavigationStateRecorder()
            model.readerPageDocumentNavigationOverlayPreparation = {}
            model.readerPageDocumentNavigationStateDidChange = { state in
                recorder.record(state)
            }
            return recorder
        }

        await MainActor.run {
            model.jumpToSurface(model.surfaceCount - 1)
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentSurfaceNumber, model.surfaceCount)
            XCTAssertTrue(model.canNavigateBack)
            navigationStateRecorder.removeAll()
        }

        await model.navigateBack()

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
            XCTAssertFalse(model.isNavigatingReaderPageDocument)
            XCTAssertEqual(navigationStateRecorder.states, [])
        }
    }

    func testPreviousWebViewBoundaryNavigationLandsOnPreviousLastSurfaceAfterOverlay() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章", "第三章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第四章", "第五章"]),
            ]
        )
        await model.jumpToWebView(2)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
        }
        let navigationStateRecorder = await MainActor.run {
            let recorder = ReaderNavigationStateRecorder()
            let gate = ReaderNavigationOverlayGate()
            model.readerPageDocumentNavigationOverlayPreparation = {
                await gate.prepare()
            }
            model.readerPageDocumentNavigationStateDidChange = { state in
                recorder.record(state)
            }
            return (recorder, gate)
        }

        let navigationTask = Task {
            await model.jumpRelativeSurface(-1)
        }

        try await waitFor {
            await MainActor.run {
                navigationStateRecorder.1.didEnterPreparation
            }
        }

        await MainActor.run {
            XCTAssertTrue(navigationStateRecorder.0.states.contains(true))
            XCTAssertTrue(model.isNavigatingReaderPageDocument)
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
            navigationStateRecorder.1.release()
        }
        await navigationTask.value

        await MainActor.run {
            XCTAssertEqual(navigationStateRecorder.0.states, [true, false])
            XCTAssertFalse(model.isNavigatingReaderPageDocument)
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentSurfaceNumber, model.surfaceCount)
        }
    }

    func testPublishesPresentationAndRequestsDisplayReferencesBySurfaceIdentity() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let initialPresentation = try await MainActor.run {
            try XCTUnwrap(model.readerPresentation)
        }
        let initialSurface = try XCTUnwrap(initialPresentation.selectedSurfaceIdentity)
        let initialReference = await MainActor.run {
            model.novelTextViewportDisplayReference(for: initialSurface)
        }
        let initialReferenceGeneration = await MainActor.run {
            initialReference?.generation
        }
        let modelPageIdentities = await MainActor.run {
            viewportSurfaces(in: model).map(\.surfaceOrdinal)
        }

        XCTAssertEqual(initialReferenceGeneration, initialPresentation.generation)
        XCTAssertEqual(initialPresentation.surfaces.map(\.presentationIndex), modelPageIdentities)

        await MainActor.run {
            model.jumpToSurface(min(1, max(model.surfaceCount - 1, 0)))
        }

        let navigatedPresentation = try await MainActor.run {
            try XCTUnwrap(model.readerPresentation)
        }

        XCTAssertEqual(navigatedPresentation.generation, initialPresentation.generation)
        XCTAssertEqual(navigatedPresentation.revision, initialPresentation.revision + 1)
    }

    func testTracksChapterBoundaries() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.currentChapterTitle, "第一章")
            XCTAssertFalse(model.hasPreviousChapter)
            XCTAssertTrue(model.hasNextChapter)
        }

        await MainActor.run {
            model.jumpToAdjacentChapter(1)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
            XCTAssertTrue(model.hasPreviousChapter)
            XCTAssertFalse(model.hasNextChapter)
        }

        await MainActor.run {
            model.jumpToAdjacentChapter(1)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
        }
    }

    func testCurrentChapterDirectoryChapterUsesOccurrenceInsteadOfTitle() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["同名章", "同名章"]),
            ]
        )

        await MainActor.run {
            let chapters = model.visibleChapterDirectoryChapters
            XCTAssertEqual(chapters.map(\.title), ["同名章", "同名章"])
            XCTAssertTrue(chapters.indices.contains(1))

            model.jumpToSurface(chapters[1].startIndex)

            XCTAssertEqual(model.currentChapterDirectoryIndex, 1)
            XCTAssertFalse(model.isCurrentChapterDirectoryChapter(chapters[0]))
            XCTAssertTrue(model.isCurrentChapterDirectoryChapter(chapters[1]))
        }
    }

    func testClampsWebJumpAndReportsProgress() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await MainActor.run {
            model.jumpToSurface(model.surfaceCount - 1)
            XCTAssertEqual(model.currentProgressFraction, 1)
            XCTAssertEqual(model.currentProgressPercentText, "100%")
        }

        await model.jumpToWebView(99)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
            XCTAssertEqual(model.currentWebViewText, "网页 2 / 2")
            XCTAssertEqual(model.directoryWebTitle, "网页 2 / 2 的章节")
        }
    }

    func testPreviewingChapterDirectoryWebViewDoesNotMoveReadingPosition() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await MainActor.run {
            model.jumpToSurface(model.surfaceCount - 1)
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
        }

        await model.previewChapterDirectoryWebView(2)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
            XCTAssertEqual(model.currentSurfaceNumber, model.surfaceCount)
            XCTAssertEqual(model.visibleChapterDirectoryView, 2)
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第三章", "第四章"])
            XCTAssertEqual(model.previousChapterDirectoryWebView, 1)
            XCTAssertNil(model.nextChapterDirectoryWebView)
            XCTAssertNil(model.currentChapterDirectoryIndex)
        }
    }

    func testPreviewingCurrentChapterDirectoryWebViewReturnsToReadingDirectory() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await model.previewChapterDirectoryWebView(2)
        await MainActor.run {
            XCTAssertEqual(model.visibleChapterDirectoryView, 2)
            XCTAssertEqual(model.previousChapterDirectoryWebView, 1)
            XCTAssertNil(model.nextChapterDirectoryWebView)
        }

        await model.previewChapterDirectoryWebView(1)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.visibleChapterDirectoryView, 1)
            XCTAssertNil(model.previousChapterDirectoryWebView)
            XCTAssertEqual(model.nextChapterDirectoryWebView, 2)
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第一章", "第二章"])
            XCTAssertEqual(model.currentChapterDirectoryIndex, model.currentChapterIndex)
        }
    }

    func testSelectingPreviewedChapterDirectoryChapterMovesReaderToThatChapter() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章"]),
            ]
        )

        await model.previewChapterDirectoryWebView(2)
        let target = try await MainActor.run {
            try XCTUnwrap(model.visibleChapterDirectoryChapters.first(where: { $0.title == "第四章" }))
        }
        await model.jumpToChapterDirectoryChapter(target)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第四章")
            XCTAssertEqual(model.visibleChapterDirectoryView, model.visibleView)
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第三章", "第四章"])
        }
    }

    func testSelectingPreviewedChapterDirectoryChapterKeepsPagedSelectionOnTargetPage() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章", "第四章", "第五章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        await model.previewChapterDirectoryWebView(2)
        let target = try await MainActor.run {
            try XCTUnwrap(model.visibleChapterDirectoryChapters.first(where: { $0.title == "第五章" }))
        }
        await model.jumpToChapterDirectoryChapter(target)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第五章")
            XCTAssertGreaterThan(model.pagedViewportSelectionIndex, 0)
            XCTAssertEqual(viewportSurfaces(in: model)[model.selectedSurfaceIndex].chapterTitle, "第五章")
        }
    }

    func testChapterTitleHelperResolvesSurfaceChapter() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.chapterTitle(forSurfaceIndex: 0), "第一章")
            XCTAssertEqual(model.chapterTitle(forSurfaceIndex: model.surfaceCount - 1), "第二章")
            XCTAssertEqual(model.chapterTitle(forSurfaceIndex: 999), "第二章")
        }
    }

    func testProgressChapterTickStartIndexMatchesChapterBoundaryPages() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 1, surfaceCount: 5),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        await MainActor.run {
            XCTAssertEqual(model.progressChapterTickStartIndex(forSurfaceIndex: 0), 0)
            XCTAssertEqual(model.progressChapterTickStartIndex(forSurfaceIndex: 3), 3)
            XCTAssertEqual(model.progressChapterTickStartIndex(forSurfaceIndex: 999), 4)
        }
    }

    func testTargetSurfaceIndexMapsPagedAndVerticalProgress() async throws {
        let pagedModel = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )
        let verticalModel = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            XCTAssertEqual(pagedModel.targetSurfaceIndex(forProgressValue: -3), 0)
            XCTAssertEqual(pagedModel.targetSurfaceIndex(forProgressValue: 999), pagedModel.surfaceCount - 1)
            XCTAssertEqual(verticalModel.targetSurfaceIndex(forProgressValue: 0), 0)
            XCTAssertEqual(verticalModel.targetSurfaceIndex(forProgressValue: 100), verticalModel.surfaceCount - 1)
        }
    }

    func testVerticalProgressScrubContextUsesCachedCurrentViewSurfaceMapping() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 1, surfaceCount: 5),
            ],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            let context = model.verticalProgressScrubContext

            XCTAssertEqual(context.targetIndex(0), 0)
            XCTAssertEqual(context.targetIndex(0.5), 2)
            XCTAssertEqual(context.targetIndex(1), 4)
            XCTAssertEqual(context.targetIndex(-0.25), 0)
            XCTAssertEqual(context.targetIndex(2.5), 4)
            XCTAssertEqual(context.title(2), "第3章")
            XCTAssertEqual(context.tickTargetIndex(2), 2)
        }
    }

    func testChromeProgressSnapshotUsesLargeVerticalProjection() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 1, surfaceCount: 800),
            ],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            model.selectSurface(799)
            let snapshot = model.chromeProgressSnapshot

            XCTAssertEqual(snapshot.surfaceCount, 800)
            XCTAssertEqual(snapshot.currentSurfaceNumber, 800)
            XCTAssertEqual(snapshot.currentProgressPercentText, "100%")
            XCTAssertEqual(snapshot.targetSurfaceIndex(forProgressValue: 0), 0)
            XCTAssertEqual(snapshot.targetSurfaceIndex(forProgressValue: 50), 399)
            XCTAssertEqual(snapshot.targetSurfaceIndex(forProgressValue: 100), 799)
            XCTAssertEqual(snapshot.chapterTitle(forSurfaceIndex: 399), "第400章")
            XCTAssertEqual(snapshot.progressChapterTickStartIndex(forSurfaceIndex: 399), 399)

            let revision = model.readerPresentation?.revision
            for _ in 0..<100 {
                _ = model.chromeProgressSnapshot.progressText
                _ = model.chromeProgressSnapshot.currentProgressPercentText
                _ = model.chromeProgressSnapshot.progressChapterTicks
                _ = model.chromeProgressSnapshot.progressScrubContext.targetIndex(0.5)
            }
            XCTAssertEqual(model.readerPresentation?.revision, revision)
        }
    }

    func testVerticalProgressScrubContextClampsSingleSurfaceWithoutChapters() async throws {
        let document = ReaderPageDocument(
            threadID: "445566",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text("没有章节标题的正文。", chapterTitle: nil),
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            let context = model.verticalProgressScrubContext

            XCTAssertEqual(context.targetIndex(0), 0)
            XCTAssertEqual(context.targetIndex(0.5), 0)
            XCTAssertEqual(context.targetIndex(1), 0)
            XCTAssertNil(context.title(0))
            XCTAssertNil(context.tickTargetIndex(0))
        }
    }

    func testVerticalNearEndPrefetchDoesNotMergeNextWebView() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        await MainActor.run {
            model.selectSurface(max(model.surfaceCount - 1, 0))
        }

        try await waitFor {
            await MainActor.run {
                model.currentProgressPercentText == "100%"
            }
        }

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(Set(viewportSurfaces(in: model).map(\.documentView)), [1])
            XCTAssertEqual(model.currentProgressPercentText, "100%")
            XCTAssertEqual(
                model.targetSurfaceIndex(forProgressValue: 100),
                viewportSurfaces(in: model).lastIndex(where: { $0.documentView == 1 })
            )
        }

        await model.jumpRelativeSurface(1)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentSurfaceNumber, 1)
            XCTAssertEqual(Set(viewportSurfaces(in: model).map(\.documentView)), [2])
        }
    }

    func testPagedNearEndPrefetchDoesNotMergeNextWebView() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章", "第二章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第三章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        await MainActor.run {
            model.selectSurface(max(model.surfaceCount - 1, 0))
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(Set(viewportSurfaces(in: model).map(\.documentView)), [1])
        }
    }

    func testProgressSliderPreviewLabelUsesEditingTargetPage() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 1, surfaceCount: 5),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        await MainActor.run {
            let targetIndex = model.targetSurfaceIndex(forProgressValue: 3)
            XCTAssertEqual(targetIndex, 3)
            XCTAssertEqual(
                model.progressSliderLabelText(
                    isEditing: true,
                    sliderValue: 3,
                    targetSurfaceIndex: targetIndex
                ),
                "4 / 5"
            )
            XCTAssertEqual(
                model.progressSliderLabelText(
                    isEditing: false,
                    sliderValue: 3,
                    targetSurfaceIndex: targetIndex
                ),
                "1 / 5"
            )
        }
    }

    func testChromeProgressProjectionUsesNeutralProgressForSharedChrome() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 1, surfaceCount: 5),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        await MainActor.run {
            model.selectSurface(2)
            let progress = model.chromeProgressSnapshot.chromeProgress

            XCTAssertEqual(progress.itemCount, 5)
            XCTAssertEqual(progress.currentIndex, 2)
            XCTAssertEqual(progress.progressFraction, 0.5, accuracy: 0.001)
            XCTAssertEqual(progress.percentText, "50%")
            XCTAssertEqual(progress.targetIndex(forProgressFraction: 0.75), 3)
            XCTAssertEqual(progress.positionFraction(forTargetIndex: 3), 0.75, accuracy: 0.001)
            XCTAssertEqual(progress.title(forTargetIndex: 2), "第3章")
            XCTAssertEqual(progress.tickTargetIndex(forTargetIndex: 2), 2)
        }
    }

    func testTwoPageSpreadRequiresPadLandscapePagedModeAndSetting() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, surfaceCount: 5)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }
        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }

        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )
        await MainActor.run {
            XCTAssertTrue(model.isTwoPageSpreadActive)
        }

        await model.commitNovelTextAppearance(
            ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .vertical
            )
        )
        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }

        await model.commitNovelTextAppearance(
            ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: false,
                readingMode: .paged
            )
        )
        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }
    }

    func testTwoPageSpreadBuildsExpectedPairsAndProgressText() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, surfaceCount: 5)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertEqual(
                model.presentationSpreads.map { "\($0.leftSurfaceIndex)-\($0.rightSurfaceIndex.map(String.init) ?? "nil")" },
                ["0-1", "2-3", "4-nil"]
            )
            XCTAssertEqual(model.selectedSurfaceIndex, 1)
            XCTAssertEqual(model.currentSurfaceNumber, 2)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 0)
            XCTAssertTrue(model.progressText.contains("第 1-2 / 5 页"))

            model.jumpToSurface(4)
            XCTAssertEqual(model.selectedSurfaceIndex, 4)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 2)
            XCTAssertTrue(model.progressText.contains("第 5 / 5 页"))
        }
    }

    func testLeftToRightTwoPageSpreadMapsSliderAndPagingToRightAnchor() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, surfaceCount: 6)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 1), 1)
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 5), 5)

            model.jumpToSurface(0)
            XCTAssertEqual(model.selectedSurfaceIndex, 1)
            model.jumpToSurface(3)
            XCTAssertEqual(model.selectedSurfaceIndex, 3)
        }

        await model.jumpRelativeSurface(1)
        await MainActor.run {
            XCTAssertEqual(model.selectedSurfaceIndex, 5)
            XCTAssertEqual(model.currentSurfaceNumber, 6)
        }

        await MainActor.run {
            model.selectPagedViewportIndex(1)
            XCTAssertEqual(model.selectedSurfaceIndex, 3)
        }
    }

    func testRightToLeftTwoPageSpreadMapsSliderAndPagingToLeftAnchor() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, surfaceCount: 6)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged,
                pageTurnDirection: .rightToLeft
            )
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 1), 0)
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 5), 4)

            model.jumpToSurface(1)
            XCTAssertEqual(model.selectedSurfaceIndex, 0)
            model.jumpToSurface(3)
            XCTAssertEqual(model.selectedSurfaceIndex, 2)
        }

        await model.jumpRelativeSurface(1)
        await MainActor.run {
            XCTAssertEqual(model.selectedSurfaceIndex, 4)
            XCTAssertEqual(model.currentSurfaceNumber, 5)
        }

        await MainActor.run {
            model.selectPagedViewportIndex(1)
            XCTAssertEqual(model.selectedSurfaceIndex, 2)
        }
    }

    func testTwoPageSpreadMovesToNextWebViewAfterLastCompleteSpread() async throws {
        let model = try await makeModel(
            documents: [
                makeImageDocument(view: 1, maxView: 2, surfaceCount: 6),
                makeImageDocument(view: 2, maxView: 2, surfaceCount: 4),
            ],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )

        await MainActor.run {
            model.jumpToSurface(5)
            XCTAssertEqual(model.selectedSurfaceIndex, 5)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 2)
        }

        await model.jumpRelativeSurface(1)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.selectedSurfaceIndex, 1)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 0)
        }
    }

    func testTwoPageSpreadRepaginatesTextForHalfWidthColumns() async throws {
        let document = ReaderPageDocument(
            threadID: "9911",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 420), chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                width: 844,
                height: 390,
                readingMode: .paged
            )
        )
        await MainActor.run {
            XCTAssertTrue(model.isTwoPageSpreadActive)
            XCTAssertGreaterThan(model.surfaceCount, 0)
            XCTAssertFalse(model.presentationSpreads.isEmpty)
        }
    }

    func testLatestLandscapeLayoutSupersedesInFlightPortraitLayoutMatchingCommittedLayout() async throws {
        let document = ReaderPageDocument(
            threadID: "9912",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 前台恢复布局竞态。", count: 1_200), chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )
        let portrait = ReaderContainerLayout(
            width: 1032,
            height: 1376,
            readingMode: .paged
        )
        let landscape = ReaderContainerLayout(
            width: 1376,
            height: 1032,
            readingMode: .paged
        )

        await model.commitNovelTextPresentationEnvironment(isPad: true)
        await model.commitNovelTextLayout(landscape)
        await MainActor.run {
            model.jumpToSurface(max(model.surfaceCount / 2, 0))
        }

        let initialState = try await MainActor.run {
            (
                try XCTUnwrap(model.readerPresentation),
                try XCTUnwrap(model.novelReaderDebugState),
                try XCTUnwrap(model.currentNovelResumePoint)
            )
        }
        let gate = ReaderLayoutUpdatePreparationGate(blockedLayout: portrait)
        await MainActor.run {
            model.runtimeUpdatePreparation = { update in
                await gate.prepare(update)
            }
        }

        let portraitTask = Task {
            await model.commitNovelTextLayout(portrait)
        }
        await gate.waitUntilBlocked()

        await model.commitNovelTextLayout(landscape)
        await gate.release()
        await portraitTask.value

        await MainActor.run {
            let finalPresentation = try? XCTUnwrap(model.readerPresentation)
            let finalDebugState = try? XCTUnwrap(model.novelReaderDebugState)
            let finalResumePoint = try? XCTUnwrap(model.currentNovelResumePoint)

            XCTAssertTrue(model.isTwoPageSpreadActive)
            XCTAssertEqual(finalPresentation?.generation, initialState.0.generation + 1)
            XCTAssertEqual(finalPresentation?.surfaces.count, initialState.0.surfaces.count)
            XCTAssertEqual(finalDebugState?.fingerprints?.layout, initialState.1.fingerprints?.layout)
            XCTAssertEqual(
                finalDebugState?.transactions.committedTransactionCount,
                initialState.1.transactions.committedTransactionCount + 1
            )
            XCTAssertEqual(finalResumePoint?.view, initialState.2.view)
            XCTAssertEqual(finalResumePoint?.chapterIdentity, initialState.2.chapterIdentity)
            XCTAssertEqual(finalResumePoint?.textSegmentIdentity, initialState.2.textSegmentIdentity)
            XCTAssertEqual(finalResumePoint?.displayedTextOffset, initialState.2.displayedTextOffset)
            XCTAssertNil(model.errorMessage)
        }
    }

    func testRepeatedCommittedLayoutDoesNotCreateRuntimeTransaction() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )
        let layout = ReaderContainerLayout(
            width: 844,
            height: 390,
            readingMode: .paged
        )

        await model.commitNovelTextLayout(layout)
        let committedState = try await MainActor.run {
            (
                try XCTUnwrap(model.readerPresentation),
                try XCTUnwrap(model.novelReaderDebugState)
            )
        }

        await model.commitNovelTextLayout(layout)

        await MainActor.run {
            XCTAssertEqual(model.readerPresentation?.generation, committedState.0.generation)
            XCTAssertEqual(
                model.novelReaderDebugState?.transactions,
                committedState.1.transactions
            )
        }
    }

    func testFailedLayoutRequestCanRetrySameLayout() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )
        let targetLayout = ReaderContainerLayout(
            width: 390,
            height: 844,
            readingMode: .paged
        )
        let initialState = try await MainActor.run {
            (
                try XCTUnwrap(model.readerPresentation),
                try XCTUnwrap(model.novelReaderDebugState)
            )
        }
        let failureInjector = ReaderLayoutUpdateFailureInjector(failingLayout: targetLayout)
        await MainActor.run {
            model.runtimeUpdatePreparation = { update in
                try await failureInjector.prepare(update)
            }
        }

        await model.commitNovelTextLayout(targetLayout)
        await MainActor.run {
            XCTAssertEqual(model.readerPresentation?.generation, initialState.0.generation)
            XCTAssertEqual(model.novelReaderDebugState?.transactions, initialState.1.transactions)
            XCTAssertEqual(model.errorMessage, NovelTextLayoutFailure.textKitIndexing.localizedDescription)
        }

        await model.commitNovelTextLayout(targetLayout)

        let attemptCount = await failureInjector.attemptCount
        await MainActor.run {
            XCTAssertEqual(attemptCount, 2)
            XCTAssertEqual(model.readerPresentation?.generation, initialState.0.generation + 1)
            XCTAssertNotEqual(
                model.novelReaderDebugState?.fingerprints?.layout,
                initialState.1.fingerprints?.layout
            )
            XCTAssertEqual(
                model.novelReaderDebugState?.transactions.committedTransactionCount,
                initialState.1.transactions.committedTransactionCount + 1
            )
        }
    }

    func testApplySettingsUpdatesStoredReaderSettings() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ]
        )
        let updated = ReaderAppearanceSettings(
            fontScale: 1.2,
            fontFamily: .rounded,
            lineHeightScale: 1.7,
            characterSpacingScale: 0.05,
            horizontalPadding: 22,
            usesJustifiedText: true,
            loadsInlineImages: false,
            showsAuthorRepliesToOthers: false,
            backgroundStyle: .paper,
            readingMode: .vertical,
            translationMode: .traditional
        )

        await model.commitNovelTextAppearance(updated)
        await MainActor.run {
            XCTAssertEqual(model.settings, updated)
        }
    }

    func testLayoutSettingsFailureKeepsCommittedSettingsAndDoesNotPersistDraft() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let initialSettings = ReaderAppearanceSettings(fontScale: 1.0, readingMode: .paged)
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
        try await settingsStore.save(AppSettings(reader: initialSettings))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
            pagination: { document, settings, layout in
                if settings.fontScale > 1.1 {
                    throw NovelTextLayoutFailure.textKitIndexing
                }
                return try readerModelSegmentPagination(document: document, settings: settings, layout: layout)
            }
        )
        }
        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        var failedSettings = initialSettings
        failedSettings.fontScale = 1.2

        await model.commitNovelTextAppearance(failedSettings)
        await MainActor.run {
            XCTAssertEqual(model.settings, initialSettings)
            XCTAssertEqual(model.errorMessage, NovelTextLayoutFailure.textKitIndexing.localizedDescription)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let loaded = await settingsStore.load()
        XCTAssertEqual(loaded.reader, initialSettings)
    }

    func testSurfaceOnlyAppearanceSettingsPublishRevisionWithoutRuntimeRebuild() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let initialSettings = ReaderAppearanceSettings(backgroundStyle: .system, readingMode: .paged)
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
        try await settingsStore.save(AppSettings(reader: initialSettings))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelPreviewSourcePagination
            )
        }
        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let initialPresentation = try await MainActor.run { try XCTUnwrap(model.readerPresentation) }
        var updatedSettings = initialSettings
        updatedSettings.backgroundStyle = .paper

        await model.commitNovelTextAppearance(updatedSettings)
        let updatedPresentation = try await MainActor.run { try XCTUnwrap(model.readerPresentation) }

        XCTAssertEqual(updatedPresentation.generation, initialPresentation.generation)
        XCTAssertEqual(updatedPresentation.revision, initialPresentation.revision + 1)
        XCTAssertEqual(updatedPresentation.committedSettings, updatedSettings)

        try await waitFor {
            await settingsStore.load().reader == updatedSettings
        }
    }

    func testApplySettingsPersistsSharedApplePencilSettingsWithoutOverwritingMangaSettings() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
        let initialMangaSettings = MangaReaderSettings(
            readingMode: .paged,
            pageEdgeFillStyle: .system,
            brightness: 0.82,
            zoomEnabled: false,
            showsTwoPagesInLandscapeOnPad: true,
            directorySortOrder: .descending
        )
        try await settingsStore.save(
            AppSettings(
                reader: ReaderAppearanceSettings(readingMode: .paged),
                manga: initialMangaSettings
            )
        )
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }
        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let updatedReaderSettings = ReaderAppearanceSettings(
            fontScale: 1.2,
            readingMode: .vertical
        )
        let updatedApplePencilSettings = ApplePencilPageTurnSettings(
            isEnabled: true,
            behavior: .doubleTapNextSqueezePrevious
        )
        await model.commitNovelTextAppearance(
            updatedReaderSettings,
            applePencilPageTurnSettings: updatedApplePencilSettings
        )

        try await waitFor {
            let loaded = await settingsStore.load()
            return loaded.reader == updatedReaderSettings &&
                loaded.applePencilPageTurn == updatedApplePencilSettings
        }

        let loaded = await settingsStore.load()
        XCTAssertEqual(loaded.manga, initialMangaSettings)
    }

    func testNovelTextLayoutFailureSurfacesAsReaderErrorWithoutEmptyContent() async throws {
        let failure = NovelTextLayoutFailure.textKitIndexing
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章"])
            ],
            pagination: { _, _, _ in throw failure }
        )

        await MainActor.run {
            XCTAssertEqual(model.errorMessage, failure.localizedDescription)
            XCTAssertTrue(viewportSurfaces(in: model).isEmpty)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testChapterDirectoryPreviewDoesNotCreateLayoutCandidate() async throws {
        let failure = NovelTextLayoutFailure.textKitIndexing
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 2, chapterTitles: ["第一章"]),
                makeDocument(view: 2, maxView: 2, chapterTitles: ["第二章"])
            ],
            pagination: { document, settings, layout in
                guard document.view == 1 else { throw failure }
                return try readerModelSegmentPagination(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )

        await model.previewChapterDirectoryWebView(2)

        await MainActor.run {
            XCTAssertNil(model.chapterDirectoryError)
            XCTAssertEqual(model.visibleChapterDirectoryView, 2)
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第二章"])
            XCTAssertEqual(model.chapterDirectoryPageCount, 0)
            XCTAssertFalse(model.isLoadingChapterDirectory)
        }
    }

    func testChapterDirectoryPreviewHidesAuthorRepliesToOthersAcrossWebViews() async throws {
        let threadID = "889900"
        let documents = [
            ReaderPageDocument(
                threadID: threadID,
                view: 1,
                maxView: 2,
                resolvedAuthorID: "42",
                contentSource: .authorFilteredPage,
                segments: [
                    .text(String(repeating: "第一章 正文。", count: 40), chapterTitle: "第一章"),
                    .text(String(repeating: "读者甲 发表于 2026-5-1\n楼主回复。", count: 12), chapterTitle: "读者甲 发表于 2026-5-1"),
                ],
                segmentSources: [
                    ReaderSegmentSource(ownerPostID: "1001"),
                    ReaderSegmentSource(ownerPostID: "1002", isAuthorReplyToOther: true),
                ]
            ),
            ReaderPageDocument(
                threadID: threadID,
                view: 2,
                maxView: 2,
                resolvedAuthorID: "42",
                contentSource: .authorFilteredPage,
                segments: [
                    .text(String(repeating: "第二章 正文。", count: 40), chapterTitle: "第二章"),
                    .text(String(repeating: "读者乙 发表于 2026-5-2\n楼主回复。", count: 12), chapterTitle: "读者乙 发表于 2026-5-2"),
                    .text(String(repeating: "第三章 正文。", count: 40), chapterTitle: "第三章"),
                ],
                segmentSources: [
                    ReaderSegmentSource(ownerPostID: "2001"),
                    ReaderSegmentSource(ownerPostID: "2002", isAuthorReplyToOther: true),
                    ReaderSegmentSource(ownerPostID: "2003"),
                ]
            ),
        ]
        let model = try await makeModel(
            documents: documents,
            settings: ReaderAppearanceSettings(showsAuthorRepliesToOthers: false, readingMode: .vertical),
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            )
        )

        await MainActor.run {
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第一章"])
        }

        await model.previewChapterDirectoryWebView(2)

        await MainActor.run {
            XCTAssertNil(model.chapterDirectoryError)
            XCTAssertEqual(model.visibleChapterDirectoryView, 2)
            XCTAssertEqual(model.visibleChapterDirectoryChapters.map(\.title), ["第二章", "第三章"])
        }
    }

    func testUpdatingLayoutRepaginatesPagedContentAndKeepsCurrentSegment() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let initialPageCount = await MainActor.run { model.surfaceCount }

        await MainActor.run {
            model.jumpToSurface(min(1, max(initialPageCount - 1, 0)))
        }
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                containerSize: CGSize(width: 390, height: 844),
                safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
                contentInsets: ReaderLayoutInsets(leading: 16, trailing: 16),
                chromeInsets: ReaderLayoutInsets(top: 88, bottom: 108),
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertGreaterThan(model.surfaceCount, 0)
            XCTAssertEqual(model.currentView, 1)
            XCTAssertNotNil(model.currentChapterTitle)
            XCTAssertLessThan(model.selectedSurfaceIndex, model.surfaceCount)
        }
    }

    func testSettingsPreviewTextUsesDraftTranslationModeFromOriginalDocument() async throws {
        let document = ReaderPageDocument(
            threadID: "9012",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text("聽到弓莉這麼說，我急忙收拾東西。戀上朋友的妹妹了 後記", chapterTitle: "後記")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(translationMode: .simplified)
        )

        await MainActor.run {
            XCTAssertTrue(
                model.previewText(translationMode: .none, characterCount: 80, fallback: "")
                    .contains("聽到弓莉這麼說")
            )
            XCTAssertTrue(
                model.previewText(translationMode: .simplified, characterCount: 80, fallback: "")
                    .contains("听到弓莉这么说")
            )
            XCTAssertTrue(
                model.previewText(translationMode: .traditional, characterCount: 80, fallback: "")
                    .contains("戀上朋友的妹妹了 後記")
            )
        }
    }

    func testWorkflowBackedPreviewAndProgressStayAlignedAfterVerticalViewportMovement() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadID = "9013"
        let document = ReaderPageDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("第一段不应预览", chapterTitle: "第一章"),
                .text("第二段不应预览", chapterTitle: "第一章"),
                .text("0123456789第三段预览", chapterTitle: "第一章")
            ]
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: "测试线程",
                    source: .favorites,
                    authorID: "author-1"
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        let targetOffset = "0123456789".count
        let previewTarget = try await MainActor.run {
            try XCTUnwrap(
                zip(model.readerSurfaces, model.novelReaderDebugState?.viewportSurfaces ?? []).first { _, page in
                    page.ranges.contains { $0.segmentIndex == 2 }
                }
            )
        }
        let intraSurfaceProgress = try pageProgress(
            in: previewTarget.1,
            segmentIndex: 2,
            segmentOffset: targetOffset
        )
        await MainActor.run {
            model.updateVerticalViewportPosition(
                surfaceIndex: previewTarget.0.presentationIndex,
                intraSurfaceProgress: intraSurfaceProgress
            )
        }

        await MainActor.run {
            let preview = model.previewText(translationMode: .none, characterCount: 40, fallback: "")
            XCTAssertTrue(preview.hasPrefix("第三段预览"))
            XCTAssertFalse(preview.contains("第一段不应预览"))
            XCTAssertFalse(preview.contains("第二段不应预览"))
        }

        let resumeContext = await model.saveProgress()

        let readingProgress = await readingProgressStore.load(threadID: threadID)
        let savedResumePoint = try XCTUnwrap(readingProgress?.novel?.novelResumePoint)
        XCTAssertEqual(savedResumePoint.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity))
        XCTAssertEqual(savedResumePoint.displayedTextOffset, targetOffset)
        XCTAssertEqual(resumeContext.initialResumePoint, savedResumePoint)
        XCTAssertEqual(resumeContext.initialView, savedResumePoint.view)
    }

    func testForumNovelProgressDoesNotCreateFavorite() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await MainActor.run {
            model.selectSurface(1)
            model.selectSurface(2)
        }
        await model.saveProgress()

        let favorites = await appContext.localFavoriteLibraryStore.load().items
        let readingProgress = await readingProgressStore.load(threadID: document.threadID)
        XCTAssertTrue(favorites.isEmpty)
        XCTAssertNotNil(readingProgress?.novel)
    }

    func testNovelProgressPersistsReaderResumeRoute() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let readerResumeRouteStore = try ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "readerRoute")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerResumeRouteStore: readerResumeRouteStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination,
                onReaderResumeRouteChange: { route in
                    try? await readerResumeRouteStore.saveReadingPosition(route)
                }
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await MainActor.run {
            model.updateVerticalViewportPosition(surfaceIndex: 2, intraSurfaceProgress: 0.55, force: true)
        }
        let savedContext = await model.saveProgress()

        guard case let .novel(context)? = await readerResumeRouteStore.load() else {
            return XCTFail("Expected novel resume route")
        }
        XCTAssertEqual(context.threadID, document.threadID)
        XCTAssertEqual(context.threadTitle, "测试线程")
        XCTAssertEqual(context.source, .resume)
        XCTAssertEqual(context.initialView, 1)
        XCTAssertEqual(context.initialResumePoint?.view, 1)
        XCTAssertEqual(savedContext, context)
    }

    func testLateNovelSaveAfterDismissDoesNotRecreateReaderResumeRoute() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let readerResumeRouteStore = try ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "readerRoute")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerResumeRouteStore: readerResumeRouteStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let appModel = await MainActor.run {
            YamiboAppModel(appContext: appContext)
        }
        let model = await MainActor.run {
            let context = ReaderLaunchContext(
                threadID: document.threadID,
                threadTitle: "测试线程",
                source: .forum
            )
            appModel.presentReader(context)
            return ReaderContainerModel(
                context: context,
                appContext: appContext,
                pagination: readerModelSegmentPagination,
                onReaderResumeRouteChange: { route in
                    appModel.updateReaderResumeRoute(route)
                }
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await MainActor.run {
            model.selectSurface(2)
        }
        await model.saveProgress()
        try await waitFor {
            await readerResumeRouteStore.load() != nil
        }

        await MainActor.run {
            appModel.dismissReader()
        }
        await model.saveProgress()
        try await Task.sleep(nanoseconds: 100_000_000)

        let routeAfterLateSave = await readerResumeRouteStore.load()
        XCTAssertNil(routeAfterLateSave)
    }

    func testForumNovelProgressUpdatesExistingFavorite() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])
        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await MainActor.run {
            model.updateVerticalViewportPosition(surfaceIndex: 2, intraSurfaceProgress: 0.55, force: true)
        }
        await model.saveProgress()

        let readingProgress = await readingProgressStore.load(threadID: document.threadID)
        XCTAssertNotNil(readingProgress?.novel?.novelResumePoint)
    }

    func testVerticalModePersistsSemanticResumePoint() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = ReaderPageDocument(
            threadID: "901",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 220), chapterTitle: "第一章")
            ]
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try makeReadingProgressStore(defaultsSuiteName: defaultsSuiteName)

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let targetIndex = await MainActor.run { min(2, max(model.surfaceCount - 1, 0)) }
        let targetViewportSurface = try await MainActor.run {
            try viewportSurface(in: model, surfaceIndex: targetIndex)
        }
        let targetRange = try XCTUnwrap(targetViewportSurface.ranges.first)
        await MainActor.run {
            model.updateVerticalViewportPosition(surfaceIndex: targetIndex, intraSurfaceProgress: 0.55)
        }

        try await waitFor {
            let readingProgress = await readingProgressStore.load(threadID: document.threadID)
            return readingProgress?.novel?.novelResumePoint != nil
        }

        let readingProgress = await readingProgressStore.load(threadID: document.threadID)
        let savedResumePoint = try XCTUnwrap(readingProgress?.novel?.novelResumePoint)
        XCTAssertEqual(readingProgress?.novel?.lastView, 1)
        XCTAssertEqual(readingProgress?.novel?.lastChapter, "第一章")
        XCTAssertEqual(savedResumePoint.view, 1)
        XCTAssertEqual(savedResumePoint.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: targetRange.segmentIndex)?.textSegmentIdentity))
        XCTAssertTrue(savedResumePoint.displayedTextOffset > targetRange.startOffset)
        XCTAssertEqual(savedResumePoint.chapterTitle, "第一章")
    }

    func testVerticalModeRestoresStoredResumePointWithinChapter() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadID = "902"
        let document = ReaderPageDocument(
            threadID: threadID,
            view: 2,
            maxView: 2,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 120), chapterTitle: "第一章"),
                .text(String(repeating: "第二章 内容。", count: 120), chapterTitle: "第二章"),
                .text(String(repeating: "第三章 内容。", count: 120), chapterTitle: "第三章")
            ]
        )
        let pagination = try readerModelSegmentPagination(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let savedViewportSurface = try XCTUnwrap(
            pagination.viewportIndex.surfaces.first(where: { $0.chapterTitle == "第三章" && !$0.ranges.isEmpty })
        )
        let savedRange = try XCTUnwrap(savedViewportSurface.ranges.first)
        let savedSemantics = try XCTUnwrap(document.semantics(forSegmentIndex: savedRange.segmentIndex))
        let savedOffset = midpoint(in: savedRange)
        let savedResumePoint = ReaderResumePoint(
            view: 2,
            chapterIdentity: savedSemantics.chapterIdentity,
            textSegmentIdentity: try XCTUnwrap(savedSemantics.textSegmentIdentity),
            displayedTextOffset: savedOffset,
            chapterOrdinal: try XCTUnwrap(savedViewportSurface.chapterOrdinal),
            chapterTitle: savedViewportSurface.chapterTitle,
            segmentProgress: 0.5,
            authorID: nil,
            readingModeHint: .vertical
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")
        try await readingProgressStore.saveNovel(
            NovelReadingPosition(
                threadID: threadID,
                view: 2,
                maxView: 2,
                chapterTitle: "第三章",
                resumePoint: savedResumePoint
            )
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: "测试线程",
                    source: .favorites
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第三章")
            XCTAssertEqual(model.selectedSurfaceIndex, savedViewportSurface.surfaceOrdinal)
            XCTAssertEqual(viewportSurfaces(in: model)[model.selectedSurfaceIndex].ranges.first?.segmentIndex, savedRange.segmentIndex)
            XCTAssertGreaterThan(model.currentSurfaceIntraProgress, 0.2)
        }
    }

    func testVerticalModePersistsSmallIntraPageScrollAndRestoresIt() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadID = "905"
        let document = ReaderPageDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 420), chapterTitle: "第一章")
            ]
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let launchContext = ReaderLaunchContext(
            threadID: threadID,
            threadTitle: "测试线程",
            source: .favorites
        )
        let model = await MainActor.run {
            ReaderContainerModel(context: launchContext, appContext: appContext, pagination: readerModelSegmentPagination)
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let targetPage = try await MainActor.run {
            try XCTUnwrap(
                viewportSurfaces(in: model).first { page in
                    page.ranges.contains { $0.length > 50 }
                }
            )
        }
        await MainActor.run {
            model.updateVerticalViewportPosition(surfaceIndex: targetPage.surfaceOrdinal, intraSurfaceProgress: 0.50)
        }
        await model.saveProgress()
        await MainActor.run {
            model.updateVerticalViewportPosition(surfaceIndex: targetPage.surfaceOrdinal, intraSurfaceProgress: 0.59)
        }
        await model.saveProgress()
        let savedReadingProgress = await readingProgressStore.load(threadID: threadID)
        let savedProgressPercent = await MainActor.run { model.currentProgressPercent }
        XCTAssertEqual(savedReadingProgress?.novel?.novelDocumentSurfaceProgressPercent, savedProgressPercent)

        let restoredModel = await MainActor.run {
            ReaderContainerModel(context: launchContext, appContext: appContext, pagination: readerModelSegmentPagination)
        }

        await restoredModel.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(restoredModel.selectedSurfaceIndex, targetPage.surfaceOrdinal)
            XCTAssertEqual(
                viewportSurfaces(in: restoredModel)[restoredModel.selectedSurfaceIndex].ranges.first?.segmentIndex,
                targetPage.ranges.first?.segmentIndex
            )
            XCTAssertEqual(restoredModel.currentSurfaceIntraProgress, 0.59, accuracy: 0.02)
        }
    }

    func testStoredResumePointDeterminesPositionWhenPreparingReader() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadID = "904"
        let document = ReaderPageDocument(
            threadID: threadID,
            view: 2,
            maxView: 2,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 160), chapterTitle: "第一章"),
                .text(String(repeating: "第二章 内容。", count: 160), chapterTitle: "第二章"),
                .text(String(repeating: "第三章 内容。", count: 160), chapterTitle: "第三章")
            ]
        )
        let pagination = try readerModelSegmentPagination(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let savedViewportSurface = try XCTUnwrap(
            pagination.viewportIndex.surfaces.first(where: { $0.chapterTitle == "第二章" && !$0.ranges.isEmpty })
        )
        let savedRange = try XCTUnwrap(savedViewportSurface.ranges.first)
        let savedSemantics = try XCTUnwrap(document.semantics(forSegmentIndex: savedRange.segmentIndex))
        let savedResumePoint = ReaderResumePoint(
            view: 2,
            chapterIdentity: savedSemantics.chapterIdentity,
            textSegmentIdentity: try XCTUnwrap(savedSemantics.textSegmentIdentity),
            displayedTextOffset: savedRange.startOffset,
            chapterOrdinal: try XCTUnwrap(savedViewportSurface.chapterOrdinal),
            chapterTitle: savedViewportSurface.chapterTitle,
            segmentProgress: 0,
            authorID: nil,
            readingModeHint: .vertical
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")
        try await readingProgressStore.saveNovel(
            NovelReadingPosition(
                threadID: threadID,
                view: 2,
                maxView: 2,
                chapterTitle: "第二章",
                resumePoint: savedResumePoint
            )
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: "测试线程",
                    source: .favorites,
                    initialView: 2
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
            XCTAssertEqual(model.selectedSurfaceIndex, savedViewportSurface.surfaceOrdinal)
            XCTAssertEqual(viewportSurfaces(in: model)[model.selectedSurfaceIndex].ranges.first?.segmentIndex, savedRange.segmentIndex)
        }
    }

    func testPagedFavoriteLaunchKeepsSelectionOnSavedResumePoint() async throws {
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadID = "909"
        let document = ReaderPageDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 520), chapterTitle: "第一章")
            ]
        )
        let pagination = try readerModelSegmentPagination(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let savedViewportSurface = try XCTUnwrap(pagination.viewportIndex.surfaces.dropFirst().last { !$0.ranges.isEmpty })
        let savedRange = try XCTUnwrap(savedViewportSurface.ranges.first)
        let savedSemantics = try XCTUnwrap(document.semantics(forSegmentIndex: savedRange.segmentIndex))
        let savedResumePoint = ReaderResumePoint(
            view: 1,
            chapterIdentity: savedSemantics.chapterIdentity,
            textSegmentIdentity: try XCTUnwrap(savedSemantics.textSegmentIdentity),
            displayedTextOffset: savedRange.startOffset,
            chapterOrdinal: try XCTUnwrap(savedViewportSurface.chapterOrdinal),
            chapterTitle: savedViewportSurface.chapterTitle,
            segmentProgress: 0,
            authorID: nil,
            readingModeHint: .paged
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")
        try await readingProgressStore.saveNovel(
            NovelReadingPosition(
                threadID: threadID,
                view: 1,
                maxView: 1,
                chapterTitle: "第一章",
                resumePoint: savedResumePoint
            )
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: "测试线程",
                    source: .favorites
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.selectedSurfaceIndex, savedViewportSurface.surfaceOrdinal)
            XCTAssertEqual(model.pagedViewportSelectionIndex, savedViewportSurface.surfaceOrdinal)
            XCTAssertGreaterThan(model.pagedViewportSelectionIndex, 0)
            XCTAssertEqual(viewportSurfaces(in: model)[model.selectedSurfaceIndex].ranges.first?.segmentIndex, savedRange.segmentIndex)
        }
    }

    func testPagedDirectLaunchRestoresSemanticPosition() async throws {
        let document = ReaderPageDocument(
            threadID: "910",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 520), chapterTitle: "第一章")
            ]
        )
        let pagination = try readerModelSegmentPagination(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let targetViewportSurface = try XCTUnwrap(pagination.viewportIndex.surfaces.dropFirst().last { !$0.ranges.isEmpty })
        let targetRange = try XCTUnwrap(targetViewportSurface.ranges.first)
        let targetSemantics = try XCTUnwrap(document.semantics(forSegmentIndex: targetRange.segmentIndex))
        let resumePoint = ReaderResumePoint(
            view: document.view,
            chapterIdentity: targetSemantics.chapterIdentity,
            textSegmentIdentity: try XCTUnwrap(targetSemantics.textSegmentIdentity),
            displayedTextOffset: targetRange.startOffset,
            chapterOrdinal: targetViewportSurface.chapterOrdinal ?? 0,
            chapterTitle: targetViewportSurface.chapterTitle,
            segmentProgress: 0,
            readingModeHint: .paged
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .paged),
            launchContext: ReaderLaunchContext(
                threadID: document.threadID,
                threadTitle: "测试线程",
                source: .resume,
                initialView: 1,
                initialResumePoint: resumePoint
            )
        )

        await MainActor.run {
            XCTAssertEqual(model.selectedSurfaceIndex, targetViewportSurface.surfaceOrdinal)
            XCTAssertEqual(model.pagedViewportSelectionIndex, targetViewportSurface.surfaceOrdinal)
            XCTAssertGreaterThan(model.pagedViewportSelectionIndex, 0)
            XCTAssertEqual(viewportSurfaces(in: model)[model.selectedSurfaceIndex].ranges.first?.segmentIndex, targetViewportSurface.ranges.first?.segmentIndex)
        }
    }

    func testLaunchWithoutSemanticPositionStartsAtFirstSurface() async throws {
        let document = ReaderPageDocument(
            threadID: "905",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 320), chapterTitle: "第一章")
            ]
        )
        let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
        let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let forumCacheStore = ForumCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await seedReaderSourceCaches(
            documents: [document],
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )

        let appContext = YamiboAppContext(
            sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
            settingsStore: settingsStore,
            readerCacheStore: cacheStore,
            forumCacheStore: forumCacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadID: document.threadID,
                    threadTitle: "测试线程",
                    source: .forum,
                    initialView: 1
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.selectedSurfaceIndex, 0)
        }
    }

    func testChangingReadingModeKeepsSemanticAnchorOnSameSegment() async throws {
        let document = ReaderPageDocument(
            threadID: "903",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 260), chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .paged),
            pagination: readerModelMergedTextPagination
        )

        let originalOffset = await MainActor.run { () -> Int in
            let targetIndex = min(1, max(model.surfaceCount - 1, 0))
            model.updateVerticalViewportPosition(surfaceIndex: targetIndex, intraSurfaceProgress: 0.5)
            let page = viewportSurfaces(in: model)[targetIndex]
            return page.ranges.first.map(midpoint(in:)) ?? 0
        }

        await model.commitNovelTextAppearance(ReaderAppearanceSettings(readingMode: .vertical))

        await MainActor.run {
            let page = viewportSurfaces(in: model)[model.selectedSurfaceIndex]
            let viewportSurface = try? viewportSurface(in: model, surfaceIndex: model.selectedSurfaceIndex)
            XCTAssertEqual(page.chapterTitle, "第一章")
            XCTAssertEqual(viewportSurface?.ranges.first?.segmentIndex, 0)
            XCTAssertTrue(viewportSurface.map { viewportSurfaceContainsOffset($0, offset: originalOffset) } ?? false)
        }

        await model.commitNovelTextAppearance(ReaderAppearanceSettings(readingMode: .paged))

        await MainActor.run {
            let page = viewportSurfaces(in: model)[model.selectedSurfaceIndex]
            let viewportSurface = try? viewportSurface(in: model, surfaceIndex: model.selectedSurfaceIndex)
            XCTAssertEqual(page.chapterTitle, "第一章")
            XCTAssertEqual(viewportSurface?.ranges.first?.segmentIndex, 0)
            XCTAssertTrue(viewportSurface.map { viewportSurfaceContainsOffset($0, offset: originalOffset) } ?? false)
        }
    }

    func testChangingReadingModeFromMergedPagedTextTargetsActualSegment() async throws {
        let document = ReaderPageDocument(
            threadID: "906",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text("第一段。", chapterTitle: "第一章"),
                .text("第二段目标位置。", chapterTitle: "第一章"),
                .text("第三段。", chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .paged),
            pagination: readerModelMergedTextPagination
        )

        let target = try await MainActor.run {
            let mergedPage = try XCTUnwrap(viewportSurfaces(in: model).first { $0.ranges.count >= 2 })
            let ranges = mergedPage.ranges
            let targetRange = try XCTUnwrap(ranges.first { $0.segmentIndex == 1 })
            let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
            let precedingLength = ranges
                .prefix { $0.segmentIndex != targetRange.segmentIndex }
                .reduce(0) { $0 + max($1.length, 1) }
            let targetOffset = targetRange.startOffset + max(1, targetRange.length / 2)
            let progress = Double(precedingLength + max(1, targetRange.length / 2)) / Double(max(totalLength, 1))
            model.updateVerticalViewportPosition(surfaceIndex: mergedPage.surfaceOrdinal, intraSurfaceProgress: progress)
            return (segmentIndex: targetRange.segmentIndex, offset: targetOffset)
        }

        await model.commitNovelTextAppearance(ReaderAppearanceSettings(readingMode: .vertical))

        await MainActor.run {
            let page = viewportSurfaces(in: model)[model.selectedSurfaceIndex]
            let viewportSurface = try? viewportSurface(in: model, surfaceIndex: page.surfaceOrdinal)
            XCTAssertTrue(viewportSurface.map { viewportSurfaceContainsSegmentOffset($0, segmentIndex: target.segmentIndex, offset: target.offset) } ?? false)
        }
    }

    func testModeSwitchAnchorSurvivesFollowUpLayoutRepagination() async throws {
        let document = ReaderPageDocument(
            threadID: "907",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 420), chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let originalOffset = try await MainActor.run {
            let page = try XCTUnwrap(viewportSurfaces(in: model).dropFirst().first { !$0.ranges.isEmpty })
            let offset = try midpoint(in: XCTUnwrap(page.ranges.first))
            model.updateVerticalViewportPosition(surfaceIndex: page.surfaceOrdinal, intraSurfaceProgress: 0.5)
            return offset
        }

        await model.commitNovelTextAppearance(ReaderAppearanceSettings(readingMode: .vertical))
        await model.commitNovelTextLayout(
            ReaderContainerLayout(
                containerSize: CGSize(width: 390, height: 844),
                safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
                contentInsets: ReaderLayoutInsets(top: 16, leading: 16, bottom: 24, trailing: 16),
                chromeInsets: ReaderLayoutInsets(top: 72, bottom: 96),
                readingMode: .vertical
            )
        )

        await MainActor.run {
            let page = viewportSurfaces(in: model)[model.selectedSurfaceIndex]
            let viewportSurface = try? viewportSurface(in: model, surfaceIndex: page.surfaceOrdinal)
            XCTAssertTrue(viewportSurface.map { viewportSurfaceContainsSegmentOffset($0, segmentIndex: 0, offset: originalOffset) } ?? false)
        }
    }

    func testVerticalToPagedModeSwitchDoesNotTemporarilyShowFirstPageBeforeLayoutSync() async throws {
        let document = ReaderPageDocument(
            threadID: "908",
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 520), chapterTitle: "第一章")
            ]
        )
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(readingMode: .vertical)
        )

        let originalOffset = try await MainActor.run {
            let page = try XCTUnwrap(viewportSurfaces(in: model).dropFirst().last { !$0.ranges.isEmpty })
            let offset = try midpoint(in: XCTUnwrap(page.ranges.first))
            model.updateVerticalViewportPosition(surfaceIndex: page.surfaceOrdinal, intraSurfaceProgress: 0.5)
            return offset
        }

        await MainActor.run {
            XCTAssertGreaterThan(model.selectedSurfaceIndex, 0)
        }
        await model.commitNovelTextAppearance(ReaderAppearanceSettings(readingMode: .paged))

        await MainActor.run {
            XCTAssertGreaterThan(model.selectedSurfaceIndex, 0)
            let page = viewportSurfaces(in: model)[model.selectedSurfaceIndex]
            let viewportSurface = try? viewportSurface(in: model, surfaceIndex: page.surfaceOrdinal)
            XCTAssertTrue(viewportSurface.map { viewportSurfaceContainsSegmentOffset($0, segmentIndex: 0, offset: originalOffset) } ?? false)
        }
    }

    func testCachedViewsTrackCurrentVariant() async throws {
        let threadID = "556677"
        let unfilteredDocument = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            chapterTitles: ["全部回复"],
            contentSource: .fallbackUnfilteredPage
        )
        let authorFilteredDocument = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            chapterTitles: ["只看楼主"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )

        let unfilteredOfflineStore = try makeReaderModelOfflineCacheStore()
        try await seedNovelOfflineCache(unfilteredOfflineStore, document: unfilteredDocument)
        let unfilteredModel = try await makeModel(
            documents: [unfilteredDocument],
            offlineCacheStore: unfilteredOfflineStore
        )
        await MainActor.run {
            XCTAssertEqual(unfilteredModel.cachedViews, [1])
        }

        let filteredOfflineStore = try makeReaderModelOfflineCacheStore()
        try await seedNovelOfflineCache(filteredOfflineStore, document: authorFilteredDocument)
        let filteredModel = try await makeModel(
            documents: [authorFilteredDocument],
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            ),
            offlineCacheStore: filteredOfflineStore
        )
        await MainActor.run {
            XCTAssertEqual(filteredModel.cachedViews, [1])
        }
    }

    func testOfflineFallbackShowsStaleNoticeAndRetryKeepsOnlinePathAvailable() async throws {
        defer { ReaderTestURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        ReaderTestURLProtocol.handler = { request in
            (
                Data("temporarily unavailable".utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let threadID = "559900"
        let document = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            chapterTitles: ["离线章节"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        let offlineStore = try makeReaderModelOfflineCacheStore()
        try await seedNovelOfflineCache(
            offlineStore,
            document: document,
            updatedAt: Date(timeIntervalSince1970: 55_990)
        )

        let model = try await makeModel(
            documents: [document],
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            ),
            session: session,
            offlineCacheStore: offlineStore,
            seedSourceCaches: false
        )

        await MainActor.run {
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.readerSurfaces.isEmpty)
            XCTAssertNotNil(model.sourceStatusText)
        }

        await model.loadCurrent(forceRefresh: true)

        await MainActor.run {
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.readerSurfaces.isEmpty)
            XCTAssertNotNil(model.sourceStatusText)
        }
    }

    func testRefreshingCurrentVariantDoesNotDeleteSiblingVariantCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadID = "556677"
        let unfilteredDocument = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            chapterTitles: ["全部回复旧缓存"],
            contentSource: .fallbackUnfilteredPage
        )
        let authorFilteredDocument = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 1,
            chapterTitles: ["只看楼主旧缓存"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheStore = ReaderCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("reader", isDirectory: true))
        let forumCacheStore = ForumCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("forum", isDirectory: true))
        let offlineStore = try makeReaderModelOfflineCacheStore(
            rootDirectory: cacheDirectory.appendingPathComponent("offline-root", isDirectory: true)
        )
        try await seedNovelOfflineCache(offlineStore, document: authorFilteredDocument)
        try await cacheStore.save(unfilteredDocument)

        let model = try await makeModel(
            documents: [authorFilteredDocument],
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            ),
            session: session,
            cacheStore: cacheStore,
            forumCacheStore: forumCacheStore,
            offlineCacheStore: offlineStore
        )
        await model.refreshCurrentCache()
        try await waitFor {
            await MainActor.run { model.cachingViews == [1] }
        }

        let preservedAuthorFiltered = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadID: threadID, view: 1, authorID: "42"),
            contentSource: .authorFilteredPage
        )
        let preservedUnfiltered = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadID: threadID, view: 1),
            contentSource: .fallbackUnfilteredPage
        )

        XCTAssertTrue(
            preservedAuthorFiltered?.segments.contains(.text(String(repeating: "只看楼主旧缓存 内容。", count: 80), chapterTitle: "只看楼主旧缓存")) == true
        )
        XCTAssertTrue(
            preservedUnfiltered?.segments.contains(.text(String(repeating: "全部回复旧缓存 内容。", count: 80), chapterTitle: "全部回复旧缓存")) == true
        )
        await MainActor.run {
            XCTAssertEqual(model.cachedViews, [1])
            XCTAssertEqual(model.offlineCacheQueueEntryCount, 1)
        }
    }

    func testChapterCommentsReuseSessionCacheUntilExplicitRefresh() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadID = "9001"
        nonisolated(unsafe) var requestCount = 0
        ReaderTestURLProtocol.handler = { request in
            requestCount += 1
            let body = makeChapterCommentsHTML(ownerPostID: "100", commentBody: "评论\(requestCount)")
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadID: threadID, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadID: threadID, view: 1, maxView: 1, chapterTitles: ["第一章"])],
            session: session
        )

        await model.loadChapterComments(for: target)
        await model.loadChapterComments(for: target)

        await MainActor.run {
            guard case let .loaded(_, page) = model.chapterCommentsState else {
                XCTFail("Expected loaded chapter comments")
                return
            }
            XCTAssertEqual(page.comments.map(\.body), ["评论1"])
            XCTAssertEqual(requestCount, 1)
        }

        await model.refreshChapterComments(for: target)

        await MainActor.run {
            guard case let .loaded(_, page) = model.chapterCommentsState else {
                XCTFail("Expected refreshed chapter comments")
                return
            }
            XCTAssertEqual(page.comments.map(\.body), ["评论2"])
            XCTAssertEqual(requestCount, 2)
        }
    }

    func testChapterCommentsRefreshFailurePreservesCachedRows() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadID = "9002"
        ReaderTestURLProtocol.handler = { request in
            let body = makeChapterCommentsHTML(ownerPostID: "100", commentBody: "旧评论")
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadID: threadID, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadID: threadID, view: 1, maxView: 1, chapterTitles: ["第一章"])],
            session: session
        )
        await model.loadChapterComments(for: target)

        ReaderTestURLProtocol.handler = { request in
            (
                Data("server error".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }

        await model.refreshChapterComments(for: target)

        await MainActor.run {
            guard case let .loaded(_, page) = model.chapterCommentsState else {
                XCTFail("Expected cached comments to remain visible")
                return
            }
            XCTAssertEqual(page.comments.map(\.body), ["旧评论"])
            XCTAssertNotNil(model.chapterCommentsRefreshError)
        }
    }

    func testChapterCommentsInitialFailureShowsRetryableErrorState() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadID = "9003"
        ReaderTestURLProtocol.handler = { request in
            (
                Data("server error".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadID: threadID, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadID: threadID, view: 1, maxView: 1, chapterTitles: ["第一章"])],
            session: session
        )

        await model.loadChapterComments(for: target)

        await MainActor.run {
            guard case let .failed(failedTarget, message) = model.chapterCommentsState else {
                XCTFail("Expected failed chapter comments state")
                return
            }
            XCTAssertEqual(failedTarget, target)
            XCTAssertFalse(message.isEmpty)
            XCTAssertNil(model.chapterCommentsRefreshError)
        }
    }

    func testReaderBodyRefreshDoesNotClearChapterCommentsSessionCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadID = "9004"
        nonisolated(unsafe) var requestCount = 0
        nonisolated(unsafe) var servesComments = true
        ReaderTestURLProtocol.handler = { request in
            requestCount += 1
            let body = servesComments
                ? makeChapterCommentsHTML(ownerPostID: "100", commentBody: "缓存评论")
                : "<html><body><div class=\"message\">正文刷新结果</div></body></html>"
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadID: threadID, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadID: threadID, view: 1, maxView: 1, chapterTitles: ["第一章"])],
            session: session
        )

        await model.loadChapterComments(for: target)
        servesComments = false
        await model.loadCurrent(forceRefresh: true)
        await model.loadChapterComments(for: target)

        await MainActor.run {
            guard case let .loaded(_, page) = model.chapterCommentsState else {
                XCTFail("Expected cached chapter comments")
                return
            }
            XCTAssertEqual(page.comments.map(\.body), ["缓存评论"])
            XCTAssertEqual(requestCount, 2)
        }
    }

    func testCurrentForumTargetURLUsesCurrentChapterPostIdentity() async throws {
        let threadID = "7001"
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadID: threadID,
                    view: 1,
                    maxView: 1,
                    chapterTitles: ["第一章"],
                    ownerPostIDs: ["100"]
                )
            ]
        )

        await MainActor.run {
            XCTAssertEqual(
                model.currentForumTargetURL.absoluteString,
                "https://bbs.yamibo.com/forum.php?goto=findpost&mobile=2&mod=redirect&pid=100&ptid=7001"
            )
        }
    }

    func testCurrentForumTargetURLFallsBackToCurrentWebPageWithoutPostIdentity() async throws {
        let threadID = "7002"
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadID: threadID,
                    view: 1,
                    maxView: 1,
                    chapterTitles: ["第一章"]
                )
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.currentForumTargetURL, model.forumURL)
        }
    }

    func testCurrentForumTargetURLIgnoresAuthorFilterWhenOpeningChapterPost() async throws {
        let threadID = "7003"
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadID: threadID,
                    view: 1,
                    maxView: 1,
                    chapterTitles: ["第一章"],
                    authorID: "42",
                    contentSource: .authorFilteredPage,
                    ownerPostIDs: ["101"]
                )
            ],
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            )
        )

        await MainActor.run {
            XCTAssertEqual(
                model.currentForumTargetURL.absoluteString,
                "https://bbs.yamibo.com/forum.php?goto=findpost&mobile=2&mod=redirect&pid=101&ptid=7003"
            )
        }
    }

    func testCacheSelectionStateSeparatesCachedAndUncachedViews() async throws {
        let offlineStore = try makeReaderModelOfflineCacheStore()
        let document = makeDocument(view: 1, maxView: 3, chapterTitles: ["第一章"])
        try await seedNovelOfflineCache(offlineStore, document: document)
        let seededSnapshot = await offlineStore.novelOfflineCacheViewsSnapshot(
            ownerTitle: "测试线程",
            threadID: document.threadID,
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        XCTAssertEqual(seededSnapshot.cachedViews, [1])
        let model = try await makeModel(
            documents: [
                document,
            ],
            offlineCacheStore: offlineStore
        )

        await MainActor.run {
            let selection = model.cacheSelectionState(for: [1, 2])
            XCTAssertEqual(selection.cachedSelectedViews, [1])
            XCTAssertEqual(selection.uncachedSelectedViews, [2])
            XCTAssertTrue(selection.canCache)
            XCTAssertTrue(selection.canUpdate)
            XCTAssertTrue(selection.canDelete)
            XCTAssertFalse(selection.isAllSelected)
        }
    }

    func testStartCachingEnqueuesSelectedViewsInSharedDownloadQueue() async throws {
        let threadID = "7001"

        let model = try await makeModel(
            documents: [
                makeDocument(threadID: threadID, view: 1, maxView: 3, chapterTitles: ["当前页"]),
            ]
        )

        await MainActor.run {
            model.startCaching(views: [2, 3])
        }

        try await waitFor {
            await MainActor.run { model.cachingViews == [2, 3] }
        }

        await MainActor.run {
            XCTAssertEqual(model.cachedViews, [])
            XCTAssertEqual(model.offlineCacheQueueEntryCount, 2)
            XCTAssertEqual(model.cacheOperationState.status, .completed)
            XCTAssertEqual(model.cacheOperationState.completedViews, [2, 3])
        }
    }

    func testStartCachingContinuesSharedDownloadQueue() async throws {
        let threadID = "7101"
        let offlineStore = try makeReaderModelOfflineCacheStore()

        let model = try await makeModel(
            documents: [
                makeDocument(threadID: threadID, view: 1, maxView: 2, chapterTitles: ["当前页"]),
            ],
            offlineCacheStore: offlineStore
        )

        await MainActor.run {
            model.startCaching(views: [2])
        }

        try await waitFor {
            await offlineStore.offlineCacheQueueRunState() == .running
        }
    }

    func testOfflineCacheQueueUpdatesRefreshNovelCacheStateAndEntryCount() async throws {
        let threadID = "7102"
        let offlineStore = try makeReaderModelOfflineCacheStore()
        let document = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 2,
            chapterTitles: ["当前页"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        let model = try await makeModel(
            documents: [document],
            launchContext: ReaderLaunchContext(
                threadID: threadID,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            ),
            offlineCacheStore: offlineStore
        )

        await MainActor.run {
            XCTAssertEqual(model.cacheStatus(for: 2), .uncached)
            XCTAssertEqual(model.offlineCacheQueueEntryCount, 0)
        }

        let request = NovelOfflineCacheWorkRequest(
            ownerTitle: "测试线程",
            title: L10n.string("reader.page_number_spaced", 2),
            threadID: threadID,
            view: 2,
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        _ = try await offlineStore.enqueueNovelOfflineCacheWork(request)

        try await waitFor {
            await MainActor.run {
                model.cacheStatus(for: 2) == .caching
                    && model.offlineCacheQueueEntryCount == 1
            }
        }

        let completedAt = Date(timeIntervalSince1970: 71_020)
        let completionDocument = makeDocument(
            threadID: threadID,
            view: 2,
            maxView: 2,
            chapterTitles: ["离线完成"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        let thread = makeThreadIdentity(from: threadID)
        let sourcePage = makeThreadPageSource(from: completionDocument, thread: thread, authorID: "42")
        var projection = completionDocument
        projection.threadID = thread.tid
        projection.resolvedAuthorID = "42"
        projection.contentSource = .authorFilteredPage
        try await offlineStore.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            updatedAt: completedAt,
            completesMatchingWork: true,
            preservesExistingImageReferencesWhenEmpty: false
        )

        try await waitFor {
            await MainActor.run {
                model.cacheStatus(for: 2) == .cached
                    && model.offlineCacheQueueEntryCount == 0
                    && model.cacheUpdateTime(for: 2) == completedAt
            }
        }
    }

    func testUpdatingCachedViewShowsCachingWhileRetainingLastUpdateTime() async throws {
        let threadID = "7002"
        let offlineStore = try makeReaderModelOfflineCacheStore()
        let updatedAt = Date(timeIntervalSince1970: 44_000)
        let document = makeDocument(threadID: threadID, view: 1, maxView: 4, chapterTitles: ["当前页"])
        try await seedNovelOfflineCache(offlineStore, document: document, updatedAt: updatedAt)
        let model = try await makeModel(
            documents: [
                document,
            ],
            offlineCacheStore: offlineStore
        )

        await MainActor.run {
            model.updateCachedViews([1])
        }

        try await waitFor {
            await MainActor.run { model.cacheStatus(for: 1) == .caching }
        }

        await MainActor.run {
            XCTAssertEqual(model.cachedViews, [1])
            XCTAssertEqual(model.cachingViews, [1])
            XCTAssertEqual(model.cacheUpdateTime(for: 1), updatedAt)
            XCTAssertEqual(model.offlineCacheQueueEntryCount, 1)
        }
    }

    func testDeletingNovelOfflineCachePreservesTransparentCaches() async throws {
        let threadID = "7003"
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheStore = ReaderCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("reader", isDirectory: true))
        let forumCacheStore = ForumCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("forum", isDirectory: true))
        let offlineStore = try makeReaderModelOfflineCacheStore(rootDirectory: cacheDirectory.appendingPathComponent("offline-root", isDirectory: true))
        let document = makeDocument(
            threadID: threadID,
            view: 1,
            maxView: 2,
            chapterTitles: ["离线缓存"]
        )
        try await seedNovelOfflineCache(offlineStore, document: document)

        let model = try await makeModel(
            documents: [document],
            cacheStore: cacheStore,
            forumCacheStore: forumCacheStore,
            offlineCacheStore: offlineStore
        )

        await MainActor.run {
            XCTAssertEqual(model.cachedViews, [1])
        }
        await model.deleteCachedViews([1])
        try await waitFor {
            await MainActor.run { model.cachedViews.isEmpty }
        }

        let thread = makeThreadIdentity(from: threadID)
        let retainedThreadPage = await forumCacheStore.loadThreadPage(thread: thread, page: 1, authorID: "42")
        XCTAssertNotNil(retainedThreadPage)
        let retainedProjection = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadID: threadID, view: 1, authorID: "42"),
            contentSource: .authorFilteredPage
        )
        XCTAssertNotNil(retainedProjection)
    }
}

private func makeModel(
    documents: [ReaderPageDocument],
    settings: ReaderAppearanceSettings = ReaderAppearanceSettings(readingMode: .paged),
    launchContext: ReaderLaunchContext? = nil,
    session: URLSession = .shared,
    cacheStore: ReaderCacheStore? = nil,
    forumCacheStore: ForumCacheStore? = nil,
    offlineCacheStore: (any OfflineCacheStoring)? = nil,
    seedSourceCaches: Bool = true,
    pagination: @escaping NovelTextLayoutFixture = readerModelSegmentPagination
) async throws -> ReaderContainerModel {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-container-model")
    let sessionStore = try SessionStore(testSuiteName: defaultsSuiteName, key: "session")
    let settingsStore = try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings")
    let readingProgressStore = try ReadingProgressStore(
        testSuiteName: defaultsSuiteName,
        key: "reading-progress"
    )
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let resolvedCacheStore = cacheStore
        ?? ReaderCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("reader", isDirectory: true))
    let resolvedForumCacheStore = forumCacheStore
        ?? ForumCacheStore(baseDirectory: cacheDirectory.appendingPathComponent("forum", isDirectory: true))
    let grdbRootDirectory = cacheDirectory.appendingPathComponent("grdb", isDirectory: true)
    let resolvedOfflineCacheStore: any OfflineCacheStoring
    if let offlineCacheStore {
        resolvedOfflineCacheStore = offlineCacheStore
    } else {
        resolvedOfflineCacheStore = try OfflineCacheStore(
            databasePool: try YamiboDatabase.openSharedPool(rootDirectory: grdbRootDirectory),
            baseDirectory: cacheDirectory.appendingPathComponent("offline", isDirectory: true)
        )
    }

    try await settingsStore.save(AppSettings(reader: settings))
    if seedSourceCaches {
        try await seedReaderSourceCaches(
            documents: documents,
            readerCacheStore: resolvedCacheStore,
            forumCacheStore: resolvedForumCacheStore
        )
    }

    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        readingProgressStore: readingProgressStore,
        readerCacheStore: resolvedCacheStore,
        offlineCacheStore: resolvedOfflineCacheStore,
        forumCacheStore: resolvedForumCacheStore,
        grdbRootDirectory: grdbRootDirectory,
        session: session
    )
    let model = await MainActor.run {
        ReaderContainerModel(
            context: launchContext ?? ReaderLaunchContext(
                threadID: documents[0].threadID,
                threadTitle: "测试线程",
                source: .forum
            ),
            appContext: appContext,
            pagination: pagination
        )
    }

    await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
    await model.refreshCachedState()
    return model
}

private func seedReaderSourceCaches(
    documents: [ReaderPageDocument],
    readerCacheStore: ReaderCacheStore,
    forumCacheStore: ForumCacheStore
) async throws {
    var didSaveDiscoveryPage: Set<String> = []
    for document in documents {
        let thread = makeThreadIdentity(from: document.threadID)
        let trimmedAuthorID = document.resolvedAuthorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authorID = trimmedAuthorID.isEmpty ? "42" : trimmedAuthorID
        let sourcePage = makeThreadPageSource(from: document, thread: thread, authorID: authorID)
        try await forumCacheStore.saveThreadPage(
            sourcePage,
            thread: thread,
            pageNumber: document.view,
            authorID: authorID
        )
        if didSaveDiscoveryPage.insert(thread.tid).inserted {
            try await forumCacheStore.saveThreadPage(
                sourcePage,
                thread: thread,
                pageNumber: 1,
                authorID: nil
            )
        }

        var projection = document
        projection.threadID = thread.tid
        projection.resolvedAuthorID = authorID
        projection.contentSource = .authorFilteredPage
        projection.projectionSourceFingerprint = projectionFingerprint(
            page: sourcePage,
            threadID: thread.tid,
            view: document.view,
            authorID: authorID
        )
        projection.projectionSchemaVersion = 1
        try await readerCacheStore.save(projection)
    }
}

private func seedNovelOfflineCache(
    _ store: any OfflineCacheStoring,
    document: ReaderPageDocument,
    ownerTitle: String = "测试线程",
    updatedAt: Date = Date(timeIntervalSince1970: 40_000)
) async throws {
    let thread = makeThreadIdentity(from: document.threadID)
    let trimmedAuthorID = document.resolvedAuthorID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let authorID = trimmedAuthorID?.isEmpty == false ? trimmedAuthorID! : "42"
    let sourcePage = makeThreadPageSource(from: document, thread: thread, authorID: authorID)
    let request = NovelOfflineCacheWorkRequest(
        ownerTitle: ownerTitle,
        title: L10n.string("reader.page_number_spaced", document.view),
        threadID: document.threadID,
        view: document.view,
        authorID: authorID,
        contentSource: .authorFilteredPage
    )
    var projection = document
    projection.threadID = thread.tid
    projection.resolvedAuthorID = authorID
    projection.contentSource = .authorFilteredPage
    try await store.saveNovelOfflineSourcePage(
        sourcePage,
        request: request,
        updatedAt: updatedAt,
        completesMatchingWork: true,
        preservesExistingImageReferencesWhenEmpty: false
    )
}

private func makeReaderModelOfflineCacheStore(
    rootDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
) throws -> OfflineCacheStore {
    OfflineCacheStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        baseDirectory: rootDirectory.appendingPathComponent("offline", isDirectory: true)
    )
}

private func makeThreadIdentity(from threadID: String) -> ThreadIdentity {
    ThreadIdentity(tid: threadID)
}

private func makeThreadPageSource(
    from document: ReaderPageDocument,
    thread: ThreadIdentity,
    authorID: String
) -> ForumThreadPage {
    let posts = document.segments.enumerated().map { index, segment in
        ForumThreadPost(
            postID: document.segmentSources.indices.contains(index)
                ? document.segmentSources[index]?.ownerPostID ?? "\(document.view)\(index)"
                : "\(document.view)\(index)",
            author: BlogReaderUser(uid: authorID, name: "楼主"),
            contentHTML: projectionSourceHTML(for: segment, index: index),
            contentText: ""
        )
    }
    return ForumThreadPage(
        thread: thread,
        title: "测试线程",
        posts: posts,
        pageNavigation: ForumPageNavigation(currentPage: document.view, totalPages: document.maxView)
    )
}

private func projectionSourceHTML(for segment: ReaderSegment, index: Int) -> String {
    switch segment {
    case let .text(text, chapterTitle):
        return "<strong>\(escapeHTML(chapterTitle ?? "第\(index + 1)章"))</strong><br>\(escapeHTML(text))"
    case let .image(url, _):
        return #"<img src="\#(escapeHTML(url.absoluteString))" />"#
    }
}

private func projectionFingerprint(
    page: ForumThreadPage,
    threadID: String,
    view: Int,
    authorID: String
) -> String {
    let value = [
        threadID,
        String(max(1, view)),
        authorID,
        page.posts.map { post in
            [
                post.postID,
                post.author.uid ?? "",
                post.contentHTML,
                post.images.map(\.url).joined(separator: ",")
            ].joined(separator: "\u{1E}")
        }.joined(separator: "\u{1D}"),
        String(page.pageNavigation?.totalPages ?? 0)
    ].joined(separator: "\u{1F}")
    var hash: UInt64 = 1469598103934665603
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    return String(hash, radix: 16)
}

private func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func makeReadingProgressStore(
    defaultsSuiteName: String
) throws -> ReadingProgressStore {
    try ReadingProgressStore(
        testSuiteName: defaultsSuiteName,
        key: "reading-progress"
    )
}

private func readerModelSegmentPagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) throws -> NovelTextLayoutResult {
    let targetCharactersPerSurface = 120
    return try NovelTextLayout.layout(
        document: document,
        settings: settings,
        layout: layout,
        viewportSurfaceLayout: { context, _, _ in
            document.segments.indices.flatMap { segmentIndex -> [NovelTextViewportDocumentSurfaceRange] in
                guard case .text = document.segments[segmentIndex],
                      let range = context.document.textRangesBySegment[segmentIndex],
                      range.endOffset > range.startOffset else {
                    return []
                }
                var surfaceRanges: [NovelTextViewportDocumentSurfaceRange] = []
                var startOffset = range.startOffset
                while startOffset < range.endOffset {
                    let endOffset = min(startOffset + targetCharactersPerSurface, range.endOffset)
                    surfaceRanges.append(
                        NovelTextViewportDocumentSurfaceRange(
                            startOffset: startOffset,
                            endOffset: endOffset
                        )
                    )
                    startOffset = endOffset
                }
                return surfaceRanges
            }
        }
    )
}

private func waitFor(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    predicate: @escaping () async -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    XCTFail("Timed out waiting for condition")
}

@MainActor
private final class ReaderNavigationStateRecorder {
    private(set) var states: [Bool] = []

    func record(_ state: Bool) {
        states.append(state)
    }

    func removeAll() {
        states.removeAll()
    }
}

@MainActor
private final class ReaderNavigationOverlayGate {
    private(set) var didEnterPreparation = false
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare() async {
        didEnterPreparation = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ReaderLayoutUpdatePreparationGate {
    private let blockedLayout: ReaderContainerLayout
    private var continuation: CheckedContinuation<Void, Never>?

    init(blockedLayout: ReaderContainerLayout) {
        self.blockedLayout = blockedLayout
    }

    func prepare(
        _ update: NovelReadingWorkflowRuntimeUpdate
    ) async -> NovelReadingWorkflowRuntimeUpdate {
        guard update.layout == blockedLayout else { return update }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return update
    }

    func waitUntilBlocked() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ReaderLayoutUpdateFailureInjector {
    private let failingLayout: ReaderContainerLayout
    private var hasFailed = false
    private(set) var attemptCount = 0

    init(failingLayout: ReaderContainerLayout) {
        self.failingLayout = failingLayout
    }

    func prepare(
        _ update: NovelReadingWorkflowRuntimeUpdate
    ) async throws -> NovelReadingWorkflowRuntimeUpdate {
        guard update.layout == failingLayout else { return update }
        attemptCount += 1
        if !hasFailed {
            hasFailed = true
            throw NovelTextLayoutFailure.textKitIndexing
        }
        return update
    }
}

@MainActor
private func viewportSurfaces(in model: ReaderContainerModel) -> [NovelTextViewportIndexSurface] {
    model.novelReaderDebugState?.viewportSurfaces ?? []
}

@MainActor
private func viewportSurface(
    in model: ReaderContainerModel,
    surfaceIndex: Int
) throws -> NovelTextViewportIndexSurface {
    try XCTUnwrap(viewportSurfaces(in: model).first { $0.surfaceOrdinal == surfaceIndex })
}

private func midpoint(in range: ReaderRenderedTextRange) -> Int {
    range.startOffset + max(1, range.length / 2)
}

private func viewportSurfaceContainsOffset(_ page: NovelTextViewportIndexSurface, offset: Int) -> Bool {
    page.ranges.contains { rangeContainsOffset($0, offset: offset) }
}

private func pageProgress(
    in page: NovelTextViewportIndexSurface,
    segmentIndex: Int,
    segmentOffset: Int
) throws -> Double {
    let ranges = page.ranges
    let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
    var runningLength = 0
    for range in ranges {
        let length = max(range.length, 1)
        defer { runningLength += length }
        guard range.segmentIndex == segmentIndex else { continue }
        let localOffset = min(max(segmentOffset - range.startOffset, 0), length)
        return Double(runningLength + localOffset) / Double(max(totalLength, 1))
    }
    throw XCTSkip("Surface does not contain requested segment.")
}

private func viewportSurfaceContainsSegmentOffset(
    _ page: NovelTextViewportIndexSurface,
    segmentIndex: Int,
    offset: Int
) -> Bool {
    page.ranges.filter { $0.segmentIndex == segmentIndex }.contains {
        rangeContainsOffset($0, offset: offset)
    }
}

private func rangeContainsOffset(_ range: ReaderRenderedTextRange, offset: Int) -> Bool {
    if range.startOffset == range.endOffset {
        return offset <= range.startOffset
    }
    return offset >= range.startOffset && offset < range.endOffset
}

private func makeDocument(
    threadID: String = "556677",
    view: Int,
    maxView: Int,
    chapterTitles: [String],
    authorID: String? = nil,
    contentSource: ReaderContentSource = .fallbackUnfilteredPage,
    ownerPostIDs: [String?]? = nil
) -> ReaderPageDocument {
    let segments = chapterTitles.map { title in
        ReaderSegment.text(String(repeating: "\(title) 内容。", count: 80), chapterTitle: title)
    }
    let segmentSources = ownerPostIDs.map { postIDs in
        segments.indices.map { index in
            postIDs.indices.contains(index) ? ReaderSegmentSource(ownerPostID: postIDs[index]) : nil
        }
    }
    return ReaderPageDocument(
        threadID: threadID,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: contentSource,
        segments: segments,
        segmentSources: segmentSources
    )
}

private func makeImageDocument(
    threadID: String = "998877",
    view: Int,
    maxView: Int,
    surfaceCount: Int
) -> ReaderPageDocument {
    let segments = (0..<surfaceCount).map { index in
        ReaderSegment.image(
            URL(string: "https://example.com/\(view)-\(index).jpg")!,
            chapterTitle: "第\(index + 1)章"
        )
    }
    return ReaderPageDocument(
        threadID: threadID,
        view: view,
        maxView: maxView,
        contentSource: .fallbackUnfilteredPage,
        segments: segments
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
            threadID: "test-thread",
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

private func readerModelPreviewSourcePagination(
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
                chapterOrdinal: 0,
                chapterTitle: segment.chapterTitle
            )
        },
        chapters: [
            ReaderChapter(
                ordinal: 0,
                title: document.segments.first?.chapterTitle ?? "Chapter",
                startIndex: 0
            )
        ],
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
                    chapterOrdinal: 0,
                    chapterTitle: segment.chapterTitle,
                    ranges: text.isEmpty
                        ? []
                        : [ReaderRenderedTextRange(segmentIndex: index, startOffset: 0, endOffset: text.count)]
                )
            },
            chapters: [
                NovelTextViewportIndexChapter(
                    ordinal: 0,
                    title: document.segments.first?.chapterTitle ?? "Chapter",
                    startSurfaceOrdinal: 0
                )
            ]
        )
    )
}

private func readerModelMergedTextPagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) -> NovelTextLayoutResult {
    let ranges = document.segments.enumerated().compactMap { index, segment -> ReaderRenderedTextRange? in
        guard case let .text(text, _) = segment else { return nil }
        return ReaderRenderedTextRange(segmentIndex: index, startOffset: 0, endOffset: text.count)
    }
    return layoutResult(
        pages: [
            viewportTestPage(
                index: 0,
                blocks: [
                    .text(
                        document.segments.compactMap { segment in
                            if case let .text(text, _) = segment { return text }
                            return nil
                        }.joined(separator: "\n\n"),
                        chapterTitle: document.segments.first?.chapterTitle,
                        ranges: ranges
                    )
                ],
                documentView: document.view,
                chapterOrdinal: 0,
                chapterTitle: document.segments.first?.chapterTitle
            )
        ],
        chapters: [
            ReaderChapter(
                ordinal: 0,
                title: document.segments.first?.chapterTitle ?? "Chapter",
                startIndex: 0
            )
        ],
        viewportIndex: NovelTextViewportIndex(
            documentView: document.view,
            readingMode: settings.readingMode,
            surfaces: [
                NovelTextViewportIndexSurface(
                    surfaceOrdinal: 0,
                    documentView: document.view,
                    chapterOrdinal: 0,
                    chapterTitle: document.segments.first?.chapterTitle,
                    ranges: ranges
                )
            ],
            chapters: [
                NovelTextViewportIndexChapter(
                    ordinal: 0,
                    title: document.segments.first?.chapterTitle ?? "Chapter",
                    startSurfaceOrdinal: 0
                )
            ]
        )
    )
}

@MainActor
private final class ReaderModelFixtureRuntimeAdapter: NovelTextLayoutRuntimeAdapter {
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
        return NovelTextLayoutRuntimeCandidate(
            result: result,
            fullDocumentLayoutPassCount: 0,
            postIndexCompactionCount: 0,
            ownsAuthoritativeIndex: false
        )
    }
}

@MainActor
private extension ReaderContainerModel {
    convenience init(
        context: ReaderLaunchContext,
        appContext: YamiboAppContext,
        initialSettings: ReaderAppearanceSettings? = nil,
        pagination: @escaping NovelTextLayoutFixture = readerModelSegmentPagination,
        onReaderResumeRouteChange: @escaping ReaderResumeRouteChangeHandler = { _ in }
    ) {
        self.init(
            context: context,
            appContext: appContext,
            initialSettings: initialSettings,
            runtimeAdapter: ReaderModelFixtureRuntimeAdapter(fixture: pagination),
            onReaderResumeRouteChange: onReaderResumeRouteChange
        )
    }
}

private func makeChapterCommentsHTML(ownerPostID: String, commentBody: String) -> String {
    """
    <html><body>
      <div class="t_f" id="postmessage_\(ownerPostID)">第一章<br>正文</div>
      <div id="comment_\(ownerPostID)" class="cm">
        <div class="pstl xs1 cl">
          <div class="psta vm"><a class="xi2 xw1">读者甲</a></div>
          <div class="psti">\(commentBody) <span class="xg1">发表于 2026-5-1 12:00</span></div>
        </div>
      </div>
    </body></html>
    """
}

private final class ReaderTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
