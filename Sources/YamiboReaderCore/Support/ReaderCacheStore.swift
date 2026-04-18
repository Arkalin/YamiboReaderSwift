import Foundation

public actor ReaderCacheStore {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let memoryCache = NSCache<NSString, CacheBox>()
    private var index: [String: CacheEntryIndex] = [:]
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

    public func loadDocument(for request: ReaderPageRequest) async -> ReaderPageDocument? {
        await ensureIndexLoaded()
        let key = cacheKey(for: request)
        if let cached = memoryCache.object(forKey: key as NSString)?.document {
            return cached
        }

        guard let metadata = index[request.threadURL.absoluteString]?.pages["\(request.view)"],
              let document = try? loadDocumentFromDisk(fileName: metadata.fileName) else {
            return nil
        }

        memoryCache.setObject(CacheBox(document: document), forKey: key as NSString)
        return document
    }

    public func save(_ document: ReaderPageDocument) async throws {
        await ensureIndexLoaded()
        try ensureDirectoryExists()

        let request = ReaderPageRequest(threadURL: document.threadURL, view: document.view, authorID: document.resolvedAuthorID)
        let key = cacheKey(for: request)
        let fileName = fileName(for: document.threadURL, view: document.view)
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])

        let documentKey = document.threadURL.absoluteString
        var entry = index[documentKey] ?? CacheEntryIndex(threadURL: document.threadURL)
        entry.pages["\(document.view)"] = CachePageMetadata(
            fileName: fileName,
            fetchedAt: document.fetchedAt
        )
        index[documentKey] = entry
        try persistIndex()

        memoryCache.setObject(CacheBox(document: document), forKey: key as NSString)
    }

    public func cachedViews(for threadURL: URL) async -> Set<Int> {
        await ensureIndexLoaded()
        let entry = index[threadURL.absoluteString] ?? index[canonicalURLString(from: threadURL)]
        return Set(entry?.pages.keys.compactMap(Int.init) ?? [])
    }

    public func deleteViews(_ views: Set<Int>, for threadURL: URL) async throws {
        await ensureIndexLoaded()
        let resolvedKey = resolvedIndexKey(for: threadURL)
        guard var entry = index[resolvedKey] else { return }
        memoryCache.removeAllObjects()

        for view in views {
            if let metadata = entry.pages.removeValue(forKey: "\(view)") {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false))
            }
        }

        if entry.pages.isEmpty {
            index.removeValue(forKey: resolvedKey)
        } else {
            index[resolvedKey] = entry
        }
        try persistIndex()
    }

    public func deleteAll(for threadURL: URL) async throws {
        let views = await cachedViews(for: threadURL)
        try await deleteViews(views, for: threadURL)
    }

    private func ensureIndexLoaded() async {
        guard !didLoadIndex else { return }
        didLoadIndex = true
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([String: CacheEntryIndex].self, from: data) else {
            index = [:]
            return
        }
        index = decoded
    }

    private func loadDocumentFromDisk(fileName: String) throws -> ReaderPageDocument {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try Data(contentsOf: url)
        return try decoder.decode(ReaderPageDocument.self, from: data)
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func cacheKey(for request: ReaderPageRequest) -> String {
        "\(canonicalURLString(from: request.threadURL))#\(request.view)#\(request.authorID ?? "")"
    }

    private func fileName(for threadURL: URL, view: Int) -> String {
        "reader_\(stableIdentifier(for: canonicalURLString(from: threadURL)))_\(view).json"
    }

    private func resolvedIndexKey(for threadURL: URL) -> String {
        let canonical = canonicalURLString(from: threadURL)
        return index[canonical] == nil ? threadURL.absoluteString : canonical
    }

    private func canonicalURLString(from url: URL) -> String {
        ReaderModeDetector.canonicalThreadURL(from: url)?.absoluteString ?? url.absoluteString
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

private struct CacheEntryIndex: Codable {
    var threadURL: URL
    var pages: [String: CachePageMetadata] = [:]
}

private struct CachePageMetadata: Codable {
    var fileName: String
    var fetchedAt: Date
}
