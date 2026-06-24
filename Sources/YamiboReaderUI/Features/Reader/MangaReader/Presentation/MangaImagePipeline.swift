import Foundation
import YamiboReaderCore

#if os(iOS)
import UIKit

enum MangaImagePipelineError: Error, Equatable {
    case invalidImageData
}

@MainActor
final class MangaImagePipeline {
    static let defaultMemoryLimitBytes = 80 * 1024 * 1024

    private let dataLoader: any MangaImageDataLoading
    private let cache = NSCache<NSString, UIImage>()
    private var inFlightContinuations: [String: [CheckedContinuation<UIImage, Error>]] = [:]
    private var prefetchingKeys = Set<String>()

    init(
        dataLoader: any MangaImageDataLoading,
        memoryLimitBytes: Int = defaultMemoryLimitBytes
    ) {
        self.dataLoader = dataLoader
        cache.totalCostLimit = memoryLimitBytes
    }

    func cachedImage(for page: MangaReaderPageProjection) -> UIImage? {
        cache.object(forKey: cacheKey(for: page) as NSString)
    }

    func prefetchImages(for pages: [MangaReaderPageProjection]) {
        for page in pages {
            let key = cacheKey(for: page)
            guard cache.object(forKey: key as NSString) == nil,
                  inFlightContinuations[key] == nil,
                  prefetchingKeys.insert(key).inserted else {
                continue
            }

            Task { @MainActor in
                defer {
                    self.prefetchingKeys.remove(key)
                }
                _ = try? await self.image(for: page)
            }
        }
    }

    func image(for page: MangaReaderPageProjection) async throws -> UIImage {
        let key = cacheKey(for: page)
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
                await self.loadImage(for: page, key: key)
            }
        }
    }

    private func loadImage(for page: MangaReaderPageProjection, key: String) async {
        do {
            let data = try await dataLoader.imageData(for: page.imageURL, refererURL: page.refererURL)
            guard let image = UIImage(data: data) else {
                throw MangaImagePipelineError.invalidImageData
            }
            cache.setObject(image, forKey: key as NSString, cost: Self.cost(for: image))
            finishLoad(for: key, result: .success(image))
        } catch {
            finishLoad(for: key, result: .failure(error))
        }
    }

    private func finishLoad(for key: String, result: Result<UIImage, Error>) {
        let continuations = inFlightContinuations.removeValue(forKey: key) ?? []
        continuations.forEach { continuation in
            continuation.resume(with: result)
        }
    }

    private func cacheKey(for page: MangaReaderPageProjection) -> String {
        page.imageURL.absoluteString
    }

    private static func cost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let scale = max(image.scale, 1)
        return Int(image.size.width * scale * image.size.height * scale * 4)
    }
}
#endif
