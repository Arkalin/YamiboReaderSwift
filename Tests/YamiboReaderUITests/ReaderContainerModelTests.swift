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
