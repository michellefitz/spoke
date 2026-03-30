import SwiftUI

struct OnboardingView: View {
    private let settings = AppSettings.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Wordmark
            HStack(spacing: 4) {
                Text("spoke")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(coral)
                    .frame(width: 6, height: 6)
            }
            .padding(.bottom, 48)

            Text("How do you want to work?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            // Mode cards
            HStack(spacing: 16) {
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
