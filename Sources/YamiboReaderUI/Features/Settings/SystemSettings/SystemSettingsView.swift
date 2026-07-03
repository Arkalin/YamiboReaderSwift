import PhotosUI
import SwiftUI
import YamiboReaderCore

public struct SystemSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let appContext: YamiboAppContext
    private let onApplicationReset: @MainActor () async -> Void

    @StateObject private var viewModel: SystemSettingsViewModel
    @StateObject private var favoriteSyncViewModel: LocalFavoritesViewModel
    @State private var showingWebDAVSettings = false
    @State private var showingFavoriteRemoteSyncProgress = false
    @State private var showingPeripheralSettings = false
    @State private var showingOfflineCacheManagement = false
    @State private var showingAboutSheet = false
    @State private var pendingConfirmation: SystemSettingsConfirmation?
    @State private var activeAppearanceCategory: FavoriteAppearanceCategory?
    @State private var showingFavoriteBackgroundPicker = false
    @State private var favoriteBackgroundPickerItem: PhotosPickerItem?
    @State private var favoriteBackgroundPickerPurpose = FavoriteBackgroundPickerPurpose.initial
    @State private var favoriteBackgroundEditorDraft: FavoriteBackgroundEditorDraft?

    public init(
        appContext: YamiboAppContext,
        onApplicationReset: @escaping @MainActor () async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SystemSettingsViewModel(appContext: appContext))
        _favoriteSyncViewModel = StateObject(wrappedValue: LocalFavoritesViewModel(appContext: appContext))
        self.appContext = appContext
        self.onApplicationReset = onApplicationReset
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("settings.section.general")) {
                    SystemSettingsHomePageSelector(
                        homePage: viewModel.homePage,
                        isBusy: viewModel.isBusy,
                        onSelect: viewModel.updateHomePage
                    )

                    Button {
                        openCheckInAutomationCreator()
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.auto_sign_in"),
                            titleColor: .accentColor
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        openWebDAVSettings()
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.webdav_sync"),
                            titleColor: .accentColor
                        )
                    }
                    .disabled(viewModel.isBusy)

                    if favoriteSyncViewModel.remoteSyncSnapshot != nil {
                        Button {
                            showingFavoriteRemoteSyncProgress = true
                        } label: {
                            SystemSettingsRow(
                                title: L10n.string("settings.favorite_sync"),
                                value: favoriteRemoteSyncStatusLabel,
                                showsChevronAfterValue: true,
                                titleColor: .accentColor
                            )
                        }
                        .disabled(viewModel.isBusy)
                    }

                    Button {
                        showingPeripheralSettings = true
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.peripheral_behavior"),
                            titleColor: .accentColor
                        )
                    }
                    .disabled(viewModel.isBusy)
                }

                Section(L10n.string("settings.section.appearance")) {
                    Button {
                        openFavoriteBackgroundEditorOrPicker()
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.favorite_background"),
                            value: favoriteBackgroundStatusLabel,
                            showsChevronAfterValue: true
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Picker(
                        L10n.string("favorites.layout"),
                        selection: favoriteLayoutModeBinding
                    ) {
                        ForEach(FavoriteLibraryLayoutMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImageName)
                                .tag(mode)
                        }
                    }
                    .disabled(viewModel.isBusy)

                    Picker(
                        L10n.string("favorites.sort"),
                        selection: favoriteSortOrderBinding
                    ) {
                        ForEach(LocalFavoriteLibrarySortOrder.allCases) { sortOrder in
                            Text(sortOrder.title)
                                .tag(sortOrder)
                        }
                    }
                    .disabled(viewModel.isBusy)

                    Toggle(
                        L10n.string("favorites.sort.descending"),
                        isOn: favoriteSortDescendingBinding
                    )
                    .disabled(viewModel.isBusy)

                    Toggle(
                        L10n.string("favorites.category.show_counts"),
                        isOn: favoriteShowsCategoryCountsBinding
                    )
                    .disabled(viewModel.isBusy)

                    ForEach(FavoriteAppearanceCategory.allCases) { category in
                        FavoriteAppearanceColorSelectorRow(
                            category: category,
                            selectedColor: viewModel.favoriteAppearance.color(for: category),
                            isBusy: viewModel.isBusy,
                            onSelectColor: { color in
                                viewModel.updateFavoriteAppearanceColor(color, for: category)
                            },
                            activeCategory: $activeAppearanceCategory
                        )
                    }
                }

                Section(L10n.string("settings.section.storage")) {
                    Button {
                        pendingConfirmation = .clearNovelCache
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.clear_novel_cache"),
                            value: viewModel.novelCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearMangaIndexCache
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.clear_manga_index_cache"),
                            value: viewModel.mangaIndexCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearImageCache
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.clear_image_cache")
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        showingOfflineCacheManagement = true
                    } label: {
                        SystemSettingsRow(
                            title: L10n.string("settings.offline_cache.cleanup"),
                            value: viewModel.offlineCacheLabel,
                            showsChevronAfterValue: true
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

                Section(L10n.string("settings.section.support")) {
                    Button {
                        showingAboutSheet = true
                    } label: {
                        SystemSettingsRow(
                            title: aboutSettingsTitle,
                            titleColor: .accentColor
                        )
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .navigationTitle(L10n.string("settings.title"))
            .toolbar(content: toolbarContent)
            .overlay(content: loadingOverlay)
            .task {
                await viewModel.load()
                await favoriteSyncViewModel.load()
            }
            .sheet(isPresented: $showingWebDAVSettings) {
                WebDAVSyncSettingsView(appContext: appContext)
            }
            .sheet(isPresented: $showingFavoriteRemoteSyncProgress) {
                NavigationStack {
                    FavoriteRemoteSyncProgressSheet(
                        snapshot: favoriteSyncViewModel.remoteSyncSnapshot,
                        onResume: {
                            await favoriteSyncViewModel.resumeRemoteFavoriteSync()
                        },
                        onInterrupt: {
                            await favoriteSyncViewModel.interruptRemoteFavoriteSync()
                        },
                        onHide: {
                            await favoriteSyncViewModel.hideRemoteFavoriteSyncCard()
                        }
                    )
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView(appContext: appContext)
            }
            .navigationDestination(isPresented: $showingPeripheralSettings) {
                SystemSettingsPeripheralPageTurnView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $showingOfflineCacheManagement) {
                OfflineCacheManagementView(viewModel: viewModel)
            }
            .photosPicker(
                isPresented: $showingFavoriteBackgroundPicker,
                selection: $favoriteBackgroundPickerItem,
                matching: .images
            )
            .onChange(of: favoriteBackgroundPickerItem) { _, item in
                guard let item else { return }
                Task {
                    await handleFavoriteBackgroundPickerItem(item)
                    favoriteBackgroundPickerItem = nil
                }
            }
            .favoriteBackgroundEditorPresentation(isPresented: favoriteBackgroundEditorIsPresented) {
                if favoriteBackgroundEditorDraft != nil {
                    FavoriteBackgroundEditorView(
                        draft: favoriteBackgroundEditorDraftBinding,
                        onCancel: {
                            favoriteBackgroundEditorDraft = nil
                        },
                        onChangeImage: {
                            favoriteBackgroundPickerPurpose = .replacement
                            showingFavoriteBackgroundPicker = true
                        },
                        onApply: { draft in
                            await applyFavoriteBackgroundDraft(draft)
                        }
                    )
                }
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
                isPresented: confirmationIsPresented,
                presenting: pendingConfirmation
            ) { confirmation in
                Button(confirmation.buttonTitle, role: .destructive) {
                    Task {
                        await handleConfirmation(confirmation)
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: { confirmation in
                Text(confirmation.message)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.string("common.close")) {
                dismiss()
            }
            .disabled(viewModel.activeAction == .resettingApplication)
        }
    }

    @ViewBuilder
    private func loadingOverlay() -> some View {
        if viewModel.activeAction == .loading || viewModel.activeAction == .resettingApplication {
            ProgressView(loadingOverlayTitle)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var loadingOverlayTitle: String {
        viewModel.activeAction == .resettingApplication
            ? L10n.string("settings.resetting_application")
            : L10n.string("common.loading")
    }

    private var confirmationTitle: String {
        pendingConfirmation?.title ?? ""
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingConfirmation = nil
                }
            }
        )
    }

    private var favoriteBackgroundStatusLabel: String {
        viewModel.favoriteBackground.isEnabled
            ? L10n.string("settings.favorite_background.custom")
            : L10n.string("settings.favorite_background.default")
    }

    private var favoriteRemoteSyncStatusLabel: String {
        guard let snapshot = favoriteSyncViewModel.remoteSyncSnapshot else {
            return L10n.string("favorites.sync.status.none")
        }
        switch snapshot.status {
        case .running:
            return L10n.string("favorites.sync.status.running")
        case .completed:
            return L10n.string("favorites.sync.status.completed")
        case .failed:
            return L10n.string("favorites.sync.status.failed")
        case .interrupted:
            return L10n.string("favorites.sync.status.interrupted")
        }
    }

    private var favoriteLayoutModeBinding: Binding<FavoriteLibraryLayoutMode> {
        Binding(
            get: { viewModel.favoriteLayoutMode },
            set: { viewModel.updateFavoriteLayoutMode($0) }
        )
    }

    private var favoriteSortOrderBinding: Binding<LocalFavoriteLibrarySortOrder> {
        Binding(
            get: { viewModel.favoriteSortOrder },
            set: { viewModel.updateFavoriteSortOrder($0) }
        )
    }

    private var favoriteSortDescendingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.favoriteSortDescending },
            set: { viewModel.updateFavoriteSortDescending($0) }
        )
    }

    private var favoriteShowsCategoryCountsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.favoriteShowsCategoryCounts },
            set: { viewModel.updateFavoriteShowsCategoryCounts($0) }
        )
    }

    private var aboutSettingsTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return L10n.string(
            "settings.about_app_with_version",
            version?.isEmpty == false ? version! : "--"
        )
    }

    private var favoriteBackgroundEditorIsPresented: Binding<Bool> {
        Binding(
            get: { favoriteBackgroundEditorDraft != nil },
            set: { isPresented in
                if !isPresented {
                    favoriteBackgroundEditorDraft = nil
                }
            }
        )
    }

    private var favoriteBackgroundEditorDraftBinding: Binding<FavoriteBackgroundEditorDraft> {
        Binding(
            get: {
                favoriteBackgroundEditorDraft ?? FavoriteBackgroundEditorDraft(
                    imageData: nil,
                    imageSize: .zero,
                    settings: FavoriteBackgroundSettings()
                )
            },
            set: { favoriteBackgroundEditorDraft = $0 }
        )
    }

    private func openCheckInAutomationCreator() {
        guard let url = URL(string: "shortcuts://create-automation") else {
            viewModel.errorMessage = L10n.string("settings.shortcuts_open_failed")
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            viewModel.errorMessage = L10n.string("settings.shortcuts_open_failed")
        }
    }

    private func openWebDAVSettings() {
        Task { @MainActor in
            let session = await appContext.sessionStore.load()
            if session.isLoggedIn, !session.cookie.isEmpty {
                showingWebDAVSettings = true
            } else {
                viewModel.errorMessage = L10n.string("webdav.error.login_required")
            }
        }
    }

    private func openFavoriteBackgroundEditorOrPicker() {
        Task { @MainActor in
            if viewModel.favoriteBackground.isEnabled,
               let imageData = await viewModel.loadFavoriteBackgroundImageData(),
               let draft = FavoriteBackgroundEditorDraft.custom(
                   imageData: imageData,
                   settings: viewModel.favoriteBackground
               ) {
                favoriteBackgroundEditorDraft = draft
                return
            }

            favoriteBackgroundPickerPurpose = .initial
            showingFavoriteBackgroundPicker = true
        }
    }

    private func handleFavoriteBackgroundPickerItem(_ item: PhotosPickerItem) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                viewModel.errorMessage = L10n.string("favorite_background.load_failed")
                return
            }
            let imageData = try viewModel.normalizedFavoriteBackgroundImageData(from: sourceData)

            switch favoriteBackgroundPickerPurpose {
            case .initial:
                guard let draft = FavoriteBackgroundEditorDraft.custom(imageData: imageData) else {
                    viewModel.errorMessage = L10n.string("favorite_background.load_failed")
                    return
                }
                favoriteBackgroundEditorDraft = draft
            case .replacement:
                guard var draft = favoriteBackgroundEditorDraft, draft.replaceImage(with: imageData) else {
                    viewModel.errorMessage = L10n.string("favorite_background.load_failed")
                    return
                }
                favoriteBackgroundEditorDraft = draft
            }
        } catch {
            viewModel.errorMessage = L10n.string("favorite_background.load_failed")
        }
    }

    private func applyFavoriteBackgroundDraft(_ draft: FavoriteBackgroundEditorDraft) async -> Bool {
        let didApply: Bool
        if let imageData = draft.imageData {
            didApply = await viewModel.applyFavoriteBackground(
                imageData: imageData,
                draftSettings: draft.settings
            )
        } else {
            didApply = await viewModel.restoreDefaultFavoriteBackground()
        }

        if didApply {
            favoriteBackgroundEditorDraft = nil
        }
        return didApply
    }

    private func handleConfirmation(_ confirmation: SystemSettingsConfirmation) async {
        switch confirmation {
        case .clearNovelCache:
            _ = await viewModel.clearNovelCache()
        case .clearMangaIndexCache:
            _ = await viewModel.clearMangaIndexCache()
        case .clearImageCache:
            _ = await viewModel.clearImageCache()
        case .resetApplication:
            let didReset = await viewModel.resetApplication()
            guard didReset else { return }
            dismiss()
            await onApplicationReset()
        }
    }
}

private enum FavoriteBackgroundPickerPurpose {
    case initial
    case replacement
}

private extension View {
    @ViewBuilder
    func favoriteBackgroundEditorPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, content: content)
    }
}
