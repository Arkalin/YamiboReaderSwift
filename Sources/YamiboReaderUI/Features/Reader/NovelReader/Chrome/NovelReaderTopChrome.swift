import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct NovelReaderTopChrome: View {
    private let pagedChapterTitleTopLift: CGFloat = 12

    let model: ReaderContainerModel
    let topInset: CGFloat
    let onNavigateBack: () -> Void
    let onNavigateForward: () -> Void
    let onClose: () -> Void
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: model.currentChapterTitle,
            progressText: model.progressText
        )

        ReaderGlassContainer(spacing: 12) {
            let chromeButtonSize: CGFloat = 44
            let historyButtonsUseGlassBackground = model.settings.readingMode == .vertical
            let historyIconSize = ReaderChromeHistoryButton.controlSize(
                isGlassBacked: historyButtonsUseGlassBackground
            )
            let buttonSpacing: CGFloat = 8
            let leadingControlsWidth = model.canNavigateBack ? historyIconSize : 0
            let trailingControlsWidth = chromeButtonSize
                + (model.canNavigateForward ? historyIconSize + buttonSpacing : 0)
            let titleSidePadding = max(leadingControlsWidth, trailingControlsWidth) + 16

            ZStack {
                chapterTitleView(summary.chapterTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, titleSidePadding)
                    .offset(y: shouldLiftPagedChapterTitle ? -pagedChapterTitleTopLift : 0)

                HStack(spacing: buttonSpacing) {
                    if model.canNavigateBack {
                        ReaderChromeHistoryButton(
                            direction: .back,
                            title: L10n.string("common.back"),
                            isGlassBacked: historyButtonsUseGlassBackground,
                            action: onNavigateBack
                        )
                    }

                    Spacer(minLength: 0)

                    if model.canNavigateForward {
                        ReaderChromeHistoryButton(
                            direction: .forward,
                            title: L10n.string("common.forward"),
                            isGlassBacked: historyButtonsUseGlassBackground,
                            action: onNavigateForward
                        )
                    }

                    ReaderChromeCircleButton(
                        systemName: "xmark",
                        title: L10n.string("common.close"),
                        tint: readerChromeButtonTint(for: colorScheme),
                        action: onClose
                    )
                    .frame(width: chromeButtonSize, height: chromeButtonSize)
                }
            }
            .frame(maxWidth: .infinity, minHeight: chromeButtonSize)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .tint(readerChromeButtonTint(for: colorScheme))
    }

    @ViewBuilder
    private func chapterTitleView(_ title: String) -> some View {
        let text = Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.primary)

        if model.settings.readingMode == .vertical {
            text
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))
        } else {
            text
                .frame(maxWidth: .infinity)
        }
    }

    private var shouldLiftPagedChapterTitle: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && model.settings.readingMode == .paged
#else
        false
#endif
    }
}
#endif
