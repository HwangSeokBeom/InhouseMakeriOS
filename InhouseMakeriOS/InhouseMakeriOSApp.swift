import ComposableArchitecture
import Foundation
import GoogleSignIn
import SwiftUI
import SwiftData

@main
struct InhouseMakeriOSApp: App {
    @StateObject private var router: AppRouter
    @StateObject private var session: AppSessionViewModel
    @State private var hasStartedLaunchSequence = false
    @State private var hasCompletedLaunchSequence = false
    private let modelContainer: ModelContainer
    private let debugLaunchScenario: DebugUITestLaunchScenario?

    init() {
        AppNavigationAppearance.apply()
        let modelContainer = AppModelContainerFactory.makeContainer()
        self.modelContainer = modelContainer
        if let launchScenario = DebugUITestLaunchScenario.makeCurrent(modelContainer: modelContainer) {
            self.debugLaunchScenario = launchScenario
            _router = StateObject(wrappedValue: launchScenario.router)
            _session = StateObject(wrappedValue: launchScenario.session)
        } else {
            self.debugLaunchScenario = nil
            _router = StateObject(wrappedValue: AppRouter())
            _session = StateObject(
                wrappedValue: AppSessionViewModel(
                    container: AppContainer(modelContainer: modelContainer)
                )
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let debugLaunchScenario {
                    debugLaunchScenario.rootView
                } else if !hasCompletedLaunchSequence {
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
            .modelContainer(modelContainer)
            .onAppear {
                debugAppRoot("source=AppRoot action=calculateRoot root=\(currentRootKind.rawValue) reason=\(currentRootReason)")
            }
            .task {
                guard debugLaunchScenario == nil else { return }
                await runLaunchSequenceIfNeeded()
            }
            .onChange(of: currentRootKind) { oldRoot, newRoot in
                debugAppRoot("source=AppRoot action=rootChanged from=\(oldRoot.rawValue) to=\(newRoot.rawValue) reason=\(currentRootReason)")
            }
            .onChange(of: session.shouldPresentOnboarding) { _, shouldPresentOnboarding in
                #if DEBUG
                if shouldPresentOnboarding {
                    print("[AppRoot] onboarding presented")
                    debugAppRoot("source=AppRoot action=setRoot from=home to=onboarding reason=onboarding_required")
                } else {
                    print("[AppRoot] landing dismissed; presenting main shell")
                    debugAppRoot("source=AppRoot action=setRoot from=onboarding to=home reason=onboarding_completed")
                }
                #endif
            }
            .onOpenURL { url in
                _ = GoogleAuthCallbackHandler.handle(url)
            }
        }
    }

    @MainActor
    private func runLaunchSequenceIfNeeded() async {
        guard !hasStartedLaunchSequence else {
            debugAppRoot("source=AppRoot action=launchSequenceDrop root=\(currentRootKind.rawValue) reason=already_started")
            return
        }
        hasStartedLaunchSequence = true

        #if DEBUG
        print("[AppRoot] splash presented")
        debugAppRoot("source=AppRoot action=splashPresented root=splash reason=launch_sequence_started")
        #endif

        async let bootstrapTask: Void = session.bootstrap()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await bootstrapTask

        guard !hasCompletedLaunchSequence else {
            debugAppRoot("source=AppRoot action=setRootDrop root=\(currentRootKind.rawValue) reason=launch_sequence_already_completed")
            return
        }
        let nextRoot = rootKindAfterSplash
        debugAppRoot("source=AppRoot action=setRoot from=splash to=\(nextRoot.rawValue) reason=\(rootReasonAfterBootstrap)")

        withAnimation(.easeInOut(duration: 0.3)) {
            hasCompletedLaunchSequence = true
        }

        #if DEBUG
        print("[AppRoot] splash finished")
        debugAppRoot("source=AppRoot action=splashFinished root=\(nextRoot.rawValue) reason=\(rootReasonAfterBootstrap)")
        #endif
    }

    private var currentRootKind: AppRootKind {
        if debugLaunchScenario != nil {
            return .debug
        }
        if !hasCompletedLaunchSequence {
            return .splash
        }
        if session.shouldPresentOnboarding {
            return .onboarding
        }
        return .home
    }

    private var rootKindAfterSplash: AppRootKind {
        session.shouldPresentOnboarding ? .onboarding : .home
    }

    private var currentRootReason: String {
        if debugLaunchScenario != nil {
            return "debug_launch_scenario"
        }
        if !hasCompletedLaunchSequence {
            return hasStartedLaunchSequence ? "launch_sequence_running" : "launch_sequence_not_started"
        }
        return rootReasonAfterBootstrap
    }

    private var rootReasonAfterBootstrap: String {
        if session.shouldPresentOnboarding {
            return "onboarding_required"
        }
        if session.isAuthenticated {
            return "session_restored"
        }
        return "guest_session"
    }

    private func debugAppRoot(_ message: String) {
        #if DEBUG
        print("[RouteDebug] \(message)")
        #endif
    }
}

private enum AppRootKind: String, Equatable {
    case debug
    case splash
    case onboarding
    case home
}

@MainActor
enum GoogleAuthCallbackHandler {
#if DEBUG
    static var handleURL: (URL) -> Bool = { url in
        GIDSignIn.sharedInstance.handle(url)
    }
#endif

    static func handle(_ url: URL) -> Bool {
#if DEBUG
        let handled = handleURL(url)
#else
        let handled = GIDSignIn.sharedInstance.handle(url)
#endif
        debugLog("callbackReceived scheme=\(url.scheme ?? "nil") handled=\(handled)")
        return handled
    }

    private static func debugLog(_ message: String) {
#if DEBUG
        print("[GoogleAuth] \(message)")
#endif
    }
}

private struct SplashView: View {
    @State private var isAnimating = false
    @State private var appearCount = 0

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
            appearCount += 1
            #if DEBUG
            print("[LifecycleDebug] screen=SplashView event=onAppear count=\(appearCount)")
            #endif
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#if DEBUG
@MainActor
private struct DebugUITestLaunchScenario {
    let session: AppSessionViewModel
    let router: AppRouter
    let rootView: AnyView

    static func makeCurrent(modelContainer: ModelContainer) -> DebugUITestLaunchScenario? {
        guard ProcessInfo.processInfo.arguments.contains(DebugGroupInviteFlowScenario.launchArgument) else {
            return nil
        }

        let defaults = UserDefaults(suiteName: "InhouseMakeriOS.DebugUITest.\(UUID().uuidString)")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DebugUITestURLProtocol.self]

        let container = AppContainer(
            modelContainer: modelContainer,
            localStore: AppLocalStore(defaults: defaults, modelContainer: modelContainer),
            urlSession: URLSession(configuration: configuration)
        )
        let session = AppSessionViewModel(container: container)
        session.applyAuthenticatedSession(
            UserSession(
                authTokens: AuthTokens(
                    user: AuthUser(
                        id: DebugGroupInviteFlowScenario.currentUser.id,
                        email: "uitest@example.com",
                        nickname: DebugGroupInviteFlowScenario.currentUser.nickname,
                        provider: .email,
                        status: .active
                    ),
                    accessToken: "uitest-access-token",
                    refreshToken: "uitest-refresh-token"
                ),
                user: UserProfile(
                    id: DebugGroupInviteFlowScenario.currentUser.id,
                    email: "uitest@example.com",
                    nickname: DebugGroupInviteFlowScenario.currentUser.nickname,
                    primaryPosition: .mid,
                    secondaryPosition: .top,
                    isFillAvailable: true,
                    styleTags: ["빡겜"],
                    mannerScore: 100,
                    noshowCount: 0
                )
            )
        )
        session.selectedTab = .match

        let router = AppRouter()
        return DebugUITestLaunchScenario(
            session: session,
            router: router,
            rootView: AnyView(DebugGroupInviteFlowRootView(session: session, router: router))
        )
    }
}

private struct DebugGroupInviteFlowRootView: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @StateObject private var viewModel: GroupDetailViewModel

    init(session: AppSessionViewModel, router: AppRouter) {
        self.session = session
        self.router = router
        _viewModel = StateObject(
            wrappedValue: GroupDetailViewModel(
                session: session,
                groupID: DebugGroupInviteFlowScenario.groupID
            )
        )
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            GroupDetailScreen(
                viewModel: viewModel,
                router: router,
                onGroupUpdated: { _ in },
                onGroupDeleted: { _ in }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case let .matchLobby(groupID, matchID):
                    MatchLobbyFeatureView(
                        store: Store(
                            initialState: MatchLobbyFeature.State(groupID: groupID, matchID: matchID)
                        ) {
                            MatchLobbyFeature()
                        } withDependencies: {
                            $0.appContainer = { session.container }
                        },
                        session: session,
                        router: router
                    )
                case let .teamBalance(groupID, matchID):
                    TeamBalanceFeatureView(
                        store: Store(
                            initialState: TeamBalanceFeature.State(groupID: groupID, matchID: matchID)
                        ) {
                            TeamBalanceFeature()
                        } withDependencies: {
                            $0.appContainer = { session.container }
                        },
                        session: session,
                        router: router
                    )
                case let .matchResult(matchID):
                    MatchResultFeatureView(
                        store: Store(
                            initialState: MatchResultFeature.State(matchID: matchID)
                        ) {
                            MatchResultFeature()
                        } withDependencies: {
                            $0.appContainer = { session.container }
                        },
                        session: session,
                        router: router
                    )
                default:
                    Text("Unsupported debug route")
                        .foregroundStyle(AppPalette.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppPalette.bgPrimary)
                }
            }
        }
    }
}

private final class DebugUITestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ProcessInfo.processInfo.arguments.contains(DebugGroupInviteFlowScenario.launchArgument)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            let response = await DebugGroupInviteFlowScenario.shared.response(for: request)
            guard let client else { return }

            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": response.contentType]
            )!

            client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: response.data)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private struct DebugProtocolResponse {
    let statusCode: Int
    let data: Data
    let contentType: String

    init(statusCode: Int, data: Data, contentType: String = "application/json") {
        self.statusCode = statusCode
        self.data = data
        self.contentType = contentType
    }
}

private actor DebugGroupInviteFlowScenario {
    static let launchArgument = "-ui-test-group-invite-flow"
    static let groupID = "debug-invite-flow-group"
    static let matchID = "debug-invite-flow-match"
    static let shared = DebugGroupInviteFlowScenario()

    struct StubUser: Identifiable {
        let id: String
        let nickname: String
        let role: GroupRole
        let primaryPosition: Position
        let secondaryPosition: Position
        let power: Double
    }

    static let currentUser = StubUser(
        id: "u1",
        nickname: "테스터",
        role: .owner,
        primaryPosition: .mid,
        secondaryPosition: .top,
        power: 94
    )

    private let inviteOnlyUser = StubUser(
        id: "u11",
        nickname: "초대후보",
        role: .member,
        primaryPosition: .support,
        secondaryPosition: .adc,
        power: 76
    )

    private let testMemberPool: [StubUser]
    private var members: [StubUser]
    private var matchResponse: MatchResponseDTO?
    private var submittedResult: MatchResultDTO?

    private init() {
        testMemberPool = [
            Self.currentUser,
            StubUser(id: "u2", nickname: "알파", role: .member, primaryPosition: .top, secondaryPosition: .mid, power: 83),
            StubUser(id: "u3", nickname: "브라보", role: .member, primaryPosition: .jungle, secondaryPosition: .top, power: 80),
            StubUser(id: "u4", nickname: "찰리", role: .member, primaryPosition: .mid, secondaryPosition: .adc, power: 81),
            StubUser(id: "u5", nickname: "델타", role: .member, primaryPosition: .adc, secondaryPosition: .support, power: 79),
            StubUser(id: "u6", nickname: "에코", role: .member, primaryPosition: .support, secondaryPosition: .adc, power: 78),
            StubUser(id: "u7", nickname: "폭스트롯", role: .member, primaryPosition: .top, secondaryPosition: .jungle, power: 77),
            StubUser(id: "u8", nickname: "골프", role: .member, primaryPosition: .jungle, secondaryPosition: .support, power: 82),
            StubUser(id: "u9", nickname: "호텔", role: .member, primaryPosition: .mid, secondaryPosition: .top, power: 84),
            StubUser(id: "u10", nickname: "인디아", role: .member, primaryPosition: .adc, secondaryPosition: .mid, power: 75),
        ]
        members = Array(testMemberPool.prefix(10))
    }

    func response(for request: URLRequest) -> DebugProtocolResponse {
        guard let url = request.url else {
            return serverError(statusCode: 400, code: "BAD_REQUEST", message: "Missing URL.", path: "/")
        }

        let method = request.httpMethod ?? "GET"
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path
        let requestBody = requestBodyData(from: request)

        switch (method, path) {
        case ("GET", "/groups/\(Self.groupID)"):
            return success(groupSummaryData())

        case ("GET", "/groups/\(Self.groupID)/members"):
            return success(memberListData())

        case ("GET", "/users/\(Self.currentUser.id)/inhouse-history"):
            return success(try! JSONEncoder.app.encode(HistoryResponseDTO(items: [])))

        case ("GET", let matchedPath) where matchedPath.hasPrefix("/users/") && matchedPath.hasSuffix("/power-profile"):
            let userID = matchedPath
                .replacingOccurrences(of: "/users/", with: "")
                .replacingOccurrences(of: "/power-profile", with: "")
            return success(powerProfileData(for: userID))

        case ("GET", "/users/search"):
            let query = components?.queryItems?.first(where: { $0.name == "query" })?.value ?? ""
            return success(inviteSearchData(query: query))

        case ("POST", "/groups/\(Self.groupID)/members"):
            guard
                let data = requestBody,
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let userID = object["userId"] as? String
            else {
                return serverError(statusCode: 400, code: "INVALID_PAYLOAD", message: "Invalid member payload.", path: path)
            }

            if members.contains(where: { $0.id == userID }) {
                return serverError(
                    statusCode: 409,
                    code: "GROUP_MEMBER_ALREADY_EXISTS",
                    message: "This user is already a member of the group.",
                    path: path
                )
            }

            if userID == inviteOnlyUser.id {
                members.append(inviteOnlyUser)
            }

            return success(memberListData())

        case ("POST", "/groups/\(Self.groupID)/matches"):
            let createdMatch = MatchResponseDTO(
                id: Self.matchID,
                groupId: Self.groupID,
                status: .recruiting,
                scheduledAt: nil,
                balanceMode: nil,
                selectedCandidateNo: nil,
                players: [makeMatchPlayer(for: Self.currentUser)],
                candidates: []
            )
            matchResponse = createdMatch
            return success(try! JSONEncoder.app.encode(createdMatch))

        case ("GET", "/matches/\(Self.matchID)"):
            guard let matchResponse else {
                return serverError(statusCode: 404, code: "MATCH_NOT_FOUND", message: "Match not found.", path: path)
            }
            return success(try! JSONEncoder.app.encode(matchResponse))

        case ("POST", "/matches/\(Self.matchID)/players"):
            guard var matchResponse else {
                return serverError(statusCode: 404, code: "MATCH_NOT_FOUND", message: "Match not found.", path: path)
            }
            guard
                let data = requestBody,
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let players = object["players"] as? [[String: Any]]
            else {
                return serverError(statusCode: 400, code: "INVALID_PAYLOAD", message: "Invalid player payload.", path: path)
            }

            let currentUserIDs = Set(matchResponse.players.map(\.userId))
            let appendedPlayers = players.compactMap { item -> MatchPlayerDTO? in
                guard let userID = item["userId"] as? String else { return nil }
                guard let member = members.first(where: { $0.id == userID }) else { return nil }
                guard !currentUserIDs.contains(userID) else { return nil }
                return makeMatchPlayer(for: member)
            }
            matchResponse = MatchResponseDTO(
                id: matchResponse.id,
                groupId: matchResponse.groupId,
                status: .recruiting,
                scheduledAt: matchResponse.scheduledAt,
                balanceMode: matchResponse.balanceMode,
                selectedCandidateNo: matchResponse.selectedCandidateNo,
                players: matchResponse.players + appendedPlayers,
                candidates: []
            )
            self.matchResponse = matchResponse
            return success(try! JSONEncoder.app.encode(matchResponse))

        case ("POST", "/matches/\(Self.matchID)/lock"):
            guard var matchResponse else {
                return serverError(statusCode: 404, code: "MATCH_NOT_FOUND", message: "Match not found.", path: path)
            }
            matchResponse = MatchResponseDTO(
                id: matchResponse.id,
                groupId: matchResponse.groupId,
                status: .locked,
                scheduledAt: matchResponse.scheduledAt,
                balanceMode: matchResponse.balanceMode,
                selectedCandidateNo: matchResponse.selectedCandidateNo,
                players: matchResponse.players,
                candidates: matchResponse.candidates
            )
            self.matchResponse = matchResponse
            return success(try! JSONEncoder.app.encode(matchResponse))

        case ("POST", "/matches/\(Self.matchID)/auto-balance"):
            guard var matchResponse else {
                return serverError(statusCode: 404, code: "MATCH_NOT_FOUND", message: "Match not found.", path: path)
            }
            let candidates = makeBalancedCandidates(from: matchResponse.players)
            matchResponse = MatchResponseDTO(
                id: matchResponse.id,
                groupId: matchResponse.groupId,
                status: .balanced,
                scheduledAt: matchResponse.scheduledAt,
                balanceMode: .balanced,
                selectedCandidateNo: nil,
                players: matchResponse.players,
                candidates: candidates
            )
            self.matchResponse = matchResponse
            return success(try! JSONEncoder.app.encode(MatchmakingCandidatesDTO(candidates: candidates)))

        case ("POST", "/matches/\(Self.matchID)/select-candidate"):
            guard var matchResponse else {
                return serverError(statusCode: 404, code: "MATCH_NOT_FOUND", message: "Match not found.", path: path)
            }
            let candidates = matchResponse.candidates ?? makeBalancedCandidates(from: matchResponse.players)
            guard let selectedCandidate = candidates.first else {
                return serverError(statusCode: 409, code: "BALANCE_CANDIDATE_EMPTY", message: "No candidates.", path: path)
            }
            let candidatePlayers = selectedCandidate.teamA + selectedCandidate.teamB
            let updatedPlayers = matchResponse.players.map { player -> MatchPlayerDTO in
                guard let candidatePlayer = candidatePlayers.first(where: { $0.userId == player.userId }) else {
                    return player
                }
                return MatchPlayerDTO(
                    id: player.id,
                    userId: player.userId,
                    nickname: player.nickname,
                    teamSide: candidatePlayer.teamSide,
                    assignedRole: candidatePlayer.assignedRole,
                    participationStatus: player.participationStatus,
                    isCaptain: player.isCaptain
                )
            }
            matchResponse = MatchResponseDTO(
                id: matchResponse.id,
                groupId: matchResponse.groupId,
                status: .resultPending,
                scheduledAt: matchResponse.scheduledAt,
                balanceMode: selectedCandidate.type,
                selectedCandidateNo: selectedCandidate.candidateNo,
                players: updatedPlayers,
                candidates: candidates
            )
            self.matchResponse = matchResponse
            return success(try! JSONEncoder.app.encode(matchResponse))

        case ("GET", "/matches/\(Self.matchID)/results"):
            guard let submittedResult else {
                return serverError(statusCode: 404, code: "RESOURCE_NOT_FOUND", message: "Result not found.", path: path)
            }
            return success(try! JSONEncoder.app.encode(submittedResult))

        case ("POST", "/matches/\(Self.matchID)/results/quick"):
            let result = MatchResultDTO(
                id: "result-ui-test",
                winningTeam: .blue,
                resultStatus: .partial,
                inputMode: .quick,
                players: (matchResponse?.players ?? []).map {
                    MatchStatDTO(userId: $0.userId, kills: 0, deaths: 0, assists: 0, laneResult: .even)
                },
                confirmations: []
            )
            submittedResult = result
            return success(try! JSONEncoder.app.encode(ResultSubmissionDTO(resultId: result.id, status: result.resultStatus, confirmationNeeded: 1)))

        default:
            return serverError(statusCode: 404, code: "RESOURCE_NOT_FOUND", message: "Unsupported debug route.", path: path)
        }
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(contentsOf: buffer[..<bytesRead])
            } else if bytesRead < 0 {
                return nil
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }

    private func groupSummaryData() -> Data {
        try! JSONEncoder.app.encode(
            GroupSummaryDTO(
                id: Self.groupID,
                name: "UI 테스트 그룹",
                description: "멤버 초대와 실제 로비 흐름을 검증하기 위한 UI 테스트 시나리오입니다.",
                visibility: .private,
                joinPolicy: .inviteOnly,
                tags: ["서울", "빡겜"],
                ownerUserId: Self.currentUser.id,
                canInviteMembers: true,
                inviteMembersBlockedReason: nil,
                memberCount: members.count,
                recentMatches: matchResponse == nil ? 0 : 1
            )
        )
    }

    private func memberListData() -> Data {
        try! JSONEncoder.app.encode(
            GroupMemberListDTO(
                items: members.enumerated().map { index, member in
                    GroupMemberDTO(
                        id: "gm-\(index + 1)",
                        userId: member.id,
                        nickname: member.nickname,
                        role: member.role
                    )
                }
            )
        )
    }

    private func inviteSearchData(query: String) -> Data {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let users: [DebugInviteSearchUser]
        if trimmedQuery.contains("none") || trimmedQuery.contains("없음") || trimmedQuery.contains("zero") {
            users = []
        } else {
            users = [
                DebugInviteSearchUser(from: Self.currentUser),
                DebugInviteSearchUser(from: testMemberPool[1]),
                DebugInviteSearchUser(from: inviteOnlyUser),
            ]
        }

        return try! JSONEncoder.app.encode(DebugInviteSearchResponse(items: users))
    }

    private func powerProfileData(for userID: String) -> Data {
        let user = (testMemberPool + [inviteOnlyUser]).first(where: { $0.id == userID }) ?? Self.currentUser
        return try! JSONEncoder.app.encode(
            PowerProfileDTO(
                userId: user.id,
                overallPower: user.power,
                lanePower: [
                    Position.top.rawValue: user.primaryPosition == .top ? user.power : user.power - 8,
                    Position.jungle.rawValue: user.primaryPosition == .jungle ? user.power : user.power - 9,
                    Position.mid.rawValue: user.primaryPosition == .mid ? user.power : user.power - 7,
                    Position.adc.rawValue: user.primaryPosition == .adc ? user.power : user.power - 6,
                    Position.support.rawValue: user.primaryPosition == .support ? user.power : user.power - 5,
                ],
                primaryPosition: user.primaryPosition,
                secondaryPosition: user.secondaryPosition,
                style: PowerProfileDTO.StyleDTO(
                    stability: nil,
                    carry: 77,
                    teamContribution: 82,
                    laneInfluence: 79
                ),
                basePower: user.power - 4,
                formScore: 78,
                inhouseMmr: user.power + 30,
                inhouseConfidence: 0.92,
                version: "debug-ui-test",
                calculatedAt: Date()
            )
        )
    }

    private func makeMatchPlayer(for user: StubUser) -> MatchPlayerDTO {
        MatchPlayerDTO(
            id: "mp-\(user.id)",
            userId: user.id,
            nickname: user.nickname,
            teamSide: nil,
            assignedRole: user.primaryPosition,
            participationStatus: .accepted,
            isCaptain: user.id == Self.currentUser.id
        )
    }

    private func makeBalancedCandidates(from players: [MatchPlayerDTO]) -> [MatchCandidateDTO] {
        let orderedPlayers = players.sorted { $0.userId < $1.userId }
        let blueTeam = Array(orderedPlayers.prefix(5))
        let redTeam = Array(orderedPlayers.dropFirst(5).prefix(5))

        let blueCandidatePlayers = blueTeam.enumerated().map { index, player in
            CandidatePlayerDTO(
                userId: player.userId,
                nickname: player.nickname,
                teamSide: .blue,
                assignedRole: preferredRole(for: index),
                rolePower: rolePower(for: player.userId)
            )
        }
        let redCandidatePlayers = redTeam.enumerated().map { index, player in
            CandidatePlayerDTO(
                userId: player.userId,
                nickname: player.nickname,
                teamSide: .red,
                assignedRole: preferredRole(for: index),
                rolePower: rolePower(for: player.userId)
            )
        }

        return [
            MatchCandidateDTO(
                candidateId: "candidate-balanced-1",
                candidateNo: 1,
                type: .balanced,
                score: 3,
                metrics: CandidateMetricsDTO(
                    teamPowerGap: 3,
                    laneMatchupGap: 2,
                    offRolePenalty: 0,
                    repeatTeamPenalty: 0,
                    preferenceViolationPenalty: 0,
                    volatilityClusterPenalty: 1
                ),
                teamAPower: blueCandidatePlayers.map(\.rolePower).reduce(0, +),
                teamBPower: redCandidatePlayers.map(\.rolePower).reduce(0, +),
                offRoleCount: 0,
                explanationTags: ["파워 균형", "포지션 안정"],
                teamA: blueCandidatePlayers,
                teamB: redCandidatePlayers
            )
        ]
    }

    private func preferredRole(for index: Int) -> Position {
        let roles: [Position] = [.top, .jungle, .mid, .adc, .support]
        return roles[index % roles.count]
    }

    private func rolePower(for userID: String) -> Double {
        (testMemberPool + [inviteOnlyUser]).first(where: { $0.id == userID })?.power ?? 70
    }

    private func success(_ data: Data) -> DebugProtocolResponse {
        DebugProtocolResponse(statusCode: 200, data: data)
    }

    private func serverError(statusCode: Int, code: String, message: String, path: String) -> DebugProtocolResponse {
        let payload: [String: Any] = [
            "statusCode": statusCode,
            "code": code,
            "message": message,
            "timestamp": ISO8601DateFormatter.full.string(from: Date()),
            "path": path,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return DebugProtocolResponse(statusCode: statusCode, data: data)
    }
}

private struct DebugInviteSearchResponse: Encodable {
    let items: [DebugInviteSearchUser]
}

private struct DebugInviteSearchUser: Encodable {
    let id: String
    let nickname: String
    let primaryPosition: Position
    let secondaryPosition: Position
    let recentPower: Double
    let riotDisplayName: String

    init(from user: DebugGroupInviteFlowScenario.StubUser) {
        id = user.id
        nickname = user.nickname
        primaryPosition = user.primaryPosition
        secondaryPosition = user.secondaryPosition
        recentPower = user.power
        riotDisplayName = "\(user.nickname)#KR1"
    }
}
#else
@MainActor
private struct DebugUITestLaunchScenario {
    static func makeCurrent(modelContainer _: ModelContainer) -> DebugUITestLaunchScenario? {
        nil
    }

    var session: AppSessionViewModel {
        fatalError("DebugUITestLaunchScenario is unavailable in non-debug builds.")
    }

    var router: AppRouter {
        fatalError("DebugUITestLaunchScenario is unavailable in non-debug builds.")
    }

    var rootView: AnyView {
        fatalError("DebugUITestLaunchScenario is unavailable in non-debug builds.")
    }
}
#endif
