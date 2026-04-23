import Foundation

enum ReaderChromeMode: Equatable {
    case loading
    case error
    case visible
    case immersiveHidden

    var showsChrome: Bool {
        self != .immersiveHidden
    }
}

struct ReaderChromeState: Equatable {
    private(set) var mode: ReaderChromeMode = .loading
    private(set) var hasCompletedInitialAutoHide = false
    private(set) var overlayRestoreMode: ReaderChromeMode?

    mutating func update(
        isLoading: Bool,
        errorMessage: String?,
        hasPages: Bool,
        hasPresentedOverlay: Bool
    ) {
        if hasPresentedOverlay {
            if overlayRestoreMode == nil {
                overlayRestoreMode = mode
            }
            mode = .visible
            return
        }

        if let overlayRestoreMode {
            mode = overlayRestoreMode
            self.overlayRestoreMode = nil
        }

        if isLoading && !hasPages {
            hasCompletedInitialAutoHide = false
            mode = .loading
            return
        }

        if errorMessage != nil && !hasPages {
            hasCompletedInitialAutoHide = false
            mode = .error
            return
        }

        guard hasPages else {
            hasCompletedInitialAutoHide = false
            return
        }

        guard !hasCompletedInitialAutoHide else { return }
        hasCompletedInitialAutoHide = true
        mode = .immersiveHidden
    }

    mutating func toggleChrome() {
        mode = mode == .immersiveHidden ? .visible : .immersiveHidden
    }

    mutating func showChrome() {
        mode = .visible
    }
}
