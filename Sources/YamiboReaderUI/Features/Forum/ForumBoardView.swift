import SwiftUI
import YamiboReaderCore

struct ForumBoardView: View {
    let onSubBoardTap: (ForumBoardSummary) -> Void
    let onPinnedTap: (ForumPinnedItem) -> Void
    let onThreadTap: (ForumThreadSummary) -> Void
    let onAuthorTap: (String, String?) -> Void
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
        onAuthorTap: @escaping (String, String?) -> Void,
        onSearchTap: @escaping () -> Void,
        onPostThreadTap: @escaping () -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onSubBoardTap = onSubBoardTap
        self.onPinnedTap = onPinnedTap
        self.onThreadTap = onThreadTap
        self.onAuthorTap = onAuthorTap
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
            onThreadTap: onThreadTap,
            onAuthorTap: onAuthorTap
        )
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
        .navigationTitle(model.title)
        .navigationBarBackButtonHidden(model.canRestorePreviousPage)
        .toolbar {
            if model.canRestorePreviousPage {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        _ = model.restorePreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(L10n.string("common.back"))
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button {
                        _ = model.restorePreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(L10n.string("common.back"))
                }
                #endif
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(L10n.string("forum.home.search_placeholder"))

                Menu {
                    Button(action: onPostThreadTap) {
                        Label(L10n.string("forum.board.post_thread"), systemImage: "square.and.pencil")
                    }
                    Button {
                        Task {
                            await model.addFavorite()
                        }
                    } label: {
                        Label(
                            model.isFavoriting ? L10n.string("forum.board.favoriting") : L10n.string("forum.board.favorite"),
                            systemImage: "star"
                        )
                    }
                    .disabled(model.isFavoriting)
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
        .alert(
            L10n.string("forum.board.favorite"),
            isPresented: Binding(
                get: { model.favoriteMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.favoriteMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.favoriteMessage = nil
            }
        } message: {
            Text(model.favoriteMessage ?? "")
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
    let onAuthorTap: (String, String?) -> Void

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
                onThreadTap: onThreadTap,
                onAuthorTap: onAuthorTap
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
    let onAuthorTap: (String, String?) -> Void

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
                        ForumThreadSummaryRowView(
                            thread: thread,
                            onThreadTap: {
                                onThreadTap(thread)
                            },
                            onAuthorTap: onAuthorTap
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
        .forumPageBackground()
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
        .background(
            LinearGradient(
                colors: [ForumColors.brownDeep, ForumColors.brownPrimary.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(ForumColors.redAccent)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.white.opacity(0.14), in: Capsule())
    }
}

private struct ForumSubBoardSectionView: View {
    let boards: [ForumBoardSummary]
    let onTap: (ForumBoardSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("forum.board.sub_boards"))
                .font(.headline)
                .foregroundStyle(ForumColors.brownPrimary)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(boards) { board in
                        Button {
                            onTap(board)
                        } label: {
                            Label(board.name, systemImage: "folder")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(ForumColors.textDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .forumCardBackground()
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
                .foregroundStyle(ForumColors.brownPrimary)

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
                    .foregroundStyle(ForumColors.textDark)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ForumColors.orangeAccent, in: Capsule())

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ForumColors.textDark)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(11)
            .forumCardBackground(fill: kind == .announcement ? ForumColors.announcementBackground : ForumColors.pinnedBackground)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("forum-pinned-row-\(id)")
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
                .foregroundStyle(ForumColors.secondaryText)

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
        .tint(ForumColors.brownDeep)
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
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forumPageBackground()
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
