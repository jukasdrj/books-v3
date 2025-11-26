import SwiftUI

/// Celebratory success animation with confetti particles and points award
/// Shown after user completes progressive profiling questions
@available(iOS 26.0, *)
public struct CelebrationView: View {
    let pointsAwarded: Int
    let completionPercentage: Double
    
    @State private var showCheckmark = false
    @State private var showPoints = false
    @State private var showCompletion = false
    @State private var particles: [ConfettiParticle] = []
    @State private var screenWidth: CGFloat = 400
    @State private var screenHeight: CGFloat = 800
    
    public init(pointsAwarded: Int, completionPercentage: Double) {
        self.pointsAwarded = pointsAwarded
        self.completionPercentage = completionPercentage
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Confetti particles layer
                ForEach(particles) { particle in
                    ConfettiParticleView(particle: particle, screenHeight: screenHeight)
                }
                
                // Main content
                VStack(spacing: 24) {
                    // Success checkmark
                    if showCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Points award badge
                    if showPoints {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundColor(.yellow)
                            Text("+\(pointsAwarded) Curator Points")
                                .font(.headline.bold())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Completion percentage update
                    if showCompletion {
                        VStack(spacing: 8) {
                            Text("Diversity Data Completion")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            // Progress bar
                            GeometryReader { progressGeometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    // Progress fill
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [
                                                Color(red: 0.42, green: 0.39, blue: 1.00),
                                                Color(red: 0.00, green: 0.82, blue: 1.00)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: progressGeometry.size.width * completionPercentage / 100, height: 8)
                                        .animation(.easeInOut(duration: 1.0), value: completionPercentage)
                                }
                            }
                            .frame(height: 8)
                            
                            Text("\(Int(completionPercentage))% Complete")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .onAppear {
                screenWidth = geometry.size.width
                screenHeight = geometry.size.height
                startCelebrationAnimation()
            }
        }
    }
    
    // MARK: - Animation Sequence
    
    private func startCelebrationAnimation() {
        // Generate confetti particles
        particles = (0..<30).map { _ in
            ConfettiParticle(
                x: .random(in: 0...screenWidth),
                y: -20,
                color: [.red, .blue, .green, .yellow, .purple, .orange].randomElement()!,
                rotation: .random(in: 0...360)
            )
        }
        
        // Sequence the animations
        withAnimation(.spring(duration: 0.5)) {
            showCheckmark = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.5)) {
                showPoints = true
            }
            
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.5)) {
                showCompletion = true
            }
        }
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let color: Color
    let rotation: Double
}

private struct ConfettiParticleView: View {
    let particle: ConfettiParticle
    let screenHeight: CGFloat
    
    @State private var yOffset: Double = 0
    @State private var xOffset: Double = 0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(particle.rotation))
            .position(x: particle.x + xOffset, y: particle.y + yOffset)
            .opacity(opacity)
            .onAppear {
                // Animate particles falling down
                withAnimation(.easeInOut(duration: 2.0)) {
                    yOffset = screenHeight + 50
                    xOffset = .random(in: -50...50)
                    opacity = 0
                }
            }
    }
}

// MARK: - Preview

#Preview {
    CelebrationView(pointsAwarded: 25, completionPercentage: 67.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
}
