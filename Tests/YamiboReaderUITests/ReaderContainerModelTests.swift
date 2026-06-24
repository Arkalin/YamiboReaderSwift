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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=445566&mobile=2")!,
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
            XCTAssertEqual(model.pagedViewportSelectionIndex, 0)
            XCTAssertTrue(model.progressText.contains("第 1-2 / 5 页"))

            model.jumpToSurface(4)
            XCTAssertEqual(model.selectedSurfaceIndex, 4)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 2)
            XCTAssertTrue(model.progressText.contains("第 5 / 5 页"))
        }
    }

    func testTwoPageSpreadMapsSliderAndPagingToSpreadLeftAnchor() async throws {
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
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 1), 0)
            XCTAssertEqual(model.targetSurfaceIndex(forProgressValue: 5), 4)

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
            XCTAssertEqual(model.selectedSurfaceIndex, 4)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 2)
        }

        await model.jumpRelativeSurface(1)

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.selectedSurfaceIndex, 0)
            XCTAssertEqual(model.pagedViewportSelectionIndex, 0)
        }
    }

    func testTwoPageSpreadRepaginatesTextForHalfWidthColumns() async throws {
        let document = ReaderPageDocument(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9911&mobile=2")!,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9912&mobile=2")!,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let initialSettings = ReaderAppearanceSettings(fontScale: 1.0, readingMode: .paged)
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
        try await settingsStore.save(AppSettings(reader: initialSettings))
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites"),
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let initialSettings = ReaderAppearanceSettings(backgroundStyle: .system, readingMode: .paged)
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"])
        try await settingsStore.save(AppSettings(reader: initialSettings))
        try await cacheStore.save(document)
        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites"),
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let cacheStore = ReaderCacheStore(
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
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites"),
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9012&mobile=2")!,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9013&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
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
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(title: "测试线程", url: threadURL, authorID: "author-1", type: .novel)
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: threadURL,
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

        let favorite = await favoriteStore.favorite(for: threadURL)
        XCTAssertEqual(favorite?.novelResumePoint?.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: 2)?.textSegmentIdentity))
        XCTAssertEqual(favorite?.novelResumePoint?.displayedTextOffset, targetOffset)
        XCTAssertEqual(favorite?.mangaPageIndex, 0)
        XCTAssertEqual(resumeContext.initialResumePoint, favorite?.novelResumePoint)
        XCTAssertEqual(resumeContext.initialView, favorite?.novelResumePoint?.view)
    }

    func testForumNovelProgressDoesNotCreateFavorite() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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

        let favorites = await favoriteStore.loadFavorites()
        XCTAssertTrue(favorites.isEmpty)
    }

    func testNovelProgressPersistsReaderResumeRoute() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let readerResumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).readerRoute")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            readerResumeRouteStore: readerResumeRouteStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
        let savedContext = await model.saveProgress()

        guard case let .novel(context)? = await readerResumeRouteStore.load() else {
            return XCTFail("Expected novel resume route")
        }
        XCTAssertEqual(context.threadURL, document.threadURL)
        XCTAssertEqual(context.threadTitle, "测试线程")
        XCTAssertEqual(context.source, .resume)
        XCTAssertEqual(context.initialView, 1)
        XCTAssertEqual(context.initialResumePoint?.view, 1)
        XCTAssertEqual(savedContext, context)
    }

    func testLateNovelSaveAfterDismissDoesNotRecreateReaderResumeRoute() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let readerResumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).readerRoute")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            readerResumeRouteStore: readerResumeRouteStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
                    threadTitle: "测试线程",
                    source: .forum
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
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

        readerResumeRouteStore.clearSync()
        await model.saveProgress()
        try await Task.sleep(nanoseconds: 100_000_000)

        let routeAfterLateSave = await readerResumeRouteStore.load()
        XCTAssertNil(routeAfterLateSave)
    }

    func testForumNovelProgressUpdatesExistingFavorite() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"])
        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(title: "测试线程", url: document.threadURL, type: .novel)
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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

        let favorite = await favoriteStore.favorite(for: document.threadURL)
        XCTAssertEqual(favorite?.lastView, 1)
        XCTAssertEqual(favorite?.mangaPageIndex, 0)
        XCTAssertNotNil(favorite?.novelResumePoint)
    }

    func testVerticalModePersistsSemanticResumePoint() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let document = ReaderPageDocument(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2")!,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 220), chapterTitle: "第一章")
            ]
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(title: "测试线程", url: document.threadURL, type: .novel)
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
            let favorite = await favoriteStore.favorite(for: document.threadURL)
            return favorite?.novelResumePoint != nil
        }

        let favorite = await favoriteStore.favorite(for: document.threadURL)
        XCTAssertEqual(favorite?.lastView, 1)
        XCTAssertEqual(favorite?.lastChapter, "第一章")
        XCTAssertEqual(favorite?.novelResumePoint?.view, 1)
        XCTAssertEqual(favorite?.novelResumePoint?.textSegmentIdentity, try XCTUnwrap(document.semantics(forSegmentIndex: targetRange.segmentIndex)?.textSegmentIdentity))
        XCTAssertTrue((favorite?.novelResumePoint?.displayedTextOffset ?? 0) > targetRange.startOffset)
        XCTAssertEqual(favorite?.novelResumePoint?.chapterTitle, "第一章")
    }

    func testVerticalModeRestoresStoredResumePointWithinChapter() async throws {
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
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
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(
                title: "测试线程",
                url: threadURL,
                mangaPageIndex: savedViewportSurface.surfaceOrdinal,
                lastView: 2,
                lastChapter: "第三章",
                novelResumePoint: savedResumePoint,
                type: .novel
            )
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: threadURL,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=905&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 420), chapterTitle: "第一章")
            ]
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(title: "测试线程", url: threadURL, type: .novel)
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let launchContext = ReaderLaunchContext(
            threadURL: threadURL,
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
        let savedFavorite = await favoriteStore.favorite(for: threadURL)
        let savedProgressPercent = await MainActor.run { model.currentProgressPercent }
        XCTAssertEqual(savedFavorite?.novelDocumentSurfaceProgressPercent, savedProgressPercent)

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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=904&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
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
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(
                title: "测试线程",
                url: threadURL,
                mangaPageIndex: 99,
                lastView: 2,
                lastChapter: "第二章",
                novelResumePoint: savedResumePoint,
                type: .novel
            )
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: threadURL,
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
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=909&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
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
        try await cacheStore.save(document)
        try await favoriteStore.saveFavorites([
            Favorite(
                title: "测试线程",
                url: threadURL,
                mangaPageIndex: savedViewportSurface.surfaceOrdinal,
                lastView: 1,
                lastChapter: "第一章",
                novelResumePoint: savedResumePoint,
                type: .novel
            )
        ])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: threadURL,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=910&mobile=2")!,
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
                threadURL: document.threadURL,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=905&mobile=2")!,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: [
                .text(String(repeating: "第一章 内容。", count: 320), chapterTitle: "第一章")
            ]
        )
        let keyPrefix = UUID().uuidString
        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let cacheStore = ReaderCacheStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        try await settingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .paged)))
        try await cacheStore.save(document)

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: favoriteStore,
            readerCacheStore: cacheStore
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: document.threadURL,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=903&mobile=2")!,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=906&mobile=2")!,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=907&mobile=2")!,
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
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=908&mobile=2")!,
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=556677&mobile=2")!
        let unfilteredDocument = makeDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            chapterTitles: ["全部回复"],
            contentSource: .fallbackUnfilteredPage
        )
        let authorFilteredDocument = makeDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            chapterTitles: ["只看楼主"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )

        let unfilteredModel = try await makeModel(documents: [unfilteredDocument])
        await MainActor.run {
            XCTAssertEqual(unfilteredModel.cachedViews, [1])
        }

        let filteredModel = try await makeModel(
            documents: [authorFilteredDocument],
            launchContext: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "测试线程",
                source: .forum,
                authorID: "42"
            )
        )
        await MainActor.run {
            XCTAssertEqual(filteredModel.cachedViews, [1])
        }
    }

    func testRefreshingCurrentVariantDoesNotDeleteSiblingVariantCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=556677&mobile=2")!
        let unfilteredDocument = makeDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            chapterTitles: ["全部回复旧缓存"],
            contentSource: .fallbackUnfilteredPage
        )
        let authorFilteredDocument = makeDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            chapterTitles: ["只看楼主旧缓存"],
            authorID: "42",
            contentSource: .authorFilteredPage
        )

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheStore = ReaderCacheStore(baseDirectory: cacheDirectory)
        try await cacheStore.save(unfilteredDocument)
        try await cacheStore.save(authorFilteredDocument)

        ReaderTestURLProtocol.handler = { request in
            let absolute = request.url?.absoluteString ?? ""
            let body = absolute.contains("authorid=42")
                ? "<html><body><div class=\"message\">只看楼主新缓存</div></body></html>"
                : "<html><body><div class=\"message\">全部回复新缓存</div></body></html>"
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html; charset=utf-8"]
                )!
            )
        }

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(UUID().uuidString).session"),
            settingsStore: SettingsStore(key: "\(UUID().uuidString).settings"),
            favoriteStore: FavoriteStore(key: "\(UUID().uuidString).favorites"),
            readerCacheStore: cacheStore,
            session: session
        )
        let model = await MainActor.run {
            ReaderContainerModel(
                context: ReaderLaunchContext(
                    threadURL: threadURL,
                    threadTitle: "测试线程",
                    source: .forum,
                    authorID: "42"
                ),
                appContext: appContext,
                pagination: readerModelSegmentPagination
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await model.refreshCurrentCache()

        let refreshedAuthorFiltered = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"),
            contentSource: .authorFilteredPage
        )
        let preservedUnfiltered = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: threadURL, view: 1),
            contentSource: .fallbackUnfilteredPage
        )

        XCTAssertTrue(
            refreshedAuthorFiltered?.segments.contains(.text("只看楼主新缓存", chapterTitle: "只看楼主新缓存")) == true
        )
        XCTAssertTrue(
            preservedUnfiltered?.segments.contains(.text(String(repeating: "全部回复旧缓存 内容。", count: 80), chapterTitle: "全部回复旧缓存")) == true
        )
    }

    func testChapterCommentsReuseSessionCacheUntilExplicitRefresh() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9001&mobile=2")!
        nonisolated(unsafe) var requestCount = 0
        ReaderTestURLProtocol.handler = { request in
            requestCount += 1
            let body = makeChapterCommentsHTML(ownerPostID: "100", commentBody: "评论\(requestCount)")
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadURL: threadURL, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadURL: threadURL, view: 1, maxView: 1, chapterTitles: ["第一章"])],
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9002&mobile=2")!
        ReaderTestURLProtocol.handler = { request in
            let body = makeChapterCommentsHTML(ownerPostID: "100", commentBody: "旧评论")
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadURL: threadURL, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadURL: threadURL, view: 1, maxView: 1, chapterTitles: ["第一章"])],
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9003&mobile=2")!
        ReaderTestURLProtocol.handler = { request in
            (
                Data("server error".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            )
        }
        let target = ReaderChapterCommentTarget(threadURL: threadURL, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadURL: threadURL, view: 1, maxView: 1, chapterTitles: ["第一章"])],
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9004&mobile=2")!
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
        let target = ReaderChapterCommentTarget(threadURL: threadURL, view: 1, ownerPostID: "100", title: "第一章")
        let model = try await makeModel(
            documents: [makeDocument(threadURL: threadURL, view: 1, maxView: 1, chapterTitles: ["第一章"])],
            session: session
        )

        await model.loadChapterComments(for: target)
        servesComments = false
        await model.refreshCurrentCache()
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7001&mobile=2")!
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadURL: threadURL,
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7002&mobile=2")!
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadURL: threadURL,
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
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7003&mobile=2")!
        let model = try await makeModel(
            documents: [
                makeDocument(
                    threadURL: threadURL,
                    view: 1,
                    maxView: 1,
                    chapterTitles: ["第一章"],
                    authorID: "42",
                    contentSource: .authorFilteredPage,
                    ownerPostIDs: ["101"]
                )
            ],
            launchContext: ReaderLaunchContext(
                threadURL: threadURL,
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
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 3, chapterTitles: ["第一章"]),
            ]
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

    func testStartCachingSupportsBackgroundProgressAndCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7001&mobile=2")!
        ReaderTestURLProtocol.handler = { request in
            let absolute = request.url?.absoluteString ?? ""
            let page = absolute.contains("page=3") ? "3" : "2"
            let body = "<html><body><div class=\"message\">缓存页\(page)</div></body></html>"
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html; charset=utf-8"]
                )!
            )
        }

        let model = try await makeModel(
            documents: [
                makeDocument(threadURL: threadURL, view: 1, maxView: 3, chapterTitles: ["当前页"]),
            ],
            session: session
        )

        await MainActor.run {
            model.startCaching(views: [2, 3])
            XCTAssertTrue(model.cacheOperationState.isRunning)
            model.hideCacheProgress()
            XCTAssertTrue(model.cacheOperationState.isProgressHidden)
        }

        try await waitFor {
            await MainActor.run { model.cacheOperationState.isFinished }
        }

        await MainActor.run {
            XCTAssertEqual(model.cachedViews, [1, 2, 3])
            XCTAssertEqual(model.cacheOperationState.status, .completed)
            XCTAssertEqual(model.cacheOperationState.completedViews, [2, 3])
        }
    }

    func testStopCachingCancelsRemainingQueueButKeepsCompletedPages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7002&mobile=2")!
        ReaderTestURLProtocol.handler = { request in
            Thread.sleep(forTimeInterval: 0.1)
            let absolute = request.url?.absoluteString ?? ""
            let page: String
            if absolute.contains("page=4") {
                page = "4"
            } else if absolute.contains("page=3") {
                page = "3"
            } else {
                page = "2"
            }
            let body = "<html><body><div class=\"message\">缓存页\(page)</div></body></html>"
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html; charset=utf-8"]
                )!
            )
        }

        let model = try await makeModel(
            documents: [
                makeDocument(threadURL: threadURL, view: 1, maxView: 4, chapterTitles: ["当前页"]),
            ],
            session: session
        )

        await MainActor.run {
            model.startCaching(views: [2, 3, 4])
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        await MainActor.run {
            model.stopCaching()
        }

        try await waitFor {
            await MainActor.run { model.cacheOperationState.isFinished }
        }

        await MainActor.run {
            XCTAssertEqual(model.cacheOperationState.status, .cancelled)
            XCTAssertLessThan(model.cacheOperationState.completedViews.count, 3)
            XCTAssertTrue(model.cachedViews.isSuperset(of: [1]))
        }
    }

    func testUpdateCachedViewsRewritesSelectedPages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7003&mobile=2")!
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheStore = ReaderCacheStore(baseDirectory: cacheDirectory)
        let original = makeDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 2,
            chapterTitles: ["旧缓存"]
        )
        let sibling = makeDocument(
            threadURL: threadURL,
            view: 2,
            maxView: 2,
            chapterTitles: ["保留缓存"]
        )
        try await cacheStore.save(original)
        try await cacheStore.save(sibling)

        ReaderTestURLProtocol.handler = { request in
            let body = "<html><body><div class=\"message\">新缓存</div></body></html>"
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html; charset=utf-8"]
                )!
            )
        }

        let model = try await makeModel(
            documents: [original, sibling],
            session: session,
            cacheStore: cacheStore
        )

        await MainActor.run {
            model.updateCachedViews([1])
        }

        try await waitFor {
            await MainActor.run { model.cacheOperationState.isFinished }
        }

        let updated = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: threadURL, view: 1),
            contentSource: .fallbackUnfilteredPage
        )
        let preserved = await cacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: threadURL, view: 2),
            contentSource: .fallbackUnfilteredPage
        )

        let updatedText = updated?.segments.compactMap { segment -> String? in
            if case let .text(text, _) = segment { return text }
            return nil
        }.first
        let preservedText = preserved?.segments.compactMap { segment -> String? in
            if case let .text(text, _) = segment { return text }
            return nil
        }.first

        XCTAssertEqual(updatedText, "新缓存")
        XCTAssertTrue(preservedText?.contains("保留缓存") == true)
    }
}

private func makeModel(
    documents: [ReaderPageDocument],
    settings: ReaderAppearanceSettings = ReaderAppearanceSettings(readingMode: .paged),
    launchContext: ReaderLaunchContext? = nil,
    session: URLSession = .shared,
    cacheStore: ReaderCacheStore? = nil,
    pagination: @escaping NovelTextLayoutFixture = readerModelSegmentPagination
) async throws -> ReaderContainerModel {
    let keyPrefix = UUID().uuidString
    let sessionStore = SessionStore(key: "\(keyPrefix).session")
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let resolvedCacheStore = cacheStore ?? ReaderCacheStore(baseDirectory: cacheDirectory)

    try await settingsStore.save(AppSettings(reader: settings))
    for document in documents {
        try await resolvedCacheStore.save(document)
    }

    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        readerCacheStore: resolvedCacheStore,
        session: session
    )
    let model = await MainActor.run {
        ReaderContainerModel(
            context: launchContext ?? ReaderLaunchContext(
                threadURL: documents[0].threadURL,
                threadTitle: "测试线程",
                source: .forum
            ),
            appContext: appContext,
            pagination: pagination
        )
    }

    await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
    return model
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
    threadURL: URL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=556677&mobile=2")!,
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
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: contentSource,
        segments: segments,
        segmentSources: segmentSources
    )
}

private func makeImageDocument(
    threadURL: URL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=998877&mobile=2")!,
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
        threadURL: threadURL,
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
        pagination: @escaping NovelTextLayoutFixture = readerModelSegmentPagination
    ) {
        self.init(
            context: context,
            appContext: appContext,
            initialSettings: initialSettings,
            runtimeAdapter: ReaderModelFixtureRuntimeAdapter(fixture: pagination)
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
