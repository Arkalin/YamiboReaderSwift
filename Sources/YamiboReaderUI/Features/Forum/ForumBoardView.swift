import SwiftUI
import YamiboReaderCore

struct ForumBoardView: View {
    let onSubBoardTap: (ForumBoardSummary) -> Void
    let onPinnedTap: (ForumPinnedItem) -> Void
    let onThreadTap: (ForumThreadSummary) -> Void
    let onSearchTap: () -> Void
    let onPostThreadTap: () -> Void

    @State private var model: ForumBoardViewModel
    @State private var showsFilterDialog = false
    @State private var showsOrderDialog = false

    init(
        model: ForumBoardViewModel,
        onSubBoardTap: @escaping (ForumBoardSummary) -> Void,
        onPinnedTap: @escaping (ForumPinnedItem) -> Void,
        onThreadTap: @escaping (ForumThreadSummary) -> Void,
        onSearchTap: @escaping () -> Void,
        onPostThreadTap: @escaping () -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onSubBoardTap = onSubBoardTap
        self.onPinnedTap = onPinnedTap
        self.onThreadTap = onThreadTap
        self.onSearchTap = onSearchTap
        self.onPostThreadTap = onPostThreadTap
    }

    var body: some View {
        ForumBoardBodyView(
            page: model.page,
            subBoards: model.subBoards,
            pinnedItems: model.pinnedItems,
            threads: model.threads,
            pageNavigation: model.pageNavigation,
            filters: model.filters,
            orders: model.orders,
            selectedFilterTitle: model.selectedFilterTitle,
            selectedOrderTitle: model.selectedOrderTitle,
            isLoading: model.isLoading,
            isRefreshing: model.isRefreshing,
            errorMessage: model.errorMessage,
            retry: retry,
            refresh: refresh,
            goToPage: goToPage,
            showFilters: { showsFilterDialog = true },
            showOrders: { showsOrderDialog = true },
            onSubBoardTap: onSubBoardTap,
            onPinnedTap: onPinnedTap,
            onThreadTap: onThreadTap
        )
        .navigationTitle(model.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(L10n.string("forum.home.search_placeholder"))

                Menu {
                    Button(action: onPostThreadTap) {
                        Label(L10n.string("forum.board.post_thread"), systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L10n.string("common.more"))
            }
        }
        .confirmationDialog(
            L10n.string("forum.board.filter"),
            isPresented: $showsFilterDialog,
            titleVisibility: .visible
        ) {
            Button(L10n.string("forum.board.all")) {
                Task { await model.selectFilter(id: nil) }
            }
            ForEach(model.filters) { option in
                Button(option.title) {
                    Task { await model.selectFilter(id: option.id) }
                }
            }
        }
        .confirmationDialog(
            L10n.string("forum.board.order"),
            isPresented: $showsOrderDialog,
            titleVisibility: .visible
        ) {
            Button(L10n.string("forum.board.all")) {
                Task { await model.selectOrder(id: nil) }
            }
            ForEach(model.orders) { option in
                Button(option.title) {
                    Task { await model.selectOrder(id: option.id) }
                }
            }
        }
        .task {
            await model.load()
        }
    }

    private func retry() {
        Task {
            await model.load()
        }
    }

    private func refresh() async {
        await model.refresh()
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }
}

private struct ForumBoardBodyView: View {
    let page: ForumBoardPage?
    let subBoards: [ForumBoardSummary]
    let pinnedItems: [ForumPinnedItem]
    let threads: [ForumThreadSummary]
    let pageNavigation: ForumPageNavigation?
    let filters: [ForumFilterOption]
    let orders: [ForumOrderOption]
    let selectedFilterTitle: String
    let selectedOrderTitle: String
    let isLoading: Bool
    let isRefreshing: Bool
    let errorMessage: String?
    let retry: () -> Void
    let refresh: () async -> Void
    let goToPage: (Int) -> Void
    let showFilters: () -> Void
    let showOrders: () -> Void
    let onSubBoardTap: (ForumBoardSummary) -> Void
    let onPinnedTap: (ForumPinnedItem) -> Void
    let onThreadTap: (ForumThreadSummary) -> Void

    var body: some View {
        if isLoading && page == nil {
            ForumBoardLoadingView()
        } else if let errorMessage, page == nil {
            ForumBoardErrorView(message: errorMessage, retry: retry)
        } else if let page {
            ForumBoardContentView(
                board: page.board,
                subBoards: subBoards,
                pinnedItems: pinnedItems,
                threads: threads,
                pageNavigation: pageNavigation,
                showsFilter: !filters.isEmpty,
                showsOrder: !orders.isEmpty,
                selectedFilterTitle: selectedFilterTitle,
                selectedOrderTitle: selectedOrderTitle,
                isRefreshing: isRefreshing,
                refresh: refresh,
                goToPage: goToPage,
                showFilters: showFilters,
                showOrders: showOrders,
                onSubBoardTap: onSubBoardTap,
                onPinnedTap: onPinnedTap,
                onThreadTap: onThreadTap
            )
        } else {
            ForumBoardEmptyView(retry: retry)
        }
    }
}

private struct ForumBoardContentView: View {
    let board: ForumBoardSummary
    let subBoards: [ForumBoardSummary]
    let pinnedItems: [ForumPinnedItem]
    let threads: [ForumThreadSummary]
    let pageNavigation: ForumPageNavigation?
    let showsFilter: Bool
    let showsOrder: Bool
    let selectedFilterTitle: String
    let selectedOrderTitle: String
    let isRefreshing: Bool
    let refresh: () async -> Void
    let goToPage: (Int) -> Void
    let showFilters: () -> Void
    let showOrders: () -> Void
    let onSubBoardTap: (ForumBoardSummary) -> Void
    let onPinnedTap: (ForumPinnedItem) -> Void
    let onThreadTap: (ForumThreadSummary) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForumBoardStatsView(
                    todayCount: board.todayCount,
                    threadCount: board.threadCount,
                    rank: board.rank,
                    showsFilter: showsFilter,
                    showsOrder: showsOrder,
                    selectedFilterTitle: selectedFilterTitle,
                    selectedOrderTitle: selectedOrderTitle,
                    showFilters: showFilters,
                    showOrders: showOrders
                )

                if !subBoards.isEmpty {
                    ForumSubBoardSectionView(boards: subBoards, onTap: onSubBoardTap)
                }

                if !pinnedItems.isEmpty {
                    ForumPinnedSectionView(items: pinnedItems, onTap: onPinnedTap)
                }

                if threads.isEmpty {
                    ForumBoardNoThreadsView()
                } else {
                    ForEach(threads) { thread in
                        ForumThreadRowView(
                            tid: thread.tid,
                            title: thread.title,
                            authorName: thread.authorName,
                            authorAvatarURL: thread.authorAvatarURL,
                            description: thread.description,
                            tag: thread.tag,
                            isPoll: thread.isPoll,
                            replyCount: thread.replyCount,
                            viewCount: thread.viewCount,
                            lastActivityText: thread.lastActivityText,
                            onTap: {
                                onThreadTap(thread)
                            }
                        )
                    }
                }

                if let pageNavigation {
                    ForumPageNavigationView(navigation: pageNavigation, goToPage: goToPage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .refreshable {
            await refresh()
        }
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
    }
}

private struct ForumBoardStatsView: View {
    let todayCount: Int?
    let threadCount: Int?
    let rank: Int?
    let showsFilter: Bool
    let showsOrder: Bool
    let selectedFilterTitle: String
    let selectedOrderTitle: String
    let showFilters: () -> Void
    let showOrders: () -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                statChips
                Spacer(minLength: 8)
                optionButtons
            }
            VStack(alignment: .leading, spacing: 10) {
                statChips
                optionButtons
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statChips: some View {
        HStack(spacing: 8) {
            if let todayCount {
                ForumStatChipView(label: L10n.string("forum.board.today"), value: String(todayCount))
            }
            if let threadCount {
                ForumStatChipView(label: L10n.string("forum.board.threads"), value: String(threadCount))
            }
            if let rank {
                ForumStatChipView(label: L10n.string("forum.board.rank"), value: String(rank))
            }
        }
    }

    private var optionButtons: some View {
        HStack(spacing: 8) {
            if showsOrder {
                Button(action: showOrders) {
                    Label(selectedOrderTitle, systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showsFilter {
                Button(action: showFilters) {
                    Label(selectedFilterTitle, systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct ForumStatChipView: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.background.opacity(0.72), in: Capsule())
    }
}

private struct ForumSubBoardSectionView: View {
    let boards: [ForumBoardSummary]
    let onTap: (ForumBoardSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("forum.board.sub_boards"))
                .font(.headline)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(boards) { board in
                        Button {
                            onTap(board)
                        } label: {
                            Label(board.name, systemImage: "folder")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.quaternary, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ForumPinnedSectionView: View {
    let items: [ForumPinnedItem]
    let onTap: (ForumPinnedItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("forum.board.pinned"))
                .font(.headline)

            ForEach(items) { item in
                ForumPinnedRowView(
                    id: item.id,
                    title: item.title,
                    kind: item.kind,
                    onTap: {
                        onTap(item)
                    }
                )
            }
        }
    }
}

private struct ForumPinnedRowView: View {
    let id: String
    let title: String
    let kind: ForumPinnedItem.Kind
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(kind == .announcement ? L10n.string("forum.board.announcement") : L10n.string("forum.board.pinned_badge"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kind == .announcement ? Color.orange : Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((kind == .announcement ? Color.orange : Color.accentColor).opacity(0.12), in: Capsule())

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(11)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("forum-pinned-row-\(id)")
    }
}

private struct ForumThreadRowView: View {
    let tid: String
    let title: String
    let authorName: String?
    let authorAvatarURL: URL?
    let description: String?
    let tag: String?
    let isPoll: Bool
    let replyCount: Int?
    let viewCount: Int?
    let lastActivityText: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ForumThreadMetaView(
                    authorName: authorName,
                    authorAvatarURL: authorAvatarURL,
                    lastActivityText: lastActivityText
                )

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isPoll {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForumThreadFooterView(tag: tag, viewCount: viewCount, replyCount: replyCount)
            }
            .padding(13)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("forum-thread-row-\(tid)")
    }
}

private struct ForumThreadMetaView: View {
    let authorName: String?
    let authorAvatarURL: URL?
    let lastActivityText: String?

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: authorAvatarURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .accessibilityHidden(true)

            if let authorName {
                Text(authorName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            if let lastActivityText {
                Text(lastActivityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ForumThreadFooterView: View {
    let tag: String?
    let viewCount: Int?
    let replyCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let viewCount {
                Label(String(viewCount), systemImage: "eye")
            }
            if let replyCount {
                Label(String(replyCount), systemImage: "bubble.right")
            }

            Spacer(minLength: 0)

            if let tag {
                Text("#\(tag)")
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ForumPageNavigationView: View {
    let navigation: ForumPageNavigation
    let goToPage: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                goToPage(navigation.currentPage - 1)
            } label: {
                Label(L10n.string("forum.board.previous_page"), systemImage: "chevron.left")
            }
            .disabled(navigation.currentPage <= 1)

            Spacer()

            Text(pageText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                goToPage(navigation.currentPage + 1)
            } label: {
                Label(L10n.string("forum.board.next_page"), systemImage: "chevron.right")
            }
            .labelStyle(.titleAndIcon)
            .disabled(navigation.totalPages.map { navigation.currentPage >= $0 } ?? false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }

    private var pageText: String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", navigation.currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", navigation.currentPage)
    }
}

private struct ForumBoardLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ForumBoardErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("common.load_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("common.retry"), action: retry)
        }
    }
}

private struct ForumBoardEmptyView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("forum.board.empty"), systemImage: "list.bullet.rectangle")
        } description: {
            Text(L10n.string("forum.board.empty_message"))
        } actions: {
            Button(L10n.string("common.retry"), action: retry)
        }
    }
}

private struct ForumBoardNoThreadsView: View {
    var body: some View {
        ContentUnavailableView(
            L10n.string("forum.board.no_threads"),
            systemImage: "text.bubble",
            description: Text(L10n.string("forum.board.no_threads_message"))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
