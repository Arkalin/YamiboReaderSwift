import Foundation

public actor MangaDirectoryStore {
    private static let schemaVersion = 1

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let indexURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var index: [String: String] = [:]
    private var didLoadIndex = false
    private var lastSearchAt: Date?

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReaderPro", isDirectory: true)
            .appendingPathComponent("manga-directory", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manga-directory", isDirectory: true)
        self.indexURL = self.baseDirectory.appendingPathComponent("index.json", isDirectory: false)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func initializeDirectory(
        currentURL: URL,
        rawTitle: String,
        html: String
    ) async throws -> MangaDirectory {
        await ensureIndexLoaded()

        let tid = MangaTitleCleaner.extractTid(from: currentURL.absoluteString) ?? ""
        let existingByTID = await directory(containingTID: tid)
        let cleanName = existingByTID?.cleanBookName ?? MangaTitleCleaner.cleanBookName(rawTitle)
        if var existing = await directory(named: cleanName) {
            let gathered = initialGatheredChapters(currentURL: currentURL, rawTitle: rawTitle, html: html)
            let merged = mergeAndSortChapters(existing.chapters, gathered)
            let resolvedStrategy: MangaDirectoryStrategy
            if existing.strategy == .pendingSearch, gathered.count > 1 {
                resolvedStrategy = .links
            } else {
                resolvedStrategy = existing.strategy
            }
            existing.chapters = merged
            existing.strategy = resolvedStrategy
            try saveDirectory(existing)
            return existing
        }

        let tagIDs = MangaHTMLParser.findTagIDsMobile(in: html)
        let gathered = initialGatheredChapters(currentURL: currentURL, rawTitle: rawTitle, html: html)
        let strategy: MangaDirectoryStrategy
        let sourceKey: String
        if !tagIDs.isEmpty {
            strategy = .tag
            sourceKey = tagIDs.joined(separator: ",")
        } else if gathered.count > 1 {
            strategy = .links
            sourceKey = cleanName
        } else {
            strategy = .pendingSearch
            sourceKey = cleanName
        }

        let directory = MangaDirectory(
            cleanBookName: cleanName,
            strategy: strategy,
            sourceKey: sourceKey,
            chapters: mergeAndSortChapters([], gathered),
            lastUpdatedAt: nil,
            searchKeyword: nil
        )
        try saveDirectory(directory)
        return directory
    }

    public func updateDirectory(
        _ currentDirectory: MangaDirectory,
        currentTID: String? = nil,
        isForcedSearch: Bool = false,
        using repository: MangaRepository
    ) async throws -> MangaDirectoryUpdateResult {
        let latest = await directory(named: currentDirectory.cleanBookName) ?? currentDirectory
        let keyword = latest.searchKeyword ?? MangaTitleCleaner.searchKeyword(latest.chapters.first(where: { $0.tid == currentTID })?.rawTitle ?? latest.cleanBookName)

        var chapters: [MangaChapter] = []
        var searchPerformed = false

        if latest.strategy == .tag, !isForcedSearch {
            let tagIDs = latest.sourceKey.split(separator: ",").map(String.init)
            chapters = try await repository.fetchTagDirectory(tagIDs: tagIDs)
            if chapters.isEmpty {
                searchPerformed = true
                chapters = try await performSearch(keyword: keyword, using: repository)
            }
        } else {
            searchPerformed = true
            chapters = try await performSearch(keyword: keyword, using: repository)
        }

        var updated = latest
        updated.chapters = mergeAndSortChapters(latest.chapters, chapters)
        updated.lastUpdatedAt = .now
        if updated.strategy != .tag {
            updated.strategy = .searched
        }
        try saveDirectory(updated)
        return MangaDirectoryUpdateResult(directory: updated, searchPerformed: searchPerformed)
    }

    public func renameAndMergeDirectory(
        _ currentDirectory: MangaDirectory,
        newCleanName: String,
        newSearchKeyword: String
    ) async throws -> MangaDirectory {
        let resolvedName = newCleanName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKeyword = newSearchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let latest = await directory(named: currentDirectory.cleanBookName) ?? currentDirectory

        if latest.cleanBookName == resolvedName {
            var updated = latest
            updated.searchKeyword = resolvedKeyword
            updated.lastUpdatedAt = .now
            try saveDirectory(updated)
            return updated
        }

        let target = await directory(named: resolvedName)
        let merged = MangaDirectory(
            cleanBookName: resolvedName,
            strategy: target?.strategy ?? latest.strategy,
            sourceKey: target?.sourceKey ?? (latest.strategy == .tag ? latest.sourceKey : resolvedName),
            chapters: mergeAndSortChapters(target?.chapters ?? [], latest.chapters),
            lastUpdatedAt: .now,
            searchKeyword: resolvedKeyword
        )
        try saveDirectory(merged)
        _ = try await deleteDirectory(named: latest.cleanBookName)
        return merged
    }

    public func directory(named name: String) async -> MangaDirectory? {
        await ensureIndexLoaded()
        guard let fileName = index[name] else { return nil }
        return try? loadDirectory(fileName: fileName)
    }

    public func directory(containingTID tid: String) async -> MangaDirectory? {
        let all = await allDirectories()
        return all.first(where: { $0.chapters.contains(where: { $0.tid == tid }) })
    }

    public func allDirectories() async -> [MangaDirectory] {
        await ensureIndexLoaded()
        return index.keys.compactMap { name in
            guard let fileName = index[name] else { return nil }
            return try? loadDirectory(fileName: fileName)
        }
        .sorted { ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast) }
    }

    @discardableResult
    public func deleteDirectory(named name: String) async throws -> Bool {
        await ensureIndexLoaded()
        guard let fileName = index.removeValue(forKey: name) else {
            return false
        }
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        try? fileManager.removeItem(at: fileURL)
        try persistIndex()
        return true
    }

    public func clearAll() async throws {
        await ensureIndexLoaded()
        for (_, fileName) in index {
            let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            try? fileManager.removeItem(at: url)
        }
        index = [:]
        try persistIndex()
    }

    private func performSearch(keyword: String, using repository: MangaRepository) async throws -> [MangaChapter] {
        let now = Date()
        if let lastSearchAt, now.timeIntervalSince(lastSearchAt) < 20 {
            throw YamiboError.searchCooldown(seconds: 20)
        }
        lastSearchAt = now
        return try await repository.searchAll(keyword: keyword)
    }

    private func initialGatheredChapters(currentURL: URL, rawTitle: String, html: String) -> [MangaChapter] {
        let current = MangaChapter(
            tid: MangaTitleCleaner.extractTid(from: currentURL.absoluteString) ?? UUID().uuidString,
            rawTitle: MangaTitleCleaner.cleanThreadTitle(rawTitle),
            chapterNumber: MangaTitleCleaner.extractChapterNumber(rawTitle),
            url: YamiboRoute.thread(url: currentURL, page: 1, authorID: nil).url
        )
        return MangaHTMLParser.extractSamePageLinks(from: html) + [current]
    }

    private func mergeAndSortChapters(_ lhs: [MangaChapter], _ rhs: [MangaChapter]) -> [MangaChapter] {
        var mergedByID: [String: MangaChapter] = [:]
        for chapter in lhs + rhs {
            mergedByID[chapter.tid] = chapter
        }
        var sorted = mergedByID.values.sorted {
            ($0.tid.toInt64OrZero, $0.publishTime ?? .distantPast, $0.rawTitle) < ($1.tid.toInt64OrZero, $1.publishTime ?? .distantPast, $1.rawTitle)
        }

        var previousNumber = 0.0
        for index in sorted.indices {
            guard sorted[index].chapterNumber == 0 else {
                previousNumber = sorted[index].chapterNumber
                continue
            }

            let candidates = MangaTitleCleaner.extractAllPossibleNumbers(from: sorted[index].rawTitle)
            if let next = candidates.first(where: { $0 >= previousNumber }) {
                sorted[index].chapterNumber = next
                previousNumber = next
            } else if previousNumber > 0 {
                previousNumber += 0.1
                sorted[index].chapterNumber = previousNumber
            }
        }
        return sorted
    }

    private func ensureIndexLoaded() async {
        guard !didLoadIndex else { return }
        didLoadIndex = true

        guard let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }

        guard
            let envelope = try? decoder.decode(MangaDirectoryIndexEnvelope.self, from: data),
            envelope.version == Self.schemaVersion
        else {
            index = [:]
            return
        }

        index = envelope.files
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func saveDirectory(_ directory: MangaDirectory) throws {
        try ensureDirectoryExists()
        let fileName = fileName(for: directory.cleanBookName)
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try encoder.encode(directory)
        try data.write(to: fileURL, options: .atomic)
        index[directory.cleanBookName] = fileName
        try persistIndex()
    }

    private func loadDirectory(fileName: String) throws -> MangaDirectory {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try Data(contentsOf: url)
        return try decoder.decode(MangaDirectory.self, from: data)
    }

    private func persistIndex() throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(MangaDirectoryIndexEnvelope(version: Self.schemaVersion, files: index))
        try data.write(to: indexURL, options: .atomic)
    }

    private func fileName(for cleanName: String) -> String {
        let sanitized = cleanName.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "_", options: .regularExpression)
        let prefix = String(sanitized.prefix(50))
        return "\(prefix)_\(stableIdentifier(for: cleanName)).json"
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

private struct MangaDirectoryIndexEnvelope: Codable {
    var version: Int
    var files: [String: String]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var toInt64OrZero: Int64 {
        Int64(self) ?? 0
    }
}
