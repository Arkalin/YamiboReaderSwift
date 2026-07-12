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

@Test func webDAVSyncRequiresStoredAccountUID() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-requires-account-uid")
    try await fixture.signInWithoutAccountUID()
    let service = fixture.makeService()

    await #expect(throws: YamiboError.accountUIDUnavailable) {
        _ = try await service.upload(using: fixture.settings)
    }
    await #expect(throws: YamiboError.accountUIDUnavailable) {
        _ = try await service.download(using: fixture.settings)
    }
}

@Test func webDAVServiceUploadWritesLocalFirstFavoriteLibraryAndReadingProgressPayloads() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-local-first-upload")
    try await fixture.signIn(accountUID: "100")

    let threadID = "940"
    var document = FavoriteLibraryDocument()
    let target = FavoriteItemTarget(kind: .novelThread, threadID: threadID)
    try document.upsertItem(
        FavoriteItem(
            target: target,
            title: "本地优先收藏",
            locations: [.category(document.defaultCategory.id)]
        )
    )
    try await fixture.localFavoriteLibraryStore.save(document)
    _ = try await fixture.readingProgressStore.saveNovel(
        NovelReadingPosition(threadID: threadID, view: 4, chapterTitle: "第四章")
    )

    var putPaths: [String] = []
    WebDAVTestURLProtocol.setHandler(for: fixture.host) { request in
        if request.httpMethod == "GET" {
            return (
                Data(),
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            )
        }
        guard request.httpMethod == "PUT" || request.httpMethod == "MKCOL" else {
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        if request.httpMethod == "PUT" {
            let path = try #require(request.url?.path)
            putPaths.append(path)
            let body = try #require(request.webDAVBodyData())
            if path.hasSuffix("yamibo-favorite-library-v1.json") {
                let payload = try JSONDecoder().decode(FavoriteLibraryWebDAVPayload.self, from: body)
                #expect(payload.accountUID == "100")
                #expect(payload.library.items.map(\.id) == [target.id])
            } else if path.hasSuffix("yamibo-reading-progress-v1.json") {
                let payload = try JSONDecoder().decode(ReadingProgressWebDAVPayload.self, from: body)
                #expect(payload.records.map(\.id) == [target.id])
            }
        }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: fixture.host) }

    _ = try await fixture.makeService().upload(using: fixture.settings, allowingAccountMismatch: true)

    #expect(!putPaths.contains { $0.hasSuffix("yamibo-sync-v1.json") })
    #expect(putPaths.contains { $0.hasSuffix("yamibo-favorite-library-v1.json") })
    #expect(putPaths.contains { $0.hasSuffix("yamibo-reading-progress-v1.json") })
}

@Test func webDAVServiceLocalFirstUploadWritesAppSettingsPayloadWithoutLegacyPayload() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-local-first-app-settings-upload")
    try await fixture.signIn(accountUID: "123")
    let appSettings = AppSettings(
        favorites: FavoriteLibrarySettings(
            appearance: FavoriteAppearanceSettings(collection: .purple, novel: .red, manga: .green, other: .gray)
        ),
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        system: SystemSettings(homePage: .favorites)
    )
    try await fixture.appSettingsStore.save(appSettings)

    var putPaths: [String] = []
    var uploadedAppSettings: AppSettingsWebDAVPayload?
    WebDAVTestURLProtocol.setHandler(for: fixture.host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            let path = try #require(request.url?.path)
            putPaths.append(path)
            if path.hasSuffix("yamibo-app-settings-v1.json") {
                uploadedAppSettings = try JSONDecoder().decode(AppSettingsWebDAVPayload.self, from: try #require(request.webDAVBodyData()))
            }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: fixture.host) }

    _ = try await fixture.makeService().upload(using: fixture.settings)

    #expect(!putPaths.contains { $0.hasSuffix("yamibo-sync-v1.json") })
    #expect(putPaths.contains { $0.hasSuffix("yamibo-favorite-library-v1.json") })
    #expect(putPaths.contains { $0.hasSuffix("yamibo-app-settings-v1.json") })
    #expect(uploadedAppSettings?.accountUID == "123")
    #expect(uploadedAppSettings?.appSettings == WebDAVSyncedAppSettings(settings: appSettings))
}

@Test func webDAVServiceLocalFirstDownloadAppliesAppSettingsPayloadWithoutLegacyPayload() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-local-first-app-settings-download")
    try await fixture.signIn(accountUID: "123")
    let localSettings = AppSettings(
        webBrowser: WebBrowserSettings(showsNavigationBar: true),
        system: SystemSettings(homePage: .forum)
    )
    let remoteSettings = WebDAVSyncedAppSettings(
        homePage: .favorites,
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        favoriteAppearance: FavoriteAppearanceSettings(collection: .purple, novel: .red, manga: .green, other: .gray)
    )
    let remotePayload = AppSettingsWebDAVPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "123",
        appSettings: remoteSettings
    )
    try await fixture.appSettingsStore.save(localSettings)

    var getPaths: [String] = []
    WebDAVTestURLProtocol.setHandler(for: fixture.host) { request in
        #expect(request.httpMethod == "GET")
        let path = try #require(request.url?.path)
        getPaths.append(path)
        if path.hasSuffix("yamibo-app-settings-v1.json") {
            return (
                try JSONEncoder().encode(remotePayload),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: fixture.host) }

    _ = try await fixture.makeService().download(using: fixture.settings)

    #expect(!getPaths.contains { $0.hasSuffix("yamibo-sync-v1.json") })
    let loadedSettings = await fixture.appSettingsStore.load()
    #expect(loadedSettings.system.homePage == .favorites)
    #expect(loadedSettings.webBrowser.showsNavigationBar == false)
    #expect(loadedSettings.favorites.appearance == remoteSettings.favoriteAppearance)
}

@Test func webDAVAutomaticLocalFirstSyncUploadsWithoutLegacyPayload() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-local-first-auto-no-legacy")
    let localClock = Date(timeIntervalSince1970: 3_000)
    try await fixture.settingsStore.save(WebDAVSyncSettings(
        baseURLString: "https://\(fixture.host)",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
        localUpdatedAt: localClock
    ))
    try await fixture.signIn(accountUID: "123")

    var document = FavoriteLibraryDocument()
    try document.upsertItem(
        FavoriteItem(
            target: FavoriteItemTarget(kind: .normalThread, threadID: "965"),
            title: "自动同步收藏",
            locations: [.category(document.defaultCategory.id)]
        )
    )
    try await fixture.localFavoriteLibraryStore.save(document)

    var putPaths: [String] = []
    WebDAVTestURLProtocol.setHandler(for: fixture.host) { request in
        switch request.httpMethod {
        case "GET":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            putPaths.append(try #require(request.url?.path))
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: fixture.host) }

    let result = try await fixture.makeService().synchronizeAutomatically()

    #expect(result == .uploaded)
    #expect(!putPaths.contains { $0.hasSuffix("yamibo-sync-v1.json") })
    #expect(putPaths.contains { $0.hasSuffix("yamibo-favorite-library-v1.json") })
    let updatedSettings = await fixture.settingsStore.load()
    #expect(updatedSettings.lastSyncedAt != nil)
    #expect(updatedSettings.lastRemoteUpdatedAt != nil)
}

@Test func webDAVLocalFirstManualSyncRequiresConfirmationForAccountMismatch() async throws {
    let fixture = try WebDAVSyncFixture(prefix: "webdav-local-first-mismatch")
    try await fixture.signIn(accountUID: "local-uid")
    let remotePayload = FavoriteLibraryWebDAVPayload(
        updatedAt: Date(timeIntervalSince1970: 4_000),
        accountUID: "remote-uid",
        library: FavoriteLibraryDocument()
    )
    let encodedRemotePayload = try JSONEncoder().encode(remotePayload)
    var putCount = 0

    WebDAVTestURLProtocol.setHandler(for: fixture.host) { request in
        switch request.httpMethod {
        case "GET":
            if request.url?.path.hasSuffix("yamibo-favorite-library-v1.json") == true {
                return (
                    encodedRemotePayload,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        case "MKCOL":
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        case "PUT":
            putCount += 1
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        default:
            Issue.record("Unexpected method \(request.httpMethod ?? "nil")")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
    }
    defer { WebDAVTestURLProtocol.removeHandler(for: fixture.host) }

    let service = fixture.makeService()
    await #expect(throws: WebDAVSyncError.accountMismatch(localUID: "local-uid", remoteUID: "remote-uid")) {
        _ = try await service.upload(using: fixture.settings)
    }
    #expect(putCount == 0)

    _ = try await service.upload(using: fixture.settings, allowingAccountMismatch: true)
    #expect(putCount == 3)
}

private struct WebDAVSyncFixture {
    let suiteName: String
    let host: String
    let settingsStore: WebDAVSyncSettingsStore
    let localFavoriteLibraryStore: FavoriteLibraryStore
    let readingProgressStore: ReadingProgressStore
    let sessionStore: SessionStore
    let appSettingsStore: SettingsStore
    let settings: WebDAVSyncSettings

    init(prefix: String) throws {
        suiteName = "\(prefix)-\(UUID().uuidString)"
        host = "\(prefix).example.com"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        settingsStore = WebDAVSyncSettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "webdav")
        localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try makeWebDAVDefaults(suiteName: suiteName),
            key: "local-favorites"
        )
        readingProgressStore = ReadingProgressStore(
            defaults: try makeWebDAVDefaults(suiteName: suiteName),
            key: "reading-progress"
        )
        sessionStore = SessionStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "session")
        appSettingsStore = SettingsStore(defaults: try makeWebDAVDefaults(suiteName: suiteName), key: "settings")
        settings = WebDAVSyncSettings(
            baseURLString: "https://\(host)",
            username: "admin",
            password: "secret"
        )
    }

    func signIn(accountUID: String) async throws {
        try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: accountUID))
    }

    func signInWithoutAccountUID() async throws {
        try await sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true))
    }

    func makeService() -> WebDAVSyncService {
        WebDAVSyncService(
            settingsStore: settingsStore,
            sessionStore: sessionStore,
            participants: [
                FavoriteLibraryWebDAVParticipant(store: localFavoriteLibraryStore),
                ReadingProgressWebDAVParticipant(store: readingProgressStore),
                AppSettingsWebDAVParticipant(store: appSettingsStore),
            ],
            client: WebDAVClient(session: makeWebDAVTestSession())
        )
    }
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
