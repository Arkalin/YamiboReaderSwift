import Foundation

public struct WebDAVSyncSettings: Codable, Equatable, Sendable {
    public var baseURLString: String
    public var username: String
    public var password: String
    public var isAutoSyncEnabled: Bool
    public var lastSyncedAt: Date?
    public var lastRemoteUpdatedAt: Date?
    public var localUpdatedAt: Date?
    public var appSettingsUpdatedAt: Date?
    public var lastSyncedAppSettings: WebDAVSyncedAppSettings?

    public init(
        baseURLString: String = "",
        username: String = "",
        password: String = "",
        isAutoSyncEnabled: Bool = false,
        lastSyncedAt: Date? = nil,
        lastRemoteUpdatedAt: Date? = nil,
        localUpdatedAt: Date? = nil,
        appSettingsUpdatedAt: Date? = nil,
        lastSyncedAppSettings: WebDAVSyncedAppSettings? = nil
    ) {
        self.baseURLString = baseURLString
        self.username = username
        self.password = password
        self.isAutoSyncEnabled = isAutoSyncEnabled
        self.lastSyncedAt = lastSyncedAt
        self.lastRemoteUpdatedAt = lastRemoteUpdatedAt
        self.localUpdatedAt = localUpdatedAt
        self.appSettingsUpdatedAt = appSettingsUpdatedAt
        self.lastSyncedAppSettings = lastSyncedAppSettings
    }

    public var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isConfigured: Bool {
        URL(string: trimmedBaseURLString) != nil && !trimmedUsername.isEmpty
    }
}

public actor WebDAVSyncSettingsStore {
    public static let didChangeNotification = Notification.Name("yamibo.webDAVSyncSettingsStore.didChange")
    public static let changeIDUserInfoKey = "changeID"
    public static let defaultKey = "yamibo.webdav.sync.settings"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> WebDAVSyncSettings {
        guard let data = defaults.data(forKey: key) else { return WebDAVSyncSettings() }
        return (try? decoder.decode(WebDAVSyncSettings.self, from: data)) ?? WebDAVSyncSettings()
    }

    public func save(_ settings: WebDAVSyncSettings) async throws {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func reset() async throws {
        try await save(WebDAVSyncSettings())
    }

    public func markLocalDataChanged(at date: Date = .now) async throws {
        var settings = await load()
        settings.localUpdatedAt = date
        try await save(settings)
    }

    public func markSynchronized(remoteUpdatedAt: Date, at date: Date = .now) async throws {
        var settings = await load()
        settings.lastSyncedAt = date
        settings.lastRemoteUpdatedAt = remoteUpdatedAt
        settings.localUpdatedAt = remoteUpdatedAt
        settings.appSettingsUpdatedAt = nil
        try await save(settings)
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}

public struct WebDAVSyncedAppSettings: Codable, Equatable, Sendable {
    public var homePage: AppHomePage
    public var webBrowser: WebBrowserSettings
    public var favoriteAppearance: FavoriteAppearanceSettings

    public init(
        homePage: AppHomePage,
        webBrowser: WebBrowserSettings,
        favoriteAppearance: FavoriteAppearanceSettings
    ) {
        self.homePage = homePage
        self.webBrowser = webBrowser
        self.favoriteAppearance = favoriteAppearance
    }

    public init(settings: AppSettings) {
        self.init(
            homePage: settings.system.homePage,
            webBrowser: settings.webBrowser,
            favoriteAppearance: settings.favorites.appearance
        )
    }

    public func applying(to settings: AppSettings) -> AppSettings {
        var updated = settings
        updated.system.homePage = homePage
        updated.webBrowser = webBrowser
        updated.favorites.appearance = favoriteAppearance
        return updated
    }
}

public enum WebDAVSyncDirection: String, Codable, CaseIterable, Sendable {
    case upload
    case download
}

public enum WebDAVAutomaticSyncResult: Equatable, Sendable {
    case skipped
    case downloaded
    case uploaded
}

public enum WebDAVSyncError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case notFound
    case notAuthenticated
    case unsupportedPayloadVersion(Int)
    case invalidResponse(Int?)
    case emptyPayload
    case accountMismatch(localUID: String, remoteUID: String)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            L10n.string("webdav.error.invalid_configuration")
        case .notFound:
            L10n.string("webdav.error.not_found")
        case .notAuthenticated:
            L10n.string("webdav.error.not_authenticated")
        case let .unsupportedPayloadVersion(version):
            L10n.string("webdav.error.unsupported_version", version)
        case let .invalidResponse(statusCode):
            if let statusCode {
                L10n.string("webdav.error.invalid_response_with_status", statusCode)
            } else {
                L10n.string("webdav.error.invalid_response")
            }
        case .emptyPayload:
            L10n.string("webdav.error.empty_payload")
        case .accountMismatch:
            L10n.string("webdav.error.account_mismatch")
        case let .underlying(message):
            message
        }
    }
}

public struct WebDAVClient: Sendable {
    private static let favoriteLibraryPayloadFileName = "yamibo-favorite-library-v1.json"
    private static let readingProgressPayloadFileName = "yamibo-reading-progress-v1.json"
    private static let appSettingsPayloadFileName = "yamibo-app-settings-v1.json"

    let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession = YamiboNetworkConfiguration.makeSession()) {
        self.session = session
    }

    public func fetchFavoriteLibraryPayload(settings: WebDAVSyncSettings) async throws -> FavoriteLibraryWebDAVPayload {
        try await fetchPayload(
            settings: settings,
            fileName: Self.favoriteLibraryPayloadFileName,
            as: FavoriteLibraryWebDAVPayload.self
        )
    }

    public func fetchReadingProgressPayload(settings: WebDAVSyncSettings) async throws -> ReadingProgressWebDAVPayload {
        try await fetchPayload(
            settings: settings,
            fileName: Self.readingProgressPayloadFileName,
            as: ReadingProgressWebDAVPayload.self
        )
    }

    public func fetchAppSettingsPayload(settings: WebDAVSyncSettings) async throws -> AppSettingsWebDAVPayload {
        try await fetchPayload(
            settings: settings,
            fileName: Self.appSettingsPayloadFileName,
            as: AppSettingsWebDAVPayload.self
        )
    }

    public func uploadFavoriteLibraryPayload(
        _ payload: FavoriteLibraryWebDAVPayload,
        settings: WebDAVSyncSettings
    ) async throws {
        try await uploadPayload(payload, settings: settings, fileName: Self.favoriteLibraryPayloadFileName)
    }

    public func uploadReadingProgressPayload(
        _ payload: ReadingProgressWebDAVPayload,
        settings: WebDAVSyncSettings
    ) async throws {
        try await uploadPayload(payload, settings: settings, fileName: Self.readingProgressPayloadFileName)
    }

    public func uploadAppSettingsPayload(
        _ payload: AppSettingsWebDAVPayload,
        settings: WebDAVSyncSettings
    ) async throws {
        try await uploadPayload(payload, settings: settings, fileName: Self.appSettingsPayloadFileName)
    }

    private func fetchPayload<Payload: Decodable>(
        settings: WebDAVSyncSettings,
        fileName: String,
        as _: Payload.Type
    ) async throws -> Payload {
        let config = try configuration(from: settings, fileName: fileName)
        var request = YamiboNetworkConfiguration.makeRequest(url: config.fileURL)
        request.httpMethod = "GET"
        applyHeaders(to: &request, configuration: config)

        let (data, response) = try await session.data(for: request)
        let statusCode = try statusCode(from: response)
        guard statusCode != 404 else { throw WebDAVSyncError.notFound }
        guard statusCode != 401 && statusCode != 403 else { throw WebDAVSyncError.notAuthenticated }
        guard 200 ..< 300 ~= statusCode else { throw WebDAVSyncError.invalidResponse(statusCode) }
        guard !data.isEmpty else { throw WebDAVSyncError.emptyPayload }

        do {
            return try decoder.decode(Payload.self, from: data)
        } catch let error as WebDAVSyncError {
            throw error
        } catch {
            throw WebDAVSyncError.underlying(error.localizedDescription)
        }
    }

    private func uploadPayload<Payload: Encodable>(
        _ payload: Payload,
        settings: WebDAVSyncSettings,
        fileName: String
    ) async throws {
        let config = try configuration(from: settings, fileName: fileName)
        try await createDirectoryIfNeeded(configuration: config)

        var request = YamiboNetworkConfiguration.makeRequest(url: config.fileURL)
        request.httpMethod = "PUT"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request, configuration: config)

        let (_, response) = try await session.data(for: request)
        let statusCode = try statusCode(from: response)
        guard statusCode != 401 && statusCode != 403 else { throw WebDAVSyncError.notAuthenticated }
        guard 200 ..< 300 ~= statusCode else { throw WebDAVSyncError.invalidResponse(statusCode) }
    }

    private func createDirectoryIfNeeded(configuration: Configuration) async throws {
        var request = YamiboNetworkConfiguration.makeRequest(url: configuration.directoryURL)
        request.httpMethod = "MKCOL"
        applyHeaders(to: &request, configuration: configuration)

        let (_, response) = try await session.data(for: request)
        let statusCode = try statusCode(from: response)
        guard statusCode != 401 && statusCode != 403 else { throw WebDAVSyncError.notAuthenticated }
        guard 200 ..< 300 ~= statusCode || statusCode == 405 else {
            throw WebDAVSyncError.invalidResponse(statusCode)
        }
    }

    private func configuration(from settings: WebDAVSyncSettings, fileName: String) throws -> Configuration {
        guard
            let baseURL = URL(string: settings.trimmedBaseURLString),
            !settings.trimmedUsername.isEmpty
        else {
            throw WebDAVSyncError.invalidConfiguration
        }

        let directoryURL = baseURL.appendingPathComponent("YamiboReader", isDirectory: true)
        return Configuration(
            directoryURL: directoryURL,
            fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false),
            username: settings.trimmedUsername,
            password: settings.password
        )
    }

    private func applyHeaders(to request: inout URLRequest, configuration: Configuration) {
        let token = Data("\(configuration.username):\(configuration.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func statusCode(from response: URLResponse) throws -> Int {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVSyncError.invalidResponse(nil)
        }
        return httpResponse.statusCode
    }

    private struct Configuration: Sendable {
        var directoryURL: URL
        var fileURL: URL
        var username: String
        var password: String
    }
}

public actor WebDAVSyncService {
    private let settingsStore: WebDAVSyncSettingsStore
    private let localFavoriteLibraryStore: FavoriteLibraryStore
    private let readingProgressStore: ReadingProgressStore
    private let sessionStore: SessionStore
    private let appSettingsStore: SettingsStore?
    private let client: WebDAVClient
    private let policyModule: WebDAVSyncPolicyModule

    public init(
        settingsStore: WebDAVSyncSettingsStore,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        readingProgressStore: ReadingProgressStore,
        sessionStore: SessionStore,
        appSettingsStore: SettingsStore? = nil,
        client: WebDAVClient = WebDAVClient(),
        policyModule: WebDAVSyncPolicyModule = WebDAVSyncPolicyModule()
    ) {
        self.settingsStore = settingsStore
        self.localFavoriteLibraryStore = localFavoriteLibraryStore
        self.readingProgressStore = readingProgressStore
        self.sessionStore = sessionStore
        self.appSettingsStore = appSettingsStore
        self.client = client
        self.policyModule = policyModule
    }

    @discardableResult
    public func upload() async throws -> Date {
        let settings = await settingsStore.load()
        return try await upload(using: settings)
    }

    @discardableResult
    public func upload(using settings: WebDAVSyncSettings, allowingAccountMismatch: Bool = false) async throws -> Date {
        let accountUID = try await currentAccountUID()
        if !allowingAccountMismatch {
            try await validateRemoteAccountIfPresent(settings: settings, localUID: accountUID)
        }
        return try await upload(
            using: settings,
            accountUID: accountUID,
            allowingAccountMismatch: allowingAccountMismatch
        )
    }

    @discardableResult
    public func download() async throws -> Date {
        let settings = await settingsStore.load()
        return try await download(using: settings)
    }

    @discardableResult
    public func download(using settings: WebDAVSyncSettings, allowingAccountMismatch _: Bool = false) async throws -> Date {
        let accountUID = try await currentAccountUID()
        let metadata = try await downloadLocalFirstPayloadsIfPresent(settings: settings, accountUID: accountUID)
        guard let metadata else {
            throw WebDAVSyncError.notFound
        }
        try await updateSettingsAfterSync(settings, metadata: metadata)
        return metadata.updatedAt
    }

    @discardableResult
    public func synchronizeAutomatically() async throws -> WebDAVAutomaticSyncResult {
        let settings = await settingsStore.load()
        let sessionState = await sessionStore.load()
        guard policyModule.canSynchronizeAutomatically(settings: settings, session: sessionState) else { return .skipped }
        guard let accountUID = try? currentAccountUID(from: sessionState) else { return .skipped }

        return try await synchronizeLocalFirstAutomatically(settings: settings, accountUID: accountUID)
    }

    private func currentAccountUID() async throws -> String {
        try currentAccountUID(from: await sessionStore.load())
    }

    private nonisolated func currentAccountUID(from sessionState: SessionState) throws -> String {
        guard sessionState.isLoggedIn, !sessionState.cookie.isEmpty else {
            throw YamiboError.notAuthenticated
        }
        let accountUID = sessionState.accountUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accountUID.isEmpty else {
            throw YamiboError.accountUIDUnavailable
        }
        return accountUID
    }

    public func markLocalDataChanged(at date: Date = .now, touchesAppSettings: Bool = false) async throws {
        var settings = await settingsStore.load()
        guard settings.isAutoSyncEnabled else { return }
        settings.localUpdatedAt = date
        if touchesAppSettings, let appSettingsStore {
            let syncedAppSettings = WebDAVSyncedAppSettings(settings: await appSettingsStore.load())
            if settings.lastSyncedAppSettings != syncedAppSettings {
                settings.appSettingsUpdatedAt = date
                settings.lastSyncedAppSettings = syncedAppSettings
            }
        }
        try await settingsStore.save(settings)
    }

    private func upload(
        using settings: WebDAVSyncSettings,
        accountUID: String,
        allowingAccountMismatch: Bool
    ) async throws -> Date {
        let updatedAt = Date.now
        let metadata = try await synchronizeLocalFirstPayloads(
            settings: settings,
            accountUID: accountUID,
            updatedAt: updatedAt,
            includesAppSettings: true,
            allowingAccountMismatch: allowingAccountMismatch
        )
        try await updateSettingsAfterSync(settings, metadata: metadata)
        return updatedAt
    }

    private func validateRemoteAccountIfPresent(settings: WebDAVSyncSettings, localUID: String) async throws {
        if let remotePayload = try await fetchFavoriteLibraryPayloadIfPresent(settings: settings) {
            try validateLocalFirstAccount(remoteAccountUID: remotePayload.accountUID, localUID: localUID)
            return
        }
        if let appSettingsPayload = try await fetchAppSettingsPayloadIfPresent(settings: settings) {
            try validateLocalFirstAccount(remoteAccountUID: appSettingsPayload.accountUID, localUID: localUID)
        }
    }

    private func synchronizeLocalFirstAutomatically(
        settings: WebDAVSyncSettings,
        accountUID: String
    ) async throws -> WebDAVAutomaticSyncResult {
        let remoteFavoriteLibraryPayload = try await fetchFavoriteLibraryPayloadIfPresent(settings: settings)
        try validateLocalFirstAccount(remoteAccountUID: remoteFavoriteLibraryPayload?.accountUID, localUID: accountUID)
        let remoteReadingProgressPayload = try await fetchReadingProgressPayloadIfPresent(settings: settings)
        let remoteAppSettingsPayload = try await fetchAppSettingsPayloadIfPresent(settings: settings)
        try validateLocalFirstAccount(remoteAccountUID: remoteAppSettingsPayload?.accountUID, localUID: accountUID)
        let newestRemoteUpdatedAt = max(
            max(remoteFavoriteLibraryPayload?.updatedAt, remoteReadingProgressPayload?.updatedAt),
            remoteAppSettingsPayload?.updatedAt
        )
        let localUpdatedAt = settings.localUpdatedAt ?? .distantPast

        if let newestRemoteUpdatedAt, newestRemoteUpdatedAt > localUpdatedAt {
            let metadata = try await downloadLocalFirstPayloadsIfPresent(settings: settings, accountUID: accountUID) ??
                WebDAVSyncMetadata(updatedAt: newestRemoteUpdatedAt)
            try await updateSettingsAfterSync(settings, metadata: metadata)
            return .downloaded
        }

        if newestRemoteUpdatedAt == nil || localUpdatedAt > (newestRemoteUpdatedAt ?? .distantPast) {
            let now = Date.now
            let metadata = try await synchronizeLocalFirstPayloads(
                settings: settings,
                accountUID: accountUID,
                updatedAt: now,
                includesAppSettings: settings.appSettingsUpdatedAt != nil,
                allowingAccountMismatch: false
            )
            try await updateSettingsAfterSync(settings, metadata: metadata)
            return .uploaded
        }

        return .skipped
    }

    private func synchronizeLocalFirstPayloads(
        settings: WebDAVSyncSettings,
        accountUID: String,
        updatedAt: Date,
        includesAppSettings: Bool,
        allowingAccountMismatch: Bool
    ) async throws -> WebDAVSyncMetadata {
        let localFavoriteLibraryPayload = FavoriteLibraryWebDAVPayload(
            updatedAt: updatedAt,
            accountUID: accountUID,
            library: await localFavoriteLibraryStore.load()
        )
        let remoteFavoriteLibraryPayload = try await fetchFavoriteLibraryPayloadIfPresent(settings: settings)
        if !allowingAccountMismatch {
            try validateLocalFirstAccount(remoteAccountUID: remoteFavoriteLibraryPayload?.accountUID, localUID: accountUID)
        }
        let mergedFavoriteLibrary = FavoriteLibraryWebDAVMerger().merge(
            local: localFavoriteLibraryPayload,
            remote: remoteFavoriteLibraryPayload,
            updatedAt: updatedAt
        )
        try await localFavoriteLibraryStore.save(mergedFavoriteLibrary.library)
        try await client.uploadFavoriteLibraryPayload(mergedFavoriteLibrary, settings: settings)

        let localReadingProgressPayload = ReadingProgressWebDAVPayload(
            updatedAt: updatedAt,
            records: await readingProgressStore.loadAll()
        )
        let remoteReadingProgressPayload = try await fetchReadingProgressPayloadIfPresent(settings: settings)
        let mergedReadingProgress = ReadingProgressWebDAVMerger().merge(
            local: localReadingProgressPayload,
            remote: remoteReadingProgressPayload,
            updatedAt: updatedAt
        )
        try await readingProgressStore.replaceAll(mergedReadingProgress.records)
        try await client.uploadReadingProgressPayload(mergedReadingProgress, settings: settings)

        guard includesAppSettings, let appSettingsStore else {
            return WebDAVSyncMetadata(updatedAt: updatedAt)
        }
        let remoteAppSettingsPayload = try await fetchAppSettingsPayloadIfPresent(settings: settings)
        if !allowingAccountMismatch {
            try validateLocalFirstAccount(remoteAccountUID: remoteAppSettingsPayload?.accountUID, localUID: accountUID)
        }
        let syncedAppSettings = WebDAVSyncedAppSettings(settings: await appSettingsStore.load())
        let appSettingsPayload = AppSettingsWebDAVPayload(
            updatedAt: updatedAt,
            accountUID: accountUID,
            appSettings: syncedAppSettings
        )
        try await client.uploadAppSettingsPayload(appSettingsPayload, settings: settings)
        return WebDAVSyncMetadata(
            updatedAt: updatedAt,
            appSettings: syncedAppSettings,
            appSettingsUpdatedAt: updatedAt
        )
    }

    private func downloadLocalFirstPayloadsIfPresent(
        settings: WebDAVSyncSettings,
        accountUID: String
    ) async throws -> WebDAVSyncMetadata? {
        var newestUpdatedAt: Date?
        var syncedAppSettings: WebDAVSyncedAppSettings?
        if let payload = try await fetchFavoriteLibraryPayloadIfPresent(settings: settings) {
            try validateLocalFirstAccount(remoteAccountUID: payload.accountUID, localUID: accountUID)
            try await localFavoriteLibraryStore.save(payload.library)
            newestUpdatedAt = max(newestUpdatedAt, payload.updatedAt)
        }

        if let payload = try await fetchReadingProgressPayloadIfPresent(settings: settings) {
            try await readingProgressStore.replaceAll(payload.records)
            newestUpdatedAt = max(newestUpdatedAt, payload.updatedAt)
        }

        if let appSettingsStore,
           let payload = try await fetchAppSettingsPayloadIfPresent(settings: settings) {
            try validateLocalFirstAccount(remoteAccountUID: payload.accountUID, localUID: accountUID)
            let currentSettings = await appSettingsStore.load()
            try await appSettingsStore.save(payload.appSettings.applying(to: currentSettings))
            syncedAppSettings = payload.appSettings
            newestUpdatedAt = max(newestUpdatedAt, payload.updatedAt)
        }

        guard let newestUpdatedAt else { return nil }
        return WebDAVSyncMetadata(
            updatedAt: newestUpdatedAt,
            appSettings: syncedAppSettings,
            appSettingsUpdatedAt: nil
        )
    }

    private func fetchFavoriteLibraryPayloadIfPresent(settings: WebDAVSyncSettings) async throws -> FavoriteLibraryWebDAVPayload? {
        do {
            return try await client.fetchFavoriteLibraryPayload(settings: settings)
        } catch WebDAVSyncError.notFound {
            return nil
        } catch WebDAVSyncError.underlying {
            return nil
        }
    }

    private func fetchReadingProgressPayloadIfPresent(settings: WebDAVSyncSettings) async throws -> ReadingProgressWebDAVPayload? {
        do {
            return try await client.fetchReadingProgressPayload(settings: settings)
        } catch WebDAVSyncError.notFound {
            return nil
        } catch WebDAVSyncError.underlying {
            return nil
        }
    }

    private func fetchAppSettingsPayloadIfPresent(settings: WebDAVSyncSettings) async throws -> AppSettingsWebDAVPayload? {
        do {
            return try await client.fetchAppSettingsPayload(settings: settings)
        } catch WebDAVSyncError.notFound {
            return nil
        } catch WebDAVSyncError.underlying {
            return nil
        }
    }

    private func validateLocalFirstAccount(remoteAccountUID: String?, localUID: String) throws {
        guard let remoteAccountUID,
              !remoteAccountUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              remoteAccountUID != localUID else {
            return
        }
        throw WebDAVSyncError.accountMismatch(localUID: localUID, remoteUID: remoteAccountUID)
    }

    private func updateSettingsAfterSync(_ settings: WebDAVSyncSettings, metadata: WebDAVSyncMetadata) async throws {
        var updated = settings
        updated.lastSyncedAt = .now
        updated.lastRemoteUpdatedAt = metadata.updatedAt
        updated.localUpdatedAt = metadata.updatedAt
        updated.appSettingsUpdatedAt = metadata.appSettingsUpdatedAt
        updated.lastSyncedAppSettings = metadata.appSettings
        try await settingsStore.save(updated)
    }
}

private struct WebDAVSyncMetadata: Sendable {
    var updatedAt: Date
    var appSettings: WebDAVSyncedAppSettings?
    var appSettingsUpdatedAt: Date?

    init(
        updatedAt: Date,
        appSettings: WebDAVSyncedAppSettings? = nil,
        appSettingsUpdatedAt: Date? = nil
    ) {
        self.updatedAt = updatedAt
        self.appSettings = appSettings
        self.appSettingsUpdatedAt = appSettingsUpdatedAt
    }
}

private func max(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        Swift.max(lhs, rhs)
    case let (lhs?, nil):
        lhs
    case let (nil, rhs?):
        rhs
    case (nil, nil):
        nil
    }
}
