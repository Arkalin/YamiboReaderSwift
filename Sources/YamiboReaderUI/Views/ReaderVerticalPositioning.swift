import CoreGraphics

enum ReaderVerticalPositioning {
    static func viewportReferenceLineY(in bounds: CGRect) -> CGFloat {
        bounds.height / 2
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
