import SwiftUI
import YamiboReaderCore

struct ForumMangaDetailView: View {
    @State private var model: ForumMangaDetailViewModel

    let onChapterTap: (MangaLaunchContext) -> Void
    let onViewThread: () -> Void

    init(
        model: ForumMangaDetailViewModel,
        onChapterTap: @escaping (MangaLaunchContext) -> Void,
        onViewThread: @escaping () -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onChapterTap = onChapterTap
        self.onViewThread = onViewThread
    }

    var body: some View {
        ForumMangaDetailBodyView(
            directory: model.directory,
            focusedChapterTID: model.focusedChapterTID,
            hasReadingProgress: model.hasReadingProgress,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            retry: retry,
            onContinueTap: {
                guard let context = model.continueLaunchContext() else { return }
                onChapterTap(context)
            },
            onChapterTap: { chapter in
                onChapterTap(model.launchContext(for: chapter))
            },
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

private struct ForumMangaDetailBodyView: View {
    let directory: MangaDirectory?
    let focusedChapterTID: String?
    let hasReadingProgress: Bool
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void
    let onContinueTap: () -> Void
    let onChapterTap: (MangaChapter) -> Void
    let onViewThread: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let directory {
                        ForumMangaDetailHeader(
                            directory: directory,
                            hasReadingProgress: hasReadingProgress,
                            onContinueTap: onContinueTap,
                            onViewThread: onViewThread
                        )

                        ForEach(directory.chapters) { chapter in
                            ForumMangaChapterRow(
                                directory: directory,
                                chapter: chapter,
                                isFocused: chapter.tid == focusedChapterTID,
                                onTap: {
                                    onChapterTap(chapter)
                                }
                            )
                            .id(chapter.tid)
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
            .task(id: scrollTaskIdentity(directory: directory, focusedChapterTID: focusedChapterTID)) {
                guard let focusedChapterTID,
                      directory?.chapters.contains(where: { $0.tid == focusedChapterTID }) == true else {
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.snappy) {
                    proxy.scrollTo(focusedChapterTID, anchor: .center)
                }
            }
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }

    private func scrollTaskIdentity(directory: MangaDirectory?, focusedChapterTID: String?) -> String {
        [
            focusedChapterTID ?? "",
            directory?.chapters.map(\.tid).joined(separator: ",") ?? ""
        ].joined(separator: "|")
    }
}

private struct ForumMangaDetailHeader: View {
    let directory: MangaDirectory
    let hasReadingProgress: Bool
    let onContinueTap: () -> Void
    let onViewThread: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(directory.cleanBookName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ForumColors.textDark)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Label(String(directory.chapters.count), systemImage: "list.number")
                if let lastUpdatedAt = directory.lastUpdatedAt {
                    Label(lastUpdatedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(ForumColors.secondaryText)

            HStack(spacing: 10) {
                Button(action: onContinueTap) {
                    Label(
                        L10n.string(hasReadingProgress ? "forum.thread_route.continue_manga" : "forum.thread_route.read_manga"),
                        systemImage: "book"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(ForumColors.brownDeep)

                Button(action: onViewThread) {
                    Label(L10n.string("forum.thread_route.view_discussion"), systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)
                .tint(ForumColors.brownEmphasis)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct ForumMangaChapterRow: View {
    let directory: MangaDirectory
    let chapter: MangaChapter
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused ? ForumColors.brownEmphasis : ForumColors.secondaryText)
                    .frame(width: 42, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(MangaChapterDisplayFormatter.readerHeaderTitle(
                        rawTitle: chapter.rawTitle,
                        cleanBookName: directory.cleanBookName
                    ))
                    .font(.subheadline.weight(isFocused ? .semibold : .regular))
                    .foregroundStyle(ForumColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)

                    if isFocused {
                        Text(L10n.string("forum.thread_route.current_chapter_hint"))
                            .font(.caption)
                            .foregroundStyle(ForumColors.brownPrimary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.tertiaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forumCardBackground(fill: isFocused ? ForumColors.accentFill : ForumColors.creamSurface)
        }
        .buttonStyle(.plain)
    }
}
