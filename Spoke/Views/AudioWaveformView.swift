import SwiftUI

struct AudioWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    private let barCount = 24
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 28
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    @State private var levels: [Float] = []
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(coral.opacity(0.7))
                    .frame(width: barWidth, height: barHeight(for: i))
                    .animation(
                        .spring(response: 0.15, dampingFraction: 0.7),
                        value: levels
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.92))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.26),
                                .init(color: .black, location: 0.74),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
            }
        }
        .frame(height: maxHeight + 16)
        .onAppear {
            levels = Array(repeating: 0, count: barCount)
        }
        .onChange(of: isActive) { _, active in
            if active {
                startPolling()
            } else {
                stopPolling()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    levels = Array(repeating: 0, count: barCount)
                }
            }
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in
                guard isActive else { return }
                // Add slight variation so bars feel organic
                let jitter = Float.random(in: -0.08...0.08)
                let level = max(0, min(1, audioLevel + jitter))
                var updated = levels
                if updated.count >= barCount {
                    updated.removeFirst()
                }
                updated.append(level)
                levels = updated
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < levels.count else { return minHeight }
        let level = CGFloat(levels[index])
        return minHeight + level * (maxHeight - minHeight)
    }
}
