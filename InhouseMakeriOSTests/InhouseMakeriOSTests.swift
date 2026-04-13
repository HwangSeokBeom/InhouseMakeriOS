import Combine
import ComposableArchitecture
import XCTest
@testable import InhouseMakeriOS

final class InhouseMakeriOSTests: XCTestCase {
    func testPositionShortLabel() {
        XCTAssertEqual(Position.jungle.shortLabel, "JGL")
        XCTAssertEqual(Position.support.shortLabel, "SUP")
    }

    func testResultStatusTitle() {
        XCTAssertEqual(ResultStatus.partial.title, "임시 기록")
        XCTAssertEqual(ResultStatus.confirmed.title, "확인됨")
    }

    func testAuthProviderOnlyContainsAppleAndGoogle() {
        XCTAssertEqual(AuthProvider.allCases, [.apple, .google])
        XCTAssertNil(AuthProvider(serverValue: "EMAIL"))
    }

    func testAuthFlowStateDoesNotExposeEmailSubflows() {
        let labels = Mirror(reflecting: AuthFlowState()).children.compactMap(\.label)
        XCTAssertEqual(labels, ["entryState", "socialLoginState", "successTransitionState"])
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

    func testEmailAuthDisabledUsesSocialOnlyCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Disabled",
            code: "EMAIL_AUTH_DISABLED",
            statusCode: 400
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .emailAuthDisabled)
        XCTAssertEqual(
            AuthError.emailAuthDisabled.presentationError.message,
            "이 앱에서는 Apple 또는 Google 로그인만 사용할 수 있어요."
        )
    }

    func testPasswordAuthDisabledUsesSocialOnlyCopy() {
        let error = UserFacingError(
            title: "서버 오류",
            message: "Disabled",
            code: "PASSWORD_AUTH_DISABLED",
            statusCode: 400
        )

        XCTAssertEqual(AuthErrorMapper.map(error), .passwordAuthDisabled)
        XCTAssertEqual(
            AuthError.passwordAuthDisabled.presentationError.message,
            "이 앱에서는 Apple 또는 Google 로그인만 사용할 수 있어요."
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
                            user: AuthUserDTO(id: "u1", email: "user@example.com", nickname: "tester"),
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
    func testBootstrapWithoutPersistedTokensTransitionsToGuest() async {
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
        session.restoreGuestSession()
        XCTAssertTrue(session.shouldPresentOnboarding)

        let didPublish = expectation(description: "session publishes onboarding completion")
        let cancellable = session.objectWillChange.sink {
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

    private func makeTokens() -> AuthTokens {
        AuthTokens(
            user: AuthUser(id: "u1", email: "user@example.com", nickname: "tester"),
            accessToken: "access",
            refreshToken: "refresh"
        )
    }

    private func makeConfiguration() -> AppConfiguration {
        AppConfiguration(baseURL: URL(string: "http://localhost:3000")!, googleClientID: "test-google-client-id")
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
