import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: File Manga Directory Store")
struct MangaReaderTestsFileMangaDirectoryStore {
    @Test func savesAndLoadsDirectoryAcrossStoreInstances() async throws {
        let directory = try makeTemporaryDirectory()
        let writingStore = FileMangaDirectoryStore(baseDirectory: directory)
        let mangaDirectory = makeDirectory(name: "  作品  ", tids: ["1"])

        try await writingStore.saveDirectory(mangaDirectory)

        let readingStore = FileMangaDirectoryStore(baseDirectory: directory)
        let loaded = try await readingStore.directory(named: "作品")

        #expect(loaded?.cleanBookName == "作品")
        #expect(loaded?.chapters.map(\.tid) == ["1"])
    }

    @Test func overwritesExistingDirectoryWithSameCleanBookName() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)

        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["1"]))
        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["2", "3"]))

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(named: "作品")
        #expect(loaded?.chapters.map(\.tid) == ["2", "3"])
    }

    @Test func directoryContainingTIDLoadsAcrossStoreInstances() async throws {
        let directory = try makeTemporaryDirectory()
        let writingStore = FileMangaDirectoryStore(baseDirectory: directory)
        try await writingStore.saveDirectory(makeDirectory(name: "作品A", tids: ["1"]))
        try await writingStore.saveDirectory(makeDirectory(name: "作品B", tids: ["2", "3"]))

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(containingTID: " 2 ")

        #expect(loaded?.cleanBookName == "作品B")
        #expect(loaded?.chapters.map(\.tid) == ["2", "3"])
    }

    @Test func directoryContainingBlankTIDReturnsNil() async throws {
        let store = FileMangaDirectoryStore(baseDirectory: try makeTemporaryDirectory())
        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["1"]))

        let loaded = try await store.directory(containingTID: "   ")

        #expect(loaded == nil)
    }

    @Test func directoryContainingTIDSelfHealsInvalidIndexedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)
        try await store.saveDirectory(makeDirectory(name: "Good", tids: ["target"]))
        try await store.saveDirectory(makeDirectory(name: "Broken", tids: ["other"]))
        try corruptStoredDirectory(named: "Broken", in: directory)

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(containingTID: "target")
        let broken = try await FileMangaDirectoryStore(baseDirectory: directory).directory(named: "Broken")

        #expect(loaded?.cleanBookName == "Good")
        #expect(broken == nil)
    }

    @Test func directoryContainingTIDPrefersMostRecentlyUpdatedDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)
        try await store.saveDirectory(
            makeDirectory(
                name: "Older",
                tids: ["shared"],
                lastUpdatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        try await store.saveDirectory(
            makeDirectory(
                name: "Newer",
                tids: ["shared"],
                lastUpdatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(containingTID: "shared")

        #expect(loaded?.cleanBookName == "Newer")
    }

    @Test func deleteDirectoryIsIdempotentAndPersists() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)

        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["1"]))
        try await store.deleteDirectory(named: " 作品 ")
        try await store.deleteDirectory(named: "作品")
        try await store.deleteDirectory(named: " ")

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(named: "作品")
        #expect(loaded == nil)
    }

    @Test func corruptIndexDegradesToEmptyStore() async throws {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("index.json"))

        let store = FileMangaDirectoryStore(baseDirectory: directory)
        let loaded = try await store.directory(named: "作品")

        #expect(loaded == nil)
    }

    @Test func missingIndexedDirectoryFileSelfHealsToNil() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)
        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["1"]))

        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.lastPathComponent != "index.json" {
            try FileManager.default.removeItem(at: url)
        }

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(named: "作品")
        #expect(loaded == nil)
    }

    @Test func clearAllRemovesAllStoredDirectories() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileMangaDirectoryStore(baseDirectory: directory)
        try await store.saveDirectory(makeDirectory(name: "作品", tids: ["1"]))

        try await store.clearAll()

        let loaded = try await FileMangaDirectoryStore(baseDirectory: directory).directory(named: "作品")
        #expect(loaded == nil)
    }

    @Test func saveRejectsEmptyDirectoryName() async throws {
        let store = FileMangaDirectoryStore(baseDirectory: try makeTemporaryDirectory())

        await #expect(throws: YamiboError.self) {
            try await store.saveDirectory(makeDirectory(name: "   ", tids: ["1"]))
        }
    }
}

private func makeDirectory(name: String, tids: [String], lastUpdatedAt: Date? = nil) -> MangaDirectory {
    MangaDirectory(
        cleanBookName: name,
        strategy: .tag,
        sourceKey: "source",
        chapters: tids.map { tid in
            MangaChapter(
                tid: tid,
                rawTitle: "第\(tid)话",
                chapterNumber: Double(tid) ?? 0,
                url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
            )
        },
        lastUpdatedAt: lastUpdatedAt
    )
}

private func corruptStoredDirectory(named name: String, in directory: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    for file in files where file.lastPathComponent != "index.json" {
        guard let data = try? Data(contentsOf: file),
              String(decoding: data, as: UTF8.self).contains(name) else {
            continue
        }
        try Data("not-json".utf8).write(to: file)
        return
    }
    Issue.record("Expected stored directory file named \(name)")
}

private func makeTemporaryDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
