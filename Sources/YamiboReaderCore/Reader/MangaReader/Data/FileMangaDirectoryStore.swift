import Foundation

public actor FileMangaDirectoryStore: MangaDirectoryPersisting, MangaDirectoryStorageReporting, MangaDirectoryClearing {
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
            .appendingPathComponent("directories", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("manga-reader", isDirectory: true)
                .appendingPathComponent("directories", isDirectory: true)
        self.baseDirectory = root
        self.indexURL = root.appendingPathComponent("index.json", isDirectory: false)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func directory(named name: String) async throws -> MangaDirectory? {
        do {
            try ensureIndexLoaded()
            guard let key = name.mangaReaderTrimmedNonEmpty,
                  let fileName = index[key] else {
                return nil
            }

            do {
                return try loadDirectory(fileName: fileName)
            } catch {
                index.removeValue(forKey: key)
                try persistIndex()
                return nil
            }
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func directory(containingTID tid: String) async throws -> MangaDirectory? {
        do {
            try ensureIndexLoaded()
            guard let targetTID = tid.mangaReaderTrimmedNonEmpty else {
                return nil
            }

            var candidates: [MangaDirectory] = []
            var removedInvalidEntry = false
            for (name, fileName) in index {
                do {
                    let directory = try loadDirectory(fileName: fileName)
                    if directory.chapters.contains(where: { $0.tid.mangaReaderTrimmedNonEmpty == targetTID }) {
                        candidates.append(directory)
                    }
                } catch {
                    index.removeValue(forKey: name)
                    removedInvalidEntry = true
                }
            }

            if removedInvalidEntry {
                try persistIndex()
            }

            return candidates.sorted(by: directoryLookupSort).first
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func saveDirectory(_ directory: MangaDirectory) async throws {
        do {
            try ensureIndexLoaded()
            var normalized = directory
            guard let cleanBookName = directory.cleanBookName.mangaReaderTrimmedNonEmpty else {
                throw YamiboError.persistenceFailed("Directory name is empty")
            }
            normalized.cleanBookName = cleanBookName

            try ensureDirectoryExists()
            let fileName = fileName(for: cleanBookName)
            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            let data = try encoder.encode(normalized)
            try data.write(to: fileURL, options: [.atomic])
            index[cleanBookName] = fileName
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func deleteDirectory(named name: String) async throws {
        do {
            try ensureIndexLoaded()
            guard let key = name.mangaReaderTrimmedNonEmpty,
                  let fileName = index.removeValue(forKey: key) else {
                return
            }

            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func clearAll() async throws {
        do {
            try ensureIndexLoaded()
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
            index = [:]
            try persistIndex()
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        do {
            try ensureIndexLoaded()
            return index.values.reduce(0) { total, fileName in
                let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
                return total + ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        } catch {
            return 0
        }
    }

    private func ensureIndexLoaded() throws {
        guard !didLoadIndex else { return }
        didLoadIndex = true

        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let envelope = try? decoder.decode(MangaDirectoryIndexEnvelope.self, from: data),
              envelope.version == Self.schemaVersion else {
            index = [:]
            return
        }

        index = envelope.files
    }

    private func loadDirectory(fileName: String) throws -> MangaDirectory {
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(MangaDirectory.self, from: data)
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(MangaDirectoryIndexEnvelope(version: Self.schemaVersion, files: index))
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func directoryLookupSort(_ lhs: MangaDirectory, _ rhs: MangaDirectory) -> Bool {
        let leftDate = lhs.lastUpdatedAt ?? .distantPast
        let rightDate = rhs.lastUpdatedAt ?? .distantPast
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.cleanBookName.localizedStandardCompare(rhs.cleanBookName) == .orderedAscending
    }

    private func fileName(for cleanBookName: String) -> String {
        let sanitized = cleanBookName.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "_", options: .regularExpression)
        let prefix = String(sanitized.prefix(50))
        return "\(prefix)_\(stableIdentifier(for: cleanBookName)).json"
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func persistenceError(from error: Error) -> YamiboError {
        if let error = error as? YamiboError {
            return error
        }
        return YamiboError.persistenceFailed(error.localizedDescription)
    }
}

private struct MangaDirectoryIndexEnvelope: Codable {
    var version: Int
    var files: [String: String]
}
