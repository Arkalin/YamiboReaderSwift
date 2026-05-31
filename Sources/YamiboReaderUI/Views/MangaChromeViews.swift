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
    let onShowComments: () -> Void
    let onJumpChapter: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReaderGlassContainer(spacing: 12) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Button(action: onShowDirectory) {
                        Label(L10n.string("manga.directory"), systemImage: "list.bullet")
                    }
                    .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
                    .disabled(model.isTransitioningChapter)

                    Spacer(minLength: 0)

                    Button(action: onShowComments) {
                        Label(L10n.string("reader.comments"), systemImage: "text.bubble")
                    }
                    .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
                    .disabled(model.isTransitioningChapter)

                    Spacer(minLength: 0)

                    Button(action: onShowSettings) {
                        Label(L10n.string("settings.title"), systemImage: "gearshape")
                    }
                    .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
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
            .padding(.vertical, 12)
            .readerChromePanel(tint: readerChromePanelTint(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, max(bottomInset, 12))
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
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .readerChromePanel(cornerRadius: 18, tint: Color.accentColor.opacity(0.08))
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
