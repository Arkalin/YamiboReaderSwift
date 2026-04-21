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

enum FavoriteLaunchMode: Sendable {
    case start
    case resume
}

@MainActor
public final class FavoritesViewModel: ObservableObject {
    @Published public private(set) var favorites: [Favorite] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var resolvingFavoriteID: String?
    @Published public private(set) var deletingFavoriteID: String?
    @Published public var errorMessage: String?

    private let appContext: YamiboAppContext
    private let favoriteStore: FavoriteStore
    private var favoriteUpdatesTask: Task<Void, Never>?

    public init(appContext: YamiboAppContext, favoriteStore: FavoriteStore) {
        self.appContext = appContext
        self.favoriteStore = favoriteStore
        favoriteUpdatesTask = Task { @MainActor [weak self, favoriteStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String,
                      changeID == favoriteStore.changeID else {
                    continue
                }
                await self.reloadLocalFavorites()
            }
        }
    }

    deinit {
        favoriteUpdatesTask?.cancel()
    }

    public func loadCachedFavorites() async {
        favorites = await favoriteStore.loadFavorites()
    }

    public func reloadLocalFavorites() async {
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

    public func setDisplayName(_ displayName: String?, for favorite: Favorite) async {
        await setDisplayName(displayName, forFavoriteID: favorite.id, originalTitle: favorite.title)
    }

    public func setDisplayName(_ displayName: String?, forFavoriteID favoriteID: String, originalTitle: String) async {
        do {
            let normalized = displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let valueToPersist: String? = if let normalized, !normalized.isEmpty, normalized != originalTitle {
                normalized
            } else {
                nil
            }
            favorites = try await favoriteStore.setDisplayName(valueToPersist, for: favoriteID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteFavorite(_ favorite: Favorite) async {
        guard deletingFavoriteID == nil else { return }
        guard let remoteFavoriteID = favorite.remoteFavoriteID, !remoteFavoriteID.isEmpty else {
            errorMessage = YamiboError.missingFavoriteDeleteID.localizedDescription
            return
        }

        deletingFavoriteID = favorite.id
        defer { deletingFavoriteID = nil }

        do {
            let repository = await appContext.makeRepository()
            try await repository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
            favorites = try await favoriteStore.deleteFavorite(id: favorite.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTarget(for favorite: Favorite, mode: FavoriteLaunchMode = .resume) async -> FavoriteOpenTarget {
        let latestFavorite = await favoriteStore.favorite(id: favorite.id) ?? favorite

        switch latestFavorite.type {
        case .novel:
            return .reader(
                ReaderLaunchContext(
                    threadURL: latestFavorite.url,
                    threadTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialView: mode == .start ? 1 : nil,
                    initialPage: mode == .start ? 0 : nil,
                    authorID: latestFavorite.authorID
                )
            )
        case .manga:
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: latestFavorite.url,
                    chapterURL: mode == .start ? latestFavorite.url : (latestFavorite.lastMangaURL ?? latestFavorite.url),
                    displayTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialPage: mode == .start ? 0 : latestFavorite.lastPage
                )
            )
        case .other:
            return .web(latestFavorite)
        case .unknown:
            resolvingFavoriteID = latestFavorite.id
            defer { resolvingFavoriteID = nil }

            do {
                let resolver = await appContext.makeThreadOpenResolver()
                let target = try await resolver.resolve(
                    threadURL: latestFavorite.url,
                    title: latestFavorite.resolvedDisplayTitle,
                    htmlOverride: nil,
                    favoriteType: .unknown,
                    favoriteChapterURL: latestFavorite.lastMangaURL,
                    initialPage: latestFavorite.lastPage
                )

                switch target {
                case let .novel(context):
                    favorites = try await favoriteStore.setType(.novel, for: latestFavorite.id)
                    return .reader(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case let .manga(context):
                    favorites = try await favoriteStore.setType(.manga, for: latestFavorite.id)
                    return .manga(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case .web:
                    favorites = try await favoriteStore.setType(.other, for: latestFavorite.id)
                    var updated = latestFavorite
                    updated.type = .other
                    return .web(updated)
                }
            } catch {
                errorMessage = error.localizedDescription
                return .web(latestFavorite)
            }
        }
    }

    func resolveOpenTarget(for favorite: Favorite) async -> FavoriteOpenTarget {
        await openTarget(for: favorite, mode: .resume)
    }

    private func applyStartModeIfNeeded(
        to context: ReaderLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> ReaderLaunchContext {
        guard mode == .start else { return context }

        return ReaderLaunchContext(
            threadURL: context.threadURL,
            threadTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialView: 1,
            initialPage: 0,
            authorID: context.authorID
        )
    }

    private func applyStartModeIfNeeded(
        to context: MangaLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> MangaLaunchContext {
        guard mode == .start else { return context }

        return MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: favorite.url,
            displayTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialPage: 0,
            directoryName: context.directoryName
        )
    }
}

public enum FavoriteOpenTarget: Sendable {
    case reader(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(Favorite)
}

private struct FavoriteDisplayNameDraft {
    let favoriteID: String
    let originalTitle: String
    var displayName: String

    init(favorite: Favorite) {
        favoriteID = favorite.id
        originalTitle = favorite.title
        displayName = favorite.displayName ?? favorite.resolvedDisplayTitle
    }
}

public struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @AppStorage("yamibo.favorite.filter") private var filterRawValue = FavoriteFilter.all.rawValue
    @AppStorage("yamibo.favorite.sort") private var sortRawValue = FavoriteSortOrder.manual.rawValue
    @AppStorage("yamibo.favorite.showHidden") private var showsHidden = false
    @State private var searchText = ""
    @State private var selectedFavorite: Favorite?
    @State private var showingSettingsSheet = false
    @State private var displayNameDraft: FavoriteDisplayNameDraft?
    @State private var pendingDeleteFavorite: Favorite?
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
                FavoriteRow(
                    favorite: favorite,
                    isResolving: viewModel.resolvingFavoriteID == favorite.id,
                    isDeleting: viewModel.deletingFavoriteID == favorite.id,
                    onOpen: {
                        open(favorite, mode: .resume)
                    }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    ShareLink(item: favorite.url) {
                        swipeActionLabel(title: "分享", systemImage: "square.and.arrow.up")
                    }
                    .tint(.teal)
                    .disabled(viewModel.deletingFavoriteID != nil)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeleteFavorite = favorite
                    } label: {
                        swipeActionLabel(
                            title: viewModel.deletingFavoriteID == favorite.id ? "删除中" : "删除",
                            systemImage: "trash"
                        )
                    }
                    .tint(.red)
                    .disabled(viewModel.deletingFavoriteID != nil)

                    Button {
                        displayNameDraft = FavoriteDisplayNameDraft(favorite: favorite)
                    } label: {
                        swipeActionLabel(title: "编辑", systemImage: "pencil")
                    }
                    .tint(.indigo)
                    .disabled(viewModel.deletingFavoriteID != nil)
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading {
                    ProgressView("同步收藏中…")
                } else if filteredFavorites.isEmpty {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("暂无收藏", systemImage: "books.vertical")
                    } else {
                        ContentUnavailableView("没有匹配结果", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索"
            )
            #else
            .searchable(text: $searchText, prompt: "搜索")
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingSettingsSheet = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }

                        Button {} label: {
                            Label("关于", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #else
                ToolbarItem {
                    Menu {
                        Button {
                            showingSettingsSheet = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }

                        Button {} label: {
                            Label("关于", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #endif

                ToolbarItem(placement: .principal) {
                    Menu {
                        favoritesToolbarMenuContent
                    } label: {
                        titleMenuLabel
                    }
                }

                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) {
                        Text("选择")
                    }
                }
                #else
                ToolbarItem {
                    Button(action: {}) {
                        Text("选择")
                    }
                }
                #endif
            }
            .task {
                await viewModel.loadCachedFavorites()
                await viewModel.refresh()
            }
            .onChange(of: filterRawValue) { _, _ in
                searchText = ""
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
            .alert("编辑显示名称", isPresented: editNameAlertBinding) {
                TextField("显示名称", text: displayNameTextBinding)
                Button("取消", role: .cancel) {
                    displayNameDraft = nil
                }
                Button("保存") {
                    guard let draft = displayNameDraft else { return }
                    Task {
                        await viewModel.setDisplayName(
                            draft.displayName,
                            forFavoriteID: draft.favoriteID,
                            originalTitle: draft.originalTitle
                        )
                    }
                    displayNameDraft = nil
                }
            } message: {
                Text("留空后将恢复显示原标题。")
            }
            .alert(
                "删除收藏",
                isPresented: pendingDeleteAlertBinding,
                presenting: pendingDeleteFavorite
            ) { favorite in
                Button("取消", role: .cancel) {
                    pendingDeleteFavorite = nil
                }
                Button("删除", role: .destructive) {
                    Task {
                        await viewModel.deleteFavorite(favorite)
                    }
                    pendingDeleteFavorite = nil
                }
            } message: { favorite in
                Text("确定要删除“\(favorite.resolvedDisplayTitle)”吗？这会同步删除远端收藏，但会保留本地缓存和阅读进度。")
            }
            .sheet(item: $selectedFavorite) { favorite in
                ForumBrowserView(url: favorite.url, appContext: appContext, appModel: appModel)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingSettingsSheet) {
                FavoritesSettingsView(appContext: appContext) {
                    filterRawValue = FavoriteFilter.all.rawValue
                    sortRawValue = FavoriteSortOrder.manual.rawValue
                    showsHidden = false
                    searchText = ""
                    await appModel.bootstrap()
                }
            }
        }
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var editNameAlertBinding: Binding<Bool> {
        Binding(
            get: { displayNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    displayNameDraft = nil
                }
            }
        )
    }

    private var displayNameTextBinding: Binding<String> {
        Binding(
            get: { displayNameDraft?.displayName ?? "" },
            set: { displayNameDraft?.displayName = $0 }
        )
    }

    private var pendingDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteFavorite != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteFavorite = nil
                }
            }
        )
    }

    @ViewBuilder
    private var favoritesToolbarMenuContent: some View {
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
    }

    private var titleMenuLabel: some View {
        HStack(spacing: 6) {
            Text(currentFilter.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var filteredFavorites: [Favorite] {
        let sortOrder = FavoriteSortOrder(rawValue: sortRawValue) ?? .manual
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = viewModel.favorites
            .filter { showsHidden || !$0.isHidden }
            .filter { currentFilter.matches($0) }
            .filter { favorite in
                guard !trimmedSearchText.isEmpty else { return true }
                return favorite.resolvedDisplayTitle.localizedCaseInsensitiveContains(trimmedSearchText)
            }

        switch sortOrder {
        case .manual:
            return filtered
        case .title:
            return filtered.sorted { lhs, rhs in
                lhs.resolvedDisplayTitle.localizedCompare(rhs.resolvedDisplayTitle) == .orderedAscending
            }
        case .progress:
            return filtered.sorted { lhs, rhs in
                progressScore(for: lhs) > progressScore(for: rhs)
            }
        }
    }

    private func open(_ favorite: Favorite, mode: FavoriteLaunchMode) {
        Task {
            let target = await viewModel.openTarget(for: favorite, mode: mode)
            switch target {
            case let .reader(context):
                appModel.presentReader(context)
            case let .manga(context):
                await appModel.openManga(context)
            case let .web(resolvedFavorite):
                selectedFavorite = resolvedFavorite
            }
        }
    }

    @ViewBuilder
    private func swipeActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
    }
}

struct FavoriteRow: View {
    let favorite: Favorite
    let isResolving: Bool
    let isDeleting: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(favoriteAccentColor(for: favorite.type))
                    .frame(width: 5)
                    .padding(.vertical, 14)
                    .padding(.leading, 10)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(favorite.resolvedDisplayTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isResolving {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 2)
                        } else if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(favoriteDetailLines(for: favorite), id: \.self) { line in
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if favorite.isHidden {
                            Label("已隐藏", systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.leading, 16)
                .padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(favoriteAccentColor(for: favorite.type).opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

func favoriteProgressScore(for favorite: Favorite) -> Int {
    favorite.lastView * 1000 + favorite.lastPage
}

func progressScore(for favorite: Favorite) -> Int {
    favoriteProgressScore(for: favorite)
}

func favoriteProgressText(for favorite: Favorite) -> String? {
    if favorite.type == .novel,
       let chapterTitle = favorite.novelResumePoint?.chapterTitle,
       !chapterTitle.isEmpty {
        return chapterTitle
    }
    if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
        if favorite.type == .manga, favorite.lastPage > 0 {
            if let chapterLabel = favoriteMangaChapterLabel(from: lastChapter) {
                return "读至第 \(favorite.lastPage + 1) 页 · \(chapterLabel)"
            }
            return "读至第 \(favorite.lastPage + 1) 页"
        }
        return lastChapter
    }
    if favorite.type == .manga, favorite.lastPage > 0 {
        return "读至第 \(favorite.lastPage + 1) 页"
    }
    if favorite.lastPage > 0 || favorite.lastView > 1 {
        return "第\(favorite.lastPage + 1)页 / 网页第\(favorite.lastView)页"
    }
    return nil
}

func favoriteMangaChapterLabel(from rawTitle: String) -> String? {
    let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return nil }

    let chapterNumber = MangaTitleCleaner.extractChapterNumber(trimmedTitle)
    let displayNumber = MangaChapterDisplayFormatter.displayNumber(
        rawTitle: trimmedTitle,
        chapterNumber: chapterNumber
    )

    guard !displayNumber.isEmpty else { return nil }
    return "第\(displayNumber)话"
}

func favoriteDetailLines(for favorite: Favorite) -> [String] {
    var lines: [String] = []

    if favorite.type == .manga {
        if let progressText = favoriteProgressText(for: favorite) {
            lines.append(progressText)
        } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !lastChapter.isEmpty {
            lines.append(lastChapter)
        }

        if lines.isEmpty {
            lines.append(favorite.type.title)
        }

        return Array(lines.prefix(1))
    }

    if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
       !lastChapter.isEmpty {
        lines.append(lastChapter)
    }

    if favorite.type == .novel {
        if favorite.lastPage > 0 || favorite.lastView > 1 {
            lines.append("读至第 \(favorite.lastPage + 1) 页 · 网页第 \(favorite.lastView) 页")
        }
    } else if let progressText = favoriteProgressText(for: favorite),
              !lines.contains(progressText) {
        lines.append(progressText)
    }

    if lines.isEmpty {
        lines.append(favorite.type.title)
    }

    return Array(lines.prefix(2))
}

func favoriteAccentColor(for type: FavoriteType) -> Color {
    switch type {
    case .unknown: .gray
    case .novel: .green
    case .manga: .blue
    case .other: .orange
    }
}
