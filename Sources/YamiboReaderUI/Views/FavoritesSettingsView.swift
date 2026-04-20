import SwiftUI
import YamiboReaderCore

private enum FavoritesSettingsAction: Equatable {
    case loading
    case clearingNovelCache
    case clearingMangaCache
    case resettingApplication
}

private enum FavoritesSettingsConfirmation: String, Identifiable {
    case clearNovelCache
    case clearMangaCache
    case resetApplication

    var id: String { rawValue }
}

@MainActor
private final class FavoritesSettingsViewModel: ObservableObject {
    @Published var showsNavigationBar = true
    @Published private(set) var novelCacheBytes = 0
    @Published private(set) var mangaCacheBytes = 0
    @Published private(set) var activeAction: FavoritesSettingsAction?
    @Published var errorMessage: String?

    private let appContext: YamiboAppContext

    init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    var isBusy: Bool {
        activeAction != nil
    }

    var novelCacheLabel: String {
        cacheLabel(for: novelCacheBytes)
    }

    var mangaCacheLabel: String {
        cacheLabel(for: mangaCacheBytes)
    }

    func load() async {
        activeAction = .loading
        defer { activeAction = nil }

        let settings = await appContext.settingsStore.load()
        showsNavigationBar = settings.webBrowser.showsNavigationBar
        await refreshStorageUsage()
    }

    func updateShowsNavigationBar(_ value: Bool) {
        let previous = showsNavigationBar
        showsNavigationBar = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.webBrowser.showsNavigationBar = value

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    showsNavigationBar = previous
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func clearNovelCache() async -> Bool {
        activeAction = .clearingNovelCache
        defer { activeAction = nil }

        do {
            try await appContext.readerCacheStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearMangaCache() async -> Bool {
        activeAction = .clearingMangaCache
        defer { activeAction = nil }

        do {
            try await appContext.mangaImageCacheStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resetApplication() async -> Bool {
        activeAction = .resettingApplication
        defer { activeAction = nil }

        do {
            try await appContext.resetApplicationData()
            showsNavigationBar = true
            novelCacheBytes = 0
            mangaCacheBytes = 0
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshStorageUsage() async {
        async let novelBytes = appContext.readerCacheStore.totalDiskUsageBytes()
        async let mangaBytes = appContext.mangaImageCacheStore.totalDiskUsageBytes()
        novelCacheBytes = await novelBytes
        mangaCacheBytes = await mangaBytes
    }

    private func cacheLabel(for bytes: Int) -> String {
        let megabytes = Double(max(0, bytes)) / 1_048_576
        return String(format: "%.2f MB", megabytes)
    }
}

public struct FavoritesSettingsView: View {
    @StateObject private var viewModel: FavoritesSettingsViewModel
    @State private var showingDirectoryManager = false
    @State private var pendingConfirmation: FavoritesSettingsConfirmation?

    private let appContext: YamiboAppContext
    private let onApplicationReset: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        appContext: YamiboAppContext,
        onApplicationReset: @escaping @MainActor () async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: FavoritesSettingsViewModel(appContext: appContext))
        self.appContext = appContext
        self.onApplicationReset = onApplicationReset
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("网页浏览") {
                    Toggle(
                        "显示网址导航栏",
                        isOn: Binding(
                            get: { viewModel.showsNavigationBar },
                            set: { viewModel.updateShowsNavigationBar($0) }
                        )
                    )
                    .disabled(viewModel.isBusy)
                }

                Section("存储管理") {
                    Button {
                        showingDirectoryManager = true
                    } label: {
                        settingsRow(title: "漫画目录管理")
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearNovelCache
                    } label: {
                        settingsRow(
                            title: "清除小说缓存",
                            value: viewModel.novelCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearMangaCache
                    } label: {
                        settingsRow(
                            title: "清除漫画缓存",
                            value: viewModel.mangaCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button(role: .destructive) {
                        pendingConfirmation = .resetApplication
                    } label: {
                        Text("初始化应用")
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .disabled(viewModel.activeAction == .resettingApplication)
                }
            }
            .overlay {
                if viewModel.activeAction == .loading || viewModel.activeAction == .resettingApplication {
                    ProgressView(viewModel.activeAction == .resettingApplication ? "初始化应用中…" : "加载中…")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showingDirectoryManager) {
                MangaDirectoryManagementView(store: appContext.mangaDirectoryStore)
            }
            .alert("操作失败", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert(
                confirmationTitle,
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingConfirmation = nil
                        }
                    }
                ),
                presenting: pendingConfirmation
            ) { confirmation in
                Button(confirmationButtonTitle(for: confirmation), role: .destructive) {
                    Task {
                        await handleConfirmation(confirmation)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { confirmation in
                Text(confirmationMessage(for: confirmation))
            }
        }
    }

    @ViewBuilder
    private func settingsRow(title: String, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var confirmationTitle: String {
        switch pendingConfirmation {
        case .clearNovelCache:
            "确认清除小说缓存"
        case .clearMangaCache:
            "确认清除漫画缓存"
        case .resetApplication:
            "确认初始化应用"
        case nil:
            ""
        }
    }

    private func confirmationButtonTitle(for confirmation: FavoritesSettingsConfirmation) -> String {
        switch confirmation {
        case .clearNovelCache, .clearMangaCache:
            "清除"
        case .resetApplication:
            "初始化"
        }
    }

    private func confirmationMessage(for confirmation: FavoritesSettingsConfirmation) -> String {
        switch confirmation {
        case .clearNovelCache:
            "将清除所有本地小说阅读缓存。"
        case .clearMangaCache:
            "将清除所有本地漫画图片缓存。"
        case .resetApplication:
            "这将清空登录态、收藏本地状态、全部缓存、漫画目录和应用设置，并移除网页持久化数据。"
        }
    }

    private func handleConfirmation(_ confirmation: FavoritesSettingsConfirmation) async {
        switch confirmation {
        case .clearNovelCache:
            _ = await viewModel.clearNovelCache()
        case .clearMangaCache:
            _ = await viewModel.clearMangaCache()
        case .resetApplication:
            let didReset = await viewModel.resetApplication()
            guard didReset else { return }
            dismiss()
            await onApplicationReset()
        }
    }
}
