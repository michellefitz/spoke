import SwiftUI

// MARK: - OnboardingView (manages two-screen intro flow)

struct OnboardingView: View {
    @State private var showModeChoice = false

    var body: some View {
        ZStack {
            if showModeChoice {
                ModeChoiceView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            } else {
                SplashIntroView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        showModeChoice = true
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showModeChoice)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Splash intro (typewriter + mic dot + tagline)

private struct SplashIntroView: View {
    let onContinue: () -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let fullWord = "spoke"
    private let dotSize: CGFloat = 16

    @State private var typedCount = 0
    @State private var cursorOpacity: Double = 1
    @State private var showDot = false
    @State private var dotScale: CGFloat = 0
    @State private var taglineOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    private var typedText: String { String(fullWord.prefix(typedCount)) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Wordmark row: typed letters + cursor or pulsing mic dot
            HStack(alignment: .bottom, spacing: 0) {
                Text(typedText)
                    .font(.system(size: 70, weight: .medium))
                    .foregroundStyle(.primary)
                    .kerning(-1.5)
                    .animation(nil, value: typedText)

                if showDot {
                    PulsingMicDot(size: dotSize, coral: coral)
                        .scaleEffect(dotScale)
                        // frame provides room for ripple rings without layout jumps
                        .frame(width: dotSize * 2.4, height: dotSize * 2.4)
                        .offset(x: 3, y: -14)
                } else {
                    // Blinking cursor
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(width: 3, height: 56)
                        .opacity(cursorOpacity)
                        .offset(x: 3, y: -8)
                }
            }

            // Tagline
            Text("Your day, dictated.")
                .font(.system(size: 17))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, 20)
                .opacity(taglineOpacity)

            Spacer()

            // Get started
            Button(action: onContinue) {
                Text("Get started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(coral))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
            .opacity(buttonOpacity)
        }
        .task { await runAnimation() }
        .task { await blinkCursor() }
    }

    @MainActor
    private func runAnimation() async {
        // Initial pause before typing starts
        try? await Task.sleep(for: .milliseconds(700))

        // Type each letter
        for _ in 0..<fullWord.count {
            typedCount += 1
            try? await Task.sleep(for: .milliseconds(115))
        }

        // Brief pause then mic dot springs in
        try? await Task.sleep(for: .milliseconds(100))
        showDot = true
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 14)) {
            dotScale = 1.0
        }

        // Tagline fades in ~1s after dot lands
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.easeOut(duration: 0.6)) { taglineOpacity = 1 }

        // Button fades in after tagline
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeOut(duration: 0.5)) { buttonOpacity = 1 }
    }

    @MainActor
    private func blinkCursor() async {
        var visible = true
        while !showDot {
            try? await Task.sleep(for: .milliseconds(520))
            guard !showDot else { break }
            withAnimation(.easeInOut(duration: 0.1)) {
                cursorOpacity = visible ? 0 : 1
            }
            visible.toggle()
        }
    }
}

// MARK: - Pulsing mic dot (coral circle + mic icon + ripple rings)

private struct PulsingMicDot: View {
    let size: CGFloat
    let coral: Color

    @State private var pulsing = false

    var body: some View {
        ZStack {
            // Ripple ring 1
            Circle()
                .strokeBorder(coral, lineWidth: 1.5)
                .scaleEffect(pulsing ? 2.2 : 1.0)
                .opacity(pulsing ? 0 : 0.4)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulsing
                )

            // Ripple ring 2 (staggered by 0.7s)
            Circle()
                .strokeBorder(coral, lineWidth: 1.5)
                .scaleEffect(pulsing ? 2.2 : 1.0)
                .opacity(pulsing ? 0 : 0.4)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.7),
                    value: pulsing
                )

            // Main dot with mic icon
            Circle()
                .fill(coral)
                .frame(width: size, height: size)
                .shadow(color: coral.opacity(0.35), radius: 5, x: 0, y: 2)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: size * 0.46))
                        .foregroundStyle(.white)
                )
                .scaleEffect(pulsing ? 1.07 : 1.0)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: pulsing
                )
        }
        .onAppear {
            // Delay matches the spring settle time so ripples start after dot lands
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pulsing = true
            }
        }
    }
}

// MARK: - Mode choice screen

private struct ModeChoiceView: View {
    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 4) {
                Text("spoke")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(coral)
                    .frame(width: 6, height: 6)
            }
            .padding(.bottom, 24)

            Text("How do you want to work?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            VStack(spacing: 16) {
                simpleModeCard
                organizedModeCard
            }
            .padding(.horizontal, 24)

            Spacer()

            Text("Don't worry, you can always change this later.")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 48)
        }
    }

    // MARK: Simple card

    private var simpleModeCard: some View {
        Button {
            settings.appMode = .simple
            settings.hasCompletedOnboarding = true
        } label: {
            VStack(spacing: 14) {
                // Illustration
                VStack(spacing: 0) {
                    voiceInputRow
                    bubbleDots
                    // Result: section header + task
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Added today")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(.label).opacity(0.35))
                        HStack(spacing: 7) {
                            Circle()
                                .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                            Text("Get milk and eggs")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                // Title + description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Simple")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Just capture your thoughts. No fuss.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(coral.opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Organized card

    private var organizedModeCard: some View {
        Button {
            settings.appMode = .organized
            settings.hasCompletedOnboarding = true
        } label: {
            VStack(spacing: 14) {
                // Illustration
                VStack(spacing: 0) {
                    voiceInputRow
                    bubbleDots
                    // Result: filter pills + section header + task + pills + subtasks
                    VStack(alignment: .leading, spacing: 5) {
                        // Tag filter pills
                        HStack(spacing: 4) {
                            filterChip("All", active: true)
                            filterChip("Work", active: false)
                            filterChip("Errands", active: false)
                            filterChip("Home", active: false)
                        }

                        Text("Due today")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(.label).opacity(0.35))
                            .padding(.top, 2)

                        // Task row
                        HStack(spacing: 7) {
                            Circle()
                                .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                                .frame(width: 13, height: 13)
                            Text("Get milk and eggs for baking")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        // Pills
                        HStack(spacing: 4) {
                            metadataPill("FRIDAY", coral: true)
                            metadataPill("ERRANDS", coral: false)
                        }
                        .padding(.leading, 20)

                        // Subtasks
                        VStack(alignment: .leading, spacing: 4) {
                            subtaskRow("Milk")
                            subtaskRow("Eggs")
                        }
                        .padding(.leading, 20)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                // Title + description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Organized")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Auto-tags, deadlines, and org tools.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(coral.opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared illustration elements

    private var voiceInputRow: some View {
        HStack(spacing: 10) {
            // Waveform bars
            HStack(spacing: 2) {
                waveBar(height: 8, opacity: 0.3)
                waveBar(height: 16, opacity: 0.45)
                waveBar(height: 22, opacity: 0.7)
                waveBar(height: 12, opacity: 0.5)
                waveBar(height: 18, opacity: 0.6)
                waveBar(height: 10, opacity: 0.4)
                waveBar(height: 6, opacity: 0.3)
            }
            Text("\"Get milk and eggs for baking on Friday\"")
                .font(.system(size: 11, weight: .medium))
                .italic()
                .foregroundStyle(coral)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var bubbleDots: some View {
        VStack(spacing: 4) {
            Circle().fill(coral.opacity(0.5)).frame(width: 8, height: 8)
            Circle().fill(coral.opacity(0.32)).frame(width: 6, height: 6)
            Circle().fill(coral.opacity(0.18)).frame(width: 4, height: 4)
        }
        .padding(.bottom, 6)
    }

    private func waveBar(height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(coral.opacity(opacity))
            .frame(width: 2.5, height: height)
    }

    private func filterChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 8, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? .white : Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(active ? coral : Color(.tertiarySystemFill)))
    }

    private func metadataPill(_ label: String, coral isCoral: Bool) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(isCoral ? coral : Color(.secondaryLabel))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isCoral ? coral.opacity(0.12) : Color(.tertiarySystemFill))
            )
    }

    private func subtaskRow(_ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .strokeBorder(Color(.systemGray3), lineWidth: 1)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

#Preview {
    OnboardingView()
}
