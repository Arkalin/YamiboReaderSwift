import Foundation

public struct NovelUpdateCheckResult: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        case notCheckable
        case noCachedBaseline
        case noUpdate
        case newPage
        case contentChanged
        case structureChanged
    }

    public var status: Status
    public var message: String
    public var updatedFavorite: Favorite?

    public init(status: Status, message: String, updatedFavorite: Favorite? = nil) {
        self.status = status
        self.message = message
        self.updatedFavorite = updatedFavorite
    }
}

public struct NovelUpdateCheckService: Sendable {
    private let appContext: YamiboAppContext

    public init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    public func check(favoriteID: String) async throws -> NovelUpdateCheckResult {
        guard var favorite = await appContext.favoriteStore.favorite(id: favoriteID) else {
            return NovelUpdateCheckResult(status: .notCheckable, message: "收藏不存在")
        }
        guard favorite.type == .novel else {
            return NovelUpdateCheckResult(status: .notCheckable, message: "暂仅支持小说检查更新")
        }

        let baseline = try await resolveBaseline(for: favorite)
        guard let baseline else {
            let updated = try await updateMetadata(
                for: favorite,
                knownMaxView: nil,
                fingerprint: nil,
                status: .none,
                remoteMaxView: nil,
                currentSignature: nil
            )
            return NovelUpdateCheckResult(
                status: .noCachedBaseline,
                message: "暂无已缓存末页，无需检查",
                updatedFavorite: updated
            )
        }

        favorite = baseline.favorite
        let repository = await appContext.makeReaderRepository()
        let firstRemote = try await repository.fetchRemoteDocument(
            ReaderPageRequest(threadURL: favorite.url, view: 1, authorID: favorite.authorID)
        )
        let remoteMaxView = firstRemote.maxView

        if remoteMaxView > baseline.view {
            let signature = Self.newPageSignature(remoteMaxView: remoteMaxView)
            let status: FavoriteNovelUpdateStatus = signature == favorite.acknowledgedNovelUpdateSignature ? .none : .newPage
            let updated = try await updateMetadata(
                for: favorite,
                knownMaxView: baseline.view,
                fingerprint: baseline.fingerprint,
                status: status,
                remoteMaxView: remoteMaxView,
                currentSignature: signature
            )
            if status == .none {
                return NovelUpdateCheckResult(status: .noUpdate, message: "该更新已处理", updatedFavorite: updated)
            }
            return NovelUpdateCheckResult(status: .newPage, message: "发现新网页", updatedFavorite: updated)
        }

        if remoteMaxView < baseline.view {
            let updated = try await updateMetadata(
                for: favorite,
                knownMaxView: baseline.view,
                fingerprint: baseline.fingerprint,
                status: .structureChanged,
                remoteMaxView: remoteMaxView,
                currentSignature: nil
            )
            return NovelUpdateCheckResult(status: .structureChanged, message: "远端结构发生变化", updatedFavorite: updated)
        }

        let remoteLast = try await repository.fetchRemoteDocument(
            ReaderPageRequest(threadURL: favorite.url, view: baseline.view, authorID: favorite.authorID)
        )
        let remoteFingerprint = ReaderDocumentFingerprint.fingerprint(for: remoteLast)
        let signature = remoteFingerprint == baseline.fingerprint
            ? nil
            : Self.contentChangedSignature(knownMaxView: baseline.view, remoteFingerprint: remoteFingerprint)
        let status: FavoriteNovelUpdateStatus = if let signature, signature != favorite.acknowledgedNovelUpdateSignature {
            .contentChanged
        } else {
            .none
        }
        let updated = try await updateMetadata(
            for: favorite,
            knownMaxView: baseline.view,
            fingerprint: baseline.fingerprint,
            status: status,
            remoteMaxView: remoteMaxView,
            currentSignature: signature
        )

        if status == .contentChanged {
            return NovelUpdateCheckResult(status: .contentChanged, message: "末页内容有更新", updatedFavorite: updated)
        }
        return NovelUpdateCheckResult(status: .noUpdate, message: "已缓存末页暂无更新", updatedFavorite: updated)
    }

    private func resolveBaseline(for favorite: Favorite) async throws -> Baseline? {
        if let knownMaxView = favorite.knownMaxView,
           let cached = await cachedDocument(for: favorite, view: knownMaxView) {
            return Baseline(
                favorite: favorite,
                view: knownMaxView,
                fingerprint: favorite.knownMaxViewFingerprint ?? ReaderDocumentFingerprint.fingerprint(for: cached)
            )
        }

        if favorite.knownMaxView != nil {
            _ = try await updateMetadata(
                for: favorite,
                knownMaxView: nil,
                fingerprint: nil,
                status: .none,
                remoteMaxView: favorite.lastRemoteMaxView,
                currentSignature: nil
            )
            return nil
        }

        let views = await appContext.readerCacheStore.cachedViews(
            for: favorite.url,
            authorID: favorite.authorID,
            contentSource: contentSource(for: favorite)
        )
        guard let maxCachedView = views.max(),
              let cached = await cachedDocument(for: favorite, view: maxCachedView),
              cached.view == cached.maxView else {
            return nil
        }

        let fingerprint = ReaderDocumentFingerprint.fingerprint(for: cached)
        let updated = try await updateMetadata(
            for: favorite,
            knownMaxView: cached.maxView,
            fingerprint: fingerprint,
            status: .none,
            remoteMaxView: cached.maxView,
            currentSignature: nil
        )
        let refreshedFavorite = updated ?? favorite
        return Baseline(favorite: refreshedFavorite, view: cached.maxView, fingerprint: fingerprint)
    }

    private func cachedDocument(for favorite: Favorite, view: Int) async -> ReaderPageDocument? {
        await appContext.readerCacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: favorite.url, view: view, authorID: favorite.authorID),
            contentSource: contentSource(for: favorite)
        )
    }

    private func updateMetadata(
        for favorite: Favorite,
        knownMaxView: Int?,
        fingerprint: String?,
        status: FavoriteNovelUpdateStatus,
        remoteMaxView: Int?,
        currentSignature: String?
    ) async throws -> Favorite? {
        let favorites = try await appContext.favoriteStore.updateNovelUpdateMetadata(
            for: favorite.id,
            metadata: FavoriteNovelUpdateMetadata(
                knownMaxView: knownMaxView,
                knownMaxViewFingerprint: fingerprint,
                novelUpdateStatus: status,
                lastRemoteMaxView: remoteMaxView,
                lastUpdateCheckedAt: Date(),
                currentNovelUpdateSignature: currentSignature,
                acknowledgedNovelUpdateSignature: favorite.acknowledgedNovelUpdateSignature,
                notifiedNovelUpdateSignature: favorite.notifiedNovelUpdateSignature
            )
        )
        return favorites.first { $0.id == favorite.id }
    }

    private static func newPageSignature(remoteMaxView: Int) -> String {
        "newPage:\(remoteMaxView)"
    }

    private static func contentChangedSignature(knownMaxView: Int, remoteFingerprint: String) -> String {
        "contentChanged:\(knownMaxView):\(remoteFingerprint)"
    }

    private func contentSource(for favorite: Favorite) -> ReaderContentSource? {
        let authorID = favorite.authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return authorID.isEmpty ? .fallbackUnfilteredPage : nil
    }
}

private struct Baseline: Sendable {
    var favorite: Favorite
    var view: Int
    var fingerprint: String
}
