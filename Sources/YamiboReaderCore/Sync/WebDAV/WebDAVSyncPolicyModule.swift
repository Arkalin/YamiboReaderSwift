import Foundation

public struct WebDAVSyncPolicyModule: Sendable {
    public init() {}

    public func canSynchronizeAutomatically(
        settings: WebDAVSyncSettings,
        session: SessionState
    ) -> Bool {
        settings.isAutoSyncEnabled &&
            settings.isConfigured &&
            session.isLoggedIn &&
            !session.cookie.isEmpty
    }
}
