import Foundation
import Observation
import YamiboReaderCore

public protocol OfflineCacheQueueControlling: Sendable {
    func continueQueue() async throws
    func pauseQueue() async throws
    func cancelWork(id: OfflineCacheWorkID) async throws
    func cancelGroup(id: OfflineCacheGroupID) async throws
}

public extension OfflineCacheQueueControlling {
    func cancelWork(id: OfflineCacheWorkID) async throws {}
    func cancelGroup(id: OfflineCacheGroupID) async throws {}
}

extension OfflineCacheQueueExecutor: OfflineCacheQueueControlling {}

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
    var isCheckingIn = false
    var hasCheckedInToday = false
    var checkInResultMessage: String?
    var offlineCacheQueueRunState = OfflineCacheQueueRunState.paused
    var offlineCacheQueueGroups: [MineOfflineCacheQueueOwnerGroup] = []
    var offlineCacheQueueEntryCount = 0
    var isLoadingOfflineCacheQueue = false
    var isOfflineCacheQueueCommandRunning = false
    var selectedOfflineCacheWorkIDs: Set<OfflineCacheWorkID> = []
    var isOfflineCacheQueueSelectionMode = false

    let loginQuestions = YamiboLoginQuestion.defaultQuestions
    @ObservationIgnored let profileAvatarLoader: YamiboProfileAvatarLoader

    private let dependencies: AccountDependencies
    @ObservationIgnored private let checkInService: any YamiboCheckInServicing
    @ObservationIgnored private var offlineCacheQueueController: (any OfflineCacheQueueControlling)?
    @ObservationIgnored private var offlineCacheQueueUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutomaticProfileRefreshCredential: String?

    init(
        dependencies: AccountDependencies,
        offlineCacheQueueController: (any OfflineCacheQueueControlling)? = nil,
        checkInService: (any YamiboCheckInServicing)? = nil
    ) {
        self.dependencies = dependencies
        self.offlineCacheQueueController = offlineCacheQueueController
        self.checkInService = checkInService ?? dependencies.makeCheckInService()
        profileAvatarLoader = YamiboProfileAvatarLoader(sessionStore: dependencies.sessionStore)
    }

    deinit {
        offlineCacheQueueUpdatesTask?.cancel()
    }

    var isLoggedIn: Bool {
        session.isLoggedIn && SessionState.hasAuthenticationCookie(session.cookie)
    }

    var isBusy: Bool {
        isLoading || isLoggingIn || isSigningOut || isCheckingIn
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

        session = await dependencies.sessionStore.load()
        profile = await dependencies.profileStore.load()
        await refreshCheckInState()
        await loadOfflineCacheQueue()

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
            profile = try await dependencies.makeAccountService().login(
                YamiboLoginRequest(
                    username: username,
                    password: password,
                    questionID: questionID,
                    answer: answer
                )
            )
            session = await dependencies.sessionStore.load()
            await refreshCheckInState()
            errorMessage = nil
            checkInResultMessage = nil
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
            try await dependencies.makeAccountService().signOut()
            session = await dependencies.sessionStore.load()
            profile = await dependencies.profileStore.load()
            lastAutomaticProfileRefreshCredential = nil
            hasCheckedInToday = false
            errorMessage = nil
            checkInResultMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkIn() async {
        guard !isCheckingIn else { return }
        guard !hasCheckedInToday else {
            checkInResultMessage = YamiboCheckInResult.alreadyCheckedInToday.message
            errorMessage = nil
            return
        }
        isCheckingIn = true
        defer { isCheckingIn = false }

        let result = await checkInService.checkInIfNeeded(force: false)
        checkInResultMessage = nil
        switch result {
        case .success:
            hasCheckedInToday = true
            checkInResultMessage = result.message
            errorMessage = nil
            await refreshProfile(presentsErrors: false)
        case .alreadyCheckedInToday, .skippedToday:
            hasCheckedInToday = true
            checkInResultMessage = YamiboCheckInResult.alreadyCheckedInToday.message
            errorMessage = nil
        case .notAuthenticated:
            hasCheckedInToday = false
            errorMessage = result.message
        case .parseFailed, .verificationFailed, .networkFailed:
            errorMessage = result.message
        }
    }

    private func refreshCheckInState() async {
        guard isLoggedIn else {
            hasCheckedInToday = false
            return
        }
        hasCheckedInToday = !(await dependencies.checkInStore.needsCheckIn(session: session))
    }

    func loadOfflineCacheQueue() async {
        startObservingOfflineCacheQueueUpdates()
        await refreshOfflineCacheQueue()
    }

    func refreshOfflineCacheQueue() async {
        guard !isLoadingOfflineCacheQueue else { return }
        isLoadingOfflineCacheQueue = true
        defer { isLoadingOfflineCacheQueue = false }

        let store = dependencies.offlineCacheStore
        let works = await store.offlineCacheQueueWorks()
        let directoriesByOwnerName = await offlineCacheDirectoriesByOwnerName(for: works)
        let projection = OfflineCacheQueueProjection.project(
            works: works,
            mangaDirectoriesByOwnerName: directoriesByOwnerName
        )
        offlineCacheQueueGroups = projection.groups.map(MineOfflineCacheQueueOwnerGroup.init(group:))
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

    func cancelOfflineCacheChapter(_ id: OfflineCacheWorkID) async {
        guard let row = offlineCacheChapterRow(id: id) else { return }
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelWork(id: row.id)
        }
    }

    func cancelOfflineCacheOwnerGroup(id: OfflineCacheGroupID) async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelGroup(id: id)
        }
    }

    func cancelSelectedOfflineCacheWorks() async {
        let ids = selectedOfflineCacheWorkIDs
        guard !ids.isEmpty else { return }

        await performOfflineCacheQueueCommand {
            let controller = await self.offlineCacheController()
            let rowsByID = self.offlineCacheChapterRowsByID()
            for id in ids {
                guard let row = rowsByID[id] else { continue }
                try await controller.cancelWork(id: row.id)
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

    func toggleOfflineCacheWorkSelection(_ id: OfflineCacheWorkID) {
        if selectedOfflineCacheWorkIDs.contains(id) {
            selectedOfflineCacheWorkIDs.remove(id)
        } else {
            selectedOfflineCacheWorkIDs.insert(id)
        }
    }

    func isOfflineCacheOwnerSelected(id: OfflineCacheGroupID) -> Bool {
        let ids = offlineCacheWorkIDs(groupID: id)
        return !ids.isEmpty && ids.isSubset(of: selectedOfflineCacheWorkIDs)
    }

    func toggleOfflineCacheOwnerSelection(id: OfflineCacheGroupID) {
        let ids = offlineCacheWorkIDs(groupID: id)
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: selectedOfflineCacheWorkIDs) {
            selectedOfflineCacheWorkIDs.subtract(ids)
        } else {
            selectedOfflineCacheWorkIDs.formUnion(ids)
        }
    }

    func isOfflineCacheWorkSelectionComplete(groupID: OfflineCacheGroupID? = nil) -> Bool {
        let ids = offlineCacheWorkIDs(groupID: groupID)
        return !ids.isEmpty && ids.isSubset(of: selectedOfflineCacheWorkIDs)
    }

    func toggleAllOfflineCacheWorks(groupID: OfflineCacheGroupID? = nil) {
        let ids = offlineCacheWorkIDs(groupID: groupID)
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: selectedOfflineCacheWorkIDs) {
            selectedOfflineCacheWorkIDs.subtract(ids)
        } else {
            selectedOfflineCacheWorkIDs.formUnion(ids)
        }
    }

    private func offlineCacheWorkIDs(groupID: OfflineCacheGroupID?) -> Set<OfflineCacheWorkID> {
        let groups = groupID.map { id in
            offlineCacheQueueGroups.filter { $0.id == id }
        } ?? offlineCacheQueueGroups
        return Set(groups.flatMap { group in
            group.chapters.map(\.id)
        })
    }

    private func offlineCacheWorkIDs(groupID: OfflineCacheGroupID) -> Set<OfflineCacheWorkID> {
        Set(
            offlineCacheQueueGroups
                .first { $0.id == groupID }?
                .chapters
                .map(\.id) ?? []
        )
    }

    private func offlineCacheChapterRow(id: OfflineCacheWorkID) -> MineOfflineCacheQueueChapterRow? {
        offlineCacheChapterRowsByID()[id]
    }

    private func offlineCacheChapterRowsByID() -> [OfflineCacheWorkID: MineOfflineCacheQueueChapterRow] {
        Dictionary(
            uniqueKeysWithValues: offlineCacheQueueGroups.flatMap(\.chapters).map { ($0.id, $0) }
        )
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

    private func offlineCacheController() async -> any OfflineCacheQueueControlling {
        if let offlineCacheQueueController {
            return offlineCacheQueueController
        }

        let controller = await dependencies.makeOfflineCacheQueueExecutor()
        offlineCacheQueueController = controller
        return controller
    }

    private func startObservingOfflineCacheQueueUpdates() {
        guard offlineCacheQueueUpdatesTask == nil else { return }
        let store = dependencies.offlineCacheStore
        let updates = store.offlineCacheUpdates()
        offlineCacheQueueUpdatesTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await self?.refreshOfflineCacheQueue()
            }
        }
    }

    private func offlineCacheDirectoriesByOwnerName(
        for works: [OfflineCacheQueueWorkProjection]
    ) async -> [String: MangaDirectory] {
        var directoriesByOwnerName: [String: MangaDirectory] = [:]
        for work in works.sorted(by: { $0.insertionIndex < $1.insertionIndex }) {
            guard work.groupID.readerKind == .manga else { continue }
            guard directoriesByOwnerName[work.groupID.ownerKey] == nil else { continue }
            do {
                if let directory = try await dependencies.mangaDirectoryStore.directory(named: work.groupID.ownerKey) {
                    directoriesByOwnerName[work.groupID.ownerKey] = directory
                }
            } catch {
                YamiboLog.offlineCache.warning("Failed to load manga directory metadata for offline cache queue owner: \(error)")
            }
        }
        return directoriesByOwnerName
    }

    private func refreshProfile(presentsErrors: Bool) async {
        guard isLoggedIn, !isRefreshingProfile else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        do {
            profile = try await dependencies.makeAccountService().refreshProfile()
            session = await dependencies.sessionStore.load()
            errorMessage = nil
        } catch YamiboError.notAuthenticated {
            do {
                try await dependencies.makeAccountService().clearLocalAuthentication()
            } catch {
                YamiboLog.account.error("Failed to clear local authentication after server reported notAuthenticated: \(error)")
            }
            session = await dependencies.sessionStore.load()
            profile = await dependencies.profileStore.load()
            await refreshCheckInState()
            if presentsErrors {
                errorMessage = YamiboError.notAuthenticated.localizedDescription
            }
        } catch {
            if presentsErrors {
                errorMessage = error.localizedDescription
            }
        }
    }
}
