import Foundation
import YamiboReaderCore

struct MineOfflineCacheQueueFavoriteGroup: Hashable, Identifiable {
    var favoriteID: String
    var favoriteTitle: String
    var chapterCount: Int
    var currentSpeedText: String?
    var chapters: [MineOfflineCacheQueueChapterRow]

    var id: String { favoriteID }

    init(group: MangaOfflineCacheQueueGroup) {
        let rows = group.works.map(MineOfflineCacheQueueChapterRow.init(work:))
        favoriteID = group.favoriteID
        favoriteTitle = group.favoriteTitle
        chapterCount = rows.count
        currentSpeedText = rows.first { $0.speedText != nil }?.speedText
        chapters = rows
    }
}

struct MineOfflineCacheQueueChapterRow: Hashable, Identifiable {
    var id: MangaOfflineCacheMembershipID
    var title: String
    var completedImageCount: Int
    var targetImageCount: Int
    var progressFraction: Double
    var progressText: String
    var percentageText: String
    var failureStatusText: String?
    var speedText: String?

    init(work: MangaOfflineCacheWork) {
        id = work.id
        title = work.chapterTitle.isEmpty ? work.tid : work.chapterTitle
        completedImageCount = work.progress.completedImageCount
        targetImageCount = work.progress.targetImageCount
        progressFraction = work.progress.fractionCompleted
        if targetImageCount > 0 {
            progressText = L10n.string(
                "mine.offline_queue.image_progress_format",
                completedImageCount,
                targetImageCount
            )
        } else {
            progressText = L10n.string("mine.offline_queue.preparing")
        }
        percentageText = L10n.string(
            "mine.offline_queue.percent_format",
            Int((progressFraction * 100).rounded())
        )
        if work.state == .failed {
            failureStatusText = work.failureMessage?.isEmpty == false
                ? work.failureMessage
                : L10n.string("mine.offline_queue.failed")
        } else {
            failureStatusText = nil
        }
        speedText = Self.speedText(bytesPerSecond: work.currentBytesPerSecond)
    }

    private static func speedText(bytesPerSecond: Int) -> String? {
        guard bytesPerSecond > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return L10n.string(
            "mine.offline_queue.speed_format",
            formatter.string(fromByteCount: Int64(bytesPerSecond))
        )
    }
}
