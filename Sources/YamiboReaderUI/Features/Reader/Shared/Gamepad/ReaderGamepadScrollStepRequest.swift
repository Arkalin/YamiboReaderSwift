import Foundation
import YamiboReaderCore

/// One-shot "scroll one viewport" command for the vertical viewports,
/// deduplicated by `revision` like `MangaNovelReaderViewportPlacement`.
struct ReaderGamepadScrollStepRequest: Hashable, Sendable {
    var direction: GamepadScrollDirection
    var revision: Int
}
