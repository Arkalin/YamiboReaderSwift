import Foundation
import YamiboReaderCore

enum YamiboTestDefaults {
    static func suiteName(prefix: String) -> String {
        "yamibo-tests.\(prefix).\(UUID().uuidString)"
    }

    static func make(prefix: String) throws -> UserDefaults {
        try make(suiteName: suiteName(prefix: prefix))
    }

    static func make(suiteName: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "YamiboTestDefaults",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create UserDefaults suite \(suiteName)"]
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func defaults(suiteName: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "YamiboTestDefaults",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create UserDefaults suite \(suiteName)"]
            )
        }
        return defaults
    }
}

extension ReadingProgressStore {
    init(testSuiteName suiteName: String, key: String) throws {
        self.init(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: key
        )
    }
}

extension ReaderResumeRouteStore {
    convenience init(testSuiteName suiteName: String, key: String) throws {
        self.init(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: key)
    }
}
