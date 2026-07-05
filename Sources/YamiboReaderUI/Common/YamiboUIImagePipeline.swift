import SwiftUI
import YamiboReaderCore
import UIKit
import Nuke

typealias YamiboPlatformImage = UIImage

enum YamiboUIImagePipelineError: Error, Equatable {
    case invalidImageData
}

@MainActor
final class YamiboUIImagePipeline {
    static let shared = YamiboUIImagePipeline()
    static let defaultMemoryLimitBytes = 80 * 1024 * 1024

    private let pipeline: ImagePipeline
    private var prefetchingKeys = Set<String>()

    init(memoryLimitBytes: Int = YamiboUIImagePipeline.defaultMemoryLimitBytes) {
        self.pipeline = ImagePipeline {
            $0.imageCache = ImageCache(costLimit: memoryLimitBytes)
            $0.dataCache = nil
            $0.isResumableDataEnabled = false
        }
    }

    func cachedImage(for request: YamiboImageRequest) -> YamiboPlatformImage? {
        pipeline.cache.cachedImage(for: nukeRequest(for: request))?.image
    }

    func image(
        for request: YamiboImageRequest,
        dataLoader: any YamiboImageDataLoading
    ) async throws -> YamiboPlatformImage {
        try await image(for: request) {
            try await dataLoader.imageData(for: request)
        }
    }

    func image(
        for request: YamiboImageRequest,
        loadData: @escaping @Sendable () async throws -> Data
    ) async throws -> YamiboPlatformImage {
        if let cached = cachedImage(for: request) {
            return cached
        }

        do {
            return try await pipeline.image(for: nukeRequest(for: request, loadData: loadData))
        } catch {
            throw Self.mapImagePipelineError(error)
        }
    }

    func prefetchImages(
        for requests: [YamiboImageRequest],
        dataLoader: any YamiboImageDataLoading
    ) {
        for request in requests {
            prefetchImage(for: request) {
                try await dataLoader.imageData(for: request)
            }
        }
    }

    func prefetchImage(
        for request: YamiboImageRequest,
        loadData: @escaping @Sendable () async throws -> Data
    ) {
        let key = request.cacheKey
        guard cachedImage(for: request) == nil,
              prefetchingKeys.insert(key).inserted else {
            return
        }

        Task { @MainActor in
            defer {
                self.prefetchingKeys.remove(key)
            }
            _ = try? await self.image(for: request, loadData: loadData)
        }
    }

    private func nukeRequest(for request: YamiboImageRequest) -> ImageRequest {
        nukeRequest(for: request) {
            Data()
        }
    }

    private func nukeRequest(
        for request: YamiboImageRequest,
        loadData: @escaping @Sendable () async throws -> Data
    ) -> ImageRequest {
        var imageRequest = ImageRequest(
            id: request.cacheKey,
            data: loadData,
            options: [.disableDiskCache]
        )
        imageRequest.scale = Float(UIScreen.main.scale)
        return imageRequest
    }

    private static func mapImagePipelineError(_ error: ImagePipeline.Error) -> Error {
        switch error {
        case .dataLoadingFailed(let underlying):
            return underlying
        case .dataIsEmpty, .decoderNotRegistered, .decodingFailed:
            return YamiboUIImagePipelineError.invalidImageData
        default:
            return error
        }
    }
}

extension EnvironmentValues {
    var yamiboImageLoadingContext: YamiboImageLoadingContext? {
        get { self[YamiboImageLoadingContextKey.self] }
        set { self[YamiboImageLoadingContextKey.self] = newValue }
    }
}

private struct YamiboImageLoadingContextKey: EnvironmentKey {
    static let defaultValue: YamiboImageLoadingContext? = nil
}

struct YamiboRemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    private let request: YamiboImageRequest?
    private let explicitContext: YamiboImageLoadingContext?
    private let pipeline: YamiboUIImagePipeline
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure

    @Environment(\.yamiboImageLoadingContext) private var environmentContext
    @State private var image: YamiboPlatformImage?
    @State private var didFail = false
    @State private var loadedKey: String?

    init(
        request: YamiboImageRequest?,
        context: YamiboImageLoadingContext? = nil,
        pipeline: YamiboUIImagePipeline = .shared,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.request = request
        explicitContext = context
        self.pipeline = pipeline
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let image {
                content(Image(yamiboPlatformImage: image))
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: taskIdentity) {
            await load()
        }
    }

    private var activeContext: YamiboImageLoadingContext? {
        explicitContext ?? environmentContext
    }

    private var taskIdentity: String {
        request?.cacheKey ?? "yamibo-image:no-request"
    }

    private func load() async {
        guard let request,
              let activeContext else {
            image = nil
            loadedKey = nil
            didFail = false
            return
        }
        guard loadedKey != request.cacheKey || image == nil else {
            return
        }
        if let cached = pipeline.cachedImage(for: request) {
            image = cached
            loadedKey = request.cacheKey
            didFail = false
            return
        }

        image = nil
        didFail = false
        do {
            let loaded = try await pipeline.image(for: request, dataLoader: activeContext.dataLoader)
            image = loaded
            loadedKey = request.cacheKey
            didFail = false
        } catch {
            loadedKey = request.cacheKey
            didFail = true
        }
    }
}

private extension Image {
    init(yamiboPlatformImage image: YamiboPlatformImage) {
        self.init(uiImage: image)
    }
}
