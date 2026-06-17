// Legacy manga reader reference extracted from
// Sources/YamiboReaderUI/Features/NovelReader/Sheets/ReaderChapterCommentsSheets.swift.
// This file is reference-only and is not compiled.

import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaChapterCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReaderChapterCommentTarget?
    let appModel: YamiboAppModel

    @ObservedObject var model: MangaReaderModel

    init(
        model: MangaReaderModel,
        target: ReaderChapterCommentTarget?,
        appModel: YamiboAppModel
    ) {
        self.model = model
        self.target = target
        self.appModel = appModel
    }

    var body: some View {
        NavigationStack {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: retry(_:),
                loadNext: loadNext,
                openOriginalPost: openOriginalPost(_:)
            )
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
            await model.saveProgress()
            appModel.dismissManga(openThreadInForum: url)
        }
    }
}
#endif
