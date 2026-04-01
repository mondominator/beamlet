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
            // Outer pulse rings — big, bold, visible
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 3)
                .frame(width: size + pulse1, height: size + pulse1)
                .opacity(1 - Double(pulse1 / 50))

            Circle()
                .stroke(color.opacity(0.35), lineWidth: 2.5)
                .frame(width: size + pulse2, height: size + pulse2)
                .opacity(1 - Double(pulse2 / 60))

            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
                .frame(width: size + pulse3, height: size + pulse3)
                .opacity(1 - Double(pulse3 / 70))

            // Glow halo
            Circle()
                .fill(color.opacity(glowOpacity * 0.25))
                .frame(width: size + 16, height: size + 16)
                .blur(radius: 8)

            // Main avatar
            if isSelected {
                Circle()
                    .fill(color.opacity(0.25))
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
                            .stroke(color, lineWidth: 2.5)
                    )
                    .shadow(color: color.opacity(0.4), radius: 6)
            }
        }
        .frame(width: size + 72, height: size + 72)
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulse1 = 50
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(0.6)) {
                pulse2 = 60
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(1.2)) {
                pulse3 = 70
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                glowOpacity = 1.0
            }
        }
    }
}
