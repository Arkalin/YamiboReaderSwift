import Foundation

struct ReaderVerticalScrollRequest: Equatable, Sendable {
    let view: Int?
    let pageIndex: Int
    let intraPageProgress: Double

    init(view: Int? = nil, pageIndex: Int, intraPageProgress: Double) {
        self.view = view
        self.pageIndex = pageIndex
        self.intraPageProgress = intraPageProgress
    }
}

enum ReaderVerticalRestorePhase: Equatable, Sendable {
    case idle
    case scrolling(request: ReaderVerticalScrollRequest)
    case fineTuning(request: ReaderVerticalScrollRequest)
    case settling(request: ReaderVerticalScrollRequest, deadline: CFTimeInterval)
}

struct ReaderVerticalRestoreController: Equatable, Sendable {
    private(set) var phase: ReaderVerticalRestorePhase = .idle
    private var viewportSamplingSuppressedUntil: CFTimeInterval?

    var activeRequest: ReaderVerticalScrollRequest? {
        switch phase {
        case .idle:
            return nil
        case let .scrolling(request),
             let .fineTuning(request),
             let .settling(request, _):
            return request
        }
    }

    var scrollingRequest: ReaderVerticalScrollRequest? {
        if case let .scrolling(request) = phase {
            return request
        }
        return nil
    }

    var shouldSuppressViewportSampling: Bool {
        activeRequest != nil || viewportSamplingSuppressedUntil != nil
    }

    var shouldConcealViewportContent: Bool {
        switch phase {
        case .scrolling, .fineTuning:
            return true
        case .idle, .settling:
            return false
        }
    }

    mutating func beginScrolling(to request: ReaderVerticalScrollRequest) {
        viewportSamplingSuppressedUntil = nil
        phase = .scrolling(request: request)
    }

    mutating func beginFineTuning(_ request: ReaderVerticalScrollRequest) {
        phase = .fineTuning(request: request)
    }

    mutating func beginSettling(_ request: ReaderVerticalScrollRequest, now: CFTimeInterval, duration: CFTimeInterval = 0.45) {
        phase = .settling(request: request, deadline: now + duration)
    }

    mutating func cancel(now: CFTimeInterval? = nil, samplingCooldown: CFTimeInterval = 0.25) {
        phase = .idle
        guard let now, samplingCooldown > 0 else {
            viewportSamplingSuppressedUntil = nil
            return
        }
        viewportSamplingSuppressedUntil = now + samplingCooldown
    }

    mutating func refresh(now: CFTimeInterval) {
        if case let .settling(_, deadline) = phase, now >= deadline {
            phase = .idle
        }
        if let viewportSamplingSuppressedUntil, now >= viewportSamplingSuppressedUntil {
            self.viewportSamplingSuppressedUntil = nil
        }
    }

    mutating func canSampleViewport(now: CFTimeInterval) -> Bool {
        refresh(now: now)
        return !shouldSuppressViewportSampling
    }
}
