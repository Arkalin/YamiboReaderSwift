import Foundation

public enum WebDAVAutomaticSyncDecision: Equatable, Sendable {
    case skip
    case download(WebDAVSyncPayload)
    case upload
}

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

    public func automaticDecision(
        settings: WebDAVSyncSettings,
        remotePayload: WebDAVSyncPayload?,
        localUID: String
    ) -> WebDAVAutomaticSyncDecision {
        if let remotePayload, isAccountMismatch(remotePayload: remotePayload, localUID: localUID) {
            return .skip
        }

        if let remotePayload, remotePayload.updatedAt > (settings.localUpdatedAt ?? .distantPast) {
            return .download(remotePayload)
        }

        let newestKnownRemoteDate = remotePayload?.updatedAt ?? settings.lastRemoteUpdatedAt ?? .distantPast
        if (settings.localUpdatedAt ?? .distantPast) > newestKnownRemoteDate || remotePayload == nil {
            return .upload
        }

        return .skip
    }

    public func validate(
        remotePayload: WebDAVSyncPayload,
        localUID: String,
        allowingAccountMismatch: Bool
    ) throws {
        guard !allowingAccountMismatch, isAccountMismatch(remotePayload: remotePayload, localUID: localUID) else {
            return
        }
        throw WebDAVSyncError.accountMismatch(localUID: localUID, remoteUID: remotePayload.accountUID ?? "")
    }

    public func isAccountMismatch(remotePayload: WebDAVSyncPayload, localUID: String) -> Bool {
        guard let remoteUID = remotePayload.accountUID?.trimmingCharacters(in: .whitespacesAndNewlines), !remoteUID.isEmpty else {
            return false
        }
        return remoteUID != localUID
    }
}
