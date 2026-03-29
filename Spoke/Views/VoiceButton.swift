import SwiftUI

enum VoiceButtonState {
    case idle
    case recording
    case processing
}

struct VoiceButton: View {
    let state: VoiceButtonState
    let audioLevel: Float
    let onStart: () -> Void
    /// Called when the gesture ends. `elapsed` is how long the button was held.
    /// < 0.3 s = tap gesture; ≥ 0.3 s = hold gesture.
    let onRelease: (_ elapsed: TimeInterval) -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    @State private var pressStart: Date?
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.15

    var body: some View {
        HStack(spacing: 8) {
            // Left waveform (newest bars near center, flows outward)
            AudioWaveformView(audioLevel: audioLevel, isActive: state == .recording)
                .opacity(state == .recording ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state)

            // Center button
            ZStack {
                if state == .recording {
                    Circle()
                        .fill(coral.opacity(pulseOpacity))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.1)
                                .repeatForever(autoreverses: true)
                            ) {
                                pulseScale = 1.17
                                pulseOpacity = 0.07
                            }
                        }
                        .onDisappear {
                            pulseScale = 1.0
                            pulseOpacity = 0.15
                        }
                }

                Circle()
                    .fill(coral)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Group {
                            if state == .processing {
                                SpinnerArc()
                                    .frame(width: 24, height: 24)
                            } else if state == .recording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .contentTransition(.opacity)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: state)
                    }
                    .scaleEffect(state == .recording ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state)
            }

            // Right waveform (mirrored so newest bars are near center, flows outward)
            AudioWaveformView(audioLevel: audioLevel, isActive: state == .recording)
                .scaleEffect(x: -1, y: 1)
                .opacity(state == .recording ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state)
        }
        .shadow(color: coral.opacity(state == .recording ? 0.5 : 0.4),
                radius: state == .recording ? 16 : 12, x: 0, y: 4)
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
