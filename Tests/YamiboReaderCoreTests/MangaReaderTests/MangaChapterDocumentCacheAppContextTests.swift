import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Chapter Document Cache App Context", .serialized)
struct MangaReaderTestsChapterDocumentCacheAppContext {
    @Test func appContextChapterDocumentLoaderUsesSharedStoreAcrossLoaderInstances() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = MangaChapterDocumentCacheRequestCounter()
        harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ChapterAgent/Context")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=chapter")
            return MangaReaderDataTestResponse(html: """
            <html>
              <head><title>缓存章节 第1话 - 中文百合漫画区 - 百合会</title></head>
              <body>
                <div id="postmessage_9001">
                  <div class="message">
                    <img src="https://img.example.com/context-1.jpg" />
                  </div>
                </div>
              </body>
            </html>
            """)
        }

        let defaults = try #require(UserDefaults(suiteName: "manga-document-context-\(UUID().uuidString)"))
        let sessionStore = SessionStore(defaults: defaults, key: "session")
        try await sessionStore.save(
            SessionState(
                cookie: "auth=chapter",
                userAgent: "ChapterAgent/Context",
                isLoggedIn: true
            )
        )

        let documentStore = try makeTestGRDBMangaChapterDocumentStore(rootDirectory: try makeTemporaryAppContextChapterDocumentDirectory())
        let appContext = YamiboAppContext(
            sessionStore: sessionStore,
            mangaChapterDocumentStore: documentStore,
            session: harness.session
        )
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=900&page=5"))

        let firstLoader = await appContext.makeMangaChapterDocumentLoader()
        let first = try await firstLoader.loadChapterDocument(at: chapterURL)
        let secondLoader = await appContext.makeMangaChapterDocumentLoader()
        let second = try await secondLoader.loadChapterDocument(at: chapterURL)

        #expect(first.tid == "900")
        #expect(second.tid == "900")
        #expect(first.imageURLs == second.imageURLs)
        #expect(counter.value == 1)
    }
}

private final class MangaChapterDocumentCacheRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private func makeTemporaryAppContextChapterDocumentDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
