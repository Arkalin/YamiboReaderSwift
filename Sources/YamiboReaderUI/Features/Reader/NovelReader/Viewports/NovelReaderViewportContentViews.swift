import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

enum NovelReaderViewportDisplayBlock: Identifiable {
    case text
    case image(URL)
    case footer(String)

    var id: String {
        switch self {
        case .text:
            return "text"
        case let .image(url):
            return "image:\(url.absoluteString)"
        case let .footer(text):
            return "footer:\(text)"
        }
    }
}

struct NovelReaderPagedHostingTopSafeAreaModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.ignoresSafeArea(.container, edges: .top)
    }
}

struct NovelReaderPresentationSpreadContent: View {
    let spread: NovelReaderPresentationSpread
    let surfaces: [NovelReaderSurface]
    let settings: NovelReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any YamiboImageDataLoading
    let topInset: CGFloat
    let bottomInset: CGFloat
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let onImageTap: (URL, String?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            spreadColumn(surfaceIndex: spread.leftSurfaceIndex)
            spreadColumn(surfaceIndex: spread.rightSurfaceIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func spreadColumn(surfaceIndex: Int?) -> some View {
        Group {
            if let surfaceIndex {
                let surface = surfaces.first {
                    $0.presentationIndex == surfaceIndex
                }
                NovelReaderViewportSurfaceContent(
                    surface: surface,
                    displayReference: surface.flatMap { displayReferenceProvider($0.identity) },
                    selectionController: selectionController,
                    fallbackDocumentView: surface?.documentView,
                    fallbackSurfaceIndex: surfaceIndex,
                    settings: settings,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    onImageTap: onImageTap
                )
                .padding(.horizontal, settings.horizontalPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct NovelReaderViewportSurfaceContent: View {
    let surface: NovelReaderSurface?
    let displayReference: NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let fallbackDocumentView: Int?
    let fallbackSurfaceIndex: Int?
    let settings: NovelReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any YamiboImageDataLoading
    let onImageTap: (URL, String?) -> Void

    init(
        surface: NovelReaderSurface?,
        displayReference: NovelTextViewportDisplayReference? = nil,
        selectionController: NovelTextSelectionController? = nil,
        fallbackDocumentView: Int?,
        fallbackSurfaceIndex: Int?,
        settings: NovelReaderAppearanceSettings,
        refererURL: URL,
        imageDataLoader: any YamiboImageDataLoading,
        onImageTap: @escaping (URL, String?) -> Void = { _, _ in }
    ) {
        self.surface = surface
        self.displayReference = displayReference
        self.selectionController = selectionController
        self.fallbackDocumentView = fallbackDocumentView
        self.fallbackSurfaceIndex = fallbackSurfaceIndex
        self.settings = settings
        self.refererURL = refererURL
        self.imageDataLoader = imageDataLoader
        self.onImageTap = onImageTap
    }

    var body: some View {
        Group {
            if centersExternalBlockInPagedMode {
                centeredViewportBlocks
            } else {
                stackedViewportBlocks
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var stackedViewportBlocks: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(
                viewportBlocks
            ) { block in
                NovelReaderViewportBlockView(
                    block: block,
                    displayReference: displayReference,
                    selectionController: selectionController,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    title: surface?.chapterTitle,
                    onImageTap: onImageTap
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var centeredViewportBlocks: some View {
        VStack(alignment: .center, spacing: 14) {
            ForEach(
                viewportBlocks
            ) { block in
                NovelReaderViewportBlockView(
                    block: block,
                    displayReference: displayReference,
                    selectionController: selectionController,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    title: surface?.chapterTitle,
                    onImageTap: onImageTap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var viewportBlocks: [NovelReaderViewportDisplayBlock] {
        Self.viewportBlocks(surface: surface)
    }

    private var centersExternalBlockInPagedMode: Bool {
        settings.readingMode == .paged && surface?.kind == .externalBlock
    }

    private var accessibilityIdentifier: String {
        let contextView = surface?.documentView ?? fallbackDocumentView ?? 1
        let surfaceIndex = surface?.presentationIndex ?? fallbackSurfaceIndex ?? 0
        return "novel-viewport-surface-\(contextView)-\(surfaceIndex)"
    }

    static func viewportBlocks(
        surface: NovelReaderSurface?
    ) -> [NovelReaderViewportDisplayBlock] {
        let externalBlockImages = surface?.externalBlocks.map {
            NovelReaderViewportDisplayBlock.image($0.url)
        } ?? []
        var blocks: [NovelReaderViewportDisplayBlock] = []
        guard let surface else {
            return externalBlockImages.isEmpty ? [.footer(L10n.string("reader.empty_content"))] : externalBlockImages
        }
        if surface.kind == .text {
            blocks.append(.text)
        }
        blocks.append(contentsOf: externalBlockImages)
        if blocks.isEmpty {
            blocks.append(.footer(L10n.string("reader.empty_content")))
        }
        return blocks
    }

}


private struct NovelReaderViewportBlockView: View {
    let block: NovelReaderViewportDisplayBlock
    let displayReference: NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let refererURL: URL
    let imageDataLoader: any YamiboImageDataLoading
    let title: String?
    let onImageTap: (URL, String?) -> Void

    var body: some View {
        switch block {
        case .text:
            if let displayReference, !displayReference.isStale {
                NativeNovelTextViewportReferenceView(
                    displayReference: displayReference,
                    selectionController: selectionController
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear.frame(height: 1)
            }
        case let .image(url):
            NovelReaderInlineViewportImage(
                url: url,
                refererURL: refererURL,
                imageDataLoader: imageDataLoader,
                title: title,
                onTap: onImageTap
            )
        case let .footer(text):
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        }
    }

}

@MainActor
final class NovelReaderImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var didFail = false

    private let request: YamiboImageRequest
    private let imageDataLoader: any YamiboImageDataLoading

    init(
        request: YamiboImageRequest,
        imageDataLoader: any YamiboImageDataLoading
    ) {
        self.request = request
        self.imageDataLoader = imageDataLoader
    }

    func loadIfNeeded() async {
        let imageDataLoader = self.imageDataLoader
        let request = self.request
        if let cachedImage = YamiboUIImagePipeline.shared.cachedImage(for: request) {
            image = cachedImage
            didFail = false
            return
        }
        guard image == nil, !isLoading else { return }
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            let image = try await YamiboUIImagePipeline.shared.image(for: request) {
                try await imageDataLoader.imageData(for: request)
            }
            self.image = image
            didFail = false
        } catch {
            didFail = true
        }
    }

    func retry() async {
        await loadIfNeeded()
    }
}

private struct AuthenticatedReaderImage: View {
    @StateObject private var loader: NovelReaderImageLoader

    init(
        request: YamiboImageRequest,
        imageDataLoader: any YamiboImageDataLoading
    ) {
        _loader = StateObject(
            wrappedValue: NovelReaderImageLoader(
                request: request,
                imageDataLoader: imageDataLoader
            )
        )
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.didFail {
                VStack(spacing: 8) {
                    Label(L10n.string("image.load_failed"), systemImage: "photo")
                        .foregroundColor(.secondary)

                    Button {
                        Task {
                            await loader.retry()
                        }
                    } label: {
                        Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await loader.loadIfNeeded()
        }
    }
}

#endif
