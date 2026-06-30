import Foundation

public protocol YamiboProfileAvatarLoading: Sendable {
    func avatarData(for profile: YamiboProfile) async throws -> Data?
}

public actor YamiboProfileAvatarLoader: YamiboProfileAvatarLoading {
    private let session: URLSession
    private let sessionStore: any SessionStoring
    private var cachedData: [RequestKey: Data] = [:]
    private var inFlightTasks: [RequestKey: Task<Data, Error>] = [:]

    public init(
        session: URLSession = YamiboNetworkConfiguration.makeSession(),
        sessionStore: any SessionStoring
    ) {
        self.session = session
        self.sessionStore = sessionStore
    }

    public func avatarData(for profile: YamiboProfile) async throws -> Data? {
        guard let avatarURL = profile.avatarURL else { return nil }

        let sessionState = await sessionStore.load()
        let key = RequestKey(
            avatarURL: avatarURL,
            profileUID: profile.uid,
            accountUID: sessionState.accountUID,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        if let data = cachedData[key] {
            return data
        }
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let urlSession = session
        let task = Task<Data, Error> {
            try await Self.fetchAvatarData(
                avatarURL: avatarURL,
                sessionState: sessionState,
                session: urlSession
            )
        }
        inFlightTasks[key] = task
        do {
            let data = try await task.value
            cachedData[key] = data
            inFlightTasks.removeValue(forKey: key)
            return data
        } catch {
            inFlightTasks.removeValue(forKey: key)
            throw error
        }
    }

    private struct RequestKey: Hashable {
        let avatarURL: URL
        let profileUID: String
        let accountUID: String?
        let cookie: String
        let userAgent: String
    }

    private static func fetchAvatarData(
        avatarURL: URL,
        sessionState: SessionState,
        session: URLSession
    ) async throws -> Data {
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        let loader = YamiboImageDataLoader(client: client)
        return try await loader.imageData(
            for: YamiboImageRequest(
                url: avatarURL,
                cacheNamespace: YamiboImageCacheNamespace.namespace(
                    cookie: sessionState.cookie,
                    userAgent: sessionState.userAgent
                )
            )
        )
    }
}
