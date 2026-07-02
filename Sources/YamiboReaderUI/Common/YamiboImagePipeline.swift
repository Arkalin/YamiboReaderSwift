import SwiftUI
import YamiboReaderCore
import UIKit

typealias YamiboPlatformImage = UIImage

enum YamiboImagePipelineError: Error, Equatable {
    case invalidImageData
}

@MainActor
final class YamiboImagePipeline {
    static let shared = YamiboImagePipeline()
    static let defaultMemoryLimitBytes = 80 * 1024 * 1024

    private let cache = NSCache<NSString, YamiboPlatformImage>()
    private var inFlightContinuations: [String: [CheckedContinuation<YamiboPlatformImage, Error>]] = [:]
    private var prefetchingKeys = Set<String>()

    init(memoryLimitBytes: Int = YamiboImagePipeline.defaultMemoryLimitBytes) {
        cache.totalCostLimit = memoryLimitBytes
    }

    func cachedImage(for request: YamiboImageRequest) -> YamiboPlatformImage? {
        cache.object(forKey: request.cacheKey as NSString)
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
        let key = request.cacheKey
        if let cachedImage = cache.object(forKey: key as NSString) {
            return cachedImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            if inFlightContinuations[key] != nil {
                inFlightContinuations[key, default: []].append(continuation)
                return
            }

            inFlightContinuations[key] = [continuation]
            Task { @MainActor in
                await self.loadImage(for: request, key: key, loadData: loadData)
            }
        }
    }

    func imageData(
        for request: YamiboImageRequest,
        dataLoader: any YamiboImageDataLoading
    ) async throws -> Data {
        try await dataLoader.imageData(for: request)
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
        guard cache.object(forKey: key as NSString) == nil,
              inFlightContinuations[key] == nil,
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

    private func loadImage(
        for request: YamiboImageRequest,
        key: String,
        loadData: @escaping @Sendable () async throws -> Data
    ) async {
        do {
            let data = try await loadData()
            guard let image = YamiboPlatformImage(data: data) else {
                throw YamiboImagePipelineError.invalidImageData
            }
            cache.setObject(image, forKey: key as NSString, cost: Self.cost(for: image, data: data))
            finishLoad(for: key, result: .success(image))
        } catch {
            finishLoad(for: key, result: .failure(error))
        }
    }

    private func finishLoad(for key: String, result: Result<YamiboPlatformImage, Error>) {
        let continuations = inFlightContinuations.removeValue(forKey: key) ?? []
        continuations.forEach { continuation in
            continuation.resume(with: result)
        }
    }

    private static func cost(for image: YamiboPlatformImage, data: Data) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let scale = max(image.scale, 1)
        return Int(image.size.width * scale * image.size.height * scale * 4)
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
    private let url: URL?
    private let refererURL: URL?
    private let explicitContext: YamiboImageLoadingContext?
    private let pipeline: YamiboImagePipeline
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure

    @Environment(\.yamiboImageLoadingContext) private var environmentContext
    @State private var image: YamiboPlatformImage?
    @State private var didFail = false
    @State private var loadedKey: String?

    init(
        url: URL?,
        refererURL: URL? = nil,
        context: YamiboImageLoadingContext? = nil,
        pipeline: YamiboImagePipeline = .shared,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.refererURL = refererURL
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

    private var request: YamiboImageRequest? {
        guard let url,
              let activeContext else {
            return nil
        }
        return YamiboImageRequest(
            url: url,
            refererURL: refererURL,
            cacheNamespace: activeContext.cacheNamespace
        )
    }

    private var taskIdentity: String {
        request?.cacheKey ?? "yamibo-image:\(url?.absoluteString ?? "nil"):no-context"
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
