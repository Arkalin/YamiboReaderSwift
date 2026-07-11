import SwiftUI
import YamiboReaderCore

public struct MineHomeView: View {
    @State private var viewModel: MineHomeViewModel
    @State private var showingLoginSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingSignOutConfirmation = false
    @State private var showingOfflineCacheQueueSheet = false
    @State private var isMyLikesPushed = false

    private let settingsDependencies: SettingsDependencies
    private let appModel: YamiboAppModel
    private let likeDependencies: LikeDependencies

    public init(
        dependencies: AccountDependencies,
        settingsDependencies: SettingsDependencies,
        appModel: YamiboAppModel,
        likeDependencies: LikeDependencies
    ) {
        _viewModel = State(initialValue: MineHomeViewModel(dependencies: dependencies))
        self.settingsDependencies = settingsDependencies
        self.appModel = appModel
        self.likeDependencies = likeDependencies
    }

    public var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoggedIn {
                    MineProfileSection(
                        profile: viewModel.profile,
                        avatarLoader: viewModel.profileAvatarLoader,
                        avatarReloadDate: viewModel.session.lastUpdatedAt,
                        isRefreshing: viewModel.isRefreshingProfile,
                        isInteractionDisabled: viewModel.isBusy,
                        showSignOutConfirmation: {
                            showingSignOutConfirmation = true
                        }
                    )
                } else {
                    MineLoggedOutProfileSection(isInteractionDisabled: viewModel.isBusy) {
                        showingLoginSheet = true
                    }
                }

                MineCheckInSection(
                    isLoggedIn: viewModel.isLoggedIn,
                    isCheckingIn: viewModel.isCheckingIn,
                    hasCheckedInToday: viewModel.hasCheckedInToday,
                    isInteractionDisabled: viewModel.isBusy,
                    checkIn: {
                        if viewModel.isLoggedIn {
                            Task {
                                await viewModel.checkIn()
                            }
                        } else {
                            showingLoginSheet = true
                        }
                    }
                )
                MineLibraryEntriesSection(
                    offlineCacheQueueCount: viewModel.offlineCacheQueueEntryCount,
                    showOfflineCacheQueue: {
                        showingOfflineCacheQueueSheet = true
                    },
                    showMyLikes: {
                        isMyLikesPushed = true
                    }
                )
                MineSettingsSection(
                    showSettings: {
                        showingSettingsSheet = true
                    }
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("tab.mine"))
            .yamiboInlineNavigationTitleDisplayMode()
            .forumNavigationBarStyle()
            .refreshable {
                await viewModel.refreshProfile()
            }
            .task {
                await viewModel.load()
            }
            .alert(L10n.string("common.operation_failed"), isPresented: errorIsPresented, actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert(L10n.string("mine.check_in"), isPresented: checkInResultIsPresented, actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.checkInResultMessage = nil
                }
            }, message: {
                Text(viewModel.checkInResultMessage ?? "")
            })
            .confirmationDialog(
                L10n.string("mine.sign_out"),
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .hidden
            ) {
                Button(L10n.string("mine.sign_out"), role: .destructive) {
                    Task {
                        await viewModel.signOut()
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            }
            .overlay {
                if viewModel.isSigningOut {
                    ProgressView(L10n.string("mine.signing_out"))
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                MineLoginSheet(viewModel: viewModel) {
                    showingLoginSheet = false
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SystemSettingsView(dependencies: settingsDependencies) {
                    await appModel.bootstrap()
                }
            }
            .sheet(isPresented: $showingOfflineCacheQueueSheet) {
                MineOfflineCacheQueueSheet(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $isMyLikesPushed) {
                LikeWorkListView(
                    likeDependencies: likeDependencies,
                    contentCoverStore: settingsDependencies.library.contentCoverStore,
                    favoriteLibraryStore: settingsDependencies.library.localFavoriteLibraryStore,
                    appModel: appModel
                )
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !showingLoginSheet },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var checkInResultIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.checkInResultMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.checkInResultMessage = nil
                }
            }
        )
    }
}
