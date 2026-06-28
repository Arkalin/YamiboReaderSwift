import Foundation
import Observation
import SwiftUI
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#endif

protocol MangaOfflineCacheQueueControlling: Sendable {
    func continueQueue() async throws
    func pauseQueue() async throws
    func cancelChapter(favoriteID: String, tid: String) async throws
    func cancelFavoriteGroup(favoriteID: String) async throws
}

extension MangaOfflineCacheQueueExecutor: MangaOfflineCacheQueueControlling {}

struct MineOfflineCacheQueueFavoriteGroup: Hashable, Identifiable {
    var favoriteID: String
    var favoriteTitle: String
    var chapterCount: Int
    var currentSpeedText: String?
    var chapters: [MineOfflineCacheQueueChapterRow]

    var id: String { favoriteID }

    init(group: MangaOfflineCacheQueueGroup) {
        let rows = group.works.map(MineOfflineCacheQueueChapterRow.init(work:))
        favoriteID = group.favoriteID
        favoriteTitle = group.favoriteTitle
        chapterCount = rows.count
        currentSpeedText = rows.first { $0.speedText != nil }?.speedText
        chapters = rows
    }
}

struct MineOfflineCacheQueueChapterRow: Hashable, Identifiable {
    var id: MangaOfflineCacheMembershipID
    var title: String
    var completedImageCount: Int
    var targetImageCount: Int
    var progressFraction: Double
    var progressText: String
    var percentageText: String
    var failureStatusText: String?
    var speedText: String?

    init(work: MangaOfflineCacheWork) {
        id = work.id
        title = work.chapterTitle.isEmpty ? work.tid : work.chapterTitle
        completedImageCount = work.progress.completedImageCount
        targetImageCount = work.progress.targetImageCount
        progressFraction = work.progress.fractionCompleted
        if targetImageCount > 0 {
            progressText = L10n.string(
                "mine.offline_queue.image_progress_format",
                completedImageCount,
                targetImageCount
            )
        } else {
            progressText = L10n.string("mine.offline_queue.preparing")
        }
        percentageText = L10n.string(
            "mine.offline_queue.percent_format",
            Int((progressFraction * 100).rounded())
        )
        if work.state == .failed {
            failureStatusText = work.failureMessage?.isEmpty == false
                ? work.failureMessage
                : L10n.string("mine.offline_queue.failed")
        } else {
            failureStatusText = nil
        }
        speedText = Self.speedText(bytesPerSecond: work.currentBytesPerSecond)
    }

    private static func speedText(bytesPerSecond: Int) -> String? {
        guard bytesPerSecond > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return L10n.string(
            "mine.offline_queue.speed_format",
            formatter.string(fromByteCount: Int64(bytesPerSecond))
        )
    }
}

public struct MineHomeView: View {
    @State private var viewModel: MineHomeViewModel
    @State private var showingLoginSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingSignOutConfirmation = false
    @State private var showingOfflineCacheQueueSheet = false

    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(appContext: YamiboAppContext, appModel: YamiboAppModel) {
        _viewModel = State(initialValue: MineHomeViewModel(appContext: appContext))
        self.appContext = appContext
        self.appModel = appModel
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

                MineCheckInSection()
                MineLibraryEntriesSection(
                    offlineCacheQueueCount: viewModel.offlineCacheQueueEntryCount,
                    showOfflineCacheQueue: {
                        showingOfflineCacheQueueSheet = true
                    }
                )
                MineSettingsSection(
                    showSettings: {
                        showingSettingsSheet = true
                    }
                )
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(L10n.string("tab.mine"))
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
                SystemSettingsView(appContext: appContext) {
                    await appModel.bootstrap()
                }
            }
            .sheet(isPresented: $showingOfflineCacheQueueSheet) {
                MineOfflineCacheQueueSheet(viewModel: viewModel)
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
}

@MainActor
@Observable
final class MineHomeViewModel {
    var session = SessionState()
    var profile: YamiboProfile?
    var errorMessage: String?
    var isLoading = false
    var isRefreshingProfile = false
    var isLoggingIn = false
    var isSigningOut = false
    var offlineCacheQueueRunState = MangaOfflineCacheQueueRunState.paused
    var offlineCacheQueueGroups: [MineOfflineCacheQueueFavoriteGroup] = []
    var offlineCacheQueueEntryCount = 0
    var isLoadingOfflineCacheQueue = false
    var isOfflineCacheQueueCommandRunning = false
    var selectedOfflineCacheWorkIDs: Set<MangaOfflineCacheMembershipID> = []
    var isOfflineCacheQueueSelectionMode = false

    let loginQuestions = YamiboLoginQuestion.defaultQuestions
    @ObservationIgnored let profileAvatarLoader: any YamiboProfileAvatarLoading

    private let appContext: YamiboAppContext
    @ObservationIgnored private var offlineCacheQueueController: (any MangaOfflineCacheQueueControlling)?
    @ObservationIgnored private var offlineCacheQueueUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutomaticProfileRefreshCredential: String?

    init(
        appContext: YamiboAppContext,
        offlineCacheQueueController: (any MangaOfflineCacheQueueControlling)? = nil
    ) {
        self.appContext = appContext
        self.offlineCacheQueueController = offlineCacheQueueController
        profileAvatarLoader = appContext.makeProfileAvatarLoader()
    }

    deinit {
        offlineCacheQueueUpdatesTask?.cancel()
    }

    var isLoggedIn: Bool {
        session.isLoggedIn && SessionState.hasAuthenticationCookie(session.cookie)
    }

    var isBusy: Bool {
        isLoading || isLoggingIn || isSigningOut
    }

    var offlineCacheQueueIsEmpty: Bool {
        offlineCacheQueueEntryCount == 0
    }

    var showsOfflineCacheQueueControls: Bool {
        !offlineCacheQueueIsEmpty
    }

    var selectedOfflineCacheWorkCount: Int {
        selectedOfflineCacheWorkIDs.count
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        startObservingOfflineCacheQueueUpdates()
        session = await appContext.sessionStore.load()
        profile = await appContext.profileStore.load()
        await refreshOfflineCacheQueue()

        guard isLoggedIn,
              let credential = SessionState.authenticationCookieValue(in: session.cookie) else {
            lastAutomaticProfileRefreshCredential = nil
            return
        }
        guard lastAutomaticProfileRefreshCredential != credential else { return }
        guard canAttemptAutomaticProfileRefresh else { return }

        lastAutomaticProfileRefreshCredential = credential
        await refreshProfile(presentsErrors: profile == nil)
    }

    private var canAttemptAutomaticProfileRefresh: Bool {
        guard profile != nil else { return true }
        guard let accountUID = session.accountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return false
        }
        return true
    }

    func refreshProfile() async {
        await refreshProfile(presentsErrors: true)
    }

    func login(username: String, password: String, questionID: String, answer: String) async -> Bool {
        guard !isLoggingIn else { return false }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            profile = try await appContext.makeAccountService().login(
                YamiboLoginRequest(
                    username: username,
                    password: password,
                    questionID: questionID,
                    answer: answer
                )
            )
            session = await appContext.sessionStore.load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await appContext.makeAccountService().signOut()
            session = await appContext.sessionStore.load()
            profile = await appContext.profileStore.load()
            lastAutomaticProfileRefreshCredential = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshOfflineCacheQueue() async {
        guard !isLoadingOfflineCacheQueue else { return }
        isLoadingOfflineCacheQueue = true
        defer { isLoadingOfflineCacheQueue = false }

        let store = appContext.makeMangaOfflineCacheStore()
        let works = await store.allOfflineCacheWorks()
        let directoriesByFavoriteID = await offlineCacheDirectoriesByFavoriteID(for: works)
        let projection = MangaOfflineCacheQueueProjection.project(
            works: works,
            directoriesByFavoriteID: directoriesByFavoriteID
        )
        offlineCacheQueueGroups = projection.groups.map(MineOfflineCacheQueueFavoriteGroup.init(group:))
        offlineCacheQueueEntryCount = projection.unfinishedCount
        offlineCacheQueueRunState = await store.offlineCacheQueueRunState()

        let visibleIDs = Set(offlineCacheQueueGroups.flatMap { group in group.chapters.map(\.id) })
        selectedOfflineCacheWorkIDs.formIntersection(visibleIDs)
        if selectedOfflineCacheWorkIDs.isEmpty && offlineCacheQueueIsEmpty {
            isOfflineCacheQueueSelectionMode = false
        }
    }

    func continueOfflineCacheQueue() async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).continueQueue()
        }
    }

    func pauseOfflineCacheQueue() async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).pauseQueue()
        }
    }

    func cancelOfflineCacheChapter(_ id: MangaOfflineCacheMembershipID) async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelChapter(
                favoriteID: id.favoriteID,
                tid: id.tid
            )
        }
    }

    func cancelOfflineCacheFavoriteGroup(favoriteID: String) async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelFavoriteGroup(favoriteID: favoriteID)
        }
    }

    func cancelSelectedOfflineCacheWorks() async {
        let ids = selectedOfflineCacheWorkIDs
        guard !ids.isEmpty else { return }

        await performOfflineCacheQueueCommand {
            let controller = await self.offlineCacheController()
            for id in ids {
                try await controller.cancelChapter(favoriteID: id.favoriteID, tid: id.tid)
            }
        }
        selectedOfflineCacheWorkIDs.removeAll()
        isOfflineCacheQueueSelectionMode = false
    }

    func setOfflineCacheQueueSelectionMode(_ isSelecting: Bool) {
        isOfflineCacheQueueSelectionMode = isSelecting
        if !isSelecting {
            selectedOfflineCacheWorkIDs.removeAll()
        }
    }

    func toggleOfflineCacheWorkSelection(_ id: MangaOfflineCacheMembershipID) {
        if selectedOfflineCacheWorkIDs.contains(id) {
            selectedOfflineCacheWorkIDs.remove(id)
        } else {
            selectedOfflineCacheWorkIDs.insert(id)
        }
    }

    func selectAllOfflineCacheWorks() {
        selectedOfflineCacheWorkIDs = Set(offlineCacheQueueGroups.flatMap { group in
            group.chapters.map(\.id)
        })
    }

    private func performOfflineCacheQueueCommand(_ command: @escaping @MainActor () async throws -> Void) async {
        guard !isOfflineCacheQueueCommandRunning else { return }
        isOfflineCacheQueueCommandRunning = true
        defer { isOfflineCacheQueueCommandRunning = false }

        do {
            try await command()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshOfflineCacheQueue()
    }

    private func offlineCacheController() async -> any MangaOfflineCacheQueueControlling {
        if let offlineCacheQueueController {
            return offlineCacheQueueController
        }

        let controller = await appContext.makeMangaOfflineCacheQueueExecutor()
        offlineCacheQueueController = controller
        return controller
    }

    private func startObservingOfflineCacheQueueUpdates() {
        guard offlineCacheQueueUpdatesTask == nil else { return }
        let store = appContext.makeMangaOfflineCacheStore()
        let updates = store.offlineCacheUpdates()
        offlineCacheQueueUpdatesTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await self?.refreshOfflineCacheQueue()
            }
        }
    }

    private func offlineCacheDirectoriesByFavoriteID(
        for works: [MangaOfflineCacheWork]
    ) async -> [String: MangaDirectory] {
        var directoriesByFavoriteID: [String: MangaDirectory] = [:]
        for work in works.sorted(by: { $0.insertionIndex < $1.insertionIndex }) {
            guard directoriesByFavoriteID[work.favoriteID] == nil else { continue }
            if let directory = try? await appContext.mangaDirectoryStore.directory(containingTID: work.tid) {
                directoriesByFavoriteID[work.favoriteID] = directory
            }
        }
        return directoriesByFavoriteID
    }

    private func refreshProfile(presentsErrors: Bool) async {
        guard isLoggedIn, !isRefreshingProfile else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        do {
            profile = try await appContext.makeAccountService().refreshProfile()
            session = await appContext.sessionStore.load()
            errorMessage = nil
        } catch YamiboError.notAuthenticated {
            try? await appContext.makeAccountService().clearLocalAuthentication()
            session = await appContext.sessionStore.load()
            profile = await appContext.profileStore.load()
            errorMessage = YamiboError.notAuthenticated.localizedDescription
        } catch {
            if presentsErrors {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MineProfileSection: View {
    let profile: YamiboProfile?
    let avatarLoader: any YamiboProfileAvatarLoading
    let avatarReloadDate: Date?
    let isRefreshing: Bool
    let isInteractionDisabled: Bool
    let showSignOutConfirmation: () -> Void

    var body: some View {
        Section {
            if let profile {
                Button(action: showSignOutConfirmation) {
                    MineProfileCard(
                        profile: profile,
                        avatarLoader: avatarLoader,
                        avatarReloadDate: avatarReloadDate
                    )
                }
                .buttonStyle(.plain)
                .disabled(isInteractionDisabled)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } else {
                MineProfileLoadingCard(isRefreshing: isRefreshing)
                    .allowsHitTesting(!isInteractionDisabled)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
    }
}

private struct MineLoggedOutProfileSection: View {
    let isInteractionDisabled: Bool
    let showLogin: () -> Void

    var body: some View {
        Section {
            Button(action: showLogin) {
                MineLoggedOutProfileCard()
            }
            .buttonStyle(.plain)
            .disabled(isInteractionDisabled)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .accessibilityLabel(L10n.string("mine.tap_to_login"))
            .accessibilityHint(L10n.string("mine.login_card_hint"))
        }
    }
}

private struct MineLoggedOutProfileCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(.secondary.opacity(0.14))

                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Text(L10n.string("mine.tap_to_login"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 96)
        .contentShape(Rectangle())
    }
}

private struct MineLoginSheet: View {
    let viewModel: MineHomeViewModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                MineLoginSection(viewModel: viewModel, onLoginSuccess: close)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(L10n.string("mine.login"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: close)
                }
            }
            .alert(L10n.string("common.operation_failed"), isPresented: errorIsPresented, actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
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
}

private struct MineProfileCard: View {
    let profile: YamiboProfile
    let avatarLoader: any YamiboProfileAvatarLoading
    let avatarReloadDate: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MineAvatarView(
                profile: profile,
                avatarLoader: avatarLoader,
                avatarReloadDate: avatarReloadDate
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 10) {
                MineProfileIdentityRow(username: profile.username, uid: profile.uid)
                MineCreditProgressView(progress: YamiboUserGroups.progress(for: profile))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 96)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.string("mine.profile_card_sign_out_hint"))
    }
}

private struct MineProfileIdentityRow: View {
    let username: String
    let uid: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(username.isEmpty ? L10n.string("mine.unknown_user") : username)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                MineUIDText(uid: uid)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(username.isEmpty ? L10n.string("mine.unknown_user") : username)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                MineUIDText(uid: uid)
            }
        }
    }
}

private struct MineUIDText: View {
    let uid: String

    var body: some View {
        Text(L10n.string("mine.uid_format", uid))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct MineCreditProgressView: View {
    let progress: ForumCreditProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fraction)
                .tint(.accentColor)

            HStack(spacing: 8) {
                Text(progress.currentGroupName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(L10n.string("mine.credit_progress_format", progress.currentTotalPoints, progress.targetTotalPoints))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct MineProfileLoadingCard: View {
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("common.loading"))
                    .font(.title3.weight(.semibold))
                ProgressView()
                    .opacity(isRefreshing ? 1 : 0)
            }
        }
        .frame(minHeight: 96)
    }
}

private struct MineLoginSection: View {
    let viewModel: MineHomeViewModel
    let onLoginSuccess: () -> Void

    @AppStorage("yamibo.login.username") private var username = ""
    @State private var password = ""
    @State private var selectedQuestionID = YamiboLoginQuestion.none.id
    @State private var answer = ""

    var body: some View {
        Section {
            TextField(L10n.string("mine.login_username"), text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            SecureField(L10n.string("mine.login_password"), text: $password)
                .textContentType(.password)

            Picker(L10n.string("mine.security_question"), selection: $selectedQuestionID) {
                ForEach(viewModel.loginQuestions) { question in
                    Text(question.title).tag(question.id)
                }
            }

            if selectedQuestionID != YamiboLoginQuestion.none.id {
                TextField(L10n.string("mine.security_answer"), text: $answer)
                    .autocorrectionDisabled()
            }
        }

        Section {
            Button {
                Task {
                    let didLogin = await viewModel.login(
                        username: username,
                        password: password,
                        questionID: selectedQuestionID,
                        answer: answer
                    )
                    if didLogin {
                        password = ""
                        answer = ""
                        onLoginSuccess()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isLoggingIn {
                        ProgressView()
                    } else {
                        Text(L10n.string("mine.login"))
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(loginIsDisabled)
        }
    }

    private var loginIsDisabled: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.isEmpty
            || viewModel.isLoggingIn
    }
}

private struct MineOfflineCacheQueueSheet: View {
    let viewModel: MineHomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.offlineCacheQueueIsEmpty {
                    MineOfflineCacheQueueEmptyState()
                } else {
                    if viewModel.showsOfflineCacheQueueControls {
                        MineOfflineCacheQueueControls(viewModel: viewModel)
                    }

                    ForEach(viewModel.offlineCacheQueueGroups) { group in
                        Section {
                            MineOfflineCacheQueueFavoriteRow(
                                group: group,
                                cancel: {
                                    Task {
                                        await viewModel.cancelOfflineCacheFavoriteGroup(favoriteID: group.favoriteID)
                                    }
                                }
                            )

                            ForEach(group.chapters) { chapter in
                                MineOfflineCacheQueueChapterRowView(
                                    chapter: chapter,
                                    isSelecting: viewModel.isOfflineCacheQueueSelectionMode,
                                    isSelected: viewModel.selectedOfflineCacheWorkIDs.contains(chapter.id),
                                    toggleSelection: {
                                        viewModel.toggleOfflineCacheWorkSelection(chapter.id)
                                    },
                                    cancel: {
                                        Task {
                                            await viewModel.cancelOfflineCacheChapter(chapter.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(L10n.string("mine.download_queue"))
            .task {
                await viewModel.refreshOfflineCacheQueue()
            }
            .refreshable {
                await viewModel.refreshOfflineCacheQueue()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.offlineCacheQueueIsEmpty {
                        Button(
                            viewModel.isOfflineCacheQueueSelectionMode
                                ? L10n.string("common.done")
                                : L10n.string("common.select")
                        ) {
                            viewModel.setOfflineCacheQueueSelectionMode(!viewModel.isOfflineCacheQueueSelectionMode)
                        }
                        .disabled(viewModel.isOfflineCacheQueueCommandRunning)
                    }
                }

                if viewModel.isOfflineCacheQueueSelectionMode {
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #else
                    ToolbarItem(placement: .secondaryAction) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #endif
                }
            }
            .overlay {
                if viewModel.isLoadingOfflineCacheQueue {
                    ProgressView()
                }
            }
        }
    }
}

private struct MineOfflineCacheQueueSelectAllButton: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        Button(L10n.string("common.select_all")) {
            viewModel.selectAllOfflineCacheWorks()
        }
        .disabled(viewModel.offlineCacheQueueIsEmpty)
    }
}

private struct MineOfflineCacheQueueCancelSelectionButton: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        Button(role: .destructive) {
            Task {
                await viewModel.cancelSelectedOfflineCacheWorks()
            }
        } label: {
            Label(
                L10n.string(
                    "mine.offline_queue.cancel_selected_format",
                    viewModel.selectedOfflineCacheWorkCount
                ),
                systemImage: "xmark.circle"
            )
        }
        .disabled(
            viewModel.selectedOfflineCacheWorkIDs.isEmpty
                || viewModel.isOfflineCacheQueueCommandRunning
        )
    }
}

private struct MineOfflineCacheQueueControls: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        Section {
            Button {
                Task {
                    if viewModel.offlineCacheQueueRunState == .running {
                        await viewModel.pauseOfflineCacheQueue()
                    } else {
                        await viewModel.continueOfflineCacheQueue()
                    }
                }
            } label: {
                Label(controlTitle, systemImage: controlImage)
            }
            .disabled(viewModel.isOfflineCacheQueueCommandRunning)
        }
    }

    private var controlTitle: String {
        viewModel.offlineCacheQueueRunState == .running
            ? L10n.string("mine.offline_queue.pause")
            : L10n.string("mine.offline_queue.continue")
    }

    private var controlImage: String {
        viewModel.offlineCacheQueueRunState == .running ? "pause.fill" : "play.fill"
    }
}

private struct MineOfflineCacheQueueFavoriteRow: View {
    let group: MineOfflineCacheQueueFavoriteGroup
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.favoriteTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(L10n.string("mine.offline_queue.chapter_count_format", group.chapterCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let currentSpeedText = group.currentSpeedText {
                Text(currentSpeedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
            }
        }
    }
}

private struct MineOfflineCacheQueueChapterRowView: View {
    let chapter: MineOfflineCacheQueueChapterRow
    let isSelecting: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let cancel: () -> Void

    var body: some View {
        Button(action: rowAction) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chapter.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(chapter.percentageText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ProgressView(value: chapter.progressFraction)

                    HStack(spacing: 8) {
                        Text(chapter.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let speedText = chapter.speedText {
                            Text(speedText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let failureStatusText = chapter.failureStatusText {
                            Text(failureStatusText)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
            }
        }
    }

    private func rowAction() {
        guard isSelecting else { return }
        toggleSelection()
    }
}

private struct MineOfflineCacheQueueEmptyState: View {
    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(L10n.string("mine.offline_queue.empty_title"))
                    .font(.headline)
                Text(L10n.string("mine.offline_queue.empty_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}

private struct MineSettingsSection: View {
    let showSettings: () -> Void

    var body: some View {
        Section {
            MineEntryButtonRow(
                title: L10n.string("settings.title"),
                systemImage: "gearshape.fill",
                tint: .gray,
                action: showSettings
            )
        }
    }
}

private struct MineCheckInSection: View {
    var body: some View {
        Section {
            MineEntryDisplayRow(
                title: L10n.string("mine.check_in"),
                systemImage: "checkmark.seal.fill",
                tint: .green
            )
        }
    }
}

private struct MineLibraryEntriesSection: View {
    let offlineCacheQueueCount: Int
    let showOfflineCacheQueue: () -> Void

    var body: some View {
        Section {
            MineEntryDisplayRow(
                title: L10n.string("forum.history"),
                systemImage: "clock.arrow.circlepath",
                tint: .blue
            )
            MineEntryDisplayRow(
                title: L10n.string("mine.my_likes"),
                systemImage: "heart.fill",
                tint: .pink
            )
            MineEntryButtonRow(
                title: L10n.string("mine.download_queue"),
                systemImage: "arrow.down.circle.fill",
                tint: .indigo,
                badgeText: String(offlineCacheQueueCount),
                action: showOfflineCacheQueue
            )
        }
    }
}

private struct MineEntryDisplayRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        MineEntryRowContent(title: title, systemImage: systemImage, tint: tint)
    }
}

private struct MineEntryButtonRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MineEntryRowContent(title: title, systemImage: systemImage, tint: tint, badgeText: badgeText)
        }
        .buttonStyle(.plain)
    }
}

private struct MineEntryRowContent: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct MineAvatarView: View {
    let profile: YamiboProfile
    let avatarLoader: any YamiboProfileAvatarLoading
    let avatarReloadDate: Date?

    @State private var image: Image?

    var body: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.14))

            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .clipShape(Circle())
        .task(id: MineAvatarTaskIdentity(profile: profile, avatarReloadDate: avatarReloadDate)) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> Image? {
        do {
            guard let data = try await avatarLoader.avatarData(for: profile) else { return nil }
            return platformImage(from: data)
        } catch {
            return nil
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}

private struct MineAvatarTaskIdentity: Hashable {
    let uid: String
    let avatarURL: URL?
    let avatarReloadDate: Date?

    init(profile: YamiboProfile, avatarReloadDate: Date?) {
        uid = profile.uid
        avatarURL = profile.avatarURL
        self.avatarReloadDate = avatarReloadDate
    }
}
