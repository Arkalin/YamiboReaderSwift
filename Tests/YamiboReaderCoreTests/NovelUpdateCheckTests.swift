import Foundation
import Testing
@testable import YamiboReaderCore

private final class NovelUpdateURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let body = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct NovelUpdateCheckTests {

@Test func readerDocumentFingerprintIsStableForEquivalentDocuments() async throws {
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=810&mobile=2"))
    let first = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 1,
        segments: [
            .text("第一章\n正文", chapterTitle: "第一章"),
            .image(URL(string: "https://example.com/a.jpg")!, chapterTitle: "第一章")
        ],
        fetchedAt: Date(timeIntervalSince1970: 1)
    )
    let sameContent = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 1,
        contentSource: .fallbackUnfilteredPage,
        segments: first.segments,
        fetchedAt: Date(timeIntervalSince1970: 2)
    )
    let changed = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 1,
        segments: [
            .text("第一章\n正文已修改", chapterTitle: "第一章"),
            .image(URL(string: "https://example.com/a.jpg")!, chapterTitle: "第一章")
        ]
    )

    #expect(ReaderDocumentFingerprint.fingerprint(for: first) == ReaderDocumentFingerprint.fingerprint(for: sameContent))
    #expect(ReaderDocumentFingerprint.fingerprint(for: first) != ReaderDocumentFingerprint.fingerprint(for: changed))
}

@Test func novelUpdateCheckWithoutCachedTerminalPageDoesNotSetBadge() async throws {
    let setup = try await makeNovelUpdateSetup()
    let favorite = Favorite(title: "小说", url: setup.threadURL, type: .novel)
    try await setup.favoriteStore.saveFavorites([favorite])

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .noCachedBaseline)
    #expect(updated?.novelUpdateStatus == FavoriteNovelUpdateStatus.none)
    #expect(updated?.hasPendingNovelUpdate == false)
}

@Test func novelUpdateCheckMarksNewPageWhenRemoteMaxViewIncreases() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached)
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { request in
        html(text: "第一页", tid: "811", maxView: 3)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .newPage)
    #expect(updated?.novelUpdateStatus == .newPage)
    #expect(updated?.hasPendingNovelUpdate == true)
    #expect(updated?.knownMaxView == 2)
    #expect(updated?.lastRemoteMaxView == 3)
    #expect(updated?.currentNovelUpdateSignature == "newPage:3")
}

@Test func novelUpdateCheckDoesNotRepeatAcknowledgedNewPageSignature() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached),
        currentNovelUpdateSignature: "newPage:3",
        acknowledgedNovelUpdateSignature: "newPage:3"
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { _ in
        html(text: "第一页", tid: "811", maxView: 3)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .noUpdate)
    #expect(updated?.novelUpdateStatus == FavoriteNovelUpdateStatus.none)
    #expect(updated?.hasPendingNovelUpdate == false)
    #expect(updated?.currentNovelUpdateSignature == "newPage:3")
    #expect(updated?.acknowledgedNovelUpdateSignature == "newPage:3")
}

@Test func novelUpdateCheckRemindsAgainWhenRemoteMaxViewAdvancesAfterAcknowledgement() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached),
        currentNovelUpdateSignature: "newPage:3",
        acknowledgedNovelUpdateSignature: "newPage:3"
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { _ in
        html(text: "第一页", tid: "811", maxView: 4)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .newPage)
    #expect(updated?.novelUpdateStatus == .newPage)
    #expect(updated?.hasPendingNovelUpdate == true)
    #expect(updated?.currentNovelUpdateSignature == "newPage:4")
    #expect(updated?.acknowledgedNovelUpdateSignature == "newPage:3")
}

@Test func novelUpdateCheckMarksContentChangedWhenLastPageFingerprintDiffers() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached)
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { request in
        let page = pageNumber(from: request)
        return html(text: page == 2 ? "新末页" : "第一页", tid: "811", maxView: 2)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)
    let cachedViews = await setup.cacheStore.cachedViews(
        for: setup.threadURL,
        authorID: nil,
        contentSource: .fallbackUnfilteredPage
    )

    #expect(result.status == .contentChanged)
    #expect(updated?.novelUpdateStatus == .contentChanged)
    #expect(updated?.hasPendingNovelUpdate == true)
    #expect(updated?.currentNovelUpdateSignature?.hasPrefix("contentChanged:2:") == true)
    #expect(cachedViews == Set([2]))
}

@Test func novelUpdateCheckClearsBadgeWhenLastPageFingerprintMatches() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached),
        novelUpdateStatus: .contentChanged
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { request in
        let page = pageNumber(from: request)
        return html(text: page == 2 ? "旧末页" : "第一页", tid: "811", maxView: 2)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .noUpdate)
    #expect(updated?.novelUpdateStatus == FavoriteNovelUpdateStatus.none)
    #expect(updated?.hasPendingNovelUpdate == false)
    #expect(updated?.lastUpdateCheckedAt != nil)
}

@Test func novelUpdateCheckMarksStructureChangedWithoutBadgeWhenRemoteMaxViewShrinks() async throws {
    let setup = try await makeNovelUpdateSetup()
    let cached = makeNovelDocument(threadURL: setup.threadURL, view: 2, maxView: 2, text: "旧末页")
    try await setup.cacheStore.save(cached)
    let favorite = Favorite(
        title: "小说",
        url: setup.threadURL,
        type: .novel,
        knownMaxView: 2,
        knownMaxViewFingerprint: ReaderDocumentFingerprint.fingerprint(for: cached)
    )
    try await setup.favoriteStore.saveFavorites([favorite])

    NovelUpdateURLProtocol.handler = { _ in
        html(text: "第一页", tid: "811", maxView: 1)
    }

    let result = try await NovelUpdateCheckService(appContext: setup.appContext).check(favoriteID: favorite.id)
    let updated = await setup.favoriteStore.favorite(id: favorite.id)

    #expect(result.status == .structureChanged)
    #expect(updated?.novelUpdateStatus == .structureChanged)
    #expect(updated?.hasPendingNovelUpdate == false)
    #expect(updated?.lastRemoteMaxView == 1)
}

}

private struct NovelUpdateSetup {
    var appContext: YamiboAppContext
    var favoriteStore: FavoriteStore
    var cacheStore: ReaderCacheStore
    var threadURL: URL
}

private func makeNovelUpdateSetup() async throws -> NovelUpdateSetup {
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=811&mobile=2"))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NovelUpdateURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let suiteName = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let favoriteStore = FavoriteStore(defaults: defaults, key: "favorites")
    let cacheStore = ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    let appContext = YamiboAppContext(
        favoriteStore: favoriteStore,
        readerCacheStore: cacheStore,
        session: session
    )
    return NovelUpdateSetup(appContext: appContext, favoriteStore: favoriteStore, cacheStore: cacheStore, threadURL: threadURL)
}

private func makeNovelDocument(threadURL: URL, view: Int, maxView: Int, text: String) -> ReaderPageDocument {
    ReaderPageDocument(
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        contentSource: .fallbackUnfilteredPage,
        segments: [.text(text, chapterTitle: text)]
    )
}

private func html(text: String, tid: String, maxView: Int) -> String {
    let links = maxView > 1
        ? (1 ... maxView).map { #"<a href="forum.php?mod=viewthread&tid=\#(tid)&page=\#($0)">\#($0)</a>"# }.joined()
        : ""
    return """
    <html>
      <body>
        <div class="message">\(text)</div>
        \(links)
      </body>
    </html>
    """
}

private func pageNumber(from request: URLRequest) -> Int {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == "page" })?
        .value
        .flatMap(Int.init) ?? 1
}
