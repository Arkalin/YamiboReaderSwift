import Foundation

public protocol SessionStoring: Sendable {
    func load() async -> SessionState
    func save(_ session: SessionState) async throws
    func updateCookie(_ cookie: String, isLoggedIn: Bool) async throws
    func updateWebSession(cookie: String, userAgent: String, isLoggedIn: Bool) async throws
    func reset() async throws
}

public actor SessionStore: SessionStoring {
    public static let didChangeNotification = Notification.Name("yamibo.sessionStore.didChange")
    public static let changeIDUserInfoKey = "changeID"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.session") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> SessionState {
        guard let data = defaults.data(forKey: key) else { return SessionState() }
        return (try? decoder.decode(SessionState.self, from: data)) ?? SessionState()
    }

    public func save(_ session: SessionState) async throws {
        do {
            let data = try encoder.encode(session)
            defaults.set(data, forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func updateCookie(_ cookie: String, isLoggedIn: Bool) async throws {
        var session = await load()
        session.cookie = cookie
        session.isLoggedIn = isLoggedIn
        session.lastUpdatedAt = .now
        try await save(session)
    }

    public func updateWebSession(cookie: String, userAgent: String, isLoggedIn: Bool) async throws {
        var session = await load()
        session.cookie = cookie
        session.userAgent = userAgent
        session.isLoggedIn = isLoggedIn
        session.lastUpdatedAt = .now
        try await save(session)
    }

    public func reset() async throws {
        try await save(SessionState())
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}
