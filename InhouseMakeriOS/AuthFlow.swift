import AuthenticationServices
import GoogleSignIn
import SwiftUI
import UIKit

enum AuthProvider: String, Codable, CaseIterable, Hashable {
    case apple = "APPLE"
    case google = "GOOGLE"
    case email = "EMAIL"

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
        case "email", "password", "email_password":
            self = .email
        default:
            return nil
        }
    }

    static let supportedProviders: [AuthProvider] = [.email, .apple, .google]
    static let socialProviders: [AuthProvider] = [.apple, .google]

    var title: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        case .email:
            return "이메일"
        }
    }

    var continueTitle: String {
        switch self {
        case .apple:
            return "Apple로 계속하기"
        case .google:
            return "Google로 계속하기"
        case .email:
            return "이메일로 계속하기"
        }
    }

    var symbolName: String {
        switch self {
        case .apple:
            return "apple.logo"
        case .google:
            return "globe"
        case .email:
            return "envelope.fill"
        }
    }

    var loginTitle: String {
        switch self {
        case .apple, .google:
            return continueTitle
        case .email:
            return "이메일로 로그인"
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
            return "Riot ID 관리와 동기화는 로그인 후 사용할 수 있어요."
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

    var resolvedAvailableProviders: [AuthProvider] {
        var providers = availableProviders
        if providers.isEmpty {
            providers = [suggestedProvider]
        } else if let suggestedIndex = providers.firstIndex(of: suggestedProvider), suggestedIndex != 0 {
            providers.remove(at: suggestedIndex)
            providers.insert(suggestedProvider, at: 0)
        } else if !providers.contains(suggestedProvider) {
            providers.insert(suggestedProvider, at: 0)
        }

        var deduplicated: [AuthProvider] = []
        for provider in providers where !deduplicated.contains(provider) {
            deduplicated.append(provider)
        }
        return deduplicated
    }

    var presentationError: PresentationError {
        let message: String
        switch suggestedProvider {
        case .apple:
            message = "이 계정은 Apple 로그인으로 이용할 수 있어요. Apple로 계속해 주세요."
        case .google:
            message = "이 계정은 Google 로그인으로 이용할 수 있어요. Google로 계속해 주세요."
        case .email:
            message = "이 계정은 이메일 로그인으로 이용할 수 있어요. 이메일로 로그인해 주세요."
        }
        return PresentationError(title: "로그인 방법 안내", message: message)
    }
}

struct SignupValidationIssue: Equatable {
    let field: String
    let message: String
}

enum AuthError: Error, Equatable {
    case socialTokenInvalid
    case accountExistsWithApple(email: String?)
    case accountExistsWithGoogle(email: String?)
    case authProviderMismatch(email: String?, provider: AuthProvider?, availableProviders: [AuthProvider])
    case accountNotFound(email: String?)
    case unsupportedProvider(provider: String?, availableProviders: [AuthProvider])
    case authRequired
    case emailAlreadyInUse
    case nicknameAlreadyInUse
    case invalidEmailFormat(message: String?)
    case weakPassword(message: String?)
    case requiredTermsNotAgreed(message: String?)
    case invalidPayload(issues: [SignupValidationIssue], message: String?)
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
        case .socialTokenInvalid, .accountNotFound, .unsupportedProvider, .authRequired, .emailAlreadyInUse, .nicknameAlreadyInUse, .invalidEmailFormat, .weakPassword, .requiredTermsNotAgreed, .invalidPayload, .invalidCredentials, .emailAuthDisabled, .passwordAuthDisabled, .networkOffline, .networkTimeout, .rateLimited, .serverUnavailable, .networkError, .unknown:
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
        case .accountNotFound:
            return PresentationError(title: "존재하지 않는 계정이에요", message: "가입한 이메일인지 다시 확인해 주세요.")
        case let .unsupportedProvider(_, availableProviders):
            let supportedCopy = availableProviders.isEmpty
                ? "이 앱에서는 이메일, Apple, Google 로그인을 사용할 수 있어요."
                : "이 앱에서는 \(availableProviders.map(\.title).joined(separator: ", ")) 로그인을 사용할 수 있어요."
            return PresentationError(title: "지원하지 않는 로그인 방식이에요", message: supportedCopy)
        case .authRequired:
            return PresentationError(title: "로그인이 필요해요", message: "로그인 후 다시 시도해 주세요.")
        case .emailAlreadyInUse:
            return PresentationError(title: "이미 가입된 이메일이에요", message: "이메일 로그인으로 계속하거나 다른 이메일을 사용해 주세요.")
        case .nicknameAlreadyInUse:
            return PresentationError(title: "이미 사용 중인 닉네임이에요", message: "다른 닉네임으로 다시 시도해 주세요.")
        case let .invalidEmailFormat(message):
            return PresentationError(title: "이메일 형식을 확인해 주세요", message: message ?? "올바른 이메일 형식으로 다시 입력해 주세요.")
        case let .weakPassword(message):
            return PresentationError(title: "비밀번호를 다시 확인해 주세요", message: message ?? "비밀번호 조건을 만족하도록 다시 입력해 주세요.")
        case let .requiredTermsNotAgreed(message):
            return PresentationError(title: "필수 약관 동의가 필요해요", message: message ?? "서비스 이용약관과 개인정보 처리방침에 동의해 주세요.")
        case let .invalidPayload(_, message):
            return PresentationError(title: "입력값을 다시 확인해 주세요", message: message ?? "입력한 회원가입 정보를 다시 확인한 뒤 시도해 주세요.")
        case .invalidCredentials:
            return PresentationError(title: "로그인에 실패했어요", message: "로그인 정보를 다시 확인한 뒤 다시 시도해 주세요.")
        case .emailAuthDisabled:
            return PresentationError(title: "이메일 회원가입을 사용할 수 없어요", message: "현재 이메일 회원가입이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요.")
        case .passwordAuthDisabled:
            return PresentationError(title: "이메일 로그인을 사용할 수 없어요", message: "현재 이메일 로그인이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요.")
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

        if userFacingError.serverContractCode == .accountNotFound {
            return .accountNotFound(email: email)
        }

        if userFacingError.statusCode == 404,
           (rawMessage.contains("not found") || rawMessage.contains("does not exist")),
           rawMessage.contains("account") || rawMessage.contains("email") || rawMessage.contains("user")
        {
            return .accountNotFound(email: email)
        }

        if userFacingError.normalizedCode.contains("ACCOUNT_EXISTS_WITH_EMAIL") {
            let resolvedProviders = availableProviders.isEmpty ? [.email] : availableProviders
            return .authProviderMismatch(
                email: email,
                provider: provider ?? .email,
                availableProviders: resolvedProviders
            )
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
        case .accountNotFound:
            return .accountNotFound(email: email)
        case .unsupportedProvider:
            return .unsupportedProvider(
                provider: userFacingError.providerHint,
                availableProviders: availableProviders
            )
        case .authRequired:
            return .authRequired
        case .invalidCredentials:
            return .invalidCredentials
        case .emailAlreadyExists:
            return .emailAlreadyInUse
        case .nicknameAlreadyExists:
            return .nicknameAlreadyInUse
        case .invalidEmailFormat:
            return .invalidEmailFormat(message: userFacingError.message)
        case .weakPassword:
            return .weakPassword(message: userFacingError.message)
        case .requiredTermsNotAgreed:
            return .requiredTermsNotAgreed(message: userFacingError.message)
        case .invalidPayload:
            return .invalidPayload(
                issues: userFacingError.signupValidationIssues,
                message: userFacingError.message
            )
        case .emailAuthDisabled:
            return .emailAuthDisabled
        case .passwordAuthDisabled:
            return .passwordAuthDisabled
        case .rateLimited:
            return .rateLimited
        case .internalServerError:
            return .serverUnavailable
        case .forbiddenFeature:
            return .networkError
        case .socialTokenInvalid:
            return .socialTokenInvalid
        case .unknown:
            break
        @unknown default:
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

        if userFacingError.normalizedCode.contains("UNSUPPORTED"), userFacingError.normalizedCode.contains("PROVIDER") || rawMessage.contains("unsupported provider") {
            return .unsupportedProvider(
                provider: userFacingError.providerHint,
                availableProviders: availableProviders
            )
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

enum EmailAuthDestination: String, Identifiable {
    case signUp
    case login

    var id: String { rawValue }
}

enum AuthSessionEvent {
    case login(AuthProvider)
    case emailSignUp
    case emailLogin

    var debugName: String {
        switch self {
        case let .login(provider):
            return "login.\(provider.rawValue.lowercased())"
        case .emailSignUp:
            return "emailSignUp"
        case .emailLogin:
            return "emailLogin"
        }
    }

    var title: String {
        switch self {
        case .login, .emailLogin:
            return "로그인 완료"
        case .emailSignUp:
            return "회원가입 완료"
        }
    }

    var symbol: String {
        switch self {
        case .login(.apple):
            return "apple.logo"
        case .login(.google):
            return "globe"
        case .login(.email), .emailSignUp, .emailLogin:
            return "envelope.fill"
        }
    }

    func body(for profile: UserProfile) -> String {
        switch self {
        case .login, .emailLogin:
            return "\(profile.nickname)님이 로그인했습니다."
        case .emailSignUp:
            return "\(profile.nickname)님 가입을 환영합니다."
        }
    }
}

@MainActor
final class AuthFlowViewModel: ObservableObject {
    @Published private(set) var state = AuthFlowState()
    @Published var emailAuthDestination: EmailAuthDestination?

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

    func presentEmailSignUp() {
        clearLandingError()
        emailAuthDestination = .signUp
    }

    func presentEmailLogin() {
        clearLandingError()
        emailAuthDestination = .login
    }

    func dismissEmailAuth() {
        emailAuthDestination = nil
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

    var signupValidationIssues: [SignupValidationIssue] {
        details?["validationErrors"]?.objectArrayValue?.compactMap { item in
            guard let field = item["field"]?.stringValue, !field.isEmpty else { return nil }
            let message = item["message"]?.stringValue ?? ""
            return SignupValidationIssue(field: field, message: message)
        } ?? []
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

    var objectArrayValue: [[String: JSONValue]]? {
        guard case let .array(values) = self else { return nil }
        return values.compactMap { value in
            guard case let .object(object) = value else { return nil }
            return object
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
        debugLog("completeAuthenticatedSession started event=\(event.debugName) tokenUserId=\(tokens.user.id) tokenEmail=\(tokens.user.email)")

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
            completeGuestOnboarding(resetTabSelection: false)
            pendingAction?()
            debugLog("completeAuthenticatedSession succeeded event=\(event.debugName) userId=\(profile.id) email=\(profile.email)")
            return profile
        } catch {
            let mappedError = AuthErrorMapper.map(error)
            debugLog("completeAuthenticatedSession failed event=\(event.debugName) mappedError=\(String(describing: mappedError))")
            await onSignOut()
            restoreGuestSession()
            throw mappedError
        }
    }
}

private enum OnboardingAccent: String {
    case blue
    case purple
    case gold
    case green
    case orange

    var color: Color {
        switch self {
        case .blue:
            return AppPalette.accentBlue
        case .purple:
            return AppPalette.accentPurple
        case .gold:
            return AppPalette.accentGold
        case .green:
            return AppPalette.accentGreen
        case .orange:
            return AppPalette.accentOrange
        }
    }
}

private struct OnboardingFeatureCardModel: Identifiable {
    let id: String
    let symbolName: String
    let title: String
    let description: String
    let accent: OnboardingAccent
}

private struct OnboardingPageModel: Identifiable {
    let id: String
    let heroSymbolName: String
    let title: String
    let subtitle: String
    let footnote: String
    let accent: OnboardingAccent
    let featureCards: [OnboardingFeatureCardModel]
    let showsActionSection: Bool

    static let `default`: [OnboardingPageModel] = [
        OnboardingPageModel(
            id: "maker",
            heroSymbolName: "shield.lefthalf.filled",
            title: "내전 메이커",
            subtitle: "내전의 완벽한 밸런스",
            footnote: "공개 그룹과 예시 화면은 로그인 없이 먼저 확인할 수 있어요.",
            accent: .blue,
            featureCards: [
                OnboardingFeatureCardModel(id: "auto-balance", symbolName: "scalemass.fill", title: "자동 팀 밸런싱", description: "파워 데이터 기반 5:5 최적 팀 생성", accent: .blue),
                OnboardingFeatureCardModel(id: "lane-balance", symbolName: "chart.bar.xaxis", title: "라인별 밸런스 분석", description: "TOP/JGL/MID/ADC/SUP 포지션별 파워 비교", accent: .purple),
                OnboardingFeatureCardModel(id: "result-rematch", symbolName: "trophy.fill", title: "결과 기록 및 재매칭", description: "내전 결과 빠른 입력, 실력 반영 자동 업데이트", accent: .gold),
                OnboardingFeatureCardModel(id: "recruit", symbolName: "person.3.fill", title: "팀원 · 상대팀 모집", description: "포지션 · 티어 · 성향 매칭으로 빠른 내전 구성", accent: .green),
            ],
            showsActionSection: false
        ),
        OnboardingPageModel(
            id: "position-balance",
            heroSymbolName: "square.grid.3x3.middleleft.filled",
            title: "포지션 기반 빠른 팀 구성",
            subtitle: "TOP / JGL / MID / ADC / SUP 선호 포지션과 티어를 반영해 균형 잡힌 팀을 만듭니다.",
            footnote: "포지션 선호, 오프롤 패널티, 라인별 비교를 함께 보여줍니다.",
            accent: .purple,
            featureCards: [
                OnboardingFeatureCardModel(id: "position-priority", symbolName: "line.3.horizontal.decrease.circle.fill", title: "선호 포지션 우선 배치", description: "모든 플레이어의 메인 라인을 먼저 고려합니다", accent: .purple),
                OnboardingFeatureCardModel(id: "tier-reflect", symbolName: "bolt.circle.fill", title: "티어·파워 반영", description: "라인별 파워 차이를 조합 전부터 확인할 수 있어요", accent: .blue),
                OnboardingFeatureCardModel(id: "lane-visual", symbolName: "waveform.path.ecg", title: "라인별 밸런스 시각화", description: "어느 라인이 기울었는지 빠르게 파악합니다", accent: .gold),
                OnboardingFeatureCardModel(id: "quick-compose", symbolName: "person.2.wave.2.fill", title: "10명 기준 빠른 조합", description: "매치 준비 시간을 줄이고 바로 내전을 시작해요", accent: .green),
            ],
            showsActionSection: false
        ),
        OnboardingPageModel(
            id: "result-flow",
            heroSymbolName: "flag.checkered.2.crossed",
            title: "결과 입력으로 실력 자동 반영",
            subtitle: "내전 결과를 기록하면 이후 매칭에 반영할 수 있도록 설계합니다.",
            footnote: "경기 결과, 승패 반영, 재매칭 흐름이 끊기지 않도록 이어집니다.",
            accent: .gold,
            featureCards: [
                OnboardingFeatureCardModel(id: "quick-record", symbolName: "square.and.pencil", title: "경기 결과 기록", description: "경기 종료 직후 승패와 핵심 결과를 빠르게 남겨요", accent: .gold),
                OnboardingFeatureCardModel(id: "win-loss", symbolName: "checkmark.seal.fill", title: "승패 반영", description: "다음 매치 밸런스에 반영될 기준 데이터를 만듭니다", accent: .green),
                OnboardingFeatureCardModel(id: "rematch-ready", symbolName: "arrow.triangle.2.circlepath.circle.fill", title: "재매칭 준비", description: "같은 멤버로 다시 돌릴 때도 더 자연스럽게 조합됩니다", accent: .blue),
                OnboardingFeatureCardModel(id: "history", symbolName: "clock.arrow.circlepath", title: "기록 히스토리", description: "최근 흐름을 확인하고 다음 게임을 더 빨리 준비합니다", accent: .purple),
            ],
            showsActionSection: false
        ),
        OnboardingPageModel(
            id: "guest-first",
            heroSymbolName: "sparkles.rectangle.stack.fill",
            title: "로그인 없이 먼저 둘러보고,\n필요할 때 시작하세요",
            subtitle: "비로그인으로 핵심 화면을 먼저 체험하고, 저장/생성/기록 기능이 필요할 때 로그인 또는 회원가입할 수 있어요.",
            footnote: "핵심 가치는 먼저 보여주고, 계정 연결은 필요한 순간에 안내합니다.",
            accent: .green,
            featureCards: [
                OnboardingFeatureCardModel(id: "guest-home", symbolName: "house.fill", title: "홈과 공개 그룹 둘러보기", description: "앱 구조와 핵심 흐름을 읽기 전용으로 먼저 체험", accent: .blue),
                OnboardingFeatureCardModel(id: "guest-recruit", symbolName: "megaphone.fill", title: "공개 모집글 확인", description: "모집 목록과 공개 팀 조합 예시를 바로 확인", accent: .orange),
                OnboardingFeatureCardModel(id: "guest-preview", symbolName: "eye.fill", title: "밸런스·결과 예시 보기", description: "로그인 없이도 팀 조합과 결과 입력 흐름 미리보기", accent: .green),
            ],
            showsActionSection: true
        ),
    ]
}

enum FieldValidationState: Equatable {
    case idle
    case validating(String)
    case valid(String)
    case invalid(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case let .validating(message), let .valid(message), let .invalid(message):
            return message
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return AppPalette.textMuted
        case .validating:
            return AppPalette.accentBlue
        case .valid:
            return AppPalette.accentGreen
        case .invalid:
            return AppPalette.accentRed
        }
    }

    var iconName: String? {
        switch self {
        case .idle:
            return nil
        case .validating:
            return "clock.arrow.circlepath"
        case .valid:
            return "checkmark.circle.fill"
        case .invalid:
            return "exclamationmark.circle.fill"
        }
    }

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

struct EmailAuthTermsState: Equatable {
    var hasAcceptedServiceTerms = false
    var hasAcceptedPrivacyPolicy = false
    var hasAcceptedMarketing = false
    var hasAttemptedValidation = false

    var hasAcceptedRequiredTerms: Bool {
        hasAcceptedServiceTerms && hasAcceptedPrivacyPolicy
    }

    var isAllSelected: Bool {
        hasAcceptedServiceTerms && hasAcceptedPrivacyPolicy && hasAcceptedMarketing
    }

    var validationState: FieldValidationState {
        guard hasAttemptedValidation else { return .idle }
        if hasAcceptedRequiredTerms {
            return .valid("필수 약관 동의가 완료되었습니다")
        }
        return .invalid("서비스 이용약관과 개인정보 처리방침에 동의해 주세요")
    }
}

enum EmailSignUpField: Hashable {
    case email
    case password
    case passwordConfirmation
    case nickname
}

enum EmailLoginField: Hashable {
    case email
    case password
}

struct EmailSignUpFormState: Equatable {
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var nickname = ""
    var emailValidation: FieldValidationState = .idle
    var passwordValidation: FieldValidationState = .idle
    var passwordConfirmationValidation: FieldValidationState = .idle
    var nicknameValidation: FieldValidationState = .idle
    var hasEditedEmail = false
    var hasEditedPassword = false
    var hasEditedPasswordConfirmation = false
    var hasEditedNickname = false
    var termsState = EmailAuthTermsState()
    var isPasswordVisible = false
    var isPasswordConfirmationVisible = false
    var formError: PresentationError?
    var providerConflict: ProviderConflictError?
    var submittingState: SubmittingState = .idle

    var isSubmitEnabled: Bool {
        emailValidation.isValid &&
            passwordValidation.isValid &&
            passwordConfirmationValidation.isValid &&
            nicknameValidation.isValid &&
            termsState.hasAcceptedRequiredTerms &&
            !submittingState.isLoading
    }
}

struct EmailLoginFormState: Equatable {
    var email = ""
    var password = ""
    var emailValidation: FieldValidationState = .idle
    var passwordValidation: FieldValidationState = .idle
    var hasEditedEmail = false
    var hasEditedPassword = false
    var isPasswordVisible = false
    var formError: PresentationError?
    var providerConflict: ProviderConflictError?
    var submittingState: SubmittingState = .idle

    var isSubmitEnabled: Bool {
        emailValidation.isValid && passwordValidation.isValid && !submittingState.isLoading
    }
}

enum EmailAuthValidator {
    static func validateEmail(_ rawValue: String) -> FieldValidationState {
        let normalizedValue = normalizedEmail(rawValue)
        guard !normalizedValue.isEmpty else {
            return .invalid("이메일을 입력해 주세요")
        }

        let emailPattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        guard normalizedValue.range(of: emailPattern, options: .regularExpression) != nil else {
            return .invalid("올바른 이메일 형식이 아닙니다")
        }

        return .valid("사용 가능한 이메일 형식입니다")
    }

    static func validatePasswordForSignUp(_ rawValue: String) -> FieldValidationState {
        guard !rawValue.isEmpty else {
            return .invalid("비밀번호를 입력해 주세요")
        }

        guard rawValue.count >= 8 else {
            return .invalid("비밀번호는 8자 이상이어야 합니다")
        }

        let containsAlphabet = rawValue.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let containsNumber = rawValue.range(of: #"[0-9]"#, options: .regularExpression) != nil
        let containsSpecialCharacter = rawValue.range(of: #"[!@#$%^&*()_\+\-=\[\]{};':"\\|,.<>\/?]"#, options: .regularExpression) != nil

        guard containsAlphabet && containsNumber && containsSpecialCharacter else {
            return .invalid("영문, 숫자, 특수문자를 모두 포함해 주세요")
        }

        return .valid("사용 가능한 비밀번호입니다")
    }

    static func validatePasswordConfirmation(password: String, confirmation: String) -> FieldValidationState {
        guard !confirmation.isEmpty else {
            return .invalid("비밀번호를 다시 입력해 주세요")
        }

        guard password == confirmation else {
            return .invalid("비밀번호가 일치하지 않습니다")
        }

        return .valid("비밀번호가 일치합니다")
    }

    static func validateNickname(_ rawValue: String) -> FieldValidationState {
        let normalizedValue = normalizedNickname(rawValue)
        guard !normalizedValue.isEmpty else {
            return .invalid("닉네임을 입력해 주세요")
        }

        guard normalizedValue.count >= 2 && normalizedValue.count <= 12 else {
            return .invalid("닉네임은 2자 이상 12자 이하로 입력해 주세요")
        }

        let nicknamePattern = #"^[A-Za-z0-9가-힣]+$"#
        guard normalizedValue.range(of: nicknamePattern, options: .regularExpression) != nil else {
            return .invalid("한글, 영문, 숫자만 사용할 수 있습니다")
        }

        return .valid("사용 가능한 닉네임 형식입니다")
    }

    static func validatePasswordForLogin(_ rawValue: String) -> FieldValidationState {
        guard !rawValue.isEmpty else {
            return .invalid("비밀번호를 입력해 주세요")
        }
        return .valid("비밀번호를 입력했습니다")
    }

    static func normalizedEmail(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizedNickname(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class EmailSignUpViewModel: ObservableObject {
    @Published private(set) var state = EmailSignUpFormState()

    private let session: AppSessionViewModel

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func updateEmail(_ text: String) {
        clearSubmissionFeedback()
        state.email = text
        if state.hasEditedEmail || !text.isEmpty {
            state.hasEditedEmail = true
            state.emailValidation = EmailAuthValidator.validateEmail(text)
        }
    }

    func updatePassword(_ text: String) {
        clearSubmissionFeedback()
        state.password = text
        if state.hasEditedPassword || !text.isEmpty {
            state.hasEditedPassword = true
            state.passwordValidation = EmailAuthValidator.validatePasswordForSignUp(text)
        }
        if state.hasEditedPasswordConfirmation {
            state.passwordConfirmationValidation = EmailAuthValidator.validatePasswordConfirmation(
                password: state.password,
                confirmation: state.passwordConfirmation
            )
        }
    }

    func updatePasswordConfirmation(_ text: String) {
        clearSubmissionFeedback()
        state.passwordConfirmation = text
        if state.hasEditedPasswordConfirmation || !text.isEmpty {
            state.hasEditedPasswordConfirmation = true
            state.passwordConfirmationValidation = EmailAuthValidator.validatePasswordConfirmation(
                password: state.password,
                confirmation: text
            )
        }
    }

    func updateNickname(_ text: String) {
        clearSubmissionFeedback()
        state.nickname = text
        if state.hasEditedNickname || !text.isEmpty {
            state.hasEditedNickname = true
            state.nicknameValidation = EmailAuthValidator.validateNickname(text)
        }
    }

    func handleFocusChange(from previousField: EmailSignUpField?, to _: EmailSignUpField?) {
        guard let previousField else { return }
        markFieldAsEdited(previousField)
        validate(field: previousField)
    }

    func togglePasswordVisibility() {
        state.isPasswordVisible.toggle()
    }

    func togglePasswordConfirmationVisibility() {
        state.isPasswordConfirmationVisible.toggle()
    }

    func toggleAllTerms() {
        let shouldSelectAll = !state.termsState.isAllSelected
        state.termsState.hasAcceptedServiceTerms = shouldSelectAll
        state.termsState.hasAcceptedPrivacyPolicy = shouldSelectAll
        state.termsState.hasAcceptedMarketing = shouldSelectAll
        if state.termsState.hasAttemptedValidation {
            state.termsState.hasAttemptedValidation = true
        }
    }

    func toggleServiceTerms() {
        state.termsState.hasAcceptedServiceTerms.toggle()
    }

    func togglePrivacyTerms() {
        state.termsState.hasAcceptedPrivacyPolicy.toggle()
    }

    func toggleMarketingTerms() {
        state.termsState.hasAcceptedMarketing.toggle()
    }

    func submit() async {
        clearSubmissionFeedback()
        validateAll(force: true)

        guard state.isSubmitEnabled else { return }

        state.submittingState = .loading("회원가입 정보를 확인하고 있습니다")
        state.emailValidation = .validating("이메일 계정을 생성하고 있습니다")

        do {
            let tokens = try await session.container.authRepository.signUpWithEmail(
                email: EmailAuthValidator.normalizedEmail(state.email),
                password: state.password,
                nickname: EmailAuthValidator.normalizedNickname(state.nickname),
                agreedToTerms: state.termsState.hasAcceptedServiceTerms,
                agreedToPrivacy: state.termsState.hasAcceptedPrivacyPolicy,
                agreedToMarketing: state.termsState.hasAcceptedMarketing
            )
            _ = try await session.completeAuthenticatedSession(tokens: tokens, event: .emailSignUp)
            state.submittingState = .idle
            state.emailValidation = EmailAuthValidator.validateEmail(state.email)
        } catch {
            handleFailure(error)
        }
    }

    private func handleFailure(_ error: Error) {
        state.submittingState = .idle
        state.emailValidation = EmailAuthValidator.validateEmail(state.email)

        let authError = AuthErrorMapper.map(error)
        if let providerConflict = authError.providerConflict {
            state.providerConflict = providerConflict
            state.formError = authError.presentationError
            return
        }

        switch authError {
        case .emailAlreadyInUse:
            state.emailValidation = .invalid("이미 가입된 이메일입니다")
            return
        case .nicknameAlreadyInUse:
            state.nicknameValidation = .invalid("이미 사용 중인 닉네임입니다")
            return
        case let .invalidEmailFormat(message):
            state.emailValidation = .invalid(message ?? "올바른 이메일 형식이 아닙니다")
            return
        case let .weakPassword(message):
            state.passwordValidation = .invalid(message ?? "비밀번호 조건을 만족해 주세요")
            return
        case .requiredTermsNotAgreed:
            state.termsState.hasAttemptedValidation = true
            return
        case let .invalidPayload(issues, message):
            if applyServerValidationIssues(issues) {
                return
            }
            state.formError = PresentationError(
                title: "입력값을 다시 확인해 주세요",
                message: message ?? "입력한 회원가입 정보를 다시 확인한 뒤 다시 시도해 주세요."
            )
            return
        case .networkOffline, .networkTimeout, .rateLimited, .serverUnavailable, .networkError, .emailAuthDisabled, .passwordAuthDisabled:
            state.formError = authError.presentationError
            return
        case .unsupportedProvider:
            state.formError = authError.presentationError
            return
        case .invalidCredentials:
            state.formError = PresentationError(title: "회원가입 정보를 확인해 주세요", message: "입력한 정보를 다시 확인한 뒤 다시 시도해 주세요.")
            return
        case .accountNotFound:
            state.formError = authError.presentationError
            return
        case .socialTokenInvalid, .accountExistsWithApple, .accountExistsWithGoogle, .authProviderMismatch, .authRequired:
            state.formError = authError.presentationError
            return
        case .unknown:
            break
        }

        state.formError = PresentationError(title: "회원가입에 실패했어요", message: "잠시 후 다시 시도해 주세요.")
    }

    private func clearSubmissionFeedback() {
        state.formError = nil
        state.providerConflict = nil
    }

    private func validateAll(force: Bool) {
        if force {
            state.hasEditedEmail = true
            state.hasEditedPassword = true
            state.hasEditedPasswordConfirmation = true
            state.hasEditedNickname = true
            state.termsState.hasAttemptedValidation = true
        }
        validate(field: .email)
        validate(field: .password)
        validate(field: .passwordConfirmation)
        validate(field: .nickname)
    }

    private func validate(field: EmailSignUpField) {
        switch field {
        case .email:
            state.emailValidation = state.hasEditedEmail ? EmailAuthValidator.validateEmail(state.email) : .idle
        case .password:
            state.passwordValidation = state.hasEditedPassword ? EmailAuthValidator.validatePasswordForSignUp(state.password) : .idle
        case .passwordConfirmation:
            state.passwordConfirmationValidation = state.hasEditedPasswordConfirmation
                ? EmailAuthValidator.validatePasswordConfirmation(password: state.password, confirmation: state.passwordConfirmation)
                : .idle
        case .nickname:
            state.nicknameValidation = state.hasEditedNickname ? EmailAuthValidator.validateNickname(state.nickname) : .idle
        }
    }

    private func markFieldAsEdited(_ field: EmailSignUpField) {
        switch field {
        case .email:
            state.hasEditedEmail = true
        case .password:
            state.hasEditedPassword = true
        case .passwordConfirmation:
            state.hasEditedPasswordConfirmation = true
        case .nickname:
            state.hasEditedNickname = true
        }
    }

    private func applyServerValidationIssues(_ issues: [SignupValidationIssue]) -> Bool {
        guard !issues.isEmpty else { return false }

        var appliedFieldError = false
        var remainingMessages: [String] = []

        for issue in issues {
            switch issue.field {
            case "email":
                state.emailValidation = .invalid(issue.message)
                appliedFieldError = true
            case "password":
                state.passwordValidation = .invalid(issue.message)
                appliedFieldError = true
            case "nickname":
                state.nicknameValidation = .invalid(issue.message)
                appliedFieldError = true
            case "agreedToTerms", "agreedToPrivacy":
                state.termsState.hasAttemptedValidation = true
                appliedFieldError = true
            default:
                if !issue.message.isEmpty {
                    remainingMessages.append(issue.message)
                }
            }
        }

        if !remainingMessages.isEmpty {
            state.formError = PresentationError(
                title: "입력값을 다시 확인해 주세요",
                message: remainingMessages.joined(separator: "\n")
            )
        }

        return appliedFieldError
    }
}

@MainActor
final class EmailLoginViewModel: ObservableObject {
    @Published private(set) var state = EmailLoginFormState()

    private let session: AppSessionViewModel

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func updateEmail(_ text: String) {
        clearSubmissionFeedback()
        state.email = text
        if state.hasEditedEmail || !text.isEmpty {
            state.hasEditedEmail = true
            state.emailValidation = EmailAuthValidator.validateEmail(text)
        }
    }

    func updatePassword(_ text: String) {
        clearSubmissionFeedback()
        state.password = text
        if state.hasEditedPassword || !text.isEmpty {
            state.hasEditedPassword = true
            state.passwordValidation = EmailAuthValidator.validatePasswordForLogin(text)
        }
    }

    func handleFocusChange(from previousField: EmailLoginField?, to _: EmailLoginField?) {
        guard let previousField else { return }
        markFieldAsEdited(previousField)
        validate(field: previousField)
    }

    func togglePasswordVisibility() {
        state.isPasswordVisible.toggle()
    }

    func submit() async {
        let normalizedEmail = EmailAuthValidator.normalizedEmail(state.email)
        debugLog("submitTapped email=\(normalizedEmail) passwordLength=\(state.password.count)")
        clearSubmissionFeedback()
        validateAll(force: true)

        guard state.isSubmitEnabled else {
            debugLog(
                "submitBlocked email=\(normalizedEmail) emailValidation=\(String(describing: state.emailValidation)) passwordValidation=\(String(describing: state.passwordValidation))"
            )
            return
        }

        state.submittingState = .loading("로그인 정보를 확인하고 있습니다")
        debugLog("requestPrepared endpoint=/auth/login/email email=\(normalizedEmail) passwordLength=\(state.password.count)")
        do {
            let tokens = try await session.container.authRepository.loginWithEmail(
                email: normalizedEmail,
                password: state.password
            )
            debugLog("loginRequestSucceeded userId=\(tokens.user.id) email=\(tokens.user.email)")
            _ = try await session.completeAuthenticatedSession(tokens: tokens, event: .emailLogin)
            debugLog("sessionBootstrapSucceeded userId=\(tokens.user.id) email=\(tokens.user.email)")
            state.submittingState = .idle
        } catch {
            handleFailure(error, attemptedEmail: normalizedEmail)
        }
    }

    private func handleFailure(_ error: Error, attemptedEmail: String) {
        state.submittingState = .idle

        let authError = AuthErrorMapper.map(error)
        debugLog("loginFlowFailed email=\(attemptedEmail) mappedError=\(String(describing: authError))")
        if let providerConflict = authError.providerConflict {
            state.providerConflict = providerConflict
            state.formError = authError.presentationError
            return
        }

        switch authError {
        case .accountNotFound:
            state.emailValidation = .invalid("가입된 계정을 찾을 수 없습니다")
            state.formError = authError.presentationError
            return
        case .invalidCredentials:
            state.passwordValidation = .invalid("이메일 또는 비밀번호가 일치하지 않습니다")
            state.formError = PresentationError(title: "로그인 정보를 다시 확인해 주세요", message: "이메일 또는 비밀번호가 일치하지 않습니다.")
            return
        case let .invalidEmailFormat(message):
            state.emailValidation = .invalid(message ?? "올바른 이메일 형식이 아닙니다")
            return
        case let .invalidPayload(issues, message):
            if let emailIssue = issues.first(where: { $0.field == "email" }) {
                state.emailValidation = .invalid(emailIssue.message)
                return
            }
            if let passwordIssue = issues.first(where: { $0.field == "password" }) {
                state.passwordValidation = .invalid(passwordIssue.message)
                return
            }
            state.formError = PresentationError(
                title: "로그인 정보를 확인해 주세요",
                message: message ?? "입력한 로그인 정보를 다시 확인해 주세요."
            )
            return
        case .unsupportedProvider, .networkOffline, .networkTimeout, .rateLimited, .serverUnavailable, .networkError, .emailAuthDisabled, .passwordAuthDisabled:
            state.formError = authError.presentationError
            return
        case .emailAlreadyInUse, .nicknameAlreadyInUse, .weakPassword, .requiredTermsNotAgreed:
            state.formError = authError.presentationError
            return
        case .socialTokenInvalid, .accountExistsWithApple, .accountExistsWithGoogle, .authProviderMismatch, .authRequired:
            state.formError = authError.presentationError
            return
        case .unknown:
            break
        }

        state.formError = PresentationError(title: "로그인에 실패했어요", message: "잠시 후 다시 시도해 주세요.")
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[EmailLoginViewModel] \(message)")
#endif
    }

    private func clearSubmissionFeedback() {
        state.formError = nil
        state.providerConflict = nil
    }

    private func validateAll(force: Bool) {
        if force {
            state.hasEditedEmail = true
            state.hasEditedPassword = true
        }
        validate(field: .email)
        validate(field: .password)
    }

    private func validate(field: EmailLoginField) {
        switch field {
        case .email:
            state.emailValidation = state.hasEditedEmail ? EmailAuthValidator.validateEmail(state.email) : .idle
        case .password:
            state.passwordValidation = state.hasEditedPassword ? EmailAuthValidator.validatePasswordForLogin(state.password) : .idle
        }
    }

    private func markFieldAsEdited(_ field: EmailLoginField) {
        switch field {
        case .email:
            state.hasEditedEmail = true
        case .password:
            state.hasEditedPassword = true
        }
    }
}

struct OnboardingLandingView: View {
    @ObservedObject private var session: AppSessionViewModel
    @StateObject private var viewModel: AuthFlowViewModel
    @State private var selectedPageIndex = 0
    private let pages = OnboardingPageModel.default

    init(session: AppSessionViewModel) {
        self.session = session
        _viewModel = StateObject(wrappedValue: AuthFlowViewModel(session: session))
    }

    private var isLastPage: Bool {
        selectedPageIndex == pages.count - 1
    }

    private var currentPage: OnboardingPageModel {
        pages[selectedPageIndex]
    }

    var body: some View {
        ZStack {
            OnboardingBackdropView(accent: currentPage.accent.color)

            VStack(spacing: 0) {
                StatusBarView()

                HStack {
                    Spacer()
                    if !isLastPage {
                        Button("건너뛰기") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedPageIndex = pages.count - 1
                            }
                        }
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(AppPalette.bgSecondary.opacity(0.92))
                        .clipShape(Capsule())
                        .padding(.top, 12)
                        .padding(.trailing, 24)
                    }
                }
                .frame(height: 44)

                TabView(selection: $selectedPageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(
                            page: page,
                            session: session,
                            viewModel: viewModel
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 16) {
                    OnboardingPageIndicator(pageCount: pages.count, currentPageIndex: selectedPageIndex)

                    if !isLastPage {
                        HStack(spacing: 12) {
                            Button("건너뛰기") {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedPageIndex = pages.count - 1
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("다음") {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedPageIndex = min(selectedPageIndex + 1, pages.count - 1)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }

            if viewModel.isBusy {
                AuthBlockingProgressView(title: viewModel.progressTitle)
            }
        }
        .fullScreenCover(item: $viewModel.emailAuthDestination) { destination in
            EmailAuthFlowContainer(
                session: session,
                authViewModel: viewModel,
                initialDestination: destination
            )
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

                AuthPromptActionSection(
                    viewModel: viewModel,
                    prompt: prompt,
                    showsSkipButton: true,
                    onSkip: { session.dismissAuthPrompt() }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            if viewModel.isBusy {
                AuthBlockingProgressView(title: viewModel.progressTitle)
            }
        }
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
        .fullScreenCover(item: $viewModel.emailAuthDestination) { destination in
            EmailAuthFlowContainer(
                session: session,
                authViewModel: viewModel,
                initialDestination: destination
            )
        }
    }
}

struct AuthInlineAccessCard: View {
    private let title: String
    private let message: String
    @StateObject private var viewModel: AuthFlowViewModel
    @ObservedObject private var session: AppSessionViewModel

    init(session: AppSessionViewModel, title: String, message: String) {
        self.title = title
        self.message = message
        self.session = session
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

                AuthPromptActionSection(
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
        .fullScreenCover(item: $viewModel.emailAuthDestination) { destination in
            EmailAuthFlowContainer(
                session: session,
                authViewModel: viewModel,
                initialDestination: destination
            )
        }
    }
}

private struct OnboardingBackdropView: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.bgPrimary, AppPalette.bgSecondary, AppPalette.bgPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(accent.opacity(0.32))
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: 120, y: -240)

            Circle()
                .fill(AppPalette.accentBlue.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 100)
                .offset(x: -120, y: 260)
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPageModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var viewModel: AuthFlowViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28)
                                .fill(page.accent.color.opacity(0.18))
                                .frame(width: 112, height: 112)
                            RoundedRectangle(cornerRadius: 26)
                                .fill(page.accent.color)
                                .frame(width: 88, height: 88)
                            Image(systemName: page.heroSymbolName)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color.white)
                        }

                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(AppTypography.heading(33, weight: .heavy))
                                .tracking(1)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(AppPalette.textPrimary)

                            Text(page.subtitle)
                                .font(AppTypography.body(15))
                                .foregroundStyle(AppPalette.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.top, 36)

                    VStack(spacing: 14) {
                        ForEach(page.featureCards) { featureCard in
                            OnboardingFeatureCardView(card: featureCard)
                        }
                    }

                    Text(page.footnote)
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    if page.showsActionSection {
                        OnboardingFinalActionSection(session: session, viewModel: viewModel)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, page.showsActionSection ? 24 : 36)
            }
        }
    }
}

private struct OnboardingFeatureCardView: View {
    let card: OnboardingFeatureCardModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: card.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(card.accent.color)
                .frame(width: 44, height: 44)
                .background(AppPalette.bgSecondary.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(AppTypography.body(15, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(card.description)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.bgCard.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct OnboardingFinalActionSection: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var viewModel: AuthFlowViewModel

    var body: some View {
        VStack(spacing: 12) {
            AuthEntryFeedbackSection(viewModel: viewModel)

            Button("비로그인으로 둘러보기") {
                session.completeGuestOnboarding()
            }
            .buttonStyle(PrimaryButtonStyle())

            AuthEntryOptionsGroup(viewModel: viewModel)

            Text("저장, 생성, 결과 기록, 참여 신청 같은 개인화 기능은 로그인 후 이어서 사용할 수 있어요.")
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 4)
        }
    }
}

private struct OnboardingPageIndicator: View {
    let pageCount: Int
    let currentPageIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(0..<pageCount), id: \.self) { index in
                Capsule()
                    .fill(index == currentPageIndex ? AppPalette.accentBlue : AppPalette.border)
                    .frame(width: index == currentPageIndex ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentPageIndex)
            }
        }
    }
}

private struct AuthPromptActionSection: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    let prompt: AuthPromptContext?
    let showsSkipButton: Bool
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            AuthEntryFeedbackSection(viewModel: viewModel)

            AuthEntryOptionsGroup(viewModel: viewModel)

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

private struct AuthEntryOptionsGroup: View {
    @ObservedObject var viewModel: AuthFlowViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.presentEmailSignUp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                    Text("이메일로 회원가입")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isBusy)

            Button {
                viewModel.presentEmailLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                    Text("이메일로 로그인")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isBusy)

            AuthSocialButtonsGroup(viewModel: viewModel)
        }
    }
}

private struct AuthEntryFeedbackSection: View {
    @ObservedObject var viewModel: AuthFlowViewModel

    var body: some View {
        VStack(spacing: 12) {
            if let presentationError = viewModel.landingPresentationError {
                AuthBanner(title: presentationError.title, message: presentationError.message, tint: AppPalette.accentRed)
            }

            if let conflict = viewModel.currentProviderConflict {
                SuggestedProviderPanel(
                    conflict: conflict,
                    onEmailLoginTap: { viewModel.presentEmailLogin() },
                    onGoogleTap: { viewModel.startGoogleLogin() },
                    onAppleCompletion: viewModel.handleAppleAuthorizationResult
                )
            }
        }
    }
}

private struct AuthSocialButtonsGroup: View {
    @ObservedObject var viewModel: AuthFlowViewModel

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                viewModel.handleAppleAuthorizationResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(viewModel.isBusy)

            Button {
                viewModel.startGoogleLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Google로 계속하기")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isBusy)
        }
    }
}

private struct EmailAuthFlowContainer: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var authViewModel: AuthFlowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentDestination: EmailAuthDestination
    @StateObject private var signUpViewModel: EmailSignUpViewModel
    @StateObject private var loginViewModel: EmailLoginViewModel

    init(session: AppSessionViewModel, authViewModel: AuthFlowViewModel, initialDestination: EmailAuthDestination) {
        self.session = session
        self.authViewModel = authViewModel
        _currentDestination = State(initialValue: initialDestination)
        _signUpViewModel = StateObject(wrappedValue: EmailSignUpViewModel(session: session))
        _loginViewModel = StateObject(wrappedValue: EmailLoginViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.bgPrimary
                    .ignoresSafeArea()

                Group {
                    switch currentDestination {
                    case .signUp:
                        EmailSignUpScreen(
                            authViewModel: authViewModel,
                            viewModel: signUpViewModel,
                            onSwitchToLogin: { withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .login } }
                        )
                    case .login:
                        EmailLoginScreen(
                            authViewModel: authViewModel,
                            viewModel: loginViewModel,
                            onSwitchToSignUp: { withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .signUp } }
                        )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        authViewModel.dismissEmailAuth()
                        dismiss()
                    }
                }
            }
            .navigationTitle(currentDestination == .signUp ? "이메일 회원가입" : "이메일 로그인")
            .appNavigationBarStyle(.inline)
        }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            authViewModel.dismissEmailAuth()
            dismiss()
        }
    }
}

private struct EmailSignUpScreen: View {
    @ObservedObject var authViewModel: AuthFlowViewModel
    @ObservedObject var viewModel: EmailSignUpViewModel
    let onSwitchToLogin: () -> Void
    @FocusState private var focusedField: EmailSignUpField?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                authHeader(
                    title: "실시간으로 조건을 확인하면서 가입할 수 있어요",
                    subtitle: "이메일, 비밀번호, 닉네임 상태를 바로 확인하고 계정을 만드세요."
                )

                if let formError = viewModel.state.formError {
                    AuthBanner(title: formError.title, message: formError.message, tint: AppPalette.accentRed)
                }

                if let providerConflict = viewModel.state.providerConflict {
                    SuggestedProviderPanel(
                        conflict: providerConflict,
                        onEmailLoginTap: onSwitchToLogin,
                        onGoogleTap: { authViewModel.startGoogleLogin() },
                        onAppleCompletion: authViewModel.handleAppleAuthorizationResult
                    )
                }

                VStack(spacing: 18) {
                    AuthInputFieldView(
                        title: "이메일",
                        text: Binding(get: { viewModel.state.email }, set: { viewModel.updateEmail($0) }),
                        placeholder: "name@example.com",
                        helperText: "가입에 사용할 이메일을 입력해 주세요",
                        validationState: viewModel.state.emailValidation,
                        focusedField: $focusedField,
                        field: .email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        textInputAutocapitalization: .never,
                        submitLabel: .next,
                        onSubmit: { focusedField = .password }
                    )

                    AuthInputFieldView(
                        title: "비밀번호",
                        text: Binding(get: { viewModel.state.password }, set: { viewModel.updatePassword($0) }),
                        placeholder: "8자 이상, 영문/숫자/특수문자 포함",
                        helperText: "8자 이상, 영문·숫자·특수문자를 모두 포함해 주세요",
                        validationState: viewModel.state.passwordValidation,
                        focusedField: $focusedField,
                        field: .password,
                        keyboardType: .default,
                        textContentType: .newPassword,
                        textInputAutocapitalization: .never,
                        submitLabel: .next,
                        isSecureEntry: true,
                        isTextVisible: viewModel.state.isPasswordVisible,
                        visibilityToggleAction: { viewModel.togglePasswordVisibility() },
                        onSubmit: { focusedField = .passwordConfirmation }
                    )

                    AuthInputFieldView(
                        title: "비밀번호 확인",
                        text: Binding(get: { viewModel.state.passwordConfirmation }, set: { viewModel.updatePasswordConfirmation($0) }),
                        placeholder: "비밀번호를 다시 입력해 주세요",
                        helperText: "위에서 입력한 비밀번호와 동일하게 입력해 주세요",
                        validationState: viewModel.state.passwordConfirmationValidation,
                        focusedField: $focusedField,
                        field: .passwordConfirmation,
                        keyboardType: .default,
                        textContentType: .newPassword,
                        textInputAutocapitalization: .never,
                        submitLabel: .next,
                        isSecureEntry: true,
                        isTextVisible: viewModel.state.isPasswordConfirmationVisible,
                        visibilityToggleAction: { viewModel.togglePasswordConfirmationVisibility() },
                        onSubmit: { focusedField = .nickname }
                    )

                    AuthInputFieldView(
                        title: "닉네임",
                        text: Binding(get: { viewModel.state.nickname }, set: { viewModel.updateNickname($0) }),
                        placeholder: "2~12자, 한글/영문/숫자",
                        helperText: "2자 이상 12자 이하, 한글·영문·숫자만 사용할 수 있어요",
                        validationState: viewModel.state.nicknameValidation,
                        focusedField: $focusedField,
                        field: .nickname,
                        keyboardType: .default,
                        textContentType: .nickname,
                        textInputAutocapitalization: .never,
                        submitLabel: .done,
                        onSubmit: {
                            focusedField = nil
                            Task { await viewModel.submit() }
                        }
                    )
                }

                TermsAgreementCard(viewModel: viewModel)

                VStack(spacing: 14) {
                    AuthDividerLabel(title: "또는 소셜로 빠르게 시작")

                    AuthEntryFeedbackSection(viewModel: authViewModel)
                    AuthSocialButtonsGroup(viewModel: authViewModel)
                }

                HStack(spacing: 4) {
                    Text("이미 계정이 있나요?")
                        .foregroundStyle(AppPalette.textSecondary)
                    Button("로그인") {
                        onSwitchToLogin()
                    }
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.accentBlue)
                }
                .font(AppTypography.body(13))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 140)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focusedField) { previousField, currentField in
            viewModel.handleFocusChange(from: previousField, to: currentField)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    focusedField = nil
                    Task { await viewModel.submit() }
                } label: {
                    Text(viewModel.state.submittingState.isLoading ? "회원가입 중..." : "회원가입 완료하기")
                }
                .buttonStyle(PrimaryButtonStyle(fill: viewModel.state.isSubmitEnabled ? AppPalette.accentBlue : AppPalette.bgTertiary))
                .disabled(!viewModel.state.isSubmitEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(AppPalette.bgPrimary.opacity(0.96))
        }
        .overlay {
            if viewModel.state.submittingState.isLoading {
                AuthBlockingProgressView(title: viewModel.state.submittingState.title ?? "회원가입 중입니다")
            }
        }
    }
}

private struct EmailLoginScreen: View {
    @ObservedObject var authViewModel: AuthFlowViewModel
    @ObservedObject var viewModel: EmailLoginViewModel
    let onSwitchToSignUp: () -> Void
    @FocusState private var focusedField: EmailLoginField?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                authHeader(
                    title: "기존 계정으로 다시 이어서 사용하세요",
                    subtitle: "이메일과 비밀번호로 로그인하고 저장된 기록과 개인화 기능을 이어갑니다."
                )

                if let formError = viewModel.state.formError {
                    AuthBanner(title: formError.title, message: formError.message, tint: AppPalette.accentRed)
                }

                if let providerConflict = viewModel.state.providerConflict {
                    SuggestedProviderPanel(
                        conflict: providerConflict,
                        onEmailLoginTap: nil,
                        onGoogleTap: { authViewModel.startGoogleLogin() },
                        onAppleCompletion: authViewModel.handleAppleAuthorizationResult
                    )
                }

                VStack(spacing: 18) {
                    AuthInputFieldView(
                        title: "이메일",
                        text: Binding(get: { viewModel.state.email }, set: { viewModel.updateEmail($0) }),
                        placeholder: "name@example.com",
                        helperText: "가입한 이메일 주소를 입력해 주세요",
                        validationState: viewModel.state.emailValidation,
                        focusedField: $focusedField,
                        field: .email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        textInputAutocapitalization: .never,
                        submitLabel: .next,
                        onSubmit: { focusedField = .password }
                    )

                    AuthInputFieldView(
                        title: "비밀번호",
                        text: Binding(get: { viewModel.state.password }, set: { viewModel.updatePassword($0) }),
                        placeholder: "비밀번호를 입력해 주세요",
                        helperText: "가입할 때 사용한 비밀번호를 입력해 주세요",
                        validationState: viewModel.state.passwordValidation,
                        focusedField: $focusedField,
                        field: .password,
                        keyboardType: .default,
                        textContentType: .password,
                        textInputAutocapitalization: .never,
                        submitLabel: .done,
                        isSecureEntry: true,
                        isTextVisible: viewModel.state.isPasswordVisible,
                        visibilityToggleAction: { viewModel.togglePasswordVisibility() },
                        onSubmit: {
                            focusedField = nil
                            Task { await viewModel.submit() }
                        }
                    )
                }

                VStack(spacing: 14) {
                    AuthDividerLabel(title: "또는 소셜로 계속하기")

                    AuthEntryFeedbackSection(viewModel: authViewModel)
                    AuthSocialButtonsGroup(viewModel: authViewModel)
                }

                HStack(spacing: 4) {
                    Text("아직 계정이 없나요?")
                        .foregroundStyle(AppPalette.textSecondary)
                    Button("회원가입") {
                        onSwitchToSignUp()
                    }
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.accentBlue)
                }
                .font(AppTypography.body(13))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 140)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focusedField) { previousField, currentField in
            viewModel.handleFocusChange(from: previousField, to: currentField)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    focusedField = nil
                    Task { await viewModel.submit() }
                } label: {
                    Text(viewModel.state.submittingState.isLoading ? "로그인 중..." : "로그인")
                }
                .buttonStyle(PrimaryButtonStyle(fill: viewModel.state.isSubmitEnabled ? AppPalette.accentBlue : AppPalette.bgTertiary))
                .disabled(!viewModel.state.isSubmitEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(AppPalette.bgPrimary.opacity(0.96))
        }
        .overlay {
            if viewModel.state.submittingState.isLoading {
                AuthBlockingProgressView(title: viewModel.state.submittingState.title ?? "로그인 중입니다")
            }
        }
    }
}

private struct TermsAgreementCard: View {
    @ObservedObject var viewModel: EmailSignUpViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                viewModel.toggleAllTerms()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.state.termsState.isAllSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.state.termsState.isAllSelected ? AppPalette.accentBlue : AppPalette.textMuted)
                    Text("전체 동의")
                        .font(AppTypography.body(15, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Spacer()
                    Text("필수 + 선택")
                        .font(AppTypography.body(11))
                        .foregroundStyle(AppPalette.textMuted)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(AppPalette.border)

            VStack(spacing: 12) {
                TermsAgreementRow(
                    title: "서비스 이용약관 동의",
                    isRequired: true,
                    isAccepted: viewModel.state.termsState.hasAcceptedServiceTerms,
                    action: { viewModel.toggleServiceTerms() }
                )
                TermsAgreementRow(
                    title: "개인정보 처리방침 동의",
                    isRequired: true,
                    isAccepted: viewModel.state.termsState.hasAcceptedPrivacyPolicy,
                    action: { viewModel.togglePrivacyTerms() }
                )
                TermsAgreementRow(
                    title: "마케팅 수신 동의",
                    isRequired: false,
                    isAccepted: viewModel.state.termsState.hasAcceptedMarketing,
                    action: { viewModel.toggleMarketingTerms() }
                )
            }

            ValidationMessageRow(
                state: viewModel.state.termsState.validationState,
                helperText: "필수 약관 2개에 동의하면 회원가입 버튼이 활성화됩니다"
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct TermsAgreementRow: View {
    let title: String
    let isRequired: Bool
    let isAccepted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isAccepted ? AppPalette.accentBlue : AppPalette.textMuted)
                Text(title)
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textPrimary)
                if isRequired {
                    Text("필수")
                        .font(AppTypography.body(10, weight: .semibold))
                        .foregroundStyle(AppPalette.accentOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppPalette.accentOrange.opacity(0.14))
                        .clipShape(Capsule())
                } else {
                    Text("선택")
                        .font(AppTypography.body(10, weight: .semibold))
                        .foregroundStyle(AppPalette.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppPalette.bgSecondary)
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AuthInputFieldView<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let helperText: String?
    let validationState: FieldValidationState
    let focusedField: FocusState<Field?>.Binding
    let field: Field
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let textInputAutocapitalization: TextInputAutocapitalization
    let submitLabel: SubmitLabel
    var isSecureEntry: Bool = false
    var isTextVisible: Bool = false
    var visibilityToggleAction: (() -> Void)?
    let onSubmit: () -> Void

    private var isFocused: Bool {
        focusedField.wrappedValue == field
    }

    private var borderColor: Color {
        switch validationState {
        case .invalid:
            return AppPalette.accentRed
        case .valid:
            return AppPalette.accentGreen
        case .validating:
            return AppPalette.accentBlue
        case .idle:
            return isFocused ? AppPalette.accentBlue : AppPalette.border
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(13, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)

            HStack(spacing: 12) {
                Group {
                    if isSecureEntry && !isTextVisible {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(AppTypography.body(15))
                .foregroundStyle(AppPalette.textPrimary)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled(true)
                .submitLabel(submitLabel)
                .focused(focusedField, equals: field)
                .onSubmit(onSubmit)

                if let visibilityToggleAction {
                    Button(action: visibilityToggleAction) {
                        Image(systemName: isTextVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(AppPalette.bgSecondary.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            ValidationMessageRow(state: validationState, helperText: helperText)
        }
    }
}

private struct ValidationMessageRow: View {
    let state: FieldValidationState
    let helperText: String?

    var body: some View {
        HStack(spacing: 6) {
            if let iconName = state.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.tint)
            }

            Text(state.message ?? helperText ?? " ")
                .font(AppTypography.body(11))
                .foregroundStyle(state.message == nil ? AppPalette.textMuted : state.tint)

            Spacer()
        }
        .frame(minHeight: 18, alignment: .leading)
    }
}

private struct AuthDividerLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppPalette.border)
                .frame(height: 1)
            Text(title)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textMuted)
            Rectangle()
                .fill(AppPalette.border)
                .frame(height: 1)
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
    let onEmailLoginTap: (() -> Void)?
    let onGoogleTap: () -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AuthBanner(
                title: conflict.presentationError.title,
                message: conflict.presentationError.message,
                tint: AppPalette.accentOrange
            )

            ForEach(conflict.resolvedAvailableProviders, id: \.self) { provider in
                switch provider {
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
                            Text(provider.loginTitle)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                case .email:
                    if let onEmailLoginTap {
                        Button {
                            onEmailLoginTap()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: provider.symbolName)
                                Text(provider.loginTitle)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
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

@ViewBuilder
private func authHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(AppTypography.heading(26, weight: .bold))
            .foregroundStyle(AppPalette.textPrimary)
        Text(subtitle)
            .font(AppTypography.body(14))
            .foregroundStyle(AppPalette.textSecondary)
            .lineSpacing(3)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
