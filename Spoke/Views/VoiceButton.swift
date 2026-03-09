import SwiftUI

enum VoiceButtonState {
    case idle
    case recording
    case processing
}

struct VoiceButton: View {
    let state: VoiceButtonState
    let onStart: () -> Void
    /// Called when the gesture ends. `elapsed` is how long the button was held.
    /// < 0.3 s = tap gesture; ≥ 0.3 s = hold gesture.
    let onRelease: (_ elapsed: TimeInterval) -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    @State private var pressStart: Date?

    var body: some View {
        ZStack {
            if state == .recording {
                PulseRing(color: coral)
            }

            Circle()
                .fill(coral)
                .frame(width: 72, height: 72)
                .overlay {
                    if state == .processing {
                        SpinnerArc()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(state == .recording ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state)
        }
        .shadow(color: coral.opacity(0.4), radius: 12, x: 0, y: 4)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard pressStart == nil else { return }
                    pressStart = .now
                    onStart()
                }
                .onEnded { _ in
                    let elapsed = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
                    pressStart = nil
                    onRelease(elapsed)
                }
        )
        .disabled(state == .processing)
    }
}

private struct PulseRing: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 80, height: 80)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    scale = 1.6
                    opacity = 0
                }
            }
    }
}

private struct SpinnerArc: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
