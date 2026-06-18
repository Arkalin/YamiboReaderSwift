import SwiftUI
import YamiboReaderCore

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var presentation: MangaReaderPresentation

    public let context: MangaLaunchContext
    #if os(iOS)
    private(set) var imagePipeline: MangaImagePipeline?
    #endif

    private let appContext: YamiboAppContext
    private var workflow: MangaReaderWorkflow?
    private var hasPrepared = false

    public init(context: MangaLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
        #if os(iOS)
        self.imagePipeline = nil
        #endif
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    public func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        #if os(iOS)
        let imagePipeline = MangaImagePipeline(dataLoader: await appContext.makeMangaImageDataLoader())
        #endif
        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: await appContext.makeMangaChapterDocumentLoader(),
            directoryRepository: await appContext.makeMangaDirectoryRepository(),
            directoryStore: appContext.makeMangaDirectoryStore()
        )
        self.workflow = workflow
        #if os(iOS)
        self.imagePipeline = imagePipeline
        #endif
        presentation = workflow.presentation
        presentation = await workflow.prepare()
    }

    public func updateCurrentPage(globalIndex: Int) {
        guard let workflow else { return }
        let nextPresentation = workflow.moveToLoadedPage(at: globalIndex)
        guard nextPresentation != presentation else { return }
        presentation = nextPresentation
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }
}
