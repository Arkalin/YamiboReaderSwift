import Foundation

public protocol SettingsStoring: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async throws
    func reset() async throws
}

public actor SettingsStore: SettingsStoring {
    public static let didChangeNotification = Notification.Name("yamibo.settingsStore.didChange")
    public static let changeIDUserInfoKey = "changeID"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public func save(_ settings: AppSettings) async throws {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func reset() async throws {
        try await save(AppSettings())
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}
