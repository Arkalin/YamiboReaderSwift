import Foundation
import Testing
@testable import YamiboReaderCore

@Test func yamiboRemoteSyncImportsIntoSelectedCategoryOnlyAfterProbe() async throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "远端")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901"))

    let report = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-901", threadURL: url, remoteOrder: 3)],
        date: Date(timeIntervalSince1970: 10)
    ) { probeURL in
        FavoriteThreadProbeResult(
            target: FavoriteContentTarget(kind: .novelThread, threadURL: probeURL),
            title: "远端小说",
            sourceGroup: .forumBoard(id: "fid", label: "小说")
        )
    }

    let item = try #require(document.items.first)
    #expect(report.importedTargetIDs == [item.id])
    #expect(item.locations == [.category(category.id)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-901")
    #expect(item.remoteMapping?.yamiboRemoteOrder == 3)
}

@Test func yamiboRemoteSyncSkipsFailedProbeWithoutPlaceholder() async throws {
    var document = FavoriteLibraryDocument()
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902"))

    let report = await document.syncYamiboRemoteFavorites(
        into: document.defaultCategory.id,
        remoteEntries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-902", threadURL: url)]
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("offline")
    }

    #expect(report.failedRemoteFavoriteIDs == ["r-902"])
    #expect(document.items.isEmpty)
}

@Test func yamiboRemoteSyncMarksDisappearedRemoteMappingMissingWithoutDeletingItem() async throws {
    var document = FavoriteLibraryDocument()
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=903"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    let item = try FavoriteItem(
        target: target,
        title: "本地",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "r-903"),
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(item)

    let report = await document.syncYamiboRemoteFavorites(
        into: document.defaultCategory.id,
        remoteEntries: []
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("unused")
    }

    let stored = try #require(document.items.first)
    #expect(report.markedMissingTargetIDs == [target.id])
    #expect(stored.remoteMapping?.isMarkedRemoteMissing == true)
}

@Test func yamiboRemoteSyncUploadsOnlyThreadItemsInCategoryWithoutRemoteMapping() async throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "同步")
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=904"))
    let unsyncedThread = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadURL: threadURL),
        title: "本地主题",
        locations: [.category(category.id)]
    )
    let manga = try FavoriteItem(
        target: FavoriteContentTarget(mangaCleanBookName: "漫画"),
        title: "漫画",
        locations: [.category(category.id)]
    )
    document.addItem(unsyncedThread)
    document.addItem(manga)

    let report = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: []
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("unused")
    }

    #expect(report.uploadTargetIDs == [unsyncedThread.id])
}
