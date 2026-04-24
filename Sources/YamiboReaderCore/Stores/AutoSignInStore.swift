import CryptoKit
import Foundation

public struct AutoSignInSnapshot: Codable, Equatable, Sendable {
    public var signedDatesByAccountHash: [String: String]

    public init(signedDatesByAccountHash: [String: String] = [:]) {
        self.signedDatesByAccountHash = signedDatesByAccountHash
    }
}

public actor AutoSignInStore {
    public static let didChangeNotification = Notification.Name("yamibo.autoSignInStore.didChange")
    public static let changeIDUserInfoKey = "changeID"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let keyPrefix: String
    private let calendar: Calendar
    private let formatter: DateFormatter

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "yamibo.autoSign.lastDate"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        self.calendar = calendar

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter
    }

    public func needsSignIn(session: SessionState) async -> Bool {
        guard let key = storageKey(for: session) else { return true }
        return defaults.string(forKey: key) != currentDateString()
    }

    public func markSignedIn(session: SessionState) async {
        guard let key = storageKey(for: session) else { return }
        defaults.set(currentDateString(), forKey: key)
        postChangeNotification()
    }

    public func lastSignedDate(session: SessionState) async -> String? {
        guard let key = storageKey(for: session) else { return nil }
        return defaults.string(forKey: key)
    }

    public func exportSnapshot() async -> AutoSignInSnapshot {
        let prefix = "\(keyPrefix)."
        let values = defaults.dictionaryRepresentation().reduce(into: [String: String]()) { partial, item in
            guard item.key.hasPrefix(prefix), let date = item.value as? String else { return }
            let hash = String(item.key.dropFirst(prefix.count))
            guard !hash.isEmpty else { return }
            partial[hash] = date
        }
        return AutoSignInSnapshot(signedDatesByAccountHash: values)
    }

    public func importSnapshot(_ snapshot: AutoSignInSnapshot) async {
        let prefix = "\(keyPrefix)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        for (hash, date) in snapshot.signedDatesByAccountHash where !hash.isEmpty && !date.isEmpty {
            defaults.set(date, forKey: "\(prefix)\(hash)")
        }
        postChangeNotification()
    }

    private func storageKey(for session: SessionState) -> String? {
        guard let hash = accountHash(from: session.cookie) else { return nil }
        return "\(keyPrefix).\(hash)"
    }

    private func currentDateString() -> String {
        formatter.string(from: Date())
    }

    private func accountHash(from cookie: String) -> String? {
        let parts = cookie.split(separator: ";")
        guard
            let authValue = parts
                .compactMap({ part -> String? in
                    let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { return nil }
                    return pair[0].trimmingCharacters(in: .whitespacesAndNewlines) == "EeqY_2132_auth" ? pair[1] : nil
                })
                .first,
            !authValue.isEmpty
        else {
            return nil
        }

        let digest = SHA256.hash(data: Data(authValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}
