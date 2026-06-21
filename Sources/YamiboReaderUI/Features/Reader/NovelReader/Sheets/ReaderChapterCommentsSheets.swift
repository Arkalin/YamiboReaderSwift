import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct ReaderChapterCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReaderChapterCommentTarget?
    let onOpenOriginalPost: (URL) -> Void

    @ObservedObject var model: ReaderContainerModel

    init(
        model: ReaderContainerModel,
        target: ReaderChapterCommentTarget?,
        onOpenOriginalPost: @escaping (URL) -> Void
    ) {
        self.model = model
        self.target = target
        self.onOpenOriginalPost = onOpenOriginalPost
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
        onOpenOriginalPost(url)
    }
}

struct ReaderChapterCommentsContent: View {
    private static let loadNextColor = Color(red: 0.54, green: 0.35, blue: 0.22)

    let state: ReaderChapterCommentsState
    let isLoadingMore: Bool
    let loadMoreError: String?
    let refreshError: String?
    let retry: (ReaderChapterCommentTarget) -> Void
    let loadNext: () -> Void
    let openOriginalPost: (URL) -> Void
    var emptyTitle = L10n.string("reader.chapter_comments_empty")

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.string("common.loading"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unsupported:
            ContentUnavailableView(
                L10n.string("reader.chapter_comments_unsupported"),
                systemImage: "text.bubble"
            )
        case let .failed(target, message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    message,
                    systemImage: "exclamationmark.triangle"
                )
                Button(L10n.string("common.retry")) {
                    retry(target)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        case let .loaded(target, page):
            if page.comments.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "text.bubble"
                )
            } else {
                List {
                    if let refreshError {
                        Section {
                            Label(refreshError, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        ForEach(page.comments) { comment in
                            ReaderChapterCommentRow(
                                comment: comment,
                                originalPostURL: comment.originalPostURL(threadURL: target.threadURL),
                                openOriginalPost: openOriginalPost
                            )
                        }
                    } footer: {
                        if page.nextView != nil {
                            loadNextButton
                                .padding(.top, 10)
                        }
                    }
                }
            }
        }
    }

    private var loadNextButton: some View {
        Button(action: loadNext) {
            HStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .tint(Self.loadNextColor)
                } else {
                    Text(loadMoreError ?? L10n.string("reader.chapter_comments_load_next"))
                        .font(.footnote.weight(.medium))
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Self.loadNextColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
    }
}

struct ReaderChapterCommentsToolbarTitle: View {
    let target: ReaderChapterCommentTarget?

    var body: some View {
        VStack(spacing: 1) {
            Text(L10n.string("reader.chapter_comments"))
                .font(.headline)
            if let title = target?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ReaderChapterCommentRow: View {
    let comment: ChapterComment
    let originalPostURL: URL?
    let openOriginalPost: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.authorName.isEmpty ? L10n.string("reader.comment_anonymous") : comment.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let metadata = comment.metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                ReaderChapterCommentSourceBadge(source: comment.source)
                if let originalPostURL {
                    Button {
                        openOriginalPost(originalPostURL)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.string("reader.open_original_post"))
                }
            }
            Text(comment.body)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

struct ReaderChapterCommentSourceBadge: View {
    let source: ChapterCommentSource

    private var palette: (foreground: Color, border: Color) {
        switch source {
        case .postComment:
            (Color(red: 0.54, green: 0.35, blue: 0.22), Color(red: 0.74, green: 0.52, blue: 0.38))
        case .ratingReason:
            (Color(red: 0.15, green: 0.44, blue: 0.36), Color(red: 0.36, green: 0.65, blue: 0.55))
        case .reply:
            (Color(red: 0.28, green: 0.36, blue: 0.68), Color(red: 0.48, green: 0.56, blue: 0.82))
        }
    }

    var body: some View {
        Text(source.displayLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .accessibilityLabel(source.displayLabel)
    }
}
#endif
