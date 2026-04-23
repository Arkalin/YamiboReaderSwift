import Foundation

struct ReaderVerticalScrollRequest: Equatable, Sendable {
    let pageIndex: Int
    let intraPageProgress: Double
}

enum ReaderVerticalRestorePhase: Equatable, Sendable {
    case idle
    case scrolling(request: ReaderVerticalScrollRequest)
    case fineTuning(request: ReaderVerticalScrollRequest)
    case settling(request: ReaderVerticalScrollRequest, deadline: CFTimeInterval)
}

struct ReaderVerticalRestoreController: Equatable, Sendable {
    private(set) var phase: ReaderVerticalRestorePhase = .idle

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
        activeRequest != nil
    }

    mutating func beginScrolling(to request: ReaderVerticalScrollRequest) {
        phase = .scrolling(request: request)
    }

    mutating func beginFineTuning(_ request: ReaderVerticalScrollRequest) {
        phase = .fineTuning(request: request)
    }

    mutating func beginSettling(_ request: ReaderVerticalScrollRequest, now: CFTimeInterval, duration: CFTimeInterval = 0.45) {
        phase = .settling(request: request, deadline: now + duration)
    }

    mutating func cancel() {
        phase = .idle
    }

    mutating func refresh(now: CFTimeInterval) {
        guard case let .settling(_, deadline) = phase, now >= deadline else { return }
        phase = .idle
    }

    mutating func canSampleViewport(now: CFTimeInterval) -> Bool {
        refresh(now: now)
        return !shouldSuppressViewportSampling
    }
}
