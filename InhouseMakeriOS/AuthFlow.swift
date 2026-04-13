import AuthenticationServices
import GoogleSignIn
import SwiftUI
import UIKit

enum AuthProvider: String, Codable, CaseIterable, Hashable {
    case apple = "APPLE"
    case google = "GOOGLE"

    init?(serverValue: String?) {
        guard let serverValue else { return nil }
        switch serverValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "apple", "apple_id":
            self = .apple
        case "google":
            self = .google
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        }
    }

    var continueTitle: String {
        switch self {
        case .apple:
            return "Apple로 계속하기"
        case .google:
            return "Google로 계속하기"
        }
    }

    var symbolName: String {
        switch self {
        case .apple:
            return "apple.logo"
        case .google:
            return "globe"
        }
    }
}

struct PresentationError: Equatable {
    let title: String
    let message: String
}

enum AuthRequirement: Equatable {
    case favorites
    case cloudSave
    case shareRecord
    case profileSync
    case groupManagement
    case recruitingWrite
    case matchSave
    case resultSave
    case notifications
    case profileHistory
    case riotAccount
    case settings
    case generic

    var title: String {
        "로그인하면 이 기능을 사용할 수 있어요"
    }

    var message: String {
        switch self {
        case .favorites:
            return "찜 목록을 기기 간에 동기화하고, 다시 들어와도 바로 이어서 확인할 수 있어요."
        case .cloudSave:
            return "내전 기록 저장, 기기 간 이어하기, 내 계정 기준 기록 관리를 사용할 수 있어요."
        case .shareRecord:
            return "내전 기록 저장, 공유 링크 생성, 기기 간 이어하기를 사용하려면 로그인이 필요해요."
        case .profileSync:
            return "프로필 동기화, 최근 전적 백업, 기기 간 이어하기를 사용할 수 있어요."
        case .groupManagement:
            return "그룹 상세 확인, 그룹 생성, 멤버 관리, 매치 저장은 로그인 후 이어서 사용할 수 있어요."
        case .recruitingWrite:
            return "모집 상세 확인, 모집 참여 흐름, 글 작성과 그룹 연결은 로그인 후 사용할 수 있어요."
        case .matchSave:
            return "지금 프리뷰는 이 기기에만 임시 저장됩니다. 실제 매치 생성과 저장, 로비 관리 기능은 로그인 후 사용할 수 있어요."
        case .resultSave:
            return "지금 프리뷰 결과는 계정에 자동 저장되지 않아요. 결과 저장과 계정 동기화는 로그인 후 직접 이어서 진행할 수 있어요."
        case .notifications:
            return "알림은 계정 기반 기능이라 로그인 후 확인할 수 있어요."
        case .profileHistory:
            return "내 기록, 통계, 프로필 상세는 로그인 후 사용할 수 있어요."
        case .riotAccount:
            return "Riot 계정 연동과 동기화는 계정 귀속 기능이라 로그인 후 사용할 수 있어요."
        case .settings:
            return "계정 기반 설정, 프로필 편집, 동기화 기능을 사용하려면 로그인이 필요해요."
        case .generic:
            return "찜 목록 동기화, 내전 기록 저장, 기기 간 이어하기를 사용할 수 있어요."
        }
    }
}

struct AuthPromptContext: Identifiable, Equatable {
    let id = UUID()
    let requirement: AuthRequirement

    var title: String { requirement.title }
    var message: String { requirement.message }
}

struct ProviderConflictError: Error, Equatable {
    let email: String?
    let suggestedProvider: AuthProvider
    let availableProviders: [AuthProvider]

    var presentationError: PresentationError {
        let message: String
        switch suggestedProvider {
        case .apple:
            message = "이 계정은 Apple 로그인으로 이용할 수 있어요. Apple로 계속해 주세요."
        case .google:
            message = "이 계정은 Google 로그인으로 이용할 수 있어요. Google로 계속해 주세요."
        }
        return PresentationError(title: "로그인 방법 안내", message: message)
    }
}

enum AuthError: Error, Equatable {
    case socialTokenInvalid
    case accountExistsWithApple(email: String?)
    case accountExistsWithGoogle(email: String?)
    case authProviderMismatch(email: String?, provider: AuthProvider?, availableProviders: [AuthProvider])
    case authRequired
    case invalidCredentials
    case emailAuthDisabled
    case passwordAuthDisabled
    case networkOffline
    case networkTimeout
    case rateLimited
    case serverUnavailable
    case networkError
    case unknown

    var providerConflict: ProviderConflictError? {
        switch self {
        case let .accountExistsWithApple(email):
            return ProviderConflictError(email: email, suggestedProvider: .apple, availableProviders: [.apple])
        case let .accountExistsWithGoogle(email):
            return ProviderConflictError(email: email, suggestedProvider: .google, availableProviders: [.google])
        case let .authProviderMismatch(email, provider, availableProviders):
            guard let suggestedProvider = provider ?? availableProviders.first else { return nil }
            return ProviderConflictError(
                email: email,
                suggestedProvider: suggestedProvider,
                availableProviders: availableProviders.isEmpty ? [suggestedProvider] : availableProviders
            )
        case .socialTokenInvalid, .authRequired, .invalidCredentials, .emailAuthDisabled, .passwordAuthDisabled, .networkOffline, .networkTimeout, .rateLimited, .serverUnavailable, .networkError, .unknown:
            return nil
        }
    }

    var presentationError: PresentationError {
        switch self {
        case .socialTokenInvalid:
            return PresentationError(title: "로그인 정보를 확인할 수 없어요", message: "선택한 로그인 정보를 다시 확인한 뒤 한 번 더 시도해 주세요.")
        case .accountExistsWithApple:
            return ProviderConflictError(email: nil, suggestedProvider: .apple, availableProviders: [.apple]).presentationError
        case .accountExistsWithGoogle:
            return ProviderConflictError(email: nil, suggestedProvider: .google, availableProviders: [.google]).presentationError
        case let .authProviderMismatch(_, provider, availableProviders):
            if let provider = provider ?? availableProviders.first {
                return ProviderConflictError(email: nil, suggestedProvider: provider, availableProviders: availableProviders.isEmpty ? [provider] : availableProviders).presentationError
            }
            return PresentationError(title: "로그인 방법 안내", message: "이 계정은 다른 로그인 방식으로 연결되어 있어요. 올바른 로그인 방식으로 다시 시도해 주세요.")
        case .authRequired:
            return PresentationError(title: "로그인이 필요해요", message: "로그인 후 다시 시도해 주세요.")
        case .invalidCredentials:
            return PresentationError(title: "로그인에 실패했어요", message: "로그인 정보를 다시 확인한 뒤 다시 시도해 주세요.")
        case .emailAuthDisabled, .passwordAuthDisabled:
            return PresentationError(title: "지원하지 않는 로그인 방식이에요", message: "이 앱에서는 Apple 또는 Google 로그인만 사용할 수 있어요.")
        case .networkOffline:
            return PresentationError(title: "인터넷 연결 확인", message: "인터넷 연결을 확인한 뒤 다시 시도해 주세요.")
        case .networkTimeout:
            return PresentationError(title: "응답이 지연되고 있어요", message: "잠시 후 다시 시도해 주세요.")
        case .rateLimited:
            return PresentationError(title: "요청이 잠시 몰리고 있어요", message: "잠시 후 다시 시도해 주세요.")
        case .serverUnavailable:
            return PresentationError(title: "서버에 잠시 문제가 있어요", message: "잠시 후 다시 시도해 주세요.")
        case .networkError, .unknown:
            return PresentationError(title: "문제가 발생했어요", message: "잠시 후 다시 시도해 주세요.")
        }
    }
}

enum AuthErrorMapper {
    static func map(_ error: Error) -> AuthError {
        if let authError = error as? AuthError {
            return authError
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return .networkOffline
            case .timedOut:
                return .networkTimeout
            default:
                return .networkError
            }
        }

        if let apiError = error as? APIClientError {
            switch apiError {
            case .unauthorized:
                return .invalidCredentials
            case .invalidResponse, .emptyBody, .invalidURL:
                return .networkError
            }
        }

        guard let userFacingError = error as? UserFacingError else {
            return .unknown
        }

        let rawMessage = userFacingError.message.lowercased()
        let provider = AuthProvider(serverValue: userFacingError.providerHint)
        let availableProviders = userFacingError.availableProviderHints.compactMap(AuthProvider.init(serverValue:))
        let email = userFacingError.details?["email"]?.stringValue

        if userFacingError.serverContractCode == .socialTokenInvalid || rawMessage.contains("social token") && rawMessage.contains("invalid") {
            return .socialTokenInvalid
        }

        switch userFacingError.serverContractCode {
        case .accountExistsWithApple:
            return .accountExistsWithApple(email: email)
        case .accountExistsWithGoogle:
            return .accountExistsWithGoogle(email: email)
        case .authProviderMismatch:
            return .authProviderMismatch(
                email: email,
                provider: provider,
                availableProviders: availableProviders
            )
        case .authRequired:
            return .authRequired
        case .invalidCredentials:
            return .invalidCredentials
        case .emailAuthDisabled:
            return .emailAuthDisabled
        case .passwordAuthDisabled:
            return .passwordAuthDisabled
        case .rateLimited:
            return .rateLimited
        case .forbiddenFeature:
            return .networkError
        case .socialTokenInvalid, .unknown:
            break
        }

        if userFacingError.statusCode == 401 {
            return .invalidCredentials
        }

        if userFacingError.statusCode.map({ $0 >= 500 }) == true {
            return .serverUnavailable
        }

        if userFacingError.normalizedCode.contains("NETWORK") {
            return .networkError
        }

        return .unknown
    }
}

enum SubmittingState: Equatable {
    case idle
    case loading(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var title: String? {
        if case let .loading(message) = self {
            return message
        }
        return nil
    }
}

struct AuthEntryState: Equatable {
    var formError: PresentationError?
    var providerConflict: ProviderConflictError?
}

struct SocialLoginState: Equatable {
    var activeProvider: AuthProvider?
    var submittingState: SubmittingState = .idle
    var formError: PresentationError?
    var providerConflict: ProviderConflictError?
}

enum SuccessTransitionState: Equatable {
    case idle
    case bootstrappingSession
    case completed
}

struct AuthFlowState: Equatable {
    var entryState = AuthEntryState()
    var socialLoginState = SocialLoginState()
    var successTransitionState: SuccessTransitionState = .idle
}

enum AuthSessionEvent {
    case login(AuthProvider)

    var title: String {
        "로그인 완료"
    }

    var symbol: String {
        switch self {
        case .login(.apple):
            return "apple.logo"
        case .login(.google):
            return "globe"
        }
    }

    func body(for profile: UserProfile) -> String {
        "\(profile.nickname)님이 로그인했습니다."
    }
}

@MainActor
final class AuthFlowViewModel: ObservableObject {
    @Published private(set) var state = AuthFlowState()

    private let session: AppSessionViewModel

    init(session: AppSessionViewModel) {
        self.session = session
    }

    var isBusy: Bool {
        state.socialLoginState.submittingState.isLoading || state.successTransitionState == .bootstrappingSession
    }

    var landingPresentationError: PresentationError? {
        state.socialLoginState.formError ?? state.entryState.formError
    }

    var currentProviderConflict: ProviderConflictError? {
        state.socialLoginState.providerConflict ?? state.entryState.providerConflict
    }

    var progressTitle: String {
        if state.successTransitionState == .bootstrappingSession {
            return "계정을 확인하고 있습니다"
        }
        return state.socialLoginState.submittingState.title ?? "로그인 중입니다"
    }

    func clearLandingError() {
        state.entryState.formError = nil
        state.entryState.providerConflict = nil
        state.socialLoginState.formError = nil
        state.socialLoginState.providerConflict = nil
    }

    func beginInteractiveLogin(provider: AuthProvider) {
        guard !isBusy else { return }
        clearLandingError()
        state.socialLoginState.activeProvider = provider
        state.socialLoginState.submittingState = .loading("\(provider.title) 로그인을 준비하고 있습니다")
    }

    func handleAppleAuthorizationResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                handleAppleFailure(AuthError.unknown)
                return
            }
            Task {
                await handleAppleCredential(credential)
            }
        case let .failure(error):
            handleAppleFailure(error)
        }
    }

    func startGoogleLogin() {
        beginInteractiveLogin(provider: .google)

        guard !session.container.configuration.googleClientID.isEmpty else {
            handleGoogleFailure(AuthError.unknown)
            return
        }

        guard let presentingViewController = topViewController() else {
            handleGoogleFailure(AuthError.unknown)
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: session.container.configuration.googleClientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error {
                Task { @MainActor in
                    self.handleGoogleFailure(error)
                }
                return
            }

            guard let result else {
                Task { @MainActor in
                    self.handleGoogleFailure(AuthError.unknown)
                }
                return
            }

            Task {
                await self.handleGoogleResult(result)
            }
        }
    }

    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            presentInlineError(
                PresentationError(title: "Apple 로그인 실패", message: "Apple 로그인 정보를 가져오지 못했어요. 다시 시도해 주세요.")
            )
            return
        }

        await authenticateSocial(provider: .apple) {
            try await self.session.container.authRepository.loginWithApple(
                authorization: AppleLoginAuthorization(
                    identityToken: token,
                    authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                    userIdentifier: credential.user,
                    email: credential.email,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
            )
        }
    }

    func handleAppleFailure(_ error: Error) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled
        {
            resetLoadingState()
            return
        }

        let mappedError = AuthErrorMapper.map(error)
        if mappedError != .unknown {
            presentInlineError(mappedError.presentationError)
        } else {
            presentInlineError(
                PresentationError(title: "Apple 로그인 실패", message: "Apple 로그인을 완료하지 못했어요. 다시 시도해 주세요.")
            )
        }
    }

    func handleGoogleResult(_ result: GIDSignInResult) async {
        guard let idToken = result.user.idToken?.tokenString else {
            presentInlineError(
                PresentationError(title: "Google 로그인 실패", message: "Google 로그인 정보를 가져오지 못했어요. 다시 시도해 주세요.")
            )
            return
        }

        await authenticateSocial(provider: .google) {
            try await self.session.container.authRepository.loginWithGoogle(
                authorization: GoogleLoginAuthorization(
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    email: result.user.profile?.email,
                    name: result.user.profile?.name
                )
            )
        }
    }

    func handleGoogleFailure(_ error: Error?) {
        if let nsError = error as NSError?,
           nsError.domain == kGIDSignInErrorDomain,
           nsError.code == -5
        {
            resetLoadingState()
            return
        }

        if let error {
            let mappedError = AuthErrorMapper.map(error)
            if mappedError != .unknown {
                presentInlineError(mappedError.presentationError)
                return
            }
        }

        presentInlineError(
            PresentationError(title: "Google 로그인 실패", message: "Google 로그인을 완료하지 못했어요. 다시 시도해 주세요.")
        )
    }

    private func authenticateSocial(
        provider: AuthProvider,
        operation: @escaping () async throws -> AuthTokens
    ) async {
        guard !isBusy || state.socialLoginState.activeProvider == provider else { return }

        clearLandingError()
        state.socialLoginState.activeProvider = provider
        state.socialLoginState.submittingState = .loading("\(provider.title) 로그인 중입니다")

        do {
            let tokens = try await operation()
            try await finalizeAuthentication(tokens: tokens, event: .login(provider))
        } catch {
            let authError = AuthErrorMapper.map(error)
            resetLoadingState()
            state.socialLoginState.formError = authError.presentationError
            state.socialLoginState.providerConflict = authError.providerConflict
            state.entryState.formError = authError.presentationError
            state.entryState.providerConflict = authError.providerConflict
        }
    }

    private func finalizeAuthentication(tokens: AuthTokens, event: AuthSessionEvent) async throws {
        state.successTransitionState = .bootstrappingSession
        _ = try await session.completeAuthenticatedSession(tokens: tokens, event: event)
        resetLoadingState()
        state.successTransitionState = .completed
    }

    private func presentInlineError(_ error: PresentationError) {
        resetLoadingState()
        state.entryState.formError = error
        state.socialLoginState.formError = error
    }

    private func resetLoadingState() {
        state.socialLoginState.submittingState = .idle
        state.socialLoginState.activeProvider = nil
        state.successTransitionState = .idle
    }
}

private extension UserFacingError {
    var providerHint: String? {
        if let direct = details?["provider"]?.stringValue, !direct.isEmpty {
            return direct
        }
        if let provider, !provider.isEmpty {
            return provider
        }
        return code
    }

    var availableProviderHints: [String] {
        details?["availableProviders"]?.stringArrayValue ?? []
    }
}

private extension JSONValue {
    var stringArrayValue: [String]? {
        guard case let .array(values) = self else { return nil }
        return values.compactMap { value in
            switch value {
            case let .string(text):
                return text
            default:
                let rendered = value.stringValue
                return rendered.isEmpty ? nil : rendered
            }
        }
    }
}

extension AppSessionViewModel {
    func completeAuthenticatedSession(tokens: AuthTokens, event: AuthSessionEvent) async throws -> UserProfile {
        try await completeAuthenticatedSession(
            tokens: tokens,
            event: event,
            loadProfile: { try await self.container.profileRepository.me() },
            onSignOut: { await self.container.authRepository.signOut() }
        )
    }

    func completeAuthenticatedSession(
        tokens: AuthTokens,
        event: AuthSessionEvent,
        loadProfile: @escaping () async throws -> UserProfile,
        onSignOut: @escaping () async -> Void
    ) async throws -> UserProfile {
        beginAuthenticating()

        do {
            let profile = try await loadProfile()
            let sessionData = UserSession(authTokens: tokens, user: profile)
            let pendingAction = consumePendingAuthAction()
            container.localStore.appendNotification(
                title: event.title,
                body: event.body(for: profile),
                symbol: event.symbol
            )
            applyAuthenticatedSession(sessionData)
            completeGuestOnboarding()
            pendingAction?()
            return profile
        } catch {
            await onSignOut()
            restoreGuestSession()
            throw AuthErrorMapper.map(error)
        }
    }
}

struct AuthLandingView: View {
    @ObservedObject private var session: AppSessionViewModel
    @StateObject private var viewModel: AuthFlowViewModel

    init(session: AppSessionViewModel) {
        self.session = session
        _viewModel = StateObject(wrappedValue: AuthFlowViewModel(session: session))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StatusBarView()

                VStack(spacing: 0) {
                    brandingSection
                        .padding(.top, 54)

                    featureSection
                        .padding(.top, 34)

                    Spacer()

                    onboardingActionSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }

            if viewModel.isBusy {
                AuthBlockingProgressView(title: viewModel.progressTitle)
            }
        }
    }

    private var brandingSection: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppPalette.accentBlue)
                    .frame(width: 80, height: 80)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            Text("내전 메이커")
                .font(AppTypography.heading(32, weight: .heavy))
                .tracking(2)
            Text("Apple 또는 Google 로그인으로 빠르게 시작하세요")
                .font(AppTypography.body(16))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureSection: some View {
        VStack(spacing: 14) {
            featureCard(symbol: "scalemass.fill", title: "자동 팀 밸런싱", subtitle: "매치 데이터 기반 5:5 최적 팀 생성", tint: AppPalette.accentBlue)
            featureCard(symbol: "chart.bar.xaxis", title: "라인별 밸런스 분석", subtitle: "TOP/JGL/MID/ADC/SUP 포지션별 파워 비교", tint: AppPalette.accentPurple)
            featureCard(symbol: "trophy.fill", title: "결과 기록 및 재매칭", subtitle: "내전 결과 빠른 입력, 실력 반영 자동 업데이트", tint: AppPalette.accentGold)
            featureCard(symbol: "person.3.fill", title: "팀원 · 상대팀 모집", subtitle: "포지션 · 티어 · 성향 매칭으로 빠른 내전 구성", tint: AppPalette.accentGreen)
        }
    }

    private var onboardingActionSection: some View {
        VStack(spacing: 12) {
            Button {
                session.completeGuestOnboarding()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("바로 시작하기")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("로그인은 선택 사항이에요. 찜 동기화, 기록 저장, 기기 간 이어하기가 필요할 때 언제든 로그인할 수 있어요.")
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

            SocialLoginOptionsSection(
                viewModel: viewModel,
                prompt: nil,
                showsSkipButton: false,
                onSkip: nil
            )

            Text("Apple 또는 Google 로그인으로 찜, 동기화, 공유 기능을 연결할 수 있어요")
                .font(AppTypography.body(10))
                .foregroundStyle(AppPalette.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private func featureCard(symbol: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(AppPalette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.body(15, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(subtitle)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}

struct AuthGateSheet: View {
    @ObservedObject private var session: AppSessionViewModel
    let prompt: AuthPromptContext
    @StateObject private var viewModel: AuthFlowViewModel

    init(session: AppSessionViewModel, prompt: AuthPromptContext) {
        self.session = session
        self.prompt = prompt
        _viewModel = StateObject(wrappedValue: AuthFlowViewModel(session: session))
    }

    var body: some View {
        ZStack {
            AppPalette.bgPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(AppPalette.border)
                    .frame(width: 42, height: 5)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text(prompt.title)
                        .font(AppTypography.heading(22, weight: .bold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Text(prompt.message)
                        .font(AppTypography.body(14))
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    SocialLoginOptionsSection(
                        viewModel: viewModel,
                        prompt: prompt,
                        showsSkipButton: true,
                        onSkip: { session.dismissAuthPrompt() }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            if viewModel.isBusy {
                AuthBlockingProgressView(title: viewModel.progressTitle)
            }
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
    }
}

struct AuthInlineAccessCard: View {
    private let title: String
    private let message: String
    @StateObject private var viewModel: AuthFlowViewModel

    init(session: AppSessionViewModel, title: String, message: String) {
        self.title = title
        self.message = message
        _viewModel = StateObject(wrappedValue: AuthFlowViewModel(session: session))
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(AppTypography.heading(18, weight: .bold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(message)
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SocialLoginOptionsSection(
                    viewModel: viewModel,
                    prompt: nil,
                    showsSkipButton: false,
                    onSkip: nil
                )
            }
            .padding(16)
            .appPanel(background: AppPalette.bgCard, radius: 12)

            if viewModel.isBusy {
                AuthBlockingProgressView(title: viewModel.progressTitle)
            }
        }
    }
}

private struct SocialLoginOptionsSection: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    let prompt: AuthPromptContext?
    let showsSkipButton: Bool
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let presentationError = viewModel.landingPresentationError {
                AuthBanner(title: presentationError.title, message: presentationError.message, tint: AppPalette.accentRed)
            }

            if let conflict = viewModel.currentProviderConflict {
                SuggestedProviderPanel(
                    conflict: conflict,
                    onGoogleTap: { viewModel.startGoogleLogin() },
                    onAppleCompletion: viewModel.handleAppleAuthorizationResult
                )
            }

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                viewModel.handleAppleAuthorizationResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(viewModel.isBusy)

            Button {
                viewModel.startGoogleLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Google로 로그인")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isBusy)

            if showsSkipButton {
                Button("나중에 하기") {
                    onSkip?()
                }
                .font(AppTypography.body(14, weight: .semibold))
                .foregroundStyle(AppPalette.textSecondary)
                .padding(.top, 4)
            } else if prompt != nil {
                Text("로그인 후 원래 하려던 작업으로 바로 돌아갑니다")
                    .font(AppTypography.body(10))
                    .foregroundStyle(AppPalette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct AuthBanner: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.body(13, weight: .semibold))
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .foregroundStyle(tint)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: AppCorner.md)
                .stroke(tint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppCorner.md))
    }
}

private struct SuggestedProviderPanel: View {
    let conflict: ProviderConflictError
    let onGoogleTap: () -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AuthBanner(
                title: conflict.presentationError.title,
                message: conflict.presentationError.message,
                tint: AppPalette.accentOrange
            )

            switch conflict.suggestedProvider {
            case .apple:
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    onAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .google:
                Button {
                    onGoogleTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("Google로 계속하기")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct AuthBlockingProgressView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppPalette.accentBlue)
                Text(title)
                    .font(AppTypography.body(13))
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .padding(24)
            .frame(width: 220)
            .appPanel(background: AppPalette.bgSecondary, radius: AppCorner.lg)
        }
    }
}
