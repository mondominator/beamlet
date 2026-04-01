import SwiftUI

struct SendSuccessOverlay: View {
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var checkmarkTrim: CGFloat = 0
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        let angle: Double
        let speed: CGFloat
        let size: CGFloat
        let color: Color
    }

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.3 * opacity)
                .ignoresSafeArea()

            // Particles
            GeometryReader { geo in
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(
                            x: geo.size.width / 2 + particle.x,
                            y: geo.size.height / 2 + particle.y
                        )
                        .opacity(opacity)
                }
            }

            // Success circle + checkmark
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.5), radius: 20)

                // Checkmark
                Path { path in
                    path.move(to: CGPoint(x: -15, y: 0))
                    path.addLine(to: CGPoint(x: -3, y: 12))
                    path.addLine(to: CGPoint(x: 18, y: -12))
                }
                .trim(from: 0, to: checkmarkTrim)
                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 30)

                Text("Sent!")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(y: 65)
                    .opacity(checkmarkTrim > 0.5 ? 1 : 0)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            generateParticles()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                checkmarkTrim = 1.0
            }
            animateParticles()
        }
    }

    private func generateParticles() {
        let colors: [Color] = [
            Color(red: 0.55, green: 0.36, blue: 0.96),
            Color(red: 0.23, green: 0.51, blue: 0.96),
            Color(red: 0.02, green: 0.71, blue: 0.83),
            .white
        ]
        particles = (0..<20).map { i in
            let angle = Double(i) / 20.0 * .pi * 2
            return Particle(
                x: 0,
                y: 0,
                angle: angle,
                speed: CGFloat.random(in: 80...200),
                size: CGFloat.random(in: 4...10),
                color: colors.randomElement() ?? .white
            )
        }
    }

    private func animateParticles() {
        withAnimation(.easeOut(duration: 0.8)) {
            for i in particles.indices {
                let p = particles[i]
                particles[i].x += cos(p.angle) * p.speed
                particles[i].y += sin(p.angle) * p.speed
            }
        }
    }
}
