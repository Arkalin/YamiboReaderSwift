import Foundation

public actor ForumRepository {
    private let client: YamiboClient
    private let cacheStore: ForumCacheStore
    private let now: @Sendable () -> Date

    public init(
        client: YamiboClient,
        cacheStore: ForumCacheStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.cacheStore = cacheStore
        self.now = now
    }

    public func cachedForumHome(allowExpired: Bool = false) async -> ForumHomePage? {
        await cacheStore.loadHome(allowExpired: allowExpired)
    }

    public func fetchForumHome(preferCache: Bool = true) async throws -> ForumHomePage {
        if preferCache, let cached = await cacheStore.loadHome() {
            return cached
        }

        let html = try await client.fetchHTML(for: .forumHome, cachePolicy: .reloadIgnoringLocalCacheData)
        let page = try ForumHTMLParser.parseHomePage(from: html, fetchedAt: now())
        try await cacheStore.saveHome(page)
        return page
    }

    public func fetchForumBoard(
        fid: String,
        title: String? = nil,
        page: Int = 1,
        filterID: String? = nil,
        orderID: String? = nil,
        preferCache: Bool = true
    ) async throws -> ForumBoardPage {
        if preferCache,
           let cached = await cacheStore.loadBoard(fid: fid, page: page, filterID: filterID, orderID: orderID) {
            return cached
        }

        let html = try await client.fetchHTML(
            for: .forumBoard(fid: fid, page: page, filterID: filterID, orderID: orderID),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let board = try ForumHTMLParser.parseBoardPage(from: html, fid: fid, title: title, fetchedAt: now())
        try await cacheStore.saveBoard(board, fid: fid, pageNumber: page, filterID: filterID, orderID: orderID)
        return board
    }
}
