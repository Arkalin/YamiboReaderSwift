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

private enum FavoriteAppearanceCategory: String, CaseIterable, Identifiable {
    case collection
    case novel
    case manga
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: L10n.string("favorite_category.collection")
        case .novel: L10n.string("favorite_category.novel")
        case .manga: L10n.string("favorite_category.manga")
        case .other: L10n.string("favorite_category.other")
        }
    }
}

private extension FavoriteAppearanceSettings {
    func color(for category: FavoriteAppearanceCategory) -> FavoriteAppearanceColor {
        switch category {
        case .collection: collection
        case .novel: novel
        case .manga: manga
        case .other: other
        }
    }

    mutating func setColor(_ color: FavoriteAppearanceColor, for category: FavoriteAppearanceCategory) {
        switch category {
        case .collection:
            collection = color
        case .novel:
            novel = color
        case .manga:
            manga = color
        case .other:
            other = color
        }
    }
}

@MainActor
private final class FavoritesSettingsViewModel: ObservableObject {
    @Published var homePage: AppHomePage = .forum
    @Published var showsNavigationBar = true
    @Published var favoriteAppearance = FavoriteAppearanceSettings()
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
        homePage = settings.homePage
        showsNavigationBar = settings.webBrowser.showsNavigationBar
        favoriteAppearance = settings.favoriteAppearance
        await refreshStorageUsage()
    }

    func updateHomePage(_ value: AppHomePage) {
        let previous = homePage
        homePage = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.homePage = value

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    homePage = previous
                    errorMessage = error.localizedDescription
                }
            }
        }
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

    func updateFavoriteAppearanceColor(_ color: FavoriteAppearanceColor, for category: FavoriteAppearanceCategory) {
        let previous = favoriteAppearance
        var updated = favoriteAppearance
        updated.setColor(color, for: category)
        favoriteAppearance = updated

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favoriteAppearance = updated

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteAppearance == updated {
                        favoriteAppearance = previous
                    }
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
            homePage = .forum
            showsNavigationBar = true
            favoriteAppearance = .init()
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
    @State private var activeAppearanceCategory: FavoriteAppearanceCategory?

    private let appContext: YamiboAppContext
    private let onApplicationReset: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
                Section(L10n.string("settings.section.general")) {
                    homePageSelector

                    Button {
                        openAutoSignInAutomationCreator()
                    } label: {
                        settingsRow(title: L10n.string("settings.auto_sign_in"))
                    }
                    .disabled(viewModel.isBusy)
                }

                Section(L10n.string("settings.section.appearance")) {
                    ForEach(FavoriteAppearanceCategory.allCases) { category in
                        colorSelectorRow(for: category)
                    }

                    Toggle(
                        L10n.string("settings.show_web_title_url"),
                        isOn: Binding(
                            get: { viewModel.showsNavigationBar },
                            set: { viewModel.updateShowsNavigationBar($0) }
                        )
                    )
                    .disabled(viewModel.isBusy)
                }

                Section(L10n.string("settings.section.storage")) {
                    Button {
                        showingDirectoryManager = true
                    } label: {
                        settingsRow(title: L10n.string("settings.manga_directory_management"))
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearNovelCache
                    } label: {
                        settingsRow(
                            title: L10n.string("settings.clear_novel_cache"),
                            value: viewModel.novelCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearMangaCache
                    } label: {
                        settingsRow(
                            title: L10n.string("settings.clear_manga_cache"),
                            value: viewModel.mangaCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button(role: .destructive) {
                        pendingConfirmation = .resetApplication
                    } label: {
                        Text(L10n.string("settings.reset_application"))
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .navigationTitle(L10n.string("settings.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                    .disabled(viewModel.activeAction == .resettingApplication)
                }
            }
            .overlay {
                if viewModel.activeAction == .loading || viewModel.activeAction == .resettingApplication {
                    ProgressView(viewModel.activeAction == .resettingApplication ? L10n.string("settings.resetting_application") : L10n.string("common.loading"))
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
            .alert(L10n.string("common.operation_failed"), isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button(L10n.string("common.ok")) {
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
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: { confirmation in
                Text(confirmationMessage(for: confirmation))
            }
        }
    }

    private var homePageSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("settings.home_page"))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                ForEach([AppHomePage.forum, .favorites], id: \.self) { option in
                    Button {
                        viewModel.updateHomePage(option)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.systemImageName)
                                .font(.subheadline.weight(.semibold))
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(viewModel.homePage == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(viewModel.homePage == option ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy)
                }
            }
        }
        .padding(.vertical, 4)
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

    private func colorSelectorRow(for category: FavoriteAppearanceCategory) -> some View {
        let selectedColor = viewModel.favoriteAppearance.color(for: category)

        return VStack(alignment: .trailing, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    activeAppearanceCategory = activeAppearanceCategory == category ? nil : category
                }
            } label: {
                HStack(spacing: 10) {
                    Text(category.title)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    colorSwatch(selectedColor)

                    Text(selectedColor.title)
                        .foregroundStyle(.secondary)

                    Image(systemName: activeAppearanceCategory == category ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy)

            if activeAppearanceCategory == category {
                colorPaletteBubble(for: category, selectedColor: selectedColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .padding(.vertical, 6)
    }

    private func colorPaletteBubble(
        for category: FavoriteAppearanceCategory,
        selectedColor: FavoriteAppearanceColor
    ) -> some View {
        let columns = Array(repeating: GridItem(.fixed(34), spacing: 12), count: 5)

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(FavoriteAppearanceColor.allCases, id: \.self) { color in
                Button {
                    viewModel.updateFavoriteAppearanceColor(color, for: category)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.95)) {
                        activeAppearanceCategory = nil
                    }
                } label: {
                    colorChoiceSwatch(color, isSelected: selectedColor == color)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .accessibilityLabel("\(category.title)\(color.title)")
                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.09))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }

                BubbleArrow()
                    .fill(Color.secondary.opacity(0.09))
                    .frame(width: 18, height: 10)
                    .offset(x: -28, y: -9)
            }
        }
        .padding(.top, 2)
    }

    private func colorSwatch(_ color: FavoriteAppearanceColor) -> some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: 14, height: 14)
            .overlay {
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private func colorChoiceSwatch(_ color: FavoriteAppearanceColor, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 28, height: 28)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .overlay {
            Circle()
                .strokeBorder(isSelected ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 0.75)
        }
        .contentShape(Circle())
    }

    private var confirmationTitle: String {
        switch pendingConfirmation {
        case .clearNovelCache:
            L10n.string("settings.confirm_clear_novel_cache")
        case .clearMangaCache:
            L10n.string("settings.confirm_clear_manga_cache")
        case .resetApplication:
            L10n.string("settings.confirm_reset_application")
        case nil:
            ""
        }
    }

    private func openAutoSignInAutomationCreator() {
        guard let url = URL(string: "shortcuts://create-automation") else {
            viewModel.errorMessage = L10n.string("settings.shortcuts_open_failed")
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            viewModel.errorMessage = L10n.string("settings.shortcuts_open_failed")
        }
    }

    private func confirmationButtonTitle(for confirmation: FavoritesSettingsConfirmation) -> String {
        switch confirmation {
        case .clearNovelCache, .clearMangaCache:
            L10n.string("common.clear")
        case .resetApplication:
            L10n.string("settings.reset")
        }
    }

    private func confirmationMessage(for confirmation: FavoritesSettingsConfirmation) -> String {
        switch confirmation {
        case .clearNovelCache:
            L10n.string("settings.clear_novel_cache_message")
        case .clearMangaCache:
            L10n.string("settings.clear_manga_cache_message")
        case .resetApplication:
            L10n.string("settings.reset_application_message")
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

private struct BubbleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
