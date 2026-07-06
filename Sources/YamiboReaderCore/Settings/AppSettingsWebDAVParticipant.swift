import Foundation

/// WebDAV sync participant for the synchronized subset of app settings.
/// Last-writer-wins: the payload is a snapshot, never merged, and it is only
/// uploaded automatically after the synchronized subset actually changed.
struct AppSettingsWebDAVParticipant: WebDAVSyncParticipant {
    let datasetID = "appSettings"
    let remoteFileName = "yamibo-app-settings-v1.json"
    let uploadsOnlyWhenMarkedDirty = true

    private let store: SettingsStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: SettingsStore) {
        self.store = store
    }

    func inspectRemote(_ data: Data) throws -> WebDAVRemotePayloadInfo {
        let payload = try decoder.decode(AppSettingsWebDAVPayload.self, from: data)
        return WebDAVRemotePayloadInfo(updatedAt: payload.updatedAt, accountUID: payload.accountUID)
    }

    func mergeAndExport(remoteData _: Data?, updatedAt: Date, accountUID: String) async throws -> Data {
        let payload = AppSettingsWebDAVPayload(
            updatedAt: updatedAt,
            accountUID: accountUID,
            appSettings: WebDAVSyncedAppSettings(settings: await store.load())
        )
        return try encoder.encode(payload)
    }

    func applyRemote(_ data: Data) async throws {
        let payload = try decoder.decode(AppSettingsWebDAVPayload.self, from: data)
        let currentSettings = await store.load()
        try await store.save(payload.appSettings.applying(to: currentSettings))
    }

    func localFingerprint() async -> String? {
        let snapshot = WebDAVSyncedAppSettings(settings: await store.load())
        let fingerprintEncoder = JSONEncoder()
        fingerprintEncoder.outputFormatting = [.sortedKeys]
        guard let data = try? fingerprintEncoder.encode(snapshot) else { return nil }
        return data.base64EncodedString()
    }
}

/// The subset of `AppSettings` that participates in WebDAV synchronization.
struct WebDAVSyncedAppSettings: Codable, Equatable, Sendable {
    var homePage: AppHomePage
    var webBrowser: WebBrowserSettings
    var favoriteAppearance: FavoriteAppearanceSettings

    init(
        homePage: AppHomePage,
        webBrowser: WebBrowserSettings,
        favoriteAppearance: FavoriteAppearanceSettings
    ) {
        self.homePage = homePage
        self.webBrowser = webBrowser
        self.favoriteAppearance = favoriteAppearance
    }

    init(settings: AppSettings) {
        self.init(
            homePage: settings.system.homePage,
            webBrowser: settings.webBrowser,
            favoriteAppearance: settings.favorites.appearance
        )
    }

    func applying(to settings: AppSettings) -> AppSettings {
        var updated = settings
        updated.system.homePage = homePage
        updated.webBrowser = webBrowser
        updated.favorites.appearance = favoriteAppearance
        return updated
    }
}

struct AppSettingsWebDAVPayload: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var updatedAt: Date
    var accountUID: String?
    var appSettings: WebDAVSyncedAppSettings

    init(
        version: Int = Self.currentVersion,
        updatedAt: Date,
        accountUID: String? = nil,
        appSettings: WebDAVSyncedAppSettings
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.accountUID = accountUID
        self.appSettings = appSettings
    }
}
