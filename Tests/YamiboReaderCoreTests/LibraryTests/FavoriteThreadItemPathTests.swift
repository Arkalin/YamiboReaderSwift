import Foundation
import Testing
@testable import YamiboReaderCore

@Test func threadFavoriteImportProbesBeforeCreatingNormalThreadItem() async throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=420"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    var document = FavoriteLibraryDocument()
    var probedURL: URL?

    let item = try await document.importThreadFavorite(threadURL: url) { url in
        probedURL = url
        return FavoriteThreadProbeResult(
            target: target,
            title: "普通主题",
            sourceGroup: .forumBoard(id: "fid-regular", label: "综合讨论")
        )
    }

    #expect(probedURL == url)
    #expect(item.target == target)
    #expect(item.locations == [.category(FavoriteCategory.defaultID)])
    #expect(item.sourceGroup == .forumBoard(id: "fid-regular", label: "综合讨论"))
}

@Test func threadFavoriteImportFailureSkipsPlaceholderCreation() async throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=421"))
    var document = FavoriteLibraryDocument()

    await #expect(throws: FavoriteThreadImportFailure.self) {
        _ = try await document.importThreadFavorite(threadURL: url) { _ in
            throw FavoriteThreadImportFailure.probeFailed("missing thread")
        }
    }

    #expect(document.items.isEmpty)
}

@Test func threadFavoriteImportRetargetsExistingItemWhenThreadKindChanges() async throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=422"))
    let normalTarget = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    let novelTarget = FavoriteContentTarget(kind: .novelThread, threadURL: url)
    var document = FavoriteLibraryDocument()
    let tag = document.createTag(name: "保留标签", color: .purple)
    let existing = try FavoriteItem(
        target: normalTarget,
        title: "旧普通主题",
        displayName: "本地标题",
        locations: [.category(document.defaultCategory.id)],
        tagIDs: [tag.id]
    )
    document.addItem(existing)

    let imported = try await document.importThreadFavorite(threadURL: url) { _ in
        FavoriteThreadProbeResult(target: novelTarget, title: "轻小说主题")
    }

    #expect(imported.target == novelTarget)
    #expect(document.items.count == 1)
    let stored = try #require(document.items.first)
    #expect(stored.id == novelTarget.id)
    #expect(stored.displayName == "本地标题")
    #expect(stored.tagIDs == [tag.id])
}

@Test func threadFavoriteDisplayNameStaysLocalMetadata() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=423"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    var document = FavoriteLibraryDocument()

    let item = try document.importThreadFavorite(
        probeResult: FavoriteThreadProbeResult(target: target, title: "远端标题"),
        displayName: " 本地展示名 ",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-423")
    )

    #expect(item.title == "远端标题")
    #expect(item.displayName == "本地展示名")
    #expect(item.remoteMapping?.yamiboFavoriteID == "remote-423")
}

@Test func threadFavoriteOpenRoutesUseNormalAndNovelNativeTargets() throws {
    let normalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=424"))
    let novelURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=425"))
    var document = FavoriteLibraryDocument()
    let normal = try document.importThreadFavorite(
        probeResult: FavoriteThreadProbeResult(
            target: FavoriteContentTarget(kind: .normalThread, threadURL: normalURL),
            title: "普通主题"
        )
    )
    let novel = try document.importThreadFavorite(
        probeResult: FavoriteThreadProbeResult(
            target: FavoriteContentTarget(kind: .novelThread, threadURL: novelURL),
            title: "小说主题"
        )
    )

    #expect(document.openRoute(for: normal) == .nativeThread(FavoriteLibraryURLIdentity.canonicalThreadURL(from: normalURL)))
    #expect(document.openRoute(for: novel) == .novelDetail(FavoriteLibraryURLIdentity.canonicalThreadURL(from: novelURL)))
}
