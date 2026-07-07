import Foundation

public struct WebDAVSyncSettings: Codable, Equatable, Sendable {
    public var baseURLString: String
    public var username: String
    public var password: String
    public var isAutoSyncEnabled: Bool
    public var lastSyncedAt: Date?
    public var lastRemoteUpdatedAt: Date?
    public var localUpdatedAt: Date?
    /// Datasets flagged as changed since the last sync; only consulted for
    /// participants that upload exclusively when marked dirty.
    public var dirtyDatasetIDs: Set<String>
    /// Fingerprint of each fingerprint-tracked dataset as of the last time it
    /// was marked or synchronized, used for change detection.
    public var lastSyncedFingerprintByDatasetID: [String: String]

    public init(
        baseURLString: String = "",
        username: String = "",
        password: String = "",
        isAutoSyncEnabled: Bool = false,
        lastSyncedAt: Date? = nil,
        lastRemoteUpdatedAt: Date? = nil,
        localUpdatedAt: Date? = nil,
        dirtyDatasetIDs: Set<String> = [],
        lastSyncedFingerprintByDatasetID: [String: String] = [:]
    ) {
        self.baseURLString = baseURLString
        self.username = username
        self.password = password
        self.isAutoSyncEnabled = isAutoSyncEnabled
        self.lastSyncedAt = lastSyncedAt
        self.lastRemoteUpdatedAt = lastRemoteUpdatedAt
        self.localUpdatedAt = localUpdatedAt
        self.dirtyDatasetIDs = dirtyDatasetIDs
        self.lastSyncedFingerprintByDatasetID = lastSyncedFingerprintByDatasetID
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
        do {
            return try decoder.decode(WebDAVSyncSettings.self, from: data)
        } catch {
            YamiboLog.sync.error("Failed to decode stored WebDAV sync settings, resetting to defaults: \(error)")
            return WebDAVSyncSettings()
        }
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

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
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

struct WebDAVClient: Sendable {
    let session: URLSession

    init(session: URLSession = YamiboNetworkConfiguration.makeSession()) {
        self.session = session
    }

    func fetchPayloadData(settings: WebDAVSyncSettings, fileName: String) async throws -> Data {
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
        return data
    }

    func uploadPayloadData(_ data: Data, settings: WebDAVSyncSettings, fileName: String) async throws {
        let config = try configuration(from: settings, fileName: fileName)
        try await createDirectoryIfNeeded(configuration: config)

        var request = YamiboNetworkConfiguration.makeRequest(url: config.fileURL)
        request.httpMethod = "PUT"
        request.httpBody = data
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
    private let sessionStore: SessionStore
    private let participants: [any WebDAVSyncParticipant]
    private let client: WebDAVClient
    private let policyModule: WebDAVSyncPolicyModule

    init(
        settingsStore: WebDAVSyncSettingsStore,
        sessionStore: SessionStore,
        participants: [any WebDAVSyncParticipant],
        client: WebDAVClient = WebDAVClient(),
        policyModule: WebDAVSyncPolicyModule = WebDAVSyncPolicyModule()
    ) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.participants = participants
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
        let remotePayloads = try await fetchRemotePayloads(settings: settings)
        if !allowingAccountMismatch {
            try validateAccount(of: remotePayloads, localUID: accountUID)
        }
        let updatedAt = Date.now
        try await uploadParticipants(
            participants,
            remotePayloads: remotePayloads,
            settings: settings,
            accountUID: accountUID,
            updatedAt: updatedAt
        )
        try await updateSettingsAfterSync(
            settings,
            updatedAt: updatedAt,
            syncedDatasetIDs: Set(participants.map(\.datasetID))
        )
        return updatedAt
    }

    @discardableResult
    public func download() async throws -> Date {
        let settings = await settingsStore.load()
        return try await download(using: settings)
    }

    @discardableResult
    public func download(using settings: WebDAVSyncSettings, allowingAccountMismatch _: Bool = false) async throws -> Date {
        let accountUID = try await currentAccountUID()
        let remotePayloads = try await fetchRemotePayloads(settings: settings)
        try validateAccount(of: remotePayloads, localUID: accountUID)
        guard let updatedAt = try await applyRemotePayloads(remotePayloads) else {
            throw WebDAVSyncError.notFound
        }
        try await updateSettingsAfterSync(
            settings,
            updatedAt: updatedAt,
            syncedDatasetIDs: Set(remotePayloads.keys)
        )
        return updatedAt
    }

    @discardableResult
    public func synchronizeAutomatically() async throws -> WebDAVAutomaticSyncResult {
        let settings = await settingsStore.load()
        let sessionState = await sessionStore.load()
        guard policyModule.canSynchronizeAutomatically(settings: settings, session: sessionState) else { return .skipped }
        guard let accountUID = try? currentAccountUID(from: sessionState) else { return .skipped }

        let remotePayloads = try await fetchRemotePayloads(settings: settings)
        try validateAccount(of: remotePayloads, localUID: accountUID)
        let newestRemoteUpdatedAt = remotePayloads.values.map(\.info.updatedAt).max()
        let localUpdatedAt = settings.localUpdatedAt ?? .distantPast

        if let newestRemoteUpdatedAt, newestRemoteUpdatedAt > localUpdatedAt {
            _ = try await applyRemotePayloads(remotePayloads)
            try await updateSettingsAfterSync(
                settings,
                updatedAt: newestRemoteUpdatedAt,
                syncedDatasetIDs: Set(remotePayloads.keys)
            )
            return .downloaded
        }

        if newestRemoteUpdatedAt == nil || localUpdatedAt > (newestRemoteUpdatedAt ?? .distantPast) {
            let included = participants.filter {
                !$0.uploadsOnlyWhenMarkedDirty || settings.dirtyDatasetIDs.contains($0.datasetID)
            }
            let updatedAt = Date.now
            try await uploadParticipants(
                included,
                remotePayloads: remotePayloads,
                settings: settings,
                accountUID: accountUID,
                updatedAt: updatedAt
            )
            try await updateSettingsAfterSync(
                settings,
                updatedAt: updatedAt,
                syncedDatasetIDs: Set(included.map(\.datasetID))
            )
            return .uploaded
        }

        return .skipped
    }

    /// Records that locally synchronized data changed. When `touchesAppSettings`
    /// is true, fingerprint-tracked participants are re-fingerprinted and marked
    /// dirty if their synchronized subset actually changed.
    public func markLocalDataChanged(at date: Date = .now, touchesAppSettings: Bool = false) async throws {
        var settings = await settingsStore.load()
        guard settings.isAutoSyncEnabled else { return }
        settings.localUpdatedAt = date
        if touchesAppSettings {
            for participant in participants where participant.uploadsOnlyWhenMarkedDirty {
                guard let fingerprint = await participant.localFingerprint() else { continue }
                if settings.lastSyncedFingerprintByDatasetID[participant.datasetID] != fingerprint {
                    settings.dirtyDatasetIDs.insert(participant.datasetID)
                    settings.lastSyncedFingerprintByDatasetID[participant.datasetID] = fingerprint
                }
            }
        }
        try await settingsStore.save(settings)
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

    private struct RemotePayload: Sendable {
        var data: Data
        var info: WebDAVRemotePayloadInfo
    }

    private func fetchRemotePayloads(settings: WebDAVSyncSettings) async throws -> [String: RemotePayload] {
        var payloads: [String: RemotePayload] = [:]
        for participant in participants {
            if let payload = try await fetchRemotePayloadIfPresent(for: participant, settings: settings) {
                payloads[participant.datasetID] = payload
            }
        }
        return payloads
    }

    private func fetchRemotePayloadIfPresent(
        for participant: any WebDAVSyncParticipant,
        settings: WebDAVSyncSettings
    ) async throws -> RemotePayload? {
        let data: Data
        do {
            data = try await client.fetchPayloadData(settings: settings, fileName: participant.remoteFileName)
        } catch WebDAVSyncError.notFound {
            return nil
        }
        do {
            return RemotePayload(data: data, info: try participant.inspectRemote(data))
        } catch let error as WebDAVSyncError {
            if case .underlying = error {
                YamiboLog.sync.warning("WebDAV inspectRemote failed for dataset \(participant.datasetID): \(error)")
                return nil
            }
            throw error
        } catch {
            YamiboLog.sync.warning("WebDAV inspectRemote failed for dataset \(participant.datasetID): \(error)")
            return nil
        }
    }

    private func uploadParticipants(
        _ included: [any WebDAVSyncParticipant],
        remotePayloads: [String: RemotePayload],
        settings: WebDAVSyncSettings,
        accountUID: String,
        updatedAt: Date
    ) async throws {
        for participant in included {
            let payloadData = try await participant.mergeAndExport(
                remoteData: remotePayloads[participant.datasetID]?.data,
                updatedAt: updatedAt,
                accountUID: accountUID
            )
            try await client.uploadPayloadData(payloadData, settings: settings, fileName: participant.remoteFileName)
        }
    }

    private func applyRemotePayloads(_ remotePayloads: [String: RemotePayload]) async throws -> Date? {
        var newestUpdatedAt: Date?
        for participant in participants {
            guard let payload = remotePayloads[participant.datasetID] else { continue }
            try await participant.applyRemote(payload.data)
            newestUpdatedAt = Swift.max(newestUpdatedAt ?? .distantPast, payload.info.updatedAt)
        }
        return newestUpdatedAt
    }

    private func validateAccount(of remotePayloads: [String: RemotePayload], localUID: String) throws {
        for payload in remotePayloads.values {
            try validateAccount(remoteAccountUID: payload.info.accountUID, localUID: localUID)
        }
    }

    private func validateAccount(remoteAccountUID: String?, localUID: String) throws {
        guard let remoteAccountUID,
              !remoteAccountUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              remoteAccountUID != localUID else {
            return
        }
        throw WebDAVSyncError.accountMismatch(localUID: localUID, remoteUID: remoteAccountUID)
    }

    private func updateSettingsAfterSync(
        _ settings: WebDAVSyncSettings,
        updatedAt: Date,
        syncedDatasetIDs: Set<String>
    ) async throws {
        var updated = settings
        updated.lastSyncedAt = .now
        updated.lastRemoteUpdatedAt = updatedAt
        updated.localUpdatedAt = updatedAt
        for participant in participants where syncedDatasetIDs.contains(participant.datasetID) {
            updated.dirtyDatasetIDs.remove(participant.datasetID)
            if let fingerprint = await participant.localFingerprint() {
                updated.lastSyncedFingerprintByDatasetID[participant.datasetID] = fingerprint
            }
        }
        try await settingsStore.save(updated)
    }
}
