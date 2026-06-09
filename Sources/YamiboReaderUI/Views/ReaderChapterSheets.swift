import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderChapterSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onSelect: (ReaderChapter) -> Void
    let onSelectWebView: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingWebPicker = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ZStack {
                    if model.isLoadingChapterDirectory {
                        Text(L10n.string("common.loading"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                if let error = model.chapterDirectoryError {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if let previousView = model.previousChapterDirectoryWebView {
                                    ReaderChapterWebNavigationButton(
                                        title: L10n.string("reader.go_previous_web_page"),
                                        systemImage: "chevron.up",
                                        action: { onSelectWebView(previousView) }
                                    )
                                }

                                ForEach(model.visibleChapterDirectoryChapters, id: \.startIndex) { chapter in
                                    Button {
                                        onSelect(chapter)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(chapter.title)
                                                .font(.body.weight(isCurrent(chapter) ? .semibold : .regular))
                                                .foregroundStyle(isCurrent(chapter) ? Color.accentColor : .primary)
                                                .lineLimit(1)
                                            Text(chapterLocationText(for: chapter))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(isCurrent(chapter) ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .id(chapter.startIndex)
                                }

                                if let nextView = model.nextChapterDirectoryWebView {
                                    ReaderChapterWebNavigationButton(
                                        title: L10n.string("reader.go_next_web_page"),
                                        systemImage: "chevron.down",
                                        action: { onSelectWebView(nextView) }
                                    )
                                }
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            guard model.maxView > 1 else { return }
                            showingWebPicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Text(model.chapterDirectoryWebTitle)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .rotationEffect(.degrees(showingWebPicker ? 180 : 0))
                            }
                            .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.maxView <= 1)
                        .popover(isPresented: $showingWebPicker, arrowEdge: .top) {
                            ReaderChapterWebPicker(model: model) { view in
                                showingWebPicker = false
                                guard view != model.visibleChapterDirectoryView else { return }
                                onSelectWebView(view)
                            }
                            .presentationCompactAdaptation(.popover)
                        }
                        .accessibilityLabel(model.chapterDirectoryWebTitle)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        ReaderToolbarIconButton(
                            systemName: "xmark",
                            title: L10n.string("common.done"),
                            action: { dismiss() }
                        )
                    }
                }
                .onAppear {
                    model.resetChapterDirectoryBrowsing()
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.currentChapterIndex) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    showingWebPicker = false
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.visibleChapterDirectoryView) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.maxView) { _, newValue in
                    if newValue <= 1 {
                        showingWebPicker = false
                    }
                }
            }
        }
    }

    private func isCurrent(_ chapter: ReaderChapter) -> Bool {
        guard model.visibleChapterDirectoryView == model.visibleView else { return false }
        return chapter.title == model.currentChapterTitle
    }

    private func chapterLocationText(for chapter: ReaderChapter) -> String {
        if model.settings.readingMode == .vertical {
            guard model.visibleChapterDirectoryPageCount > 1 else { return "0%" }
            let fraction = Double(chapter.startIndex) / Double(model.visibleChapterDirectoryPageCount - 1)
            return "\(Int((fraction * 100).rounded()))%"
        }
        return L10n.string("reader.page_number_spaced", chapter.startIndex + 1)
    }

    private func scrollToCurrentChapter(using proxy: ScrollViewProxy) {
        guard let currentChapterIndex = model.currentChapterDirectoryIndex,
              model.visibleChapterDirectoryChapters.indices.contains(currentChapterIndex) else { return }
        let targetIndex = max(currentChapterIndex - 3, 0)
        let targetChapter = model.visibleChapterDirectoryChapters[targetIndex]
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(targetChapter.startIndex, anchor: .top)
        }
    }
}

private struct ReaderChapterWebNavigationButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct ReaderChapterCommentsSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let target: ReaderChapterCommentTarget?
    let onOpenOriginalPost: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: { target in Task { await model.loadChapterComments(for: target) } },
                loadNext: { Task { await model.loadNextChapterCommentsPage() } },
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
                            action: { Task { await model.refreshChapterComments(for: target) } }
                        )
                        .disabled(target == nil)
                    }
                }
        }
        .task(id: target) {
            await model.loadChapterComments(for: target)
        }
    }

    private func openOriginalPost(_ url: URL) {
        dismiss()
        onOpenOriginalPost(url)
    }
}

struct MangaChapterCommentsSheet: View {
    @ObservedObject var model: MangaReaderModel
    let target: ReaderChapterCommentTarget?
    let appModel: YamiboAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: { target in Task { await model.loadChapterComments(for: target) } },
                loadNext: { Task { await model.loadNextChapterCommentsPage() } },
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
                        action: { Task { await model.refreshChapterComments(for: target) } }
                    )
                    .disabled(target == nil)
                }
            }
        }
        .task(id: target) {
            await model.loadChapterComments(for: target)
        }
    }

    private func openOriginalPost(_ url: URL) {
        dismiss()
        Task {
            await model.saveProgress()
            appModel.dismissManga(openThreadInForum: url)
        }
    }
}

private struct ReaderChapterCommentsContent: View {
    let state: ReaderChapterCommentsState
    let isLoadingMore: Bool
    let loadMoreError: String?
    let refreshError: String?
    let retry: (ReaderChapterCommentTarget) -> Void
    let loadNext: () -> Void
    let openOriginalPost: (URL) -> Void

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
                    L10n.string("reader.chapter_comments_empty"),
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

    private static let loadNextColor = Color(red: 0.54, green: 0.35, blue: 0.22)
}

private struct ReaderChapterCommentsToolbarTitle: View {
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

private struct ReaderChapterCommentRow: View {
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

private struct ReaderChapterCommentSourceBadge: View {
    let source: ChapterCommentSource

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
}

private struct ReaderChapterWebPicker: View {
    @ObservedObject var model: ReaderContainerModel
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(1 ... model.maxView, id: \.self) { view in
                        Button {
                            onSelect(view)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: view == model.visibleChapterDirectoryView ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(view == model.visibleChapterDirectoryView ? Color.accentColor : Color.secondary)

                                Text(L10n.string("reader.page_number_spaced", view))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)

                                if view == model.visibleView {
                                    Text(L10n.string("common.current"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(view == model.visibleChapterDirectoryView ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(view)
                    }
                }
                .padding(8)
            }
            .frame(width: 200)
            .frame(maxHeight: 260)
            .onAppear {
                scrollToCurrentView(using: proxy)
            }
            .onChange(of: model.visibleChapterDirectoryView) { _, _ in
                scrollToCurrentView(using: proxy)
            }
        }
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleChapterDirectoryView - 2, 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

struct ReaderWebJumpSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        HStack {
                            Text(L10n.string("reader.current_web_page"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.currentWebViewText)
                                .fontWeight(.semibold)
                        }
                    }

                    Section(L10n.string("reader.select_web_page")) {
                        ForEach(1 ... model.maxView, id: \.self) { view in
                            Button {
                                onJump(view)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: view == model.visibleView ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(view == model.visibleView ? Color.accentColor : Color.secondary)

                                    Text(L10n.string("reader.page_number_spaced", view))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if view == model.visibleView {
                                        Text(L10n.string("common.current"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .id(view)
                        }
                    }
                }
                .navigationTitle(L10n.string("reader.jump_web_page"))
                .onAppear {
                    scrollToCurrentView(using: proxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    scrollToCurrentView(using: proxy)
                }
            }
        }
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleView - 3, 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}
#endif
