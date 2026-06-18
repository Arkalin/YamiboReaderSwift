import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Cached Chapter Document Loader", .serialized)
struct MangaReaderTestsCachedChapterDocumentLoader {
    @Test func cacheHitDoesNotCallUpstream() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=800"))
        let document = try makeLoaderDocument(tid: "800")
        let store = RecordingMangaChapterDocumentStore(initialDocuments: [
            normalizedChapterDocumentKey(chapterURL): document
        ])
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.success(try makeLoaderDocument(tid: "999"))])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let loaded = try await loader.loadChapterDocument(at: chapterURL)

        #expect(loaded == document)
        #expect(await upstream.callCount == 0)
        #expect(await store.saveCallCount == 0)
    }

    @Test func missFetchesSavesAndThenHitsCache() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=801"))
        let document = try makeLoaderDocument(tid: "801")
        let store = RecordingMangaChapterDocumentStore()
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.success(document)])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let first = try await loader.loadChapterDocument(at: chapterURL)
        let second = try await loader.loadChapterDocument(at: chapterURL)

        #expect(first == document)
        #expect(second == document)
        #expect(await upstream.callCount == 1)
        #expect(await store.saveCallCount == 1)
    }

    @Test func concurrentMissesForSameNormalizedURLShareOneUpstreamRequest() async throws {
        let firstURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=802&page=5"))
        let secondURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=802&page=1&mobile=2"))
        let document = try makeLoaderDocument(tid: "802")
        let store = RecordingMangaChapterDocumentStore()
        let upstream = RecordingCachedMangaChapterDocumentUpstream(
            results: [.success(document)],
            delayNanoseconds: 50_000_000
        )
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        async let first = loader.loadChapterDocument(at: firstURL)
        async let second = loader.loadChapterDocument(at: secondURL)

        let values = try await [first, second]

        #expect(values == [document, document])
        #expect(await upstream.callCount == 1)
        #expect(await store.saveCallCount == 1)
    }

    @Test func htmlEncodedDirectoryURLSharesNormalizedCacheKey() async throws {
        let cachedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=807&page=1&mobile=2"))
        let directoryURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=807&amp;extra=&amp;mobile=2"))
        let document = try makeLoaderDocument(tid: "807")
        let store = RecordingMangaChapterDocumentStore(initialDocuments: [
            normalizedChapterDocumentKey(cachedURL): document
        ])
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.failure(YamiboError.invalidResponse(statusCode: 404))])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let loaded = try await loader.loadChapterDocument(at: directoryURL)

        #expect(loaded == document)
        #expect(await upstream.callCount == 0)
    }

    @Test func upstreamFailureFallsBackToDocumentThatAppearsInStore() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=803"))
        let document = try makeLoaderDocument(tid: "803")
        let store = ThirdReadHitMangaChapterDocumentStore(chapterURL: chapterURL, document: document)
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.failure(YamiboError.offline)])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let loaded = try await loader.loadChapterDocument(at: chapterURL)

        #expect(loaded == document)
        #expect(await upstream.callCount == 1)
    }

    @Test func upstreamFailureWithFinalCacheMissThrowsOriginalError() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=804"))
        let store = RecordingMangaChapterDocumentStore()
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.failure(YamiboError.offline)])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.loadChapterDocument(at: chapterURL)
        }

        #expect(await upstream.callCount == 1)
        #expect(await store.saveCallCount == 0)
    }

    @Test func saveFailureDoesNotPreventReturningNetworkDocument() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=805"))
        let document = try makeLoaderDocument(tid: "805")
        let store = RecordingMangaChapterDocumentStore(failsSave: true)
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.success(document)])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let loaded = try await loader.loadChapterDocument(at: chapterURL)

        #expect(loaded == document)
        #expect(await upstream.callCount == 1)
        #expect(await store.saveCallCount == 1)
    }

    @Test func missTaskRechecksStoreBeforeCallingUpstream() async throws {
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=806"))
        let document = try makeLoaderDocument(tid: "806")
        let store = SecondReadHitMangaChapterDocumentStore(chapterURL: chapterURL, document: document)
        let upstream = RecordingCachedMangaChapterDocumentUpstream(results: [.success(try makeLoaderDocument(tid: "999"))])
        let loader = CachedMangaChapterDocumentLoader(store: store, upstream: upstream)

        let loaded = try await loader.loadChapterDocument(at: chapterURL)

        #expect(loaded == document)
        #expect(await upstream.callCount == 0)
        #expect(await store.saveCallCount == 0)
    }
}

private actor RecordingMangaChapterDocumentStore: MangaChapterDocumentPersisting {
    private var documents: [String: MangaChapterDocument]
    private let failsSave: Bool
    private(set) var saveCallCount = 0

    init(initialDocuments: [String: MangaChapterDocument] = [:], failsSave: Bool = false) {
        self.documents = initialDocuments
        self.failsSave = failsSave
    }

    func document(for chapterURL: URL) async -> MangaChapterDocument? {
        documents[normalizedChapterDocumentKey(chapterURL)]
    }

    func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws {
        saveCallCount += 1
        if failsSave {
            throw YamiboError.persistenceFailed("save failed")
        }
        documents[normalizedChapterDocumentKey(chapterURL)] = document
    }

    func clearAll() async throws {
        documents = [:]
    }
}

private actor SecondReadHitMangaChapterDocumentStore: MangaChapterDocumentPersisting {
    private let key: String
    private let output: MangaChapterDocument
    private var documentCallCount = 0
    private(set) var saveCallCount = 0

    init(chapterURL: URL, document: MangaChapterDocument) {
        self.key = normalizedChapterDocumentKey(chapterURL)
        self.output = document
    }

    func document(for chapterURL: URL) async -> MangaChapterDocument? {
        documentCallCount += 1
        guard normalizedChapterDocumentKey(chapterURL) == key, documentCallCount >= 2 else { return nil }
        return output
    }

    func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws {
        saveCallCount += 1
    }

    func clearAll() async throws {}
}

private actor ThirdReadHitMangaChapterDocumentStore: MangaChapterDocumentPersisting {
    private let key: String
    private let output: MangaChapterDocument
    private var documentCallCount = 0

    init(chapterURL: URL, document: MangaChapterDocument) {
        self.key = normalizedChapterDocumentKey(chapterURL)
        self.output = document
    }

    func document(for chapterURL: URL) async -> MangaChapterDocument? {
        documentCallCount += 1
        guard normalizedChapterDocumentKey(chapterURL) == key, documentCallCount >= 3 else { return nil }
        return output
    }

    func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws {}

    func clearAll() async throws {}
}

private actor RecordingCachedMangaChapterDocumentUpstream: MangaChapterDocumentLoading {
    private var results: [Result<MangaChapterDocument, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(results: [Result<MangaChapterDocument, Error>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let result = results.isEmpty
            ? Result<MangaChapterDocument, Error>.failure(YamiboError.unreadableBody)
            : results.removeFirst()
        return try result.get()
    }
}

private func makeLoaderDocument(tid: String) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=\(tid)")),
        imageURLs: [
            try #require(URL(string: "https://img.example.com/\(tid)-1.jpg")),
            try #require(URL(string: "https://img.example.com/\(tid)-2.jpg")),
        ]
    )
}

private func normalizedChapterDocumentKey(_ chapterURL: URL) -> String {
    MangaReaderDataSupport.normalizedChapterURL(chapterURL).absoluteString
}
