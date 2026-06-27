import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

enum ReaderViewportDisplayBlock: Identifiable {
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

struct ReaderPagedHostingTopSafeAreaModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.ignoresSafeArea(.container, edges: .top)
    }
}

struct ReaderPresentationSpreadContent: View {
    let spread: NovelReaderPresentationSpread
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
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
                ReaderViewportSurfaceContent(
                    surface: surface,
                    displayReference: surface.flatMap { displayReferenceProvider($0.identity) },
                    selectionController: selectionController,
                    fallbackDocumentView: surface?.documentView,
                    fallbackSurfaceIndex: surfaceIndex,
                    settings: settings,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    imageCacheNamespace: imageCacheNamespace,
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

struct ReaderViewportSurfaceContent: View {
    let surface: NovelReaderSurface?
    let displayReference: NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let fallbackDocumentView: Int?
    let fallbackSurfaceIndex: Int?
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
    let onImageTap: (URL, String?) -> Void

    init(
        surface: NovelReaderSurface?,
        displayReference: NovelTextViewportDisplayReference? = nil,
        selectionController: NovelTextSelectionController? = nil,
        fallbackDocumentView: Int?,
        fallbackSurfaceIndex: Int?,
        settings: ReaderAppearanceSettings,
        refererURL: URL,
        imageDataLoader: any NovelInlineImageDataLoading,
        imageCacheNamespace: NovelInlineImageCacheNamespace,
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
        self.imageCacheNamespace = imageCacheNamespace
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
                ReaderViewportBlockView(
                    block: block,
                    displayReference: displayReference,
                    selectionController: selectionController,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    imageCacheNamespace: imageCacheNamespace,
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
                ReaderViewportBlockView(
                    block: block,
                    displayReference: displayReference,
                    selectionController: selectionController,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    imageCacheNamespace: imageCacheNamespace,
                    title: surface?.chapterTitle,
                    onImageTap: onImageTap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var viewportBlocks: [ReaderViewportDisplayBlock] {
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
    ) -> [ReaderViewportDisplayBlock] {
        let externalBlockImages = surface?.externalBlocks.map {
            ReaderViewportDisplayBlock.image($0.url)
        } ?? []
        var blocks: [ReaderViewportDisplayBlock] = []
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


private struct ReaderViewportBlockView: View {
    let block: ReaderViewportDisplayBlock
    let displayReference: NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
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
#if os(iOS)
            ReaderInlineViewportImage(
                url: url,
                refererURL: refererURL,
                imageDataLoader: imageDataLoader,
                imageCacheNamespace: imageCacheNamespace,
                title: title,
                onTap: onImageTap
            )
#else
            AuthenticatedReaderImage(
                url: url,
                refererURL: refererURL,
                imageDataLoader: imageDataLoader,
                imageCacheNamespace: imageCacheNamespace
            )
#endif
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
final class ReaderImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var didFail = false

    private let url: URL
    private let refererURL: URL
    private let imageDataLoader: any NovelInlineImageDataLoading
    private let imageCacheNamespace: NovelInlineImageCacheNamespace

    init(
        url: URL,
        refererURL: URL,
        imageDataLoader: any NovelInlineImageDataLoading,
        imageCacheNamespace: NovelInlineImageCacheNamespace
    ) {
        self.url = url
        self.refererURL = refererURL
        self.imageDataLoader = imageDataLoader
        self.imageCacheNamespace = imageCacheNamespace
    }

    func loadIfNeeded() async {
        let requestIdentity = ReaderInlineImageRequestIdentity(
            url: url,
            refererURL: refererURL,
            cacheNamespace: imageCacheNamespace
        )
        if let cachedImage = ReaderInlineImageMemoryCache.image(for: requestIdentity) {
            image = cachedImage
            didFail = false
            return
        }
        guard image == nil, !isLoading else { return }
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            let data = try await imageDataLoader.imageData(for: url, refererURL: refererURL)
            guard let image = UIImage(data: data) else {
                didFail = true
                return
            }
            ReaderInlineImageMemoryCache.store(image, for: requestIdentity)
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
    @StateObject private var loader: ReaderImageLoader

    init(
        url: URL,
        refererURL: URL,
        imageDataLoader: any NovelInlineImageDataLoading,
        imageCacheNamespace: NovelInlineImageCacheNamespace
    ) {
        _loader = StateObject(
            wrappedValue: ReaderImageLoader(
                url: url,
                refererURL: refererURL,
                imageDataLoader: imageDataLoader,
                imageCacheNamespace: imageCacheNamespace
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

struct ReaderInlineImageRequestIdentity: Hashable {
    let url: URL
    let refererURL: URL
    let cacheNamespace: NovelInlineImageCacheNamespace

    init(
        url: URL,
        refererURL: URL,
        cacheNamespace: NovelInlineImageCacheNamespace
    ) {
        self.url = url
        self.refererURL = refererURL
        self.cacheNamespace = cacheNamespace
    }

    var cacheKey: String {
        [
            url.absoluteString,
            refererURL.absoluteString,
            cacheNamespace.value
        ].joined(separator: "\u{1F}")
    }
}

struct ReaderInlineImageMemoryCache {
    static let defaultMemoryLimitBytes = 80 * 1024 * 1024

    private static let storage = ReaderInlineImageMemoryCacheStorage(memoryLimitBytes: defaultMemoryLimitBytes)

    private init() {}

    static func image(for requestIdentity: ReaderInlineImageRequestIdentity) -> UIImage? {
        storage.cache.object(forKey: requestIdentity.cacheKey as NSString)
    }

    static func store(_ image: UIImage, for requestIdentity: ReaderInlineImageRequestIdentity) {
        storage.cache.setObject(
            image,
            forKey: requestIdentity.cacheKey as NSString,
            cost: cost(for: image)
        )
    }

    private static func cost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let scale = max(image.scale, 1)
        return Int(image.size.width * scale * image.size.height * scale * 4)
    }
}

private final class ReaderInlineImageMemoryCacheStorage: @unchecked Sendable {
    let cache: NSCache<NSString, UIImage>

    init(memoryLimitBytes: Int) {
        cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = memoryLimitBytes
    }
}
#endif
