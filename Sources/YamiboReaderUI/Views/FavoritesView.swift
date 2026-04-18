import SwiftUI
import YamiboReaderCore

public enum FavoriteFilter: String, CaseIterable, Identifiable {
    case all
    case novel
    case manga
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部"
        case .novel: "小说"
        case .manga: "漫画"
        case .other: "其他"
        }
    }

    fileprivate func matches(_ favorite: Favorite) -> Bool {
        switch self {
        case .all:
            true
        case .novel:
            favorite.type == .novel
        case .manga:
            favorite.type == .manga
        case .other:
            favorite.type == .other || favorite.type == .unknown
        }
    }
}

public enum FavoriteSortOrder: String, CaseIterable, Identifiable {
    case manual
    case title
    case progress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "默认"
        case .title: "标题"
        case .progress: "进度"
        }
    }
}

@MainActor
public final class FavoritesViewModel: ObservableObject {
    @Published public private(set) var favorites: [Favorite] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var resolvingFavoriteID: String?
    @Published public var errorMessage: String?

    private let appContext: YamiboAppContext
    private let favoriteStore: FavoriteStore

    public init(appContext: YamiboAppContext, favoriteStore: FavoriteStore) {
        self.appContext = appContext
        self.favoriteStore = favoriteStore
    }

    public func loadCachedFavorites() async {
        favorites = await favoriteStore.loadFavorites()
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = await appContext.makeRepository()
            let remote = try await repository.fetchFavorites()
            favorites = try await favoriteStore.mergeRemoteFavorites(remote)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setHidden(_ isHidden: Bool, for favorite: Favorite) async {
        do {
            favorites = try await favoriteStore.setHidden(isHidden, for: favorite.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resolveOpenTarget(for favorite: Favorite) async -> FavoriteOpenTarget {
        switch favorite.type {
        case .novel:
            return .reader(favorite)
        case .manga, .other:
            return .web(favorite)
        case .unknown:
            resolvingFavoriteID = favorite.id
            defer { resolvingFavoriteID = nil }

            do {
                let repository = await appContext.makeReaderRepository()
                let title = try await repository.fetchThreadDisplayTitle(for: favorite.url, authorID: favorite.authorID)
                if ReaderModeDetector.canOpenReader(url: favorite.url, title: title) {
                    favorites = try await favoriteStore.setType(.novel, for: favorite.id)
                    var updated = favorite
                    updated.type = .novel
                    return .reader(updated)
                }

                favorites = try await favoriteStore.setType(.other, for: favorite.id)
                var updated = favorite
                updated.type = .other
                return .web(updated)
            } catch {
                errorMessage = error.localizedDescription
                return .web(favorite)
            }
        }
    }
}

public enum FavoriteOpenTarget: Sendable {
    case reader(Favorite)
    case web(Favorite)
}

public struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @AppStorage("yamibo.favorite.filter") private var filterRawValue = FavoriteFilter.all.rawValue
    @AppStorage("yamibo.favorite.sort") private var sortRawValue = FavoriteSortOrder.manual.rawValue
    @AppStorage("yamibo.favorite.showHidden") private var showsHidden = false
    @State private var selectedFavorite: Favorite?
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(favoriteStore: FavoriteStore, appContext: YamiboAppContext, appModel: YamiboAppModel) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore))
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        NavigationStack {
            List(filteredFavorites) { favorite in
                Button {
                    Task {
                        let target = await viewModel.resolveOpenTarget(for: favorite)
                        switch target {
                        case let .reader(resolvedFavorite):
                            appModel.presentReader(
                                ReaderLaunchContext(
                                    threadURL: resolvedFavorite.url,
                                    threadTitle: resolvedFavorite.title,
                                    source: .favorites,
                                    initialView: resolvedFavorite.lastView,
                                    initialPage: resolvedFavorite.lastPage,
                                    authorID: resolvedFavorite.authorID
                                )
                            )
                        case let .web(resolvedFavorite):
                            selectedFavorite = resolvedFavorite
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color(for: favorite.type))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favorite.title)
                                .font(.headline)
                                .lineLimit(2)
                            if let progressText = progressText(for: favorite) {
                                Text(progressText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(favorite.type.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if favorite.isHidden {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        if viewModel.resolvingFavoriteID == favorite.id {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(favorite.isHidden ? "取消隐藏" : "隐藏") {
                        Task {
                            await viewModel.setHidden(!favorite.isHidden, for: favorite)
                        }
                    }
                    .tint(favorite.isHidden ? .green : .orange)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("同步收藏中…")
                } else if filteredFavorites.isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: "books.vertical")
                }
            }
            .navigationTitle("我的收藏")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("分类", selection: $filterRawValue) {
                            ForEach(FavoriteFilter.allCases) { filter in
                                Text(filter.title).tag(filter.rawValue)
                            }
                        }

                        Picker("排序", selection: $sortRawValue) {
                            ForEach(FavoriteSortOrder.allCases) { sortOrder in
                                Text(sortOrder.title).tag(sortOrder.rawValue)
                            }
                        }

                        Toggle("显示隐藏项", isOn: $showsHidden)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await viewModel.loadCachedFavorites()
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("加载失败", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .sheet(item: $selectedFavorite) { favorite in
                ForumBrowserView(url: favorite.url, appContext: appContext, appModel: appModel)
                    .ignoresSafeArea()
            }
        }
    }

    private var filteredFavorites: [Favorite] {
        let filter = FavoriteFilter(rawValue: filterRawValue) ?? .all
        let sortOrder = FavoriteSortOrder(rawValue: sortRawValue) ?? .manual

        let filtered = viewModel.favorites
            .filter { showsHidden || !$0.isHidden }
            .filter { filter.matches($0) }

        switch sortOrder {
        case .manual:
            return filtered
        case .title:
            return filtered.sorted { lhs, rhs in
                lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        case .progress:
            return filtered.sorted { lhs, rhs in
                progressScore(for: lhs) > progressScore(for: rhs)
            }
        }
    }

    private func progressScore(for favorite: Favorite) -> Int {
        favorite.lastView * 1000 + favorite.lastPage
    }

    private func progressText(for favorite: Favorite) -> String? {
        if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
            return lastChapter
        }
        if favorite.lastPage > 0 || favorite.lastView > 1 {
            return "第\(favorite.lastPage + 1)页 / 网页第\(favorite.lastView)页"
        }
        return nil
    }

    private func color(for type: FavoriteType) -> Color {
        switch type {
        case .unknown: .gray
        case .novel: .green
        case .manga: .blue
        case .other: .orange
        }
    }
}
