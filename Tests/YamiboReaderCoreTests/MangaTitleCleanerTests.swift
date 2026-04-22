import Testing
@testable import YamiboReaderCore

@Test func extractTidSupportsMobileAndLegacyURLs() async throws {
    #expect(MangaTitleCleaner.extractTid(from: "forum.php?mod=viewthread&tid=12345&mobile=2") == "12345")
    #expect(MangaTitleCleaner.extractTid(from: "thread-54321-1-1.html") == "54321")
}

@Test func chapterNumberMatchesSimplePatterns() async throws {
    #expect(MangaTitleCleaner.extractChapterNumber("第12话 相遇") == 12)
    #expect(MangaTitleCleaner.extractChapterNumber("第12-3话") == 12.03)
    #expect(MangaTitleCleaner.extractChapterNumber("最终话") == 999)
}

@Test func chapterNumberMatchesCircledSuffixAfterEpisodeMarker() async throws {
    #expect(MangaTitleCleaner.extractChapterNumber("第03话①") == 3.01)
    #expect(MangaTitleCleaner.extractChapterNumber("第06话②③") == 6.23)
    #expect(MangaChapterDisplayFormatter.displayNumber(rawTitle: "第03话①", chapterNumber: 3.01) == "3-1")
}

@Test func searchKeywordKeepsAuthorAndBookName() async throws {
    #expect(MangaTitleCleaner.searchKeyword("【作者名】作品标题 - 中文百合漫画区") == "作者名 作品标题")
}
