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
            .padding(.bottom, 32)

            Text("How do you want to work?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            VStack(spacing: 16) {
                ModeCard(
                    title: "Simple",
                    description: "Just capture your thoughts. No fuss.",
                    systemImage: "mic.circle.fill",
                    mode: .simple
                )
                ModeCard(
                    title: "Organized",
                    description: "Auto-tags, deadlines, and org tools.",
                    systemImage: "list.bullet.clipboard.fill",
                    mode: .organized
                )
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
}

// MARK: - Mode card

private struct ModeCard: View {
    let title: String
    let description: String
    let systemImage: String
    let mode: AppMode

    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        Button {
            settings.appMode = mode
            settings.hasCompletedOnboarding = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(coral)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .padding(20)
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
}

#Preview {
    OnboardingView()
}
