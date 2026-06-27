import Foundation
import Testing
@testable import YamiboReaderCore

@Test func automaticPolicyDownloadsWhenRemotePayloadIsNewerThanLocalData() throws {
    let policy = WebDAVSyncPolicyModule()
    let settings = WebDAVSyncSettings(
        baseURLString: "https://sync.example.com",
        username: "admin",
        password: "secret",
        isAutoSyncEnabled: true,
        lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
        localUpdatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let session = SessionState(cookie: "auth=1", isLoggedIn: true)
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "100",
        library: FavoriteLibrarySnapshot(favorites: [], collections: [])
    )

    #expect(policy.canSynchronizeAutomatically(settings: settings, session: session))
    #expect(policy.automaticDecision(
        settings: settings,
        remotePayload: payload,
        localUID: "100"
    ) == .download(payload))
}

@Test func automaticPolicySkipsWhenRemoteAccountMismatches() throws {
    let policy = WebDAVSyncPolicyModule()
    let settings = WebDAVSyncSettings(
        baseURLString: "https://sync.example.com",
        username: "admin",
        isAutoSyncEnabled: true,
        localUpdatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let payload = WebDAVSyncPayload(
        updatedAt: Date(timeIntervalSince1970: 2_000),
        accountUID: "remote",
        library: FavoriteLibrarySnapshot(favorites: [], collections: [])
    )

    #expect(policy.automaticDecision(
        settings: settings,
        remotePayload: payload,
        localUID: "local"
    ) == .skip)
}
