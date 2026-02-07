import SwiftUI

// MARK: - Card Modifier

struct PedefCardModifier: ViewModifier {
    var isHovering: Bool = false
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: PedefTheme.Radius.lg)
                    .fill(isSelected
                        ? PedefTheme.Brand.indigo.opacity(0.08)
                        : (isHovering ? PedefTheme.Surface.hover : Color.clear))
                    .shadow(
                        color: PedefTheme.Shadow.card.color,
                        radius: isHovering ? PedefTheme.Shadow.md.radius : PedefTheme.Shadow.card.radius,
                        x: PedefTheme.Shadow.card.x,
                        y: isHovering ? PedefTheme.Shadow.md.y : PedefTheme.Shadow.card.y
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: PedefTheme.Radius.lg)
                    .strokeBorder(isSelected ? PedefTheme.Brand.indigo : Color.clear, lineWidth: 2)
            }
    }
}

// MARK: - Sidebar Row Modifier

struct PedefSidebarRowModifier: ViewModifier {
    var isSelected: Bool = false
    var isHovering: Bool = false

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                    .fill(isSelected
                        ? PedefTheme.Brand.indigo.opacity(0.15)
                        : (isHovering ? PedefTheme.Surface.hover : Color.clear))
            )
    }
}

// MARK: - Bar Modifier

struct PedefBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(PedefTheme.Surface.bar)
    }
}

// MARK: - Toolbar Icon Button Style

/// A custom button style for toolbar-style icon buttons with brand hover/press states.
struct PedefToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? PedefTheme.Brand.indigo : PedefTheme.TextColor.secondary)
            .padding(PedefTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                    .fill(configuration.isPressed
                        ? PedefTheme.Brand.indigo.opacity(0.12)
                        : (isActive ? PedefTheme.Brand.indigo.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Branded Segmented Picker Style

/// A custom segmented control with brand-styled selection indicator.
struct PedefSegmentedPicker<SelectionValue: Hashable>: View {
    @Binding var selection: SelectionValue
    let items: [(value: SelectionValue, icon: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    withAnimation(PedefTheme.Animation.quick) {
                        selection = item.value
                    }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == item.value ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                                .fill(selection == item.value ? PedefTheme.Brand.indigo.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
    }
}

// MARK: - Custom Search Field

struct PedefSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(PedefTheme.Typography.callout)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.sm)
        .padding(.vertical, PedefTheme.Spacing.xs)
        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                .stroke(isFocused ? PedefTheme.Brand.indigo.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - View Extensions

extension View {
    func pedefCard(isHovering: Bool = false, isSelected: Bool = false) -> some View {
        modifier(PedefCardModifier(isHovering: isHovering, isSelected: isSelected))
    }

    func pedefSidebarRow(isSelected: Bool = false, isHovering: Bool = false) -> some View {
        modifier(PedefSidebarRowModifier(isSelected: isSelected, isHovering: isHovering))
    }

    func pedefBar() -> some View {
        modifier(PedefBarModifier())
    }

    func pedefShadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
