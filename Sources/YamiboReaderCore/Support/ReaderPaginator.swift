import Foundation
import CoreGraphics

public enum NovelTextLayoutFailure: LocalizedError, Equatable, Sendable {
    case unableToLayoutText

    public var errorDescription: String? {
        switch self {
        case .unableToLayoutText:
            return "Novel Text Layout could not produce rendered text."
        }
    }
}

public typealias NovelTextPagination = @Sendable (
    _ document: ReaderPageDocument,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) throws -> NovelTextLayoutResult

public enum ReaderPaginator {
    public static func paginate(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try NovelTextLayout.layout(document: document, settings: settings, layout: layout)
    }

    public static func paginateNovelTextLayout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try NovelTextLayout.layout(document: document, settings: settings, layout: layout)
    }

    static func paginateNovelTextLayout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportPageLayout: NovelTextViewportPageLayout? = nil
    ) throws -> NovelTextLayoutResult {
        try NovelTextLayout.layout(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: viewportPageLayout
        )
    }

}
