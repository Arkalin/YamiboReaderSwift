import CryptoKit
import Foundation

public actor FileMangaImageDataCacheStore: MangaImageDataCaching {
    public static let defaultDiskLimitBytes = 512 * 1024 * 1024

    private static let schemaVersion = 1

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let diskLimitBytes: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var index: [String: MangaImageDataCacheMetadata] = [:]
    private var didLoadIndex = false
    private var isIndexDirty = false

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        diskLimitBytes: Int = FileMangaImageDataCacheStore.defaultDiskLimitBytes
    ) {
        self.fileManager = fileManager
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("manga-reader", isDirectory: true)
            .appendingPathComponent("image-data", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("manga-reader", isDirectory: true)
                .appendingPathComponent("image-data", isDirectory: true)
        self.baseDirectory = root
        self.indexURL = root.appendingPathComponent("index.json", isDirectory: false)
        self.diskLimitBytes = max(0, diskLimitBytes)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func data(for imageURL: URL) async -> Data? {
        await ensureIndexLoaded()
        let key = cacheKey(for: imageURL)
        guard var metadata = index[key] else { return nil }

        let fileURL = baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            removeEntry(forKey: key)
            try? persistIndexIfDirty()
            return nil
        }

        metadata.lastAccessedAt = .now
        index[key] = metadata
        isIndexDirty = true
        return data
    }

    public func save(_ data: Data, for imageURL: URL) async throws {
        await ensureIndexLoaded()
        let key = cacheKey(for: imageURL)

        guard !data.isEmpty, diskLimitBytes > 0, data.count <= diskLimitBytes else {
            removeEntry(forKey: key)
            try persistIndexIfDirty()
            return
        }

        do {
            try ensureDirectoryExists()
            let fileName = fileName(for: imageURL)
            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: fileURL, options: [.atomic])

            if let oldFileName = index[key]?.fileName, oldFileName != fileName {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(oldFileName, isDirectory: false))
            }

            index[key] = MangaImageDataCacheMetadata(
                fileName: fileName,
                byteCount: data.count,
                lastAccessedAt: .now
            )
            isIndexDirty = true
            try trimDiskIfNeeded()
            try persistIndexIfDirty()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func clearAll() async throws {
        await ensureIndexLoaded()
        do {
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
            index = [:]
            isIndexDirty = false
        } catch {
            throw persistenceError(from: error)
        }
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
            isIndexDirty = false
            return
        }

        guard
            let envelope = try? decoder.decode(MangaImageDataCacheIndexEnvelope.self, from: data),
            envelope.version == Self.schemaVersion
        else {
            clearCacheDirectory()
            index = [:]
            isIndexDirty = false
            return
        }

        index = envelope.images
        isIndexDirty = false
    }

    private func removeEntry(forKey key: String) {
        guard let metadata = index.removeValue(forKey: key) else { return }
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false))
        isIndexDirty = true
    }

    private func trimDiskIfNeeded() throws {
        var totalBytes = index.values.reduce(0) { $0 + $1.byteCount }
        guard totalBytes > diskLimitBytes else { return }

        let sortedKeys = index
            .sorted { lhs, rhs in
                if lhs.value.lastAccessedAt == rhs.value.lastAccessedAt {
                    lhs.key < rhs.key
                } else {
                    lhs.value.lastAccessedAt < rhs.value.lastAccessedAt
                }
            }
            .map(\.key)

        for key in sortedKeys where totalBytes > diskLimitBytes {
            guard let metadata = index.removeValue(forKey: key) else { continue }
            try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false))
            totalBytes -= metadata.byteCount
            isIndexDirty = true
        }
    }

    private func persistIndexIfDirty() throws {
        guard isIndexDirty else { return }
        try ensureDirectoryExists()
        let data = try encoder.encode(MangaImageDataCacheIndexEnvelope(version: Self.schemaVersion, images: index))
        try data.write(to: indexURL, options: [.atomic])
        isIndexDirty = false
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
    }

    private func cacheKey(for imageURL: URL) -> String {
        imageURL.absoluteString
    }

    private func fileName(for imageURL: URL) -> String {
        let rawExtension = imageURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = rawExtension.isEmpty ? "bin" : sanitizedFileExtension(rawExtension)
        return "manga_image_\(sha256Hex(cacheKey(for: imageURL))).\(safeExtension)"
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "", options: .regularExpression)
        return sanitized.isEmpty ? "bin" : sanitized
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistenceError(from error: Error) -> YamiboError {
        if let error = error as? YamiboError {
            return error
        }
        return YamiboError.persistenceFailed(error.localizedDescription)
    }
}

private struct MangaImageDataCacheIndexEnvelope: Codable {
    var version: Int
    var images: [String: MangaImageDataCacheMetadata]
}

private struct MangaImageDataCacheMetadata: Codable {
    var fileName: String
    var byteCount: Int
    var lastAccessedAt: Date
}
