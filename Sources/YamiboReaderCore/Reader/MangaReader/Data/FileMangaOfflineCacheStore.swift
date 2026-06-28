import CryptoKit
import Foundation

public actor FileMangaOfflineCacheStore: MangaOfflineCacheStoring {
    private static let schemaVersion = 2
    private static let supportedSchemaVersions: Set<Int> = [1, 2]

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var memberships: [String: MangaOfflineCacheMembership] = [:]
    private var images: [String: MangaOfflineCacheImageMetadata] = [:]
    private var queueWorks: [String: MangaOfflineCacheWork] = [:]
    private var queueRunState: MangaOfflineCacheQueueRunState = .paused
    private var didLoadIndex = false

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("manga-reader", isDirectory: true)
            .appendingPathComponent("offline-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("manga-reader", isDirectory: true)
                .appendingPathComponent("offline-cache", isDirectory: true)
        self.baseDirectory = root
        self.imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        self.indexURL = root.appendingPathComponent("index.json", isDirectory: false)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func membership(favoriteID: String, tid: String) async -> MangaOfflineCacheMembership? {
        await ensureIndexLoaded()
        return memberships[membershipKey(favoriteID: favoriteID, tid: tid)]
    }

    public func memberships(forFavoriteID favoriteID: String) async -> [MangaOfflineCacheMembership] {
        await ensureIndexLoaded()
        let normalizedFavoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
        return memberships.values
            .filter { $0.favoriteID == normalizedFavoriteID }
            .sorted(by: membershipSort)
    }

    public func allMemberships() async -> [MangaOfflineCacheMembership] {
        await ensureIndexLoaded()
        return memberships.values.sorted(by: membershipSort)
    }

    public func saveMembership(_ membership: MangaOfflineCacheMembership) async throws {
        await ensureIndexLoaded()
        do {
            guard membership.favoriteID.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Favorite identity is empty")
            }
            guard membership.tid.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Chapter tid is empty")
            }

            let normalized = MangaOfflineCacheMembership(
                favoriteID: membership.favoriteID,
                favoriteTitle: membership.favoriteTitle,
                favoriteURL: membership.favoriteURL,
                tid: membership.tid,
                chapterTitle: membership.chapterTitle,
                chapterURL: membership.chapterURL,
                imageURLs: membership.imageURLs,
                createdAt: membership.createdAt
            )
            memberships[membershipKey(for: normalized.id)] = normalized
            removeCompletedQueueWorkIfNeeded(for: normalized)
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMembership(favoriteID: String, tid: String) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(favoriteID: favoriteID, tid: tid)
            let canceled = queueWorks.removeValue(forKey: key)
            let removed = memberships.removeValue(forKey: key)
            let canceledImageURLs = canceled.map { $0.targetImageURLs + $0.completedImageURLs } ?? []
            if let removed {
                try removeUnreferencedImages(afterRemoving: [removed], additionalImageURLs: canceledImageURLs)
            } else {
                try removeUnreferencedImages(forImageURLs: canceledImageURLs)
                try persistIndex()
                return
            }
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMemberships(forFavoriteID favoriteID: String) async throws {
        await ensureIndexLoaded()
        do {
            let normalizedFavoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
            let canceled = queueWorks.values.filter { $0.favoriteID == normalizedFavoriteID }
            let removed = memberships.filter { $0.value.favoriteID == normalizedFavoriteID }
            queueWorks = queueWorks.filter { $0.value.favoriteID != normalizedFavoriteID }
            guard !removed.isEmpty else {
                try removeUnreferencedImages(forImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs })
                try persistIndex()
                return
            }
            for key in removed.keys {
                memberships.removeValue(forKey: key)
            }
            try removeUnreferencedImages(
                afterRemoving: Array(removed.values),
                additionalImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs }
            )
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func offlineImageData(for imageURL: URL) async -> Data? {
        await ensureIndexLoaded()
        let key = imageKey(for: imageURL)
        guard let metadata = images[key] else { return nil }

        let fileURL = imagesDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            images.removeValue(forKey: key)
            try? persistIndex()
            return nil
        }
        return data
    }

    public func saveOfflineImageData(_ data: Data, for imageURL: URL) async throws {
        await ensureIndexLoaded()
        do {
            let key = imageKey(for: imageURL)
            guard !data.isEmpty else {
                removeImage(forKey: key)
                try persistIndex()
                return
            }

            try ensureImagesDirectoryExists()
            let fileName = imageFileName(for: imageURL)
            let fileURL = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: fileURL, options: [.atomic])

            if let oldFileName = images[key]?.fileName, oldFileName != fileName {
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(oldFileName, isDirectory: false))
            }
            images[key] = MangaOfflineCacheImageMetadata(fileName: fileName, byteCount: data.count)
            removeCompletedQueueWorkReferencingImage(forKey: key)
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func diskUsageByFavorite() async -> [MangaOfflineCacheFavoriteUsage] {
        await ensureIndexLoaded()
        var usageByFavorite: [String: Int] = [:]
        var imageKeysByFavorite: [String: Set<String>] = [:]

        for membership in memberships.values {
            var keys = imageKeysByFavorite[membership.favoriteID, default: []]
            for imageURL in membership.imageURLs {
                keys.insert(imageKey(for: imageURL))
            }
            imageKeysByFavorite[membership.favoriteID] = keys
        }

        for (favoriteID, imageKeys) in imageKeysByFavorite {
            usageByFavorite[favoriteID] = imageKeys.reduce(0) { total, key in
                total + (images[key]?.byteCount ?? 0)
            }
        }

        return usageByFavorite
            .map { MangaOfflineCacheFavoriteUsage(favoriteID: $0.key, byteCount: $0.value) }
            .sorted { lhs, rhs in lhs.favoriteID.localizedStandardCompare(rhs.favoriteID) == .orderedAscending }
    }

    public func offlineCacheWork(favoriteID: String, tid: String) async -> MangaOfflineCacheWork? {
        await ensureIndexLoaded()
        return queueWorks[membershipKey(favoriteID: favoriteID, tid: tid)]
    }

    public func allOfflineCacheWorks() async -> [MangaOfflineCacheWork] {
        await ensureIndexLoaded()
        return queueWorks.values.sorted(by: queueWorkSort)
    }

    public func enqueueOfflineCacheWork(_ request: MangaOfflineCacheWorkRequest) async throws -> MangaOfflineCacheEnqueueResult {
        await ensureIndexLoaded()
        do {
            guard request.favoriteID.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Favorite identity is empty")
            }
            guard request.tid.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Chapter tid is empty")
            }

            let key = membershipKey(favoriteID: request.favoriteID, tid: request.tid)
            if let membership = memberships[key], isMembershipComplete(membership) {
                return .alreadyCached(membership)
            }
            if let work = queueWorks[key] {
                return .alreadyQueued(work)
            }

            let work = MangaOfflineCacheWork(
                request: request,
                insertionIndex: nextQueueInsertionIndex()
            )
            queueWorks[key] = work
            try persistIndex()
            return .enqueued(work)
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func updateOfflineCacheWorkProgress(
        favoriteID: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL]
    ) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(favoriteID: favoriteID, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.updatingProgress(
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func prepareOfflineCacheWorkForRun(
        favoriteID: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL]
    ) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(favoriteID: favoriteID, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.preparingForRun(
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func markOfflineCacheWorkFailed(favoriteID: String, tid: String, message: String?) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(favoriteID: favoriteID, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.markingFailed(message: message)
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func cancelOfflineCacheWork(favoriteID: String, tid: String) async throws {
        await ensureIndexLoaded()
        do {
            let canceled = queueWorks.removeValue(forKey: membershipKey(favoriteID: favoriteID, tid: tid))
            if let canceled {
                try removeUnreferencedImages(forImageURLs: canceled.targetImageURLs + canceled.completedImageURLs)
            }
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func cancelOfflineCacheWorks(forFavoriteID favoriteID: String) async throws {
        await ensureIndexLoaded()
        do {
            let normalizedFavoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
            let canceled = queueWorks.values.filter { $0.favoriteID == normalizedFavoriteID }
            queueWorks = queueWorks.filter { $0.value.favoriteID != normalizedFavoriteID }
            try removeUnreferencedImages(forImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs })
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func clearOfflineCacheQueue() async throws {
        await ensureIndexLoaded()
        do {
            queueWorks = [:]
            queueRunState = .paused
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func offlineCacheQueueRunState() async -> MangaOfflineCacheQueueRunState {
        await ensureIndexLoaded()
        return queueRunState
    }

    public func setOfflineCacheQueueRunState(_ state: MangaOfflineCacheQueueRunState) async throws {
        await ensureIndexLoaded()
        do {
            queueRunState = state
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func offlineCacheState(favoriteID: String, tid: String) async -> MangaOfflineCacheState {
        await ensureIndexLoaded()
        let key = membershipKey(favoriteID: favoriteID, tid: tid)
        if let membership = memberships[key], isMembershipComplete(membership) {
            return .cached
        }
        if queueWorks[key] != nil {
            return .caching
        }
        return .uncached
    }

    public func clearAll() async throws {
        await ensureIndexLoaded()
        do {
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
            memberships = [:]
            images = [:]
            queueWorks = [:]
            queueRunState = .paused
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        await ensureIndexLoaded()
        return images.values.reduce(0) { $0 + $1.byteCount }
    }

    private func ensureIndexLoaded() async {
        guard !didLoadIndex else { return }
        didLoadIndex = true

        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            memberships = [:]
            images = [:]
            queueWorks = [:]
            queueRunState = .paused
            return
        }

        guard
            let envelope = try? decoder.decode(MangaOfflineCacheIndexEnvelope.self, from: data),
            Self.supportedSchemaVersions.contains(envelope.version)
        else {
            clearStoreDirectory()
            memberships = [:]
            images = [:]
            queueWorks = [:]
            queueRunState = .paused
            return
        }

        memberships = envelope.memberships
        images = envelope.images
        queueWorks = envelope.queueWorks
        queueRunState = .paused
    }

    private func removeUnreferencedImages(
        afterRemoving removedMemberships: [MangaOfflineCacheMembership],
        additionalImageURLs: [URL] = []
    ) throws {
        let remainingImageKeys = Set(memberships.values.flatMap { membership in
            membership.imageURLs.map { imageKey(for: $0) }
        })
        let removedImageKeys = Set(
            removedMemberships.flatMap { membership in
                membership.imageURLs.map { imageKey(for: $0) }
            } + additionalImageURLs.map { imageKey(for: $0) }
        )

        for key in removedImageKeys where !remainingImageKeys.contains(key) {
            removeImage(forKey: key)
        }
    }

    private func removeUnreferencedImages(forImageURLs imageURLs: [URL]) throws {
        let remainingImageKeys = Set(memberships.values.flatMap { membership in
            membership.imageURLs.map { imageKey(for: $0) }
        })
        let candidateImageKeys = Set(imageURLs.map { imageKey(for: $0) })

        for key in candidateImageKeys where !remainingImageKeys.contains(key) {
            removeImage(forKey: key)
        }
    }

    private func removeImage(forKey key: String) {
        guard let metadata = images.removeValue(forKey: key) else { return }
        try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(metadata.fileName, isDirectory: false))
    }

    private func persistIndex() throws {
        try ensureBaseDirectoryExists()
        let envelope = MangaOfflineCacheIndexEnvelope(
            version: Self.schemaVersion,
            memberships: memberships,
            images: images,
            queueWorks: queueWorks,
            queueRunState: queueRunState
        )
        let data = try encoder.encode(envelope)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureBaseDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func ensureImagesDirectoryExists() throws {
        try ensureBaseDirectoryExists()
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
    }

    private func clearStoreDirectory() {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
    }

    private func isMembershipComplete(_ membership: MangaOfflineCacheMembership) -> Bool {
        guard !membership.imageURLs.isEmpty else { return false }
        return membership.imageURLs.allSatisfy { imageURL in
            let key = imageKey(for: imageURL)
            guard let metadata = images[key] else { return false }
            let fileURL = imagesDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
            return fileManager.fileExists(atPath: fileURL.path)
        }
    }

    private func removeCompletedQueueWorkIfNeeded(for membership: MangaOfflineCacheMembership) {
        guard isMembershipComplete(membership) else { return }
        queueWorks.removeValue(forKey: membershipKey(for: membership.id))
    }

    private func removeCompletedQueueWorkReferencingImage(forKey targetImageKey: String) {
        let candidateMemberships = memberships.values.filter { membership in
            membership.imageURLs.contains { imageKey(for: $0) == targetImageKey }
        }
        for membership in candidateMemberships {
            removeCompletedQueueWorkIfNeeded(for: membership)
        }
    }

    private func nextQueueInsertionIndex() -> Int {
        (queueWorks.values.map(\.insertionIndex).max() ?? 0) + 1
    }

    private func membershipKey(for id: MangaOfflineCacheMembershipID) -> String {
        membershipKey(favoriteID: id.favoriteID, tid: id.tid)
    }

    private func membershipKey(favoriteID: String, tid: String) -> String {
        "\(favoriteID.trimmingCharacters(in: .whitespacesAndNewlines))|\(tid.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func imageKey(for imageURL: URL) -> String {
        imageURL.absoluteString
    }

    private func imageFileName(for imageURL: URL) -> String {
        let rawExtension = imageURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = rawExtension.isEmpty ? "bin" : sanitizedFileExtension(rawExtension)
        return "manga_offline_image_\(sha256Hex(imageKey(for: imageURL))).\(safeExtension)"
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "", options: .regularExpression)
        return sanitized.isEmpty ? "bin" : sanitized
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func membershipSort(_ lhs: MangaOfflineCacheMembership, _ rhs: MangaOfflineCacheMembership) -> Bool {
        if lhs.favoriteID != rhs.favoriteID {
            return lhs.favoriteID.localizedStandardCompare(rhs.favoriteID) == .orderedAscending
        }
        return lhs.tid.localizedStandardCompare(rhs.tid) == .orderedAscending
    }

    private func queueWorkSort(_ lhs: MangaOfflineCacheWork, _ rhs: MangaOfflineCacheWork) -> Bool {
        if lhs.insertionIndex != rhs.insertionIndex {
            return lhs.insertionIndex < rhs.insertionIndex
        }
        if lhs.favoriteID != rhs.favoriteID {
            return lhs.favoriteID.localizedStandardCompare(rhs.favoriteID) == .orderedAscending
        }
        return lhs.tid.localizedStandardCompare(rhs.tid) == .orderedAscending
    }

    private func persistenceError(from error: Error) -> YamiboError {
        if let error = error as? YamiboError {
            return error
        }
        return YamiboError.persistenceFailed(error.localizedDescription)
    }
}

private struct MangaOfflineCacheIndexEnvelope: Codable {
    var version: Int
    var memberships: [String: MangaOfflineCacheMembership]
    var images: [String: MangaOfflineCacheImageMetadata]
    var queueWorks: [String: MangaOfflineCacheWork]
    var queueRunState: MangaOfflineCacheQueueRunState

    init(
        version: Int,
        memberships: [String: MangaOfflineCacheMembership],
        images: [String: MangaOfflineCacheImageMetadata],
        queueWorks: [String: MangaOfflineCacheWork],
        queueRunState: MangaOfflineCacheQueueRunState
    ) {
        self.version = version
        self.memberships = memberships
        self.images = images
        self.queueWorks = queueWorks
        self.queueRunState = queueRunState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        memberships = try container.decode([String: MangaOfflineCacheMembership].self, forKey: .memberships)
        images = try container.decode([String: MangaOfflineCacheImageMetadata].self, forKey: .images)
        queueWorks = try container.decodeIfPresent([String: MangaOfflineCacheWork].self, forKey: .queueWorks) ?? [:]
        queueRunState = try container.decodeIfPresent(MangaOfflineCacheQueueRunState.self, forKey: .queueRunState) ?? .paused
    }
}

private struct MangaOfflineCacheImageMetadata: Codable {
    var fileName: String
    var byteCount: Int
}
