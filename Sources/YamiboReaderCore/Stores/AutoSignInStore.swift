import CryptoKit
import Foundation

public actor AutoSignInStore {
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
    }

    public func lastSignedDate(session: SessionState) async -> String? {
        guard let key = storageKey(for: session) else { return nil }
        return defaults.string(forKey: key)
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
}
