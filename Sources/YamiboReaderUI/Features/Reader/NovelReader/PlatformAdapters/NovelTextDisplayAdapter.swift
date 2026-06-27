import YamiboReaderCore

#if canImport(UIKit)
import SwiftUI
import UIKit

struct NativeNovelTextViewportReferenceView: UIViewRepresentable {
    let displayReference: NovelTextViewportDisplayReference
    let selectionController: NovelTextSelectionController?

    init(
        displayReference: NovelTextViewportDisplayReference,
        selectionController: NovelTextSelectionController? = nil
    ) {
        self.displayReference = displayReference
        self.selectionController = selectionController
    }

    func makeUIView(context: Context) -> NovelTextViewportReferenceUIView {
        NovelTextViewportReferenceUIView()
    }

    func updateUIView(_ uiView: NovelTextViewportReferenceUIView, context: Context) {
        uiView.displayReference = displayReference
        uiView.selectionController = selectionController
    }
}

struct NativeNovelTextSettingsPreviewView: UIViewRepresentable {
    let surface: NovelTextSettingsPreviewSurface

    func makeUIView(context: Context) -> NovelTextSettingsPreviewUIView {
        NovelTextSettingsPreviewUIView()
    }

    func updateUIView(_ uiView: NovelTextSettingsPreviewUIView, context: Context) {
        uiView.surface = surface
    }
}

@MainActor
final class NovelTextViewportReferenceUIView: UIView, @preconcurrency UIEditMenuInteractionDelegate {
    var displayReference: NovelTextViewportDisplayReference? {
        didSet {
            guard oldValue !== displayReference else { return }
            selectionController?.refreshSelectionDisplay()
            setNeedsDisplay()
        }
    }

    weak var selectionController: NovelTextSelectionController? {
        didSet {
            guard oldValue !== selectionController else { return }
            oldValue?.unregister(self)
            selectionController?.register(self)
            setNeedsDisplay()
        }
    }

    private var lastDrawBounds: CGRect = .zero
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override func draw(_ rect: CGRect) {
        guard self.bounds.width > 0, self.bounds.height > 0 else {
            return
        }
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(self.bounds)
        guard let displayReference = self.displayReference else {
            return
        }
        guard !displayReference.isStale else {
            return
        }
        displayReference.drawBlockBackgrounds(in: context, bounds: self.bounds)
        drawSelectionHighlight(
            displayReference: displayReference,
            in: context
        )
        displayReference.drawText(in: context, bounds: self.bounds)
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(copy(_:)) && selectionController?.hasSelection == true
    }

    override func copy(_ sender: Any?) {
        selectionController?.copySelection()
    }

    func dismissCopyMenu() {
        editMenuInteraction.dismissMenu()
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard selectionController?.hasSelection == true else { return nil }
        if !suggestedActions.isEmpty {
            return UIMenu(children: suggestedActions)
        }
        let copyAction = UIAction(
            title: L10n.string("reader.copy")
        ) { [weak self] _ in
            self?.selectionController?.copySelection()
        }
        return UIMenu(children: [copyAction])
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        selectionController?.menuTargetRect(in: self) ?? bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard self.bounds != self.lastDrawBounds else { return }
        self.lastDrawBounds = self.bounds
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        setNeedsDisplay()
    }

    private func configureSurface() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        clearsContextBeforeDrawing = true
        contentMode = .redraw
        let longPressRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = 0.35
        addGestureRecognizer(longPressRecognizer)
        addInteraction(editMenuInteraction)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let selectionController else { return }
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard selectionController.beginSelection(in: self, at: point) else { return }
            becomeFirstResponder()
            dismissCopyMenu()
        case .changed:
            selectionController.updateSelection(in: self, at: point)
        case .ended:
            selectionController.updateSelection(in: self, at: point)
            showCopyMenu()
        case .cancelled, .failed:
            dismissCopyMenu()
        default:
            break
        }
    }

    private func showCopyMenu() {
        guard selectionController?.hasSelection == true else { return }
        let targetRect = selectionController?.menuTargetRect(in: self) ?? bounds
        editMenuInteraction.presentEditMenu(
            with: UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: CGPoint(x: targetRect.midX, y: targetRect.minY)
            )
        )
    }

    private func drawSelectionHighlight(
        displayReference: NovelTextViewportDisplayReference,
        in context: CGContext
    ) {
        guard let selectionController,
              let range = selectionController.selectionRange(for: displayReference) else {
            return
        }
        let rects = displayReference.selectionRects(for: range)
        guard !rects.isEmpty else { return }
        context.saveGState()
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.22).cgColor)
        for rect in rects {
            context.fill(rect.insetBy(dx: -1, dy: -1))
        }
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.85).cgColor)
        if let first = rects.first {
            context.fill(
                CGRect(
                    x: first.minX - 2,
                    y: first.minY,
                    width: 3,
                    height: max(first.height, 12)
                )
            )
        }
        if let last = rects.last {
            context.fill(
                CGRect(
                    x: last.maxX - 1,
                    y: last.minY,
                    width: 3,
                    height: max(last.height, 12)
                )
            )
        }
        context.restoreGState()
    }
}

@MainActor
final class NovelTextSettingsPreviewUIView: UIView {
    var surface: NovelTextSettingsPreviewSurface? {
        didSet {
            guard oldValue !== surface else { return }
            setNeedsDisplay()
        }
    }

    private var lastDrawBounds: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override func draw(_ rect: CGRect) {
        guard self.bounds.width > 0, self.bounds.height > 0 else {
            return
        }
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(self.bounds)
        surface?.draw(in: context, bounds: self.bounds)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard self.bounds != self.lastDrawBounds else { return }
        self.lastDrawBounds = self.bounds
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        setNeedsDisplay()
    }

    private func configureSurface() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        clearsContextBeforeDrawing = true
        contentMode = .redraw
    }
}
#endif
