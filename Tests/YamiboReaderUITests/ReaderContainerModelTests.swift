import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderContainerModelTests: XCTestCase {
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
        }
    }
}

private func makeModel(
    documents: [ReaderPageDocument],
    settings: ReaderAppearanceSettings = ReaderAppearanceSettings(readingMode: .paged)
) async throws -> ReaderContainerModel {
    let keyPrefix = UUID().uuidString
    let sessionStore = SessionStore(key: "\(keyPrefix).session")
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheStore = ReaderCacheStore(baseDirectory: cacheDirectory)

    try await settingsStore.save(AppSettings(reader: settings))
    for document in documents {
        try await cacheStore.save(document)
    }

    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        readerCacheStore: cacheStore
    )
    let model = await MainActor.run {
        ReaderContainerModel(
            context: ReaderLaunchContext(
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

private func makeDocument(view: Int, maxView: Int, chapterTitles: [String]) -> ReaderPageDocument {
    let segments = chapterTitles.map { title in
        ReaderSegment.text(String(repeating: "\(title) 内容。", count: 80), chapterTitle: title)
    }
    return ReaderPageDocument(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=556677&mobile=2")!,
        view: view,
        maxView: maxView,
        segments: segments
    )
}
