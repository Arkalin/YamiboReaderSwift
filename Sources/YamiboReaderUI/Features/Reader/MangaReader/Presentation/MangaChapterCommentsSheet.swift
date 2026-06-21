import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaChapterCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReaderChapterCommentTarget?
    let appModel: YamiboAppModel

    @ObservedObject var model: MangaReaderModel

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ReaderChapterCommentsToolbarTitle(target: target)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        ReaderToolbarIconButton(
                            systemName: "xmark",
                            title: L10n.string("common.done"),
                            action: { dismiss() }
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ReaderToolbarIconButton(
                            systemName: "arrow.clockwise",
                            title: L10n.string("common.refresh"),
                            action: refresh
                        )
                        .disabled(target == nil)
                    }
                }
        }
        .task(id: target) {
            await model.loadChapterComments(for: target)
        }
    }

    @ViewBuilder
    private var content: some View {
        if target == nil {
            ContentUnavailableView(
                L10n.string("reader.comments_empty"),
                systemImage: "text.bubble"
            )
        } else {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: retry(_:),
                loadNext: loadNext,
                openOriginalPost: openOriginalPost(_:),
                emptyTitle: L10n.string("reader.comments_empty")
            )
        }
    }

    private func retry(_ target: ReaderChapterCommentTarget) {
        Task { await model.loadChapterComments(for: target) }
    }

    private func loadNext() {
        Task { await model.loadNextChapterCommentsPage() }
    }

    private func refresh() {
        Task { await model.refreshChapterComments(for: target) }
    }

    private func openOriginalPost(_ url: URL) {
        dismiss()
        Task {
            let latestRoute = await model.saveProgress()
            appModel.dismissManga(openThreadInForum: url, suspendedRoute: latestRoute)
        }
    }
}
#endif
