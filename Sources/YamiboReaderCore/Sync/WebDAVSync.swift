import Foundation

public struct WebDAVSyncSettings: Codable, Equatable, Sendable {
    public var baseURLString: String
    public var username: String
    public var password: String
    public var isAutoSyncEnabled: Bool
    public var lastSyncedAt: Date?
    public var lastRemoteUpdatedAt: Date?
    public var localUpdatedAt: Date?

    public init(
        baseURLString: String = "",
        username: String = "",
        password: String = "",
        isAutoSyncEnabled: Bool = false,
        lastSyncedAt: Date? = nil,
        lastRemoteUpdatedAt: Date? = nil,
        localUpdatedAt: Date? = nil
    ) {
        self.baseURLString = baseURLString
        self.username = username
        self.password = password
        self.isAutoSyncEnabled = isAutoSyncEnabled
        self.lastSyncedAt = lastSyncedAt
        self.lastRemoteUpdatedAt = lastRemoteUpdatedAt
        self.localUpdatedAt = localUpdatedAt
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

public struct WebDAVSyncPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var updatedAt: Date
    public var accountUID: String?
    public var library: FavoriteLibrarySnapshot
    public var appSettings: WebDAVSyncedAppSettings?

    public init(
        version: Int = Self.currentVersion,
        updatedAt: Date,
        accountUID: String? = nil,
        library: FavoriteLibrarySnapshot,
        appSettings: WebDAVSyncedAppSettings? = nil
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.accountUID = accountUID
        self.library = library
        self.appSettings = appSettings
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
            homePage: settings.homePage,
            webBrowser: settings.webBrowser,
            favoriteAppearance: settings.favoriteAppearance
        )
    }

    public func applying(to settings: AppSettings) -> AppSettings {
        var updated = settings
        updated.homePage = homePage
        updated.webBrowser = webBrowser
        updated.favoriteAppearance = favoriteAppearance
        return updated
    }
}

public enum WebDAVSyncDirection: String, Codable, CaseIterable, Sendable {
    case upload
    case download
}

public enum WebDAVAutomaticSyncResult: Equatable, Sendable {
    case skipped
    case downloaded(WebDAVSyncPayload)
    case uploaded(WebDAVSyncPayload)
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
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchPayload(settings: WebDAVSyncSettings) async throws -> WebDAVSyncPayload {
        let config = try configuration(from: settings)
        var request = URLRequest(url: config.fileURL)
        request.httpMethod = "GET"
        applyHeaders(to: &request, configuration: config)

        let (data, response) = try await session.data(for: request)
        let statusCode = try statusCode(from: response)
        guard statusCode != 404 else { throw WebDAVSyncError.notFound }
        guard statusCode != 401 && statusCode != 403 else { throw WebDAVSyncError.notAuthenticated }
        guard 200 ..< 300 ~= statusCode else { throw WebDAVSyncError.invalidResponse(statusCode) }
        guard !data.isEmpty else { throw WebDAVSyncError.emptyPayload }

        do {
            let payload = try decoder.decode(WebDAVSyncPayload.self, from: data)
            guard payload.version == WebDAVSyncPayload.currentVersion else {
                throw WebDAVSyncError.unsupportedPayloadVersion(payload.version)
            }
            return payload
        } catch let error as WebDAVSyncError {
            throw error
        } catch {
            throw WebDAVSyncError.underlying(error.localizedDescription)
        }
    }

    public func uploadPayload(_ payload: WebDAVSyncPayload, settings: WebDAVSyncSettings) async throws {
        let config = try configuration(from: settings)
        try await createDirectoryIfNeeded(configuration: config)

        var request = URLRequest(url: config.fileURL)
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
        var request = URLRequest(url: configuration.directoryURL)
        request.httpMethod = "MKCOL"
        applyHeaders(to: &request, configuration: configuration)

        let (_, response) = try await session.data(for: request)
        let statusCode = try statusCode(from: response)
        guard statusCode != 401 && statusCode != 403 else { throw WebDAVSyncError.notAuthenticated }
        guard 200 ..< 300 ~= statusCode || statusCode == 405 else {
            throw WebDAVSyncError.invalidResponse(statusCode)
        }
    }

    private func configuration(from settings: WebDAVSyncSettings) throws -> Configuration {
        guard
            let baseURL = URL(string: settings.trimmedBaseURLString),
            !settings.trimmedUsername.isEmpty
        else {
            throw WebDAVSyncError.invalidConfiguration
        }

        let directoryURL = baseURL.appendingPathComponent("YamiboReader", isDirectory: true)
        return Configuration(
            directoryURL: directoryURL,
            fileURL: directoryURL.appendingPathComponent("yamibo-sync-v1.json", isDirectory: false),
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
    private let favoriteStore: FavoriteStore
    private let sessionStore: SessionStore
    private let appSettingsStore: (any SettingsStoring)?
    private let accountUIDResolver: AccountUIDResolver
    private let client: WebDAVClient
    private let policyModule: WebDAVSyncPolicyModule

    public init(
        settingsStore: WebDAVSyncSettingsStore,
        favoriteStore: FavoriteStore,
        sessionStore: SessionStore,
        appSettingsStore: (any SettingsStoring)? = nil,
        client: WebDAVClient = WebDAVClient(),
        accountUIDResolver: AccountUIDResolver? = nil,
        policyModule: WebDAVSyncPolicyModule = WebDAVSyncPolicyModule()
    ) {
        self.settingsStore = settingsStore
        self.favoriteStore = favoriteStore
        self.sessionStore = sessionStore
        self.appSettingsStore = appSettingsStore
        self.client = client
        self.accountUIDResolver = accountUIDResolver ?? AccountUIDResolver(sessionStore: sessionStore)
        self.policyModule = policyModule
    }

    public func upload() async throws -> WebDAVSyncPayload {
        let settings = await settingsStore.load()
        return try await upload(using: settings)
    }

    @discardableResult
    public func upload(using settings: WebDAVSyncSettings, allowingAccountMismatch: Bool = false) async throws -> WebDAVSyncPayload {
        let accountUID = try await accountUIDResolver.resolveCurrentAccountUID()
        if !allowingAccountMismatch {
            try await validateRemoteAccountIfPresent(settings: settings, localUID: accountUID)
        }
        return try await upload(using: settings, accountUID: accountUID)
    }

    @discardableResult
    public func download() async throws -> WebDAVSyncPayload {
        let settings = await settingsStore.load()
        return try await download(using: settings)
    }

    @discardableResult
    public func download(using settings: WebDAVSyncSettings, allowingAccountMismatch _: Bool = false) async throws -> WebDAVSyncPayload {
        let accountUID = try await accountUIDResolver.resolveCurrentAccountUID()
        let payload = try await client.fetchPayload(settings: settings)
        try validate(remotePayload: payload, localUID: accountUID, allowingAccountMismatch: false)
        try await apply(payload)
        try await updateSettingsAfterSync(settings, remoteUpdatedAt: payload.updatedAt)
        return payload
    }

    @discardableResult
    public func synchronizeAutomatically() async throws -> WebDAVAutomaticSyncResult {
        let settings = await settingsStore.load()
        let sessionState = await sessionStore.load()
        guard policyModule.canSynchronizeAutomatically(settings: settings, session: sessionState) else { return .skipped }
        guard let accountUID = try? await accountUIDResolver.resolveCurrentAccountUID() else { return .skipped }

        let remotePayload: WebDAVSyncPayload?
        do {
            remotePayload = try await client.fetchPayload(settings: settings)
        } catch WebDAVSyncError.notFound {
            remotePayload = nil
        }
        switch policyModule.automaticDecision(settings: settings, remotePayload: remotePayload, localUID: accountUID) {
        case .skip:
            return .skipped
        case let .download(remotePayload):
            try await apply(remotePayload)
            try await updateSettingsAfterSync(settings, remoteUpdatedAt: remotePayload.updatedAt)
            return .downloaded(remotePayload)
        case .upload:
            let payload = try await upload(using: settings, accountUID: accountUID)
            return .uploaded(payload)
        }
    }

    public func markLocalDataChanged(at date: Date = .now) async throws {
        var settings = await settingsStore.load()
        guard settings.isAutoSyncEnabled else { return }
        settings.localUpdatedAt = date
        try await settingsStore.save(settings)
    }

    private func upload(using settings: WebDAVSyncSettings, accountUID: String) async throws -> WebDAVSyncPayload {
        let payload = try await makePayload(updatedAt: .now, accountUID: accountUID)
        try await client.uploadPayload(payload, settings: settings)
        try await updateSettingsAfterSync(settings, remoteUpdatedAt: payload.updatedAt)
        return payload
    }

    private func validateRemoteAccountIfPresent(settings: WebDAVSyncSettings, localUID: String) async throws {
        do {
            let remotePayload = try await client.fetchPayload(settings: settings)
            try policyModule.validate(remotePayload: remotePayload, localUID: localUID, allowingAccountMismatch: false)
        } catch WebDAVSyncError.notFound {
            return
        }
    }

    private func validate(
        remotePayload: WebDAVSyncPayload,
        localUID: String,
        allowingAccountMismatch: Bool
    ) throws {
        try policyModule.validate(
            remotePayload: remotePayload,
            localUID: localUID,
            allowingAccountMismatch: allowingAccountMismatch
        )
    }

    private func isAccountMismatch(remotePayload: WebDAVSyncPayload, localUID: String) -> Bool {
        policyModule.isAccountMismatch(remotePayload: remotePayload, localUID: localUID)
    }

    private func makePayload(updatedAt: Date, accountUID: String) async throws -> WebDAVSyncPayload {
        let syncedAppSettings: WebDAVSyncedAppSettings?
        if let appSettingsStore {
            syncedAppSettings = WebDAVSyncedAppSettings(settings: await appSettingsStore.load())
        } else {
            syncedAppSettings = nil
        }

        return WebDAVSyncPayload(
            updatedAt: updatedAt,
            accountUID: accountUID,
            library: await favoriteStore.loadLibrarySnapshot(),
            appSettings: syncedAppSettings
        )
    }

    private func apply(_ payload: WebDAVSyncPayload) async throws {
        guard payload.version == WebDAVSyncPayload.currentVersion else {
            throw WebDAVSyncError.unsupportedPayloadVersion(payload.version)
        }
        try await favoriteStore.saveLibrarySnapshot(payload.library)
        if let appSettings = payload.appSettings, let appSettingsStore {
            let currentSettings = await appSettingsStore.load()
            try await appSettingsStore.save(appSettings.applying(to: currentSettings))
        }
    }

    private func updateSettingsAfterSync(_ settings: WebDAVSyncSettings, remoteUpdatedAt: Date) async throws {
        var updated = settings
        updated.lastSyncedAt = .now
        updated.lastRemoteUpdatedAt = remoteUpdatedAt
        updated.localUpdatedAt = remoteUpdatedAt
        try await settingsStore.save(updated)
    }
}
