import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NovelTextViewportRuntimeDiagnostics: Equatable, Sendable {
    public var contentStorageCount: Int
    public var activeLayoutManagerCount: Int
    public var perPageTextKitDocumentCount: Int

    public init(
        contentStorageCount: Int,
        activeLayoutManagerCount: Int,
        perPageTextKitDocumentCount: Int
    ) {
        self.contentStorageCount = max(0, contentStorageCount)
        self.activeLayoutManagerCount = max(0, activeLayoutManagerCount)
        self.perPageTextKitDocumentCount = max(0, perPageTextKitDocumentCount)
    }
}

@MainActor
public final class NovelTextViewportDisplayReference {
    public let generation: UInt64
    public let documentView: Int
    public let pageIdentity: Int

    private weak var runtimeOwner: NovelTextViewportRuntimeOwner?

    init(
        runtimeOwner: NovelTextViewportRuntimeOwner,
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int
    ) {
        self.runtimeOwner = runtimeOwner
        self.generation = generation
        self.documentView = documentView
        self.pageIdentity = pageIdentity
    }

    public var isStale: Bool {
        guard let runtimeOwner else { return true }
        return !runtimeOwner.isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        )
    }

#if canImport(UIKit)
    public func draw(in context: CGContext, bounds: CGRect) {
        runtimeOwner?.draw(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity,
            in: context,
            bounds: bounds
        )
    }
#endif
}

@MainActor
final class NovelTextViewportRuntimeOwner {
    private var generation: UInt64 = 0
    private var result: NovelTextLayoutResult?
    private var settings = ReaderAppearanceSettings()
    private var layout = ReaderContainerLayout(width: 1, height: 1)

#if canImport(UIKit) || canImport(AppKit)
    private var textContentStorage: NSTextContentStorage?
    private var textLayoutManager: NSTextLayoutManager?
    private var textContainer: NSTextContainer?
#endif

    var diagnostics: NovelTextViewportRuntimeDiagnostics {
        NovelTextViewportRuntimeDiagnostics(
            contentStorageCount: textContentStorage == nil ? 0 : 1,
            activeLayoutManagerCount: textLayoutManager == nil ? 0 : 1,
            perPageTextKitDocumentCount: 0
        )
    }

    func commit(
        result: NovelTextLayoutResult,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) {
        guard self.result != result || self.settings != settings || self.layout != layout else {
            return
        }

#if canImport(UIKit) || canImport(AppKit)
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let contentWidth = max(layout.readableFrame.width - settings.horizontalPadding * 2, 1)
        let container = NSTextContainer(
            size: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
#if canImport(UIKit)
        contentStorage.textStorage?.setAttributedString(
            ReaderAttributedTextFactory.makeAttributedText(
                text: result.viewportContext.document.text,
                chapterTitle: nil,
                settings: settings
            )
        )
#else
        contentStorage.textStorage?.setAttributedString(
            NSAttributedString(string: result.viewportContext.document.text)
        )
#endif
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        textContentStorage = contentStorage
        textLayoutManager = layoutManager
        textContainer = container
#endif

        self.result = result
        self.settings = settings
        self.layout = layout
        generation &+= 1
    }

    func displayReference(for pageIdentity: Int) -> NovelTextViewportDisplayReference? {
        guard let page = result?.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }) else {
            return nil
        }
        return NovelTextViewportDisplayReference(
            runtimeOwner: self,
            generation: generation,
            documentView: page.documentView,
            pageIdentity: page.pageIndex
        )
    }

    func isCurrent(generation: UInt64, documentView: Int, pageIdentity: Int) -> Bool {
        guard generation == self.generation,
              let page = result?.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }) else {
            return false
        }
        return page.documentView == documentView
    }

#if canImport(UIKit)
    func draw(
        generation: UInt64,
        documentView: Int,
        pageIdentity: Int,
        in context: CGContext,
        bounds: CGRect
    ) {
        guard isCurrent(
            generation: generation,
            documentView: documentView,
            pageIdentity: pageIdentity
        ),
        let result,
        let textContentStorage,
        let textLayoutManager,
        let page = result.viewportIndex.pages.first(where: { $0.pageIndex == pageIdentity }),
        let firstRange = page.ranges.first,
        let documentRange = result.viewportContext.document.textRangesBySegment[firstRange.segmentIndex],
        let pageLocation = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: documentRange.startOffset + firstRange.startOffset
        ),
        let firstFragment = textLayoutManager.textLayoutFragment(for: pageLocation) else {
            return
        }

        let pageOriginY = firstFragment.layoutFragmentFrame.minY
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.minX, y: bounds.minY - pageOriginY)
        textLayoutManager.enumerateTextLayoutFragments(
            from: pageLocation,
            options: [.ensuresLayout]
        ) { fragment in
            guard fragment.layoutFragmentFrame.minY < pageOriginY + bounds.height else {
                return false
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
        context.restoreGState()
    }
#endif
}
