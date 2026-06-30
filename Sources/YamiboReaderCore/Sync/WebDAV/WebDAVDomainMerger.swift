import Foundation

struct WebDAVDomainMergeResult: Equatable, Sendable {
    var payload: WebDAVSyncPayload
    var remoteContributedChanges: Bool
    var localContributedChanges: Bool
}

struct WebDAVDomainMerger: Sendable {
    func merge(
        local localPayload: WebDAVSyncPayload,
        remote remotePayload: WebDAVSyncPayload?,
        updatedAt: Date
    ) -> WebDAVDomainMergeResult {
        guard let remotePayload else {
            var uploadPayload = localPayload
            uploadPayload.version = WebDAVSyncPayload.currentVersion
            uploadPayload.updatedAt = updatedAt
            return WebDAVDomainMergeResult(
                payload: uploadPayload,
                remoteContributedChanges: false,
                localContributedChanges: true
            )
        }

        let mergedLibrary = mergeLibrary(local: localPayload.library, remote: remotePayload.library)
        let mergedAppSettings = chooseDomainValue(
            local: localPayload.appSettings,
            remote: remotePayload.appSettings,
            localDate: localPayload.appSettingsUpdatedAt,
            remoteDate: remotePayload.appSettingsUpdatedAt
        )
        let mergedAppSettingsUpdatedAt = mergedAppSettings == nil ? nil : chooseTimestamp(
            localPayload.appSettingsUpdatedAt,
            remotePayload.appSettingsUpdatedAt
        )

        let mergedPayload = WebDAVSyncPayload(
            version: WebDAVSyncPayload.currentVersion,
            updatedAt: updatedAt,
            accountUID: localPayload.accountUID ?? remotePayload.accountUID,
            library: mergedLibrary,
            appSettings: mergedAppSettings,
            appSettingsUpdatedAt: mergedAppSettingsUpdatedAt
        )

        return WebDAVDomainMergeResult(
            payload: mergedPayload,
            remoteContributedChanges: !contentEquals(mergedPayload, localPayload),
            localContributedChanges: !contentEquals(mergedPayload, remotePayload)
        )
    }

    private func mergeLibrary(
        local localSnapshot: FavoriteLibrarySnapshot,
        remote remoteSnapshot: FavoriteLibrarySnapshot
    ) -> FavoriteLibrarySnapshot {
        let localMetadata = localSnapshot.syncMetadata
        let remoteMetadata = remoteSnapshot.syncMetadata
        let favoriteListSource = shouldUseRemote(
            localDate: localMetadata.remoteFavoritesUpdatedAt,
            remoteDate: remoteMetadata.remoteFavoritesUpdatedAt
        ) ? remoteSnapshot : localSnapshot
        let visibleFavoritesByKey = favoriteMap(from: favoriteListSource.favorites)
        let visibleKeys = orderedFavoriteKeys(from: favoriteListSource.favorites)

        let localRecords = favoriteRecords(from: localSnapshot)
        let remoteRecords = favoriteRecords(from: remoteSnapshot)
        let allFavoriteKeys = Set(localRecords.keys)
            .union(remoteRecords.keys)
            .union(visibleKeys)

        let mergedCollections = mergeCollections(
            local: localSnapshot.collections,
            remote: remoteSnapshot.collections,
            localMetadata: localMetadata,
            remoteMetadata: remoteMetadata
        )
        let mergedTags = mergeTags(
            local: localSnapshot.tags,
            remote: remoteSnapshot.tags,
            localMetadata: localMetadata,
            remoteMetadata: remoteMetadata
        )
        let validCollectionIDs = Set(mergedCollections.map(\.id))
        let validTagIDs = Set(mergedTags.map(\.id))

        let mergedMetadata = mergeMetadata(
            local: localMetadata,
            remote: remoteMetadata,
            favoriteKeys: allFavoriteKeys
        )

        var mergedFavorites: [Favorite] = []
        for key in visibleKeys {
            guard var favorite = visibleFavoritesByKey[key] else { continue }
            let localRecord = localRecords[key]
            let remoteRecord = remoteRecords[key]
            let fallbackRecord = FavoriteMergeRecord(favorite: favorite)

            let readingPosition = chooseFavoriteDomain(
                local: localRecord?.readingPosition,
                remote: remoteRecord?.readingPosition,
                localDate: localMetadata.readingPositionUpdatedAtByCanonicalURL[key],
                remoteDate: remoteMetadata.readingPositionUpdatedAtByCanonicalURL[key],
                fallback: fallbackRecord.readingPosition
            )
            favorite.mangaPageIndex = readingPosition.mangaPageIndex
            favorite.lastView = readingPosition.lastView
            favorite.lastChapter = readingPosition.lastChapter
            favorite.authorID = readingPosition.authorID
            favorite.novelResumePoint = readingPosition.novelResumePoint
            favorite.novelMaxView = readingPosition.novelMaxView
            favorite.novelDocumentSurfaceProgressPercent = readingPosition.novelDocumentSurfaceProgressPercent
            favorite.lastMangaURL = readingPosition.lastMangaURL

            let lastReadAt = chooseFavoriteDomain(
                local: localRecord?.lastReadAt,
                remote: remoteRecord?.lastReadAt,
                localDate: localMetadata.lastReadAtUpdatedAtByCanonicalURL[key],
                remoteDate: remoteMetadata.lastReadAtUpdatedAtByCanonicalURL[key],
                fallback: fallbackRecord.lastReadAt
            )
            favorite.lastReadAt = lastReadAt

            let metadata = chooseFavoriteDomain(
                local: localRecord?.metadata,
                remote: remoteRecord?.metadata,
                localDate: localMetadata.favoriteMetadataUpdatedAtByCanonicalURL[key],
                remoteDate: remoteMetadata.favoriteMetadataUpdatedAtByCanonicalURL[key],
                fallback: fallbackRecord.metadata
            )
            favorite.displayName = metadata.displayName
            favorite.isHidden = metadata.isHidden
            favorite.type = metadata.type

            let organization = chooseFavoriteDomain(
                local: localRecord?.organization,
                remote: remoteRecord?.organization,
                localDate: localMetadata.favoriteOrganizationUpdatedAtByCanonicalURL[key],
                remoteDate: remoteMetadata.favoriteOrganizationUpdatedAtByCanonicalURL[key],
                fallback: fallbackRecord.organization
            )
            favorite.parentCollectionID = organization.parentCollectionID.flatMap { id in
                validCollectionIDs.contains(id) ? id : nil
            }
            favorite.manualOrder = organization.manualOrder
            favorite.tagIDs = sanitizedTagIDs(organization.tagIDs, validTagIDs: validTagIDs)
            mergedFavorites.append(favorite)
        }

        let archivedMetadata = allFavoriteKeys
            .subtracting(visibleKeys)
            .compactMap { key -> FavoriteMetadataArchiveEntry? in
                guard let canonicalURL = URL(string: key) else { return nil }
                let localRecord = localRecords[key]
                let remoteRecord = remoteRecords[key]
                guard localRecord != nil || remoteRecord != nil else { return nil }
                let fallbackRecord = localRecord ?? remoteRecord ?? FavoriteMergeRecord(canonicalThreadURL: canonicalURL)

                let readingPosition = chooseFavoriteDomain(
                    local: localRecord?.readingPosition,
                    remote: remoteRecord?.readingPosition,
                    localDate: localMetadata.readingPositionUpdatedAtByCanonicalURL[key],
                    remoteDate: remoteMetadata.readingPositionUpdatedAtByCanonicalURL[key],
                    fallback: fallbackRecord.readingPosition
                )
                let lastReadAt = chooseFavoriteDomain(
                    local: localRecord?.lastReadAt,
                    remote: remoteRecord?.lastReadAt,
                    localDate: localMetadata.lastReadAtUpdatedAtByCanonicalURL[key],
                    remoteDate: remoteMetadata.lastReadAtUpdatedAtByCanonicalURL[key],
                    fallback: fallbackRecord.lastReadAt
                )
                let metadata = chooseFavoriteDomain(
                    local: localRecord?.metadata,
                    remote: remoteRecord?.metadata,
                    localDate: localMetadata.favoriteMetadataUpdatedAtByCanonicalURL[key],
                    remoteDate: remoteMetadata.favoriteMetadataUpdatedAtByCanonicalURL[key],
                    fallback: fallbackRecord.metadata
                )
                let organization = chooseFavoriteDomain(
                    local: localRecord?.organization,
                    remote: remoteRecord?.organization,
                    localDate: localMetadata.favoriteOrganizationUpdatedAtByCanonicalURL[key],
                    remoteDate: remoteMetadata.favoriteOrganizationUpdatedAtByCanonicalURL[key],
                    fallback: fallbackRecord.organization
                )

                return FavoriteMetadataArchiveEntry(
                    canonicalThreadURL: canonicalURL,
                    displayName: metadata.displayName,
                    mangaPageIndex: readingPosition.mangaPageIndex,
                    lastView: readingPosition.lastView,
                    lastChapter: readingPosition.lastChapter,
                    authorID: readingPosition.authorID,
                    novelResumePoint: readingPosition.novelResumePoint,
                    novelMaxView: readingPosition.novelMaxView,
                    novelDocumentSurfaceProgressPercent: readingPosition.novelDocumentSurfaceProgressPercent,
                    isHidden: metadata.isHidden,
                    type: metadata.type,
                    lastMangaURL: readingPosition.lastMangaURL,
                    parentCollectionID: organization.parentCollectionID.flatMap { id in
                        validCollectionIDs.contains(id) ? id : nil
                    },
                    manualOrder: organization.manualOrder,
                    lastReadAt: lastReadAt,
                    tagIDs: sanitizedTagIDs(organization.tagIDs, validTagIDs: validTagIDs)
                )
            }
            .sorted { $0.canonicalThreadURL.absoluteString < $1.canonicalThreadURL.absoluteString }

        return FavoriteLibrarySnapshot(
            favorites: mergedFavorites,
            collections: mergedCollections,
            tags: mergedTags,
            archivedMetadata: archivedMetadata,
            syncMetadata: mergedMetadata
        )
    }

    private func mergeCollections(
        local localCollections: [FavoriteCollection],
        remote remoteCollections: [FavoriteCollection],
        localMetadata: FavoriteLibrarySyncMetadata,
        remoteMetadata: FavoriteLibrarySyncMetadata
    ) -> [FavoriteCollection] {
        let localByID = Dictionary(uniqueKeysWithValues: localCollections.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remoteCollections.map { ($0.id, $0) })
        return Set(localByID.keys)
            .union(remoteByID.keys)
            .union(localMetadata.collectionUpdatedAtByID.keys)
            .union(remoteMetadata.collectionUpdatedAtByID.keys)
            .compactMap { id in
                chooseDomainValue(
                    local: localByID[id],
                    remote: remoteByID[id],
                    localDate: localMetadata.collectionUpdatedAtByID[id],
                    remoteDate: remoteMetadata.collectionUpdatedAtByID[id]
                )
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }

    private func mergeTags(
        local localTags: [FavoriteTag],
        remote remoteTags: [FavoriteTag],
        localMetadata: FavoriteLibrarySyncMetadata,
        remoteMetadata: FavoriteLibrarySyncMetadata
    ) -> [FavoriteTag] {
        let localByID = Dictionary(uniqueKeysWithValues: localTags.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remoteTags.map { ($0.id, $0) })
        return Set(localByID.keys)
            .union(remoteByID.keys)
            .union(localMetadata.tagUpdatedAtByID.keys)
            .union(remoteMetadata.tagUpdatedAtByID.keys)
            .compactMap { id in
                chooseDomainValue(
                    local: localByID[id],
                    remote: remoteByID[id],
                    localDate: localMetadata.tagUpdatedAtByID[id],
                    remoteDate: remoteMetadata.tagUpdatedAtByID[id]
                )
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }

    private func mergeMetadata(
        local: FavoriteLibrarySyncMetadata,
        remote: FavoriteLibrarySyncMetadata,
        favoriteKeys: Set<String>
    ) -> FavoriteLibrarySyncMetadata {
        var metadata = FavoriteLibrarySyncMetadata(
            remoteFavoritesUpdatedAt: chooseTimestamp(local.remoteFavoritesUpdatedAt, remote.remoteFavoritesUpdatedAt)
        )
        for key in favoriteKeys
            .union(local.readingPositionUpdatedAtByCanonicalURL.keys)
            .union(remote.readingPositionUpdatedAtByCanonicalURL.keys) {
            if let timestamp = chooseTimestamp(
                local.readingPositionUpdatedAtByCanonicalURL[key],
                remote.readingPositionUpdatedAtByCanonicalURL[key]
            ) {
                metadata.readingPositionUpdatedAtByCanonicalURL[key] = timestamp
            }
        }
        for key in favoriteKeys
            .union(local.lastReadAtUpdatedAtByCanonicalURL.keys)
            .union(remote.lastReadAtUpdatedAtByCanonicalURL.keys) {
            if let timestamp = chooseTimestamp(
                local.lastReadAtUpdatedAtByCanonicalURL[key],
                remote.lastReadAtUpdatedAtByCanonicalURL[key]
            ) {
                metadata.lastReadAtUpdatedAtByCanonicalURL[key] = timestamp
            }
        }
        for key in favoriteKeys
            .union(local.favoriteMetadataUpdatedAtByCanonicalURL.keys)
            .union(remote.favoriteMetadataUpdatedAtByCanonicalURL.keys) {
            if let timestamp = chooseTimestamp(
                local.favoriteMetadataUpdatedAtByCanonicalURL[key],
                remote.favoriteMetadataUpdatedAtByCanonicalURL[key]
            ) {
                metadata.favoriteMetadataUpdatedAtByCanonicalURL[key] = timestamp
            }
        }
        for key in favoriteKeys
            .union(local.favoriteOrganizationUpdatedAtByCanonicalURL.keys)
            .union(remote.favoriteOrganizationUpdatedAtByCanonicalURL.keys) {
            if let timestamp = chooseTimestamp(
                local.favoriteOrganizationUpdatedAtByCanonicalURL[key],
                remote.favoriteOrganizationUpdatedAtByCanonicalURL[key]
            ) {
                metadata.favoriteOrganizationUpdatedAtByCanonicalURL[key] = timestamp
            }
        }
        for id in Set(local.collectionUpdatedAtByID.keys).union(remote.collectionUpdatedAtByID.keys) {
            if let timestamp = chooseTimestamp(local.collectionUpdatedAtByID[id], remote.collectionUpdatedAtByID[id]) {
                metadata.collectionUpdatedAtByID[id] = timestamp
            }
        }
        for id in Set(local.tagUpdatedAtByID.keys).union(remote.tagUpdatedAtByID.keys) {
            if let timestamp = chooseTimestamp(local.tagUpdatedAtByID[id], remote.tagUpdatedAtByID[id]) {
                metadata.tagUpdatedAtByID[id] = timestamp
            }
        }
        return metadata
    }

    private func favoriteRecords(from snapshot: FavoriteLibrarySnapshot) -> [String: FavoriteMergeRecord] {
        var records: [String: FavoriteMergeRecord] = [:]
        for favorite in snapshot.favorites {
            records[canonicalURLKey(for: favorite.url)] = FavoriteMergeRecord(favorite: favorite)
        }
        for archive in snapshot.archivedMetadata {
            records[canonicalURLKey(for: archive.canonicalThreadURL)] = FavoriteMergeRecord(archive: archive)
        }
        return records
    }

    private func favoriteMap(from favorites: [Favorite]) -> [String: Favorite] {
        var map: [String: Favorite] = [:]
        for favorite in favorites {
            map[canonicalURLKey(for: favorite.url)] = favorite
        }
        return map
    }

    private func orderedFavoriteKeys(from favorites: [Favorite]) -> [String] {
        var seen: Set<String> = []
        return favorites.compactMap { favorite in
            let key = canonicalURLKey(for: favorite.url)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return key
        }
    }

    private func canonicalURLKey(for url: URL) -> String {
        FavoriteLibraryURLIdentity.canonicalThreadURLKey(for: url)
    }

    private func sanitizedTagIDs(_ tagIDs: [String], validTagIDs: Set<String>) -> [String] {
        var seen: Set<String> = []
        return tagIDs.filter { tagID in
            guard validTagIDs.contains(tagID), !seen.contains(tagID) else { return false }
            seen.insert(tagID)
            return true
        }
    }

    private func chooseFavoriteDomain<T: Equatable>(
        local: T?,
        remote: T?,
        localDate: Date?,
        remoteDate: Date?,
        fallback: T
    ) -> T {
        chooseDomainValue(local: local, remote: remote, localDate: localDate, remoteDate: remoteDate) ?? fallback
    }

    private func chooseDomainValue<T>(
        local: T?,
        remote: T?,
        localDate: Date?,
        remoteDate: Date?
    ) -> T? {
        switch (local, remote) {
        case let (.some(local), .some(remote)):
            return shouldUseRemote(localDate: localDate, remoteDate: remoteDate) ? remote : local
        case let (.some(local), .none):
            if let remoteDate, remoteDate >= (localDate ?? .distantPast) {
                return nil
            }
            return local
        case let (.none, .some(remote)):
            if let localDate, localDate > (remoteDate ?? .distantPast) {
                return nil
            }
            return remote
        case (.none, .none):
            return nil
        }
    }

    private func shouldUseRemote(localDate: Date?, remoteDate: Date?) -> Bool {
        (remoteDate ?? .distantPast) >= (localDate ?? .distantPast)
    }

    private func chooseTimestamp(_ localDate: Date?, _ remoteDate: Date?) -> Date? {
        switch (localDate, remoteDate) {
        case let (.some(localDate), .some(remoteDate)):
            return remoteDate >= localDate ? remoteDate : localDate
        case let (.some(localDate), .none):
            return localDate
        case let (.none, .some(remoteDate)):
            return remoteDate
        case (.none, .none):
            return nil
        }
    }

    private func contentEquals(_ lhs: WebDAVSyncPayload, _ rhs: WebDAVSyncPayload) -> Bool {
        lhs.library == rhs.library &&
            lhs.appSettings == rhs.appSettings &&
            lhs.appSettingsUpdatedAt == rhs.appSettingsUpdatedAt
    }
}

private struct FavoriteMergeRecord: Equatable, Sendable {
    var readingPosition: FavoriteMergeReadingPosition
    var lastReadAt: Date?
    var metadata: FavoriteMergeMetadata
    var organization: FavoriteMergeOrganization

    init(favorite: Favorite) {
        readingPosition = FavoriteMergeReadingPosition(
            mangaPageIndex: favorite.mangaPageIndex,
            lastView: favorite.lastView,
            lastChapter: favorite.lastChapter,
            authorID: favorite.authorID,
            novelResumePoint: favorite.novelResumePoint,
            novelMaxView: favorite.novelMaxView,
            novelDocumentSurfaceProgressPercent: favorite.novelDocumentSurfaceProgressPercent,
            lastMangaURL: favorite.lastMangaURL
        )
        lastReadAt = favorite.lastReadAt
        metadata = FavoriteMergeMetadata(
            displayName: favorite.displayName,
            isHidden: favorite.isHidden,
            type: favorite.type
        )
        organization = FavoriteMergeOrganization(
            parentCollectionID: favorite.parentCollectionID,
            manualOrder: favorite.manualOrder,
            tagIDs: favorite.tagIDs
        )
    }

    init(archive: FavoriteMetadataArchiveEntry) {
        readingPosition = FavoriteMergeReadingPosition(
            mangaPageIndex: archive.mangaPageIndex,
            lastView: archive.lastView,
            lastChapter: archive.lastChapter,
            authorID: archive.authorID,
            novelResumePoint: archive.novelResumePoint,
            novelMaxView: archive.novelMaxView,
            novelDocumentSurfaceProgressPercent: archive.novelDocumentSurfaceProgressPercent,
            lastMangaURL: archive.lastMangaURL
        )
        lastReadAt = archive.lastReadAt
        metadata = FavoriteMergeMetadata(
            displayName: archive.displayName,
            isHidden: archive.isHidden,
            type: archive.type
        )
        organization = FavoriteMergeOrganization(
            parentCollectionID: archive.parentCollectionID,
            manualOrder: archive.manualOrder,
            tagIDs: archive.tagIDs
        )
    }

    init(canonicalThreadURL _: URL) {
        readingPosition = FavoriteMergeReadingPosition(
            mangaPageIndex: 0,
            lastView: 1,
            lastChapter: nil,
            authorID: nil,
            novelResumePoint: nil,
            novelMaxView: nil,
            novelDocumentSurfaceProgressPercent: nil,
            lastMangaURL: nil
        )
        lastReadAt = nil
        metadata = FavoriteMergeMetadata(displayName: nil, isHidden: false, type: .unknown)
        organization = FavoriteMergeOrganization(parentCollectionID: nil, manualOrder: 0, tagIDs: [])
    }
}

private struct FavoriteMergeReadingPosition: Equatable, Sendable {
    var mangaPageIndex: Int
    var lastView: Int
    var lastChapter: String?
    var authorID: String?
    var novelResumePoint: ReaderResumePoint?
    var novelMaxView: Int?
    var novelDocumentSurfaceProgressPercent: Int?
    var lastMangaURL: URL?
}

private struct FavoriteMergeMetadata: Equatable, Sendable {
    var displayName: String?
    var isHidden: Bool
    var type: FavoriteType
}

private struct FavoriteMergeOrganization: Equatable, Sendable {
    var parentCollectionID: String?
    var manualOrder: Int
    var tagIDs: [String]
}
