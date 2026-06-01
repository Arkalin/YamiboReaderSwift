import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderProgressScrubStateTests: XCTestCase {
    func testUpdatingScrubClampsValueAndBuildsPreviewWithoutCommit() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 5,
            currentProgressPercent: 20,
            targetPageIndex: { value in min(max(Int(value.rounded()), 0), 4) },
            chapterTitle: { index in index >= 2 ? "第二章" : "第一章" },
            chapterTickStartIndex: { index in index == 2 ? 2 : nil }
        )

        let update = state.update(value: 99, context: context)

        XCTAssertEqual(state.phase, .scrubbing)
        XCTAssertEqual(state.value, 4)
        XCTAssertEqual(state.targetRenderedPageIndex, 4)
        XCTAssertEqual(state.preview, ReaderProgressScrubPreview(chapterTitle: "第二章", pageNumber: 5))
        XCTAssertNil(update.committedPageIndex)
    }

    func testCommitReturnsOneTargetPageAndCommitHaptic() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 5,
            currentProgressPercent: 0,
            targetPageIndex: { value in Int(value.rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { _ in nil }
        )

        _ = state.update(value: 3, context: context)
        let commit = state.end()

        XCTAssertEqual(state.phase, .ended)
        XCTAssertEqual(commit.committedPageIndex, 3)
        XCTAssertEqual(commit.haptics, [.commit])
    }

    func testHapticsFireForStartAndChapterTickButNotEveryPage() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 6,
            currentProgressPercent: 0,
            targetPageIndex: { value in Int(value.rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { index in [0, 2, 5].contains(index) ? index : nil }
        )

        XCTAssertEqual(state.update(value: 1, context: context).haptics, [.start])
        XCTAssertEqual(state.update(value: 2, context: context).haptics, [.chapterTick])
        XCTAssertEqual(state.update(value: 3, context: context).haptics, [])
    }

    func testPreviewFallsBackToPageOnlyWhenChapterTitleIsUnavailable() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .vertical,
            pageCount: 6,
            currentProgressPercent: 40,
            targetPageIndex: { value in Int((value / 100 * 5).rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { _ in nil }
        )

        _ = state.update(value: 50, context: context)

        XCTAssertEqual(state.preview?.displayText, "第4页")
    }

    func testDragMappingUsesCurrentProgressAsAnchorInsteadOfFingerStartLocation() {
        let horizontal = ReaderProgressDragMapping.value(
            startProgressFraction: 0.25,
            translation: 20,
            length: 200,
            range: 0...100
        )
        let vertical = ReaderProgressDragMapping.value(
            startProgressFraction: 0.60,
            translation: -30,
            length: 300,
            range: 0...100
        )

        XCTAssertEqual(horizontal, 35, accuracy: 0.001)
        XCTAssertEqual(vertical, 50, accuracy: 0.001)
    }

    func testPagedChromePresentationUsesHorizontalScrubbingCapsule() {
        let presentation = ReaderProgressChromePresentation(readingMode: .paged, isChromeVisible: true)

        XCTAssertEqual(presentation.horizontalCapsuleText(percentText: "37%"), "目录 · 37%")
        XCTAssertTrue(presentation.showsHorizontalFill)
        XCTAssertTrue(presentation.supportsHorizontalScrub)
        XCTAssertTrue(presentation.horizontalCapsuleUsesIndependentTapAndDrag)
        XCTAssertFalse(presentation.showsConventionalSlider)
        XCTAssertFalse(presentation.showsVerticalScrubber)
    }

    func testVerticalChromePresentationUsesDirectoryCapsuleAndVisibleVerticalScrubber() {
        let visible = ReaderProgressChromePresentation(readingMode: .vertical, isChromeVisible: true)
        let hidden = ReaderProgressChromePresentation(readingMode: .vertical, isChromeVisible: false)

        XCTAssertEqual(visible.horizontalCapsuleText(percentText: "64%"), "目录 · 64%")
        XCTAssertFalse(visible.showsHorizontalFill)
        XCTAssertFalse(visible.supportsHorizontalScrub)
        XCTAssertTrue(visible.showsVerticalScrubber)
        XCTAssertFalse(hidden.showsVerticalScrubber)
    }

    func testBottomActionRowHidesDuringScrubWithoutLosingLayout() {
        let resting = ReaderBottomActionRowPresentation(isScrubbing: false)
        let scrubbing = ReaderBottomActionRowPresentation(isScrubbing: true)

        XCTAssertEqual(resting.actions.map(\.kind), [.comments, .settings, .bookmark, .cache])
        XCTAssertTrue(resting.actions.first(where: { $0.kind == .bookmark })?.isDisabled == true)
        XCTAssertEqual(resting.opacity, 1)
        XCTAssertTrue(resting.allowsHitTesting)
        XCTAssertFalse(resting.isAccessibilityHidden)

        XCTAssertEqual(scrubbing.opacity, 0)
        XCTAssertFalse(scrubbing.allowsHitTesting)
        XCTAssertTrue(scrubbing.isAccessibilityHidden)
        XCTAssertTrue(scrubbing.preservesLayout)
    }

    func testBottomChromeSeparatesProgressCapsuleFromActionButtons() {
        let presentation = ReaderBottomChromeLayoutPresentation()

        XCTAssertTrue(presentation.usesIndependentControls)
        XCTAssertEqual(presentation.panelSpacing, 10)
        XCTAssertEqual(presentation.maxChromeWidth, 260)
        XCTAssertEqual(presentation.progressPanelHeight, 44)
        XCTAssertEqual(presentation.actionButtonIconFrame, 34)
        XCTAssertEqual(presentation.actionButtonSpacing, 8)
        XCTAssertEqual(presentation.bottomControlsAdditionalBottomOffset, 8)
        XCTAssertEqual(presentation.horizontalAlignment, .trailing)
        XCTAssertTrue(presentation.progressTextLeadsIcon)
        XCTAssertTrue(presentation.progressFillHasVerticalTrailingEdge)
        XCTAssertFalse(presentation.horizontalProgressThumbVisible)
        XCTAssertTrue(presentation.horizontalChapterTicksVisibleOnlyWhileScrubbing)
        XCTAssertTrue(presentation.horizontalDirectoryContentHiddenWhileScrubbing)
        XCTAssertTrue(presentation.progressCapsulesUseButtonTint)
        XCTAssertTrue(presentation.progressSummaryVisibleWhileScrubbing)
    }

    func testReaderChromeSummarySeparatesChapterAndProgressLines() {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: "20主导权",
            progressText: "第 75 / 144 页 · 网页第 2 / 5 页 · 20主导权"
        )

        XCTAssertEqual(summary.chapterTitle, "20主导权")
        XCTAssertEqual(summary.pageProgressLine, "第 75 / 144 页")
        XCTAssertEqual(summary.webProgressLine, "网页第 2 / 5 页")
    }

    func testVerticalProgressScrubberMatchesDirectoryCapsuleLayout() {
        let presentation = ReaderBottomChromeLayoutPresentation()

        XCTAssertEqual(presentation.verticalScrubberWidth, presentation.progressPanelHeight)
        XCTAssertEqual(presentation.verticalScrubberHeight, 166)
        XCTAssertEqual(presentation.verticalPreviewWidth, presentation.maxChromeWidth)
        XCTAssertEqual(presentation.verticalPreviewHeight, 50)
        XCTAssertTrue(presentation.verticalScrubberShowsChapterTicks)
        XCTAssertTrue(presentation.verticalChapterTicksVisibleOnlyWhileScrubbing)
        XCTAssertTrue(presentation.verticalScrubberFillHasSquareEdge)
        XCTAssertTrue(presentation.hidesDirectoryCapsuleDuringVerticalScrub)
        XCTAssertEqual(presentation.verticalScrubberSideSpacing, presentation.actionButtonSpacing)
        XCTAssertTrue(presentation.verticalScrubberTicksAreCentered)
        XCTAssertFalse(presentation.verticalScrubberShowsLiveThumb)
        XCTAssertTrue(presentation.verticalScrubberBottomAlignsWithActionButtons)
        XCTAssertTrue(presentation.verticalPreviewUsesTwoLineChapterAndPage)
        XCTAssertTrue(presentation.verticalPreviewUsesLiquidGlass)
        XCTAssertTrue(presentation.horizontalPreviewMatchesVerticalCapsule)
        XCTAssertTrue(presentation.verticalScrubberShowsProgressFill)
        XCTAssertTrue(presentation.verticalCurrentChapterTickUsesAccentColor)
        XCTAssertTrue(presentation.directoryCapsuleContentUsesAccentColor)
        XCTAssertTrue(presentation.bottomProgressSummaryUsesPageCenter)
        XCTAssertTrue(presentation.verticalProgressSummaryUsesLiquidGlass)
        XCTAssertTrue(presentation.verticalChapterTitleCapsuleWrapsContent)
        XCTAssertEqual(presentation.verticalScrubberActionRowBottomOffset, 46)
    }

    func testIntegratedProgressChromeContractsAcrossPagedAndVerticalModes() {
        let paged = ReaderProgressChromePresentation(readingMode: .paged, isChromeVisible: true)
        let verticalVisible = ReaderProgressChromePresentation(readingMode: .vertical, isChromeVisible: true)
        let verticalHidden = ReaderProgressChromePresentation(readingMode: .vertical, isChromeVisible: false)
        let restingActions = ReaderBottomActionRowPresentation(isScrubbing: false)
        let scrubbingActions = ReaderBottomActionRowPresentation(isScrubbing: true)

        XCTAssertFalse(paged.showsConventionalSlider)
        XCTAssertTrue(paged.supportsHorizontalScrub)
        XCTAssertTrue(paged.showsHorizontalFill)
        XCTAssertFalse(paged.showsVerticalScrubber)

        XCTAssertFalse(verticalVisible.supportsHorizontalScrub)
        XCTAssertFalse(verticalVisible.showsHorizontalFill)
        XCTAssertTrue(verticalVisible.showsVerticalScrubber)
        XCTAssertFalse(verticalHidden.showsVerticalScrubber)

        XCTAssertTrue(restingActions.actions.contains(ReaderBottomAction(kind: .bookmark, isDisabled: true)))
        XCTAssertEqual(scrubbingActions.opacity, 0)
        XCTAssertFalse(scrubbingActions.allowsHitTesting)
        XCTAssertTrue(scrubbingActions.preservesLayout)
    }
}
