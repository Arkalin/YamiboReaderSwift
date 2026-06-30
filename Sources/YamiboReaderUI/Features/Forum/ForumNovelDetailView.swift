import SwiftUI
import YamiboReaderCore

struct ForumNovelDetailView: View {
    @State private var model: ForumNovelDetailViewModel

    let onChapterTap: (ReaderLaunchContext) -> Void
    let onViewThread: () -> Void

    init(
        model: ForumNovelDetailViewModel,
        onChapterTap: @escaping (ReaderLaunchContext) -> Void,
        onViewThread: @escaping () -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onChapterTap = onChapterTap
        self.onViewThread = onViewThread
    }

    var body: some View {
        ForumNovelDetailBodyView(
            header: model.headerSummary,
            chapters: model.chapters,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            retry: retry,
            onChapterTap: { chapter in
                onChapterTap(model.launchContext(for: chapter))
            },
            onReadStart: {
                onChapterTap(model.continueLaunchContext())
            },
            hasReadingProgress: model.favorite?.novelResumePoint != nil || (model.favorite?.lastView ?? 1) > 1,
            onViewThread: onViewThread
        )
        .navigationTitle(model.navigationTitle)
        .yamiboInlineNavigationTitleDisplayMode()
        .task {
            await model.load()
        }
    }

    private func retry() {
        Task {
            await model.reload()
        }
    }
}

private struct ForumNovelDetailBodyView: View {
    let header: ForumNovelDetailHeaderSummary
    let chapters: [ForumNovelChapterSummary]
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void
    let onChapterTap: (ForumNovelChapterSummary) -> Void
    let onReadStart: () -> Void
    let hasReadingProgress: Bool
    let onViewThread: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForumNovelDetailHeader(
                    summary: header,
                    canReadStart: !isLoading && errorMessage == nil,
                    hasReadingProgress: hasReadingProgress,
                    onReadStart: onReadStart,
                    onViewThread: onViewThread
                )

                if !chapters.isEmpty {
                    ForEach(chapters) { chapter in
                        Button {
                            onChapterTap(chapter)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.book.closed")
                                    .foregroundStyle(ForumColors.brownPrimary)
                                    .frame(width: 24)
                                Text(chapter.title)
                                    .font(.subheadline)
                                    .foregroundStyle(ForumColors.textDark)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ForumColors.tertiaryText)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .forumCardBackground()
                        }
                        .buttonStyle(.plain)
                    }
                } else if isLoading {
                    ForumThreadReaderLoadingView()
                } else if let errorMessage {
                    ForumThreadReaderErrorView(message: errorMessage, retry: retry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }
}

private struct ForumNovelDetailHeader: View {
    let summary: ForumNovelDetailHeaderSummary
    let canReadStart: Bool
    let hasReadingProgress: Bool
    let onReadStart: () -> Void
    let onViewThread: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                cover

                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                        .fixedSize(horizontal: false, vertical: true)

                    if let authorName = summary.authorName {
                        Label(authorName, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(ForumColors.brownPrimary)
                            .lineLimit(1)
                    }

                    if let postedAtText = summary.postedAtText {
                        Text(String(format: L10n.string("forum.thread_route.posted_at_format"), postedAtText))
                            .font(.caption2)
                            .foregroundStyle(ForumColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FlowStatRow(summary: summary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 10) {
                    actionButtons
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ForumColors.brownPrimary.opacity(0.12))

            if let coverURL = summary.coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        coverPlaceholder(systemImage: "book.closed")
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(ForumColors.brownPrimary)
                    @unknown default:
                        coverPlaceholder(systemImage: "book.closed")
                    }
                }
            } else {
                coverPlaceholder(systemImage: "book.closed")
            }
        }
        .frame(width: 86, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ForumColors.border.opacity(0.7), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func coverPlaceholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(ForumColors.brownPrimary.opacity(0.55))
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onReadStart) {
            Label(
                L10n.string(hasReadingProgress ? "forum.thread_route.continue_novel" : "forum.thread_route.read_novel"),
                systemImage: "book"
            )
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canReadStart)

        Button(action: onViewThread) {
            Label(L10n.string("forum.thread_route.view_discussion"), systemImage: "text.bubble")
        }
        .buttonStyle(.bordered)
    }
}

private struct FlowStatRow: View {
    let summary: ForumNovelDetailHeaderSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chips
            }
            VStack(alignment: .leading, spacing: 6) {
                chips
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(ForumColors.secondaryText)
    }

    @ViewBuilder
    private var chips: some View {
        ForumNovelDetailStatChip(
            text: String(summary.chapterCount),
            systemImage: "list.bullet"
        )
        if let totalViews = summary.totalViews {
            ForumNovelDetailStatChip(
                text: totalViews.formatted(),
                systemImage: "eye"
            )
        }
        if let totalReplies = summary.totalReplies {
            ForumNovelDetailStatChip(
                text: totalReplies.formatted(),
                systemImage: "text.bubble"
            )
        }
        if let forumName = summary.forumName {
            ForumNovelDetailStatChip(
                text: forumName,
                systemImage: "number"
            )
        }
    }
}

private struct ForumNovelDetailStatChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(ForumColors.brownPrimary.opacity(0.08), in: Capsule())
    }
}
