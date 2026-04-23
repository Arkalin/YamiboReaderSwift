import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderContainerModelTests: XCTestCase {
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
            model.jumpToRenderedPage(model.renderedPageCount - 1)
            XCTAssertEqual(model.currentRenderedPage, model.renderedPageCount)
        }

        await model.jumpRelativePage(1)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentRenderedPage, 1)
        }

        await model.jumpRelativePage(-1)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentRenderedPage, model.renderedPageCount)
        }
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
            model.jumpToRenderedPage(model.renderedPageCount - 1)
            XCTAssertEqual(model.currentProgressFraction, 1)
            XCTAssertEqual(model.currentProgressPercentText, "100%")
        }

        await model.jumpToWebView(99)
        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentRenderedPage, 1)
            XCTAssertEqual(model.currentWebViewText, "网页 2 / 2")
            XCTAssertEqual(model.directoryWebTitle, "网页 2 / 2 的章节")
        }
    }

    func testChapterTitleHelperResolvesRenderedPageChapter() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章"]),
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.chapterTitle(forRenderedPageIndex: 0), "第一章")
            XCTAssertEqual(model.chapterTitle(forRenderedPageIndex: model.renderedPageCount - 1), "第二章")
            XCTAssertEqual(model.chapterTitle(forRenderedPageIndex: 999), "第二章")
        }
    }

    func testTargetRenderedPageIndexMapsPagedAndVerticalProgress() async throws {
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
            XCTAssertEqual(pagedModel.targetRenderedPageIndex(forProgressValue: -3), 0)
            XCTAssertEqual(pagedModel.targetRenderedPageIndex(forProgressValue: 999), pagedModel.renderedPageCount - 1)
            XCTAssertEqual(verticalModel.targetRenderedPageIndex(forProgressValue: 0), 0)
            XCTAssertEqual(verticalModel.targetRenderedPageIndex(forProgressValue: 100), verticalModel.renderedPageCount - 1)
        }
    }

    func testTwoPageSpreadRequiresPadLandscapePagedModeAndSetting() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, pageCount: 5)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)
            model.updatePagedPresentationEnvironment(isPad: true)
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.updateLayout(
                ReaderContainerLayout(
                    width: 844,
                    height: 390,
                    readingMode: .paged
                )
            )
            XCTAssertTrue(model.isTwoPageSpreadActive)

            model.applySettings(
                ReaderAppearanceSettings(
                    showsTwoPagesInLandscapeOnPad: true,
                    readingMode: .vertical
                )
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.applySettings(
                ReaderAppearanceSettings(
                    showsTwoPagesInLandscapeOnPad: false,
                    readingMode: .paged
                )
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }
    }

    func testTwoPageSpreadBuildsExpectedPairsAndProgressText() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, pageCount: 5)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await MainActor.run {
            model.updatePagedPresentationEnvironment(isPad: true)
            model.updateLayout(
                ReaderContainerLayout(
                    width: 844,
                    height: 390,
                    readingMode: .paged
                )
            )

            XCTAssertEqual(
                model.pagedSpreads.map { "\($0.leftPageIndex)-\($0.rightPageIndex.map(String.init) ?? "nil")" },
                ["0-1", "2-3", "4-nil"]
            )
            XCTAssertEqual(model.pagedSelectionIndex, 0)
            XCTAssertTrue(model.progressText.contains("第 1-2 / 5 页"))

            model.jumpToRenderedPage(4)
            XCTAssertEqual(model.currentPageIndex, 4)
            XCTAssertEqual(model.pagedSelectionIndex, 2)
            XCTAssertTrue(model.progressText.contains("第 5 / 5 页"))
        }
    }

    func testTwoPageSpreadMapsSliderAndPagingToSpreadLeftAnchor() async throws {
        let document = makeImageDocument(view: 1, maxView: 1, pageCount: 6)
        let model = try await makeModel(
            documents: [document],
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            )
        )

        await MainActor.run {
            model.updatePagedPresentationEnvironment(isPad: true)
            model.updateLayout(
                ReaderContainerLayout(
                    width: 844,
                    height: 390,
                    readingMode: .paged
                )
            )

            XCTAssertEqual(model.targetRenderedPageIndex(forProgressValue: 1), 0)
            XCTAssertEqual(model.targetRenderedPageIndex(forProgressValue: 5), 4)

            model.jumpToRenderedPage(3)
            XCTAssertEqual(model.currentPageIndex, 2)
        }

        await model.jumpRelativePage(1)
        await MainActor.run {
            XCTAssertEqual(model.currentPageIndex, 4)
            XCTAssertEqual(model.currentRenderedPage, 5)
        }

        await MainActor.run {
            model.updatePagedSelection(1)
            XCTAssertEqual(model.currentPageIndex, 2)
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

        let singlePageCount = await MainActor.run { model.renderedPageCount }

        await MainActor.run {
            model.updatePagedPresentationEnvironment(isPad: true)
            model.updateLayout(
                ReaderContainerLayout(
                    width: 844,
                    height: 390,
                    readingMode: .paged
                )
            )
            XCTAssertTrue(model.renderedPageCount > singlePageCount)
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
            showsSystemStatusBar: false,
            loadsInlineImages: false,
            backgroundStyle: .paper,
            readingMode: .vertical,
            translationMode: .traditional
        )

        await MainActor.run {
            model.applySettings(updated)
            XCTAssertEqual(model.settings, updated)
        }
    }

    func testUpdatingLayoutRepaginatesPagedContentAndKeepsCurrentSegment() async throws {
        let model = try await makeModel(
            documents: [
                makeDocument(view: 1, maxView: 1, chapterTitles: ["第一章", "第二章", "第三章"]),
            ],
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let initialPageCount = await MainActor.run { model.renderedPageCount }

        await MainActor.run {
            model.jumpToRenderedPage(min(1, max(initialPageCount - 1, 0)))
            model.updateLayout(
                ReaderContainerLayout(
                    containerSize: CGSize(width: 390, height: 844),
                    safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
                    contentInsets: ReaderLayoutInsets(leading: 16, trailing: 16),
                    chromeInsets: ReaderLayoutInsets(top: 88, bottom: 108),
                    readingMode: .paged
                )
            )
        }

        await MainActor.run {
            XCTAssertNotEqual(model.renderedPageCount, initialPageCount)
            XCTAssertEqual(model.currentView, 1)
            XCTAssertNotNil(model.currentChapterTitle)
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
            let renderedText = model.pages.flatMap(\.blocks).compactMap { block -> String? in
                if case let .text(text, _) = block { return text }
                return nil
            }.joined()

            XCTAssertTrue(renderedText.contains("听到弓莉这么说"))
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

    func testPageChangesDebounceAndPersistLatestNovelProgress() async throws {
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
                appContext: appContext
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
        await MainActor.run {
            model.updateCurrentPage(1)
            model.updateCurrentPage(2)
        }

        try await waitFor {
            let favorite = await favoriteStore.favorite(for: document.threadURL)
            return favorite?.lastPage == 2
        }

        let favorite = await favoriteStore.favorite(for: document.threadURL)
        XCTAssertEqual(favorite?.lastView, 1)
        XCTAssertEqual(favorite?.lastPage, 2)
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
                appContext: appContext
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let targetIndex = await MainActor.run { min(2, max(model.renderedPageCount - 1, 0)) }
        let targetPage = await MainActor.run { model.pages[targetIndex] }
        await MainActor.run {
            model.updateVerticalViewportPosition(pageIndex: targetIndex, intraPageProgress: 0.55)
        }

        try await waitFor {
            let favorite = await favoriteStore.favorite(for: document.threadURL)
            return favorite?.novelResumePoint != nil
        }

        let favorite = await favoriteStore.favorite(for: document.threadURL)
        XCTAssertEqual(favorite?.lastView, 1)
        XCTAssertEqual(favorite?.lastChapter, "第一章")
        XCTAssertEqual(favorite?.novelResumePoint?.view, 1)
        XCTAssertEqual(favorite?.novelResumePoint?.segmentIndex, targetPage.segmentIndex)
        XCTAssertTrue((favorite?.novelResumePoint?.segmentOffset ?? 0) > targetPage.segmentStartOffset)
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
        let pagination = ReaderPaginator.paginate(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let savedPage = try XCTUnwrap(
            pagination.pages.first(where: { $0.chapterTitle == "第三章" && $0.segmentIndex != nil })
        )
        let savedOffset = savedPage.segmentStartOffset + max(1, (savedPage.segmentEndOffset - savedPage.segmentStartOffset) / 2)
        let savedResumePoint = ReaderResumePoint(
            view: 2,
            chapterOrdinal: try XCTUnwrap(savedPage.chapterOrdinal),
            chapterTitle: savedPage.chapterTitle,
            segmentIndex: try XCTUnwrap(savedPage.segmentIndex),
            segmentOffset: savedOffset,
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
                lastPage: savedPage.index,
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
                appContext: appContext
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第三章")
            XCTAssertEqual(model.currentPageIndex, savedPage.index)
            XCTAssertEqual(model.pages[model.currentPageIndex].segmentIndex, savedPage.segmentIndex)
            XCTAssertGreaterThan(model.currentPageIntraProgress, 0.2)
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
            ReaderContainerModel(context: launchContext, appContext: appContext)
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        let targetPage = try await MainActor.run {
            try XCTUnwrap(
                model.pages.first {
                    $0.segmentIndex != nil && $0.segmentEndOffset - $0.segmentStartOffset > 50
                }
            )
        }
        await MainActor.run {
            model.updateVerticalViewportPosition(pageIndex: targetPage.index, intraPageProgress: 0.50)
        }
        await model.saveProgress()
        await MainActor.run {
            model.updateVerticalViewportPosition(pageIndex: targetPage.index, intraPageProgress: 0.59)
        }
        await model.saveProgress()

        let restoredModel = await MainActor.run {
            ReaderContainerModel(context: launchContext, appContext: appContext)
        }

        await restoredModel.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(restoredModel.currentPageIndex, targetPage.index)
            XCTAssertEqual(restoredModel.pages[restoredModel.currentPageIndex].segmentIndex, targetPage.segmentIndex)
            XCTAssertEqual(restoredModel.currentPageIntraProgress, 0.59, accuracy: 0.02)
        }
    }

    func testStoredResumePointOverridesLaunchPageWhenPreparingReader() async throws {
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
        let pagination = ReaderPaginator.paginate(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let savedPage = try XCTUnwrap(
            pagination.pages.first(where: { $0.chapterTitle == "第二章" && $0.segmentIndex != nil })
        )
        let savedResumePoint = ReaderResumePoint(
            view: 2,
            chapterOrdinal: try XCTUnwrap(savedPage.chapterOrdinal),
            chapterTitle: savedPage.chapterTitle,
            segmentIndex: try XCTUnwrap(savedPage.segmentIndex),
            segmentOffset: savedPage.segmentStartOffset,
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
                lastPage: 99,
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
                    initialView: 2,
                    initialPage: 99
                ),
                appContext: appContext
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 2)
            XCTAssertEqual(model.currentChapterTitle, "第二章")
            XCTAssertEqual(model.currentPageIndex, savedPage.index)
            XCTAssertEqual(model.pages[model.currentPageIndex].segmentIndex, savedPage.segmentIndex)
        }
    }

    func testLaunchPageIsUsedWhenNoStoredResumePointExists() async throws {
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
                    initialView: 1,
                    initialPage: 1
                ),
                appContext: appContext
            )
        }

        await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))

        await MainActor.run {
            XCTAssertEqual(model.currentView, 1)
            XCTAssertEqual(model.currentPageIndex, 1)
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
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let originalOffset = await MainActor.run { () -> Int in
            let targetIndex = min(1, max(model.renderedPageCount - 1, 0))
            model.updateVerticalViewportPosition(pageIndex: targetIndex, intraPageProgress: 0.5)
            let page = model.pages[targetIndex]
            return page.segmentStartOffset + max(1, (page.segmentEndOffset - page.segmentStartOffset) / 2)
        }

        await MainActor.run {
            model.applySettings(ReaderAppearanceSettings(readingMode: .vertical))
        }

        await MainActor.run {
            let page = model.pages[model.currentPageIndex]
            XCTAssertEqual(page.chapterTitle, "第一章")
            XCTAssertTrue(pageContainsOffset(page, offset: originalOffset))
        }

        await MainActor.run {
            model.applySettings(ReaderAppearanceSettings(readingMode: .paged))
        }

        await MainActor.run {
            let page = model.pages[model.currentPageIndex]
            XCTAssertEqual(page.chapterTitle, "第一章")
            XCTAssertTrue(pageContainsOffset(page, offset: originalOffset))
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
            settings: ReaderAppearanceSettings(readingMode: .paged)
        )

        let target = try await MainActor.run {
            let mergedPage = try XCTUnwrap(model.pages.first { $0.textRanges.count >= 2 })
            let targetRange = try XCTUnwrap(mergedPage.textRanges.first { $0.segmentIndex == 1 })
            let totalLength = mergedPage.textRanges.reduce(0) { $0 + max($1.length, 1) }
            let precedingLength = mergedPage.textRanges
                .prefix { $0.segmentIndex != targetRange.segmentIndex }
                .reduce(0) { $0 + max($1.length, 1) }
            let targetOffset = targetRange.startOffset + max(1, targetRange.length / 2)
            let progress = Double(precedingLength + max(1, targetRange.length / 2)) / Double(max(totalLength, 1))
            model.updateVerticalViewportPosition(pageIndex: mergedPage.index, intraPageProgress: progress)
            return (segmentIndex: targetRange.segmentIndex, offset: targetOffset)
        }

        await MainActor.run {
            model.applySettings(ReaderAppearanceSettings(readingMode: .vertical))
        }

        await MainActor.run {
            let page = model.pages[model.currentPageIndex]
            XCTAssertTrue(pageContainsSegmentOffset(page, segmentIndex: target.segmentIndex, offset: target.offset))
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
            let page = try XCTUnwrap(model.pages.dropFirst().first { $0.segmentIndex != nil })
            let offset = page.segmentStartOffset + max(1, (page.segmentEndOffset - page.segmentStartOffset) / 2)
            model.updateVerticalViewportPosition(pageIndex: page.index, intraPageProgress: 0.5)
            return offset
        }

        await MainActor.run {
            model.applySettings(ReaderAppearanceSettings(readingMode: .vertical))
            model.updateLayout(
                ReaderContainerLayout(
                    containerSize: CGSize(width: 390, height: 844),
                    safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
                    contentInsets: ReaderLayoutInsets(top: 16, leading: 16, bottom: 24, trailing: 16),
                    chromeInsets: ReaderLayoutInsets(top: 72, bottom: 96),
                    readingMode: .vertical
                )
            )
        }

        await MainActor.run {
            let page = model.pages[model.currentPageIndex]
            XCTAssertTrue(pageContainsSegmentOffset(page, segmentIndex: 0, offset: originalOffset))
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
                appContext: appContext
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
    cacheStore: ReaderCacheStore? = nil
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
            appContext: appContext
        )
    }

    await model.prepare(layout: ReaderContainerLayout(width: 320, height: 568))
    return model
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

private func pageContainsOffset(_ page: ReaderRenderedPage, offset: Int) -> Bool {
    if page.segmentStartOffset == page.segmentEndOffset {
        return offset <= page.segmentStartOffset
    }
    return offset >= page.segmentStartOffset && offset < page.segmentEndOffset
}

private func pageContainsSegmentOffset(_ page: ReaderRenderedPage, segmentIndex: Int, offset: Int) -> Bool {
    let matchingRanges = page.textRanges.filter { $0.segmentIndex == segmentIndex }
    if !matchingRanges.isEmpty {
        return matchingRanges.contains { range in
            if range.startOffset == range.endOffset {
                return offset <= range.startOffset
            }
            return offset >= range.startOffset && offset < range.endOffset
        }
    }
    guard page.segmentIndex == segmentIndex else { return false }
    return pageContainsOffset(page, offset: offset)
}

private func makeDocument(
    threadURL: URL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=556677&mobile=2")!,
    view: Int,
    maxView: Int,
    chapterTitles: [String],
    authorID: String? = nil,
    contentSource: ReaderContentSource = .fallbackUnfilteredPage
) -> ReaderPageDocument {
    let segments = chapterTitles.map { title in
        ReaderSegment.text(String(repeating: "\(title) 内容。", count: 80), chapterTitle: title)
    }
    return ReaderPageDocument(
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: contentSource,
        segments: segments
    )
}

private func makeImageDocument(
    threadURL: URL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=998877&mobile=2")!,
    view: Int,
    maxView: Int,
    pageCount: Int
) -> ReaderPageDocument {
    let segments = (0..<pageCount).map { index in
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
