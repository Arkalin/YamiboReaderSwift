import CryptoKit
import Foundation

public actor FileMangaChapterDocumentStore: MangaChapterDocumentPersisting, MangaChapterDocumentStorageReporting {
    private static let schemaVersion = 1

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var index: [String: String] = [:]
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
            .appendingPathComponent("chapter-documents", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("manga-reader", isDirectory: true)
                .appendingPathComponent("chapter-documents", isDirectory: true)
        self.baseDirectory = root
        self.indexURL = root.appendingPathComponent("index.json", isDirectory: false)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func document(for chapterURL: URL) async -> MangaChapterDocument? {
        await ensureIndexLoaded()

        let normalizedURL = MangaReaderDataSupport.normalizedChapterURL(chapterURL)
        let key = cacheKey(for: normalizedURL)
        guard let fileName = index[key] else { return nil }

        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? decoder.decode(MangaChapterDocument.self, from: data),
              isValid(document, for: normalizedURL) else {
            removeEntry(forKey: key)
            try? persistIndex()
            return nil
        }

        return document
    }

    public func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws {
        await ensureIndexLoaded()

        let normalizedURL = MangaReaderDataSupport.normalizedChapterURL(chapterURL)
        let key = cacheKey(for: normalizedURL)
        var normalizedDocument = document
        normalizedDocument.chapterURL = normalizedURL

        do {
            try ensureDirectoryExists()
            let fileName = fileName(for: normalizedURL)
            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            let data = try encoder.encode(normalizedDocument)
            try data.write(to: fileURL, options: [.atomic])

            if let oldFileName = index[key], oldFileName != fileName {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(oldFileName, isDirectory: false))
            }

            index[key] = fileName
            try persistIndex()
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
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        await ensureIndexLoaded()
        return index.values.reduce(0) { total, fileName in
            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            return total + ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
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
            let envelope = try? decoder.decode(MangaChapterDocumentIndexEnvelope.self, from: data),
            envelope.version == Self.schemaVersion
        else {
            clearStoreDirectory()
            index = [:]
            return
        }

        index = envelope.files
    }

    private func removeEntry(forKey key: String) {
        guard let fileName = index.removeValue(forKey: key) else { return }
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(fileName, isDirectory: false))
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(MangaChapterDocumentIndexEnvelope(version: Self.schemaVersion, files: index))
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func clearStoreDirectory() {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
    }

    private func isValid(_ document: MangaChapterDocument, for normalizedURL: URL) -> Bool {
        guard document.tid.mangaReaderTrimmedNonEmpty != nil,
              document.chapterTitle.mangaReaderTrimmedNonEmpty != nil,
              !document.imageURLs.isEmpty else {
            return false
        }

        guard let urlTid = MangaTitleCleaner.extractTid(from: normalizedURL.absoluteString)?.mangaReaderTrimmedNonEmpty else {
            return true
        }
        return document.tid.mangaReaderTrimmedNonEmpty == urlTid
    }

    private func cacheKey(for normalizedURL: URL) -> String {
        normalizedURL.absoluteString
    }

    private func fileName(for normalizedURL: URL) -> String {
        "manga_chapter_document_\(sha256Hex(cacheKey(for: normalizedURL))).json"
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

private struct MangaChapterDocumentIndexEnvelope: Codable {
    var version: Int
    var files: [String: String]
}
