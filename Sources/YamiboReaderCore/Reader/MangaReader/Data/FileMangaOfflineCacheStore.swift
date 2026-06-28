import CryptoKit
import Foundation

public actor FileMangaOfflineCacheStore: MangaOfflineCacheStoring {
    private static let schemaVersion = 3
    private static let supportedSchemaVersions: Set<Int> = [3]

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
    private let updateNotifier = MangaOfflineCacheUpdateNotifier()

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

    nonisolated public func offlineCacheUpdates() -> AsyncStream<Void> {
        updateNotifier.stream()
    }

    public func membership(ownerName: String, tid: String) async -> MangaOfflineCacheMembership? {
        await ensureIndexLoaded()
        return memberships[membershipKey(ownerName: ownerName, tid: tid)]
    }

    public func memberships(forOwnerName ownerName: String) async -> [MangaOfflineCacheMembership] {
        await ensureIndexLoaded()
        let normalizedOwnerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return memberships.values
            .filter { $0.ownerName == normalizedOwnerName }
            .sorted(by: membershipSort)
    }

    public func allMemberships() async -> [MangaOfflineCacheMembership] {
        await ensureIndexLoaded()
        return memberships.values.sorted(by: membershipSort)
    }

    public func saveMembership(_ membership: MangaOfflineCacheMembership) async throws {
        await ensureIndexLoaded()
        do {
            guard membership.ownerName.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Offline cache owner is empty")
            }
            guard membership.tid.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Chapter tid is empty")
            }

            let normalized = MangaOfflineCacheMembership(
                ownerName: membership.ownerName,
                tid: membership.tid,
                chapterTitle: membership.chapterTitle,
                chapterURL: membership.chapterURL,
                imageURLs: membership.imageURLs,
                createdAt: membership.createdAt
            )
            memberships[membershipKey(for: normalized.id)] = normalized
            removeCompletedQueueWorkIfNeeded(for: normalized)
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMembership(ownerName: String, tid: String) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(ownerName: ownerName, tid: tid)
            let canceled = queueWorks.removeValue(forKey: key)
            let removed = memberships.removeValue(forKey: key)
            let canceledImageURLs = canceled.map { $0.targetImageURLs + $0.completedImageURLs } ?? []
            if let removed {
                try removeUnreferencedImages(afterRemoving: [removed], additionalImageURLs: canceledImageURLs)
            } else {
                try removeUnreferencedImages(forImageURLs: canceledImageURLs)
                try persistIndex()
                notifyOfflineCacheDidChange()
                return
            }
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMemberships(forOwnerName ownerName: String) async throws {
        await ensureIndexLoaded()
        do {
            let normalizedOwnerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let canceled = queueWorks.values.filter { $0.ownerName == normalizedOwnerName }
            let removed = memberships.filter { $0.value.ownerName == normalizedOwnerName }
            queueWorks = queueWorks.filter { $0.value.ownerName != normalizedOwnerName }
            guard !removed.isEmpty else {
                try removeUnreferencedImages(forImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs })
                try persistIndex()
                notifyOfflineCacheDidChange()
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
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func renameOwner(from oldOwnerName: String, to newOwnerName: String) async throws {
        await ensureIndexLoaded()
        do {
            guard let oldOwnerName = oldOwnerName.mangaReaderTrimmedNonEmpty,
                  let newOwnerName = newOwnerName.mangaReaderTrimmedNonEmpty,
                  oldOwnerName != newOwnerName else {
                return
            }

            let targetMemberships = memberships.values.filter { $0.ownerName == oldOwnerName }
            let targetWorks = queueWorks.values.filter { $0.ownerName == oldOwnerName }
            guard !targetMemberships.isEmpty || !targetWorks.isEmpty else { return }

            memberships = memberships.filter { $0.value.ownerName != oldOwnerName }
            queueWorks = queueWorks.filter { $0.value.ownerName != oldOwnerName }

            for membership in targetMemberships {
                let renamed = MangaOfflineCacheMembership(
                    ownerName: newOwnerName,
                    tid: membership.tid,
                    chapterTitle: membership.chapterTitle,
                    chapterURL: membership.chapterURL,
                    imageURLs: membership.imageURLs,
                    createdAt: membership.createdAt
                )
                memberships[membershipKey(for: renamed.id)] = renamed
            }

            for work in targetWorks {
                let renamed = MangaOfflineCacheWork(
                    ownerName: newOwnerName,
                    tid: work.tid,
                    chapterTitle: work.chapterTitle,
                    chapterURL: work.chapterURL,
                    targetImageURLs: work.targetImageURLs,
                    completedImageURLs: work.completedImageURLs,
                    state: work.state,
                    failureMessage: work.failureMessage,
                    currentBytesPerSecond: work.currentBytesPerSecond,
                    insertionIndex: work.insertionIndex,
                    createdAt: work.createdAt,
                    updatedAt: work.updatedAt
                )
                queueWorks[membershipKey(for: renamed.id)] = renamed
            }

            try persistIndex()
            notifyOfflineCacheDidChange()
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
                notifyOfflineCacheDidChange()
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
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func diskUsageByOwner() async -> [MangaOfflineCacheOwnerUsage] {
        await ensureIndexLoaded()
        var usageByOwner: [String: Int] = [:]
        var imageKeysByOwner: [String: Set<String>] = [:]

        for membership in memberships.values {
            var keys = imageKeysByOwner[membership.ownerName, default: []]
            for imageURL in membership.imageURLs {
                keys.insert(imageKey(for: imageURL))
            }
            imageKeysByOwner[membership.ownerName] = keys
        }

        for work in queueWorks.values {
            var keys = imageKeysByOwner[work.ownerName, default: []]
            for imageURL in work.targetImageURLs + work.completedImageURLs {
                keys.insert(imageKey(for: imageURL))
            }
            imageKeysByOwner[work.ownerName] = keys
        }

        for (ownerName, imageKeys) in imageKeysByOwner {
            usageByOwner[ownerName] = imageKeys.reduce(0) { total, key in
                total + (images[key]?.byteCount ?? 0)
            }
        }

        return usageByOwner
            .map { MangaOfflineCacheOwnerUsage(ownerName: $0.key, byteCount: $0.value) }
            .sorted { lhs, rhs in lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending }
    }

    public func offlineCacheWork(ownerName: String, tid: String) async -> MangaOfflineCacheWork? {
        await ensureIndexLoaded()
        return queueWorks[membershipKey(ownerName: ownerName, tid: tid)]
    }

    public func allOfflineCacheWorks() async -> [MangaOfflineCacheWork] {
        await ensureIndexLoaded()
        return queueWorks.values.sorted(by: queueWorkSort)
    }

    public func enqueueOfflineCacheWork(_ request: MangaOfflineCacheWorkRequest) async throws -> MangaOfflineCacheEnqueueResult {
        await ensureIndexLoaded()
        do {
            guard request.ownerName.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Offline cache owner is empty")
            }
            guard request.tid.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Chapter tid is empty")
            }

            let key = membershipKey(ownerName: request.ownerName, tid: request.tid)
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
            notifyOfflineCacheDidChange()
            return .enqueued(work)
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func updateOfflineCacheWorkProgress(
        ownerName: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL],
        currentBytesPerSecond: Int? = nil
    ) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(ownerName: ownerName, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.updatingProgress(
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs,
                currentBytesPerSecond: currentBytesPerSecond
            )
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func prepareOfflineCacheWorkForRun(
        ownerName: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL]
    ) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(ownerName: ownerName, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.preparingForRun(
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func markOfflineCacheWorkFailed(ownerName: String, tid: String, message: String?) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(ownerName: ownerName, tid: tid)
            guard let work = queueWorks[key] else { return }
            queueWorks[key] = work.markingFailed(message: message)
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func cancelOfflineCacheWork(ownerName: String, tid: String) async throws {
        await ensureIndexLoaded()
        do {
            let canceled = queueWorks.removeValue(forKey: membershipKey(ownerName: ownerName, tid: tid))
            if let canceled {
                try removeUnreferencedImages(forImageURLs: canceled.targetImageURLs + canceled.completedImageURLs)
            }
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func cancelOfflineCacheWorks(forOwnerName ownerName: String) async throws {
        await ensureIndexLoaded()
        do {
            let normalizedOwnerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let canceled = queueWorks.values.filter { $0.ownerName == normalizedOwnerName }
            queueWorks = queueWorks.filter { $0.value.ownerName != normalizedOwnerName }
            try removeUnreferencedImages(forImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs })
            try persistIndex()
            notifyOfflineCacheDidChange()
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
            notifyOfflineCacheDidChange()
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
            if state == .paused {
                queueWorks = queueWorks.mapValues { work in
                    work.updatingProgress(
                        targetImageURLs: work.targetImageURLs,
                        completedImageURLs: work.completedImageURLs,
                        currentBytesPerSecond: 0
                    )
                }
            }
            try persistIndex()
            notifyOfflineCacheDidChange()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func offlineCacheState(ownerName: String, tid: String) async -> MangaOfflineCacheState {
        await ensureIndexLoaded()
        let key = membershipKey(ownerName: ownerName, tid: tid)
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
            notifyOfflineCacheDidChange()
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

        guard let envelope = try? decoder.decode(MangaOfflineCacheIndexEnvelope.self, from: data),
              Self.supportedSchemaVersions.contains(envelope.version) else {
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

    private func notifyOfflineCacheDidChange() {
        updateNotifier.notify()
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
        membershipKey(ownerName: id.ownerName, tid: id.tid)
    }

    private func membershipKey(ownerName: String, tid: String) -> String {
        "\(ownerName.trimmingCharacters(in: .whitespacesAndNewlines))|\(tid.trimmingCharacters(in: .whitespacesAndNewlines))"
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
        if lhs.ownerName != rhs.ownerName {
            return lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
        }
        return lhs.tid.localizedStandardCompare(rhs.tid) == .orderedAscending
    }

    private func queueWorkSort(_ lhs: MangaOfflineCacheWork, _ rhs: MangaOfflineCacheWork) -> Bool {
        if lhs.insertionIndex != rhs.insertionIndex {
            return lhs.insertionIndex < rhs.insertionIndex
        }
        if lhs.ownerName != rhs.ownerName {
            return lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
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

private final class MangaOfflineCacheUpdateNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func notify() {
        let activeContinuations = lock.withLock {
            Array(continuations.values)
        }
        for continuation in activeContinuations {
            continuation.yield(())
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: id)
        }
    }
}
