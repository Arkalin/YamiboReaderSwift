import Foundation

#if os(iOS) && canImport(BackgroundTasks)
@preconcurrency import BackgroundTasks
#endif

public final class MangaOfflineCacheContinuedProcessingCoordinator: MangaOfflineCacheQueueRunObserving, @unchecked Sendable {
    public static let permittedIdentifier = "com.arkalin.YamiboReader.mangaOfflineCache.continuedProcessing.*"

    private let lock = NSLock()
    private let title: String
    private let subtitle: String
    private var activeTaskCompletion: (@Sendable (Bool) -> Void)?
    private var activeProgress: Progress?

    public init(
        title: String = L10n.string("mine.download_queue"),
        subtitle: String = L10n.string("mine.offline_queue.preparing")
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    public func submitUserInitiatedRun() async {
        #if os(iOS) && canImport(BackgroundTasks)
        guard #available(iOS 26.0, *) else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.makeTaskIdentifier(),
            title: title,
            subtitle: subtitle
        )
        request.strategy = .queue
        request.requiredResources = []
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return
        }
        #endif
    }

    public func queueRunDidUpdateProgress(
        completedImageCount: Int,
        targetImageCount: Int
    ) async {
        let progress = lock.withLock { activeProgress }
        guard let progress else { return }

        progress.totalUnitCount = max(Int64(targetImageCount), 1)
        progress.completedUnitCount = min(
            max(Int64(completedImageCount), 0),
            progress.totalUnitCount
        )
    }

    public func queueRunDidFinish(success: Bool) async {
        let completion = lock.withLock {
            let completion = activeTaskCompletion
            activeTaskCompletion = nil
            activeProgress = nil
            return completion
        }
        completion?(success)
    }

    public func queueRunDidCancel() async {
        await queueRunDidFinish(success: false)
    }

    #if os(iOS) && canImport(BackgroundTasks)
    @available(iOS 26.0, *)
    public static func registerLaunchHandler(
        coordinator: MangaOfflineCacheContinuedProcessingCoordinator,
        queue: DispatchQueue? = nil,
        continueQueue: @escaping @Sendable () async -> Void,
        pauseQueue: @escaping @Sendable () async -> Void
    ) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: permittedIdentifier,
            using: queue
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            coordinator.attach(
                task: task,
                pauseQueue: pauseQueue
            )
            Task {
                await continueQueue()
            }
        }
    }

    @available(iOS 26.0, *)
    private func attach(
        task: BGContinuedProcessingTask,
        pauseQueue: @escaping @Sendable () async -> Void
    ) {
        lock.withLock {
            activeProgress = task.progress
            activeProgress?.totalUnitCount = 1
            activeProgress?.completedUnitCount = 0
            activeTaskCompletion = { success in
                task.setTaskCompleted(success: success)
            }
        }
        task.expirationHandler = {
            Task {
                await pauseQueue()
            }
        }
    }

    @available(iOS 26.0, *)
    private static func makeTaskIdentifier() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.arkalin.YamiboReader"
        return "\(bundleIdentifier).mangaOfflineCache.continuedProcessing.\(UUID().uuidString)"
    }
    #endif
}

private extension NSLock {
    func withLock<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
