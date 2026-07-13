import SwiftUI
import YamiboReaderCore

struct SettingsStorageView: View {
    let dependencies: SettingsDependencies
    @ObservedObject var viewModel: SystemSettingsViewModel
    /// Called after a successful reset, before `viewModel.resetApplication()`'s
    /// caller-provided completion runs — lets the owning navigation stack pop
    /// back out of Settings first, since the app state it just wiped includes
    /// whatever this stack is showing.
    let onReset: () async -> Void

    @State private var showingWebDAVSettings = false
    @State private var showingOfflineCacheManagement = false
    @State private var pendingConfirmation: SystemSettingsConfirmation?

    var body: some View {
        Form {
            Section(L10n.string("settings.section.backup_sync")) {
                Button {
                    openWebDAVSettings()
                } label: {
                    SystemSettingsRow(
                        title: L10n.string("settings.webdav_sync"),
                        titleColor: .accentColor
                    )
                }
                .disabled(viewModel.isBusy)
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
            }

            Section(L10n.string("settings.section.reset")) {
                Button(role: .destructive) {
                    pendingConfirmation = .resetApplication
                } label: {
                    Text(L10n.string("settings.reset_application"))
                }
                .disabled(viewModel.isBusy)
            }
        }
        .navigationTitle(L10n.string("settings.section.data_storage"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(content: loadingOverlay)
        .navigationDestination(isPresented: $showingWebDAVSettings) {
            WebDAVSyncSettingsView(dependencies: dependencies.webDAVSync)
        }
        .navigationDestination(isPresented: $showingOfflineCacheManagement) {
            OfflineCacheManagementView(viewModel: viewModel)
        }
        .alert(L10n.string("common.operation_failed"), isPresented: errorIsPresented, actions: {
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

    @ViewBuilder
    private func loadingOverlay() -> some View {
        if viewModel.isBusy {
            let title = viewModel.activeAction == .resettingApplication
                ? L10n.string("settings.resetting_application")
                : L10n.string("common.loading")
            ProgressView(title)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
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

    private func openWebDAVSettings() {
        Task { @MainActor in
            let session = await dependencies.sessionStore.load()
            if session.isLoggedIn, !session.cookie.isEmpty {
                showingWebDAVSettings = true
            } else {
                viewModel.errorMessage = L10n.string("webdav.error.login_required")
            }
        }
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
            await onReset()
        case .restoreBoardReaderDefaults, .signOut:
            break
        }
    }
}
