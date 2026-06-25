import YamiboReaderCore

public typealias ReaderResumeRouteChangeHandler = @MainActor @Sendable (ReaderResumeRoute) async -> Void
