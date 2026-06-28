import CryptoKit
import Foundation

public actor FileMangaOfflineCacheStore: MangaOfflineCacheStoring {
    private static let schemaVersion = 1

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var memberships: [String: MangaOfflineCacheMembership] = [:]
    private var images: [String: MangaOfflineCacheImageMetadata] = [:]
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
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMembership(favoriteID: String, tid: String) async throws {
        await ensureIndexLoaded()
        do {
            let key = membershipKey(favoriteID: favoriteID, tid: tid)
            guard let removed = memberships.removeValue(forKey: key) else { return }
            try removeUnreferencedImages(afterRemoving: [removed])
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func removeMemberships(forFavoriteID favoriteID: String) async throws {
        await ensureIndexLoaded()
        do {
            let normalizedFavoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
            let removed = memberships.filter { $0.value.favoriteID == normalizedFavoriteID }
            guard !removed.isEmpty else { return }
            for key in removed.keys {
                memberships.removeValue(forKey: key)
            }
            try removeUnreferencedImages(afterRemoving: Array(removed.values))
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

    public func clearAll() async throws {
        await ensureIndexLoaded()
        do {
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
            memberships = [:]
            images = [:]
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
            return
        }

        guard
            let envelope = try? decoder.decode(MangaOfflineCacheIndexEnvelope.self, from: data),
            envelope.version == Self.schemaVersion
        else {
            clearStoreDirectory()
            memberships = [:]
            images = [:]
            return
        }

        memberships = envelope.memberships
        images = envelope.images
    }

    private func removeUnreferencedImages(afterRemoving removedMemberships: [MangaOfflineCacheMembership]) throws {
        let remainingImageKeys = Set(memberships.values.flatMap { membership in
            membership.imageURLs.map { imageKey(for: $0) }
        })
        let removedImageKeys = Set(removedMemberships.flatMap { membership in
            membership.imageURLs.map { imageKey(for: $0) }
        })

        for key in removedImageKeys where !remainingImageKeys.contains(key) {
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
            images: images
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
}

private struct MangaOfflineCacheImageMetadata: Codable {
    var fileName: String
    var byteCount: Int
}
