import SwiftUI

struct PulsingAvatarView: View {
    let name: String
    let isContact: Bool
    let isSelected: Bool
    var size: CGFloat = 44

    @State private var pulse1: CGFloat = 0
    @State private var pulse2: CGFloat = 0
    @State private var pulse3: CGFloat = 0
    @State private var glowOpacity: Double = 0.4

    private var color: Color {
        if isSelected { return .blue }
        return isContact ? .blue : .teal
    }

    var body: some View {
        ZStack {
            // Outer pulse rings
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 1.5)
                .frame(width: size + pulse1, height: size + pulse1)
                .opacity(1 - Double(pulse1 / 30))

            Circle()
                .stroke(color.opacity(0.1), lineWidth: 1)
                .frame(width: size + pulse2, height: size + pulse2)
                .opacity(1 - Double(pulse2 / 36))

            Circle()
                .stroke(color.opacity(0.06), lineWidth: 0.8)
                .frame(width: size + pulse3, height: size + pulse3)
                .opacity(1 - Double(pulse3 / 42))

            // Glow
            Circle()
                .fill(color.opacity(glowOpacity * 0.15))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: 4)

            // Main avatar
            if isSelected {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.35, weight: .bold))
                            .foregroundStyle(color)
                    )
            } else {
                AvatarView(name: name, size: size)
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.3), lineWidth: 2)
                    )
            }
        }
        .frame(width: size + 44, height: size + 44)
        .onAppear {
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
                pulse1 = 30
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.8)) {
                pulse2 = 36
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(1.6)) {
                pulse3 = 42
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever()) {
                glowOpacity = 0.8
            }
        }
    }
}
