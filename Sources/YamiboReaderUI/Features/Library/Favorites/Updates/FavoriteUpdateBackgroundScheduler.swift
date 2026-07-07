#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
import Foundation
import YamiboReaderCore

/// BGAppRefreshTask wiring for automatic favorite update checks. iOS decides
/// the actual run timing; the foreground catch-up in the favorites tab covers
/// the gaps (`FavoriteUpdateMonitor.startCheckIfDue`).
public enum FavoriteUpdateBackgroundScheduler {
    public static let taskIdentifier = "com.arkalin.YamiboReader.favoriteUpdates.refresh"

    /// Must run before the app finishes launching.
    @MainActor
    public static func register(appContext: YamiboAppContext) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handle(refreshTask, appContext: appContext)
            }
        }
    }

    /// Submits the next refresh request based on the configured interval, or
    /// cancels pending ones when automatic checking is off. Call when the app
    /// enters the background.
    @MainActor
    public static func scheduleNextIfNeeded(appContext: YamiboAppContext) {
        Task { @MainActor in
            let monitor = makeMonitor(appContext: appContext)
            await monitor.load()
            guard let interval = await monitor.configuredInterval(),
                  let delay = interval.nextDelay(hasRecentEvents: monitor.hasRecentEvents) else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    @MainActor
    private static func handle(_ task: BGAppRefreshTask, appContext: YamiboAppContext) async {
        let monitor = makeMonitor(appContext: appContext)
        await monitor.load()
        task.expirationHandler = {
            Task { @MainActor in
                await monitor.interrupt()
            }
        }
        let started = await monitor.startCheckIfDue()
        if started {
            await monitor.waitForCompletion()
        }
        task.setTaskCompleted(success: monitor.snapshot?.status != .failed)
        scheduleNextIfNeeded(appContext: appContext)
    }

    @MainActor
    private static func makeMonitor(appContext: YamiboAppContext) -> FavoriteUpdateMonitor {
        let dependencies = appContext.libraryDependencies
        return FavoriteUpdateMonitor(
            updateStore: dependencies.favoriteUpdateStore,
            libraryStore: dependencies.localFavoriteLibraryStore,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            settingsStore: dependencies.settingsStore
        )
    }
}
#endif
