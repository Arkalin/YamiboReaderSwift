import YamiboReaderCore

#if os(iOS)
import UIKit

@MainActor
final class NovelTextSelectionController {
    enum SelectionMode {
        case paged
        case vertical
    }

    private let registeredViews = NSHashTable<NovelTextViewportReferenceUIView>.weakObjects()
    private var selectionRangeValue: NovelTextSelectionRange?
    private var baseAnchor: NovelTextSelectionAnchor?
    private var activeSurfaceIdentity: NovelReaderSurfaceIdentity?
    private weak var verticalScrollView: UIScrollView?
    private var mode = SelectionMode.paged

    var hasSelection: Bool {
        selectionRangeValue != nil
    }

    func configure(mode: SelectionMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        if mode == .paged {
            verticalScrollView = nil
        }
        clearSelection()
    }

    func attachVerticalScrollView(_ scrollView: UIScrollView) {
        verticalScrollView = scrollView
    }

    func register(_ view: NovelTextViewportReferenceUIView) {
        registeredViews.add(view)
        view.setNeedsDisplay()
    }

    func unregister(_ view: NovelTextViewportReferenceUIView) {
        registeredViews.remove(view)
    }

    func beginSelection(
        in view: NovelTextViewportReferenceUIView,
        at point: CGPoint
    ) -> Bool {
        guard let displayReference = view.displayReference,
              !displayReference.isStale,
              let anchor = displayReference.selectionAnchor(at: point),
              let expandedRange = displayReference.expandedSelectionRange(around: anchor) else {
            clearSelection()
            return false
        }
        baseAnchor = anchor
        activeSurfaceIdentity = displayReference.surfaceIdentity
        selectionRangeValue = expandedRange
        refreshSelectionDisplay()
        return true
    }

    func updateSelection(
        in view: NovelTextViewportReferenceUIView,
        at point: CGPoint
    ) {
        guard let baseAnchor,
              let displayReference = view.displayReference,
              !displayReference.isStale else {
            return
        }
        if mode == .paged, displayReference.surfaceIdentity != activeSurfaceIdentity {
            return
        }
        guard let anchor = displayReference.selectionAnchor(at: point),
              let range = displayReference.selectionRange(from: baseAnchor, to: anchor) else {
            return
        }
        selectionRangeValue = range
        autoScrollIfNeeded(from: view, point: point)
        refreshSelectionDisplay()
    }

    func clearSelection() {
        guard selectionRangeValue != nil || baseAnchor != nil else { return }
        selectionRangeValue = nil
        baseAnchor = nil
        activeSurfaceIdentity = nil
        dismissMenus()
        refreshSelectionDisplay()
    }

    func selectionRange(
        for displayReference: NovelTextViewportDisplayReference
    ) -> NovelTextSelectionRange? {
        guard let selectionRangeValue,
              selectionRangeValue.generation == displayReference.generation,
              !displayReference.isStale else {
            return nil
        }
        return selectionRangeValue
    }

    func menuTargetRect(in view: NovelTextViewportReferenceUIView) -> CGRect {
        guard let displayReference = view.displayReference,
              let range = selectionRange(for: displayReference) else {
            return view.bounds
        }
        let rects = displayReference.selectionRects(for: range)
        guard !rects.isEmpty else { return view.bounds }
        return rects.reduce(CGRect.null) { partial, rect in
            partial.union(rect)
        }
    }

    func copySelection() {
        guard let selectionRangeValue,
              let displayReference = firstCurrentDisplayReference(),
              let text = displayReference.selectedText(for: selectionRangeValue),
              !text.isEmpty else {
            return
        }
        UIPasteboard.general.string = text
    }

    func refreshSelectionDisplay() {
        for view in registeredViews.allObjects {
            view.setNeedsDisplay()
        }
    }

    private func firstCurrentDisplayReference() -> NovelTextViewportDisplayReference? {
        registeredViews
            .allObjects
            .compactMap(\.displayReference)
            .first { !$0.isStale && $0.generation == selectionRangeValue?.generation }
    }

    private func dismissMenus() {
        for view in registeredViews.allObjects {
            view.dismissCopyMenu()
        }
    }

    private func autoScrollIfNeeded(
        from view: UIView,
        point: CGPoint
    ) {
        guard mode == .vertical,
              let scrollView = verticalScrollView,
              view.window != nil else {
            return
        }
        let pointInScrollView = view.convert(point, to: scrollView)
        let edgeThreshold: CGFloat = 48
        let step: CGFloat = 18
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )

        let nextOffsetY: CGFloat?
        if pointInScrollView.y < scrollView.bounds.minY + edgeThreshold {
            nextOffsetY = max(scrollView.contentOffset.y - step, minOffsetY)
        } else if pointInScrollView.y > scrollView.bounds.maxY - edgeThreshold {
            nextOffsetY = min(scrollView.contentOffset.y + step, maxOffsetY)
        } else {
            nextOffsetY = nil
        }

        guard let nextOffsetY,
              nextOffsetY != scrollView.contentOffset.y else {
            return
        }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: nextOffsetY),
            animated: false
        )
    }
}
#endif
