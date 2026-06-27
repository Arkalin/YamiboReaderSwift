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
        var request = YamiboNetworkConfiguration.makeRequest(url: avatarURL)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(sessionState.userAgent, forHTTPHeaderField: "User-Agent")
        let cookie = sessionState.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw YamiboError.invalidResponse(statusCode: nil)
            }
            guard 200 ..< 300 ~= httpResponse.statusCode else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw YamiboError.notAuthenticated
                }
                throw YamiboError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            guard !data.isEmpty else {
                throw YamiboError.unreadableBody
            }
            return data
        } catch let error as YamiboError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw YamiboError.offline
            default:
                throw YamiboError.underlying(error.localizedDescription)
            }
        } catch {
            throw YamiboError.underlying(error.localizedDescription)
        }
    }
}
