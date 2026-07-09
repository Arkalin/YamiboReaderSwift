import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Reader Projection Store")
struct MangaReaderTestsMangaReaderProjectionStore {
    @Test func projectionsAreStoredByFullSourceIdentity() async throws {
        let store = try makeTestMangaReaderProjectionStore(rootDirectory: makeProjectionStoreRoot())
        let first = try makeProjection(tid: "800", authorID: "42", view: 1, imageName: "a")
        let second = try makeProjection(tid: "800", authorID: "84", view: 2, imageName: "b")

        try await store.save(first)
        try await store.save(second)

        #expect(await store.projection(for: first.sourceIdentity) == first)
        #expect(await store.projection(for: second.sourceIdentity) == second)
        #expect(await store.projection(for: MangaReaderProjectionSourceIdentity(
            tid: "800",
            authorID: "42",
            view: 2
        )) == nil)
    }

    @Test func clearAllRemovesTransparentProjectionNamespace() async throws {
        let store = try makeTestMangaReaderProjectionStore(rootDirectory: makeProjectionStoreRoot())
        let projection = try makeProjection(tid: "801", authorID: "42", view: 1, imageName: "a")

        try await store.save(projection)
        #expect(await store.totalDiskUsageBytes() > 0)

        try await store.clearAll()

        #expect(await store.projection(for: projection.sourceIdentity) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }
}

private func makeProjectionStoreRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func makeProjection(tid: String, authorID: String, view: Int, imageName: String) throws -> MangaReaderProjection {
    let identity = MangaReaderProjectionSourceIdentity(
        tid: tid,
        authorID: authorID,
        view: view
    )
    return MangaReaderProjection(
        tid: tid,
        ownerPostID: "post-\(tid)-\(view)",
        ownerAuthorID: authorID,
        ownerAuthorName: "作者\(authorID)",
        chapterTitle: "第\(view)话",
        imageURLs: [
            try #require(URL(string: "https://img.example.com/\(tid)-\(imageName).jpg")),
        ],
        sourceIdentity: identity,
        sourceFingerprint: "fingerprint-\(imageName)"
    )
}
