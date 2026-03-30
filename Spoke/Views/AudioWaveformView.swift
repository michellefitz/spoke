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

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(coral.opacity(0.7))
                    .frame(width: barWidth, height: barHeight(for: i))
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.65),
                        value: levels
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.92))
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
            if !active {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    levels = Array(repeating: 0, count: barCount)
                }
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            guard isActive else { return }
            // Multiplicative jitter: silence stays silent, loud speech has natural variation
            let jitter = Float.random(in: 0.82...1.18)
            let level = min(newLevel * jitter, 1.0)
            var updated = levels.isEmpty ? Array(repeating: Float(0), count: barCount) : levels
            if updated.count >= barCount { updated.removeFirst() }
            updated.append(level)
            levels = updated
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < levels.count else { return minHeight }
        let level = CGFloat(levels[index])
        return minHeight + level * (maxHeight - minHeight)
    }
}
