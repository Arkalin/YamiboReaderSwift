import Foundation
import Testing
@testable import YamiboReaderCore

@Test func parsePCListExtractsThreadRows() async throws {
    let html = """
    <table>
      <tr>
        <th><a href="thread-10001-1-1.html">第12话 测试章节</a></th>
        <td class="by"></td>
        <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
      </tr>
    </table>
    """

    let chapters = MangaHTMLParser.parseListHTML(html)
    #expect(chapters.count == 1)
    #expect(chapters.first?.tid == "10001")
    #expect(chapters.first?.authorUID == "77")
    #expect(chapters.first?.chapterNumber == 12)
}

@Test func favoriteParserKeepsOnlyThreadLinks() async throws {
    let html = #"""
    <ul class="sclist">
      <li>
        <a class="mdel" href="home.php?mod=spacecp&ac=favorite&op=delete&favid=456">删除</a>
        <a href="forum.php?mod=viewthread&tid=88&mobile=2">作品 A</a>
      </li>
      <li>
        <a href="home.php?mod=space">不是作品</a>
      </li>
    </ul>
    """#

    let favorites = FavoriteHTMLParser.parseFavorites(from: html)
    #expect(favorites.count == 1)
    #expect(favorites.first?.title == "作品 A")
    #expect(favorites.first?.remoteFavoriteID == "456")
}

@Test func favoriteParserKeepsFavoriteWhenDeleteLinkIsMissing() async throws {
    let html = #"""
    <ul class="sclist">
      <li>
        <a href="forum.php?mod=viewthread&tid=99&mobile=2">作品 B</a>
      </li>
    </ul>
    """#

    let favorites = FavoriteHTMLParser.parseFavorites(from: html)
    #expect(favorites.count == 1)
    #expect(favorites.first?.title == "作品 B")
    #expect(favorites.first?.remoteFavoriteID == nil)
}
