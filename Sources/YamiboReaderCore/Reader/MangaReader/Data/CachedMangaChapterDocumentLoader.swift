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
        if let cached = await store.document(for: url) {
            return cached
        }

        let key = MangaReaderDataSupport.normalizedChapterURL(url).absoluteString
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let store = store
        let upstream = upstream
        let task = Task<MangaChapterDocument, Error> {
            if let cached = await store.document(for: url) {
                return cached
            }

            do {
                let document = try await upstream.loadChapterDocument(at: url)
                try? await store.save(document, for: url)
                return document
            } catch {
                if let cached = await store.document(for: url) {
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
