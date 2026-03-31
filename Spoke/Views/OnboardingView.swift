import SwiftUI

// MARK: - OnboardingView (manages three-screen intro flow)

struct OnboardingView: View {
    @State private var phase: OnboardingPhase = .splash

    private enum OnboardingPhase: Equatable {
        case splash
        case modeChoice
        case firstTask
    }

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashIntroView {
                    withAnimation(.easeInOut(duration: 0.45)) { phase = .modeChoice }
                }
                .transition(.opacity)
            case .modeChoice:
                ModeChoiceView {
                    withAnimation(.easeInOut(duration: 0.45)) { phase = .firstTask }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))
            case .firstTask:
                FirstTaskRecordingView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phase)
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

            HStack(alignment: .bottom, spacing: 0) {
                Text(typedText)
                    .font(.system(size: 70, weight: .medium))
                    .foregroundStyle(.primary)
                    .kerning(-1.5)
                    .animation(nil, value: typedText)

                if showDot {
                    PulsingMicDot(size: dotSize, coral: coral)
                        .scaleEffect(dotScale)
                        .frame(width: dotSize * 1.8, height: dotSize * 1.8)
                        .offset(x: 3, y: -14)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(width: 3, height: 56)
                        .opacity(cursorOpacity)
                        .offset(x: 3, y: -8)
                }
            }

            Text("Your day, dictated.")
                .font(.system(size: 17))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, 20)
                .opacity(taglineOpacity)

            Spacer()

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
        try? await Task.sleep(for: .milliseconds(700))
        for _ in 0..<fullWord.count {
            typedCount += 1
            try? await Task.sleep(for: .milliseconds(115))
        }
        try? await Task.sleep(for: .milliseconds(100))
        showDot = true
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 14)) {
            dotScale = 1.0
        }
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.easeOut(duration: 0.6)) { taglineOpacity = 1 }
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

// MARK: - Pulsing mic dot

private struct PulsingMicDot: View {
    let size: CGFloat
    let coral: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(coral, lineWidth: 1)
                .scaleEffect(pulsing ? 1.5 : 1.0)
                .opacity(pulsing ? 0 : 0.3)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulsing)
            Circle()
                .strokeBorder(coral, lineWidth: 1)
                .scaleEffect(pulsing ? 1.5 : 1.0)
                .opacity(pulsing ? 0 : 0.3)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.7), value: pulsing)
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
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pulsing = true }
        }
    }
}

// MARK: - Mode choice screen

private struct ModeChoiceView: View {
    let onModeSelected: () -> Void

    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    @State private var selectedMode: AppMode?

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
            .padding(.bottom, 16)

            Text("How do you want to work?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text("Don't worry, you can always change this later.")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

            VStack(spacing: 16) {
                modeCard(
                    mode: .simple,
                    title: "Simple",
                    description: "Just capture your thoughts. No fuss.",
                    illustration: simpleIllustration
                )
                modeCard(
                    mode: .organized,
                    title: "Organized",
                    description: "Auto-tags, deadlines, and org tools.",
                    illustration: organizedIllustration
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Next button
            Button {
                if let mode = selectedMode {
                    settings.appMode = mode
                    onModeSelected()
                }
            } label: {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(selectedMode != nil ? coral : Color(.systemGray4)))
            }
            .disabled(selectedMode == nil)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .animation(.easeInOut(duration: 0.2), value: selectedMode)
        }
    }

    private func modeCard(mode: AppMode, title: String, description: String, illustration: some View) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMode = mode
            }
        } label: {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    voiceInputRow
                    bubbleDots
                    illustration
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(description)
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
                            .strokeBorder(
                                isSelected ? coral : Color(.systemGray4),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var simpleIllustration: some View {
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

    private var organizedIllustration: some View {
        VStack(alignment: .leading, spacing: 5) {
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
            HStack(spacing: 7) {
                Circle()
                    .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                Text("Get milk and eggs for baking")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 4) {
                metadataPill("FRIDAY", coral: true)
                metadataPill("ERRANDS", coral: false)
            }
            .padding(.leading, 20)
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

    // MARK: Shared illustration elements

    private var voiceInputRow: some View {
        HStack(spacing: 10) {
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

// MARK: - First task recording screen

private struct FirstTaskRecordingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false

    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let sampleText = "\"Book a car service for Friday, and I need to do the grocery shopping — get milk, eggs, and bread\""

    private var isIdle: Bool { recorder.recordingState == .idle }
    private var isRecording: Bool { recorder.recordingState == .recording }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header text
            if recorder.recordingState == .processing {
                ProgressView()
                    .tint(coral)
                Text("Creating your tasks...")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 12)
            } else {
                Text(isRecording ? "Listening..." : "Add your first tasks")
                    .font(.system(size: 24, weight: .semibold))
                    .animation(.easeInOut(duration: 0.2), value: isRecording)

                Text(isRecording ? "Tap to stop" : "Tap the mic and try saying:")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 6)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }

            // Sample text (visible in idle and recording states)
            if recorder.recordingState != .processing {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        waveBar(height: 6, opacity: 0.3)
                        waveBar(height: 12, opacity: 0.45)
                        waveBar(height: 16, opacity: 0.7)
                        waveBar(height: 10, opacity: 0.5)
                        waveBar(height: 14, opacity: 0.6)
                        waveBar(height: 8, opacity: 0.4)
                        waveBar(height: 5, opacity: 0.3)
                    }
                    Text(sampleText)
                        .font(.system(size: 13, weight: .medium))
                        .italic()
                        .foregroundStyle(coral)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(coral.opacity(0.06))
                )
                .padding(.horizontal, 32)
                .padding(.top, 28)
            }

            Spacer()

            // Voice button at bottom center
            VoiceButton(
                state: voiceButtonState,
                audioLevel: recorder.audioLevel,
                onTap: handleTap
            )
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.bottom, 24)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spoke needs microphone and speech recognition access to create voice tasks. Please enable them in Settings.")
        }
    }

    private var voiceButtonState: VoiceButtonState {
        switch recorder.recordingState {
        case .idle:       .idle
        case .recording:  .recording
        case .processing: .processing
        }
    }

    private func handleTap() {
        switch recorder.recordingState {
        case .idle:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                let granted = await recorder.requestPermissionsIfNeeded()
                guard granted else {
                    showPermissionAlert = true
                    return
                }
                do {
                    try recorder.startRecording()
                } catch {
                    recorder.finishProcessing()
                }
            }
        case .recording:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            stopAndProcess()
        case .processing:
            break
        }
    }

    private func stopAndProcess() {
        let transcript = recorder.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recorder.finishProcessing()
            return
        }
        Task {
            let parsedTasks = await TaskParser.parse(transcript: transcript)
            for parsed in parsedTasks {
                let task = SpokeTask(
                    title: parsed.title,
                    taskDescription: parsed.description,
                    deadline: parsed.deadline,
                    tag: parsed.tag
                )
                modelContext.insert(task)
            }
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Complete onboarding — ContentView takes over
            settings.hasCompletedOnboarding = true
        }
    }

    private func waveBar(height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(coral.opacity(opacity))
            .frame(width: 2.5, height: height)
    }
}

#Preview {
    OnboardingView()
}
