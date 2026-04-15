import GoogleSignIn
import SwiftUI

@main
struct InhouseMakeriOSApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var session = AppSessionViewModel(container: AppContainer())
    @State private var hasStartedLaunchSequence = false
    @State private var hasCompletedLaunchSequence = false

    init() {
        AppNavigationAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedLaunchSequence {
                    SplashView()
                } else if session.shouldPresentOnboarding {
                    OnboardingLandingView(session: session)
                } else {
                    AppShellView(
                        session: session,
                        router: router
                    )
                }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .appBackground()
            .preferredColorScheme(.dark)
            .task {
                await runLaunchSequenceIfNeeded()
            }
            .onChange(of: session.shouldPresentOnboarding) { _, shouldPresentOnboarding in
                #if DEBUG
                if shouldPresentOnboarding {
                    print("[AppRoot] onboarding presented")
                } else {
                    print("[AppRoot] landing dismissed; presenting main shell")
                }
                #endif
            }
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    @MainActor
    private func runLaunchSequenceIfNeeded() async {
        guard !hasStartedLaunchSequence else { return }
        hasStartedLaunchSequence = true

        #if DEBUG
        print("[AppRoot] splash presented")
        #endif

        async let bootstrapTask: Void = session.bootstrap()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await bootstrapTask

        withAnimation(.easeInOut(duration: 0.3)) {
            hasCompletedLaunchSequence = true
        }

        #if DEBUG
        print("[AppRoot] splash finished")
        #endif
    }
}

private struct SplashView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.bgPrimary, AppPalette.bgSecondary, AppPalette.bgPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppPalette.accentBlue.opacity(0.18))
                        .frame(width: 118, height: 118)
                        .scaleEffect(isAnimating ? 1.06 : 0.94)

                    RoundedRectangle(cornerRadius: 26)
                        .fill(AppPalette.accentBlue)
                        .frame(width: 84, height: 84)

                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(spacing: 6) {
                    Text("내전 메이커")
                        .font(AppTypography.heading(30, weight: .heavy))
                        .tracking(2)

                    Text("매치를 준비하는 가장 빠른 시작")
                        .font(AppTypography.body(13))
                        .foregroundStyle(AppPalette.textSecondary)
                }

                ProgressView()
                    .tint(AppPalette.accentBlue)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
