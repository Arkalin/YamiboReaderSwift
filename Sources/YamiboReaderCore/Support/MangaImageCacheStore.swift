import Foundation

public actor MangaImageCacheStore {
    private static let schemaVersion = 1
    public static let defaultMemoryLimitBytes = 80 * 1024 * 1024
    public static let defaultDiskLimitBytes = 512 * 1024 * 1024

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let memoryCache = NSCache<NSString, MangaImageCacheBox>()
    private let diskLimitBytes: Int
    private var index: [String: MangaImageCacheMetadata] = [:]
    private var didLoadIndex = false

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        memoryLimitBytes: Int = MangaImageCacheStore.defaultMemoryLimitBytes,
        diskLimitBytes: Int = MangaImageCacheStore.defaultDiskLimitBytes
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReaderPro", isDirectory: true)
            .appendingPathComponent("manga-image-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manga-image-cache", isDirectory: true)
        self.indexURL = self.baseDirectory.appendingPathComponent("index.json", isDirectory: false)
        self.diskLimitBytes = max(0, diskLimitBytes)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        memoryCache.totalCostLimit = max(0, memoryLimitBytes)
    }

    public func loadData(for imageURL: URL) async -> Data? {
        await ensureIndexLoaded()
        let key = cacheKey(for: imageURL)

        if let cached = memoryCache.object(forKey: key as NSString)?.data {
            markAccessed(forKey: key)
            return cached
        }

        guard let metadata = index[key] else { return nil }
        let fileURL = baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL) else {
            index.removeValue(forKey: key)
            try? persistIndex()
            return nil
        }

        memoryCache.setObject(MangaImageCacheBox(data: data), forKey: key as NSString, cost: data.count)
        markAccessed(forKey: key)
        return data
    }

    public func save(_ data: Data, for imageURL: URL) async throws {
        await ensureIndexLoaded()
        try ensureDirectoryExists()

        let key = cacheKey(for: imageURL)
        let fileName = fileName(for: imageURL)
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic])

        index[key] = MangaImageCacheMetadata(
            fileName: fileName,
            byteCount: data.count,
            lastAccessedAt: .now
        )
        memoryCache.setObject(MangaImageCacheBox(data: data), forKey: key as NSString, cost: data.count)
        try persistIndex()
        try trimDiskIfNeeded()
    }

    public func clearAll() async throws {
        await ensureIndexLoaded()
        clearCacheDirectory()
        index = [:]
        try persistIndex()
    }

    public func totalDiskUsageBytes() async -> Int {
        await ensureIndexLoaded()
        return index.values.reduce(0) { $0 + $1.byteCount }
    }

    private func ensureIndexLoaded() async {
        guard !didLoadIndex else { return }
        didLoadIndex = true

        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }

        guard
            let envelope = try? decoder.decode(MangaImageCacheIndexEnvelope.self, from: data),
            envelope.version == Self.schemaVersion
        else {
            clearCacheDirectory()
            index = [:]
            return
        }

        index = envelope.images
    }

    private func markAccessed(forKey key: String) {
        guard var metadata = index[key] else { return }
        metadata.lastAccessedAt = .now
        index[key] = metadata
        try? persistIndex()
    }

    private func trimDiskIfNeeded() throws {
        guard diskLimitBytes > 0 else {
            try removeAllIndexedFiles()
            return
        }

        var totalBytes = index.values.reduce(0) { $0 + $1.byteCount }
        guard totalBytes > diskLimitBytes else { return }

        let sortedKeys = index
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .map(\.key)

        for key in sortedKeys where totalBytes > diskLimitBytes {
            guard let metadata = index.removeValue(forKey: key) else { continue }
            let fileURL = baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
            memoryCache.removeObject(forKey: key as NSString)
            totalBytes -= metadata.byteCount
        }

        try persistIndex()
    }

    private func removeAllIndexedFiles() throws {
        for (key, metadata) in index {
            let fileURL = baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
            memoryCache.removeObject(forKey: key as NSString)
        }
        index = [:]
        try persistIndex()
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(MangaImageCacheIndexEnvelope(version: Self.schemaVersion, images: index))
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func clearCacheDirectory() {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        memoryCache.removeAllObjects()
    }

    private func cacheKey(for imageURL: URL) -> String {
        imageURL.absoluteString
    }

    private func fileName(for imageURL: URL) -> String {
        let trimmedExt = imageURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = trimmedExt.isEmpty ? "bin" : trimmedExt
        return "manga_\(stableIdentifier(for: cacheKey(for: imageURL))).\(ext)"
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

private final class MangaImageCacheBox: NSObject {
    let data: Data

    init(data: Data) {
        self.data = data
    }
}

private struct MangaImageCacheIndexEnvelope: Codable {
    var version: Int
    var images: [String: MangaImageCacheMetadata]
}

private struct MangaImageCacheMetadata: Codable {
    var fileName: String
    var byteCount: Int
    var lastAccessedAt: Date
}
