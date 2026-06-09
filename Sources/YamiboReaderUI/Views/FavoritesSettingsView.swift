import SwiftUI
import YamiboReaderCore

public struct FavoritesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let appContext: YamiboAppContext
    private let onApplicationReset: @MainActor () async -> Void

    @StateObject private var viewModel: FavoritesSettingsViewModel
    @State private var showingDirectoryManager = false
    @State private var showingWebDAVSettings = false
    @State private var pendingConfirmation: FavoritesSettingsConfirmation?
    @State private var activeAppearanceCategory: FavoriteAppearanceCategory?

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
                    FavoritesSettingsHomePageSelector(
                        homePage: viewModel.homePage,
                        isBusy: viewModel.isBusy,
                        onSelect: viewModel.updateHomePage
                    )

                    Button {
                        openAutoSignInAutomationCreator()
                    } label: {
                        FavoritesSettingsRow(title: L10n.string("settings.auto_sign_in"))
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        openWebDAVSettings()
                    } label: {
                        FavoritesSettingsRow(title: L10n.string("settings.webdav_sync"))
                    }
                    .disabled(viewModel.isBusy)
                }

                Section(L10n.string("settings.section.appearance")) {
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
                        FavoritesSettingsRow(title: L10n.string("settings.manga_directory_management"))
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearNovelCache
                    } label: {
                        FavoritesSettingsRow(
                            title: L10n.string("settings.clear_novel_cache"),
                            value: viewModel.novelCacheLabel
                        )
                    }
                    .disabled(viewModel.isBusy)

                    Button {
                        pendingConfirmation = .clearMangaCache
                    } label: {
                        FavoritesSettingsRow(
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
            .toolbar(content: toolbarContent)
            .overlay(content: loadingOverlay)
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showingDirectoryManager) {
                MangaDirectoryManagementView(store: appContext.mangaDirectoryStore)
            }
            .sheet(isPresented: $showingWebDAVSettings) {
                WebDAVSyncSettingsView(appContext: appContext)
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
