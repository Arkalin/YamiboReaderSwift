import Foundation
import Observation
import YamiboReaderCore

protocol MangaOfflineCacheQueueControlling: Sendable {
    func continueQueue() async throws
    func pauseQueue() async throws
    func cancelChapter(favoriteID: String, tid: String) async throws
    func cancelFavoriteGroup(favoriteID: String) async throws
}

extension MangaOfflineCacheQueueExecutor: MangaOfflineCacheQueueControlling {}

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

    func selectAllOfflineCacheWorks(favoriteID: String? = nil) {
        let groups = favoriteID.map { id in
            offlineCacheQueueGroups.filter { $0.favoriteID == id }
        } ?? offlineCacheQueueGroups
        selectedOfflineCacheWorkIDs = Set(groups.flatMap { group in
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
