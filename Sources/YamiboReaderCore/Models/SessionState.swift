import Foundation

public struct SessionState: Codable, Hashable, Sendable {
    public var cookie: String
    public var userAgent: String
    public var isLoggedIn: Bool
    public var lastUpdatedAt: Date?

    public init(
        cookie: String = "",
        userAgent: String = YamiboDefaults.defaultMobileUserAgent,
        isLoggedIn: Bool = false,
        lastUpdatedAt: Date? = nil
    ) {
        self.cookie = cookie
        self.userAgent = userAgent
        self.isLoggedIn = isLoggedIn
        self.lastUpdatedAt = lastUpdatedAt
    }
}
