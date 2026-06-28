import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class FavoriteRowsTests: XCTestCase {
    func testMangaProgressOmitsUnrecognizedChapterNumber() throws {
        let url = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501595&mobile=2"))
        let favorite = Favorite(
            title: "漫画",
            url: url,
            mangaPageIndex: 3,
            lastChapter: "破晓之前，许我一梦泡沫",
            type: .manga
        )

        XCTAssertEqual(favoriteProgressText(for: favorite), "第 4 页")
        XCTAssertNil(favoriteMangaChapterLabel(from: favorite.lastChapter ?? ""))
    }

    func testMangaProgressIncludesRecognizedChapterNumber() throws {
        let url = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501596&mobile=2"))
        let favorite = Favorite(
            title: "漫画",
            url: url,
            mangaPageIndex: 9,
            lastChapter: "第1话 破晓之前",
            type: .manga
        )

        XCTAssertEqual(favoriteProgressText(for: favorite), "第 10 页 · 第1话")
    }
}
