import XCTest
@testable import YamiboReaderUI

final class ClipboardForumLinkDetectorTests: XCTestCase {
    func testExtractsForumLinksFromClipboardText() throws {
        var detector = ClipboardForumLinkDetector()

        let httpsURL = try XCTUnwrap(detector.promptURL(from: "打开 https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2 看看"))
        XCTAssertEqual(httpsURL.absoluteString, "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2")

        _ = detector.promptURL(from: nil)
        let httpURL = try XCTUnwrap(detector.promptURL(from: "http://bbs.yamibo.com/thread-123-1-1.html"))
        XCTAssertEqual(httpURL.absoluteString, "http://bbs.yamibo.com/thread-123-1-1.html")

        _ = detector.promptURL(from: "普通文本")
        let bareURL = try XCTUnwrap(detector.promptURL(from: "复制：bbs.yamibo.com/forum.php?mod=viewthread&tid=456。"))
        XCTAssertEqual(bareURL.absoluteString, "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=456")
    }

    func testRejectsNonForumHosts() {
        var detector = ClipboardForumLinkDetector()

        XCTAssertNil(detector.promptURL(from: "https://yamibo.com/forum.php?tid=123"))
        XCTAssertNil(detector.promptURL(from: "https://foo.bbs.yamibo.com/forum.php?tid=123"))
        XCTAssertNil(detector.promptURL(from: "https://example.com/?next=https://yamibo.com"))
    }

    func testSkipsInvalidOccurrenceAndExtractsLaterForumLink() throws {
        var detector = ClipboardForumLinkDetector()

        let url = try XCTUnwrap(detector.promptURL(from: "https://foo.bbs.yamibo.com/ 后面才是 bbs.yamibo.com/forum.php?tid=99"))

        XCTAssertEqual(url.absoluteString, "https://bbs.yamibo.com/forum.php?tid=99")
    }

    func testOnlySuppressesConsecutiveDuplicateForumLink() throws {
        var detector = ClipboardForumLinkDetector()
        let first = try XCTUnwrap(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=1"))

        XCTAssertNil(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=1"))

        let second = try XCTUnwrap(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=2"))
        XCTAssertNotEqual(second, first)

        let repeatedAfterDifferentLink = try XCTUnwrap(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=1"))
        XCTAssertEqual(repeatedAfterDifferentLink, first)

        XCTAssertNil(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=1"))
        XCTAssertNil(detector.promptURL(from: "普通文本"))

        let repeatedAfterNonLink = try XCTUnwrap(detector.promptURL(from: "bbs.yamibo.com/forum.php?tid=1"))
        XCTAssertEqual(repeatedAfterNonLink, first)
    }
}
