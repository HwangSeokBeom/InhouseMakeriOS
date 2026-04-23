import Combine
import ComposableArchitecture
import GoogleSignIn
import SwiftUI
import XCTest
@testable import InhouseMakeriOS

final class InhouseMakeriOSTests: XCTestCase {
    func testPositionShortLabel() {
        XCTAssertEqual(Position.jungle.shortLabel, "JGL")
        XCTAssertEqual(Position.support.shortLabel, "SUP")
    }

    func testAppConfigurationLoadsDevelopmentEnvironmentSpecificValues() throws {
        let configuration = try AppConfiguration.fromInfoDictionary([
            "APP_ENV": "development",
            "GIDClientID": "development-client-id",
        ])

        XCTAssertEqual(configuration.environment, .development)
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:3000")
        XCTAssertEqual(configuration.publicWebSocketURL.absoluteString, "ws://127.0.0.1:3000/ws/market")
        XCTAssertEqual(configuration.privateWebSocketURL.absoluteString, "ws://127.0.0.1:3000/ws/trading")
        XCTAssertEqual(configuration.googleClientID, "development-client-id")
    }

    func testAppConfigurationLoadsProductionEnvironmentSpecificValues() throws {
        let configuration = try AppConfiguration.fromInfoDictionary([
            "APP_ENV": "production",
            "GIDClientID": "production-client-id",
        ])

        XCTAssertEqual(configuration.environment, .production)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://inhousemaker.duckdns.org")
        XCTAssertEqual(configuration.publicWebSocketURL.absoluteString, "wss://inhousemaker.duckdns.org/ws/market")
        XCTAssertEqual(configuration.privateWebSocketURL.absoluteString, "wss://inhousemaker.duckdns.org/ws/trading")
        XCTAssertEqual(configuration.googleClientID, "production-client-id")
    }

    func testAppConfigurationRejectsMissingEnvironment() {
        XCTAssertThrowsError(try AppConfiguration.fromInfoDictionary([:])) { error in
            XCTAssertEqual(error as? AppConfigurationError, .missingEnvironment)
        }
    }

    func testAppConfigurationRejectsUnexpectedEnvironmentValue() {
        XCTAssertThrowsError(try AppConfiguration.fromInfoDictionary(["APP_ENV": "qa"])) { error in
            XCTAssertEqual(error as? AppConfigurationError, .invalidEnvironment("qa"))
        }
    }

    func testResultStatusTitle() {
        XCTAssertEqual(ResultStatus.partial.title, "임시 기록")
        XCTAssertEqual(ResultStatus.confirmed.title, "확인됨")
    }

    func testAuthProviderIncludesEmailAsSupportedProvider() {
        XCTAssertEqual(Set(AuthProvider.allCases), Set([.apple, .google, .email]))
        XCTAssertEqual(AuthProvider(serverValue: "EMAIL"), .email)
        XCTAssertEqual(AuthProvider(serverValue: "password"), .email)
    }

    func testAuthFlowStateDoesNotExposeEmailSubflows() {
        let labels = Mirror(reflecting: AuthFlowState()).children.compactMap(\.label)
        XCTAssertEqual(labels, ["entryState", "socialLoginState", "successTransitionState"])
    }

    func testAuthProviderSupportsGoogleLogin() {
        XCTAssertEqual(Set(AuthProvider.supportedProviders), Set([.email, .apple, .google]))
        XCTAssertEqual(Set(AuthProvider.socialProviders), Set([.apple, .google]))
    }

    @MainActor
    func testAuthFlowViewModelEnablesGoogleWhenSupportedProvidersIncludesGoogle() {
        let viewModel = AuthFlowViewModel(
            session: AppSessionViewModel(
                container: AppContainer(configuration: makeConfiguration(), tokenStore: makeTokenStore())
            )
        )

        XCTAssertTrue(viewModel.supportedAuthProviders.contains(.google))
        XCTAssertTrue(viewModel.isGoogleLoginEnabled)
    }

    @MainActor
    func testAuthFlowEntryPresentationClearsStaleGoogleFailure() {
        let viewModel = AuthFlowViewModel(
            session: AppSessionViewModel(
                container: AppContainer(configuration: makeConfiguration(), tokenStore: makeTokenStore())
            )
        )

        viewModel.handleGoogleFailure(AuthError.unknown)
        XCTAssertEqual(viewModel.landingPresentationError?.title, "Google 로그인 실패")

        viewModel.prepareForEntryPresentation()

        XCTAssertNil(viewModel.landingPresentationError)
        XCTAssertFalse(viewModel.isBusy)
    }

    @MainActor
    func testGoogleCancellationDoesNotLeaveGenericFailureBanner() {
        let viewModel = AuthFlowViewModel(
            session: AppSessionViewModel(
                container: AppContainer(configuration: makeConfiguration(), tokenStore: makeTokenStore())
            )
        )

        viewModel.beginInteractiveLogin(provider: .google)
        viewModel.handleGoogleFailure(NSError(domain: kGIDSignInErrorDomain, code: -5))

        XCTAssertNil(viewModel.landingPresentationError)
        XCTAssertFalse(viewModel.isBusy)
    }

    @MainActor
    func testGoogleURLCallbackHandlerInvokesConfiguredHandler() {
        let originalHandler = GoogleAuthCallbackHandler.handleURL
        let callbackURL = URL(string: "com.googleusercontent.apps.742162085445-gfk77jd6n7ue8i1nln6ish1kbnne00oo:/oauth2redirect?code=test")!
        var receivedURL: URL?
        GoogleAuthCallbackHandler.handleURL = { url in
            receivedURL = url
            return true
        }
        defer {
            GoogleAuthCallbackHandler.handleURL = originalHandler
        }

        XCTAssertTrue(GoogleAuthCallbackHandler.handle(callbackURL))
        XCTAssertEqual(receivedURL, callbackURL)
    }

    func testEmailValidationUsesServiceLevelRules() {
        XCTAssertEqual(EmailAuthValidator.validateEmail(" "), .invalid("이메일을 입력해 주세요"))
        XCTAssertEqual(EmailAuthValidator.validateEmail("not-an-email"), .invalid("올바른 이메일 형식이 아닙니다"))
        XCTAssertEqual(EmailAuthValidator.validateEmail("User@Example.com "), .valid("사용 가능한 이메일 형식입니다"))
        XCTAssertEqual(EmailAuthValidator.normalizedEmail(" User@Example.com "), "user@example.com")
    }

    func testSignUpPasswordValidationRequiresLetterNumberAndSpecialCharacter() {
        XCTAssertEqual(EmailAuthValidator.validatePasswordForSignUp("short"), .invalid("비밀번호는 8자 이상이어야 합니다"))
        XCTAssertEqual(EmailAuthValidator.validatePasswordForSignUp("password12"), .invalid("영문, 숫자, 특수문자를 모두 포함해 주세요"))
        XCTAssertEqual(EmailAuthValidator.validatePasswordForSignUp("Password1!"), .valid("사용 가능한 비밀번호입니다"))
    }

    func testNicknameValidationRestrictsLengthAndAllowedCharacters() {
        XCTAssertEqual(EmailAuthValidator.validateNickname(" "), .invalid("닉네임을 입력해 주세요"))
        XCTAssertEqual(EmailAuthValidator.validateNickname("a"), .invalid("닉네임은 2자 이상 12자 이하로 입력해 주세요"))
        XCTAssertEqual(EmailAuthValidator.validateNickname("닉네임!"), .invalid("한글, 영문, 숫자만 사용할 수 있습니다"))
        XCTAssertEqual(EmailAuthValidator.validateNickname("테스터12"), .valid("사용 가능한 닉네임 형식입니다"))
    }

    func testPasswordConfirmationValidationMatchesOriginalPassword() {
        XCTAssertEqual(EmailAuthValidator.validatePasswordConfirmation(password: "Password1!", confirmation: ""), .invalid("비밀번호를 다시 입력해 주세요"))
        XCTAssertEqual(EmailAuthValidator.validatePasswordConfirmation(password: "Password1!", confirmation: "Password2!"), .invalid("비밀번호가 일치하지 않습니다"))
        XCTAssertEqual(EmailAuthValidator.validatePasswordConfirmation(password: "Password1!", confirmation: "Password1!"), .valid("비밀번호가 일치합니다"))
    }

    func testSocialTokenInvalidMapping() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Invalid social token",
            code: "SOCIAL_TOKEN_INVALID",
            statusCode: 401
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .socialTokenInvalid)
    }

    func testAuthProviderMismatchMappingUsesDetailsProvider() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Provider mismatch",
            code: "AUTH_PROVIDER_MISMATCH",
            statusCode: 409,
            details: [
                "provider": .string("GOOGLE"),
                "availableProviders": .array([.string("GOOGLE")]),
                "email": .string("user@example.com"),
            ]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .authProviderMismatch(email: "user@example.com", provider: .google, availableProviders: [.google])
        )
    }

    func testAuthProviderMismatchMappingUsesTopLevelProvider() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Provider mismatch",
            code: "AUTH_PROVIDER_MISMATCH",
            provider: "APPLE",
            statusCode: 409,
            details: [
                "availableProviders": .array([.string("APPLE")]),
                "email": .string("user@example.com"),
            ]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .authProviderMismatch(email: "user@example.com", provider: .apple, availableProviders: [.apple])
        )
    }

    func testAuthProviderMismatchMappingSupportsEmailProvider() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Provider mismatch",
            code: "AUTH_PROVIDER_MISMATCH",
            statusCode: 409,
            details: [
                "provider": .string("EMAIL"),
                "availableProviders": .array([.string("EMAIL"), .string("GOOGLE")]),
                "email": .string("user@example.com"),
            ]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .authProviderMismatch(email: "user@example.com", provider: .email, availableProviders: [.email, .google])
        )
    }

    func testAccountExistsWithAppleMapsToAppleConflict() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Conflict",
            code: "ACCOUNT_EXISTS_WITH_APPLE",
            statusCode: 409,
            details: ["email": .string("user@example.com")]
        )

        XCTAssertEqual(AuthErrorMapper.map(error).providerConflict?.suggestedProvider, .apple)
    }

    func testAccountExistsWithGoogleMapsToGoogleConflict() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Conflict",
            code: "ACCOUNT_EXISTS_WITH_GOOGLE",
            statusCode: 409,
            details: ["email": .string("user@example.com")]
        )

        XCTAssertEqual(AuthErrorMapper.map(error).providerConflict?.suggestedProvider, .google)
    }

    func testAccountExistsWithEmailMapsToEmailConflict() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Conflict",
            code: "ACCOUNT_EXISTS_WITH_EMAIL",
            statusCode: 409,
            details: ["email": .string("user@example.com")]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .authProviderMismatch(email: "user@example.com", provider: .email, availableProviders: [.email])
        )
    }

    func testEmailAlreadyInUseMappingSupportsCurrentServerCode() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Email is already in use.",
            code: "EMAIL_ALREADY_IN_USE",
            statusCode: 409
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .emailAlreadyInUse)
    }

    func testInvalidPayloadMappingExposesFieldIssues() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Payload is invalid.",
            code: "INVALID_PAYLOAD",
            statusCode: 400,
            details: [
                "validationErrors": .array([
                    .object([
                        "field": .string("email"),
                        "message": .string("email must be an email"),
                    ]),
                    .object([
                        "field": .string("nickname"),
                        "message": .string("nickname should not be empty"),
                    ]),
                ]),
            ]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .invalidPayload(
                issues: [
                    SignupValidationIssue(field: "email", message: "email must be an email"),
                    SignupValidationIssue(field: "nickname", message: "nickname should not be empty"),
                ],
                message: "Payload is invalid."
            )
        )
    }

    func testAppleConflictMapsToActionableCopy() {
        let conflict = ProviderConflictError(
            email: "user@example.com",
            suggestedProvider: .apple,
            availableProviders: [.apple]
        )

        XCTAssertEqual(
            conflict.presentationError.message,
            "이 계정은 Apple 로그인으로 이용할 수 있어요. Apple로 계속해 주세요."
        )
    }

    func testGoogleConflictMapsToActionableCopy() {
        let conflict = ProviderConflictError(
            email: "user@example.com",
            suggestedProvider: .google,
            availableProviders: [.google]
        )

        XCTAssertEqual(
            conflict.presentationError.message,
            "이 계정은 Google 로그인으로 이용할 수 있어요. Google로 계속해 주세요."
        )
    }

    func testEmailConflictMapsToActionableCopy() {
        let conflict = ProviderConflictError(
            email: "user@example.com",
            suggestedProvider: .email,
            availableProviders: [.email]
        )

        XCTAssertEqual(
            conflict.presentationError.message,
            "이 계정은 이메일 로그인으로 이용할 수 있어요. 이메일로 로그인해 주세요."
        )
    }

    func testOfflineNetworkMapping() {
        XCTAssertEqual(AuthErrorMapper.map(URLError(.notConnectedToInternet)), .networkOffline)
    }

    func testTimeoutNetworkMapping() {
        XCTAssertEqual(AuthErrorMapper.map(URLError(.timedOut)), .networkTimeout)
    }

    func testServerUnavailableMapping() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Server exploded",
            code: "SERVER_ERROR",
            statusCode: 503
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .serverUnavailable)
    }

    func testEmailAuthDisabledUsesEmailSpecificCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Disabled",
            code: "EMAIL_AUTH_DISABLED",
            statusCode: 400
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .emailAuthDisabled)
        XCTAssertEqual(
            AuthError.emailAuthDisabled.presentationError.message,
            "현재 이메일 회원가입이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요."
        )
    }

    func testPasswordAuthDisabledUsesEmailSpecificCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Disabled",
            code: "PASSWORD_AUTH_DISABLED",
            statusCode: 400
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .passwordAuthDisabled)
        XCTAssertEqual(
            AuthError.passwordAuthDisabled.presentationError.message,
            "현재 이메일 로그인이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요."
        )
    }

    func testAccountNotFoundMappingUsesSpecificCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Account not found",
            code: "ACCOUNT_NOT_FOUND",
            statusCode: 404,
            details: ["email": .string("missing@example.com")]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .accountNotFound(email: "missing@example.com")
        )
        XCTAssertEqual(
            AuthError.accountNotFound(email: nil).presentationError.message,
            "가입한 이메일인지 다시 확인해 주세요."
        )
    }

    func testUnsupportedProviderMappingUsesSupportedProviderCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Unsupported provider",
            code: "UNSUPPORTED_PROVIDER",
            statusCode: 400,
            details: ["availableProviders": .array([.string("EMAIL"), .string("APPLE"), .string("GOOGLE")])]
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .unsupportedProvider(provider: "UNSUPPORTED_PROVIDER", availableProviders: [.email, .apple, .google])
        )
        XCTAssertEqual(
            AuthError.unsupportedProvider(provider: nil, availableProviders: [.email, .apple, .google]).presentationError.message,
            "이 앱에서는 이메일, Apple, Google 로그인을 사용할 수 있어요."
        )
    }

    func testValidationErrorMappingParsesSignupConsentIssuesFromServerMessage() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "agreedToTerms must be a boolean value\nagreedToPrivacy must be a boolean value",
            code: "VALIDATION_ERROR",
            statusCode: 400,
            endpoint: AuthAPI.Endpoint.signUp,
            requestMethod: HTTPMethod.post.rawValue
        )

        XCTAssertEqual(
            AuthErrorMapper.map(error),
            .invalidPayload(
                issues: [
                    SignupValidationIssue(field: "agreedToTerms", message: "agreedToTerms must be a boolean value"),
                    SignupValidationIssue(field: "agreedToPrivacy", message: "agreedToPrivacy must be a boolean value"),
                ],
                message: "agreedToTerms must be a boolean value\nagreedToPrivacy must be a boolean value"
            )
        )
    }

    func testInvalidCredentialsServerContractMapsToFriendlyCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Invalid credentials",
            code: "INVALID_CREDENTIALS",
            statusCode: 401
        ).serverContractMapped

        XCTAssertEqual(error.serverContractCode, .invalidCredentials)
        XCTAssertEqual(error.title, "로그인 정보를 다시 확인해 주세요")
    }

    func testRateLimitedServerContractMapsToFriendlyCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Too many requests",
            code: "RATE_LIMITED",
            statusCode: 429
        ).serverContractMapped

        XCTAssertTrue(error.isRateLimited)
        XCTAssertEqual(error.message, "요청이 많아 잠시 후 다시 시도해 주세요.")
    }

    func testRiotAccountDuplicateServerContractMapsToFriendlyCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Conflict",
            code: "ALREADY_ADDED_BY_THIS_USER",
            statusCode: 409
        ).serverContractMapped

        XCTAssertEqual(error.serverContractCode, .riotAccountAlreadyAddedByThisUser)
        XCTAssertEqual(error.title, "이미 추가한 Riot ID예요")
        XCTAssertEqual(error.message, "같은 Riot ID를 내 목록에 두 번 추가할 수는 없어요.")
    }

    func testRiotAccountDuplicateServerContractUsesDetailsReason() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Conflict",
            code: "CONFLICT",
            statusCode: 409,
            details: ["reason": .string("ALREADY_ADDED_BY_THIS_USER")]
        ).serverContractMapped

        XCTAssertEqual(error.serverContractCode, .riotAccountAlreadyAddedByThisUser)
        XCTAssertEqual(error.message, "같은 Riot ID를 내 목록에 두 번 추가할 수는 없어요.")
    }

    func testRiotAccountAnotherUserConflictIsNotRemappedToOwnershipCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "다른 계정에 이미 연결된 라이엇 계정입니다.",
            code: "ALREADY_LINKED_TO_ANOTHER_USER",
            statusCode: 409
        ).serverContractMapped

        XCTAssertEqual(error.serverContractCode, .riotAccountAddUnavailable)
        XCTAssertEqual(error.title, "Riot ID를 추가하지 못했어요")
        XCTAssertEqual(error.message, "요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.")
    }

    func testRecruitingListInvalidPayloadServerContractMapsToFilterCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Payload is invalid.",
            code: "INVALID_PAYLOAD",
            statusCode: 400,
            endpoint: "/recruiting-posts",
            requestMethod: "GET"
        ).serverContractMapped

        XCTAssertEqual(error.title, "필터 조건을 다시 확인해 주세요")
        XCTAssertEqual(error.message, "목록을 불러오는 조건이 올바르지 않습니다.")
    }

    func testLoginInvalidPayloadServerContractMapsToLoginCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Payload is invalid.",
            code: "INVALID_PAYLOAD",
            statusCode: 400,
            endpoint: "/auth/login/email",
            requestMethod: "POST"
        ).serverContractMapped

        XCTAssertEqual(error.title, "로그인 정보를 다시 확인해 주세요")
        XCTAssertEqual(error.message, "입력한 로그인 정보를 다시 확인한 뒤 다시 시도해 주세요.")
    }

    func testGenericInvalidPayloadServerContractMapsToGenericFormCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Payload is invalid.",
            code: "INVALID_PAYLOAD",
            statusCode: 400,
            endpoint: "/groups",
            requestMethod: "POST"
        ).serverContractMapped

        XCTAssertEqual(error.title, "입력값을 다시 확인해 주세요")
        XCTAssertEqual(error.message, "입력한 내용을 다시 확인한 뒤 시도해 주세요.")
    }

    func testAuthRateLimitedMapsToRateLimitedError() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Too many requests",
            code: "RATE_LIMITED",
            statusCode: 429
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .rateLimited)
    }

    func testAuthRequiredServerContractMapsToPromptMessage() {
        let error = UserFacingError(
            title: "인증 오류",
            message: "로그인이 필요합니다",
            code: "AUTH_REQUIRED",
            statusCode: 401
        ).serverContractMapped

        XCTAssertTrue(error.requiresAuthentication)
        XCTAssertEqual(error.title, "로그인이 필요해요")
    }

    func testForbiddenFeatureServerContractMapsToPermissionCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Forbidden",
            code: "FORBIDDEN_FEATURE",
            statusCode: 403
        ).serverContractMapped

        XCTAssertTrue(error.isForbiddenFeature)
        XCTAssertEqual(error.message, "이 기능에 대한 권한이 없습니다.")
    }

    func testGroupNotFoundServerContractMapsToDomainSpecificCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Group not found.",
            code: "RESOURCE_NOT_FOUND",
            statusCode: 404,
            endpoint: "/groups/group-1",
            requestMethod: "GET"
        ).serverContractMapped

        XCTAssertEqual(error.title, "접근할 수 없는 그룹이에요")
        XCTAssertEqual(error.message, "더 이상 접근할 수 없는 그룹입니다.")
    }

    func testTeamBalancePreviewDraftBuildsBalancedTeams() {
        let preview = TeamBalancePreviewDraft.defaultValue.makePreviewResult()

        XCTAssertEqual(preview?.bluePlayers.count, 5)
        XCTAssertEqual(preview?.redPlayers.count, 5)
        XCTAssertEqual(preview?.mode, .balanced)
    }

    func testBalancePreviewSuccessDecodesServerResult() async throws {
        let repository = MatchRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/matches/balance/preview")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let payload = try JSONEncoder.app.encode(
                    BalancePreviewResponseDTO(
                        bluePlayers: [
                            PreviewRosterPlayerInputDTO(nickname: "Blue Top", preferredPosition: .top, score: 82),
                            PreviewRosterPlayerInputDTO(nickname: "Blue Jgl", preferredPosition: .jungle, score: 79),
                            PreviewRosterPlayerInputDTO(nickname: "Blue Mid", preferredPosition: .mid, score: 84),
                            PreviewRosterPlayerInputDTO(nickname: "Blue Adc", preferredPosition: .adc, score: 80),
                            PreviewRosterPlayerInputDTO(nickname: "Blue Sup", preferredPosition: .support, score: 76),
                        ],
                        redPlayers: [
                            PreviewRosterPlayerInputDTO(nickname: "Red Top", preferredPosition: .top, score: 81),
                            PreviewRosterPlayerInputDTO(nickname: "Red Jgl", preferredPosition: .jungle, score: 78),
                            PreviewRosterPlayerInputDTO(nickname: "Red Mid", preferredPosition: .mid, score: 83),
                            PreviewRosterPlayerInputDTO(nickname: "Red Adc", preferredPosition: .adc, score: 79),
                            PreviewRosterPlayerInputDTO(nickname: "Red Sup", preferredPosition: .support, score: 75),
                        ],
                        blueTotal: 401,
                        redTotal: 396,
                        mode: .balanced
                    )
                )
                return (200, payload)
            }
        ))

        let result = try await repository.previewBalance(draft: .defaultValue)
        XCTAssertEqual(result.bluePlayers.count, 5)
        XCTAssertEqual(result.redPlayers.count, 5)
        XCTAssertEqual(result.blueTotal, 401)
        XCTAssertEqual(result.mode, .balanced)
    }

    func testResultPreviewSuccessDecodesValidation() async throws {
        let repository = MatchRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/matches/result/preview")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let payload = try JSONEncoder.app.encode(
                    ResultPreviewResponseDTO(
                        isValid: true,
                        message: "결과 프리뷰를 확인했어요."
                    )
                )
                return (200, payload)
            }
        ))

        let validation = try await repository.previewResult(draft: .defaultValue())
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.message, "결과 프리뷰를 확인했어요.")
    }

    func testResultPreviewValidationFailurePropagatesServerMessage() async {
        let repository = MatchRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/matches/result/preview")
                return (400, self.makeServerErrorData(statusCode: 400, code: "VALIDATION_FAILED", message: "MVP를 다시 선택해 주세요."))
            }
        ))

        do {
            _ = try await repository.previewResult(draft: .defaultValue())
            XCTFail("Expected validation failure")
        } catch let error as UserFacingError {
            XCTAssertEqual(error.title, "결과를 다시 확인해 주세요")
            XCTAssertEqual(error.message, "MVP를 다시 선택해 주세요.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProtectedRequestRefreshSuccessRetriesOriginalRequest() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let lock = NSLock()
        final class UnauthorizedState: @unchecked Sendable {
            var didReturnUnauthorized = false
        }
        let unauthorizedState = UnauthorizedState()
        let repository = GroupRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                switch request.url?.path {
                case "/groups":
                    lock.lock()
                    defer { lock.unlock() }
                    if !unauthorizedState.didReturnUnauthorized {
                        unauthorizedState.didReturnUnauthorized = true
                        return (401, self.makeServerErrorData(statusCode: 401, code: "TOKEN_EXPIRED", message: "Expired"))
                    }
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
                    let payload = try JSONEncoder.app.encode(GroupSummaryListDTO(items: []))
                    return (200, payload)
                case "/auth/refresh":
                    let payload = try JSONEncoder.app.encode(
                        AuthTokensDTO(
                            user: AuthUserDTO(
                                id: "u1",
                                email: "user@example.com",
                                nickname: "tester",
                                provider: "email",
                                status: .active
                            ),
                            accessToken: "refreshed-access",
                            refreshToken: "refreshed-refresh"
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        ))

        let groups = try await repository.list()
        XCTAssertTrue(groups.isEmpty)
        let refreshedTokens = await tokenStore.loadTokens()
        XCTAssertEqual(refreshedTokens?.accessToken, "refreshed-access")
    }

    func testProtectedRequestRefreshFailureReturnsAuthRequiredAndClearsTokens() async {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let repository = GroupRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                switch request.url?.path {
                case "/groups":
                    return (401, self.makeServerErrorData(statusCode: 401, code: "TOKEN_EXPIRED", message: "Expired"))
                case "/auth/refresh":
                    return (401, self.makeServerErrorData(statusCode: 401, code: "AUTH_REQUIRED", message: "Refresh expired"))
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        ))

        do {
            _ = try await repository.list()
            XCTFail("Expected auth required failure")
        } catch let error as UserFacingError {
            XCTAssertTrue(error.requiresAuthentication)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let clearedTokens = await tokenStore.loadTokens()
        XCTAssertNil(clearedTokens)
    }

    func testProfileRepositorySearchInviteUsersFallsBackToAlternateEndpoint() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var requestedPaths: [String] = []

        let repository = ProfileRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                requestLock.lock()
                requestedPaths.append(request.url?.path ?? "nil")
                requestLock.unlock()

                switch request.url?.path {
                case "/users/search":
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Not found."
                        )
                    )
                case "/users":
                    XCTAssertEqual(self.queryItemValues(from: request.url, named: "query"), ["Alpha"])
                    XCTAssertEqual(self.queryItemValues(from: request.url, named: "limit"), ["20"])
                    let json = """
                    [{"userId":"user-42","nickname":"Alpha","primaryPosition":"MID","secondaryPosition":"TOP","recentPower":73.6,"riotGameName":"Alpha","tagLine":"KR1"}]
                    """
                    return (200, Data(json.utf8))
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        ))

        let users = try await repository.searchInviteUsers(query: " Alpha ")

        requestLock.lock()
        let capturedPaths = requestedPaths
        requestLock.unlock()

        XCTAssertEqual(capturedPaths, ["/users/search", "/users"])
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, "user-42")
        XCTAssertEqual(users.first?.nickname, "Alpha")
        XCTAssertEqual(users.first?.primaryPosition, .mid)
        XCTAssertEqual(users.first?.secondaryPosition, .top)
        XCTAssertEqual(users.first?.recentPower, 73.6)
        XCTAssertEqual(users.first?.riotDisplayName, "Alpha#KR1")
    }

    func testErrorMapperMapsRecruitingClosedToFriendlyMessage() {
        let mappedError = UserFacingError(
            title: "서버 오류",
            message: "Recruiting closed.",
            code: "RECRUITING_CLOSED",
            statusCode: 409,
            endpoint: "/recruiting-posts/post-1/apply",
            requestMethod: "POST"
        ).serverContractMapped

        XCTAssertEqual(mappedError.title, "모집이 마감되었어요")
        XCTAssertEqual(mappedError.message, "모집이 마감되어 참가 신청할 수 없어요.")
    }

    func testErrorMapperMapsRecruitingApplyClosedOrFullToFriendlyMessage() {
        let mappedError = UserFacingError(
            title: "서버 오류",
            message: "Capacity full.",
            code: "UNKNOWN_SERVER_ERROR",
            statusCode: 409,
            endpoint: "/recruiting-posts/post-1/participants",
            requestMethod: "POST"
        ).serverContractMapped

        XCTAssertEqual(mappedError.title, "모집이 마감되었어요")
        XCTAssertEqual(mappedError.message, "모집이 마감되어 참가 신청할 수 없어요.")
    }

    func testPowerProfileDTODecodesSeededProfileWithoutStyleStability() throws {
        let payload = """
        {
          "userId": "seed-user",
          "overallPower": 81.5,
          "lanePower": {
            "MID": 84,
            "TOP": 78,
            "ADC": 74
          },
          "primaryPosition": "MID",
          "secondaryPosition": "TOP",
          "style": {
            "carry": 79,
            "teamContribution": 76,
            "laneInfluence": 80
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(PowerProfileDTO.self, from: payload)
        let profile = dto.toDomain(requestedUserID: "seed-user")

        XCTAssertEqual(profile.userID, "seed-user")
        XCTAssertEqual(profile.primaryPosition, .mid)
        XCTAssertEqual(profile.secondaryPosition, .top)
        XCTAssertEqual(profile.overallPower, 81.5, accuracy: 0.001)
        XCTAssertEqual(profile.stability, 81.5, accuracy: 0.001)
        XCTAssertEqual(profile.carry, 79, accuracy: 0.001)
        XCTAssertEqual(profile.teamContribution, 76, accuracy: 0.001)
        XCTAssertEqual(profile.laneInfluence, 80, accuracy: 0.001)
        XCTAssertEqual(dto.missingFieldPaths, [
            "style.stability",
            "basePower",
            "formScore",
            "inhouseMmr",
            "inhouseConfidence",
            "version",
            "calculatedAt",
        ])
    }

    func testPowerProfileDTOKeepsLobbyDataWhenOptionalFieldsAreMissing() throws {
        let payload = """
        {
          "userId": "seed-user",
          "lanePower": {
            "SUPPORT": 71,
            "ADC": 68
          },
          "overallPower": 70,
          "style": {}
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(PowerProfileDTO.self, from: payload)
        let profile = dto.toDomain(requestedUserID: "seed-user")

        XCTAssertNil(profile.primaryPosition)
        XCTAssertNil(profile.secondaryPosition)
        XCTAssertEqual(profile.resolvedPrimaryPosition, .support)
        XCTAssertEqual(profile.resolvedSecondaryPosition, .adc)
        XCTAssertEqual(profile.basePower, 70, accuracy: 0.001)
        XCTAssertEqual(profile.formScore, 70, accuracy: 0.001)
        XCTAssertEqual(profile.stability, 70, accuracy: 0.001)
    }

    func testPowerProfileDTODecodesTopChampionsAndAggregationDetails() throws {
        let payload = """
        {
          "userId": "seed-user",
          "overallPower": 84,
          "lanePower": {
            "MID": 84,
            "TOP": 76
          },
          "topChampions": [
            {
              "championId": 103,
              "championKey": "Ahri",
              "championName": "아리",
              "games": 18,
              "wins": 10,
              "losses": 8,
              "winRate": 55.6
            }
          ],
          "topChampionAggregationStatus": {
            "status": "PARTIAL",
            "reason": "INSUFFICIENT_BACKFILL",
            "message": "부분 집계 상태예요.",
            "syncCoverageSummary": "최근 30일 기준"
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(PowerProfileDTO.self, from: payload)
        let profile = dto.toDomain(requestedUserID: "seed-user")

        XCTAssertEqual(profile.topChampions?.count, 1)
        XCTAssertEqual(profile.topChampions?.first?.championKey, "Ahri")
        XCTAssertEqual(profile.topChampionAggregation?.status, .partial)
        XCTAssertEqual(profile.topChampionAggregation?.normalizedReason, "INSUFFICIENT_BACKFILL")
        XCTAssertEqual(profile.topChampionAggregation?.message, "부분 집계 상태예요.")
        XCTAssertEqual(profile.topChampionAggregation?.syncCoverageSummary, "최근 30일 기준")
    }

    func testPowerProfileDTODropsMalformedTopChampionItemsWithoutFailingDecode() throws {
        let payload = """
        {
          "userId": "seed-user",
          "overallPower": 84,
          "lanePower": {
            "MID": 84,
            "TOP": 76
          },
          "topChampions": [
            "broken",
            {
              "championKey": "Ahri",
              "championName": "아리",
              "games": "18",
              "wins": "10",
              "winRate": "55.6"
            }
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(PowerProfileDTO.self, from: payload)
        let profile = dto.toDomain(requestedUserID: "seed-user")

        XCTAssertEqual(profile.topChampions?.count, 1)
        XCTAssertEqual(profile.topChampions?.first?.championName, "아리")
        XCTAssertEqual(profile.topChampions?.first?.games, 18)
    }

    func testProfilePositionSummaryUsesServerPositionsBeforeManualProfileSettings() {
        let profile = makeProfile()
        let power = PowerProfile(
            userID: "u1",
            overallPower: 88,
            lanePower: [.support: 91, .adc: 87, .mid: 73],
            primaryPosition: .support,
            secondaryPosition: .adc,
            stability: 82,
            carry: 79,
            teamContribution: 86,
            laneInfluence: 91,
            basePower: 84,
            formScore: 88,
            inhouseMMR: 1020,
            inhouseConfidence: 0.9,
            version: "test",
            calculatedAt: Date()
        )

        let summary = ProfilePositionSummaryViewState.build(profile: profile, power: power)

        XCTAssertEqual(summary.primary, .support)
        XCTAssertEqual(summary.secondary, .adc)
        XCTAssertEqual(summary.source, .server)
        XCTAssertEqual(summary.primaryPowerText, "91")
        XCTAssertEqual(summary.secondaryPowerText, "87")
    }

    func testProfilePositionSummaryFallsBackToLanePowerWhenServerPositionsAreEmpty() {
        var profile = makeProfile()
        profile.primaryPosition = nil
        profile.secondaryPosition = nil
        let power = PowerProfile(
            userID: "u1",
            overallPower: 80,
            lanePower: [.jungle: 92, .top: 84, .mid: 77],
            primaryPosition: nil,
            secondaryPosition: nil,
            stability: 80,
            carry: 80,
            teamContribution: 80,
            laneInfluence: 80,
            basePower: 80,
            formScore: 80,
            inhouseMMR: 980,
            inhouseConfidence: 0.7,
            version: "test",
            calculatedAt: Date()
        )

        let summary = ProfilePositionSummaryViewState.build(profile: profile, power: power)
        let powerSection = ProfilePowerSectionViewState.build(power: power, positionSummary: summary)

        XCTAssertEqual(summary.primary, .jungle)
        XCTAssertEqual(summary.secondary, .top)
        XCTAssertEqual(summary.source, .fallback)
        XCTAssertEqual(powerSection.laneRows.first(where: { $0.position == .jungle })?.roleBadgeText, "주")
        XCTAssertEqual(powerSection.laneRows.first(where: { $0.position == .top })?.roleBadgeText, "부")
    }

    func testProfilePositionSummaryUsesUserProfilePositionsBeforeLaneFallback() {
        let profile = makeProfile()
        let power = PowerProfile(
            userID: "u1",
            overallPower: 80,
            lanePower: [.jungle: 92, .top: 84, .mid: 77],
            primaryPosition: nil,
            secondaryPosition: nil,
            stability: 80,
            carry: 80,
            teamContribution: 80,
            laneInfluence: 80,
            basePower: 80,
            formScore: 80,
            inhouseMMR: 980,
            inhouseConfidence: 0.7,
            version: "test",
            calculatedAt: Date()
        )

        let summary = ProfilePositionSummaryViewState.build(profile: profile, power: power)

        XCTAssertEqual(summary.primary, .mid)
        XCTAssertEqual(summary.secondary, .top)
        XCTAssertEqual(summary.source, .server)
    }

    func testUserProfileDTODecodesTopChampionsAndMapsToDomain() throws {
        let payload = """
        {
          "id": "u1",
          "email": "user@example.com",
          "nickname": "tester",
          "primaryPosition": "MID",
          "secondaryPosition": "TOP",
          "isFillAvailable": true,
          "styleTags": ["빡겜"],
          "mannerScore": 100,
          "noshowCount": 0,
          "championAggregationStatus": "READY",
          "topChampions": [
            {
              "championId": 103,
              "championKey": "Ahri",
              "championName": "아리",
              "games": 24,
              "wins": 14,
              "losses": 10,
              "winRate": 58.3,
              "kills": 8.2,
              "deaths": 3.1,
              "assists": 6.4,
              "kda": 4.7,
              "lastPlayedAt": "2026-04-18T09:30:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(UserProfileDTO.self, from: payload)
        let profile = dto.toDomain()

        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(profile.topChampions.count, 1)
        XCTAssertEqual(profile.topChampions.first?.championId, 103)
        XCTAssertEqual(profile.topChampions.first?.championKey, "Ahri")
        XCTAssertEqual(profile.topChampions.first?.championName, "아리")
        XCTAssertEqual(profile.topChampions.first?.games, 24)
        XCTAssertEqual(profile.topChampions.first?.kda ?? 0, 4.7, accuracy: 0.001)
        XCTAssertNotNil(profile.topChampions.first?.lastPlayedAt)
        XCTAssertEqual(profile.championAggregationStatus, .ready)
    }

    func testUserProfileDTODecodesTopChampionAggregationObject() throws {
        let payload = """
        {
          "id": "u1",
          "email": "user@example.com",
          "nickname": "tester",
          "isFillAvailable": true,
          "styleTags": [],
          "mannerScore": 100,
          "noshowCount": 0,
          "topChampionAggregationStatus": {
            "status": "PARTIAL",
            "reason": "INSUFFICIENT_BACKFILL",
            "message": "백필이 더 필요해요.",
            "syncCoverageSummary": "최근 랭크 전적 일부만 반영"
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(UserProfileDTO.self, from: payload)
        let profile = dto.toDomain()

        XCTAssertEqual(profile.championAggregationStatus, .partial)
        XCTAssertEqual(profile.topChampionAggregation?.normalizedReason, "INSUFFICIENT_BACKFILL")
        XCTAssertEqual(profile.topChampionAggregation?.message, "백필이 더 필요해요.")
        XCTAssertEqual(profile.topChampionAggregation?.syncCoverageSummary, "최근 랭크 전적 일부만 반영")
    }

    func testUserProfileDTODoesNotFailWhenTopChampionsShapeIsUnexpected() throws {
        let payload = """
        {
          "id": "u1",
          "email": "user@example.com",
          "nickname": "tester",
          "primaryPosition": "MID",
          "secondaryPosition": "TOP",
          "isFillAvailable": true,
          "styleTags": ["빡겜"],
          "mannerScore": 100,
          "noshowCount": 0,
          "topChampions": {
            "championKey": "Ahri"
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(UserProfileDTO.self, from: payload)
        let profile = dto.toDomain()

        XCTAssertEqual(profile.nickname, "tester")
        XCTAssertTrue(profile.topChampions.isEmpty)
    }

    func testUserProfileDTODropsMalformedTopChampionItemsWithoutFailingMeDecode() throws {
        let payload = """
        {
          "id": "u1",
          "email": "user@example.com",
          "nickname": "tester",
          "primaryPosition": "MID",
          "secondaryPosition": "TOP",
          "isFillAvailable": true,
          "styleTags": ["빡겜"],
          "mannerScore": 100,
          "noshowCount": 0,
          "topChampions": [
            "broken",
            {
              "championKey": "Ahri",
              "championName": "아리",
              "games": "12",
              "wins": "7",
              "winRate": "58.3"
            },
            {
              "championKey": "",
              "championName": "",
              "games": 99
            }
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.app.decode(UserProfileDTO.self, from: payload)
        let profile = dto.toDomain()

        XCTAssertEqual(profile.nickname, "tester")
        XCTAssertEqual(profile.topChampions.count, 1)
        XCTAssertEqual(profile.topChampions.first?.championKey, "Ahri")
        XCTAssertEqual(profile.topChampions.first?.games, 12)
    }

    func testProfileTopChampionsSectionStateBuildsThreeRowsAndUsesContentState() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [
                makeTopChampion(championKey: "Ahri", championName: "아리", games: 24, wins: 14, winRate: 58.3, kda: 4.7),
                makeTopChampion(championKey: "Orianna", championName: "오리아나", games: 18, wins: 10, winRate: 55.6, kda: nil),
                makeTopChampion(championKey: "Syndra", championName: "신드라", games: 12, wins: 7, winRate: 58.3, kda: 3.2),
                makeTopChampion(championKey: "Lux", championName: "럭스", games: 0, wins: 0, winRate: 0, kda: 2.1),
            ],
            aggregation: ProfileTopChampionAggregation(status: .ready),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .succeeded)])
        )

        guard case let .content(items, subtitle) = state else {
            return XCTFail("Expected content state")
        }

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.championName), ["아리", "오리아나", "신드라"])
        XCTAssertEqual(items.first?.gamesText, "24판")
        XCTAssertEqual(items.first?.winRateText, "승률 58.3%")
        XCTAssertEqual(items.first?.kdaText, "KDA 4.7")
        XCTAssertNil(items[1].kdaText)
        XCTAssertNil(subtitle)
        XCTAssertEqual(state.debugState, .content)
    }

    func testProfileTopChampionsSectionStateSupportsTwoChampionRows() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [
                makeTopChampion(championKey: "Ahri", championName: "아리", games: 9, wins: 5, winRate: 55.6, kda: 3.4),
                makeTopChampion(championKey: "LeBlanc", championName: "르블랑", games: 7, wins: 4, winRate: 57.1, kda: 2.9),
            ],
            aggregation: ProfileTopChampionAggregation(status: .ready),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .succeeded)])
        )

        guard case let .content(items, _) = state else {
            return XCTFail("Expected content state")
        }

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.rank), [1, 2])
    }

    func testProfileTopChampionsSectionStateShowsContentWhenPartialStatusHasChampions() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [makeTopChampion(championKey: "Ahri", championName: "아리", games: 4, wins: 2, winRate: 50, kda: 2.2)],
            aggregation: ProfileTopChampionAggregation(status: .partial, message: "부분 집계 상태예요."),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .partial)])
        )

        guard case let .content(items, subtitle) = state else {
            return XCTFail("Expected content state")
        }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(subtitle, "부분 집계 상태예요.")
        XCTAssertEqual(state.debugState, .content)
    }

    func testProfileTopChampionsSectionStateShowsContentWhenBackfillReasonHasChampions() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [makeTopChampion(championKey: "Ahri", championName: "아리", games: 1, wins: 1, winRate: 100, kda: nil)],
            aggregation: ProfileTopChampionAggregation(
                status: .partial,
                reason: "INSUFFICIENT_BACKFILL",
                message: "백필이 더 필요해요."
            ),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .partial)])
        )

        guard case let .content(items, subtitle) = state else {
            return XCTFail("Expected content state")
        }

        XCTAssertEqual(items.first?.championName, "아리")
        XCTAssertEqual(subtitle, "백필이 더 필요해요.")
        XCTAssertEqual(state.debugState, .content)
    }

    func testProfileTopChampionsSectionStateShowsContentForZeroGameChampionWhenNonEmpty() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [makeTopChampion(championKey: "Ahri", championName: "아리", games: 0, wins: 0, winRate: 0, kda: nil)],
            aggregation: ProfileTopChampionAggregation(status: .partial),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .partial)])
        )

        guard case let .content(items, _) = state else {
            return XCTFail("Expected content state")
        }

        XCTAssertEqual(items.first?.championName, "아리")
        XCTAssertEqual(items.first?.gamesText, "0판")
    }

    func testProfileTopChampionsSectionStateShowsDisconnectedWhenEmptyAndRiotDisconnected() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: nil,
            riotAccountsViewState: .noLinkedAccounts
        )

        guard case let .empty(displayState, title, message, _) = state else {
            return XCTFail("Expected disconnected empty state")
        }

        XCTAssertEqual(displayState, .disconnected)
        XCTAssertEqual(title, "Riot 계정 연결이 필요해요")
        XCTAssertEqual(message, "Riot ID를 연결하면 주 챔피언을 분석해 보여드릴게요.")
    }

    func testProfileTopChampionsSectionStateShowsSyncingWhenEmptyAndSyncRunning() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: nil,
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .running)])
        )

        guard case let .empty(displayState, title, message, _) = state else {
            return XCTFail("Expected syncing empty state")
        }

        XCTAssertEqual(displayState, .syncing)
        XCTAssertEqual(title, "최근 전적을 분석 중이에요")
        XCTAssertEqual(message, "동기화가 끝나면 주 챔피언이 자동으로 채워집니다.")
    }

    func testProfileTopChampionsSectionStateShowsBackfillPendingWhenEmptyAndBackfillPending() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: ProfileTopChampionAggregation(
                status: .partial,
                reason: "INSUFFICIENT_BACKFILL",
                message: "이전 전적이 더 필요해요."
            ),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .partial)])
        )

        guard case let .empty(displayState, title, message, subtitle) = state else {
            return XCTFail("Expected backfill pending empty state")
        }

        XCTAssertEqual(displayState, .backfillPending)
        XCTAssertEqual(title, "전적 동기화가 더 필요해요")
        XCTAssertEqual(message, "이전 랭크 전적이 더 반영되면 주 챔피언을 보여드릴게요.")
        XCTAssertEqual(subtitle, "이전 전적이 더 필요해요.")
    }

    func testProfileTopChampionsSectionStateShowsInsufficientSampleWhenEmptyAndSampleIsInsufficient() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: ProfileTopChampionAggregation(
                status: .insufficientSample,
                reason: "INSUFFICIENT_SAMPLE"
            ),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .succeeded)])
        )

        guard case let .empty(displayState, title, message, _) = state else {
            return XCTFail("Expected insufficient sample state")
        }

        XCTAssertEqual(displayState, .insufficientSample)
        XCTAssertEqual(title, "랭크 기록이 더 필요해요")
        XCTAssertEqual(message, "집계 가능한 랭크 기록이 더 쌓이면 주 챔피언을 보여드릴게요.")
    }

    func testProfileTopChampionsSectionStateShowsGenericEmptyWhenServerDidNotMarkSampleInsufficient() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: ProfileTopChampionAggregation(status: .connectedEmpty),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .succeeded)])
        )

        guard case let .empty(displayState, title, message, _) = state else {
            return XCTFail("Expected generic empty state")
        }

        XCTAssertEqual(displayState, .genericEmpty)
        XCTAssertEqual(title, "아직 표시할 챔피언이 없어요")
        XCTAssertEqual(message, "서버 집계가 완료되면 상위 챔피언을 보여드릴게요.")
    }

    func testProfileTopChampionsSectionStateUsesServerStatusBeforeRiotSyncFallback() {
        let state = ProfileTopChampionsSectionState.build(
            champions: [],
            aggregation: ProfileTopChampionAggregation(status: .syncing),
            riotAccountsViewState: .loaded([makeRiotAccount(syncStatus: .succeeded)])
        )

        guard case let .empty(displayState, title, message, _) = state else {
            return XCTFail("Expected syncing empty state")
        }

        XCTAssertEqual(displayState, .syncing)
        XCTAssertEqual(title, "최근 전적을 분석 중이에요")
        XCTAssertEqual(message, "동기화가 끝나면 주 챔피언이 자동으로 채워집니다.")
    }

    @MainActor
    func testProfileViewModelBuildsSnapshotWithAutoPositionsAndTopChampions() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/me"):
                    let profile = UserProfileDTO(
                        id: "u1",
                        email: "user@example.com",
                        nickname: "tester",
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        isFillAvailable: true,
                        styleTags: ["빡겜"],
                        mannerScore: 100,
                        noshowCount: 0,
                        topChampions: [
                            ProfileTopChampionDTO(
                                championId: 103,
                                championKey: "Ahri",
                                championName: "아리",
                                games: 14,
                                wins: 8,
                                losses: 6,
                                winRate: 57.1,
                                kills: 0,
                                deaths: 0,
                                assists: 0,
                                kda: 4.1
                            ),
                        ],
                        championAggregationStatus: .ready
                    )
                    return (200, try JSONEncoder.app.encode(profile))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [self.makeRiotAccountDTO(syncStatus: .succeeded)])))
                case ("GET", "/users/u1/power-profile"):
                    let power = PowerProfileDTO(
                        userId: "u1",
                        overallPower: 89,
                        lanePower: ["SUPPORT": 91, "ADC": 86, "MID": 72],
                        primaryPosition: .support,
                        secondaryPosition: .adc,
                        style: PowerProfileDTO.StyleDTO(stability: 83, carry: 78, teamContribution: 90, laneInfluence: 91),
                        basePower: 86,
                        formScore: 88,
                        inhouseMmr: 1040,
                        inhouseConfidence: 0.9,
                        version: "test",
                        calculatedAt: Date(),
                        autoAssignmentBasis: "라인 파워 기준 주라인 산정"
                    )
                    return (200, try JSONEncoder.app.encode(power))
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = ProfileViewModel(session: session)

        await viewModel.load(force: true, trigger: "test")

        guard case let .content(.authenticated(snapshot)) = viewModel.state else {
            return XCTFail("Expected authenticated profile snapshot")
        }
        XCTAssertEqual(snapshot.positionSummary.primary, .support)
        XCTAssertEqual(snapshot.positionSummary.secondary, .adc)
        XCTAssertEqual(snapshot.positionSummary.source, .server)
        XCTAssertEqual(snapshot.powerSection?.laneRows.first(where: { $0.position == .support })?.roleBadgeText, "주")
        guard case let .content(champions, subtitle) = snapshot.topChampionsSection else {
            return XCTFail("Expected top champions content")
        }
        XCTAssertEqual(champions.first?.championName, "아리")
        XCTAssertEqual(champions.first?.championKey, "Ahri")
        XCTAssertNil(subtitle)
        XCTAssertEqual(snapshot.topChampionsSection.headerSubtitle, "서버 집계 기준 가장 많이 플레이한 챔피언")
        XCTAssertTrue(snapshot.history.isEmpty)
    }

    @MainActor
    func testProfileViewModelPrefersPowerProfileTopChampionsWhenProfileIsEmpty() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/me"):
                    let profile = UserProfileDTO(
                        id: "u1",
                        email: "user@example.com",
                        nickname: "tester",
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        isFillAvailable: true,
                        styleTags: ["빡겜"],
                        mannerScore: 100,
                        noshowCount: 0,
                        topChampions: [],
                        championAggregationStatus: .disconnected
                    )
                    return (200, try JSONEncoder.app.encode(profile))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [self.makeRiotAccountDTO(syncStatus: .partial)])))
                case ("GET", "/users/u1/power-profile"):
                    let power = PowerProfileDTO(
                        userId: "u1",
                        overallPower: 89,
                        lanePower: ["MID": 91, "TOP": 83],
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        style: PowerProfileDTO.StyleDTO(stability: 83, carry: 78, teamContribution: 90, laneInfluence: 91),
                        basePower: 86,
                        formScore: 88,
                        inhouseMmr: 1040,
                        inhouseConfidence: 0.9,
                        version: "test",
                        calculatedAt: Date(),
                        topChampions: [
                            ProfileTopChampionDTO(
                                championId: 103,
                                championKey: "Ahri",
                                championName: "아리",
                                games: 6,
                                wins: 4,
                                losses: 2,
                                winRate: 66.7,
                                kills: 0,
                                deaths: 0,
                                assists: 0,
                                kda: 4.1
                            ),
                        ],
                        topChampionAggregation: ProfileTopChampionAggregationDTO(
                            status: .partial,
                            reason: "INSUFFICIENT_BACKFILL",
                            message: "부분 집계 상태예요."
                        )
                    )
                    return (200, try JSONEncoder.app.encode(power))
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = ProfileViewModel(session: session)

        await viewModel.load(force: true, trigger: "test")

        guard case let .content(.authenticated(snapshot)) = viewModel.state else {
            return XCTFail("Expected authenticated profile snapshot")
        }
        guard case let .content(champions, subtitle) = snapshot.topChampionsSection else {
            return XCTFail("Expected top champions content from power profile")
        }
        XCTAssertEqual(champions.first?.championName, "아리")
        XCTAssertEqual(snapshot.topChampionsSection.debugState, .content)
        XCTAssertEqual(subtitle, "부분 집계 상태예요.")
    }

    @MainActor
    func testProfileViewModelFallsBackToProfileTopChampionsWhenPowerResponseIsEmpty() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/me"):
                    let profile = UserProfileDTO(
                        id: "u1",
                        email: "user@example.com",
                        nickname: "tester",
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        isFillAvailable: true,
                        styleTags: ["빡겜"],
                        mannerScore: 100,
                        noshowCount: 0,
                        topChampions: [
                            ProfileTopChampionDTO(
                                championId: 103,
                                championKey: "Ahri",
                                championName: "아리",
                                games: 11,
                                wins: 7,
                                losses: 4,
                                winRate: 63.6,
                                kills: 0,
                                deaths: 0,
                                assists: 0,
                                kda: 4.1
                            ),
                        ],
                        championAggregationStatus: .ready
                    )
                    return (200, try JSONEncoder.app.encode(profile))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [self.makeRiotAccountDTO(syncStatus: .succeeded)])))
                case ("GET", "/users/u1/power-profile"):
                    let power = PowerProfileDTO(
                        userId: "u1",
                        overallPower: 89,
                        lanePower: ["MID": 91, "TOP": 83],
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        style: PowerProfileDTO.StyleDTO(stability: 83, carry: 78, teamContribution: 90, laneInfluence: 91),
                        basePower: 86,
                        formScore: 88,
                        inhouseMmr: 1040,
                        inhouseConfidence: 0.9,
                        version: "test",
                        calculatedAt: Date(),
                        topChampions: [],
                        topChampionAggregation: ProfileTopChampionAggregationDTO(
                            status: .connectedEmpty,
                            message: "이번 집계에는 챔피언이 비어 있어요."
                        )
                    )
                    return (200, try JSONEncoder.app.encode(power))
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = ProfileViewModel(session: session)

        await viewModel.load(force: true, trigger: "test")

        guard case let .content(.authenticated(snapshot)) = viewModel.state else {
            return XCTFail("Expected authenticated profile snapshot")
        }
        guard case let .content(champions, _) = snapshot.topChampionsSection else {
            return XCTFail("Expected top champions content from profile fallback")
        }
        XCTAssertEqual(champions.first?.championName, "아리")
        XCTAssertEqual(snapshot.topChampionsSection.debugState, .content)
    }

    func testEmailSignUpRequestUsesExpectedEndpointAndPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, AuthAPI.Endpoint.signUp)
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, "user@example.com")
                    XCTAssertEqual(payload["password"] as? String, "Password1!")
                    XCTAssertEqual(payload["nickname"] as? String, "tester")
                    XCTAssertEqual(Set(payload.keys), Set(["email", "password", "nickname"]))

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "email",
                            status: .active
                        ),
                        accessToken: "signup-access",
                        refreshToken: "signup-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                }
            ),
            tokenStore: tokenStore
        )

        let tokens = try await repository.signUpWithEmail(
            email: "user@example.com",
            password: "Password1!",
            nickname: "tester"
        )

        XCTAssertEqual(tokens.user.email, "user@example.com")
        XCTAssertEqual(tokens.user.provider, .email)
        XCTAssertEqual(tokens.user.status, .active)
        XCTAssertEqual(tokens.accessToken, "signup-access")
        let persistedTokens = await tokenStore.loadTokens()
        XCTAssertEqual(persistedTokens, tokens)
    }

    func testAppleLoginRequestUsesIdentityTokenOnlyPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, AuthAPI.Endpoint.loginApple)
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["identityToken"] as? String, "apple-identity-token")
                    XCTAssertEqual(Set(payload.keys), Set(["identityToken"]))

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "apple",
                            status: .active
                        ),
                        accessToken: "apple-access",
                        refreshToken: "apple-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                }
            ),
            tokenStore: tokenStore
        )

        let tokens = try await repository.loginWithApple(
            authorization: AppleLoginAuthorization(
                identityToken: "apple-identity-token",
                authorizationCode: "auth-code",
                userIdentifier: "apple-user",
                email: "user@example.com",
                givenName: "Seokbeom",
                familyName: "Hwang"
            )
        )

        XCTAssertEqual(tokens.accessToken, "apple-access")
        XCTAssertEqual(tokens.user.provider, .apple)
    }

    func testEmailSignUpRequestSendsRequiredConsentPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, AuthAPI.Endpoint.signUp)

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["agreedToTerms"] as? Bool, true)
                    XCTAssertEqual(payload["agreedToPrivacy"] as? Bool, true)
                    XCTAssertNil(payload["agreedToMarketing"])
                    XCTAssertEqual(
                        Set(payload.keys),
                        Set(["email", "password", "nickname", "agreedToTerms", "agreedToPrivacy"])
                    )

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "email",
                            status: .active
                        ),
                        accessToken: "signup-access",
                        refreshToken: "signup-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                }
            ),
            tokenStore: tokenStore
        )

        _ = try await repository.signUpWithEmail(
            email: "user@example.com",
            password: "Password1!",
            nickname: "tester"
        )
    }

    func testGoogleLoginRequestUsesIdentityTokenPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, AuthAPI.Endpoint.loginGoogle)
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["identityToken"] as? String, "google-id-token")
                    XCTAssertEqual(Set(payload.keys), Set(["identityToken"]))

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "google",
                            status: .active
                        ),
                        accessToken: "google-access",
                        refreshToken: "google-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                }
            ),
            tokenStore: tokenStore
        )

        let tokens = try await repository.loginWithGoogle(
            authorization: GoogleLoginAuthorization(
                idToken: "google-id-token",
                accessToken: "google-access-token",
                email: "user@example.com",
                name: "Tester"
            )
        )

        XCTAssertEqual(tokens.accessToken, "google-access")
        XCTAssertEqual(tokens.user.provider, .google)
    }

    func testEmailLoginRequestUsesExpectedEndpointAndPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, "/auth/login/email")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, "user@example.com")
                    XCTAssertEqual(payload["password"] as? String, "Password1!")

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "email",
                            status: .active
                        ),
                        accessToken: "login-access",
                        refreshToken: "login-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                }
            ),
            tokenStore: tokenStore
        )

        let tokens = try await repository.loginWithEmail(email: "user@example.com", password: "Password1!")

        XCTAssertEqual(tokens.accessToken, "login-access")
        let persistedTokens = await tokenStore.loadTokens()
        XCTAssertEqual(persistedTokens, tokens)
    }

    @MainActor
    func testEmailLoginSubmitAuthenticatesSessionAndPersistsTokens() async throws {
        let tokenStore = makeTokenStore()
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/auth/login/email":
                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, "user@example.com")
                    XCTAssertEqual(payload["password"] as? String, "Password1!")

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: "user@example.com",
                            nickname: "tester",
                            provider: "email",
                            status: .active
                        ),
                        accessToken: "login-access",
                        refreshToken: "login-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                case "/me":
                    return (200, try JSONEncoder.app.encode(self.makeProfileDTO()))
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = EmailLoginViewModel(session: session)

        viewModel.updateEmail("User@Example.com ")
        viewModel.updatePassword("Password1!")

        await viewModel.submit()

        XCTAssertEqual(session.authTokens?.accessToken, "login-access")
        XCTAssertEqual(session.profile?.email, "user@example.com")
        XCTAssertNil(viewModel.state.formError)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.authTokens.accessToken, "login-access")
            XCTAssertEqual(authenticatedSession.user.email, "user@example.com")
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state after email login")
        }
    }

    @MainActor
    func testEmailLoginSubmitShowsFieldErrorForMissingAccount() async {
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            urlSession: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/auth/login/email")
                return (
                    404,
                    self.makeServerErrorData(
                        statusCode: 404,
                        code: "ACCOUNT_NOT_FOUND",
                        message: "Account not found.",
                        provider: "email",
                        details: ["email": .string("missing@example.com")]
                    )
                )
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = EmailLoginViewModel(session: session)

        viewModel.updateEmail("missing@example.com")
        viewModel.updatePassword("Password1!")

        await viewModel.submit()

        XCTAssertEqual(viewModel.state.emailValidation, .invalid("가입된 계정을 찾을 수 없습니다"))
        XCTAssertEqual(viewModel.state.formError?.title, "존재하지 않는 계정이에요")
        XCTAssertEqual(viewModel.state.formError?.message, "가입한 이메일인지 다시 확인해 주세요.")
        XCTAssertNil(session.authTokens)
    }

    @MainActor
    func testEmailSignUpSubmitAuthenticatesSessionAndPersistsTokens() async throws {
        let tokenStore = makeTokenStore()
        let expectedEmail = "newuser5678@example.com"
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case AuthAPI.Endpoint.signUp:
                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, expectedEmail)
                    XCTAssertEqual(payload["password"] as? String, "Password1!")
                    XCTAssertEqual(payload["nickname"] as? String, "aa34")
                    XCTAssertEqual(Set(payload.keys), Set(["email", "password", "nickname"]))

                    let response = AuthTokensDTO(
                        user: AuthUserDTO(
                            id: "u1",
                            email: expectedEmail,
                            nickname: "aa34",
                            provider: "email",
                            status: .active
                        ),
                        accessToken: "signup-access",
                        refreshToken: "signup-refresh"
                    )
                    return (200, try JSONEncoder.app.encode(response))
                case "/me":
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer signup-access")
                    let profile = UserProfileDTO(
                        id: "u1",
                        email: expectedEmail,
                        nickname: "aa34",
                        primaryPosition: .mid,
                        secondaryPosition: .top,
                        isFillAvailable: true,
                        styleTags: ["빡겜"],
                        mannerScore: 100,
                        noshowCount: 0
                    )
                    return (200, try JSONEncoder.app.encode(profile))
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = EmailSignUpViewModel(session: session)

        viewModel.updateEmail(expectedEmail)
        viewModel.updatePassword("Password1!")
        viewModel.updatePasswordConfirmation("Password1!")
        viewModel.updateNickname("aa34")

        XCTAssertTrue(viewModel.state.isSubmitEnabled)

        await viewModel.submit()

        let persistedTokens = await tokenStore.loadTokens()
        XCTAssertEqual(persistedTokens?.accessToken, "signup-access")
        XCTAssertEqual(persistedTokens?.refreshToken, "signup-refresh")
        XCTAssertEqual(persistedTokens?.user.provider, .email)
        XCTAssertEqual(persistedTokens?.user.status, .active)
        XCTAssertEqual(session.authTokens?.accessToken, "signup-access")
        XCTAssertEqual(session.profile?.email, expectedEmail)
        XCTAssertNil(viewModel.state.formError)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.authTokens.accessToken, "signup-access")
            XCTAssertEqual(authenticatedSession.user.email, expectedEmail)
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state after email signup")
        }
    }

    @MainActor
    func testEmailSignUpSubmitUsesInputValidationOnly() async {
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            urlSession: makeURLSession { request in
                XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (500, Data())
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = EmailSignUpViewModel(session: session)

        viewModel.updateEmail("user@example.com")
        viewModel.updatePassword("Password1!")
        viewModel.updatePasswordConfirmation("Password1!")
        viewModel.updateNickname("tester1")

        XCTAssertTrue(viewModel.state.isSubmitEnabled)

        viewModel.updateNickname("")

        XCTAssertFalse(viewModel.state.isSubmitEnabled)
    }

    @MainActor
    func testEmailSignUpSubmitShowsFieldErrorForDuplicateEmail() async {
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            urlSession: makeURLSession { request in
                XCTAssertEqual(request.url?.path, AuthAPI.Endpoint.signUp)
                return (
                    409,
                    self.makeServerErrorData(
                        statusCode: 409,
                        code: "EMAIL_ALREADY_IN_USE",
                        message: "Email is already in use.",
                        provider: "email",
                        details: [
                            "email": .string("existing@example.com"),
                            "availableProviders": .array([.string("email")]),
                        ]
                    )
                )
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = EmailSignUpViewModel(session: session)

        viewModel.updateEmail("existing@example.com")
        viewModel.updatePassword("Password1!")
        viewModel.updatePasswordConfirmation("Password1!")
        viewModel.updateNickname("tester1")

        await viewModel.submit()

        XCTAssertEqual(viewModel.state.emailValidation, .invalid("이미 가입된 이메일입니다"))
        XCTAssertNil(viewModel.state.formError)
        XCTAssertNil(session.authTokens)
    }

    func testGuestPreviewDraftsPersistAcrossLocalStoreRecreation() {
        let suiteName = "InhouseMakeriOSTests.localstore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppLocalStore(defaults: defaults)
        var balanceDraft = TeamBalancePreviewDraft.defaultValue
        balanceDraft.selectedMode = .skillFirst
        balanceDraft.players[0].name = "Preview Captain"
        var resultDraft = ResultPreviewDraft.defaultValue(from: balanceDraft)
        resultDraft.winningTeam = .red
        resultDraft.balanceRating = 3

        store.setRecruitFilterType(.opponentRecruit)
        store.setTeamBalancePreviewDraft(balanceDraft)
        store.setResultPreviewDraft(resultDraft)

        let restored = AppLocalStore(defaults: defaults)
        XCTAssertEqual(restored.recruitFilterType, .opponentRecruit)
        XCTAssertEqual(restored.teamBalancePreviewDraft, balanceDraft)
        XCTAssertEqual(restored.resultPreviewDraft, resultDraft)
    }

    func testSavedHistoryMatchIDsPersistAcrossLocalStoreRecreation() {
        let suiteName = "InhouseMakeriOSTests.localstore.saved-history.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppLocalStore(defaults: defaults)
        XCTAssertFalse(store.isHistorySaved(matchID: "match-1"))

        store.setHistorySaved(matchID: " match-1 ", isSaved: true)

        let restored = AppLocalStore(defaults: defaults)
        XCTAssertTrue(restored.isHistorySaved(matchID: "match-1"))
        XCTAssertEqual(restored.savedHistoryMatchIDs, Set(["match-1"]))

        restored.toggleHistorySaved(matchID: "match-1")
        XCTAssertFalse(AppLocalStore(defaults: defaults).isHistorySaved(matchID: "match-1"))
    }

    func testLocalStoreRemoveGroupClearsTrackedGroupAndRecentMatchContext() {
        let suiteName = "InhouseMakeriOSTests.localstore.remove-group.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppLocalStore(defaults: defaults)
        store.trackGroup(id: "group-1", name: "삭제될 그룹")
        store.trackGroup(id: "group-2", name: "남을 그룹")
        store.trackMatch(
            RecentMatchContext(
                matchID: "match-1",
                groupID: "group-1",
                groupName: "삭제될 그룹",
                createdAt: Date(timeIntervalSince1970: 1_713_484_800)
            )
        )

        store.removeGroup(id: "group-1")

        XCTAssertEqual(store.storedGroupIDs, ["group-2"])
        XCTAssertNil(store.groupName(for: "group-1"))
        XCTAssertTrue(store.recentMatches.isEmpty)
    }

    @MainActor
    func testHistoryViewModelFiltersRemoteLocalAndSavedItemsWithoutRefetching() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.history.filters.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        let baseDate = Date(timeIntervalSince1970: 1_776_643_200)

        localStore.cacheResult(
            matchID: "remote-1",
            metadata: CachedResultMetadata(
                winningTeam: .blue,
                mvpUserID: "local-mvp-1",
                balanceRating: 4,
                updatedAt: baseDate.addingTimeInterval(10)
            )
        )
        localStore.cacheResult(
            matchID: "local-only",
            metadata: CachedResultMetadata(
                winningTeam: .red,
                mvpUserID: "local-mvp-2",
                balanceRating: 3,
                updatedAt: baseDate.addingTimeInterval(20)
            )
        )
        localStore.setHistorySaved(matchID: "remote-2", isSaved: true)
        localStore.setHistorySaved(matchID: "local-only", isSaved: true)

        let requestLock = NSLock()
        var historyRequestCount = 0
        let remoteItems = (1...12).map { index in
            HistoryItemDTO(
                matchId: "remote-\(index)",
                scheduledAt: baseDate.addingTimeInterval(Double(index) * 100),
                role: .mid,
                teamSide: index.isMultiple(of: 2) ? .blue : .red,
                result: index.isMultiple(of: 2) ? "WIN" : "LOSE",
                kda: "\(index)/1/5",
                deltaMmr: Double(index)
            )
        }

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/users/u1/inhouse-history"):
                    requestLock.lock()
                    historyRequestCount += 1
                    requestLock.unlock()
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: remoteItems))
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HistoryViewModel(session: session)

        await viewModel.load(force: true, trigger: "test")

        requestLock.lock()
        let initialRequestCount = historyRequestCount
        requestLock.unlock()
        XCTAssertEqual(initialRequestCount, 1)

        guard case let .content(.authenticated(allState)) = viewModel.state else {
            return XCTFail("Expected authenticated history content, got \(viewModel.state)")
        }
        XCTAssertEqual(allState.selectedFilter, .all)
        XCTAssertEqual(allState.allItems.count, 13)
        XCTAssertEqual(allState.displayedItems.count, 13)
        XCTAssertEqual(allState.displayedItems.filter { $0.matchID == "remote-1" }.count, 1)
        XCTAssertEqual(allState.displayedItems.first?.matchID, "remote-12")

        viewModel.selectFilter(.recent)
        guard case let .content(.authenticated(recentState)) = viewModel.state else {
            return XCTFail("Expected recent history content")
        }
        XCTAssertEqual(recentState.selectedFilter, .recent)
        XCTAssertEqual(recentState.displayedItems.count, HistoryViewModel.recentItemLimit)
        XCTAssertEqual(recentState.displayedItems.first?.matchID, "remote-12")
        XCTAssertEqual(recentState.displayedItems.last?.matchID, "remote-3")

        viewModel.selectFilter(.local)
        guard case let .content(.authenticated(localState)) = viewModel.state else {
            return XCTFail("Expected local history content")
        }
        XCTAssertEqual(localState.selectedFilter, .local)
        XCTAssertEqual(localState.displayedItems.map(\.matchID), ["local-only", "remote-1"])
        XCTAssertTrue(localState.displayedItems.allSatisfy { $0.source == .local })

        viewModel.selectFilter(.saved)
        guard case let .content(.authenticated(savedState)) = viewModel.state else {
            return XCTFail("Expected saved history content")
        }
        XCTAssertEqual(savedState.selectedFilter, .saved)
        XCTAssertEqual(savedState.displayedItems.map(\.matchID), ["remote-2", "local-only"])

        viewModel.toggleSaved(matchID: "remote-3")
        guard case let .content(.authenticated(updatedSavedState)) = viewModel.state else {
            return XCTFail("Expected updated saved history content")
        }
        XCTAssertEqual(updatedSavedState.displayedItems.map(\.matchID), ["remote-3", "remote-2", "local-only"])

        requestLock.lock()
        let finalRequestCount = historyRequestCount
        requestLock.unlock()
        XCTAssertEqual(finalRequestCount, 1)
    }

    func testGroupPublicRequestOmitsAuthorizationHeader() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let repository = GroupRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/groups/public")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let payload = try JSONEncoder.app.encode(GroupSummaryListDTO(items: []))
                return (200, payload)
            }
        ))

        let groups = try await repository.listPublic()
        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupProtectedRequestIncludesAuthorizationHeader() async throws {
        let tokenStore = makeTokenStore()
        let tokens = makeTokens()
        await tokenStore.save(tokens: tokens)
        let repository = GroupRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/groups")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(tokens.accessToken)")
                let payload = try JSONEncoder.app.encode(GroupSummaryListDTO(items: []))
                return (200, payload)
            }
        ))

        let groups = try await repository.list()
        XCTAssertTrue(groups.isEmpty)
    }

    func testRecruitingPublicRequestOmitsAuthorizationHeader() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let repository = RecruitingRepository(apiClient: APIClient(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            session: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/recruiting-posts/public")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: []))
                return (200, payload)
            }
        ))

        let posts = try await repository.listPublic(type: .memberRecruit, status: .open)
        XCTAssertTrue(posts.isEmpty)
    }

    @MainActor
    func testBootstrapWithoutPersistedTokensNormalizesFreshInstallToRequiredOnboarding() async {
        let tokenStore = makeTokenStore()
        await tokenStore.clear()
        let suiteName = "InhouseMakeriOSTests.bootstrap.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: AppLocalStore(defaults: defaults)
        )
        let session = AppSessionViewModel(container: container)

        await session.bootstrap()

        switch session.state {
        case .guest:
            XCTAssertTrue(true)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected guest session on first launch without tokens")
        }

        XCTAssertEqual(container.localStore.onboardingStatus, .pending)
        XCTAssertTrue(session.shouldPresentOnboarding)
        XCTAssertEqual(session.onboardingPresentationState, .required)
    }

    @MainActor
    func testBootstrapMigratesLegacyLocalUsageToCompletedOnboarding() async {
        let suiteName = "InhouseMakeriOSTests.bootstrap.legacy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "legacy-group")
        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: localStore
            )
        )

        await session.bootstrap()

        switch session.state {
        case .guest:
            XCTAssertTrue(true)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected legacy install without tokens to land in guest")
        }

        XCTAssertEqual(localStore.onboardingStatus, .completed)
        XCTAssertFalse(session.shouldPresentOnboarding)
        XCTAssertEqual(session.onboardingPresentationState, .completed)
    }

    @MainActor
    func testBootstrapAuthenticatedRestorePromotesPendingOnboardingToCompleted() async {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.bootstrap.authenticated.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.setOnboardingStatus(.pending)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/me":
                    let payload = try JSONEncoder.app.encode(self.makeProfileDTO())
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)

        await session.bootstrap()

        switch session.state {
        case let .authenticated(restoredSession):
            XCTAssertEqual(restoredSession.user.id, "u1")
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated session after successful restore")
        }

        XCTAssertEqual(localStore.onboardingStatus, .completed)
        XCTAssertFalse(session.shouldPresentOnboarding)
        XCTAssertEqual(session.onboardingPresentationState, .completed)
    }

    @MainActor
    func testBootstrapFailedRestoreFallsBackToRequiredOnboardingForFreshInstall() async {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.bootstrap.restorefailure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/me":
                    return (401, self.makeServerErrorData(statusCode: 401, code: "TOKEN_EXPIRED", message: "Expired"))
                case "/auth/refresh":
                    return (401, self.makeServerErrorData(statusCode: 401, code: "AUTH_REQUIRED", message: "Refresh expired"))
                case "/auth/logout":
                    return (200, Data())
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)

        await session.bootstrap()

        switch session.state {
        case .guest:
            XCTAssertTrue(true)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected guest fallback after failed restore")
        }

        XCTAssertEqual(localStore.onboardingStatus, .pending)
        XCTAssertTrue(session.shouldPresentOnboarding)
        XCTAssertEqual(session.onboardingPresentationState, .required)
    }

    @MainActor
    func testCompleteGuestOnboardingPublishesMainFlowTransition() async {
        let suiteName = "InhouseMakeriOSTests.guest.onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: AppLocalStore(defaults: defaults)
            )
        )
        await session.bootstrap()
        XCTAssertTrue(session.shouldPresentOnboarding)

        let didPublish = expectation(description: "session publishes onboarding completion")
        var hasFulfilled = false
        let cancellable = session.objectWillChange.sink {
            guard !hasFulfilled else { return }
            hasFulfilled = true
            didPublish.fulfill()
        }

        session.completeGuestOnboarding()

        await fulfillment(of: [didPublish], timeout: 1.0)
        XCTAssertFalse(session.shouldPresentOnboarding)
        XCTAssertTrue(session.isGuest)
        XCTAssertEqual(session.selectedTab, .home)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testPendingProtectedRouteRunsExactlyOnceAfterLogin() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let router = AppRouter()

        session.openProtectedRoute(.groupDetail("group-1"), requirement: .groupManagement, router: router)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertNotNil(session.authPrompt)

        _ = try await session.completeAuthenticatedSession(
            tokens: makeTokens(),
            event: .login(.apple),
            loadProfile: { self.makeProfile() },
            onSignOut: {}
        )

        XCTAssertEqual(router.path, [.groupDetail("group-1")])
        XCTAssertNil(session.authPrompt)

        session.resumePendingAuthActionIfNeeded()
        XCTAssertEqual(router.path, [.groupDetail("group-1")])

        session.openProtectedRoute(.groupDetail("group-1"), requirement: .groupManagement, router: router)
        XCTAssertEqual(router.path, [.groupDetail("group-1")])
    }

    @MainActor
    func testPassiveAuthPromptDoesNotReplacePendingProtectedRoute() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let router = AppRouter()

        session.openProtectedRoute(.groupDetail("group-1"), requirement: .groupManagement, router: router)
        XCTAssertEqual(session.authPrompt?.requirement, .groupManagement)

        session.requireAuthentication(for: .resultSave)
        XCTAssertEqual(session.authPrompt?.requirement, .groupManagement)

        _ = try await session.completeAuthenticatedSession(
            tokens: makeTokens(),
            event: .login(.google),
            loadProfile: { self.makeProfile() },
            onSignOut: {}
        )

        XCTAssertEqual(router.path, [.groupDetail("group-1")])
        XCTAssertNil(session.authPrompt)
    }

    @MainActor
    func testAuthPromptIsDeferredWhileGroupCreateModalIsActive() {
        let session = AppSessionViewModel(container: AppContainer())

        session.requestModalPresentation(.groupCreate)
        session.requireAuthentication(for: .groupManagement)

        XCTAssertNil(session.authPrompt)
        XCTAssertEqual(session.activeModal, .groupCreate)

        session.handleModalDismissed(.groupCreate)

        XCTAssertEqual(session.authPrompt?.requirement, .groupManagement)
    }

    @MainActor
    func testInteractiveAuthPromptDismissClearsPendingState() {
        let session = AppSessionViewModel(container: AppContainer())
        let router = AppRouter()

        session.openProtectedRoute(.groupDetail("group-1"), requirement: .groupManagement, router: router)
        session.syncAuthPromptPresentation(session.authPrompt)
        XCTAssertEqual(session.activeModal, .loginPrompt)

        session.authPrompt = nil
        session.syncAuthPromptPresentation(nil)

        XCTAssertNil(session.authPrompt)
        XCTAssertNil(session.activeModal)

        session.resumePendingAuthActionIfNeeded()
        XCTAssertTrue(router.path.isEmpty)
    }

    @MainActor
    func testRequireReauthenticationTransitionsSessionToGuestAndPreservesPendingAction() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))

        session.requireReauthentication(for: .groupManagement) {}

        switch session.state {
        case .guest:
            XCTAssertNotNil(session.authPrompt)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected guest state while waiting for reauthentication")
        }
    }

    @MainActor
    func testSignOutKeepsCompletedOnboardingHidden() async {
        let suiteName = "InhouseMakeriOSTests.signout.onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.setOnboardingStatus(.completed)
        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: localStore
            )
        )
        let router = AppRouter()

        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        await session.signOut(router: router)

        switch session.state {
        case .guest:
            XCTAssertTrue(true)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected guest state after sign out")
        }

        XCTAssertEqual(localStore.onboardingStatus, .completed)
        XCTAssertFalse(session.shouldPresentOnboarding)
        XCTAssertEqual(session.onboardingPresentationState, .completed)
    }

    @MainActor
    func testGroupMainViewModelReloadsPublicAndAuthenticatedDataWithoutMixing() async throws {
        let tokenStore = makeTokenStore()
        let suiteName = "InhouseMakeriOSTests.groups.scope.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "private-group")
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/groups/public":
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryListDTO(
                            items: [
                                self.makeGroupSummaryDTO(id: "public-group", name: "공개 그룹"),
                                GroupSummaryDTO(
                                    id: "leaked-private-group",
                                    name: "섞여 내려온 비공개 그룹",
                                    description: "비공개 설명",
                                    visibility: .private,
                                    joinPolicy: .inviteOnly,
                                    tags: ["서울"],
                                    ownerUserId: "owner",
                                    memberCount: 12,
                                    recentMatches: 5
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case "/groups/private-group":
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "private-group", name: "비공개 그룹"))
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = GroupMainViewModel(session: session)

        session.restoreGuestSession()
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.map(\.id), ["public-group"])

        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.first?.name, "비공개 그룹")

        session.restoreGuestSession()
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.map(\.id), ["public-group"])
    }

    func testSearchUseCaseFiltersPrivateGroupsFromSearchResults() async {
        struct MockSearchRepository: SearchRepository {
            let payload: SearchRepositoryPayload

            func loadSearchableResources(forceRefresh: Bool) async -> SearchRepositoryPayload {
                payload
            }
        }

        let useCase = SearchUseCase(
            repository: MockSearchRepository(
                payload: SearchRepositoryPayload(
                    groups: [
                        GroupSummary(
                            id: "public-group",
                            name: "공개 그룹",
                            description: "검색 가능한 그룹",
                            visibility: .public,
                            isMember: nil,
                            joinPolicy: .open,
                            tags: ["서울"],
                            ownerUserID: "owner",
                            memberCount: 10,
                            recentMatches: 4
                        ),
                        GroupSummary(
                            id: "private-group",
                            name: "비공개 그룹",
                            description: "노출되면 안 되는 그룹",
                            visibility: .private,
                            isMember: false,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserID: "owner",
                            memberCount: 8,
                            recentMatches: 3
                        ),
                    ],
                    recruitingPosts: []
                )
            )
        )

        let response = await useCase.execute(query: "그룹", linkedRiotAccounts: [])
        let groupItems = response.sections.first(where: { $0.kind == .group })?.items ?? []

        XCTAssertEqual(groupItems.map(\.title), ["공개 그룹"])
    }

    @MainActor
    func testAppSessionBlocksInaccessiblePrivateGroupRouteBeforePush() {
        let session = AppSessionViewModel(container: AppContainer(configuration: makeConfiguration(), tokenStore: makeTokenStore()))
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let router = AppRouter()
        let inaccessibleGroup = GroupSummary(
            id: "private-group",
            name: "비공개 그룹",
            description: nil,
            visibility: .private,
            isMember: false,
            joinPolicy: .inviteOnly,
            tags: ["서울"],
            ownerUserID: "owner",
            memberCount: 5,
            recentMatches: 0
        )

        session.openGroupDetailIfAccessible(inaccessibleGroup, router: router)

        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(session.actionState, .failure("참여 중인 그룹만 확인할 수 있어요."))
    }

    @MainActor
    func testRecruitBoardViewModelReloadsPublicAndAuthenticatedDataWithoutMixing() async throws {
        let tokenStore = makeTokenStore()
        let suiteName = "InhouseMakeriOSTests.recruit.scope.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts/public":
                    let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: [self.makeRecruitPostDTO(id: "public-post", title: "공개 모집")]))
                    return (200, payload)
                case "/recruiting-posts":
                    let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: [self.makeRecruitPostDTO(id: "auth-post", title: "계정 모집")]))
                    return (200, payload)
                case "/groups/group-1":
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "테스트 그룹"))
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = RecruitBoardViewModel(session: session)

        session.restoreGuestSession()
        await viewModel.load(force: true, trigger: .sessionScopeChange)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "공개 모집")

        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        await viewModel.load(force: true, trigger: .sessionScopeChange)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "계정 모집")

        session.restoreGuestSession()
        await viewModel.load(force: true, trigger: .sessionScopeChange)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "공개 모집")
    }

    @MainActor
    func testGroupMainViewModelRemovesDeletedGroupContextWhenTrackedGroupReturnsNotFound() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group.deleted-reload.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "deleted-group", name: "삭제된 그룹")
        localStore.trackGroup(id: "active-group", name: "남은 그룹")

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/groups/deleted-group":
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Group not found."
                        )
                    )
                case "/groups/active-group":
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "active-group",
                            name: "남은 그룹",
                            description: nil,
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "u1",
                            memberCount: 5,
                            recentMatches: 3
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupMainViewModel(session: session)

        await viewModel.load(force: true)

        XCTAssertEqual(viewModel.state.value?.map(\.id), ["active-group"])
        XCTAssertEqual(localStore.storedGroupIDs, ["active-group"])
    }

    @MainActor
    func testRecruitBoardViewModelHandleCreateSuccessPreservesCreatedPostType() {
        let suiteName = "InhouseMakeriOSTests.recruit.create-success.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)

        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: localStore
            )
        )
        let viewModel = RecruitBoardViewModel(session: session)
        let createdPost = makeRecruitPostDTO(
            id: "created-post",
            title: "새 상대 모집",
            postType: .opponentRecruit
        ).toDomain()

        viewModel.handleCreateSuccess(createdPost)

        XCTAssertEqual(viewModel.selectedType, .opponentRecruit)
        XCTAssertEqual(localStore.recruitFilterType, .opponentRecruit)
        XCTAssertEqual(viewModel.state.value?.selectedType, .opponentRecruit)
        XCTAssertEqual(viewModel.state.value?.posts.map(\.id), ["created-post"])
    }

    @MainActor
    func testRecruitBoardViewModelHandleCreateSuccessKeepsOverflowMenuHiddenForInsertedPost() {
        let suiteName = "InhouseMakeriOSTests.recruit.create-success-overflow.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)

        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: localStore
            )
        )
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)
        let createdPost = RecruitPost(
            id: "created-post",
            groupID: "group-1",
            postType: .memberRecruit,
            title: "새 팀원 모집",
            status: .open,
            scheduledAt: nil,
            body: "본문",
            tags: ["빡겜"],
            requiredPositions: ["MID"],
            createdBy: "u1"
        )

        viewModel.handleCreateSuccess(createdPost)

        XCTAssertEqual(viewModel.state.value?.items.map(\.canShowOverflowMenu), [false])
    }

    @MainActor
    func testRecruitBoardViewModelLoadResolvesOverflowMenuVisibilityFromSnapshotItems() async {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.recruit.load-overflow.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts":
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostListDTO(
                            items: [
                                RecruitPostDTO(
                                    id: "owned-post",
                                    groupId: "group-1",
                                    postType: .memberRecruit,
                                    title: "내 모집",
                                    status: .open,
                                    scheduledAt: nil,
                                    body: "본문",
                                    tags: ["빡겜"],
                                    requiredPositions: ["MID"],
                                    createdBy: "u1"
                                ),
                                RecruitPostDTO(
                                    id: "other-post",
                                    groupId: "group-1",
                                    postType: .memberRecruit,
                                    title: "남의 모집",
                                    status: .open,
                                    scheduledAt: nil,
                                    body: "본문",
                                    tags: ["즐겜"],
                                    requiredPositions: ["SUPPORT"],
                                    createdBy: "tester"
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case "/groups/group-1":
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "테스트 그룹"))
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)

        await viewModel.load(force: true, trigger: .screenAppear)

        XCTAssertEqual(viewModel.state.value?.items.map(\.id), ["owned-post", "other-post"])
        XCTAssertEqual(viewModel.state.value?.items.map(\.canShowOverflowMenu), [true, false])
    }

    @MainActor
    func testRecruitBoardViewModelSwitchTypeIgnoresDuplicateSelection() async {
        let requestLock = NSLock()
        var requestCount = 0
        let suiteName = "InhouseMakeriOSTests.recruit.duplicate-switch.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            localStore: localStore,
            urlSession: makeURLSession { request in
                requestLock.lock()
                requestCount += 1
                requestLock.unlock()
                let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: [self.makeRecruitPostDTO(id: "post-1", title: "모집글")]))
                return (200, payload)
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)

        await viewModel.switchType(.memberRecruit)

        requestLock.lock()
        let capturedRequestCount = requestCount
        requestLock.unlock()
        XCTAssertEqual(capturedRequestCount, 0)
        XCTAssertEqual(viewModel.selectedType, .memberRecruit)
    }

    @MainActor
    func testRecruitBoardViewModelQueuesLatestSelectionWhilePreviousLoadIsInFlight() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let firstRequestStarted = expectation(description: "first recruit request started")
        let secondRequestStarted = expectation(description: "second recruit request started")
        let releaseFirstRequest = DispatchSemaphore(value: 0)
        let requestLock = NSLock()
        var requestedPostTypes: [String] = []
        let suiteName = "InhouseMakeriOSTests.recruit.queue.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                guard request.url?.path == "/recruiting-posts" else {
                    if request.url?.path == "/groups/group-1" {
                        let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "테스트 그룹"))
                        return (200, payload)
                    }
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }

                let postType = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "postType" })?
                    .value ?? ""
                requestLock.lock()
                requestedPostTypes.append(postType)
                requestLock.unlock()

                switch postType {
                case RecruitingPostType.memberRecruit.rawValue:
                    firstRequestStarted.fulfill()
                    _ = releaseFirstRequest.wait(timeout: .now() + 1)
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostListDTO(items: [self.makeRecruitPostDTO(id: "member-post", title: "팀원 모집", postType: .memberRecruit)])
                    )
                    return (200, payload)
                case RecruitingPostType.opponentRecruit.rawValue:
                    secondRequestStarted.fulfill()
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostListDTO(items: [self.makeRecruitPostDTO(id: "opponent-post", title: "상대팀 모집", postType: .opponentRecruit)])
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected postType \(postType)")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)

        let initialLoadTask = Task { await viewModel.load(force: true, trigger: .screenAppear) }
        await fulfillment(of: [firstRequestStarted], timeout: 1)

        let switchTask = Task { await viewModel.switchType(.opponentRecruit) }
        releaseFirstRequest.signal()

        await initialLoadTask.value
        await switchTask.value
        await fulfillment(of: [secondRequestStarted], timeout: 1)
        await Task.yield()

        XCTAssertEqual(viewModel.selectedType, .opponentRecruit)
        XCTAssertEqual(viewModel.state.value?.selectedType, .opponentRecruit)
        XCTAssertEqual(viewModel.state.value?.posts.map(\.id), ["opponent-post"])

        requestLock.lock()
        let capturedRequestedPostTypes = requestedPostTypes
        requestLock.unlock()
        XCTAssertEqual(
            capturedRequestedPostTypes,
            [RecruitingPostType.memberRecruit.rawValue, RecruitingPostType.opponentRecruit.rawValue]
        )
    }

    @MainActor
    func testRecruitBoardViewModelApplyFiltersBuildsQueryAndDedupesDuplicateSelection() async throws {
        let suiteName = "InhouseMakeriOSTests.recruit.filters.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.setRecruitFilterType(.memberRecruit)

        let requestLock = NSLock()
        var requestedURL: URL?
        var requestCount = 0
        let filterDate = Date(timeIntervalSince1970: 1_776_643_200) // 2026-04-20T00:00:00Z
        let filterState = RecruitBoardFilterState(
            selectedDateFilter: RecruitDateFilter(
                preset: .specificDate,
                selectedDate: filterDate,
                includesUnscheduledPosts: false
            ),
            selectedPositions: ["MID", "SUPPORT"],
            selectedRegions: ["서울"],
            selectedTags: ["빡겜"]
        )

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            localStore: localStore,
            urlSession: makeURLSession { request in
                requestLock.lock()
                requestCount += 1
                requestedURL = request.url
                requestLock.unlock()
                let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: []))
                return (200, payload)
            }
        )
        let session = AppSessionViewModel(container: container)
        session.restoreGuestSession()
        let viewModel = RecruitBoardViewModel(session: session)

        await viewModel.applyFilters(filterState, reason: .date)
        await viewModel.applyFilters(filterState, reason: .date)

        requestLock.lock()
        let capturedRequestCount = requestCount
        let capturedRequestedURL = requestedURL
        requestLock.unlock()

        XCTAssertEqual(capturedRequestCount, 1)
        XCTAssertEqual(viewModel.filterState, filterState)
        XCTAssertEqual(capturedRequestedURL?.path, "/recruiting-posts/public")
        XCTAssertEqual(queryItemValues(from: capturedRequestedURL, named: "postType"), [RecruitingPostType.memberRecruit.rawValue])
        XCTAssertEqual(queryItemValues(from: capturedRequestedURL, named: "status"), [RecruitingPostStatus.open.rawValue])
        XCTAssertEqual(Set(queryItemValues(from: capturedRequestedURL, named: "requiredPositions")), ["MID", "SUPPORT"])
        XCTAssertEqual(queryItemValues(from: capturedRequestedURL, named: "region"), ["서울"])
        XCTAssertEqual(queryItemValues(from: capturedRequestedURL, named: "tags"), ["빡겜"])
        XCTAssertTrue(queryItemValues(from: capturedRequestedURL, named: "includeUnscheduled").isEmpty)
        XCTAssertFalse(queryItemValues(from: capturedRequestedURL, named: "scheduledFrom").isEmpty)
        XCTAssertFalse(queryItemValues(from: capturedRequestedURL, named: "scheduledTo").isEmpty)
    }

    @MainActor
    func testHomeViewModelRecruitingFailureKeepsContentAndOmitsUnsupportedQuery() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.recruiting-failure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        let requestLock = NSLock()
        var capturedRecruitingURL: URL?
        let historyDate = Date(timeIntervalSince1970: 1_776_643_200)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/recruiting-posts"):
                    requestLock.lock()
                    capturedRecruitingURL = request.url
                    requestLock.unlock()
                    return (
                        400,
                        self.makeServerErrorData(
                            statusCode: 400,
                            code: "INVALID_PAYLOAD",
                            message: "Payload is invalid.",
                            details: [
                                "validationErrors": .array([
                                    .object([
                                        "field": .string("includeUnscheduled"),
                                        "message": .string("property includeUnscheduled should not exist"),
                                    ]),
                                ]),
                            ]
                        )
                    )
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(RiotAccountListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(
                        HistoryResponseDTO(
                            items: [
                                HistoryItemDTO(
                                    matchId: "match-1",
                                    scheduledAt: historyDate,
                                    role: .mid,
                                    teamSide: .blue,
                                    result: "WIN",
                                    kda: "3/1/5",
                                    deltaMmr: 12
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test")

        requestLock.lock()
        let requestedRecruitingURL = capturedRecruitingURL
        requestLock.unlock()

        XCTAssertEqual(requestedRecruitingURL?.path, "/recruiting-posts")
        XCTAssertTrue(queryItemValues(from: requestedRecruitingURL, named: "includeUnscheduled").isEmpty)

        switch viewModel.state {
        case let .content(.authenticated(snapshot)):
            XCTAssertTrue(snapshot.recruitingPosts.isEmpty)
            XCTAssertEqual(snapshot.latestHistory?.matchID, "match-1")
            if case let .error(error) = snapshot.publicContentSectionState {
                XCTAssertEqual(error.statusCode, 400)
            } else {
                XCTFail("Expected public content section error")
            }
            if case let .populated(latestHistory) = snapshot.recentMatchesSectionState {
                XCTAssertEqual(latestHistory.matchID, "match-1")
            } else {
                XCTFail("Expected recent matches section content")
            }
        case let .error(error):
            XCTFail("Expected home content, got error: \(error.title) / \(error.message)")
        default:
            XCTFail("Expected authenticated home content")
        }
    }

    @MainActor
    func testHomeViewModelAuthenticatedEmptyResponseKeepsHomeLayoutContent() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.authenticated-empty.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: AppLocalStore(defaults: defaults),
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/recruiting-posts"):
                    return (200, try JSONEncoder.app.encode(RecruitPostListDTO(items: [])))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [])))
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test_authenticated_empty")

        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isInitialLoading)

        switch viewModel.state {
        case let .content(.authenticated(snapshot)):
            XCTAssertTrue(snapshot.groups.isEmpty)
            XCTAssertNil(snapshot.currentMatch)
            XCTAssertNil(snapshot.latestHistory)
            XCTAssertTrue(snapshot.recruitingPosts.isEmpty)
            XCTAssertEqual(snapshot.scheduledMatchesSectionState, .empty)
            XCTAssertEqual(snapshot.recentGroupsSectionState, .empty)
            XCTAssertEqual(snapshot.publicContentSectionState, .empty)
            XCTAssertEqual(snapshot.localRecordsSectionState, .empty)
            XCTAssertEqual(snapshot.recentMatchesSectionState, .empty)
        default:
            XCTFail("Expected authenticated home content instead of root empty state")
        }
    }

    @MainActor
    func testHomeViewModelGuestEmptyResponseKeepsHomeLayoutContent() async throws {
        let suiteName = "InhouseMakeriOSTests.home.guest-empty.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = AppContainer(
            configuration: makeConfiguration(),
            localStore: AppLocalStore(defaults: defaults),
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/public"):
                    return (200, try JSONEncoder.app.encode(GroupSummaryListDTO(items: [])))
                case ("GET", "/recruiting-posts/public"):
                    return (200, try JSONEncoder.app.encode(RecruitPostListDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.restoreGuestSession()
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test_guest_empty")

        switch viewModel.state {
        case let .content(.guest(snapshot)):
            XCTAssertTrue(snapshot.groups.isEmpty)
            XCTAssertTrue(snapshot.recruitingPosts.isEmpty)
            XCTAssertNil(snapshot.latestLocalResult)
            XCTAssertEqual(snapshot.scheduledMatchesSectionState, .empty)
            XCTAssertEqual(snapshot.recentGroupsSectionState, .empty)
            XCTAssertEqual(snapshot.publicContentSectionState, .empty)
            XCTAssertEqual(snapshot.localRecordsSectionState, .empty)
        default:
            XCTFail("Expected guest home content instead of root empty state")
        }
    }

    @MainActor
    func testHomeViewModelDoesNotRestoreRemovedDeletedGroupOnInitialLoad() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.deleted-group-restore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "deleted-group", name: "삭제된 그룹")
        localStore.trackGroup(id: "active-group", name: "남은 그룹")
        localStore.removeGroup(id: "deleted-group")

        let requestLock = NSLock()
        var requestedPaths: [String] = []
        let historyDate = Date(timeIntervalSince1970: 1_776_643_200)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                requestLock.lock()
                requestedPaths.append(request.url?.path ?? "nil")
                requestLock.unlock()

                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryListDTO(
                            items: [
                                GroupSummaryDTO(
                                    id: "active-group",
                                    name: "남은 그룹",
                                    description: nil,
                                    visibility: .private,
                                    joinPolicy: .inviteOnly,
                                    tags: ["서울"],
                                    ownerUserId: "u1",
                                    memberCount: 5,
                                    recentMatches: 0
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/recruiting-posts"):
                    let payload = try JSONEncoder.app.encode(RecruitPostListDTO(items: []))
                    return (200, payload)
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(RiotAccountListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(
                        HistoryResponseDTO(
                            items: [
                                HistoryItemDTO(
                                    matchId: "match-1",
                                    scheduledAt: historyDate,
                                    role: .mid,
                                    teamSide: .blue,
                                    result: "WIN",
                                    kda: "3/1/5",
                                    deltaMmr: 12
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "scene_reenter")

        requestLock.lock()
        let capturedPaths = requestedPaths
        requestLock.unlock()

        XCTAssertFalse(capturedPaths.contains("/groups/deleted-group"))
        XCTAssertTrue(capturedPaths.contains("/groups"))
        XCTAssertEqual(localStore.storedGroupIDs, ["active-group"])
    }

    @MainActor
    func testHomeViewModelClearsStaleUITestHomeContextAndKeepsContent() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.stale-ui-seed.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "group-ui-test", name: "오래된 UI 테스트 그룹")
        localStore.trackGroup(id: "active-group", name: "남은 그룹")
        localStore.trackMatch(
            RecentMatchContext(
                matchID: "match-ui-test",
                groupID: "group-ui-test",
                groupName: "오래된 UI 테스트 그룹",
                createdAt: Date(timeIntervalSince1970: 1_713_484_800)
            )
        )

        let requestLock = NSLock()
        var requestedPaths: [String] = []
        let historyDate = Date(timeIntervalSince1970: 1_776_643_200)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                requestLock.lock()
                requestedPaths.append(request.url?.path ?? "nil")
                requestLock.unlock()

                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryListDTO(
                            items: [
                                GroupSummaryDTO(
                                    id: "active-group",
                                    name: "남은 그룹",
                                    description: nil,
                                    visibility: .private,
                                    joinPolicy: .inviteOnly,
                                    tags: ["서울"],
                                    ownerUserId: "u1",
                                    memberCount: 5,
                                    recentMatches: 0
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/recruiting-posts"):
                    return (200, try JSONEncoder.app.encode(RecruitPostListDTO(items: [])))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [])))
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(
                        HistoryResponseDTO(
                            items: [
                                HistoryItemDTO(
                                    matchId: "match-1",
                                    scheduledAt: historyDate,
                                    role: .mid,
                                    teamSide: .blue,
                                    result: "WIN",
                                    kda: "3/1/5",
                                    deltaMmr: 12
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test_ui_seed_cleanup")

        requestLock.lock()
        let capturedPaths = requestedPaths
        requestLock.unlock()

        XCTAssertFalse(capturedPaths.contains("/matches/match-ui-test"))
        XCTAssertEqual(localStore.storedGroupIDs, ["active-group"])
        XCTAssertTrue(localStore.recentMatches.isEmpty)

        switch viewModel.state {
        case let .content(.authenticated(snapshot)):
            XCTAssertEqual(snapshot.groups.map(\.id), ["active-group"])
            XCTAssertNil(snapshot.currentMatch)
            XCTAssertEqual(snapshot.latestHistory?.matchID, "match-1")
            if case let .populated(groups) = snapshot.recentGroupsSectionState {
                XCTAssertEqual(groups.map(\.id), ["active-group"])
            } else {
                XCTFail("Expected recent groups section content")
            }
            if case let .error(error) = snapshot.scheduledMatchesSectionState {
                XCTAssertEqual(error.title, "예정된 내전 로딩 실패")
            } else {
                XCTFail("Expected scheduled matches section error")
            }
        default:
            XCTFail("Expected authenticated home content")
        }
    }

    @MainActor
    func testHomeViewModelClearsMissingCurrentMatchAndKeepsContent() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.missing-current-match.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "active-group", name: "남은 그룹")
        localStore.trackMatch(
            RecentMatchContext(
                matchID: "missing-match",
                groupID: "active-group",
                groupName: "남은 그룹",
                createdAt: Date(timeIntervalSince1970: 1_713_484_800)
            )
        )

        let historyDate = Date(timeIntervalSince1970: 1_776_643_200)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryListDTO(
                            items: [
                                GroupSummaryDTO(
                                    id: "active-group",
                                    name: "남은 그룹",
                                    description: nil,
                                    visibility: .private,
                                    joinPolicy: .inviteOnly,
                                    tags: ["서울"],
                                    ownerUserId: "u1",
                                    memberCount: 5,
                                    recentMatches: 0
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/matches/missing-match"):
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "MATCH_NOT_FOUND",
                            message: "Match not found."
                        )
                    )
                case ("GET", "/recruiting-posts"):
                    return (200, try JSONEncoder.app.encode(RecruitPostListDTO(items: [])))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [])))
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(
                        HistoryResponseDTO(
                            items: [
                                HistoryItemDTO(
                                    matchId: "match-1",
                                    scheduledAt: historyDate,
                                    role: .mid,
                                    teamSide: .blue,
                                    result: "WIN",
                                    kda: "3/1/5",
                                    deltaMmr: 12
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test_missing_current_match")

        XCTAssertTrue(localStore.recentMatches.isEmpty)

        switch viewModel.state {
        case let .content(.authenticated(snapshot)):
            XCTAssertEqual(snapshot.groups.map(\.id), ["active-group"])
            XCTAssertNil(snapshot.currentMatch)
            XCTAssertEqual(snapshot.latestHistory?.matchID, "match-1")
            if case let .populated(groups) = snapshot.recentGroupsSectionState {
                XCTAssertEqual(groups.map(\.id), ["active-group"])
            } else {
                XCTFail("Expected recent groups section content")
            }
            if case let .error(error) = snapshot.scheduledMatchesSectionState {
                XCTAssertEqual(error.title, "예정된 내전 로딩 실패")
            } else {
                XCTFail("Expected scheduled matches section error")
            }
        default:
            XCTFail("Expected authenticated home content")
        }
    }

    @MainActor
    func testHomeViewModelRecentHistoryFailureKeepsContentWithSectionError() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.home.history-failure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "active-group", name: "남은 그룹")
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryListDTO(
                            items: [
                                GroupSummaryDTO(
                                    id: "active-group",
                                    name: "남은 그룹",
                                    description: nil,
                                    visibility: .private,
                                    joinPolicy: .inviteOnly,
                                    tags: ["서울"],
                                    ownerUserId: "u1",
                                    memberCount: 5,
                                    recentMatches: 0
                                ),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/recruiting-posts"):
                    return (200, try JSONEncoder.app.encode(RecruitPostListDTO(items: [])))
                case ("GET", "/riot-accounts"):
                    return (200, try JSONEncoder.app.encode(RiotAccountListDTO(items: [])))
                case ("GET", "/users/u1/inhouse-history"):
                    return (
                        500,
                        self.makeServerErrorData(
                            statusCode: 500,
                            code: "INTERNAL_SERVER_ERROR",
                            message: "History failed."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = HomeViewModel(session: session)

        await viewModel.load(force: true, trigger: "test_history_failure")

        switch viewModel.state {
        case let .content(.authenticated(snapshot)):
            if case let .populated(groups) = snapshot.recentGroupsSectionState {
                XCTAssertEqual(groups.map(\.id), ["active-group"])
            } else {
                XCTFail("Expected recent groups section content")
            }
            if case let .error(error) = snapshot.recentMatchesSectionState {
                XCTAssertEqual(error.statusCode, 500)
            } else {
                XCTFail("Expected recent matches section error")
            }
        default:
            XCTFail("Expected authenticated home content")
        }
    }

    @MainActor
    func testGroupMainViewModelCreateGroupDefersLoginPromptUntilSheetDismissWhenAuthExpires() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/groups":
                    return (401, Data())
                case "/auth/refresh":
                    return (401, Data())
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        session.requestModalPresentation(.groupCreate)
        let viewModel = GroupMainViewModel(session: session)

        let result = await viewModel.createGroup(name: "테스트 그룹", description: "설명", tags: ["서울"])

        switch result {
        case .requiresAuthentication:
            XCTAssertTrue(true)
        case let .failure(message):
            XCTFail("Expected authentication recovery, got failure: \(message)")
        case .success:
            XCTFail("Expected authentication recovery result")
        }

        XCTAssertEqual(viewModel.actionState, .idle)
        XCTAssertEqual(session.activeModal, .groupCreate)
        XCTAssertNil(session.authPrompt)

        session.handleModalDismissed(.groupCreate)

        XCTAssertEqual(session.authPrompt?.requirement, .groupManagement)
    }

    @MainActor
    func testRecruitBoardViewModelCreatePostDefersLoginPromptUntilSheetDismissWhenAuthExpires() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts":
                    return (401, Data())
                case "/auth/refresh":
                    return (401, Data())
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        session.requestModalPresentation(.recruitCreate)
        let viewModel = RecruitBoardViewModel(session: session)

        let result = await viewModel.createPost(
            groupID: "group-1",
            title: "테스트 모집",
            body: "본문",
            tags: ["빡겜"],
            scheduledAt: nil,
            positions: ["MID"]
        )

        switch result {
        case .requiresAuthentication:
            XCTAssertTrue(true)
        case let .failure(message):
            XCTFail("Expected authentication recovery, got failure: \(message)")
        case let .invalidGroupContext(message):
            XCTFail("Expected authentication recovery, got invalid group context: \(message)")
        case .success:
            XCTFail("Expected authentication recovery result")
        }

        XCTAssertEqual(viewModel.actionState, .idle)
        XCTAssertEqual(session.activeModal, .recruitCreate)
        XCTAssertNil(session.authPrompt)

        session.handleModalDismissed(.recruitCreate)

        XCTAssertEqual(session.authPrompt?.requirement, .recruitingWrite)
    }

    @MainActor
    func testRecruitBoardViewModelCreatePostBlocksWhenGroupContextIsInvalid() async {
        let suiteName = "InhouseMakeriOSTests.recruit.invalid-context.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        let session = AppSessionViewModel(
            container: AppContainer(
                configuration: makeConfiguration(),
                tokenStore: makeTokenStore(),
                localStore: localStore
            )
        )
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)

        let result = await viewModel.createPost(
            groupID: "deleted-group",
            title: "테스트 모집",
            body: "본문",
            tags: ["빡겜"],
            scheduledAt: nil,
            positions: ["MID"]
        )

        switch result {
        case let .invalidGroupContext(message):
            XCTAssertEqual(message, "모집글을 연결할 그룹이 없습니다. 먼저 그룹을 생성해주세요.")
        case .failure, .requiresAuthentication, .success:
            XCTFail("Expected invalid group context result")
        }

        XCTAssertEqual(viewModel.actionState, .failure("모집글을 연결할 그룹이 없습니다. 먼저 그룹을 생성해주세요."))
    }

    @MainActor
    func testRecruitBoardViewModelCreatePostMapsGroupNotFoundToInvalidContextAndClearsStoredGroup() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.recruit.group-not-found.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "group-1", name: "삭제될 그룹")
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts":
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Group not found."
                        )
                    )
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitBoardViewModel(session: session)

        let result = await viewModel.createPost(
            groupID: "group-1",
            title: "테스트 모집",
            body: "본문",
            tags: ["빡겜"],
            scheduledAt: nil,
            positions: ["MID"]
        )

        switch result {
        case let .invalidGroupContext(message):
            XCTAssertEqual(message, "삭제되었거나 존재하지 않는 그룹입니다.")
        case .failure, .requiresAuthentication, .success:
            XCTFail("Expected invalid group context result")
        }

        XCTAssertTrue(localStore.storedGroupIDs.isEmpty)
        XCTAssertEqual(viewModel.actionState, .failure("삭제되었거나 존재하지 않는 그룹입니다."))
    }

    @MainActor
    func testRecruitDetailViewModelMapsNotFoundToEmptyState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts/post-404":
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RECRUITING_POST_NOT_FOUND",
                            message: "Not found"
                        )
                    )
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitDetailViewModel(session: session, postID: "post-404")

        await viewModel.load(trigger: .screenAppear)

        switch viewModel.state {
        case let .empty(message):
            XCTAssertEqual(message, "이 모집글을 찾을 수 없습니다.")
        default:
            XCTFail("Expected empty state, got \(viewModel.state)")
        }
    }

    @MainActor
    func testRecruitDetailViewModelMapsForbiddenToPermissionError() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts/post-403":
                    return (
                        403,
                        self.makeServerErrorData(
                            statusCode: 403,
                            code: "FORBIDDEN_FEATURE",
                            message: "Forbidden"
                        )
                    )
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitDetailViewModel(session: session, postID: "post-403")

        await viewModel.load(trigger: .screenAppear)

        switch viewModel.state {
        case let .error(error):
            XCTAssertEqual(error.title, "권한이 없어요")
            XCTAssertEqual(error.statusCode, 403)
        default:
            XCTFail("Expected forbidden error state, got \(viewModel.state)")
        }
    }

    @MainActor
    func testRecruitDetailViewModelBuildsDisplayStateWithoutRawIdentifiers() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.recruit.detail-display.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch request.url?.path {
                case "/recruiting-posts/post-1":
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostDTO(
                            id: "post-1",
                            groupId: "group-1",
                            postType: .memberRecruit,
                            title: "테스트 모집",
                            status: .open,
                            scheduledAt: nil,
                            body: "본문",
                            tags: ["빡겜"],
                            requiredPositions: ["MID"],
                            createdBy: "u1"
                        )
                    )
                    return (200, payload)
                case "/groups/group-1":
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "우리 모임"))
                    return (200, payload)
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitDetailViewModel(session: session, postID: "post-1")

        await viewModel.load(trigger: .screenAppear)

        guard case let .content(viewState) = viewModel.state else {
            return XCTFail("Expected content state, got \(viewModel.state)")
        }

        XCTAssertEqual(viewState.title, "테스트 모집")
        XCTAssertEqual(viewState.groupName, "우리 모임")
        XCTAssertNotEqual(viewState.groupName, "group-1")
        XCTAssertEqual(viewState.authorName, "tester")
        XCTAssertEqual(viewState.requiredPositionsText, "MID")
        XCTAssertEqual(viewState.statusText, "모집 중")
        XCTAssertEqual(viewState.moodTagsText, "빡겜")
        XCTAssertEqual(viewState.bodyText, "본문")
        XCTAssertTrue(viewState.isOwner)
        XCTAssertTrue(viewModel.isDeleteVisible)
    }

    @MainActor
    func testRecruitDetailViewModelDeletePostCallsDeleteEndpoint() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let deleteRequestReceived = expectation(description: "delete recruit request received")
        let requestLock = NSLock()
        var deleteRequestMethod: String?
        var deleteRequestPath: String?

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/recruiting-posts/post-1"):
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostDTO(
                            id: "post-1",
                            groupId: "group-1",
                            postType: .memberRecruit,
                            title: "테스트 모집",
                            status: .open,
                            scheduledAt: nil,
                            body: "본문",
                            tags: ["빡겜"],
                            requiredPositions: ["MID"],
                            createdBy: "u1"
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "우리 모임"))
                    return (200, payload)
                case ("DELETE", "/recruiting-posts/post-1"):
                    requestLock.lock()
                    deleteRequestMethod = request.httpMethod
                    deleteRequestPath = request.url?.path
                    requestLock.unlock()
                    deleteRequestReceived.fulfill()
                    return (204, Data())
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitDetailViewModel(session: session, postID: "post-1")

        await viewModel.load(trigger: .screenAppear)
        let deletedPost = await viewModel.deletePost()
        await fulfillment(of: [deleteRequestReceived], timeout: 1)

        requestLock.lock()
        let capturedDeleteRequestMethod = deleteRequestMethod
        let capturedDeleteRequestPath = deleteRequestPath
        requestLock.unlock()

        XCTAssertEqual(deletedPost?.id, "post-1")
        XCTAssertEqual(capturedDeleteRequestMethod, "DELETE")
        XCTAssertEqual(capturedDeleteRequestPath, "/recruiting-posts/post-1")
        XCTAssertEqual(viewModel.actionState, .success("모집글이 삭제되었습니다"))
    }

    @MainActor
    func testRecruitDetailViewModelUpdatePostCallsPatchEndpoint() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var patchRequestMethod: String?
        var patchRequestPath: String?
        var patchRequestBody: [String: Any]?
        let scheduledAt = Date(timeIntervalSince1970: 1_776_686_400) // 2026-04-20T12:00:00Z

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/recruiting-posts/post-1"):
                    let payload = try JSONEncoder.app.encode(
                        RecruitPostDTO(
                            id: "post-1",
                            groupId: "group-1",
                            postType: .memberRecruit,
                            title: "기존 모집",
                            status: .open,
                            scheduledAt: nil,
                            body: "기존 본문",
                            tags: ["빡겜"],
                            requiredPositions: ["MID"],
                            createdBy: "u1"
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(self.makeGroupSummaryDTO(id: "group-1", name: "우리 모임"))
                    return (200, payload)
                case ("PATCH", "/recruiting-posts/post-1"):
                    requestLock.lock()
                    patchRequestMethod = request.httpMethod
                    patchRequestPath = request.url?.path
                    patchRequestBody = self.requestBodyJSONObject(from: request)
                    requestLock.unlock()

                    let payload = try JSONEncoder.app.encode(
                        RecruitPostDTO(
                            id: "post-1",
                            groupId: "group-1",
                            postType: .memberRecruit,
                            title: "수정된 모집",
                            status: .open,
                            scheduledAt: scheduledAt,
                            body: "수정 본문",
                            tags: ["즐겜", "주말"],
                            requiredPositions: ["ADC", "SUPPORT"],
                            createdBy: "u1"
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RecruitDetailViewModel(session: session, postID: "post-1")

        await viewModel.load(trigger: .screenAppear)
        let updatedPost = await viewModel.updatePost(
            title: "수정된 모집",
            body: "수정 본문",
            tags: ["즐겜", "주말"],
            scheduledAt: scheduledAt,
            requiredPositions: ["ADC", "SUPPORT"]
        )

        requestLock.lock()
        let capturedPatchRequestMethod = patchRequestMethod
        let capturedPatchRequestPath = patchRequestPath
        let capturedPatchRequestBody = patchRequestBody
        requestLock.unlock()

        XCTAssertEqual(capturedPatchRequestMethod, "PATCH")
        XCTAssertEqual(capturedPatchRequestPath, "/recruiting-posts/post-1")
        XCTAssertEqual(capturedPatchRequestBody?["postType"] as? String, RecruitingPostType.memberRecruit.rawValue)
        XCTAssertEqual(capturedPatchRequestBody?["title"] as? String, "수정된 모집")
        XCTAssertEqual(capturedPatchRequestBody?["body"] as? String, "수정 본문")
        XCTAssertEqual(Set(capturedPatchRequestBody?["tags"] as? [String] ?? []), ["즐겜", "주말"])
        XCTAssertEqual(Set(capturedPatchRequestBody?["requiredPositions"] as? [String] ?? []), ["ADC", "SUPPORT"])
        XCTAssertNotNil(capturedPatchRequestBody?["scheduledAt"] as? String)
        XCTAssertEqual(updatedPost?.title, "수정된 모집")
        XCTAssertEqual(viewModel.actionState, .success("모집글이 수정되었습니다"))

        guard case let .content(viewState) = viewModel.state else {
            return XCTFail("Expected content state, got \(viewModel.state)")
        }
        XCTAssertEqual(viewState.title, "수정된 모집")
        XCTAssertEqual(viewState.requiredPositionsText, "ADC, SUPPORT")
        XCTAssertEqual(viewState.moodTagsText, "즐겜, 주말")
    }

    @MainActor
    func testGroupDetailViewModelDoesNotTrackPublicGroupForNonMember() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group.public-nonmember.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/public-group"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "public-group",
                            name: "공개 그룹",
                            description: "설명",
                            visibility: .public,
                            joinPolicy: .open,
                            tags: ["서울"],
                            ownerUserId: "owner",
                            memberCount: 12,
                            recentMatches: 4
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/public-group/members"):
                    let payload = try JSONEncoder.app.encode(GroupMemberListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: []))
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "public-group")

        await viewModel.load(trigger: .screenAppear)

        XCTAssertFalse(localStore.containsGroup(id: "public-group"))
        XCTAssertEqual(viewModel.state.value?.group.id, "public-group")
    }

    @MainActor
    func testGroupDetailViewModelTracksPrivateGroupForMember() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group.private-member.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/private-group"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "private-group",
                            name: "우리 비공개 그룹",
                            description: "설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "owner",
                            memberCount: 5,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/private-group/members"):
                    let payload = try JSONEncoder.app.encode(
                        GroupMemberListDTO(
                            items: [
                                GroupMemberDTO(id: "gm-1", userId: "u1", nickname: "tester", role: .member),
                            ]
                        )
                    )
                    return (200, payload)
                case (_, let path?) where path.hasSuffix("/power-profile"):
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Power profile not found."
                        )
                    )
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: []))
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "private-group")

        await viewModel.load(trigger: .screenAppear)

        XCTAssertTrue(localStore.containsGroup(id: "private-group"))
        XCTAssertEqual(localStore.groupName(for: "private-group"), "우리 비공개 그룹")
    }

    @MainActor
    func testGroupDetailViewModelKeepsForbiddenFallbackMessage() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/private-group"):
                    return (
                        403,
                        self.makeServerErrorData(
                            statusCode: 403,
                            code: "GROUP_ACCESS_FORBIDDEN",
                            message: "Group access forbidden."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "private-group")

        await viewModel.load(trigger: .screenAppear)

        guard case let .error(error) = viewModel.state else {
            return XCTFail("Expected forbidden error state, got \(viewModel.state)")
        }
        XCTAssertEqual(error.title, "그룹에 접근할 수 없어요")
        XCTAssertEqual(error.message, "참여 중인 그룹만 확인할 수 있어요.")
        XCTAssertEqual(error.statusCode, 403)
    }

    @MainActor
    func testGroupDetailViewModelUpdateGroupCallsPatchEndpoint() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var patchRequestMethod: String?
        var patchRequestPath: String?
        var patchRequestBody: [String: Any]?

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "기존 방",
                            description: "기존 설명",
                            visibility: .public,
                            joinPolicy: .open,
                            tags: ["서울", "빡겜"],
                            ownerUserId: "u1",
                            memberCount: 5,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    let payload = try JSONEncoder.app.encode(GroupMemberListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: []))
                    return (200, payload)
                case ("PATCH", "/groups/group-1"):
                    requestLock.lock()
                    patchRequestMethod = request.httpMethod
                    patchRequestPath = request.url?.path
                    patchRequestBody = self.requestBodyJSONObject(from: request)
                    requestLock.unlock()

                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "수정된 방",
                            description: "수정 설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["경기", "즐겜"],
                            ownerUserId: "u1",
                            memberCount: 5,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)
        let updatedGroup = await viewModel.updateGroup(
            name: "수정된 방",
            description: "수정 설명",
            visibility: .private,
            joinPolicy: .inviteOnly,
            tags: ["경기", "즐겜"]
        )

        requestLock.lock()
        let capturedPatchRequestMethod = patchRequestMethod
        let capturedPatchRequestPath = patchRequestPath
        let capturedPatchRequestBody = patchRequestBody
        requestLock.unlock()

        XCTAssertEqual(capturedPatchRequestMethod, "PATCH")
        XCTAssertEqual(capturedPatchRequestPath, "/groups/group-1")
        XCTAssertEqual(capturedPatchRequestBody?["name"] as? String, "수정된 방")
        XCTAssertEqual(capturedPatchRequestBody?["description"] as? String, "수정 설명")
        XCTAssertEqual(capturedPatchRequestBody?["visibility"] as? String, GroupVisibility.private.rawValue)
        XCTAssertEqual(capturedPatchRequestBody?["joinPolicy"] as? String, JoinPolicy.inviteOnly.rawValue)
        XCTAssertEqual(Set(capturedPatchRequestBody?["tags"] as? [String] ?? []), ["경기", "즐겜"])
        XCTAssertEqual(updatedGroup?.name, "수정된 방")
        XCTAssertEqual(viewModel.actionState, .success("내전 방 정보가 수정되었습니다"))
        XCTAssertEqual(viewModel.state.value?.group.name, "수정된 방")
    }

    @MainActor
    func testGroupDetailViewModelDeleteGroupMapsNotFoundToExplicitMessage() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var deleteRequestMethod: String?
        var deleteRequestPath: String?

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "기존 방",
                            description: "기존 설명",
                            visibility: .public,
                            joinPolicy: .open,
                            tags: ["서울", "빡겜"],
                            ownerUserId: "u1",
                            memberCount: 5,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    let payload = try JSONEncoder.app.encode(GroupMemberListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: []))
                    return (200, payload)
                case ("DELETE", "/groups/group-1"):
                    requestLock.lock()
                    deleteRequestMethod = request.httpMethod
                    deleteRequestPath = request.url?.path
                    requestLock.unlock()
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "GROUP_DELETE_ENDPOINT_NOT_READY",
                            message: "Not found"
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)
        let deletedGroupID = await viewModel.deleteGroup()

        requestLock.lock()
        let capturedDeleteRequestMethod = deleteRequestMethod
        let capturedDeleteRequestPath = deleteRequestPath
        requestLock.unlock()

        XCTAssertNil(deletedGroupID)
        XCTAssertEqual(capturedDeleteRequestMethod, "DELETE")
        XCTAssertEqual(capturedDeleteRequestPath, "/groups/group-1")
        XCTAssertEqual(viewModel.actionState, .failure("이미 삭제되었거나 서버에서 삭제 기능을 아직 지원하지 않습니다."))
    }

    @MainActor
    func testGroupDetailViewModelDeleteGroupClearsContextAndSkipsFurtherReloads() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group-detail.delete-success.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackGroup(id: "group-1", name: "삭제될 방")

        let requestLock = NSLock()
        var groupDetailGetCount = 0
        var membersGetCount = 0
        var deleteCount = 0

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    requestLock.lock()
                    groupDetailGetCount += 1
                    requestLock.unlock()
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "삭제될 방",
                            description: "설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "u1",
                            memberCount: 5,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    requestLock.lock()
                    membersGetCount += 1
                    requestLock.unlock()
                    let payload = try JSONEncoder.app.encode(GroupMemberListDTO(items: []))
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    let payload = try JSONEncoder.app.encode(HistoryResponseDTO(items: []))
                    return (200, payload)
                case ("DELETE", "/groups/group-1"):
                    requestLock.lock()
                    deleteCount += 1
                    requestLock.unlock()
                    return (200, Data("{}".utf8))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)
        let deletedGroupID = await viewModel.deleteGroup()
        await viewModel.load(force: true, trigger: .retry)

        requestLock.lock()
        let capturedDetailGetCount = groupDetailGetCount
        let capturedMembersGetCount = membersGetCount
        let capturedDeleteCount = deleteCount
        requestLock.unlock()

        XCTAssertEqual(deletedGroupID, "group-1")
        XCTAssertEqual(capturedDetailGetCount, 1)
        XCTAssertEqual(capturedMembersGetCount, 1)
        XCTAssertEqual(capturedDeleteCount, 1)
        XCTAssertTrue(localStore.storedGroupIDs.isEmpty)
        XCTAssertEqual(viewModel.actionState, .success("내전 방이 삭제되었습니다"))
    }

    @MainActor
    func testGroupDetailViewModelInviteMemberUsesActualUserIDAndUpdatesSnapshot() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var capturedPostBody: [String: Any]?
        var membersGetCount = 0

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "테스트 그룹",
                            description: "설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "u1",
                            memberCount: 1,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    requestLock.lock()
                    membersGetCount += 1
                    requestLock.unlock()
                    let payload = try JSONEncoder.app.encode(
                        GroupMemberListDTO(
                            items: [
                                GroupMemberDTO(id: "gm-owner", userId: "u1", nickname: "tester", role: .owner),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                case ("POST", "/groups/group-1/members"):
                    requestLock.lock()
                    capturedPostBody = self.requestBodyJSONObject(from: request)
                    requestLock.unlock()
                    let payload = try JSONEncoder.app.encode(
                        GroupMemberListDTO(
                            items: [
                                GroupMemberDTO(id: "gm-owner", userId: "u1", nickname: "tester", role: .owner),
                                GroupMemberDTO(id: "gm-2", userId: "user-42", nickname: "Alpha", role: .member),
                            ]
                        )
                    )
                    return (200, payload)
                case (_, let path?) where path.hasSuffix("/power-profile"):
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Power profile not found."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )

        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)
        let result = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "user-42",
                nickname: "Alpha",
                primaryPosition: .mid,
                secondaryPosition: .top,
                recentPower: 73.6,
                riotDisplayName: "Alpha#KR1",
                profileImageURL: nil
            )
        )

        requestLock.lock()
        let postBody = capturedPostBody
        let capturedMembersGetCount = membersGetCount
        requestLock.unlock()

        switch result {
        case .success:
            break
        case let .failure(message):
            XCTFail("Expected invite success, got failure: \(message)")
        }

        XCTAssertEqual(postBody?["userId"] as? String, "user-42")
        XCTAssertEqual(postBody?["role"] as? String, GroupRole.member.rawValue)
        XCTAssertEqual(viewModel.state.value?.group.memberCount, 2)
        XCTAssertEqual(viewModel.state.value?.members.map(\.userID), ["u1", "user-42"])
        XCTAssertEqual(viewModel.actionState, .success("팀원이 추가되었어요."))
        XCTAssertEqual(capturedMembersGetCount, 1)
    }

    @MainActor
    func testGroupDetailViewModelInviteMemberMapsBusinessErrorsToFriendlyMessages() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let requestLock = NSLock()
        var postAttempt = 0

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "테스트 그룹",
                            description: "설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "u1",
                            memberCount: 1,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    let payload = try JSONEncoder.app.encode(
                        GroupMemberListDTO(
                            items: [
                                GroupMemberDTO(id: "gm-owner", userId: "u1", nickname: "tester", role: .owner),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                case ("POST", "/groups/group-1/members"):
                    requestLock.lock()
                    postAttempt += 1
                    let currentAttempt = postAttempt
                    requestLock.unlock()

                    switch currentAttempt {
                    case 1:
                        return (
                            404,
                            self.makeServerErrorData(
                                statusCode: 404,
                                code: "USER_NOT_FOUND",
                                message: "User not found."
                            )
                        )
                    case 2:
                        return (
                            409,
                            self.makeServerErrorData(
                                statusCode: 409,
                                code: "GROUP_MEMBER_ALREADY_EXISTS",
                                message: "This user is already a member of the group."
                            )
                        )
                    case 3:
                        return (
                            403,
                            self.makeServerErrorData(
                                statusCode: 403,
                                code: "GROUP_ACCESS_FORBIDDEN",
                                message: "You must be a group admin to perform this action."
                            )
                        )
                    case 4:
                        return (
                            404,
                            self.makeServerErrorData(
                                statusCode: 404,
                                code: "GROUP_UNAVAILABLE",
                                message: "Group is unavailable."
                            )
                        )
                    case 5:
                        return (
                            500,
                            self.makeServerErrorData(
                                statusCode: 500,
                                code: "FK_CONSTRAINT_FAILED",
                                message: "Foreign key constraint failed."
                            )
                        )
                    default:
                        XCTFail("Unexpected invite attempt \(currentAttempt)")
                        return (500, Data())
                    }
                case (_, let path?) where path.hasSuffix("/power-profile"):
                    return (
                        404,
                        self.makeServerErrorData(
                            statusCode: 404,
                            code: "RESOURCE_NOT_FOUND",
                            message: "Power profile not found."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )

        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)

        let notFoundResult = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "missing-user",
                nickname: "Missing",
                primaryPosition: nil,
                secondaryPosition: nil,
                recentPower: nil,
                riotDisplayName: nil,
                profileImageURL: nil
            )
        )
        let duplicateResult = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "dup-user",
                nickname: "Dup",
                primaryPosition: nil,
                secondaryPosition: nil,
                recentPower: nil,
                riotDisplayName: nil,
                profileImageURL: nil
            )
        )
        let forbiddenResult = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "forbidden-user",
                nickname: "Forbidden",
                primaryPosition: nil,
                secondaryPosition: nil,
                recentPower: nil,
                riotDisplayName: nil,
                profileImageURL: nil
            )
        )
        let unavailableGroupResult = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "group-missing-user",
                nickname: "GroupMissing",
                primaryPosition: nil,
                secondaryPosition: nil,
                recentPower: nil,
                riotDisplayName: nil,
                profileImageURL: nil
            )
        )
        let serverFailureResult = await viewModel.inviteMember(
            GroupMemberInviteUser(
                id: "server-error-user",
                nickname: "ServerError",
                primaryPosition: nil,
                secondaryPosition: nil,
                recentPower: nil,
                riotDisplayName: nil,
                profileImageURL: nil
            )
        )

        guard case let .failure(notFoundMessage) = notFoundResult else {
            return XCTFail("Expected not-found failure")
        }
        guard case let .failure(duplicateMessage) = duplicateResult else {
            return XCTFail("Expected duplicate failure")
        }
        guard case let .failure(forbiddenMessage) = forbiddenResult else {
            return XCTFail("Expected forbidden failure")
        }
        guard case let .failure(unavailableGroupMessage) = unavailableGroupResult else {
            return XCTFail("Expected unavailable-group failure")
        }
        guard case let .failure(serverFailureMessage) = serverFailureResult else {
            return XCTFail("Expected server failure")
        }

        XCTAssertEqual(notFoundMessage, "추가할 사용자를 찾을 수 없어요.")
        XCTAssertEqual(duplicateMessage, "이미 그룹에 참여 중인 사용자예요.")
        XCTAssertEqual(forbiddenMessage, "이 그룹의 멤버를 추가할 권한이 없어요.")
        XCTAssertEqual(unavailableGroupMessage, "더 이상 접근할 수 없는 그룹입니다.")
        XCTAssertEqual(serverFailureMessage, "팀원 추가에 실패했어요. 잠시 후 다시 시도해 주세요.")
    }

    @MainActor
    func testGroupMemberInviteViewModelMarksCurrentUserAsSelfEvenIfAlreadyMember() {
        let suiteName = "InhouseMakeriOSTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let localStore = AppLocalStore(defaults: defaults)
        let container = AppContainer(
            configuration: makeConfiguration(),
            localStore: localStore
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))

        let viewModel = GroupMemberInviteViewModel(
            session: session,
            currentUserID: "u1",
            existingMemberUserIDs: ["u1", "u2"],
            permission: GroupInvitePermissionState(isEnabled: true, note: "검색 후 팀원을 추가할 수 있어요.")
        )

        let me = GroupMemberInviteUser(
            id: "u1",
            nickname: "tester",
            primaryPosition: .mid,
            secondaryPosition: .top,
            recentPower: 80,
            riotDisplayName: "tester#KR1",
            profileImageURL: nil
        )

        XCTAssertEqual(viewModel.availability(for: me), .selfUser)
    }

    @MainActor
    func testGroupDetailViewModelUsesInviteCapabilityFromGroupResponse() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONEncoder.app.encode(
                        GroupSummaryDTO(
                            id: "group-1",
                            name: "테스트 그룹",
                            description: "설명",
                            visibility: .private,
                            joinPolicy: .inviteOnly,
                            tags: ["서울"],
                            ownerUserId: "u1",
                            canInviteMembers: false,
                            inviteMembersBlockedReason: "GROUP_ACCESS_FORBIDDEN",
                            memberCount: 1,
                            recentMatches: 2
                        )
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    let payload = try JSONEncoder.app.encode(
                        GroupMemberListDTO(
                            items: [
                                GroupMemberDTO(id: "gm-owner", userId: "u1", nickname: "tester", role: .owner),
                            ]
                        )
                    )
                    return (200, payload)
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                case ("GET", "/users/u1/power-profile"):
                    return (200, try JSONEncoder.app.encode(self.makePowerProfileDTO(userId: "u1")))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )

        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)

        XCTAssertFalse(viewModel.isInviteButtonEnabled)
        XCTAssertEqual(viewModel.invitePermission.note, "이 그룹의 멤버를 추가할 권한이 없어요.")
    }

    @MainActor
    func testMatchLobbyFeatureAuthRequiredQueuesRetryIntent() async {
        let store = TestStore(initialState: MatchLobbyFeature.State(groupID: "g1", matchID: "m1")) {
            MatchLobbyFeature()
        }

        let requestID = store.state.activeLoadRequestID
        await store.send(.loadResponse(requestID, .failure(.authRequiredFallback()))) {
            $0.loadState = .empty("로그인 후 내전 로비를 다시 열 수 있어요.")
            $0.pendingProtectedAction = .reload
        }
    }

    @MainActor
    func testMatchLobbyFeatureSelectAllEligibleMembersKeepsExistingPlayersExcluded() async {
        let group = GroupSummary(
            id: "g1",
            name: "테스트 그룹",
            description: nil,
            visibility: .private,
            joinPolicy: .inviteOnly,
            tags: ["서울"],
            ownerUserID: "u1",
            memberCount: 3,
            recentMatches: 0
        )
        let snapshot = MatchLobbySnapshot(
            match: Match(
                id: "m1",
                groupID: "g1",
                status: .recruiting,
                scheduledAt: nil,
                balanceMode: nil,
                selectedCandidateNo: nil,
                players: [
                    MatchPlayer(
                        id: "mp-1",
                        userID: "u1",
                        nickname: "tester",
                        teamSide: nil,
                        assignedRole: .mid,
                        participationStatus: .accepted,
                        isCaptain: false
                    )
                ],
                candidates: []
            ),
            group: group,
            members: [
                GroupMember(id: "gm-1", userID: "u1", nickname: "tester", role: .owner),
                GroupMember(id: "gm-2", userID: "u2", nickname: "Alpha", role: .member),
                GroupMember(id: "gm-3", userID: "u3", nickname: "Beta", role: .member),
            ],
            powerProfiles: [:]
        )

        let store = TestStore(initialState: MatchLobbyFeature.State(groupID: "g1", matchID: "m1")) {
            MatchLobbyFeature()
        }

        let requestID = store.state.activeLoadRequestID
        await store.send(.loadResponse(requestID, .success(snapshot))) {
            $0.loadState = .content(snapshot)
        }

        await store.send(.selectAllEligibleMembersTapped) {
            $0.selectedMemberIDs = ["u2", "u3"]
        }

        await store.send(.clearSelectedMembersTapped) {
            $0.selectedMemberIDs = []
        }
    }

    @MainActor
    func testMatchLobbyFeatureReadinessRequiresTenParticipantsAndPositions() async {
        let roles: [Position] = [.top, .jungle, .mid, .adc, .support]
        let players: [MatchPlayer] = (1...10).map { index in
            let assignedRole: Position? = index == 10 ? nil : roles[(index - 1) % roles.count]
            return MatchPlayer(
                id: "mp-\(index)",
                userID: "u\(index)",
                nickname: "P\(index)",
                teamSide: nil,
                assignedRole: assignedRole,
                participationStatus: .accepted,
                isCaptain: index == 1
            )
        }
        let snapshot = MatchLobbySnapshot(
            match: Match(
                id: "m1",
                groupID: "g1",
                status: .recruiting,
                scheduledAt: nil,
                balanceMode: nil,
                selectedCandidateNo: nil,
                players: players,
                candidates: []
            ),
            group: GroupSummary(
                id: "g1",
                name: "테스트 그룹",
                description: nil,
                visibility: .private,
                joinPolicy: .inviteOnly,
                tags: ["서울"],
                ownerUserID: "u1",
                memberCount: 10,
                recentMatches: 0
            ),
            members: [],
            powerProfiles: [:]
        )

        var state = MatchLobbyFeature.State(groupID: "g1", matchID: "m1")
        state.loadState = .content(snapshot)

        XCTAssertEqual(state.balanceReadiness.participantCount, 10)
        XCTAssertEqual(state.balanceReadiness.missingParticipantCount, 0)
        XCTAssertEqual(state.balanceReadiness.missingPositionCount, 1)
        XCTAssertFalse(state.balanceReadiness.canAutoBalance)
    }

    @MainActor
    func testMatchLobbyFeatureFallbackProfilesEnableAutoBalanceReadiness() async {
        let players: [MatchPlayer] = (1...10).map { index in
            MatchPlayer(
                id: "mp-\(index)",
                userID: "u\(index)",
                nickname: "P\(index)",
                teamSide: nil,
                assignedRole: nil,
                participationStatus: .accepted,
                isCaptain: index == 1
            )
        }
        let powerProfiles = Dictionary(uniqueKeysWithValues: (1...10).map { index -> (String, PowerProfile) in
            let primary: Position = [.top, .jungle, .mid, .adc, .support][(index - 1) % 5]
            let secondary: Position = [.mid, .top, .adc, .support, .jungle][(index - 1) % 5]
            return (
                "u\(index)",
                PowerProfile(
                    userID: "u\(index)",
                    overallPower: Double(70 + index),
                    lanePower: [primary: Double(70 + index), secondary: Double(65 + index)],
                    primaryPosition: primary,
                    secondaryPosition: secondary,
                    stability: Double(70 + index),
                    carry: Double(70 + index),
                    teamContribution: Double(70 + index),
                    laneInfluence: Double(70 + index),
                    basePower: Double(68 + index),
                    formScore: Double(69 + index),
                    inhouseMMR: Double(900 + index),
                    inhouseConfidence: 0.8,
                    version: "test",
                    calculatedAt: Date()
                )
            )
        })
        let resolvedMatch = MatchLobbyFeature.effectiveMatch(match: Match(
            id: "m1",
            groupID: "g1",
            status: .recruiting,
            scheduledAt: nil,
            balanceMode: nil,
            selectedCandidateNo: nil,
            players: players,
            candidates: []
        ), powerProfiles: powerProfiles)
        let snapshot = MatchLobbySnapshot(
            match: resolvedMatch,
            group: GroupSummary(
                id: "g1",
                name: "테스트 그룹",
                description: nil,
                visibility: .private,
                joinPolicy: .inviteOnly,
                tags: ["서울"],
                ownerUserID: "u1",
                memberCount: 10,
                recentMatches: 0
            ),
            members: [],
            powerProfiles: powerProfiles
        )

        var state = MatchLobbyFeature.State(groupID: "g1", matchID: "m1")
        state.loadState = .content(snapshot)

        XCTAssertEqual(state.balanceReadiness.missingPositionCount, 0)
        XCTAssertTrue(state.balanceReadiness.canAutoBalance)
        XCTAssertEqual(snapshot.match.players.first?.assignedRole, .top)
        XCTAssertEqual(snapshot.powerProfiles["u1"]?.overallPower, 71)
    }

    @MainActor
    func testTeamBalanceFeatureAuthRequiredQueuesRetryIntent() async {
        let store = TestStore(initialState: TeamBalanceFeature.State(groupID: "g1", matchID: "m1")) {
            TeamBalanceFeature()
        }

        await store.send(.confirmSelectionFailed(.authRequiredFallback())) {
            $0.actionState = .idle
            $0.pendingProtectedAction = .confirmSelection
        }
    }

    @MainActor
    func testTeamBalanceFeatureShowsEmptyReasonWhenNoCandidatesReturned() async {
        let roles: [Position] = [.top, .jungle, .mid, .adc, .support]
        let match = Match(
            id: "m1",
            groupID: "g1",
            status: .locked,
            scheduledAt: nil,
            balanceMode: nil,
            selectedCandidateNo: nil,
            players: (1...10).map { index in
                let assignedRole = roles[(index - 1) % roles.count]
                return MatchPlayer(
                    id: "mp-\(index)",
                    userID: "u\(index)",
                    nickname: "P\(index)",
                    teamSide: nil,
                    assignedRole: assignedRole,
                    participationStatus: .accepted,
                    isCaptain: index == 1
                )
            },
            candidates: []
        )
        let snapshot = TeamBalanceSnapshot(match: match, candidates: [])
        let payload = TeamBalanceFeature.LoadPayload(
            snapshot: snapshot,
            groupName: "테스트 그룹",
            preferredPositions: [:]
        )
        let expectedMessage = "추천 조합이 없습니다.\n서버가 추천 조합을 반환하지 않았어요. 다시 시도하거나 로비에서 참가자 구성을 확인해 주세요."

        let store = TestStore(initialState: TeamBalanceFeature.State(groupID: "g1", matchID: "m1")) {
            TeamBalanceFeature()
        }

        await store.send(.loadResponse(.success(payload))) {
            $0.groupName = "테스트 그룹"
            $0.preferredPositions = [:]
            $0.emptyReasonMessage = expectedMessage
            $0.loadState = .empty(expectedMessage)
            $0.selectedMode = .balanced
        }
    }

    @MainActor
    func testMatchResultFeatureAuthRequiredQueuesRetryIntent() async {
        let store = TestStore(initialState: MatchResultFeature.State(matchID: "m1")) {
            MatchResultFeature()
        }

        await store.send(.submitResponse(.failure(.authRequiredFallback()))) {
            $0.actionState = .idle
            $0.pendingProtectedAction = .submit
        }
    }

    @MainActor
    func testMatchResultFeatureValidationGuidesMVPAndLaneMissingStates() async {
        let snapshot = MatchDetailSnapshot(
            match: Match(
                id: "m1",
                groupID: "g1",
                status: .resultPending,
                scheduledAt: nil,
                balanceMode: .balanced,
                selectedCandidateNo: 1,
                players: [
                    MatchPlayer(
                        id: "mp-1",
                        userID: "u1",
                        nickname: "Blue",
                        teamSide: .blue,
                        assignedRole: .mid,
                        participationStatus: .accepted,
                        isCaptain: true
                    ),
                    MatchPlayer(
                        id: "mp-2",
                        userID: "u2",
                        nickname: "Red",
                        teamSide: .red,
                        assignedRole: .mid,
                        participationStatus: .accepted,
                        isCaptain: false
                    ),
                ],
                candidates: []
            ),
            result: nil,
            cachedMetadata: nil
        )

        let store = TestStore(initialState: MatchResultFeature.State(matchID: "m1")) {
            MatchResultFeature()
        }

        await store.send(.loadResponse(.success(snapshot))) {
            $0.loadState = .content(snapshot)
            $0.winningTeam = .blue
            $0.selectedMVPUserID = nil
            $0.laneResults = [:]
            $0.selectedLaneResultKeys = []
            $0.balanceFeeling = 5
            $0.kdaInputs = [
                "u1": MatchResultFeature.State.KDAInput(),
                "u2": MatchResultFeature.State.KDAInput(),
            ]
        }

        await store.send(.submitTapped) {
            $0.validationMessage = "MVP를 선택해 주세요."
            $0.highlightedValidationSection = .mvp
            $0.actionState = .failure("MVP를 선택해 주세요.")
        }

        await store.send(.mvpSelected("u1")) {
            $0.selectedMVPUserID = "u1"
            $0.validationMessage = nil
            $0.highlightedValidationSection = nil
        }

        await store.send(.submitTapped) {
            let message = "라인별 승패를 모두 선택해 주세요. 누락: TOP, JGL, MID, BOT"
            $0.validationMessage = message
            $0.highlightedValidationSection = .lanes
            $0.actionState = .failure(message)
        }
    }

    @MainActor
    func testCompleteAuthenticatedSessionSuccessTransitionsToAuthenticatedWithApple() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let tokens = makeTokens()
        let profile = makeProfile()

        let result = try await session.completeAuthenticatedSession(
            tokens: tokens,
            event: .login(.apple),
            loadProfile: { profile },
            onSignOut: {}
        )

        XCTAssertEqual(result, profile)
        XCTAssertEqual(session.authTokens, tokens)
        XCTAssertEqual(session.profile, profile)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.user, profile)
            XCTAssertEqual(authenticatedSession.authTokens, tokens)
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state")
        }
    }

    @MainActor
    func testCompleteAuthenticatedSessionSuccessTransitionsToAuthenticatedWithGoogle() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let tokens = makeTokens()
        let profile = makeProfile()

        let result = try await session.completeAuthenticatedSession(
            tokens: tokens,
            event: .login(.google),
            loadProfile: { profile },
            onSignOut: {}
        )

        XCTAssertEqual(result, profile)
        XCTAssertEqual(session.authTokens, tokens)
        XCTAssertEqual(session.profile, profile)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.user, profile)
            XCTAssertEqual(authenticatedSession.authTokens, tokens)
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state")
        }
    }

    @MainActor
    func testCompleteAuthenticatedSessionSuccessTransitionsToAuthenticatedWithEmailSignUp() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let tokens = makeTokens()
        let profile = makeProfile()

        let result = try await session.completeAuthenticatedSession(
            tokens: tokens,
            event: .emailSignUp,
            loadProfile: { profile },
            onSignOut: {}
        )

        XCTAssertEqual(result, profile)
        XCTAssertEqual(session.authTokens, tokens)
        XCTAssertEqual(session.profile, profile)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.user, profile)
            XCTAssertEqual(authenticatedSession.authTokens, tokens)
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state")
        }
    }

    @MainActor
    func testCompleteAuthenticatedSessionSuccessTransitionsToAuthenticatedWithEmailLogin() async throws {
        let session = AppSessionViewModel(container: AppContainer())
        let tokens = makeTokens()
        let profile = makeProfile()

        let result = try await session.completeAuthenticatedSession(
            tokens: tokens,
            event: .emailLogin,
            loadProfile: { profile },
            onSignOut: {}
        )

        XCTAssertEqual(result, profile)
        XCTAssertEqual(session.authTokens, tokens)
        XCTAssertEqual(session.profile, profile)

        switch session.state {
        case let .authenticated(authenticatedSession):
            XCTAssertEqual(authenticatedSession.user, profile)
            XCTAssertEqual(authenticatedSession.authTokens, tokens)
        case .bootstrapping, .guest, .authenticating:
            XCTFail("Expected authenticated state")
        }
    }

    @MainActor
    func testCompleteAuthenticatedSessionFailureClearsSession() async {
        let session = AppSessionViewModel(container: AppContainer())
        let tokens = makeTokens()
        var didSignOut = false

        do {
            _ = try await session.completeAuthenticatedSession(
                tokens: tokens,
                event: .login(.google),
                loadProfile: { throw URLError(.notConnectedToInternet) },
                onSignOut: { didSignOut = true }
            )
            XCTFail("Expected failure")
        } catch let error as AuthError {
            XCTAssertEqual(error, .networkOffline)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(didSignOut)
        XCTAssertNil(session.authTokens)
        XCTAssertNil(session.profile)

        switch session.state {
        case .guest:
            XCTAssertTrue(true)
        case .bootstrapping, .authenticating, .authenticated:
            XCTFail("Expected guest state")
        }
    }

    func testRiotGameNameValidationRejectsCombinedRiotID() {
        XCTAssertEqual(
            RiotAccountInputValidator.validateGameName("Hide on bush#KR1"),
            .invalid("게임 이름과 태그라인을 나눠 입력해 주세요")
        )
        XCTAssertEqual(
            RiotAccountInputValidator.validateGameName(String(repeating: "a", count: 33)),
            .invalid("게임 이름은 32자 이하로 입력해 주세요")
        )
    }

    func testRiotTagLineValidationNormalizesHashAndUppercasesInput() {
        XCTAssertEqual(RiotAccountInputValidator.normalizedTagLine("#kr1 "), "KR1")
        XCTAssertEqual(
            RiotAccountInputValidator.validateTagLine("#KR1"),
            .invalid("# 없이 KR1만 입력해 주세요")
        )
        XCTAssertEqual(
            RiotAccountInputValidator.validateTagLine("kr1"),
            .valid("예: KR1, KOR")
        )
    }

    func testRiotSyncUIStateMapsFailureCodesToActionableStatuses() {
        XCTAssertEqual(
            makeRiotAccount(syncStatus: .failed, lastSyncErrorCode: "RIOT_RESOURCE_NOT_FOUND").syncUIState,
            .accountNotFound
        )
        XCTAssertEqual(
            makeRiotAccount(syncStatus: .failed, lastSyncErrorCode: "RIOT_CLIENT_ERROR").syncUIState,
            .invalidInput
        )
        XCTAssertEqual(
            makeRiotAccount(syncStatus: .failed, lastSyncErrorCode: "RIOT_AUTH_FAILED").syncUIState,
            .serverConfiguration
        )
        XCTAssertEqual(
            makeRiotAccount(syncStatus: .failed, lastSyncErrorCode: "RIOT_NETWORK_ERROR").syncUIState,
            .failure
        )
    }

    func testRiotSyncUIStateTracksPendingRunningAndSuccessTimestamps() {
        let now = Date(timeIntervalSince1970: 1_713_081_600)

        XCTAssertEqual(makeRiotAccount(syncStatus: .idle).syncUIState, .pending)
        XCTAssertEqual(makeRiotAccount(syncStatus: .queued).syncUIState, .pending)
        XCTAssertEqual(makeRiotAccount(syncStatus: .running).syncUIState, .syncing)

        let succeeded = makeRiotAccount(
            syncStatus: .succeeded,
            lastSyncSucceededAt: now,
            lastSyncedAt: now
        )
        XCTAssertEqual(succeeded.syncUIState, .success)
        XCTAssertEqual(succeeded.syncStatusTimestamp, now)
    }

    @MainActor
    func testRiotAccountsLoadMapsServerErrorToServerStateMessage() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    return (
                        500,
                        self.makeServerErrorData(
                            statusCode: 500,
                            code: "INTERNAL_SERVER_ERROR",
                            message: "The column `riot_accounts.sync_phase` does not exist in the current database."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        await viewModel.load(force: true, source: "test_server_error")

        guard case let .error(error) = viewModel.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertEqual(error.title, "Riot ID 목록을 불러오는 중 문제가 발생했어요.")
        XCTAssertEqual(error.message, "서버 설정 또는 동기화 상태에 문제가 있을 수 있어요. 잠시 후 다시 시도해 주세요.")
        XCTAssertEqual(error.code, "INTERNAL_SERVER_ERROR")
        XCTAssertEqual(error.statusCode, 500)
        XCTAssertEqual(error.endpoint, "/riot-accounts")
    }

    @MainActor
    func testRiotAccountsLoadMapsOfflineNetworkErrorToNetworkStateMessage() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    throw URLError(.notConnectedToInternet)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        await viewModel.load(force: true, source: "test_network_error")

        guard case let .error(error) = viewModel.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertEqual(error.title, "네트워크 연결을 확인해 주세요.")
        XCTAssertEqual(error.message, "인터넷 연결 상태를 확인한 뒤 다시 시도해 주세요.")
        XCTAssertEqual(error.code, "NETWORK_OFFLINE")
        XCTAssertEqual(error.endpoint, "/riot-accounts")
    }

    @MainActor
    func testRiotAccountsLoadMapsEmptyListToEmptyState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(RiotAccountListDTO(items: []))
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        await viewModel.load(force: true, source: "test_empty")

        guard case let .empty(message) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(message, "연결된 Riot ID가 없어요.")
    }

    @MainActor
    func testRiotAccountsLoadDropsDuplicateFetchWhileRequestIsInFlight() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let requestStarted = expectation(description: "riot accounts request started")
        let releaseRequest = DispatchSemaphore(value: 0)
        let requestLock = NSLock()
        var requestCount = 0

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    requestLock.lock()
                    requestCount += 1
                    requestLock.unlock()
                    requestStarted.fulfill()
                    _ = releaseRequest.wait(timeout: .now() + 2)
                    let payload = try JSONEncoder.app.encode(RiotAccountListDTO(items: []))
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        let firstLoad = Task { await viewModel.load(force: true, source: "first") }
        await fulfillment(of: [requestStarted], timeout: 1)

        await viewModel.load(source: "second")
        releaseRequest.signal()
        await firstLoad.value

        requestLock.lock()
        let finalRequestCount = requestCount
        requestLock.unlock()

        XCTAssertEqual(finalRequestCount, 1)
        guard case let .empty(message) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(message, "연결된 Riot ID가 없어요.")
    }

    @MainActor
    func testRiotAccountsLoadReusesSessionErrorStateWithoutRefetchOnNewViewModel() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let requestLock = NSLock()
        var requestCount = 0
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    requestLock.lock()
                    requestCount += 1
                    requestLock.unlock()
                    return (
                        500,
                        self.makeServerErrorData(
                            statusCode: 500,
                            code: "INTERNAL_SERVER_ERROR",
                            message: "The column `riot_accounts.sync_phase` does not exist in the current database."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))

        let firstViewModel = RiotAccountsViewModel(session: session)
        await firstViewModel.load(force: true, source: "initial")

        let secondViewModel = RiotAccountsViewModel(session: session)
        await secondViewModel.load(source: "reenter")

        requestLock.lock()
        let finalRequestCount = requestCount
        requestLock.unlock()

        XCTAssertEqual(finalRequestCount, 1)
        guard case let .error(error) = secondViewModel.state else {
            return XCTFail("Expected reused error state")
        }
        XCTAssertEqual(error.title, "Riot ID 목록을 불러오는 중 문제가 발생했어요.")
    }

    @MainActor
    func testRiotAccountsLoadRetryKeepsSameErrorStateWithoutRepublishing() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let requestLock = NSLock()
        var requestCount = 0
        let noStateRepublish = expectation(description: "no state republish for same error")
        noStateRepublish.isInverted = true

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    requestLock.lock()
                    requestCount += 1
                    requestLock.unlock()
                    return (
                        500,
                        self.makeServerErrorData(
                            statusCode: 500,
                            code: "INTERNAL_SERVER_ERROR",
                            message: "The column `riot_accounts.sync_phase` does not exist in the current database."
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        await viewModel.load(force: true, source: "initial")

        let cancellable = viewModel.$state
            .dropFirst()
            .sink { _ in
                noStateRepublish.fulfill()
            }

        await viewModel.load(force: true, source: "retry")
        await fulfillment(of: [noStateRepublish], timeout: 0.3)

        requestLock.lock()
        let finalRequestCount = requestCount
        requestLock.unlock()

        XCTAssertEqual(finalRequestCount, 2)
        guard case let .error(error) = viewModel.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertEqual(error.title, "Riot ID 목록을 불러오는 중 문제가 발생했어요.")
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testRiotAccountsLoadRetryRecoversFromServerErrorToLoadedState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let requestLock = NSLock()
        var requestCount = 0
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    requestLock.lock()
                    requestCount += 1
                    let currentRequestCount = requestCount
                    requestLock.unlock()

                    if currentRequestCount == 1 {
                        return (
                            500,
                            self.makeServerErrorData(
                                statusCode: 500,
                                code: "INTERNAL_SERVER_ERROR",
                                message: "The column `riot_accounts.sync_phase` does not exist in the current database."
                            )
                        )
                    }

                    let payload = try JSONEncoder.app.encode(
                        RiotAccountListDTO(items: [self.makeRiotAccountDTO(syncStatus: .succeeded)])
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        await viewModel.load(force: true, source: "initial")
        guard case .error = viewModel.state else {
            return XCTFail("Expected initial error state")
        }

        await viewModel.load(force: true, source: "retry_after_fix")

        requestLock.lock()
        let finalRequestCount = requestCount
        requestLock.unlock()

        XCTAssertEqual(finalRequestCount, 2)
        guard case let .content(snapshot) = viewModel.state else {
            return XCTFail("Expected loaded content state")
        }
        XCTAssertEqual(snapshot.accounts.count, 1)
    }

    @MainActor
    func testRiotAccountsPollingSkipsDuplicateStartAndStopsAtSucceededState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let requestLock = NSLock()
        let firstSyncStatusRequestStarted = expectation(description: "first sync-status request started")
        let syncCompleted = expectation(description: "sync completed")
        let releaseFirstSyncStatusRequest = DispatchSemaphore(value: 0)
        var didFulfillCompletion = false
        var syncStatusRequestCount = 0
        let requestedAt = Date(timeIntervalSince1970: 1_713_081_600)
        let succeededAt = requestedAt.addingTimeInterval(45)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(
                        RiotAccountListDTO(items: [
                            self.makeRiotAccountDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt),
                        ])
                    )
                    return (200, payload)
                case ("GET", "/riot-accounts/ra1/sync-status"):
                    requestLock.lock()
                    syncStatusRequestCount += 1
                    let currentCount = syncStatusRequestCount
                    requestLock.unlock()

                    if currentCount == 1 {
                        firstSyncStatusRequestStarted.fulfill()
                        _ = releaseFirstSyncStatusRequest.wait(timeout: .now() + 2)
                        let payload = try JSONEncoder.app.encode(
                            self.makeRiotSyncStatusDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt)
                        )
                        return (200, payload)
                    }

                    let payload = try JSONEncoder.app.encode(
                        self.makeRiotSyncStatusDTO(
                            syncStatus: .succeeded,
                            lastSyncRequestedAt: requestedAt,
                            lastSyncSucceededAt: succeededAt
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)
        let cancellable = viewModel.$state.sink { state in
            guard
                !didFulfillCompletion,
                case let .content(snapshot) = state,
                snapshot.accounts.first?.syncStatus == .succeeded
            else { return }
            didFulfillCompletion = true
            syncCompleted.fulfill()
        }

        viewModel.handleViewAppear()
        await viewModel.load(force: true)

        await fulfillment(of: [firstSyncStatusRequestStarted], timeout: 1)
        viewModel.handleViewAppear()
        try await Task.sleep(nanoseconds: 200_000_000)

        requestLock.lock()
        let requestsWhileFirstWasInFlight = syncStatusRequestCount
        requestLock.unlock()
        XCTAssertEqual(requestsWhileFirstWasInFlight, 1)

        releaseFirstSyncStatusRequest.signal()
        await fulfillment(of: [syncCompleted], timeout: 4)

        requestLock.lock()
        let finalRequestCount = syncStatusRequestCount
        requestLock.unlock()

        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(viewModel.state.value?.accounts.first?.syncStatus, .succeeded)
        XCTAssertTrue(viewModel.syncInProgressIDs.isEmpty)
        XCTAssertEqual(session.riotLinkedDataRevision, 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testRiotAccountsPollingDropsRepeatedRunningResponsesWithoutRepublishingState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let repeatedRunningResponseReceived = expectation(description: "repeated running response received")
        repeatedRunningResponseReceived.assertForOverFulfill = false
        let noStateRepublish = expectation(description: "no state republish")
        noStateRepublish.isInverted = true
        let requestLock = NSLock()
        var syncStatusRequestCount = 0
        let requestedAt = Date(timeIntervalSince1970: 1_713_081_600)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(
                        RiotAccountListDTO(items: [
                            self.makeRiotAccountDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt),
                        ])
                    )
                    return (200, payload)
                case ("GET", "/riot-accounts/ra1/sync-status"):
                    requestLock.lock()
                    syncStatusRequestCount += 1
                    let currentCount = syncStatusRequestCount
                    requestLock.unlock()

                    if currentCount >= 2 {
                        repeatedRunningResponseReceived.fulfill()
                    }

                    let payload = try JSONEncoder.app.encode(
                        self.makeRiotSyncStatusDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt)
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        viewModel.handleViewAppear()
        await viewModel.load(force: true)

        let cancellable = viewModel.$state
            .dropFirst()
            .sink { _ in
                noStateRepublish.fulfill()
            }

        await fulfillment(of: [repeatedRunningResponseReceived, noStateRepublish], timeout: 3)

        XCTAssertEqual(viewModel.state.value?.accounts.first?.syncStatus, .running)
        XCTAssertEqual(session.riotLinkedDataRevision, 0)
        viewModel.handleViewDisappear()
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testRiotAccountsPollingPausesInBackgroundAndResumesOnActive() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let firstSyncStatusResponseReceived = expectation(description: "first sync-status response received")
        let resumedSyncStatusResponseReceived = expectation(description: "resumed sync-status response received")
        let requestLock = NSLock()
        var syncStatusRequestCount = 0
        let requestedAt = Date(timeIntervalSince1970: 1_713_081_600)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(
                        RiotAccountListDTO(items: [
                            self.makeRiotAccountDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt),
                        ])
                    )
                    return (200, payload)
                case ("GET", "/riot-accounts/ra1/sync-status"):
                    requestLock.lock()
                    syncStatusRequestCount += 1
                    let currentCount = syncStatusRequestCount
                    requestLock.unlock()

                    if currentCount == 1 {
                        firstSyncStatusResponseReceived.fulfill()
                    } else if currentCount == 2 {
                        resumedSyncStatusResponseReceived.fulfill()
                    }

                    let payload = try JSONEncoder.app.encode(
                        self.makeRiotSyncStatusDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt)
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)

        viewModel.handleViewAppear()
        await viewModel.load(force: true)
        await fulfillment(of: [firstSyncStatusResponseReceived], timeout: 1)

        viewModel.handleScenePhaseChange(.background)
        try await Task.sleep(nanoseconds: 1_700_000_000)

        requestLock.lock()
        let pausedRequestCount = syncStatusRequestCount
        requestLock.unlock()
        XCTAssertEqual(pausedRequestCount, 1)

        viewModel.handleScenePhaseChange(.active)
        await fulfillment(of: [resumedSyncStatusResponseReceived], timeout: 1)

        requestLock.lock()
        let resumedRequestCount = syncStatusRequestCount
        requestLock.unlock()
        XCTAssertEqual(resumedRequestCount, 2)
        viewModel.handleViewDisappear()
    }

    @MainActor
    func testRiotAccountsPollingStopsAtFailedState() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())

        let syncFailed = expectation(description: "sync failed")
        var didFulfillFailure = false
        let requestedAt = Date(timeIntervalSince1970: 1_713_081_600)
        let failedAt = requestedAt.addingTimeInterval(20)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/riot-accounts"):
                    let payload = try JSONEncoder.app.encode(
                        RiotAccountListDTO(items: [
                            self.makeRiotAccountDTO(syncStatus: .running, lastSyncRequestedAt: requestedAt),
                        ])
                    )
                    return (200, payload)
                case ("GET", "/riot-accounts/ra1/sync-status"):
                    let payload = try JSONEncoder.app.encode(
                        self.makeRiotSyncStatusDTO(
                            syncStatus: .failed,
                            lastSyncRequestedAt: requestedAt,
                            lastSyncFailedAt: failedAt,
                            lastSyncErrorCode: "RIOT_NETWORK_ERROR",
                            lastSyncErrorMessage: "Riot API timeout"
                        )
                    )
                    return (200, payload)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = RiotAccountsViewModel(session: session)
        let cancellable = viewModel.$state.sink { state in
            guard
                !didFulfillFailure,
                case let .content(snapshot) = state,
                snapshot.accounts.first?.syncStatus == .failed
            else { return }
            didFulfillFailure = true
            syncFailed.fulfill()
        }

        viewModel.handleViewAppear()
        await viewModel.load(force: true)
        await fulfillment(of: [syncFailed], timeout: 1)

        let failedAccount = try XCTUnwrap(viewModel.state.value?.accounts.first)
        XCTAssertEqual(failedAccount.syncStatus, .failed)
        XCTAssertEqual(failedAccount.syncStatusSummary, "Riot API timeout")
        XCTAssertTrue(viewModel.syncInProgressIDs.isEmpty)
        XCTAssertEqual(session.riotLinkedDataRevision, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testGroupSummaryDTOPrefersExplicitCompletedHistoryCountFields() throws {
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "id": "group-1",
                "name": "테스트 그룹",
                "description": "설명",
                "visibility": GroupVisibility.public.rawValue,
                "joinPolicy": JoinPolicy.open.rawValue,
                "tags": ["서울"],
                "ownerUserId": "owner",
                "memberCount": 10,
                "recentMatches": 7,
                "matchCount": 7,
                "lobbyCount": 2,
                "recentInhouseCount": 5,
                "completedInhouseCount": 4,
            ]
        )

        let dto = try JSONDecoder.app.decode(GroupSummaryDTO.self, from: payload)

        XCTAssertEqual(dto.recentMatches, 4)
        XCTAssertEqual(dto.recentMatchCountSource, .completedHistory)
    }

    func testGroupSummaryDTOSubtractsLobbyCountFromLegacyMatchCount() throws {
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "id": "group-1",
                "name": "테스트 그룹",
                "description": "설명",
                "visibility": GroupVisibility.public.rawValue,
                "joinPolicy": JoinPolicy.open.rawValue,
                "tags": ["서울"],
                "ownerUserId": "owner",
                "memberCount": 10,
                "recentMatches": 6,
                "lobbyCount": 1,
            ]
        )

        let dto = try JSONDecoder.app.decode(GroupSummaryDTO.self, from: payload)

        XCTAssertEqual(dto.recentMatches, 5)
        XCTAssertEqual(dto.recentMatchCountSource, .legacyAdjustedByLobbyCount)
    }

    func testGroupSummaryDTOTreatsRecentInhouseCountAsLegacyWithoutCompletedField() throws {
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "id": "group-1",
                "name": "테스트 그룹",
                "description": "설명",
                "visibility": GroupVisibility.public.rawValue,
                "joinPolicy": JoinPolicy.open.rawValue,
                "tags": ["서울"],
                "ownerUserId": "owner",
                "memberCount": 10,
                "recentInhouseCount": 8,
            ]
        )

        let dto = try JSONDecoder.app.decode(GroupSummaryDTO.self, from: payload)

        XCTAssertEqual(dto.recentMatches, 8)
        XCTAssertEqual(dto.recentMatchCountSource, .legacyRecentMatches)
    }

    func testGroupCompletedInhouseDisplayFormatsConfirmedEmptyAndLegacyStates() {
        let confirmed = GroupSummary(
            id: "group-confirmed",
            name: "완료 그룹",
            description: nil,
            visibility: .public,
            joinPolicy: .open,
            tags: [],
            ownerUserID: "owner",
            memberCount: 10,
            recentMatches: 8,
            recentMatchCountSource: .completedHistory
        )
        let empty = GroupSummary(
            id: "group-empty",
            name: "빈 그룹",
            description: nil,
            visibility: .public,
            joinPolicy: .open,
            tags: [],
            ownerUserID: "owner",
            memberCount: 10,
            recentMatches: 0,
            recentMatchCountSource: .completedHistory
        )
        let legacy = GroupSummary(
            id: "group-legacy",
            name: "레거시 그룹",
            description: nil,
            visibility: .public,
            joinPolicy: .open,
            tags: [],
            ownerUserID: "owner",
            memberCount: 10,
            recentMatches: 8,
            recentMatchCountSource: .legacyRecentMatches
        )

        XCTAssertEqual(confirmed.completedInhouseDisplay.recentInhouseText, "최근 내전: 8회 진행")
        XCTAssertEqual(empty.completedInhouseDisplay.recentInhouseText, "최근 내전: 기록 없음")
        XCTAssertEqual(legacy.completedInhouseDisplay.recentInhouseText, "최근 내전: 기록 확인 중")
    }

    @MainActor
    func testGroupDetailViewModelCorrectsLegacyRecentMatchCountUsingTrackedPendingLobby() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group-detail.pending-lobby-correction.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)
        localStore.trackMatch(
            RecentMatchContext(matchID: "pending-match", groupID: "group-1", groupName: "테스트 그룹", createdAt: Date())
        )

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    let payload = try JSONSerialization.data(
                        withJSONObject: [
                            "id": "group-1",
                            "name": "테스트 그룹",
                            "description": "설명",
                            "visibility": GroupVisibility.private.rawValue,
                            "joinPolicy": JoinPolicy.inviteOnly.rawValue,
                            "tags": ["서울"],
                            "ownerUserId": "u1",
                            "memberCount": 10,
                            "recentMatches": 3,
                        ]
                    )
                    return (200, payload)
                case ("GET", "/groups/group-1/members"):
                    return (200, try JSONEncoder.app.encode(GroupMemberListDTO(items: [])))
                case ("GET", "/matches/pending-match"):
                    return (
                        200,
                        try JSONEncoder.app.encode(
                            MatchResponseDTO(
                                id: "pending-match",
                                groupId: "group-1",
                                status: .recruiting,
                                scheduledAt: nil,
                                balanceMode: nil,
                                selectedCandidateNo: nil,
                                players: [],
                                candidates: nil
                            )
                        )
                    )
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )

        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)

        XCTAssertEqual(viewModel.state.value?.group.recentMatches, 2)
        XCTAssertEqual(viewModel.state.value?.group.recentMatchCountSource, .legacyRecentMatches)
    }

    @MainActor
    func testGroupDetailViewModelCreateMatchDoesNotOptimisticallyIncrementRecentMatchCount() async throws {
        let tokenStore = makeTokenStore()
        await tokenStore.save(tokens: makeTokens())
        let suiteName = "InhouseMakeriOSTests.group-detail.create-match-count.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let localStore = AppLocalStore(defaults: defaults)

        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: tokenStore,
            localStore: localStore,
            urlSession: makeURLSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/groups/group-1"):
                    return (
                        200,
                        try JSONEncoder.app.encode(
                            GroupSummaryDTO(
                                id: "group-1",
                                name: "테스트 그룹",
                                description: "설명",
                                visibility: .private,
                                joinPolicy: .inviteOnly,
                                tags: ["서울"],
                                ownerUserId: "u1",
                                memberCount: 10,
                                recentMatches: 2
                            )
                        )
                    )
                case ("GET", "/groups/group-1/members"):
                    return (200, try JSONEncoder.app.encode(GroupMemberListDTO(items: [])))
                case ("GET", "/users/u1/inhouse-history"):
                    return (200, try JSONEncoder.app.encode(HistoryResponseDTO(items: [])))
                case ("POST", "/groups/group-1/matches"):
                    return (
                        200,
                        try JSONEncoder.app.encode(
                            MatchResponseDTO(
                                id: "created-match",
                                groupId: "group-1",
                                status: .recruiting,
                                scheduledAt: nil,
                                balanceMode: nil,
                                selectedCandidateNo: nil,
                                players: [],
                                candidates: nil
                            )
                        )
                    )
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )

        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        let viewModel = GroupDetailViewModel(session: session, groupID: "group-1")

        await viewModel.load(trigger: .screenAppear)
        let createdMatch = await viewModel.createMatch()

        XCTAssertEqual(createdMatch?.id, "created-match")
        XCTAssertEqual(viewModel.state.value?.group.recentMatches, 2)
        XCTAssertEqual(localStore.recentMatches.first?.matchID, "created-match")
    }

    @MainActor
    func testNotificationPermissionManagerDoesNotRegisterBeforeAuthorization() async {
        let authorizationProvider = MockNotificationAuthorizationProvider(
            currentStatus: .notDetermined,
            requestResult: .authorized
        )
        let registrar = MockRemoteNotificationRegistrar()
        let settingsOpener = MockApplicationSettingsOpener()
        let synchronizer = MockPushTokenSynchronizer()
        let manager = NotificationPermissionManager(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar,
            settingsOpener: settingsOpener,
            pushTokenSynchronizer: synchronizer,
            initialAuthorizationState: .notDetermined
        )

        await manager.refreshAuthorizationStatus(registerIfNeeded: true)

        XCTAssertEqual(manager.authorizationState, .notDetermined)
        XCTAssertEqual(registrar.registerCallCount, 0)
        XCTAssertEqual(synchronizer.syncCalls.count, 0)
    }

    @MainActor
    func testNotificationPermissionManagerRegistersOnlyWhenAuthorizationGranted() async {
        let authorizationProvider = MockNotificationAuthorizationProvider(
            currentStatus: .authorized,
            requestResult: .authorized
        )
        let registrar = MockRemoteNotificationRegistrar()
        let manager = NotificationPermissionManager(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar,
            settingsOpener: MockApplicationSettingsOpener(),
            pushTokenSynchronizer: MockPushTokenSynchronizer(),
            initialAuthorizationState: .notDetermined
        )

        await manager.refreshAuthorizationStatus(registerIfNeeded: true)

        XCTAssertEqual(manager.authorizationState, .authorized)
        XCTAssertEqual(registrar.registerCallCount, 1)
    }

    @MainActor
    func testNotificationPermissionManagerUsesSettingsBranchWhenDenied() async {
        let authorizationProvider = MockNotificationAuthorizationProvider(
            currentStatus: .denied,
            requestResult: .denied
        )
        let registrar = MockRemoteNotificationRegistrar()
        let settingsOpener = MockApplicationSettingsOpener()
        let manager = NotificationPermissionManager(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar,
            settingsOpener: settingsOpener,
            pushTokenSynchronizer: MockPushTokenSynchronizer(),
            initialAuthorizationState: .notDetermined
        )

        let action = await manager.resolvePrimaryAction()
        if action == .openSettings {
            manager.openSystemSettings()
        }

        XCTAssertEqual(action, .openSettings)
        XCTAssertEqual(registrar.registerCallCount, 0)
        XCTAssertEqual(settingsOpener.openSettingsCallCount, 1)
    }

    @MainActor
    func testNotificationPermissionManagerSyncsTokenOnlyAfterAuthorization() async {
        let authorizationProvider = MockNotificationAuthorizationProvider(
            currentStatus: .notDetermined,
            requestResult: .authorized
        )
        let registrar = MockRemoteNotificationRegistrar()
        let settingsOpener = MockApplicationSettingsOpener()
        let synchronizer = MockPushTokenSynchronizer()
        let manager = NotificationPermissionManager(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar,
            settingsOpener: settingsOpener,
            pushTokenSynchronizer: synchronizer,
            initialAuthorizationState: .notDetermined
        )
        let token = Data([0x0A, 0x0B, 0x0C, 0x0D])

        await manager.didRegisterForRemoteNotifications(deviceToken: token)
        XCTAssertEqual(synchronizer.syncCalls.count, 0)

        authorizationProvider.currentStatus = .authorized
        await manager.refreshAuthorizationStatus(registerIfNeeded: false)
        await manager.didRegisterForRemoteNotifications(deviceToken: token)

        XCTAssertEqual(synchronizer.syncCalls.count, 1)
        XCTAssertEqual(synchronizer.syncCalls.first?.token, "0a0b0c0d")
        XCTAssertEqual(synchronizer.syncCalls.first?.notificationsEnabled, true)
    }

    private func makeTokens() -> AuthTokens {
        AuthTokens(
            user: AuthUser(id: "u1", email: "user@example.com", nickname: "tester"),
            accessToken: "access",
            refreshToken: "refresh"
        )
    }

    private func makeConfiguration() -> AppConfiguration {
        AppConfiguration(
            environment: .development,
            networkConfiguration: AppEnvironment.development.networkConfiguration,
            googleClientID: "test-google-client-id"
        )
    }

    private func makeServerErrorData(
        statusCode: Int,
        code: String,
        message: String,
        provider: String? = nil,
        details: [String: JSONValue]? = nil
    ) -> Data {
        let detailJSON = details.flatMap { value -> String? in
            guard let data = try? JSONEncoder.app.encode(value), let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        } ?? "null"
        let providerJSON = provider.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"statusCode":\(statusCode),"code":"\(code)","provider":\(providerJSON),"message":"\(message)","timestamp":"2026-04-13T00:00:00Z","path":"/test","details":\(detailJSON)}
        """
        return Data(json.utf8)
    }

    private func makeTokenStore() -> TokenStore {
        TokenStore(service: "InhouseMakeriOSTests.\(UUID().uuidString)", account: "session")
    }

    private func makeURLSession(
        handler: @escaping @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeProfile() -> UserProfile {
        UserProfile(
            id: "u1",
            email: "user@example.com",
            nickname: "tester",
            primaryPosition: .mid,
            secondaryPosition: .top,
            isFillAvailable: true,
            styleTags: ["빡겜"],
            mannerScore: 100,
            noshowCount: 0
        )
    }

    private func makeTopChampion(
        championKey: String,
        championName: String,
        games: Int,
        wins: Int,
        winRate: Double,
        kda: Double?
    ) -> ProfileTopChampion {
        ProfileTopChampion(
            championId: nil,
            championKey: championKey,
            championName: championName,
            games: games,
            wins: wins,
            losses: max(games - wins, 0),
            winRate: winRate,
            kills: 0,
            deaths: 0,
            assists: 0,
            kda: kda,
            lastPlayedAt: nil
        )
    }

    private func makeRiotAccount(
        syncStatus: RiotSyncStatus,
        lastSyncErrorCode: String? = nil,
        lastSyncErrorMessage: String? = nil,
        lastSyncRequestedAt: Date? = nil,
        lastSyncSucceededAt: Date? = nil,
        lastSyncFailedAt: Date? = nil,
        lastSyncedAt: Date? = nil
    ) -> RiotAccount {
        RiotAccount(
            id: "ra1",
            riotGameName: "Hide on bush",
            tagLine: "KR1",
            region: "kr",
            puuid: "puuid-1",
            isPrimary: true,
            verificationStatus: .claimed,
            syncStatus: syncStatus,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage,
            lastSyncedAt: lastSyncedAt
        )
    }

    private func makeRiotAccountDTO(
        id: String = "ra1",
        syncStatus: RiotSyncStatus,
        lastSyncRequestedAt: Date? = nil,
        lastSyncSucceededAt: Date? = nil,
        lastSyncFailedAt: Date? = nil,
        lastSyncErrorCode: String? = nil,
        lastSyncErrorMessage: String? = nil,
        lastSyncedAt: Date? = nil
    ) -> RiotAccountDTO {
        RiotAccountDTO(
            id: id,
            riotGameName: "Hide on bush",
            tagLine: "KR1",
            region: "kr",
            puuid: "puuid-1",
            isPrimary: true,
            verificationStatus: .claimed,
            syncStatus: syncStatus,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage,
            lastSyncedAt: lastSyncedAt
        )
    }

    private func makeRiotSyncStatusDTO(
        id: String = "ra1",
        syncStatus: RiotSyncStatus,
        lastSyncRequestedAt: Date? = nil,
        lastSyncSucceededAt: Date? = nil,
        lastSyncFailedAt: Date? = nil,
        lastSyncErrorCode: String? = nil,
        lastSyncErrorMessage: String? = nil
    ) -> RiotAccountSyncStatusDTO {
        RiotAccountSyncStatusDTO(
            riotAccountId: id,
            syncStatus: syncStatus,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage
        )
    }

    private func makeProfileDTO() -> UserProfileDTO {
        UserProfileDTO(
            id: "u1",
            email: "user@example.com",
            nickname: "tester",
            primaryPosition: .mid,
            secondaryPosition: .top,
            isFillAvailable: true,
            styleTags: ["빡겜"],
            mannerScore: 100,
            noshowCount: 0
        )
    }

    private func makeGroupSummaryDTO(id: String, name: String) -> GroupSummaryDTO {
        GroupSummaryDTO(
            id: id,
            name: name,
            description: "\(name) 설명",
            visibility: .public,
            joinPolicy: .open,
            tags: ["서울"],
            ownerUserId: "owner",
            memberCount: 10,
            recentMatches: 3
        )
    }

    private func makePowerProfileDTO(userId: String = "u1") -> PowerProfileDTO {
        PowerProfileDTO(
            userId: userId,
            overallPower: 80,
            lanePower: ["MID": 80],
            primaryPosition: .mid,
            secondaryPosition: .top,
            style: PowerProfileDTO.StyleDTO(stability: 80, carry: 80, teamContribution: 80, laneInfluence: 80),
            version: "test"
        )
    }

    private func makeRecruitPostDTO(
        id: String,
        title: String,
        postType: RecruitingPostType = .memberRecruit
    ) -> RecruitPostDTO {
        RecruitPostDTO(
            id: id,
            groupId: "group-1",
            postType: postType,
            title: title,
            status: .open,
            scheduledAt: nil,
            body: "본문",
            tags: ["빡겜"],
            requiredPositions: ["MID"],
            createdBy: "tester"
        )
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        let bufferSize = 1024
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while bodyStream.hasBytesAvailable {
            let readCount = bodyStream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        return data.isEmpty ? nil : data
    }

    private func requestBodyJSONObject(from request: URLRequest) -> [String: Any]? {
        guard
            let data = requestBodyData(from: request),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return jsonObject
    }

    private func queryItemValues(from url: URL?, named name: String) -> [String] {
        URLComponents(url: url ?? URL(string: "https://example.invalid")!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .filter { $0.name == name }
            .compactMap(\.value) ?? []
    }
}

@MainActor
private final class MockNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    var currentStatus: NotificationAuthorizationState
    let requestResult: NotificationAuthorizationState

    init(currentStatus: NotificationAuthorizationState, requestResult: NotificationAuthorizationState) {
        self.currentStatus = currentStatus
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> NotificationAuthorizationState {
        currentStatus
    }

    func requestAuthorization() async throws -> Bool {
        currentStatus = requestResult
        return requestResult.canRegisterRemoteNotifications
    }
}

@MainActor
private final class MockRemoteNotificationRegistrar: RemoteNotificationRegistering {
    private(set) var registerCallCount = 0

    func registerForRemoteNotifications() {
        registerCallCount += 1
    }
}

@MainActor
private final class MockApplicationSettingsOpener: ApplicationSettingsOpening {
    private(set) var openSettingsCallCount = 0

    func openNotificationSettings() {
        openSettingsCallCount += 1
    }
}

@MainActor
private final class MockPushTokenSynchronizer: PushTokenSynchronizing {
    private(set) var syncCalls: [(token: String, notificationsEnabled: Bool)] = []

    func syncPushToken(_ deviceToken: String, notificationsEnabled: Bool) async {
        syncCalls.append((token: deviceToken, notificationsEnabled: notificationsEnabled))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: (@Sendable (URLRequest) throws -> (statusCode: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            let urlResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
