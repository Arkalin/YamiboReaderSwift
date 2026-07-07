import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor FavoriteBackgroundImageStore {
    public static let defaultJPEGQuality = 0.88
    public static let defaultMaximumLongEdgePixels = 4096

    private let fileManager: FileManager
    private let baseDirectory: URL

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("favorite-background", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("favorite-background", isDirectory: true)
    }

    public func loadData(imageID: String?) async -> Data? {
        guard let imageID, !imageID.isEmpty else { return nil }
        do {
            return try Data(contentsOf: imageURL(for: imageID))
        } catch {
            YamiboLog.library.warning("Failed to read favorite background image data for id \(imageID, privacy: .public): \(error)")
            return nil
        }
    }

    public func save(_ data: Data, imageID: String) async throws {
        try ensureDirectoryExists()
        try data.write(to: imageURL(for: imageID), options: [.atomic])
    }

    public func delete(imageID: String?) async throws {
        guard let imageID, !imageID.isEmpty else { return }
        let url = imageURL(for: imageID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func deleteAll() async throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
    }

    public func prune(keeping imageID: String?) async throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        let keepFileName = imageID.map(fileName(for:))
        let urls = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.lastPathComponent != keepFileName {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                YamiboLog.library.warning("Failed to remove stale favorite background image \(url.lastPathComponent, privacy: .public): \(error)")
            }
        }
    }

    public func fileExists(imageID: String?) async -> Bool {
        guard let imageID, !imageID.isEmpty else { return false }
        return fileManager.fileExists(atPath: imageURL(for: imageID).path)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func imageURL(for imageID: String) -> URL {
        baseDirectory.appendingPathComponent(fileName(for: imageID), isDirectory: false)
    }

    private func fileName(for imageID: String) -> String {
        "\(imageID).jpg"
    }
}

public enum FavoriteBackgroundImageProcessor {
    public static func normalizedJPEGData(
        from sourceData: Data,
        maximumLongEdgePixels: Int = FavoriteBackgroundImageStore.defaultMaximumLongEdgePixels,
        compressionQuality: Double = FavoriteBackgroundImageStore.defaultJPEGQuality
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw YamiboError.persistenceFailed("Invalid image data")
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumLongEdgePixels),
            kCGImageSourceShouldCache: false
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw YamiboError.persistenceFailed("Invalid image data")
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw YamiboError.persistenceFailed("Unable to create JPEG destination")
        }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: FavoriteBackgroundSettings.clampJPEGQuality(compressionQuality)
        ]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw YamiboError.persistenceFailed("Unable to write JPEG data")
        }

        return output as Data
    }
}

public struct FavoriteBackgroundRenderedFrame: Equatable, Sendable {
    public var size: CGSize
    public var offset: CGSize

    public init(size: CGSize, offset: CGSize) {
        self.size = size
        self.offset = offset
    }
}

public enum FavoriteBackgroundLayout {
    public static func renderedFrame(
        imageSize: CGSize,
        containerSize: CGSize,
        settings: FavoriteBackgroundSettings
    ) -> FavoriteBackgroundRenderedFrame {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return FavoriteBackgroundRenderedFrame(size: .zero, offset: .zero)
        }

        let fillScale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let relativeScale = FavoriteBackgroundSettings.clampScale(settings.scale)
        let renderedSize = CGSize(
            width: imageSize.width * fillScale * relativeScale,
            height: imageSize.height * fillScale * relativeScale
        )
        let overflowX = max(0, (renderedSize.width - containerSize.width) / 2)
        let overflowY = max(0, (renderedSize.height - containerSize.height) / 2)
        let offset = CGSize(
            width: overflowX * FavoriteBackgroundSettings.clampOffset(settings.offsetX),
            height: overflowY * FavoriteBackgroundSettings.clampOffset(settings.offsetY)
        )

        return FavoriteBackgroundRenderedFrame(size: renderedSize, offset: offset)
    }

    public static func normalizedOffsets(
        imageSize: CGSize,
        containerSize: CGSize,
        scale: Double,
        proposedOffset: CGSize
    ) -> (offsetX: Double, offsetY: Double) {
        let settings = FavoriteBackgroundSettings(scale: scale)
        let frame = renderedFrame(imageSize: imageSize, containerSize: containerSize, settings: settings)
        let overflowX = max(0, (frame.size.width - containerSize.width) / 2)
        let overflowY = max(0, (frame.size.height - containerSize.height) / 2)

        return (
            offsetX: overflowX > 0 ? FavoriteBackgroundSettings.clampOffset(proposedOffset.width / overflowX) : 0,
            offsetY: overflowY > 0 ? FavoriteBackgroundSettings.clampOffset(proposedOffset.height / overflowY) : 0
        )
    }
}

private extension FavoriteBackgroundSettings {
    static func clampJPEGQuality(_ value: Double) -> Double {
        guard value.isFinite else { return FavoriteBackgroundImageStore.defaultJPEGQuality }
        return min(1, max(0, value))
    }
}
