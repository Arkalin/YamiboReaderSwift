import SwiftUI
import YamiboReaderCore
import UIKit

struct FavoriteBackgroundEditorDraft: Identifiable {
    let id = UUID()
    var imageData: Data?
    var imageSize: CGSize
    var settings: FavoriteBackgroundSettings

    static func custom(
        imageData: Data,
        settings: FavoriteBackgroundSettings = FavoriteBackgroundSettings(isEnabled: true)
    ) -> FavoriteBackgroundEditorDraft? {
        guard let imageSize = favoriteBackgroundImageSize(from: imageData) else { return nil }
        return FavoriteBackgroundEditorDraft(
            imageData: imageData,
            imageSize: imageSize,
            settings: FavoriteBackgroundSettings(
                isEnabled: true,
                imageID: settings.imageID,
                scale: settings.scale,
                offsetX: settings.offsetX,
                offsetY: settings.offsetY,
                blurRadius: settings.blurRadius
            )
        )
    }

    mutating func replaceImage(with data: Data) -> Bool {
        guard let newSize = favoriteBackgroundImageSize(from: data) else { return false }
        let currentBlurRadius = settings.blurRadius
        imageData = data
        imageSize = newSize
        settings = FavoriteBackgroundSettings(
            isEnabled: true,
            scale: 1,
            offsetX: 0,
            offsetY: 0,
            blurRadius: currentBlurRadius
        )
        return true
    }

    mutating func restoreDefault() {
        imageData = nil
        imageSize = .zero
        settings = FavoriteBackgroundSettings()
    }
}

struct FavoriteBackgroundLayer: View {
    let settings: FavoriteBackgroundSettings
    let imageData: Data?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if settings.isEnabled,
               let imageData,
               let imageSize = favoriteBackgroundImageSize(from: imageData) {
                ZStack {
                    FavoriteBackgroundImage(data: imageData)
                        .frame(
                            width: renderedFrame(imageSize: imageSize, containerSize: geometry.size).size.width,
                            height: renderedFrame(imageSize: imageSize, containerSize: geometry.size).size.height
                        )
                        .offset(renderedFrame(imageSize: imageSize, containerSize: geometry.size).offset)
                        .blur(radius: settings.blurRadius)
                        .clipped()

                    readabilityOverlay
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    private var readabilityOverlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.28)
    }

    private func renderedFrame(imageSize: CGSize, containerSize: CGSize) -> FavoriteBackgroundRenderedFrame {
        FavoriteBackgroundLayout.renderedFrame(
            imageSize: imageSize,
            containerSize: containerSize,
            settings: settings
        )
    }
}

struct FavoriteBackgroundEditorView: View {
    @Binding var draft: FavoriteBackgroundEditorDraft

    let onCancel: () -> Void
    let onChangeImage: () -> Void
    let onApply: (FavoriteBackgroundEditorDraft) async -> Bool

    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification = 1.0
    @State private var isApplying = false

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)

            ZStack {
                GeometryReader { geometry in
                    ZStack {
                        editorBackground

                        if let imageData = draft.imageData {
                            editableImage(data: imageData, containerSize: geometry.size)
                        }

                        bottomControls
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(editorBackground)
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                FavoriteBackgroundEditorTopBar(
                    draft: $draft,
                    isApplying: isApplying,
                    onCancel: onCancel,
                    onApply: applyCurrentDraft
                )
                .padding(.horizontal, 16)
                .padding(.top, max(topInset + 8, 20))
                .padding(.bottom, 8)
            }
        }
    }

    private var windowSafeAreaInsets: EdgeInsets {
        guard let insets = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets
        else {
            return EdgeInsets()
        }
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    private var editorBackground: some View {
        ZStack {
            YamiboColors.SystemSurface.background

            if draft.imageData == nil {
                Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.08)
            }
        }
        .ignoresSafeArea()
    }

    private func editableImage(data: Data, containerSize: CGSize) -> some View {
        let frame = currentRenderedFrame(containerSize: containerSize)

        return FavoriteBackgroundImage(data: data)
            .frame(width: frame.size.width, height: frame.size.height)
            .offset(frame.offset)
            .blur(radius: draft.settings.blurRadius)
            .clipped()
            .frame(width: containerSize.width, height: containerSize.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(containerSize: containerSize))
            .simultaneousGesture(magnificationGesture(containerSize: containerSize))
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Spacer()

            FavoriteBackgroundEditorBottomControls(
                blurRadius: Binding(
                    get: { draft.settings.blurRadius },
                    set: { draft.settings.blurRadius = FavoriteBackgroundSettings.clampBlurRadius($0.rounded()) }
                ),
                isApplying: isApplying,
                onChangeImage: onChangeImage
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 72)
        }
    }

    private func applyCurrentDraft() {
        Task {
            isApplying = true
            let didApply = await onApply(draft)
            if !didApply {
                isApplying = false
            }
        }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                guard draft.imageSize != .zero else { return }
                let proposedOffset = clampedOffset(
                    baseOffset(containerSize: containerSize) + value.translation,
                    containerSize: containerSize,
                    scale: draft.settings.scale
                )
                let offsets = FavoriteBackgroundLayout.normalizedOffsets(
                    imageSize: draft.imageSize,
                    containerSize: containerSize,
                    scale: draft.settings.scale,
                    proposedOffset: proposedOffset
                )
                draft.settings.offsetX = offsets.offsetX
                draft.settings.offsetY = offsets.offsetY
            }
    }

    private func magnificationGesture(containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                draft.settings.scale = FavoriteBackgroundSettings.clampScale(draft.settings.scale * value)
                let offsets = FavoriteBackgroundLayout.normalizedOffsets(
                    imageSize: draft.imageSize,
                    containerSize: containerSize,
                    scale: draft.settings.scale,
                    proposedOffset: baseOffset(containerSize: containerSize)
                )
                draft.settings.offsetX = offsets.offsetX
                draft.settings.offsetY = offsets.offsetY
            }
    }

    private func currentRenderedFrame(containerSize: CGSize) -> FavoriteBackgroundRenderedFrame {
        let currentSettings = FavoriteBackgroundSettings(
            isEnabled: draft.settings.isEnabled,
            imageID: draft.settings.imageID,
            scale: draft.settings.scale * magnification,
            offsetX: draft.settings.offsetX,
            offsetY: draft.settings.offsetY,
            blurRadius: draft.settings.blurRadius
        )
        let baseFrame = FavoriteBackgroundLayout.renderedFrame(
            imageSize: draft.imageSize,
            containerSize: containerSize,
            settings: currentSettings
        )
        let offset = clampedOffset(
            baseFrame.offset + dragTranslation,
            containerSize: containerSize,
            scale: currentSettings.scale
        )
        return FavoriteBackgroundRenderedFrame(size: baseFrame.size, offset: offset)
    }

    private func baseOffset(containerSize: CGSize) -> CGSize {
        FavoriteBackgroundLayout.renderedFrame(
            imageSize: draft.imageSize,
            containerSize: containerSize,
            settings: draft.settings
        ).offset
    }

    private func clampedOffset(
        _ offset: CGSize,
        containerSize: CGSize,
        scale: Double
    ) -> CGSize {
        let frame = FavoriteBackgroundLayout.renderedFrame(
            imageSize: draft.imageSize,
            containerSize: containerSize,
            settings: FavoriteBackgroundSettings(scale: scale)
        )
        let overflowX = max(0, (frame.size.width - containerSize.width) / 2)
        let overflowY = max(0, (frame.size.height - containerSize.height) / 2)
        return CGSize(
            width: min(overflowX, max(-overflowX, offset.width)),
            height: min(overflowY, max(-overflowY, offset.height))
        )
    }
}

private struct FavoriteBackgroundImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}

private struct FavoriteBackgroundEditorTopBar: View {
    @Binding var draft: FavoriteBackgroundEditorDraft

    let isApplying: Bool
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                glassContent
            }
        } else {
            fallbackContent
        }
    }

    @ViewBuilder
    @available(iOS 26.0, *)
    private var glassContent: some View {
        #if os(iOS)
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(L10n.string("common.cancel"), action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
                    .disabled(isApplying)

                Button(role: .destructive, action: restoreDefault) {
                    Text(L10n.string("favorite_background.restore_default"))
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .tint(.red)
                .disabled(isApplying)
            }

            Spacer(minLength: 12)

            Button(action: onApply) {
                ApplyButtonLabel(isApplying: isApplying)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
            .disabled(isApplying)
        }
        #endif
    }

    private var fallbackContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(L10n.string("common.cancel"), action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(isApplying)

                Button(role: .destructive, action: restoreDefault) {
                    Text(L10n.string("favorite_background.restore_default"))
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isApplying)
            }

            Spacer(minLength: 12)

            Button(action: onApply) {
                ApplyButtonLabel(isApplying: isApplying)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .disabled(isApplying)
        }
    }

    private func restoreDefault() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            draft.restoreDefault()
        }
    }
}

private struct FavoriteBackgroundEditorBottomControls: View {
    @Binding var blurRadius: Double

    let isApplying: Bool
    let onChangeImage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            FavoriteBackgroundBlurControl(blurRadius: $blurRadius)
                .disabled(isApplying)

            FavoriteBackgroundChangeImageButton(
                isApplying: isApplying,
                action: onChangeImage
            )
        }
    }
}

private struct FavoriteBackgroundBlurControl: View {
    @Binding var blurRadius: Double

    var body: some View {
        blurContent
            .padding(16)
            .frame(maxWidth: 360)
            .surface
    }

    private var blurContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("favorite_background.blur"))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(Int(blurRadius.rounded()))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { blurRadius },
                    set: { blurRadius = FavoriteBackgroundSettings.clampBlurRadius($0.rounded()) }
                ),
                in: FavoriteBackgroundSettings.minimumBlurRadius...FavoriteBackgroundSettings.maximumBlurRadius,
                step: 1
            )
        }
    }
}

private struct FavoriteBackgroundChangeImageButton: View {
    let isApplying: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action, label: label)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glassProminent)
                .disabled(isApplying)
        } else {
            fallbackButton
        }
    }

    private var fallbackButton: some View {
        Button(action: action, label: label)
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .disabled(isApplying)
    }

    private func label() -> some View {
        Label(L10n.string("favorite_background.change_image"), systemImage: "photo.on.rectangle.angled")
            .frame(maxWidth: 260)
    }
}

private struct ApplyButtonLabel: View {
    let isApplying: Bool

    var body: some View {
        if isApplying {
            ProgressView()
                .frame(minWidth: 38)
        } else {
            Text(L10n.string("common.apply"))
                .fontWeight(.semibold)
        }
    }
}

private extension View {
    @ViewBuilder
    var surface: some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            materialSurface
        }
    }

    private var materialSurface: some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private func favoriteBackgroundImageSize(from data: Data) -> CGSize? {
    UIImage(data: data)?.size
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}
