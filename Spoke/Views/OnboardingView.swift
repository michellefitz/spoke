import SwiftUI
import AVFoundation

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
                Text("Let's go")
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
    @State private var selectedMode: AppMode = .simple

    private var modeDescription: String {
        selectedMode == .simple
            ? "A clean list. Nothing more, nothing less."
            : "Tags, deadlines, and subtasks — sorted automatically."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Constrain width for iPad
            VStack(spacing: 0) {

            // Wordmark
            HStack(spacing: 4) {
                Text("spoke")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(coral)
                    .frame(width: 5, height: 5)
            }
            .padding(.bottom, 20)

            // Heading
            Text("Pick your mode")
                .font(.system(size: 26, weight: .semibold))
                .padding(.bottom, 6)

            Text("Choose how you like to get things done.")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.bottom, 24)

            // Segmented picker
            Picker("Mode", selection: $selectedMode) {
                Text("Simple").tag(AppMode.simple)
                Text("Organized").tag(AppMode.organized)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            // App preview card — fixed height container so switching doesn't shift layout
            ZStack(alignment: .top) {
                if selectedMode == .simple {
                    simplePreview
                } else {
                    organizedPreview
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)
            .animation(.easeInOut(duration: 0.25), value: selectedMode)
            .padding(.horizontal, 24)

            // Description — changes with selection
            Text(modeDescription)
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .padding(.horizontal, 40)
                .animation(.easeInOut(duration: 0.2), value: selectedMode)

            Text("You can switch anytime in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.top, 8)

            } // end constrained width VStack
            .frame(maxWidth: 400)

            Spacer()

            // Next button — always active since a mode is always selected
            Button {
                settings.appMode = selectedMode
                onModeSelected()
            } label: {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(coral))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Simple preview (clean task list)

    private var simplePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Added today")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(.label).opacity(0.35))
                .padding(.bottom, 8)

            ForEach(["Book dentist appointment", "Do grocery shopping", "Call insurance company", "Pick up dry cleaning"], id: \.self) { task in
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    Text(task)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.separator).opacity(0.3)).frame(height: 0.5)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .transition(.opacity)
    }

    // MARK: - Organized preview (task list with tags, dates, subtasks, filter pills)

    private var organizedPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filter pills
            HStack(spacing: 6) {
                filterChip("ALL", active: true)
                filterChip("PERSONAL", active: false)
                filterChip("SHOPPING", active: false)
                filterChip("HEALTH", active: false)
            }
            .padding(.bottom, 10)

            Text("Added today")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(.label).opacity(0.35))
                .padding(.bottom, 8)

            // Task 1: with date + tag
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    Text("Book dentist appointment")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    metadataPill("FRIDAY", isCoral: true)
                    metadataPill("HEALTH", isCoral: false)
                }
                .padding(.leading, 26)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(.separator).opacity(0.3)).frame(height: 0.5)
            }

            // Task 2: with tag + subtasks
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    Text("Do grocery shopping")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    metadataPill("SHOPPING", isCoral: false)
                }
                .padding(.leading, 26)
                VStack(alignment: .leading, spacing: 3) {
                    miniSubtask("Milk")
                    miniSubtask("Eggs")
                    miniSubtask("Bread")
                }
                .padding(.leading, 26)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(.separator).opacity(0.3)).frame(height: 0.5)
            }

            // Task 3: with tag
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Call insurance company")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    metadataPill("PERSONAL", isCoral: false)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .transition(.opacity)
    }

    // MARK: - Shared elements

    private func filterChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? .white : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? coral : Color(.tertiarySystemFill)))
    }

    private func metadataPill(_ label: String, isCoral: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(isCoral ? coral : Color(.secondaryLabel))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCoral ? coral.opacity(0.12) : Color(.tertiarySystemFill))
            )
    }

    private func miniSubtask(_ label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(Color(.systemGray3), lineWidth: 1)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

// MARK: - First task recording screen

private struct FirstTaskRecordingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false
    @State private var showSample = false
    @State private var showRetry = false
    @State private var micDenied = false
    @State private var sampleTaskCreated = false

    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let sampleText = "\"Book a dentist appointment for Friday, and I need to do the grocery shopping — get milk, eggs, and bread\""

    private var isIdle: Bool { recorder.recordingState == .idle }
    private var isRecording: Bool { recorder.recordingState == .recording }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header text
            if recorder.recordingState == .processing {
                ProgressView()
                    .tint(coral)
                Text("Working on it...")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 12)
            } else if isRecording {
                Text("Listening...")
                    .font(.system(size: 24, weight: .semibold))
                Text("Tap to stop")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 6)

                // Sample stays visible during recording
                sampleCard
                    .padding(.top, 28)
            } else {
                // Phase 1: heading + value prop (always visible)
                Text("Say it, we'll sort it")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.bottom, 10)

                Text("Just talk. Spoke turns your words into organized tasks.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 36)

                // Phase 2: sample + mic note (fades in after 1s)
                if showSample {
                    VStack(spacing: 0) {
                        Text("Tap the mic and say something like:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.top, 28)

                        sampleCard
                            .padding(.top, 14)
                    }
                    .transition(.opacity)
                }
            }

            Spacer()

            // Retry/skip after failure
            if showRetry {
                VStack(spacing: 12) {
                    Text("Hmm, we didn't catch that.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.secondaryLabel))

                    Button(action: retry) {
                        Text("Try again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(coral)
                    }

                    Button(action: skip) {
                        Text("Skip")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity)
            }

            if micDenied {
                // Mic permission denied — show disabled state
                VStack(spacing: 10) {
                    Text("Spoke requires microphone access to create tasks by voice.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Enable in Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(coral)
                    }

                    Button(action: skip) {
                        Text("Skip for now")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .padding(.bottom, 16)

                // Greyed-out mic button
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    )
                    .padding(.bottom, 24)
            } else {
                // Mic permission note (above mic button)
                if showSample && isIdle && !showRetry {
                    HStack(spacing: 5) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text("Microphone access required")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.bottom, 8)
                }

                // Voice button at bottom center
                VoiceButton(
                    state: voiceButtonState,
                    audioLevel: recorder.audioLevel,
                    onTap: handleTap
                )
                .frame(maxWidth: .infinity, minHeight: 96)
                .padding(.bottom, 24)
            }
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
        .task {
            // Create the sample task on appear
            if !sampleTaskCreated {
                sampleTaskCreated = true
                let sampleTask = SpokeTask(
                    title: "Welcome to Spoke",
                    taskDescription: "This is a sample task! Spoke turns your voice into organized tasks. Here's how to get started:\n• Record your first task — tap the mic and speak\n• Edit a task — open it and use the mic to add detail\n• Try a brain dump — say several tasks at once\n• Tasks can be edited with the keyboard as well as voice\n• Tap Settings to switch between Simple and Organized mode\n• Customize your tags in Settings (top right)\n• Check off a task by tapping the circle",
                    deadline: .now,
                    tag: "personal"
                )
                // Auto-complete after 7 days
                let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
                sampleTask.completedAt = nil
                sampleTask.createdAt = .now
                modelContext.insert(sampleTask)
                // Schedule auto-complete by storing the expiry
                UserDefaults.standard.set(sevenDays.timeIntervalSince1970, forKey: "sampleTaskExpiry")
            }

            // Check mic permission status
            let status = AVAudioApplication.shared.recordPermission
            if status == .denied {
                micDenied = true
            }

            // Fade in sample prompt
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.5)) {
                showSample = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check mic permission when returning from Settings
            let status = AVAudioApplication.shared.recordPermission
            if status == .granted {
                withAnimation { micDenied = false }
            }
        }
    }

    private var sampleCard: some View {
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
                    withAnimation { micDenied = true }
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
            showRetry = true
            return
        }
        Task {
            let parsedTasks = await TaskParser.parse(transcript: transcript)
            if parsedTasks.isEmpty {
                recorder.finishProcessing()
                showRetry = true
                return
            }
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
            settings.hasCompletedOnboarding = true
        }
    }

    private func retry() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showRetry = false
        }
    }

    private func skip() {
        settings.hasCompletedOnboarding = true
        settings.hasSeenCoaching = true
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
