import CryptoKit
import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: File Manga Chapter Document Store")
struct MangaReaderTestsFileMangaChapterDocumentStore {
    @Test func savesAndLoadsDocumentAcrossStoreInstances() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=700&page=5"))
        let document = try makeCachedDocument(tid: "700", chapterURL: chapterURL)

        try await FileMangaChapterDocumentStore(baseDirectory: directory).save(document, for: chapterURL)

        let loaded = await FileMangaChapterDocumentStore(baseDirectory: directory).document(for: chapterURL)

        #expect(loaded?.tid == "700")
        #expect(loaded?.chapterTitle == "第700话")
        #expect(loaded?.imageURLs == document.imageURLs)
    }

    @Test func normalizedURLVariantsUseSameCacheEntry() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        let writeURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=701&page=5&authorid=42"))
        let readURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=701&page=1&authorid=42&mobile=2"))

        try await store.save(try makeCachedDocument(tid: "701", chapterURL: writeURL), for: writeURL)
        let loaded = await store.document(for: readURL)

        #expect(loaded?.tid == "701")
        #expect(try cachedChapterDocumentFiles(in: directory).count == 1)
    }

    @Test func fileNameUsesSHA256AndDoesNotExposeRawURL() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=702&page=9&authorid=secret"))
        let normalizedURL = MangaReaderDataSupport.normalizedChapterURL(chapterURL)
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)

        try await store.save(try makeCachedDocument(tid: "702", chapterURL: chapterURL), for: chapterURL)

        let fileName = try #require(try cachedChapterDocumentFiles(in: directory).first?.lastPathComponent)
        #expect(fileName == "manga_chapter_document_\(chapterDocumentSHA256Hex(normalizedURL.absoluteString)).json")
        #expect(!fileName.contains("secret"))
        #expect(!fileName.contains("tid"))
    }

    @Test func saveNormalizesPersistedChapterURL() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=703&page=8&authorid=42"))
        let normalizedURL = MangaReaderDataSupport.normalizedChapterURL(chapterURL)
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)

        try await store.save(try makeCachedDocument(tid: "703", chapterURL: URL(string: "https://example.com/wrong")!), for: chapterURL)
        let loaded = await store.document(for: chapterURL)

        #expect(loaded?.chapterURL == normalizedURL)
    }

    @Test func corruptIndexClearsStoreDirectory() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let orphanURL = directory.appendingPathComponent("orphan.json", isDirectory: false)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("index.json"), options: [.atomic])
        try Data([1]).write(to: orphanURL, options: [.atomic])

        let loaded = await FileMangaChapterDocumentStore(baseDirectory: directory)
            .document(for: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=704")))

        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @Test func missingIndexedDocumentSelfHealsToMiss() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=705"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(try makeCachedDocument(tid: "705", chapterURL: chapterURL), for: chapterURL)

        for url in try cachedChapterDocumentFiles(in: directory) {
            try FileManager.default.removeItem(at: url)
        }

        #expect(await store.document(for: chapterURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func unreadableIndexedDocumentSelfHealsToMiss() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=706"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(try makeCachedDocument(tid: "706", chapterURL: chapterURL), for: chapterURL)
        let fileURL = try #require(try cachedChapterDocumentFiles(in: directory).first)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        #expect(await store.document(for: chapterURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func undecodableIndexedDocumentSelfHealsToMiss() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=707"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(try makeCachedDocument(tid: "707", chapterURL: chapterURL), for: chapterURL)
        let fileURL = try #require(try cachedChapterDocumentFiles(in: directory).first)
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        #expect(await store.document(for: chapterURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func invalidIndexedDocumentSelfHealsToMiss() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=708"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(
            MangaChapterDocument(
                tid: "708",
                chapterTitle: " ",
                chapterURL: chapterURL,
                imageURLs: []
            ),
            for: chapterURL
        )

        #expect(await store.document(for: chapterURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func mismatchedDocumentTIDSelfHealsToMiss() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=709"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(try makeCachedDocument(tid: "999", chapterURL: chapterURL), for: chapterURL)

        #expect(await store.document(for: chapterURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func clearAllDeletesStoreDirectory() async throws {
        let directory = try makeTemporaryChapterDocumentDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=710"))
        let store = FileMangaChapterDocumentStore(baseDirectory: directory)
        try await store.save(try makeCachedDocument(tid: "710", chapterURL: chapterURL), for: chapterURL)

        try await store.clearAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await store.totalDiskUsageBytes() == 0)
    }
}

private func makeCachedDocument(tid: String, chapterURL: URL) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第\(tid)话",
        chapterURL: chapterURL,
        imageURLs: [
            try #require(URL(string: "https://img.example.com/\(tid)-1.jpg")),
            try #require(URL(string: "https://img.example.com/\(tid)-2.jpg")),
        ]
    )
}

private func makeTemporaryChapterDocumentDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func cachedChapterDocumentFiles(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent != "index.json" }
}

private func chapterDocumentSHA256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
