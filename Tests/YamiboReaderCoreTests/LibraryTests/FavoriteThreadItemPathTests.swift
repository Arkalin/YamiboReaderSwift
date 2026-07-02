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
    #expect(item.forumID == "fid-regular")
    #expect(item.forumName == "综合讨论")
}

@Test func threadFavoriteNormalizesExplicitForumMetadataIntoSourceGroup() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=426"))
    var document = FavoriteLibraryDocument()

    let item = try document.importThreadFavorite(
        probeResult: FavoriteThreadProbeResult(
            target: FavoriteContentTarget(kind: .normalThread, threadURL: url),
            title: "普通主题"
        ),
        displayName: nil
    )
    var stored = item
    stored.forumID = "  fid-explicit  "
    stored.forumName = "  版块显式名  "
    document.addItem(stored)

    let normalized = try #require(document.items.first)
    #expect(normalized.forumID == "fid-explicit")
    #expect(normalized.forumName == "版块显式名")
    #expect(normalized.sourceGroup == .forumBoard(id: "fid-explicit", label: "版块显式名"))
}

@Test func threadFavoriteProbeResultCarriesExplicitForumMetadata() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=428"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    let probe = FavoriteThreadProbeResult(
        target: target,
        title: "普通主题",
        forumID: " fid-probe ",
        forumName: " 探测版块 "
    )

    #expect(probe.forumID == "fid-probe")
    #expect(probe.forumName == "探测版块")
    #expect(probe.sourceGroup == .forumBoard(id: "fid-probe", label: "探测版块"))
}

@Test func favoriteContentUpdateDateResolverParsesEditedAndPostedTimes() throws {
    let edited = try #require(FavoriteContentUpdateDateResolver.date(
        lastEditedText: "本帖最后由 楼主 于 2026-6-2 12:00 编辑",
        postedAtText: "2026-6-1 10:00"
    ))
    let posted = try #require(FavoriteContentUpdateDateResolver.date(
        lastEditedText: nil,
        postedAtText: "2026-06-01 10:00"
    ))
    let calendar = Calendar(identifier: .gregorian)

    #expect(calendar.component(.year, from: edited) == 2026)
    #expect(calendar.component(.month, from: edited) == 6)
    #expect(calendar.component(.day, from: edited) == 2)
    #expect(calendar.component(.hour, from: edited) == 12)
    #expect(calendar.component(.day, from: posted) == 1)
}

@Test func threadFavoriteImportDoesNotEraseExistingForumMetadataWhenProbeSourceIsUnknown() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=427"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    var document = FavoriteLibraryDocument()
    let existing = try FavoriteItem(
        target: target,
        title: "旧标题",
        sourceGroup: .forumBoard(id: "fid-old", label: "旧版块"),
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(existing)

    let imported = try document.importThreadFavorite(
        probeResult: FavoriteThreadProbeResult(
            target: target,
            title: "新标题",
            contentUpdatedAt: Date(timeIntervalSince1970: 200)
        )
    )

    #expect(imported.title == "新标题")
    #expect(imported.sourceGroup == .forumBoard(id: "fid-old", label: "旧版块"))
    #expect(imported.forumID == "fid-old")
    #expect(imported.forumName == "旧版块")
    #expect(imported.contentUpdatedAt == Date(timeIntervalSince1970: 200))
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
