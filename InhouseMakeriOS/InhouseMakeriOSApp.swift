import GoogleSignIn
import SwiftUI

@main
struct InhouseMakeriOSApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var session = AppSessionViewModel(container: AppContainer())

    init() {
        AppNavigationAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if case .bootstrapping = session.state {
                    LoadingStateView(title: "세션을 확인하는 중입니다")
                } else if session.shouldPresentOnboarding {
                    OnboardingView(session: session)
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
                await session.bootstrap()
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
}
