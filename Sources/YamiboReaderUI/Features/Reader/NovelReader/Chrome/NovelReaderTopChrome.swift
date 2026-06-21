import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct NovelReaderTopChrome: View {
    private let pagedChapterTitleTopLift: CGFloat = 12

    let model: ReaderContainerModel
    let topInset: CGFloat
    let onClose: () -> Void
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: model.currentChapterTitle,
            progressText: model.progressText
        )

        ReaderGlassContainer(spacing: 12) {
            let closeButtonSize: CGFloat = 44

            ZStack {
                chapterTitleView(summary.chapterTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, closeButtonSize + 16)
                    .offset(y: shouldLiftPagedChapterTitle ? -pagedChapterTitleTopLift : 0)

                HStack {
                    Spacer(minLength: 0)
                    ReaderChromeCircleButton(
                        systemName: "xmark",
                        title: L10n.string("common.close"),
                        tint: readerChromeButtonTint(for: colorScheme),
                        action: onClose
                    )
                    .frame(width: closeButtonSize, height: closeButtonSize)
                }
            }
            .frame(maxWidth: .infinity, minHeight: closeButtonSize)
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
