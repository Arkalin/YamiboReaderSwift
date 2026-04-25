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

@Test func accountUIDResolverExtractsUIDFromFinalURLOrHTML() throws {
    #expect(AccountUIDResolver.extractAccountUID(
        finalURL: URL(string: "https://bbs.yamibo.com/home.php?mod=space&uid=456&do=profile")!,
        html: ""
    ) == "456")
    #expect(AccountUIDResolver.extractAccountUID(
        finalURL: nil,
        html: #"<a href="space-uid-789.html">用户</a>"#
    ) == "789")
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

@Test func webDAVSyncDownloadRestoresLibraryWithoutTouchingSessionSignInSettingsOrCaches() async throws {
    let suiteName = makeWebDAVDefaultsSuiteName(prefix: "webdav-download")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let rootDirectory = makeWebDAVTemporaryDirectory(prefix: "webdav-download-root")
    let settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
    let favoriteStore = FavoriteStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "favorites")
    let sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
    let autoSignInStore = AutoSignInStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    let appSettingsStore = SettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "settings")
    let readerCacheStore = ReaderCacheStore(baseDirectory: rootDirectory.appendingPathComponent("reader-cache", isDirectory: true))
    let mangaImageCacheStore = MangaImageCacheStore(baseDirectory: rootDirectory.appendingPathComponent("manga-cache", isDirectory: true))
    let mangaDirectoryStore = MangaDirectoryStore(
        fileManager: .default,
        baseDirectory: rootDirectory.appendingPathComponent("directory-cache", isDirectory: true)
    )

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
    await autoSignInStore.markSignedIn(session: localSession)

    let localURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2"))
    try await readerCacheStore.save(
        ReaderPageDocument(threadURL: localURL, view: 1, maxView: 1, segments: [.text("local cache", chapterTitle: nil)])
    )
    try await mangaImageCacheStore.save(Data(repeating: 3, count: 128), for: try #require(URL(string: "https://static.yamibo.com/image.jpg")))
    _ = try await mangaDirectoryStore.initializeDirectory(currentURL: localURL, rawTitle: "本地目录 第1话", html: "")

    let remoteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&mobile=2"))
    let collection = FavoriteCollection(id: "collection-a", name: "远端合集", manualOrder: 0, isHidden: true)
    let favorite = Favorite(
        title: "远端收藏",
        url: remoteURL,
        lastPage: 7,
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
    #expect(loadedLibrary.favorites == [favorite])
    #expect(loadedLibrary.collections == [collection])
    #expect(await sessionStore.load() == localSession)
    #expect(await autoSignInStore.lastSignedDate(session: localSession) != nil)
    #expect(await appSettingsStore.load().reader.readingMode == .vertical)
    #expect(await readerCacheStore.totalDiskUsageBytes() > 0)
    #expect(await mangaImageCacheStore.totalDiskUsageBytes() == 128)
    #expect(await mangaDirectoryStore.allDirectories().isEmpty == false)
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
    let remoteFavorite = Favorite(title: "较新的远端收藏", url: remoteURL, lastPage: 9)
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

    _ = try await service.download(using: settings, allowingAccountMismatch: true)
    #expect(await favoriteStore.loadFavorites() == [remoteFavorite])

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
