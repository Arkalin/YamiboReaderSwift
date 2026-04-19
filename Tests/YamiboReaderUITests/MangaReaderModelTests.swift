import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class MangaReaderModelTests: XCTestCase {
    func testPrepareLoadsInitialChapterAndSavesProgress() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                )
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.pages.count, 2)
            XCTAssertEqual(model.viewportRequest?.targetIndex, 0)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#0")
            model.updateCurrentPage(1)
        }
        await model.saveProgress()

        let favorite = await modelTestFavoriteStore?.favorite(for: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!)
        XCTAssertEqual(favorite?.type, .manga)
        XCTAssertEqual(favorite?.lastPage, 1)
        XCTAssertEqual(favorite?.lastChapter, "第1话")
    }

    func testPrefetchesNextChapterAndJumpsBetweenChapters() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 3
                )
            ]
        )

        await MainActor.run {
            model.updateCurrentPage(1)
        }
        try await waitFor {
            await MainActor.run {
                model.pages.count == 5
            }
        }

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第2话")
            XCTAssertEqual(model.currentPageIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
            XCTAssertTrue(model.hasPreviousChapter)
            XCTAssertFalse(model.hasNextChapter)
        }
    }

    func testJumpingToLoadedChapterStillEmitsViewportRequest() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 2
                )
            ]
        )

        await MainActor.run {
            model.updateCurrentPage(1)
        }
        try await waitFor {
            await MainActor.run { model.pages.count == 4 }
        }

        let initialRevision = await MainActor.run { model.viewportRequest?.revision }
        guard let targetChapter = await MainActor.run(body: { model.currentDirectory?.chapters.last }) else {
            XCTFail("Expected a second chapter")
            return
        }

        await model.jumpToChapter(targetChapter)

        await MainActor.run {
            XCTAssertEqual(model.currentPageIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
            XCTAssertNotEqual(model.viewportRequest?.revision, initialRevision)
        }
    }

    func testJumpFailureFallsBackToWeb() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 1
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 0
                )
            ]
        )

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            XCTAssertEqual(
                model.fallbackWebContext?.currentURL.absoluteString,
                "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=701"
            )
            XCTAssertFalse(model.fallbackWebContext?.autoOpenNative ?? true)
        }
    }

    func testFavoritesViewModelResolvesUnknownFavoriteToManga() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let html = makeMangaHTML(tid: "800", title: "第1话", links: [], imageCount: 1)
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
        }
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "未知收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=800&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.resolveOpenTarget(for: favorite)
        switch target {
        case .manga:
            let stored = await favoriteStore.favorite(for: favorite.url)
            XCTAssertEqual(stored?.type, .manga)
        default:
            XCTFail("Expected manga target")
        }
    }

    func testKeepsLoadedDocumentWindowBoundedToTenChapters() async throws {
        let chapterHTML = Dictionary(uniqueKeysWithValues: (700 ... 711).map { tid in
            let title = "第\(tid - 699)话"
            let links = (700 ... 711)
                .filter { $0 != tid }
                .map { ("\($0)", "第\($0 - 699)话") }
            return ("\(tid)", makeMangaHTML(tid: "\(tid)", title: title, links: links, imageCount: 1))
        })

        let model = try await makeMangaModel(chapterHTMLByTID: chapterHTML)

        for _ in 0 ..< 11 {
            await model.jumpToAdjacentChapter(1)
        }

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第12话")
            XCTAssertEqual(model.pages.count, 10)
            XCTAssertEqual(model.pages.first?.chapterTitle, "第3话")
            XCTAssertEqual(model.pages.last?.chapterTitle, "第12话")
        }
    }

    func testFarJumpResetsLoadedWindowToTargetChapter() async throws {
        let chapterHTML = Dictionary(uniqueKeysWithValues: (700 ... 705).map { tid in
            let title = "第\(tid - 699)话"
            let links = (700 ... 705)
                .filter { $0 != tid }
                .map { ("\($0)", "第\($0 - 699)话") }
            return ("\(tid)", makeMangaHTML(tid: "\(tid)", title: title, links: links, imageCount: 2))
        })

        let model = try await makeMangaModel(chapterHTMLByTID: chapterHTML)
        guard let targetChapter = await MainActor.run(body: { model.currentDirectory?.chapters.last }) else {
            XCTFail("Expected directory to be initialized")
            return
        }

        await model.jumpToChapter(targetChapter)

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第6话")
            XCTAssertEqual(model.pages.count, 2)
            XCTAssertEqual(Set(model.pages.map(\.chapterTitle)), ["第6话"])
            XCTAssertEqual(model.viewportRequest?.targetPageID, "705#0")
        }
    }

    func testPrefetchingPreviousChapterPreservesCurrentFocusAndStablePageIDs() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话"), ("702", "第3话")],
                    imageCount: 2
                ),
                "702": makeMangaHTML(
                    tid: "702",
                    title: "第3话",
                    links: [("701", "第2话")],
                    imageCount: 2
                )
            ],
            appSettings: AppSettings(
                manga: MangaReaderSettings(readingMode: .paged)
            ),
            initialTID: "701"
        )

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.id, "701#0")
            model.updateCurrentPage(0)
        }
        try await waitFor {
            await MainActor.run { Set(model.pages.map(\.tid)) == Set(["700", "701", "702"]) }
        }

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.tid, "701")
            XCTAssertEqual(model.currentPage?.localIndex, 0)
            XCTAssertEqual(model.currentPage?.id, "701#0")
            XCTAssertTrue(model.pages.map(\.id).contains("700#0"))
            XCTAssertTrue(model.pages.map(\.id).contains("700#1"))
            XCTAssertTrue(model.pages.map(\.id).contains("701#0"))
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
        }
    }

    func testCurrentPagePrefetchesVisibleImageWindow() async throws {
        let observedRequests = RequestLog()
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 10
                )
            ],
            requestLog: observedRequests
        )

        await MainActor.run {
            model.updateCurrentPage(3)
        }
        try await waitFor {
            let imageRequests = await observedRequests.snapshot().filter {
                $0.host == "img.example.com" && $0.lastPathComponent.hasPrefix("700-")
            }
            return Set(imageRequests.map(\.absoluteString)).count == 10
        }

        let imageRequests = await observedRequests.snapshot()
            .filter { $0.host == "img.example.com" && $0.lastPathComponent.hasPrefix("700-") }
            .map(\.lastPathComponent)

        XCTAssertEqual(
            Set(imageRequests),
            Set((0 ... 9).map { "700-\($0).jpg" })
        )
    }

    func testDataSaverDisablesBackgroundImagePrefetch() async throws {
        let observedRequests = RequestLog()
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 10
                )
            ],
            appSettings: AppSettings(usesDataSaverMode: true),
            requestLog: observedRequests
        )

        await MainActor.run {
            model.updateCurrentPage(3)
        }
        try await Task.sleep(nanoseconds: 300_000_000)

        let imageRequests = await observedRequests.snapshot().filter { $0.host == "img.example.com" }
        XCTAssertTrue(imageRequests.isEmpty)
    }

    func testApplyDirectorySortOrderPersistsPreference() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let tid = MangaTitleCleaner.extractTid(from: request.url!.absoluteString) ?? "700"
            let html = makeMangaHTML(
                tid: tid,
                title: tid == "700" ? "第1话" : "第2话",
                links: [("700", "第1话"), ("701", "第2话")].filter { $0.0 != tid },
                imageCount: 1
            )
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
        }

        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites"),
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaImageCacheStore: MangaImageCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )

        let firstModel = await MainActor.run {
            MangaReaderModel(
                context: MangaLaunchContext(
                    originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    displayTitle: "测试漫画",
                    source: .forum
                ),
                appContext: appContext
            )
        }
        await firstModel.prepare()
        await MainActor.run {
            firstModel.applyDirectorySortOrder(MangaDirectorySortOrder.descending)
        }
        try await waitFor {
            let loaded = await settingsStore.load()
            return loaded.manga.directorySortOrder == .descending
        }

        let secondModel = await MainActor.run {
            MangaReaderModel(
                context: MangaLaunchContext(
                    originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    displayTitle: "测试漫画",
                    source: .forum
                ),
                appContext: appContext
            )
        }
        await secondModel.prepare()

        await MainActor.run {
            XCTAssertEqual(secondModel.settings.directorySortOrder, MangaDirectorySortOrder.descending)
            XCTAssertEqual(secondModel.sortedDirectoryChapters.first?.tid, "701")
        }
    }

    func testAutoTagUpdateShowsForceSearchShortcut() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1,
                    tagIDs: ["31"]
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                guard url.contains("misc.php"), url.contains("id=31"), url.contains("page=1") else {
                    return nil
                }
                return httpResponse(
                    url: request.url!,
                    body: """
                    <table>
                      <tr>
                        <th><a href="thread-700-1-1.html">第1话</a></th>
                        <td class="by"></td>
                        <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
                      </tr>
                      <tr>
                        <th><a href="thread-701-1-1.html">第2话</a></th>
                        <td class="by"></td>
                        <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-03</span></em></td>
                      </tr>
                    </table>
                    """
                )
            }
        )

        await MainActor.run {
            XCTAssertEqual(model.currentDirectory?.strategy, .tag)
            XCTAssertTrue(model.showsForceSearchShortcut)
            XCTAssertGreaterThanOrEqual(model.forceSearchShortcutRemaining, 4)
            XCTAssertEqual(model.directoryUpdateButtonTitle, "全局搜索 \(model.forceSearchShortcutRemaining)s")
            XCTAssertTrue(model.sortedDirectoryChapters.map(\.tid).contains("701"))
        }
    }

    func testForcedSearchStartsDirectoryCooldown() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1,
                    tagIDs: ["31"]
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                if url.contains("misc.php"), url.contains("id=31"), url.contains("page=1") {
                    return httpResponse(
                        url: request.url!,
                        body: """
                        <table>
                          <tr>
                            <th><a href="thread-700-1-1.html">第1话</a></th>
                            <td class="by"></td>
                            <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
                          </tr>
                        </table>
                        """
                    )
                }
                if url.contains("search.php") {
                    return httpResponse(
                        url: request.url!,
                        body: """
                        <li class="list">
                          <a href="forum.php?mod=viewthread&tid=700&mobile=2">第1话</a>
                          <h3><a href="space-uid-77.html">作者甲</a></h3>
                        </li>
                        """
                    )
                }
                return nil
            }
        )

        await MainActor.run {
            XCTAssertTrue(model.showsForceSearchShortcut)
        }
        await model.updateDirectoryFromPanel()

        await MainActor.run {
            XCTAssertFalse(model.showsForceSearchShortcut)
            XCTAssertGreaterThanOrEqual(model.directoryCooldownRemaining, 19)
            XCTAssertEqual(model.directoryUpdateButtonTitle, "\(model.directoryCooldownRemaining)s")
        }
    }

    func testSearchCooldownErrorStartsDirectoryCooldown() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                guard url.contains("search.php") else { return nil }
                return httpResponse(
                    url: request.url!,
                    body: """
                    <li class="list">
                      <a href="forum.php?mod=viewthread&tid=700&mobile=2">第1话</a>
                      <h3><a href="space-uid-77.html">作者甲</a></h3>
                    </li>
                    """
                )
            }
        )

        let strategy = await MainActor.run { model.currentDirectory?.strategy }
        XCTAssertEqual(strategy, .pendingSearch)

        await model.updateDirectory(isForcedSearch: true)
        await model.updateDirectory(isForcedSearch: true)

        await MainActor.run {
            XCTAssertEqual(model.errorMessage, YamiboError.searchCooldown(seconds: 20).errorDescription)
            XCTAssertGreaterThanOrEqual(model.directoryCooldownRemaining, 19)
        }
    }

    func testCurrentChapterRemainsStableWhenDirectorySortOrderChanges() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 1
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 1
                )
            ]
        )

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            model.applyDirectorySortOrder(.descending)
            XCTAssertEqual(model.currentPage?.tid, "701")
            XCTAssertEqual(model.sortedDirectoryChapters.first?.tid, "701")
            XCTAssertEqual(model.sortedDirectoryChapters.last?.tid, "700")
        }
    }
}

private nonisolated(unsafe) var modelTestFavoriteStore: FavoriteStore?
private nonisolated(unsafe) var modelRequestLog: RequestLog?

private func makeMangaModel(
    chapterHTMLByTID: [String: String],
    appSettings: AppSettings = AppSettings(),
    requestLog: RequestLog? = nil,
    requestHandler: ((URLRequest) -> (Data, HTTPURLResponse)?)? = nil,
    initialTID: String = "700",
    initialPage: Int = 0
) async throws -> MangaReaderModel {
    let keyPrefix = UUID().uuidString
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
    let session = URLSession(configuration: configuration)
    modelRequestLog = requestLog
    MangaReaderTestURLProtocol.handler = { request in
        Task {
            await modelRequestLog?.record(request.url!)
        }
        if let requestHandler, let customResponse = requestHandler(request) {
            return customResponse
        }
        let url = request.url!.absoluteString
        if request.url?.host == "img.example.com" {
            return (Data([0x01, 0x02, 0x03]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!)
        }
        let tid = MangaTitleCleaner.extractTid(from: url) ?? "700"
        let html = chapterHTMLByTID[tid] ?? ""
        return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
    }

    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    try await settingsStore.save(appSettings)
    modelTestFavoriteStore = favoriteStore
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(key: "\(keyPrefix).session"),
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        mangaImageCacheStore: MangaImageCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        session: session
    )
    let model = await MainActor.run {
        let initialURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(initialTID)&mobile=2")!
        return MangaReaderModel(
            context: MangaLaunchContext(
                originalThreadURL: initialURL,
                chapterURL: initialURL,
                displayTitle: "测试漫画",
                source: .forum,
                initialPage: initialPage
            ),
            appContext: appContext
        )
    }
    await model.prepare()
    return model
}

private func makeMangaHTML(
    tid: String,
    title: String,
    links: [(String, String)],
    imageCount: Int,
    tagIDs: [String] = []
) -> String {
    let linkHTML = links.map { tid, title in
        #"<a href="forum.php?mod=viewthread&tid=\#(tid)&mobile=2">\#(title)</a>"#
    }.joined(separator: "\n")
    let tagHTML = tagIDs.map { tagID in
        #"<a href="misc.php?mod=tag&id=\#(tagID)">tag-\#(tagID)</a>"#
    }.joined(separator: "\n")
    let imageHTML = (0 ..< imageCount).map { index in
        #"<img src="https://img.example.com/\#(tid)-\#(index).jpg" />"#
    }.joined(separator: "\n")
    return """
    <html>
      <head><title>\(title) - 中文百合漫画区 - 百合会</title></head>
      <body>
        <div class="header"><h2><a>中文百合漫画区</a></h2></div>
        <div class="message">
          \(tagHTML)
          \(linkHTML)
          \(imageHTML)
        </div>
      </body>
    </html>
    """
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

private func httpResponse(url: URL, body: String, statusCode: Int = 200) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
    )
}

private final class MangaReaderTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

private actor RequestLog {
    private var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }

    func snapshot() -> [URL] {
        urls
    }
}
