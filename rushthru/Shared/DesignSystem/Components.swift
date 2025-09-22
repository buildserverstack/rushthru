import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, isCompact ? 8 : 12)
            .padding(.horizontal, isCompact ? 12 : 16)
            .frame(maxWidth: .infinity)
            .background(background(for: configuration))
            .foregroundStyle(Color.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: DesignTokens.Motion.fast), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radii.md))
    }

    private func background(for configuration: Configuration) -> some View {
        LinearGradient(
            colors: [DesignTokens.Colors.primary, DesignTokens.Colors.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(configuration.isPressed ? 0.85 : 1)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radii.md, style: .continuous))
        .shadow(
            color: DesignTokens.Shadow.card,
            radius: configuration.isPressed ? 6 : 10,
            x: 0,
            y: configuration.isPressed ? 2 : 6
        )
    }
}

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radii.lg, style: .continuous)
                    .fill(DesignTokens.Colors.surface)
                    .shadow(color: DesignTokens.Shadow.card, radius: 16, x: 0, y: 10)
            )
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
    }
}

struct PillBadge: View {
    enum Style {
        case info
        case warning
        case success
    }

    let text: String
    var style: Style = .info

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.18))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .info:
            return DesignTokens.Colors.primary
        case .warning:
            return DesignTokens.Colors.warning
        case .success:
            return DesignTokens.Colors.success
        }
    }
}

struct SkeletonView: View {
    var cornerRadius: CGFloat = DesignTokens.Radii.md

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(DesignTokens.Colors.elevatedSurface)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        DesignTokens.Colors.elevatedSurface.opacity(0.6),
                        Color.white.opacity(0.45),
                        DesignTokens.Colors.elevatedSurface.opacity(0.6)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white)
                        .phaseOffset(phase)
                )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

private extension Shape {
    func phaseOffset(_ phase: CGFloat) -> some View {
        self
            .offset(x: phase * 120)
    }
}
