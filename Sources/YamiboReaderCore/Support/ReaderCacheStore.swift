import Foundation

public actor ReaderCacheStore {
    private static let schemaVersion = 2

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let memoryCache = NSCache<NSString, CacheBox>()
    private var index: [String: CacheThreadIndex] = [:]
    private var didLoadIndex = false

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReaderPro", isDirectory: true)
            .appendingPathComponent("reader-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reader-cache", isDirectory: true)
        self.baseDirectory = root
        self.indexURL = root.appendingPathComponent("index.json", isDirectory: false)
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func loadDocument(
        for request: ReaderPageRequest,
        contentSource: ReaderContentSource? = nil
    ) async -> ReaderPageDocument? {
        await ensureIndexLoaded()
        let identity = ReaderCacheIdentity(request: request, contentSource: contentSource)
        if let cached = memoryCache.object(forKey: identity.cacheKey as NSString)?.document {
            return cached
        }

        guard let metadata = index[identity.threadKey]?
            .variants[identity.variantKey]?
            .pages["\(identity.view)"],
              let document = try? loadDocumentFromDisk(fileName: metadata.fileName) else {
            return nil
        }

        memoryCache.setObject(CacheBox(document: document), forKey: identity.cacheKey as NSString)
        return document
    }

    public func save(_ document: ReaderPageDocument) async throws {
        await ensureIndexLoaded()
        try ensureDirectoryExists()

        let identity = ReaderCacheIdentity(document: document)
        let fileName = fileName(for: identity)
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])

        var entry = index[identity.threadKey] ?? CacheThreadIndex(threadURL: identity.threadURL)
        var variantEntry = entry.variants[identity.variantKey] ?? CacheVariantIndex()
        variantEntry.pages["\(identity.view)"] = CachePageMetadata(
            fileName: fileName,
            fetchedAt: document.fetchedAt
        )
        entry.variants[identity.variantKey] = variantEntry
        index[identity.threadKey] = entry
        try persistIndex()

        memoryCache.setObject(CacheBox(document: document), forKey: identity.cacheKey as NSString)
    }

    public func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async -> Set<Int> {
        await ensureIndexLoaded()
        let identity = ReaderCacheIdentity(threadURL: threadURL, view: 1, authorID: authorID, contentSource: contentSource)
        return Set(index[identity.threadKey]?
            .variants[identity.variantKey]?
            .pages
            .keys
            .compactMap(Int.init) ?? [])
    }

    public func deleteViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        await ensureIndexLoaded()
        let identity = ReaderCacheIdentity(threadURL: threadURL, view: 1, authorID: authorID, contentSource: contentSource)
        guard var entry = index[identity.threadKey],
              var variantEntry = entry.variants[identity.variantKey] else { return }

        for view in views {
            if let metadata = variantEntry.pages.removeValue(forKey: "\(view)") {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false))
                memoryCache.removeObject(forKey: ReaderCacheIdentity(
                    threadURL: threadURL,
                    view: view,
                    authorID: authorID,
                    contentSource: contentSource
                ).cacheKey as NSString)
            }
        }

        if variantEntry.pages.isEmpty {
            entry.variants.removeValue(forKey: identity.variantKey)
        } else {
            entry.variants[identity.variantKey] = variantEntry
        }

        if entry.variants.isEmpty {
            index.removeValue(forKey: identity.threadKey)
        } else {
            index[identity.threadKey] = entry
        }
        try persistIndex()
    }

    public func deleteAll(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        let views = await cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
        try await deleteViews(views, for: threadURL, authorID: authorID, contentSource: contentSource)
    }

    private func ensureIndexLoaded() async {
        guard !didLoadIndex else { return }
        didLoadIndex = true
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }

        guard let decoded = try? decoder.decode(CacheIndexEnvelope.self, from: data),
              decoded.version == Self.schemaVersion else {
            clearLegacyCacheDirectory()
            index = [:]
            return
        }

        index = decoded.threads
    }

    private func loadDocumentFromDisk(fileName: String) throws -> ReaderPageDocument {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try Data(contentsOf: url)
        return try decoder.decode(ReaderPageDocument.self, from: data)
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(CacheIndexEnvelope(version: Self.schemaVersion, threads: index))
        try data.write(to: indexURL, options: Data.WritingOptions.atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileName(for identity: ReaderCacheIdentity) -> String {
        "reader_\(stableIdentifier(for: identity.threadKey))_\(stableIdentifier(for: identity.variantKey))_\(identity.view).json"
    }

    private func clearLegacyCacheDirectory() {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try? fileManager.removeItem(at: baseDirectory)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        memoryCache.removeAllObjects()
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

private final class CacheBox: NSObject {
    let document: ReaderPageDocument

    init(document: ReaderPageDocument) {
        self.document = document
    }
}

private struct CacheIndexEnvelope: Codable {
    var version: Int
    var threads: [String: CacheThreadIndex]
}

private struct CacheThreadIndex: Codable {
    var threadURL: URL
    var variants: [String: CacheVariantIndex] = [:]
}

private struct CacheVariantIndex: Codable {
    var pages: [String: CachePageMetadata] = [:]
}

private struct CachePageMetadata: Codable {
    var fileName: String
    var fetchedAt: Date
}
