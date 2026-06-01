import Foundation

public final class ReaderResumeRouteStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var suppressesPositionSaves = false

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.reader.resumeRoute") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> ReaderResumeRoute? {
        loadSync()
    }

    public func loadSync() -> ReaderResumeRoute? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(ReaderResumeRoute.self, from: data)
    }

    public func save(_ route: ReaderResumeRoute) async throws {
        try saveSync(route)
    }

    public func saveSync(_ route: ReaderResumeRoute) throws {
        lock.lock()
        suppressesPositionSaves = false
        lock.unlock()
        try write(route)
    }

    public func saveReadingPosition(_ route: ReaderResumeRoute) async throws {
        try saveReadingPositionSync(route)
    }

    public func saveReadingPositionSync(_ route: ReaderResumeRoute) throws {
        lock.lock()
        let shouldSuppress = suppressesPositionSaves
        lock.unlock()
        guard !shouldSuppress else { return }
        try write(route)
    }

    private func write(_ route: ReaderResumeRoute) throws {
        do {
            let data = try encoder.encode(route)
            defaults.set(data, forKey: key)
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func clear() async {
        clearSync()
    }

    public func clearSync() {
        lock.lock()
        suppressesPositionSaves = true
        lock.unlock()
        defaults.removeObject(forKey: key)
    }
}
