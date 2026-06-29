import SwiftUI
import YamiboReaderCore

struct ForumHomeView: View {
    let model: ForumHomeViewModel
    let onBoardTap: (ForumBoardSummary) -> Void
    let onCarouselTap: (ForumHomeCarouselItem) -> Void
    let onSearchTap: () -> Void
    let onWebFallbackTap: () -> Void

    var body: some View {
        Group {
            if model.isLoading && model.page == nil {
                ForumHomeLoadingView()
            } else if let error = model.errorMessage, model.page == nil {
                ForumHomeErrorView(message: error, retry: retry, openWebFallback: onWebFallbackTap)
            } else if model.categories.isEmpty {
                ForumHomeEmptyView(openWebFallback: onWebFallbackTap)
            } else {
                ForumHomeContentView(
                    categories: model.categories,
                    carouselItems: model.carouselItems,
                    expandedCategoryIDs: model.expandedCategoryIDs,
                    isRefreshing: model.isRefreshing,
                    toggleCategory: model.toggleCategory,
                    refresh: refresh,
                    onBoardTap: onBoardTap,
                    onCarouselTap: onCarouselTap,
                    onSearchTap: onSearchTap
                )
            }
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
}

private struct ForumHomeContentView: View {
    let categories: [ForumCategory]
    let carouselItems: [ForumHomeCarouselItem]
    let expandedCategoryIDs: Set<String>
    let isRefreshing: Bool
    let toggleCategory: (String) -> Void
    let refresh: () async -> Void
    let onBoardTap: (ForumBoardSummary) -> Void
    let onCarouselTap: (ForumHomeCarouselItem) -> Void
    let onSearchTap: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                ForumHomeHeaderView(onSearchTap: onSearchTap)

                if !carouselItems.isEmpty {
                    ForumHomeCarouselView(items: carouselItems, onTap: onCarouselTap)
                }

                ForEach(categories) { category in
                    ForumCategorySectionView(
                        id: category.id,
                        title: category.title,
                        boards: category.boards,
                        isExpanded: expandedCategoryIDs.contains(category.id),
                        toggle: toggleCategory,
                        onBoardTap: onBoardTap
                    )
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

private struct ForumHomeHeaderView: View {
    let onSearchTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("百合会")
                    .font(.title2.weight(.semibold))
                Text(L10n.string("forum.default_title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onSearchTap) {
                Label(L10n.string("forum.home.search_placeholder"), systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.quaternary, in: Circle())
            }
            .accessibilityLabel(L10n.string("forum.home.search_placeholder"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ForumHomeCarouselView: View {
    let items: [ForumHomeCarouselItem]
    let onTap: (ForumHomeCarouselItem) -> Void

    @State private var selection = 0

    var body: some View {
        VStack(spacing: 8) {
            #if os(iOS)
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ForumCarouselImageButton(item: item, onTap: onTap)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
            .frame(maxWidth: .infinity)
            .aspectRatio(2.63, contentMode: .fit)
            #else
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        ForumCarouselImageButton(item: item, onTap: onTap)
                            .frame(width: 320)
                    }
                }
            }
            #endif
        }
        .task(id: items.map(\.id)) {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    selection = (selection + 1) % items.count
                }
            }
        }
    }
}

private struct ForumCarouselImageButton: View {
    let item: ForumHomeCarouselItem
    let onTap: (ForumHomeCarouselItem) -> Void

    var body: some View {
        Button {
            onTap(item)
        } label: {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                case .empty:
                    ZStack {
                        Rectangle().fill(.quaternary)
                        ProgressView()
                    }
                @unknown default:
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(2.63, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ForumCategorySectionView: View {
    let id: String
    let title: String
    let boards: [ForumBoardSummary]
    let isExpanded: Bool
    let toggle: (String) -> Void
    let onBoardTap: (ForumBoardSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    toggle(id)
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(L10n.string(isExpanded ? "common.collapse" : "common.expand"))

            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(boards) { board in
                        ForumBoardRowView(
                            fid: board.fid,
                            name: board.name,
                            detail: board.detail,
                            todayCount: board.todayCount,
                            iconURL: board.iconURL,
                            onTap: {
                                onBoardTap(board)
                            }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ForumBoardRowView: View {
    let fid: String
    let name: String
    let detail: String?
    let todayCount: Int?
    let iconURL: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ForumBoardIconView(iconURL: iconURL, name: name)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let todayCount {
                            Text(L10n.string("forum.home.today_count", todayCount))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.red.opacity(0.1), in: Capsule())
                        }
                    }

                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("forum-board-row-\(fid)")
    }
}

private struct ForumBoardIconView: View {
    let iconURL: URL?
    let name: String

    var body: some View {
        AsyncImage(url: iconURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            default:
                Image(systemName: "text.bubble")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct ForumHomeLoadingView: View {
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

private struct ForumHomeErrorView: View {
    let message: String
    let retry: () -> Void
    let openWebFallback: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("common.load_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            ViewThatFits {
                HStack {
                    Button(L10n.string("common.retry"), action: retry)
                    Button(L10n.string("forum.home.open_web_fallback"), action: openWebFallback)
                }
                VStack {
                    Button(L10n.string("common.retry"), action: retry)
                    Button(L10n.string("forum.home.open_web_fallback"), action: openWebFallback)
                }
            }
        }
    }
}

private struct ForumHomeEmptyView: View {
    let openWebFallback: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("forum.home.empty"), systemImage: "rectangle.stack")
        } description: {
            Text(L10n.string("forum.home.parser_fallback"))
        } actions: {
            Button(L10n.string("forum.home.open_web_fallback"), action: openWebFallback)
        }
    }
}
