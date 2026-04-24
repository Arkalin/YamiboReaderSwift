import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaBottomChrome: View {
    @ObservedObject var model: MangaReaderModel
    let bottomInset: CGFloat
    let sliderValue: Double
    let isEditingSlider: Bool
    let onSliderValueChange: (Double) -> Void
    let onSliderEditingChanged: (Bool) -> Void
    let onShowSettings: () -> Void
    let onShowDirectory: () -> Void
    let onJumpChapter: (Int) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onShowDirectory) {
                    Label(L10n.string("manga.directory"), systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
                .disabled(model.isTransitioningChapter)

                Spacer(minLength: 0)

                Button(action: onShowSettings) {
                    Label(L10n.string("settings.title"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 10) {
                Text(progressLabelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ReaderChromeIconButton(systemName: "backward.end.fill", title: L10n.string("reader.previous_chapter")) {
                        onJumpChapter(-1)
                    }
                    .disabled(!model.hasPreviousChapter || model.isTransitioningChapter)

                    if model.sliderHasAvailableRange {
                        Slider(
                            value: Binding(
                                get: { sliderValue },
                                set: onSliderValueChange
                            ),
                            in: model.sliderRange,
                            step: 1
                        ) { editing in
                            onSliderEditingChanged(editing)
                        }
                        .tint(.white)
                        .disabled(model.isTransitioningChapter)
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: 24, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }

                    ReaderChromeIconButton(systemName: "forward.end.fill", title: L10n.string("reader.next_chapter")) {
                        onJumpChapter(1)
                    }
                    .disabled(!model.hasNextChapter || model.isTransitioningChapter)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, max(bottomInset, 12))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private var progressLabelText: String {
        if isEditingSlider {
            return model.previewLabel(forLocalIndex: Int(sliderValue.rounded()))
        }
        return model.progressLabelText
    }
}

struct MangaChapterPreviewBubble: View {
    let title: String

    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
