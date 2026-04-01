import SwiftUI

struct SendSuccessOverlay: View {
    @State private var planeOffset: CGSize = .zero
    @State private var planeScale: CGFloat = 1.0
    @State private var planeOpacity: Double = 0
    @State private var planeRotation: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dimOpacity: Double = 0
    @State private var trails: [Trail] = []

    struct Trail: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var opacity: Double
        var size: CGFloat
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25 * dimOpacity)
                .ignoresSafeArea()

            // Expanding ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.6),
                            Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )
                .frame(width: 120, height: 120)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Trail particles
            GeometryReader { geo in
                ForEach(trails) { trail in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: trail.size, height: trail.size)
                        .position(
                            x: geo.size.width / 2 + trail.x,
                            y: geo.size.height / 2 + trail.y
                        )
                        .opacity(trail.opacity)
                }
            }

            // Paper plane
            Image(systemName: "paperplane.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.5), radius: 12)
                .rotationEffect(.degrees(planeRotation))
                .scaleEffect(planeScale)
                .offset(planeOffset)
                .opacity(planeOpacity)

            // "Sent!" text
            Text("Sent!")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .opacity(textOpacity)
                .offset(y: 20)
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // Phase 1: Plane appears at center with a pop
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            planeOpacity = 1
            dimOpacity = 1
            planeScale = 1.2
        }

        // Phase 2: Plane settles, ring expands
        withAnimation(.easeOut(duration: 0.2).delay(0.2)) {
            planeScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            ringScale = 2.5
            ringOpacity = 0.8
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            ringOpacity = 0
        }

        // Phase 3: Plane tilts and flies up-right, leaving trail
        generateTrails()

        withAnimation(.easeIn(duration: 0.5).delay(0.5)) {
            planeRotation = -30
            planeOffset = CGSize(width: 150, height: -300)
            planeScale = 0.4
        }
        withAnimation(.easeIn(duration: 0.3).delay(0.8)) {
            planeOpacity = 0
        }

        // Phase 4: Show "Sent!" text
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.7)) {
            textOpacity = 1
        }

        // Animate trails
        withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
            for i in trails.indices {
                trails[i].opacity = 0
            }
        }
    }

    private func generateTrails() {
        trails = (0..<8).map { i in
            let progress = CGFloat(i) / 8.0
            return Trail(
                x: progress * 80 - 20,
                y: progress * -140 + 20,
                opacity: Double(1.0 - progress * 0.5),
                size: CGFloat.random(in: 4...8)
            )
        }
    }
}
