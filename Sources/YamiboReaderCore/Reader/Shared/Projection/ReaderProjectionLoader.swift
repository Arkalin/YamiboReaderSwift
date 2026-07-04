import Foundation

public enum ReaderProjectionLoadSource: Hashable, Sendable {
    case online(sourceLoadedOnline: Bool)
    case offlineFallback(updatedAt: Date?)
}

public struct ReaderProjectionLoadedValue<Projection: Sendable, SourcePage: Sendable>: Sendable {
    public var projection: Projection
    public var sourcePage: SourcePage
    public var source: ReaderProjectionLoadSource

    public init(
        projection: Projection,
        sourcePage: SourcePage,
        source: ReaderProjectionLoadSource
    ) {
        self.projection = projection
        self.sourcePage = sourcePage
        self.source = source
    }
}

public struct ReaderProjectionPreparedSourcePage<Projection: Sendable, SourcePage: Sendable>: Sendable {
    public var projection: Projection
    public var sourcePage: SourcePage
    public var sourceLoadedOnline: Bool

    public init(
        projection: Projection,
        sourcePage: SourcePage,
        sourceLoadedOnline: Bool
    ) {
        self.projection = projection
        self.sourcePage = sourcePage
        self.sourceLoadedOnline = sourceLoadedOnline
    }
}

public enum ReaderProjectionFallbackPolicy {
    public static func isEligibleOfflineFallbackTrigger(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        guard let yamiboError = error as? YamiboError else {
            return false
        }
        switch yamiboError {
        case .offline, .underlying, .invalidResponse, .unreadableBody, .emptyHTML:
            return true
        case .parsingFailed,
             .floodControl,
             .notAuthenticated,
             .accountUIDUnavailable,
             .loginFormUnavailable,
             .loginFailed,
             .loginVerificationRequired,
             .searchCooldown,
             .persistenceFailed,
             .missingFavoriteDeleteToken,
             .missingFavoriteDeleteID,
             .favoriteDeleteFailed,
             .missingFavoriteAddToken,
             .missingFavoriteThreadID,
             .favoriteAddFailed,
             .missingForumBoardFavoriteToken,
             .forumBoardFavoriteFailed,
             .missingForumSearchToken:
            return false
        }
    }
}

public protocol ReaderProjectionLoadingStrategy: Sendable {
    associatedtype Request: Sendable
    associatedtype Identity: Hashable & Sendable
    associatedtype Projection: Sendable
    associatedtype SourcePage: Sendable

    func identity(for request: Request, ignoresCache: Bool) async throws -> Identity
    func onlineSourcePage(
        for request: Request,
        identity: Identity,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionSourcePageLoad<SourcePage>
    func offlineSourcePage(
        for request: Request
    ) async -> ReaderProjectionOfflineSourcePageLoad<Identity, SourcePage>?
    func fingerprint(sourcePage: SourcePage, identity: Identity) -> String
    func cachedProjection(for identity: Identity) async -> Projection?
    func isReusableProjection(_ projection: Projection, identity: Identity, fingerprint: String) -> Bool
    func deriveProjection(sourcePage: SourcePage, identity: Identity, fingerprint: String) throws -> Projection
    func saveProjection(_ projection: Projection) async throws
}

public struct ReaderProjectionSourcePageLoad<SourcePage: Sendable>: Sendable {
    public var sourcePage: SourcePage
    public var loadedOnline: Bool

    public init(sourcePage: SourcePage, loadedOnline: Bool) {
        self.sourcePage = sourcePage
        self.loadedOnline = loadedOnline
    }
}

public struct ReaderProjectionOfflineSourcePageLoad<Identity: Hashable & Sendable, SourcePage: Sendable>: Sendable {
    public var sourcePage: SourcePage
    public var identity: Identity
    public var updatedAt: Date?

    public init(sourcePage: SourcePage, identity: Identity, updatedAt: Date?) {
        self.sourcePage = sourcePage
        self.identity = identity
        self.updatedAt = updatedAt
    }
}

public actor ReaderProjectionLoader<Strategy: ReaderProjectionLoadingStrategy> {
    private let strategy: Strategy
    private let coalescesInFlightRequests: Bool
    private var inFlightTasks: [ReaderProjectionLoadKey<Strategy.Identity>: Task<ReaderProjectionPreparedSourcePage<Strategy.Projection, Strategy.SourcePage>, Error>] = [:]

    public init(strategy: Strategy, coalescesInFlightRequests: Bool = false) {
        self.strategy = strategy
        self.coalescesInFlightRequests = coalescesInFlightRequests
    }

    public func load(
        _ request: Strategy.Request,
        ignoresCache: Bool = false
    ) async throws -> ReaderProjectionLoadedValue<Strategy.Projection, Strategy.SourcePage> {
        do {
            let online = try await loadOnline(request, ignoresCache: ignoresCache)
            return ReaderProjectionLoadedValue(
                projection: online.projection,
                sourcePage: online.sourcePage,
                source: .online(sourceLoadedOnline: online.sourceLoadedOnline)
            )
        } catch {
            guard ReaderProjectionFallbackPolicy.isEligibleOfflineFallbackTrigger(error),
                  let fallback = await loadOfflineFallback(request) else {
                throw error
            }
            return fallback
        }
    }

    public func loadOnlineOnly(
        _ request: Strategy.Request,
        ignoresCache: Bool = false
    ) async throws -> ReaderProjectionPreparedSourcePage<Strategy.Projection, Strategy.SourcePage> {
        try await loadOnline(request, ignoresCache: ignoresCache)
    }

    private func loadOnline(
        _ request: Strategy.Request,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionPreparedSourcePage<Strategy.Projection, Strategy.SourcePage> {
        let identity = try await strategy.identity(for: request, ignoresCache: ignoresCache)
        let taskKey = ReaderProjectionLoadKey(identity: identity, ignoresCache: ignoresCache)
        if coalescesInFlightRequests, let task = inFlightTasks[taskKey] {
            return try await task.value
        }

        let task = Task<ReaderProjectionPreparedSourcePage<Strategy.Projection, Strategy.SourcePage>, Error> {
            let sourceLoad = try await strategy.onlineSourcePage(
                for: request,
                identity: identity,
                ignoresCache: ignoresCache
            )
            let fingerprint = strategy.fingerprint(sourcePage: sourceLoad.sourcePage, identity: identity)
            if !ignoresCache,
               let cached = await strategy.cachedProjection(for: identity),
               strategy.isReusableProjection(cached, identity: identity, fingerprint: fingerprint) {
                return ReaderProjectionPreparedSourcePage(
                    projection: cached,
                    sourcePage: sourceLoad.sourcePage,
                    sourceLoadedOnline: sourceLoad.loadedOnline
                )
            }

            let projection = try strategy.deriveProjection(
                sourcePage: sourceLoad.sourcePage,
                identity: identity,
                fingerprint: fingerprint
            )
            try? await strategy.saveProjection(projection)
            return ReaderProjectionPreparedSourcePage(
                projection: projection,
                sourcePage: sourceLoad.sourcePage,
                sourceLoadedOnline: sourceLoad.loadedOnline
            )
        }
        if coalescesInFlightRequests {
            inFlightTasks[taskKey] = task
        }
        defer {
            if coalescesInFlightRequests {
                inFlightTasks.removeValue(forKey: taskKey)
            }
        }
        return try await task.value
    }

    private func loadOfflineFallback(
        _ request: Strategy.Request
    ) async -> ReaderProjectionLoadedValue<Strategy.Projection, Strategy.SourcePage>? {
        guard let sourceLoad = await strategy.offlineSourcePage(for: request) else { return nil }
        let fingerprint = strategy.fingerprint(sourcePage: sourceLoad.sourcePage, identity: sourceLoad.identity)
        if let cached = await strategy.cachedProjection(for: sourceLoad.identity),
           strategy.isReusableProjection(cached, identity: sourceLoad.identity, fingerprint: fingerprint) {
            return ReaderProjectionLoadedValue(
                projection: cached,
                sourcePage: sourceLoad.sourcePage,
                source: .offlineFallback(updatedAt: sourceLoad.updatedAt)
            )
        }

        guard let projection = try? strategy.deriveProjection(
            sourcePage: sourceLoad.sourcePage,
            identity: sourceLoad.identity,
            fingerprint: fingerprint
        ) else {
            return nil
        }
        try? await strategy.saveProjection(projection)
        return ReaderProjectionLoadedValue(
            projection: projection,
            sourcePage: sourceLoad.sourcePage,
            source: .offlineFallback(updatedAt: sourceLoad.updatedAt)
        )
    }
}

private struct ReaderProjectionLoadKey<Identity: Hashable & Sendable>: Hashable, Sendable {
    var identity: Identity
    var ignoresCache: Bool
}
