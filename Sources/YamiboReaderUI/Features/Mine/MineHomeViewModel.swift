import Foundation
import Observation
import YamiboReaderCore

public protocol MangaOfflineCacheQueueControlling: Sendable {
    func continueQueue() async throws
    func pauseQueue() async throws
    func cancelChapter(ownerName: String, tid: String) async throws
    func cancelOwnerGroup(ownerName: String) async throws
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
    var isCheckingIn = false
    var hasCheckedInToday = false
    var checkInResultMessage: String?
    var offlineCacheQueueRunState = MangaOfflineCacheQueueRunState.paused
    var offlineCacheQueueGroups: [MineOfflineCacheQueueOwnerGroup] = []
    var offlineCacheQueueEntryCount = 0
    var isLoadingOfflineCacheQueue = false
    var isOfflineCacheQueueCommandRunning = false
    var selectedOfflineCacheWorkIDs: Set<String> = []
    var isOfflineCacheQueueSelectionMode = false

    let loginQuestions = YamiboLoginQuestion.defaultQuestions
    @ObservationIgnored let profileAvatarLoader: any YamiboProfileAvatarLoading

    private let appContext: YamiboAppContext
    @ObservationIgnored private let checkInService: any YamiboCheckInServicing
    @ObservationIgnored private var offlineCacheQueueController: (any MangaOfflineCacheQueueControlling)?
    @ObservationIgnored private var offlineCacheQueueUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutomaticProfileRefreshCredential: String?

    init(
        appContext: YamiboAppContext,
        offlineCacheQueueController: (any MangaOfflineCacheQueueControlling)? = nil,
        checkInService: (any YamiboCheckInServicing)? = nil
    ) {
        self.appContext = appContext
        self.offlineCacheQueueController = offlineCacheQueueController
        self.checkInService = checkInService ?? appContext.makeCheckInService()
        profileAvatarLoader = appContext.makeProfileAvatarLoader()
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

        session = await appContext.sessionStore.load()
        profile = await appContext.profileStore.load()
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
            profile = try await appContext.makeAccountService().login(
                YamiboLoginRequest(
                    username: username,
                    password: password,
                    questionID: questionID,
                    answer: answer
                )
            )
            session = await appContext.sessionStore.load()
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
            try await appContext.makeAccountService().signOut()
            session = await appContext.sessionStore.load()
            profile = await appContext.profileStore.load()
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
        hasCheckedInToday = !(await appContext.checkInStore.needsCheckIn(session: session))
    }

    func loadOfflineCacheQueue() async {
        startObservingOfflineCacheQueueUpdates()
        await refreshOfflineCacheQueue()
    }

    func refreshOfflineCacheQueue() async {
        guard !isLoadingOfflineCacheQueue else { return }
        isLoadingOfflineCacheQueue = true
        defer { isLoadingOfflineCacheQueue = false }

        let store = appContext.makeOfflineCacheStore()
        let works = await store.allOfflineCacheWorks()
        let directoriesByOwnerName = await offlineCacheDirectoriesByOwnerName(for: works)
        let projection = MangaOfflineCacheQueueProjection.project(
            works: works,
            directoriesByOwnerName: directoriesByOwnerName
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

    func cancelOfflineCacheChapter(_ id: String) async {
        guard let row = offlineCacheChapterRow(id: id) else { return }
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelChapter(
                ownerName: row.ownerName,
                tid: row.tid
            )
        }
    }

    func cancelOfflineCacheOwnerGroup(ownerName: String) async {
        await performOfflineCacheQueueCommand {
            try await (await self.offlineCacheController()).cancelOwnerGroup(ownerName: ownerName)
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
                try await controller.cancelChapter(ownerName: row.ownerName, tid: row.tid)
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

    func toggleOfflineCacheWorkSelection(_ id: String) {
        if selectedOfflineCacheWorkIDs.contains(id) {
            selectedOfflineCacheWorkIDs.remove(id)
        } else {
            selectedOfflineCacheWorkIDs.insert(id)
        }
    }

    func isOfflineCacheOwnerSelected(ownerName: String) -> Bool {
        let ids = offlineCacheWorkIDs(ownerName: ownerName)
        return !ids.isEmpty && ids.isSubset(of: selectedOfflineCacheWorkIDs)
    }

    func toggleOfflineCacheOwnerSelection(ownerName: String) {
        let ids = offlineCacheWorkIDs(ownerName: ownerName)
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: selectedOfflineCacheWorkIDs) {
            selectedOfflineCacheWorkIDs.subtract(ids)
        } else {
            selectedOfflineCacheWorkIDs.formUnion(ids)
        }
    }

    func isOfflineCacheWorkSelectionComplete(ownerName: String? = nil) -> Bool {
        let ids = offlineCacheWorkIDs(ownerName: ownerName)
        return !ids.isEmpty && ids.isSubset(of: selectedOfflineCacheWorkIDs)
    }

    func toggleAllOfflineCacheWorks(ownerName: String? = nil) {
        let ids = offlineCacheWorkIDs(ownerName: ownerName)
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: selectedOfflineCacheWorkIDs) {
            selectedOfflineCacheWorkIDs.subtract(ids)
        } else {
            selectedOfflineCacheWorkIDs.formUnion(ids)
        }
    }

    private func offlineCacheWorkIDs(ownerName: String?) -> Set<String> {
        let groups = ownerName.map { name in
            offlineCacheQueueGroups.filter { $0.ownerName == name }
        } ?? offlineCacheQueueGroups
        return Set(groups.flatMap { group in
            group.chapters.map(\.id)
        })
    }

    private func offlineCacheWorkIDs(ownerName: String) -> Set<String> {
        Set(
            offlineCacheQueueGroups
                .first { $0.ownerName == ownerName }?
                .chapters
                .map(\.id) ?? []
        )
    }

    private func offlineCacheChapterRow(id: String) -> MineOfflineCacheQueueChapterRow? {
        offlineCacheChapterRowsByID()[id]
    }

    private func offlineCacheChapterRowsByID() -> [String: MineOfflineCacheQueueChapterRow] {
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
        let store = appContext.makeOfflineCacheStore()
        let updates = store.offlineCacheUpdates()
        offlineCacheQueueUpdatesTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await self?.refreshOfflineCacheQueue()
            }
        }
    }

    private func offlineCacheDirectoriesByOwnerName(
        for works: [MangaOfflineCacheWork]
    ) async -> [String: MangaDirectory] {
        var directoriesByOwnerName: [String: MangaDirectory] = [:]
        for work in works.sorted(by: { $0.insertionIndex < $1.insertionIndex }) {
            guard directoriesByOwnerName[work.ownerName] == nil else { continue }
            if let directory = try? await appContext.mangaDirectoryStore.directory(named: work.ownerName) {
                directoriesByOwnerName[work.ownerName] = directory
            }
        }
        return directoriesByOwnerName
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
