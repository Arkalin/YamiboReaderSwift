import CoreGraphics

struct ReaderVerticalViewportSample: Equatable {
    var pageIndex: Int
    var intraPageProgress: Double
}

enum ReaderVerticalPositioning {
    static func sample(
        frames: [Int: CGRect],
        referenceLineY: CGFloat
    ) -> ReaderVerticalViewportSample? {
        guard let bestMatch = frames
            .filter({ $0.value.height > 0 })
            .min(by: { lhs, rhs in
                pageDistance(from: referenceLineY, to: lhs.value) < pageDistance(from: referenceLineY, to: rhs.value)
            }) else {
            return nil
        }

        let frame = bestMatch.value
        return ReaderVerticalViewportSample(
            pageIndex: bestMatch.key,
            intraPageProgress: min(max((referenceLineY - frame.minY) / max(frame.height, 1), 0), 1)
        )
    }

    static func pageDistance(from referenceLineY: CGFloat, to frame: CGRect) -> CGFloat {
        if frame.contains(CGPoint(x: frame.midX, y: referenceLineY)) {
            return 0
        }
        if referenceLineY < frame.minY {
            return frame.minY - referenceLineY
        }
        return referenceLineY - frame.maxY
    }
}
