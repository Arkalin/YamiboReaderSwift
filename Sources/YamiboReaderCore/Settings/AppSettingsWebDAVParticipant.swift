import Foundation

/// WebDAV sync participant for the synchronized subset of app settings.
/// Last-writer-wins: the payload is a snapshot, never merged, and it is only
/// uploaded automatically after the synchronized subset actually changed.
public struct AppSettingsWebDAVParticipant: WebDAVSyncParticipant {
    public let datasetID = "appSettings"
    public let remoteFileName = "yamibo-app-settings-v1.json"
    public let uploadsOnlyWhenMarkedDirty = true

    private let store: SettingsStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: SettingsStore) {
        self.store = store
    }

    public func inspectRemote(_ data: Data) throws -> WebDAVRemotePayloadInfo {
        let payload = try decoder.decode(AppSettingsWebDAVPayload.self, from: data)
        return WebDAVRemotePayloadInfo(updatedAt: payload.updatedAt, accountUID: payload.accountUID)
    }

    public func mergeAndExport(remoteData _: Data?, updatedAt: Date, accountUID: String) async throws -> Data {
        let payload = AppSettingsWebDAVPayload(
            updatedAt: updatedAt,
            accountUID: accountUID,
            appSettings: WebDAVSyncedAppSettings(settings: await store.load())
        )
        return try encoder.encode(payload)
    }

    public func applyRemote(_ data: Data) async throws {
        let payload = try decoder.decode(AppSettingsWebDAVPayload.self, from: data)
        let currentSettings = await store.load()
        try await store.save(payload.appSettings.applying(to: currentSettings))
    }

    public func localFingerprint() async -> String? {
        let snapshot = WebDAVSyncedAppSettings(settings: await store.load())
        let fingerprintEncoder = JSONEncoder()
        fingerprintEncoder.outputFormatting = [.sortedKeys]
        guard let data = try? fingerprintEncoder.encode(snapshot) else { return nil }
        return data.base64EncodedString()
    }
}

/// The subset of `AppSettings` that participates in WebDAV synchronization.
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

public struct AppSettingsWebDAVPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var updatedAt: Date
    public var accountUID: String?
    public var appSettings: WebDAVSyncedAppSettings

    public init(
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
