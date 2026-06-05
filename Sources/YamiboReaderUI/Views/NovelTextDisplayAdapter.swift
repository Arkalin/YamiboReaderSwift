import YamiboReaderCore

#if canImport(UIKit)
import SwiftUI
import UIKit

struct NativeNovelTextViewportReferenceView: UIViewRepresentable {
    let displayReference: NovelTextViewportDisplayReference

    func makeUIView(context: Context) -> NovelTextViewportReferenceUIView {
        NovelTextViewportReferenceUIView()
    }

    func updateUIView(_ uiView: NovelTextViewportReferenceUIView, context: Context) {
        uiView.displayReference = displayReference
    }
}

@MainActor
final class NovelTextViewportReferenceUIView: UIView {
    var displayReference: NovelTextViewportDisplayReference? {
        didSet {
            guard oldValue !== displayReference else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let displayReference,
              !displayReference.isStale else {
            return
        }
        displayReference.draw(in: context, bounds: bounds)
    }

    private func configureSurface() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
}
#endif
