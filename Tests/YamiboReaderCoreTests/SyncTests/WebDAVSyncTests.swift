import Foundation
import Testing
@testable import YamiboReaderCore

private final class WebDAVTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let lock = NSLock()

    static func setHandler(for host: String, _ handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
        }
    }

    static func removeHandler(for host: String) {
        _ = lock.withLock {
            handlers.removeValue(forKey: host)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let host = request.url?.host,
            let handler = Self.lock.withLock({ Self.handlers[host] })
        else {
            client?.urlProtocol(self, didFailWithError: WebDAVTestError.missingHandler)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum WebDAVTestError: Error {
    case missingHandler
}

@Test func webDAVClientUploadsWithBasicAuthAndExpectedPaths() async throws {
    let session = makeWebDAVTestSession()
    let client = WebDAVClient(session: session)
    let host = "upload.example.com"
    let settings = WebDAVSyncSettings(
        baseURLString: "https://\(host)/root",
        username: "admin",
        password: "secret"
    )
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 1_000),
        library: FavoriteLibrarySnapshot(favorites: [], collections: [])
    )
    var requests: [URLRequest] = []

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        requests.append(request)
        let response: HTTPURLResponse
        switch request.httpMethod {
        case "MKCOL":
            response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        case "PUT":
            #expect(request.url?.path == "/root/YamiboReader/yamibo-sync-v1.json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("admin:secret".utf8).base64EncodedString())")
            let body = try #require(request.webDAVBodyData())
            let decoded = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            #expect(decoded == payload)
            response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    try await client.uploadPayload(payload, settings: settings)

    #expect(requests.map(\.httpMethod) == ["MKCOL", "PUT"])
    #expect(requests.first?.url?.path == "/root/YamiboReader")
}

@Test func webDAVClientMapsNotFoundAndAuthenticationFailures() async throws {
    let session = makeWebDAVTestSession()
    let client = WebDAVClient(session: session)
    let host = "status.example.com"
    let settings = WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "bad"
    )

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: WebDAVSyncError.notFound) {
        _ = try await client.fetchPayload(settings: settings)
    }

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: WebDAVSyncError.notAuthenticated) {
        _ = try await client.fetchPayload(settings: settings)
    }

    WebDAVTestURLProtocol.removeHandler(for: host)
}

@Test func webDAVSyncRequiresStoredAccountUID() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-requires-account-uid")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let settings = WebDAVSyncSettings(
        baseURLString: "https://requires-account-uid.example.com",
        username: "admin",
        password: "secret"
    )
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true))

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    await #expect(throws: YamiboError.accountUIDUnavailable) {
        _ = try await service.upload(using: settings)
    }
    await #expect(throws: YamiboError.accountUIDUnavailable) {
        _ = try await service.download(using: settings)
    }
}

@Test func webDAVSyncDownloadRestoresLibraryWithoutTouchingSessionSignInSettingsOrCaches() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-download")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let rootDirectory = makeWebDAVTemporaryDirectory(prefix: "webdav-download-root")
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let checkInStore = YamiboCheckInStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), keyPrefix: "check-in")
    let appSettingsStore = SettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "settings")
    let readerCacheStore = ReaderCacheStore(baseDirectory: rootDirectory.appendingPathComponent("reader-cache", isDirectory: true))

    let host = "download.example.com"
    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true
    ))
    try await appSettingsStore.save(AppSettings(reader: ReaderAppearanceSettings(readingMode: .vertical)))
    let localSession = SessionState(cookie: "foo=1; EeqY_2132_auth=local-user", userAgent: "Local-UA", isLoggedIn: true, accountUID: "100")
    try await sessionStore.save(localSession)
    await checkInStore.markCheckedIn(session: localSession)

    let localURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2"))
    try await readerCacheStore.save(
        ReaderPageDocument(threadURL: localURL, view: 1, maxView: 1, segments: [.text("local cache", chapterTitle: nil)])
    )

    let remoteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&mobile=2"))
    let collection = FavoriteCollection(id: "collection-a", name: "远端合集", manualOrder: 0, isHidden: true)
    let favorite = Favorite(
        title: "远端收藏",
        url: remoteURL,
        mangaPageIndex: 7,
        lastView: 2,
        lastChapter: "第二章",
        isHidden: true,
        parentCollectionID: collection.id,
        manualOrder: 0
    )
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        library: FavoriteLibrarySnapshot(favorites: [favorite], collections: [collection])
    )
    let encodedPayload = try JSONEncoder().encode(payload)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            encodedPayload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.download()

    let loadedLibrary = await favoriteStore.loadLibrarySnapshot()
    var expectedFavorite = favorite
    expectedFavorite.isHidden = false
    var expectedCollection = collection
    expectedCollection.isHidden = false
    #expect(loadedLibrary.favorites == [expectedFavorite])
    #expect(loadedLibrary.collections == [expectedCollection])
    #expect(await sessionStore.load() == localSession)
    #expect(await checkInStore.lastCheckedInDate(session: localSession) != nil)
    #expect(await appSettingsStore.load().reader.readingMode == .vertical)
    #expect(await readerCacheStore.totalDiskUsageBytes() > 0)
}

@Test func webDAVAutomaticSyncDownloadsNewerRemotePayload() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto.example.com"

    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
        localUpdatedAt: Date(timeIntervalSince1970: 1_000)
    ))
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))

    let remoteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=903&mobile=2"))
    let remoteFavorite = Favorite(title: "较新的远端收藏", url: remoteURL, mangaPageIndex: 9)
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        library: FavoriteLibrarySnapshot(favorites: [remoteFavorite], collections: [])
    )
    let encodedPayload = try JSONEncoder().encode(payload)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            encodedPayload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    try await service.synchronizeAutomatically()

    #expect(await favoriteStore.loadFavorites() == [remoteFavorite])
    let updatedSettings = await settingsStore.load()
    #expect(updatedSettings.lastRemoteUpdatedAt == payload.updatedAt)
    #expect(updatedSettings.localUpdatedAt == payload.updatedAt)
}

@Test func webDAVAutomaticSyncMergesRefreshedRemoteFavoritesWithoutOverwritingNewerReadingPosition() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto-domain-merge")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto-domain-merge.example.com"
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=906&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString
    let baseClock = Date(timeIntervalSince1970: 1_000)
    let remoteReadingClock = Date(timeIntervalSince1970: 3_000)
    let staleLocalFavorite = Favorite(title: "本地旧阅读", url: url, lastView: 1, type: .novel)
    let newerRemoteFavorite = Favorite(title: "远端旧标题", url: url, lastView: 8, lastChapter: "第八章", type: .novel)
    var localMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    localMetadata.readingPositionUpdatedAtByCanonicalURL[canonicalKey] = baseClock
    var remoteMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    remoteMetadata.readingPositionUpdatedAtByCanonicalURL[canonicalKey] = remoteReadingClock

    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: baseClock,
        localUpdatedAt: baseClock
    ))
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))
    try await favoriteStore.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [staleLocalFavorite],
        collections: [],
        syncMetadata: localMetadata
    ))

    _ = try await favoriteStore.mergeRemoteFavorites([
        Favorite(title: "刷新后的收藏标题", url: url, remoteFavoriteID: "remote-906")
    ])

    let remotePayload = WebDAVSyncPayload(
        updatedAt: remoteReadingClock,
        accountUID: "100",
        library: FavoriteLibrarySnapshot(
            favorites: [newerRemoteFavorite],
            collections: [],
            syncMetadata: remoteMetadata
        )
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)
    var uploadedPayload: WebDAVSyncPayload?
    var methods: [String] = []

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        methods.append(request.httpMethod ?? "")
        switch request.httpMethod {
        case "GET":
            return (
                encodedRemotePayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let body = try #require(request.webDAVBodyData())
            uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.synchronizeAutomatically()

    let mergedLocalFavorite = try #require(await favoriteStore.favorite(for: url))
    #expect(mergedLocalFavorite.title == "刷新后的收藏标题")
    #expect(mergedLocalFavorite.remoteFavoriteID == "remote-906")
    #expect(mergedLocalFavorite.lastView == 8)
    #expect(mergedLocalFavorite.lastChapter == "第八章")
    #expect(methods == ["GET", "MKCOL", "PUT"])
    let uploadedFavorite = try #require(uploadedPayload?.library.favorites.first)
    #expect(uploadedFavorite.title == "刷新后的收藏标题")
    #expect(uploadedFavorite.lastView == 8)
    #expect(uploadedPayload?.library.syncMetadata.readingPositionUpdatedAtByCanonicalURL[canonicalKey] == remoteReadingClock)
}

@Test func webDAVAutomaticSyncNoOpLocalMetadataDoesNotOverrideRemoteMetadata() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto-noop-metadata")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto-noop-metadata.example.com"
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=908&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString
    let baseClock = Date(timeIntervalSince1970: 1_000)
    let remoteMetadataClock = Date(timeIntervalSince1970: 3_000)
    let localFavorite = Favorite(
        title: "同一收藏",
        displayName: "本地旧名",
        url: url,
        isHidden: false,
        type: .unknown
    )
    let remoteFavorite = Favorite(
        title: "同一收藏",
        displayName: "远端新名",
        url: url,
        isHidden: true,
        type: .manga
    )
    var localMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    localMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey] = baseClock
    var remoteMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    remoteMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey] = remoteMetadataClock

    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: baseClock,
        localUpdatedAt: baseClock
    ))
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))
    try await favoriteStore.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [localFavorite],
        collections: [],
        syncMetadata: localMetadata
    ))

    _ = try await favoriteStore.setType(.unknown, for: localFavorite.id)
    _ = try await favoriteStore.setDisplayName("  本地旧名  ", for: localFavorite.id)

    let remotePayload = WebDAVSyncPayload(
        updatedAt: remoteMetadataClock,
        accountUID: "100",
        library: FavoriteLibrarySnapshot(
            favorites: [remoteFavorite],
            collections: [],
            syncMetadata: remoteMetadata
        )
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (
                encodedRemotePayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.synchronizeAutomatically()

    let mergedSnapshot = await favoriteStore.loadLibrarySnapshot()
    let mergedLocalFavorite = try #require(mergedSnapshot.favorites.first)
    #expect(mergedLocalFavorite.displayName == "远端新名")
    #expect(!mergedLocalFavorite.isHidden)
    #expect(mergedLocalFavorite.type == .manga)
    #expect(mergedSnapshot.syncMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey] == remoteMetadataClock)
}

@Test func webDAVAutomaticSyncKeepsLocalDeletionWhenRemotePayloadStillContainsFavorite() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto-local-delete")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto-local-delete.example.com"
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=907&mobile=2"))
    let baseClock = Date(timeIntervalSince1970: 1_000)
    let favorite = Favorite(title: "已删除收藏", url: url, remoteFavoriteID: "remote-907")
    let localMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    let remoteMetadata = FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)

    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: baseClock,
        localUpdatedAt: baseClock
    ))
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))
    try await favoriteStore.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        syncMetadata: localMetadata
    ))
    _ = try await favoriteStore.deleteFavorites(ids: [favorite.id])

    let localDeleteClock = try #require((await favoriteStore.loadLibrarySnapshot()).syncMetadata.remoteFavoritesUpdatedAt)
    let remotePayload = WebDAVSyncPayload(
        updatedAt: baseClock,
        accountUID: "100",
        library: FavoriteLibrarySnapshot(
            favorites: [favorite],
            collections: [],
            syncMetadata: remoteMetadata
        )
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)
    var uploadedPayload: WebDAVSyncPayload?
    var methods: [String] = []

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        methods.append(request.httpMethod ?? "")
        switch request.httpMethod {
        case "GET":
            return (
                encodedRemotePayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let body = try #require(request.webDAVBodyData())
            uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.synchronizeAutomatically()

    #expect(await favoriteStore.loadFavorites().isEmpty)
    #expect(methods == ["GET", "MKCOL", "PUT"])
    #expect(uploadedPayload?.library.favorites.isEmpty == true)
    #expect(uploadedPayload?.library.syncMetadata.remoteFavoritesUpdatedAt == localDeleteClock)
}

@Test func webDAVAutomaticSyncDiscardsArchivedFavoriteMetadata() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto-archive")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto-archive.example.com"
    let archivedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=941&mobile=2"))
    let archive = FavoriteMetadataArchiveEntry(
        canonicalThreadURL: ReaderCacheIdentity.canonicalThreadURL(from: archivedURL),
        displayName: "下载归档",
        mangaPageIndex: 4,
        lastView: 1,
        lastChapter: nil,
        authorID: nil,
        novelResumePoint: nil,
        isHidden: false,
        type: .manga,
        lastMangaURL: archivedURL,
        parentCollectionID: nil,
        manualOrder: 0,
        lastReadAt: nil
    )
    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
        localUpdatedAt: Date(timeIntervalSince1970: 1_000)
    ))
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))

    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "100",
        library: FavoriteLibrarySnapshot(favorites: [], collections: [], archivedMetadata: [archive])
    )
    let encodedPayload = try JSONEncoder().encode(payload)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (
                encodedPayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    try await service.synchronizeAutomatically()

    #expect((await favoriteStore.loadLibrarySnapshot()).archivedMetadata.isEmpty)
}

@Test func webDAVServiceUploadWritesCurrentAccountUID() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-upload-account")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "upload-account.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))

    var uploadedPayload: WebDAVSyncPayload?
    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let body = try #require(request.webDAVBodyData())
            uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.upload(using: settings)

    #expect(uploadedPayload?.accountUID == "123")
}

@Test func webDAVServiceUploadIncludesSyncedAppSettings() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-upload-app-settings")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let appSettingsStore = SettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "settings")
    let host = "upload-app-settings.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let appSettings = AppSettings(
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        favoriteAppearance: FavoriteAppearanceSettings(collection: .purple, novel: .red, manga: .green, other: .gray),
        favoriteBackground: FavoriteBackgroundSettings(
            isEnabled: true,
            imageID: "local-background",
            scale: 2,
            offsetX: 0.4,
            offsetY: -0.2,
            blurRadius: 12
        ),
        homePage: .favorites,
        usesDataSaverMode: true
    )
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))
    try await appSettingsStore.save(appSettings)

    var uploadedPayload: WebDAVSyncPayload?
    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let body = try #require(request.webDAVBodyData())
            uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        appSettingsStore: appSettingsStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.upload(using: settings)

    #expect(uploadedPayload?.appSettings == WebDAVSyncedAppSettings(settings: appSettings))
    let syncedSettingsData = try JSONEncoder().encode(try #require(uploadedPayload?.appSettings))
    let syncedSettingsObject = try #require(JSONSerialization.jsonObject(with: syncedSettingsData) as? [String: Any])
    #expect(syncedSettingsObject["favoriteBackground"] == nil)
}

@Test func webDAVServiceDownloadAppliesSyncedAppSettingsOnly() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-download-app-settings")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let appSettingsStore = SettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "settings")
    let host = "download-app-settings.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let localSettings = AppSettings(
        reader: ReaderAppearanceSettings(readingMode: .vertical),
        webBrowser: WebBrowserSettings(showsNavigationBar: true),
        favoriteAppearance: FavoriteAppearanceSettings(collection: .orange, novel: .pink, manga: .blue, other: .cyan),
        favoriteBackground: FavoriteBackgroundSettings(
            isEnabled: true,
            imageID: "local-background",
            scale: 1.8,
            offsetX: 0.25,
            offsetY: -0.5,
            blurRadius: 9
        ),
        homePage: .forum,
        usesDataSaverMode: true,
        collapsesFavoriteSections: true
    )
    let remoteSyncedSettings = WebDAVSyncedAppSettings(
        homePage: .favorites,
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        favoriteAppearance: FavoriteAppearanceSettings(collection: .purple, novel: .red, manga: .green, other: .gray)
    )
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "123",
        library: FavoriteLibrarySnapshot(favorites: [], collections: []),
        appSettings: remoteSyncedSettings
    )
    let encodedPayload = try JSONEncoder().encode(payload)

    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))
    try await appSettingsStore.save(localSettings)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            encodedPayload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        appSettingsStore: appSettingsStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.download(using: settings)

    let loadedSettings = await appSettingsStore.load()
    #expect(loadedSettings.homePage == .favorites)
    #expect(loadedSettings.webBrowser.showsNavigationBar == false)
    #expect(loadedSettings.favoriteAppearance == remoteSyncedSettings.favoriteAppearance)
    #expect(loadedSettings.favoriteBackground == localSettings.favoriteBackground)
    #expect(loadedSettings.reader.readingMode == .vertical)
    #expect(loadedSettings.usesDataSaverMode == true)
    #expect(loadedSettings.collapsesFavoriteSections == true)
}

@Test func webDAVServiceUploadDiscardsArchivedFavoriteMetadata() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-upload-archive")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "upload-archive.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let archivedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=940&mobile=2"))
    let archive = FavoriteMetadataArchiveEntry(
        canonicalThreadURL: ReaderCacheIdentity.canonicalThreadURL(from: archivedURL),
        displayName: "同步归档",
        mangaPageIndex: 9,
        lastView: 2,
        lastChapter: "归档章节",
        authorID: "77",
        novelResumePoint: nil,
        isHidden: true,
        type: .novel,
        lastMangaURL: nil,
        parentCollectionID: "collection-a",
        manualOrder: 3,
        lastReadAt: Date(timeIntervalSince1970: 1_900_000_000)
    )
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))
    try await favoriteStore.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [],
        collections: [],
        archivedMetadata: [archive]
    ))

    var uploadedPayload: WebDAVSyncPayload?
    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let body = try #require(request.webDAVBodyData())
            uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: body)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.upload(using: settings)

    #expect(uploadedPayload?.library.archivedMetadata == [])
}

@Test func webDAVServiceUploadDoesNotSerializeMangaOfflineCacheState() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-upload-offline-boundary")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let rootDirectory = makeWebDAVTemporaryDirectory(prefix: "webdav-upload-offline-boundary")
    let offlineStore = FileMangaOfflineCacheStore(baseDirectory: rootDirectory.appendingPathComponent("offline", isDirectory: true))
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(
        defaults: try makeWebDAVDefaults(suiteName: suiteName),
        key: "favorites",
        mangaOfflineCacheStore: offlineStore
    )
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "upload-offline-boundary.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=960&mobile=2"))
    let favorite = Favorite(id: "favorite-offline", title: "离线漫画", url: favoriteURL, type: .manga)
    let imageURL = try #require(URL(string: "https://img.example.com/webdav-offline-boundary.jpg"))

    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))
    try await favoriteStore.saveFavorites([favorite])
    try await offlineStore.saveOfflineImageData(Data([9]), for: imageURL)
    try await offlineStore.saveMembership(MangaOfflineCacheMembership(
        ownerName: favorite.title,
        tid: "960",
        chapterTitle: "第960话",
        chapterURL: favoriteURL,
        imageURLs: [imageURL]
    ))
    _ = try await offlineStore.enqueueOfflineCacheWork(MangaOfflineCacheWorkRequest(
        ownerName: favorite.title,
        tid: "961",
        chapterTitle: "第961话",
        chapterURL: favoriteURL,
        targetImageURLs: [imageURL]
    ))

    var uploadedPayloadData: Data?
    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            uploadedPayloadData = request.webDAVBodyData()
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.upload(using: settings)

    let payloadData = try #require(uploadedPayloadData)
    let payloadObject = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
    let libraryObject = try #require(payloadObject["library"] as? [String: Any])
    #expect(libraryObject["mangaOfflineCache"] == nil)
    #expect(libraryObject["offlineCache"] == nil)
    #expect(libraryObject["queueWorks"] == nil)
    #expect((try JSONDecoder().decode(WebDAVSyncPayload.self, from: payloadData)).library.favorites == [favorite])
    #expect(await offlineStore.membership(ownerName: favorite.title, tid: "960") != nil)
    #expect(await offlineStore.offlineCacheWork(ownerName: favorite.title, tid: "961") != nil)
}

@Test func webDAVServiceDownloadFavoriteRemovalPreservesMangaOfflineCache() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-download-offline-cleanup")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let rootDirectory = makeWebDAVTemporaryDirectory(prefix: "webdav-download-offline-cleanup")
    let offlineStore = FileMangaOfflineCacheStore(baseDirectory: rootDirectory.appendingPathComponent("offline", isDirectory: true))
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(
        defaults: try makeWebDAVDefaults(suiteName: suiteName),
        key: "favorites",
        mangaOfflineCacheStore: offlineStore
    )
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "download-offline-cleanup.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=962&mobile=2"))
    let favorite = Favorite(id: "favorite-webdav-removed", title: "被同步移除", url: favoriteURL, type: .manga)
    let imageURL = try #require(URL(string: "https://img.example.com/webdav-download-cleanup.jpg"))
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "123",
        library: FavoriteLibrarySnapshot(favorites: [], collections: [])
    )
    let encodedPayload = try JSONEncoder().encode(payload)

    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "123"))
    try await favoriteStore.saveFavorites([favorite])
    try await offlineStore.saveOfflineImageData(Data([8]), for: imageURL)
    try await offlineStore.saveMembership(MangaOfflineCacheMembership(
        ownerName: favorite.title,
        tid: "962",
        chapterTitle: "第962话",
        chapterURL: favoriteURL,
        imageURLs: [imageURL]
    ))
    _ = try await offlineStore.enqueueOfflineCacheWork(MangaOfflineCacheWorkRequest(
        ownerName: favorite.title,
        tid: "963",
        chapterTitle: "第963话",
        chapterURL: favoriteURL,
        targetImageURLs: [imageURL]
    ))

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            encodedPayload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.download(using: settings)

    #expect(await favoriteStore.loadFavorites() == [])
    #expect(await offlineStore.membership(ownerName: favorite.title, tid: "962") != nil)
    #expect(await offlineStore.offlineCacheWork(ownerName: favorite.title, tid: "963") != nil)
    #expect(await offlineStore.offlineImageData(for: imageURL) == Data([8]))
}

@Test func webDAVSyncRoundTripsFavoriteTagsAndAssociations() async throws {
    let uploadSuiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-tag-upload")
    let downloadSuiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-tag-download")
    UserDefaults(suiteName: uploadSuiteName)?.removePersistentDomain(forName: uploadSuiteName)
    UserDefaults(suiteName: downloadSuiteName)?.removePersistentDomain(forName: downloadSuiteName)
    let uploadSettingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: uploadSuiteName), key: "webdav")
    let downloadSettingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: downloadSuiteName), key: "webdav")
    let uploadFavoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: uploadSuiteName), key: "favorites")
    let downloadFavoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: downloadSuiteName), key: "favorites")
    let uploadSessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: uploadSuiteName), key: "session")
    let downloadSessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: downloadSuiteName), key: "session")
    let host = "tag-roundtrip.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let updatedAt = Date(timeIntervalSince1970: 1_800_000_500)
    let loveTag = FavoriteTag(id: "tag-love", name: "百合", color: .pink, manualOrder: 0, createdAt: createdAt, updatedAt: updatedAt)
    let shortTag = FavoriteTag(id: "tag-short", name: "短篇", color: .blue, manualOrder: 1, createdAt: createdAt.addingTimeInterval(10), updatedAt: updatedAt.addingTimeInterval(10))
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=950&mobile=2"))
    let favorite = Favorite(
        title: "带标签收藏",
        url: favoriteURL,
        remoteFavoriteID: "remote-950",
        mangaPageIndex: 5,
        tagIDs: [shortTag.id, loveTag.id]
    )
    let expectedLibrary = FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        tags: [loveTag, shortTag]
    )
    try await uploadSessionStore.save(SessionState(cookie: "sid=upload", isLoggedIn: true, accountUID: "123"))
    try await downloadSessionStore.save(SessionState(cookie: "sid=download", isLoggedIn: true, accountUID: "123"))
    try await uploadFavoriteStore.saveLibrarySnapshot(expectedLibrary)

    var uploadedPayloadData: Data?
    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            guard let body = request.webDAVBodyData() else {
                throw WebDAVTestError.missingHandler
            }
            uploadedPayloadData = body
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let uploadService = WebDAVSyncService(
        settingsStore: uploadSettingsStore,
        favoriteStore: uploadFavoriteStore,
        sessionStore: uploadSessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )
    _ = try await uploadService.upload(using: settings)

    let payloadData = try #require(uploadedPayloadData)
    let uploadedPayload = try JSONDecoder().decode(WebDAVSyncPayload.self, from: payloadData)
    #expect(uploadedPayload.version == WebDAVSyncPayload.currentVersion)
    #expect(!uploadedPayload.library.syncMetadata.isEmpty)
    #expect(uploadedPayload.library.withoutSyncMetadata == expectedLibrary)

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            payloadData,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }

    let downloadService = WebDAVSyncService(
        settingsStore: downloadSettingsStore,
        favoriteStore: downloadFavoriteStore,
        sessionStore: downloadSessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )
    _ = try await downloadService.download(using: settings)

    #expect((await downloadFavoriteStore.loadLibrarySnapshot()).withoutSyncMetadata == expectedLibrary)
}

@Test func webDAVDownloadSanitizesDanglingTagReferencesFromLegacyPayload() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-legacy-tags")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "legacy-tags.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    let payloadJSON = """
    {
      "version": 1,
      "updatedAt": 2000,
      "accountUID": "123",
      "library": {
        "favorites": [
          {
            "id": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=952&mobile=2",
            "title": "旧负载收藏",
            "url": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=952&mobile=2",
            "tagIDs": ["missing-tag"]
          }
        ],
        "collections": [],
        "archivedMetadata": [
          {
            "canonicalThreadURL": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=953&mobile=2",
            "displayName": "旧负载归档",
            "lastPage": 0,
            "lastView": 1,
            "isHidden": false,
            "type": 1,
            "manualOrder": 0,
            "tagIDs": ["missing-tag"]
          }
        ]
      }
    }
    """
    let payloadData = Data(payloadJSON.utf8)
    try await sessionStore.save(SessionState(cookie: "sid=download", isLoggedIn: true, accountUID: "123"))

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        #expect(request.httpMethod == "GET")
        return (
            payloadData,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    _ = try await service.download(using: settings)

    let loadedLibrary = await favoriteStore.loadLibrarySnapshot()
    #expect(loadedLibrary.tags.isEmpty)
    #expect(loadedLibrary.favorites.first?.tagIDs == [])
    #expect(loadedLibrary.archivedMetadata.isEmpty)
    #expect(!loadedLibrary.syncMetadata.isEmpty)
}

@Test func webDAVManualSyncRequiresConfirmationForAccountMismatch() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-mismatch")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "mismatch.example.com"
    let settings = WebDAVSyncSettings(baseURLString: "https://\(host)", username: "admin", password: "secret")
    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "local-uid"))

    let remoteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=904&mobile=2"))
    let remoteFavorite = Favorite(title: "远端", url: remoteURL)
    let remotePayload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 3_000),
        accountUID: "remote-uid",
        library: FavoriteLibrarySnapshot(favorites: [remoteFavorite], collections: [])
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)
    var putCount = 0

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        switch request.httpMethod {
        case "GET":
            return (
                encodedRemotePayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            putCount += 1
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    await #expect(throws: WebDAVSyncError.accountMismatch(localUID: "local-uid", remoteUID: "remote-uid")) {
        _ = try await service.download(using: settings)
    }
    #expect(await favoriteStore.loadFavorites().isEmpty)

    await #expect(throws: WebDAVSyncError.accountMismatch(localUID: "local-uid", remoteUID: "remote-uid")) {
        _ = try await service.download(using: settings, allowingAccountMismatch: true)
    }
    #expect(await favoriteStore.loadFavorites().isEmpty)

    await #expect(throws: WebDAVSyncError.accountMismatch(localUID: "local-uid", remoteUID: "remote-uid")) {
        _ = try await service.upload(using: settings)
    }
    #expect(putCount == 0)

    _ = try await service.upload(using: settings, allowingAccountMismatch: true)
    #expect(putCount == 1)
}

@Test func webDAVAutomaticSyncSkipsWhenLoggedOutOrAccountMismatches() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-auto-skip")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let host = "auto-skip.example.com"
    try await settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
        localUpdatedAt: Date(timeIntervalSince1970: 1_000)
    ))

    let remoteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=905&mobile=2"))
    let remoteFavorite = Favorite(title: "不应下载", url: remoteURL)
    let remotePayload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 3_000),
        accountUID: "remote-uid",
        library: FavoriteLibrarySnapshot(favorites: [remoteFavorite], collections: [])
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)
    var requestCount = 0

    WebDAVTestURLProtocol.setHandler(for: host) { request in
        requestCount += 1
        #expect(request.httpMethod == "GET")
        return (
            encodedRemotePayload,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        )
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: host) }

    let service = WebDAVSyncService(
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        sessionStore: sessionStore,
        client: WebDAVClient(session: makeWebDAVTestSession())
    )

    try await sessionStore.save(SessionState())
    try await service.synchronizeAutomatically()
    #expect(requestCount == 0)
    #expect((await settingsStore.load()).isAutoSyncEnabled)

    try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "local-uid"))
    try await service.synchronizeAutomatically()
    #expect(requestCount == 1)
    #expect(await favoriteStore.loadFavorites().isEmpty)
    #expect((await settingsStore.load()).lastRemoteUpdatedAt == Date(timeIntervalSince1970: 1_000))
}

private func makeWebDAVTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WebDAVTestURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeWebDAVDefaults(suiteName: String) throws -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw WebDAVTestError.missingHandler
    }
    return defaults
}

private func makeWebDAVDefaultsSuiteName(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString)"
}

private func makeWebDAVTemporaryDirectory(prefix: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private extension URLRequest {
    func webDAVBodyData() -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else { return nil }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let readCount = httpBodyStream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }
        return data
    }
}

private extension FavoriteLibrarySnapshot {
    var withoutSyncMetadata: FavoriteLibrarySnapshot {
        var snapshot = self
        snapshot.syncMetadata = FavoriteLibrarySyncMetadata()
        return snapshot
    }
}
