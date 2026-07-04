import Foundation

public struct YamiboRemoteFavoriteEntry: Hashable, Sendable {
    public var remoteFavoriteID: String
    public var threadURL: URL
    public var title: String?
    public var remoteOrder: Int

    public init(remoteFavoriteID: String, threadURL: URL, title: String? = nil, remoteOrder: Int = 0) {
        self.remoteFavoriteID = remoteFavoriteID
        self.threadURL = threadURL
        self.title = title
        self.remoteOrder = remoteOrder
    }
}

public struct YamiboFavoriteSyncReport: Equatable, Sendable {
    public var importedTargetIDs: [String]
    public var failedRemoteFavoriteIDs: [String]
    public var markedMissingTargetIDs: [String]
    public var uploadTargetIDs: [String]

    public init(
        importedTargetIDs: [String] = [],
        failedRemoteFavoriteIDs: [String] = [],
        markedMissingTargetIDs: [String] = [],
        uploadTargetIDs: [String] = []
    ) {
        self.importedTargetIDs = importedTargetIDs
        self.failedRemoteFavoriteIDs = failedRemoteFavoriteIDs
        self.markedMissingTargetIDs = markedMissingTargetIDs
        self.uploadTargetIDs = uploadTargetIDs
    }
}

public extension FavoriteLibraryDocument {
    @discardableResult
    mutating func syncYamiboRemoteFavorites(
        into categoryID: String,
        remoteEntries: [YamiboRemoteFavoriteEntry],
        directories: [MangaDirectory] = [],
        fallbackMangaCleanBookName: @Sendable (YamiboRemoteFavoriteEntry) -> String? = { _ in nil },
        date: Date = .now,
        probe: @Sendable (URL) async throws -> FavoriteThreadProbeResult
    ) async -> YamiboFavoriteSyncReport {
        let location = FavoriteLocation.category(categoryID)
        var importedTargetIDs: [String] = []
        var failedRemoteFavoriteIDs: [String] = []
        var seenRemoteTargetIDs: Set<String> = []
        var seenRemoteFavoriteIDs: Set<String> = []

        for remoteEntry in remoteEntries {
            do {
                let probeResult = try await probe(remoteEntry.threadURL)
                let remoteMapping = FavoriteRemoteMapping(
                    yamiboFavoriteID: remoteEntry.remoteFavoriteID,
                    yamiboRemoteOrder: remoteEntry.remoteOrder,
                    lastSeenAt: date,
                    isMarkedRemoteMissing: false
                )
                let item: FavoriteItem
                if case let .mangaTitle(_, cleanBookName) = probeResult.target {
                    item = try importMangaChapterFavorite(
                        chapterTID: YamiboThreadURLCanonicalizer.threadID(from: remoteEntry.threadURL) ?? remoteEntry.remoteFavoriteID,
                        chapterURL: remoteEntry.threadURL,
                        chapterTitle: remoteEntry.title ?? probeResult.title,
                        directories: directories,
                        fallbackCleanBookName: cleanBookName.nilIfEmpty ?? fallbackMangaCleanBookName(remoteEntry),
                        location: location,
                        remoteMapping: remoteMapping,
                        date: date
                    )
                } else {
                    item = try importThreadFavorite(
                        probeResult: probeResult,
                        location: location,
                        remoteMapping: remoteMapping,
                        date: date
                    )
                }
                seenRemoteTargetIDs.insert(item.target.id)
                seenRemoteFavoriteIDs.insert(remoteEntry.remoteFavoriteID)
                importedTargetIDs.append(item.target.id)
            } catch {
                failedRemoteFavoriteIDs.append(remoteEntry.remoteFavoriteID)
            }
        }

        var markedMissingTargetIDs: [String] = []
        for item in items where item.locations.contains(where: { $0.categoryID == categoryID }) {
            guard let mapping = item.remoteMapping,
                  let remoteID = mapping.yamiboFavoriteID,
                  !seenRemoteFavoriteIDs.contains(remoteID),
                  !seenRemoteTargetIDs.contains(item.target.id) else {
                continue
            }
            markRemoteMappingMissing(for: item.target, date: date)
            markedMissingTargetIDs.append(item.target.id)
        }

        let uploadTargetIDs = items
            .filter { item in
                item.locations.contains(where: { $0.categoryID == categoryID })
                    && item.target.threadID != nil
                    && item.remoteMapping?.yamiboFavoriteID == nil
            }
            .map(\.target.id)
            .sorted()

        return YamiboFavoriteSyncReport(
            importedTargetIDs: importedTargetIDs,
            failedRemoteFavoriteIDs: failedRemoteFavoriteIDs,
            markedMissingTargetIDs: markedMissingTargetIDs.sorted(),
            uploadTargetIDs: uploadTargetIDs
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
