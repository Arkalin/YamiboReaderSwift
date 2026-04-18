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

@Test func searchKeywordKeepsAuthorAndBookName() async throws {
    #expect(MangaTitleCleaner.searchKeyword("【作者名】作品标题 - 中文百合漫画区") == "作者名 作品标题")
}
