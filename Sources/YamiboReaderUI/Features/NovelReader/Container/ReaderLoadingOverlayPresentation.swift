import Foundation

enum ReaderLoadingOverlayReason: Equatable, Sendable {
    case appearanceSettingsApply
    case verticalRestore
    case initialContentLoad
}

struct ReaderLoadingOverlayPresentation: Equatable, Sendable {
    let reason: ReaderLoadingOverlayReason?

    init(
        isLoading: Bool,
        hasSurfaces: Bool,
        hasInitialLoadError: Bool = false,
        isApplyingAppearanceSettings: Bool,
        shouldConcealViewportContent: Bool
    ) {
        if isApplyingAppearanceSettings {
            reason = .appearanceSettingsApply
        } else if shouldConcealViewportContent {
            reason = .verticalRestore
        } else if isLoading && !hasSurfaces && !hasInitialLoadError {
            reason = .initialContentLoad
        } else {
            reason = nil
        }
    }

    var isPresented: Bool {
        reason != nil
    }

    var allowsChrome: Bool {
        !isPresented
    }
}
