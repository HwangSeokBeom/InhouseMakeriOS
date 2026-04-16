import Combine
import ComposableArchitecture
import XCTest
@testable import InhouseMakeriOS

final class InhouseMakeriOSTests: XCTestCase {
    func testPositionShortLabel() {
        XCTAssertEqual(Position.jungle.shortLabel, "JGL")
        XCTAssertEqual(Position.support.shortLabel, "SUP")
    }

    func testAppConfigurationLoadsEnvironmentSpecificValues() {
        let configuration = AppConfiguration.fromInfoDictionary([
            "APP_ENV": "staging",
            "API_BASE_URL": "https://staging.example.internal",
            "GIDClientID": "staging-client-id",
        ])

        XCTAssertEqual(configuration.environment, .staging)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://staging.example.internal")
        XCTAssertEqual(configuration.googleClientID, "staging-client-id")
    }

    func testAppConfigurationFallsBackToSafeDefaults() {
        let configuration = AppConfiguration.fromInfoDictionary([:])

        XCTAssertEqual(configuration.environment, .dev)
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:3000")
        XCTAssertEqual(configuration.googleClientID, "")
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

    func testEmailSignUpRequestUsesExpectedEndpointAndPayload() async throws {
        let tokenStore = makeTokenStore()
        let repository = AuthRepository(
            apiClient: APIClient(
                configuration: makeConfiguration(),
                tokenStore: tokenStore,
                session: makeURLSession { request in
                    XCTAssertEqual(request.url?.path, "/auth/signup/email")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, "user@example.com")
                    XCTAssertEqual(payload["password"] as? String, "Password1!")
                    XCTAssertEqual(payload["nickname"] as? String, "tester")
                    XCTAssertEqual(payload["agreedToTerms"] as? Bool, true)
                    XCTAssertEqual(payload["agreedToPrivacy"] as? Bool, true)
                    XCTAssertEqual(payload["agreedToMarketing"] as? Bool, false)

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
            nickname: "tester",
            agreedToTerms: true,
            agreedToPrivacy: true,
            agreedToMarketing: false
        )

        XCTAssertEqual(tokens.user.email, "user@example.com")
        XCTAssertEqual(tokens.user.provider, .email)
        XCTAssertEqual(tokens.user.status, .active)
        XCTAssertEqual(tokens.accessToken, "signup-access")
        let persistedTokens = await tokenStore.loadTokens()
        XCTAssertEqual(persistedTokens, tokens)
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
                case "/auth/signup/email":
                    let body = try XCTUnwrap(self.requestBodyData(from: request))
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                    XCTAssertEqual(payload["email"] as? String, expectedEmail)
                    XCTAssertEqual(payload["password"] as? String, "Password1!")
                    XCTAssertEqual(payload["nickname"] as? String, "aa34")
                    XCTAssertEqual(payload["agreedToTerms"] as? Bool, true)
                    XCTAssertEqual(payload["agreedToPrivacy"] as? Bool, true)
                    XCTAssertEqual(payload["agreedToMarketing"] as? Bool, false)

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
        viewModel.toggleServiceTerms()
        viewModel.togglePrivacyTerms()

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
    func testEmailSignUpSubmitShowsFieldErrorForDuplicateEmail() async {
        let container = AppContainer(
            configuration: makeConfiguration(),
            tokenStore: makeTokenStore(),
            urlSession: makeURLSession { request in
                XCTAssertEqual(request.url?.path, "/auth/signup/email")
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
        viewModel.toggleServiceTerms()
        viewModel.togglePrivacyTerms()

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
                    let payload = try JSONEncoder.app.encode(GroupSummaryListDTO(items: [self.makeGroupSummaryDTO(id: "public-group", name: "공개 그룹")]))
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
        XCTAssertEqual(viewModel.state.value?.first?.name, "공개 그룹")

        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.first?.name, "비공개 그룹")

        session.restoreGuestSession()
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.first?.name, "공개 그룹")
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
                default:
                    XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                    return (500, Data())
                }
            }
        )
        let session = AppSessionViewModel(container: container)
        let viewModel = RecruitBoardViewModel(session: session)

        session.restoreGuestSession()
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "공개 모집")

        session.applyAuthenticatedSession(UserSession(authTokens: makeTokens(), user: makeProfile()))
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "계정 모집")

        session.restoreGuestSession()
        await viewModel.load(force: true)
        XCTAssertEqual(viewModel.state.value?.posts.first?.title, "공개 모집")
    }

    @MainActor
    func testMatchLobbyFeatureAuthRequiredQueuesRetryIntent() async {
        let store = TestStore(initialState: MatchLobbyFeature.State(groupID: "g1", matchID: "m1")) {
            MatchLobbyFeature()
        }

        await store.send(.loadResponse(.failure(.authRequiredFallback()))) {
            $0.loadState = .empty("로그인 후 내전 로비를 다시 열 수 있어요.")
            $0.pendingProtectedAction = .reload
        }
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

    private func makeTokens() -> AuthTokens {
        AuthTokens(
            user: AuthUser(id: "u1", email: "user@example.com", nickname: "tester"),
            accessToken: "access",
            refreshToken: "refresh"
        )
    }

    private func makeConfiguration() -> AppConfiguration {
        AppConfiguration(
            environment: .dev,
            baseURL: URL(string: "http://localhost:3000")!,
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

    private func makeRecruitPostDTO(id: String, title: String) -> RecruitPostDTO {
        RecruitPostDTO(
            id: id,
            groupId: "group-1",
            postType: .memberRecruit,
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
                url: request.url ?? URL(string: "http://localhost")!,
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
