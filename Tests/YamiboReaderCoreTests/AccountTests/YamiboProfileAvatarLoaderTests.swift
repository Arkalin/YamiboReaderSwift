import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("Yamibo Profile Avatar Loader", .serialized)
struct YamiboProfileAvatarLoaderTests {
    @Test func returnsNilWhenProfileHasNoAvatarURL() async throws {
        let fixture = try await makeFixture()
        let data = try await fixture.loader.avatarData(for: makeProfile(avatarURL: nil))

        #expect(data == nil)
        #expect(fixture.harness.requests.isEmpty)
    }

    @Test func sendsAuthenticatedAvatarRequestHeaders() async throws {
        let fixture = try await makeFixture()
        fixture.harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "AvatarAgent/1")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=avatar")
            #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
            return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
        }

        let data = try await fixture.loader.avatarData(for: makeProfile())

        #expect(data == Data([1, 2, 3]))
    }

    @Test func reusesMemoryCacheForSameProfileAvatar() async throws {
        let fixture = try await makeFixture()
        let counter = ProfileAvatarRequestCounter()
        fixture.harness.setHandler { _ in
            counter.increment()
            return MangaReaderDataTestResponse(data: Data([4, 5]))
        }
        let profile = makeProfile()

        let first = try await fixture.loader.avatarData(for: profile)
        let second = try await fixture.loader.avatarData(for: profile)

        #expect(first == Data([4, 5]))
        #expect(second == Data([4, 5]))
        #expect(counter.value == 1)
    }

    @Test func doesNotReuseMemoryCacheAfterAuthenticationChanges() async throws {
        let fixture = try await makeFixture()
        let counter = ProfileAvatarRequestCounter()
        fixture.harness.setHandler { _ in
            counter.increment()
            return MangaReaderDataTestResponse(data: Data([UInt8(counter.value)]))
        }
        let profile = makeProfile()

        let first = try await fixture.loader.avatarData(for: profile)
        try await fixture.sessionStore.save(SessionState(
            cookie: "auth=second-avatar",
            userAgent: "AvatarAgent/1",
            isLoggedIn: true,
            accountUID: "535977"
        ))
        let second = try await fixture.loader.avatarData(for: profile)

        #expect(first == Data([1]))
        #expect(second == Data([2]))
        #expect(counter.value == 2)
    }

    @Test func deduplicatesConcurrentRequestsForSameProfileAvatar() async throws {
        let fixture = try await makeFixture()
        let counter = ProfileAvatarRequestCounter()
        fixture.harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([6]))
        }
        let profile = makeProfile()
        let loader = fixture.loader

        async let first = loader.avatarData(for: profile)
        async let second = loader.avatarData(for: profile)

        let values = try await [first, second]

        #expect(values == [Data([6]), Data([6])])
        #expect(counter.value == 1)
    }

    @Test func mapsHTTPAndBodyErrors() async throws {
        try await expectAvatarError(statusCode: 401, data: Data([1]), expected: YamiboError.notAuthenticated)
        try await expectAvatarError(statusCode: 403, data: Data([1]), expected: YamiboError.notAuthenticated)
        try await expectAvatarError(statusCode: 500, data: Data([1]), expected: YamiboError.invalidResponse(statusCode: 500))
        try await expectAvatarError(statusCode: 200, data: Data(), expected: YamiboError.unreadableBody)
    }

    private func expectAvatarError(statusCode: Int, data: Data, expected: YamiboError) async throws {
        let fixture = try await makeFixture()
        fixture.harness.setHandler { _ in
            MangaReaderDataTestResponse(statusCode: statusCode, data: data)
        }

        await #expect(throws: expected) {
            _ = try await fixture.loader.avatarData(for: makeProfile())
        }
    }
}

private struct ProfileAvatarLoaderFixture {
    let harness: MangaReaderDataTestHarness
    let sessionStore: SessionStore
    let loader: YamiboProfileAvatarLoader
}

private func makeFixture() async throws -> ProfileAvatarLoaderFixture {
    let harness = MangaReaderDataTestHarness()
    let suiteName = "YamiboProfileAvatarLoaderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    try await sessionStore.save(SessionState(
        cookie: "auth=avatar",
        userAgent: "AvatarAgent/1",
        isLoggedIn: true,
        accountUID: "535977"
    ))
    let loader = YamiboProfileAvatarLoader(session: harness.session, sessionStore: sessionStore)
    return ProfileAvatarLoaderFixture(harness: harness, sessionStore: sessionStore, loader: loader)
}

private func makeProfile(avatarURL: URL? = URL(string: "https://bbs.yamibo.com/avatar.jpg")!) -> YamiboProfile {
    YamiboProfile(
        uid: "535977",
        username: "reader",
        userGroup: "百合幼苗",
        points: 10,
        partner: 0,
        totalPoints: 10,
        avatarURL: avatarURL
    )
}

private final class ProfileAvatarRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
