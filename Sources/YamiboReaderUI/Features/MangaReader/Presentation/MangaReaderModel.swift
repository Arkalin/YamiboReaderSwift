import SwiftUI
import YamiboReaderCore

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var presentation: MangaReaderPresentation

    public let context: MangaLaunchContext

    private let appContext: YamiboAppContext
    private var workflow: MangaReaderWorkflow?
    private var hasPrepared = false

    public init(context: MangaLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    public func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: await appContext.makeMangaChapterDocumentLoader(),
            directoryRepository: await appContext.makeMangaDirectoryRepository(),
            directoryStore: appContext.makeMangaDirectoryStore()
        )
        self.workflow = workflow
        presentation = workflow.presentation
        presentation = await workflow.prepare()
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }
}
