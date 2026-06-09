import SwiftUI
import YamiboReaderCore

struct FavoriteAppearanceColorSelectorRow: View {
    let category: FavoriteAppearanceCategory
    let selectedColor: FavoriteAppearanceColor
    let isBusy: Bool
    let onSelectColor: (FavoriteAppearanceColor) -> Void

    @Binding var activeCategory: FavoriteAppearanceCategory?

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    activeCategory = activeCategory == category ? nil : category
                }
            } label: {
                HStack(spacing: 10) {
                    Text(category.title)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    FavoriteAppearanceColorSwatch(color: selectedColor)

                    Text(selectedColor.title)
                        .foregroundStyle(.secondary)

                    Image(systemName: activeCategory == category ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            if activeCategory == category {
                FavoriteAppearanceColorPalette(
                    category: category,
                    selectedColor: selectedColor,
                    isBusy: isBusy,
                    onSelectColor: selectColor
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .padding(.vertical, 6)
    }

    private func selectColor(_ color: FavoriteAppearanceColor) {
        onSelectColor(color)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.95)) {
            activeCategory = nil
        }
    }
}

private struct FavoriteAppearanceColorPalette: View {
    let category: FavoriteAppearanceCategory
    let selectedColor: FavoriteAppearanceColor
    let isBusy: Bool
    let onSelectColor: (FavoriteAppearanceColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 12), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(FavoriteAppearanceColor.allCases, id: \.self) { color in
                Button {
                    onSelectColor(color)
                } label: {
                    FavoriteAppearanceColorChoiceSwatch(
                        color: color,
                        isSelected: selectedColor == color
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("\(category.title)\(color.title)")
                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.09))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }

                BubbleArrow()
                    .fill(Color.secondary.opacity(0.09))
                    .frame(width: 18, height: 10)
                    .offset(x: -28, y: -9)
            }
        }
        .padding(.top, 2)
    }
}

private struct FavoriteAppearanceColorSwatch: View {
    let color: FavoriteAppearanceColor

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: 14, height: 14)
            .overlay {
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct FavoriteAppearanceColorChoiceSwatch: View {
    let color: FavoriteAppearanceColor
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 28, height: 28)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .overlay {
            Circle()
                .strokeBorder(
                    isSelected ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.25),
                    lineWidth: isSelected ? 2 : 0.75
                )
        }
        .contentShape(Circle())
    }
}

private struct BubbleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
