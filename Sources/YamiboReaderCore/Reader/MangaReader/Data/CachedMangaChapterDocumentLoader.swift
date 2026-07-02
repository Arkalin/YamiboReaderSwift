import Foundation

public actor CachedMangaChapterDocumentLoader: MangaChapterDocumentLoading {
    private let store: any MangaChapterDocumentPersisting
    private let upstream: any MangaChapterDocumentLoading
    private var inFlightTasks: [String: Task<MangaChapterDocument, Error>] = [:]

    public init(
        store: any MangaChapterDocumentPersisting,
        upstream: any MangaChapterDocumentLoading
    ) {
        self.store = store
        self.upstream = upstream
    }

    public func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        let normalizedURL = YamiboRoute.normalizedChapterURL(url)
        let tid = MangaTitleCleaner.extractTid(from: normalizedURL.absoluteString)?.mangaReaderTrimmedNonEmpty
        if let tid, let cached = await store.document(forTID: tid) {
            return cached
        }
        if let cached = await store.document(for: normalizedURL) {
            return cached
        }

        let key = tid ?? normalizedURL.absoluteString
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let store = store
        let upstream = upstream
        let task = Task<MangaChapterDocument, Error> {
            if let tid, let cached = await store.document(forTID: tid) {
                return cached
            }
            if let cached = await store.document(for: normalizedURL) {
                return cached
            }

            do {
                let document = try await upstream.loadChapterDocument(at: normalizedURL)
                try? await store.save(document)
                return document
            } catch {
                if let tid, let cached = await store.document(forTID: tid) {
                    return cached
                }
                if let cached = await store.document(for: normalizedURL) {
                    return cached
                }
                throw error
            }
        }

        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }
}
