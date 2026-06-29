public struct ReaderNavigationLinearReadingExpiration<PageKey: Equatable & Sendable>: Equatable, Sendable {
    public static var defaultThreshold: Int { 5 }

    public private(set) var latestPageKey: PageKey?
    public private(set) var linearPageCount: Int
    public var threshold: Int

    public init(threshold: Int = Self.defaultThreshold) {
        self.threshold = max(threshold, 1)
        latestPageKey = nil
        linearPageCount = 0
    }

    public var isArmed: Bool {
        latestPageKey != nil
    }

    public mutating func arm(at pageKey: PageKey) {
        latestPageKey = pageKey
        linearPageCount = 0
    }

    @discardableResult
    public mutating func recordLinearReading(at pageKey: PageKey) -> Bool {
        guard let latestPageKey else { return false }
        guard latestPageKey != pageKey else { return false }

        self.latestPageKey = pageKey
        linearPageCount += 1
        if linearPageCount >= threshold {
            reset()
            return true
        }
        return false
    }

    public mutating func reset() {
        latestPageKey = nil
        linearPageCount = 0
    }
}
