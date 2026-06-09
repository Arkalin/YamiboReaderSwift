import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct ReaderWebJumpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onJump: (Int) -> Void

    @ObservedObject var model: ReaderContainerModel

    init(model: ReaderContainerModel, onJump: @escaping (Int) -> Void) {
        self.model = model
        self.onJump = onJump
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        HStack {
                            Text(L10n.string("reader.current_web_page"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.currentWebViewText)
                                .fontWeight(.semibold)
                        }
                    }

                    Section(L10n.string("reader.select_web_page")) {
                        ForEach(1 ... model.maxView, id: \.self) { view in
                            Button {
                                jump(to: view)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: view == model.visibleView ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(view == model.visibleView ? Color.accentColor : Color.secondary)

                                    Text(L10n.string("reader.page_number_spaced", view))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if view == model.visibleView {
                                        Text(L10n.string("common.current"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .id(view)
                        }
                    }
                }
                .navigationTitle(L10n.string("reader.jump_web_page"))
                .onAppear {
                    scrollToCurrentView(using: proxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    scrollToCurrentView(using: proxy)
                }
            }
        }
    }

    private func jump(to view: Int) {
        onJump(view)
        dismiss()
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleView - 3, 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}
#endif
