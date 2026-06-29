import Foundation
import Testing
@testable import YamiboReaderCore

@Test func forumRouteResolverResolvesBoardURLs() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=5&page=3&mobile=2"))

    #expect(ForumRouteResolver.resolve(url: url) == .board(fid: "5", title: nil, page: 3))
}

@Test func forumRouteResolverResolvesRewriteBoardURLs() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum-370-2.html"))

    #expect(ForumRouteResolver.resolve(url: url) == .board(fid: "370", title: nil, page: 2))
}

@Test func forumRouteResolverResolvesThreadURLs() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/thread-570956-1-1.html"))

    #expect(ForumRouteResolver.resolve(url: url) == .thread(url))
}

@Test func forumRouteResolverKeepsReaderOriginURLsInWebFallback() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=570956&page=2#pid99"))

    #expect(ForumRouteResolver.resolve(url: url, source: .readerOrigin) == .web(url))
}

@Test func forumRouteResolverResolvesHomeURL() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mobile=2"))

    #expect(ForumRouteResolver.resolve(url: url) == .home)
}

@Test func forumRouteResolverKeepsUnsupportedForumURLsInWebFallback() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=announcement&id=17&mobile=2"))

    #expect(ForumRouteResolver.resolve(url: url) == .web(url))
}
