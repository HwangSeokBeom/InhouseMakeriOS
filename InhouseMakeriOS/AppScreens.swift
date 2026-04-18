import AuthenticationServices
import ComposableArchitecture
import GoogleSignIn
import MessageUI
import SafariServices
import SwiftUI
import UIKit

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []
    private var pendingRouteRequest: AppRoute?

    func push(_ route: AppRoute) {
        debugRoute("requested", route: route)

        if pendingRouteRequest == route {
            debugRoute("ignored duplicate", route: route, detail: "reason=same_runloop_request")
            return
        }
        pendingRouteRequest = route
        Task { @MainActor [weak self] in
            self?.pendingRouteRequest = nil
        }

        if path.last == route {
            debugRoute("ignored duplicate", route: route, detail: "reason=already_visible")
            return
        }

        if let existingIndex = path.lastIndex(of: route) {
            let nextPath = Array(path.prefix(existingIndex + 1))
            guard nextPath != path else {
                debugRoute("ignored duplicate", route: route, detail: "reason=no_path_change")
                return
            }
            path = nextPath
            debugRoute("reused", route: route, detail: "depth=\(existingIndex)")
            return
        }
        path.append(route)
        debugRoute("accepted", route: route)
    }

    func pop() {
        _ = path.popLast()
    }

    func removeRoutes(referencingGroupID groupID: String) {
        guard let firstMatchIndex = path.firstIndex(where: { $0.references(groupID: groupID) }) else { return }
        path = Array(path.prefix(firstMatchIndex))
    }

    func reset() {
        path.removeAll()
    }

    private func debugRoute(_ event: String, route: AppRoute, detail: String? = nil) {
#if DEBUG
        if let detail {
            print("[Route] \(event) route=\(route.debugDescription) \(detail)")
        } else {
            print("[Route] \(event) route=\(route.debugDescription)")
        }
#endif
    }
}

private extension AppRoute {
    var debugDescription: String {
        switch self {
        case .search:
            return "search"
        case .notifications:
            return "notifications"
        case .riotAccounts:
            return "riot_accounts"
        case .settings:
            return "settings"
        case .homeUpcomingMatches:
            return "home_upcoming_matches"
        case .homeGroups:
            return "home_groups"
        case .powerDetail:
            return "power_detail"
        case let .memberProfile(userID, nickname):
            return "member_profile userID=\(userID) nickname=\(nickname)"
        case .homeRecentMatches:
            return "home_recent_matches"
        case let .groupDetail(groupID):
            return "group_detail groupID=\(groupID)"
        case let .matchLobby(groupID, matchID):
            return "match_lobby groupID=\(groupID) matchID=\(matchID)"
        case let .teamBalance(groupID, matchID):
            return "team_balance groupID=\(groupID) matchID=\(matchID)"
        case let .manualAdjust(matchID, draft):
            return "manual_adjust matchID=\(matchID) mode=\(draft.mode.rawValue)"
        case let .matchResult(matchID):
            return "match_result matchID=\(matchID)"
        case let .matchDetail(matchID):
            return "match_detail matchID=\(matchID)"
        case let .recruitDetail(postID):
            return "recruit_detail postID=\(postID)"
        }
    }

    func references(groupID: String) -> Bool {
        switch self {
        case let .groupDetail(routeGroupID):
            return routeGroupID == groupID
        case let .matchLobby(routeGroupID, _):
            return routeGroupID == groupID
        case let .teamBalance(routeGroupID, _):
            return routeGroupID == groupID
        default:
            return false
        }
    }
}

enum SessionState {
    case bootstrapping
    case guest
    case authenticating
    case authenticated(UserSession)
}

enum OnboardingPresentationState: Equatable {
    case unresolved
    case required
    case completed
}

enum AppModalKind: String {
    case loginPrompt
    case groupCreate
    case recruitCreate

    var debugName: String { rawValue }
}

private enum InitialLoadSkipReason: String {
    case alreadyLoaded = "already_loaded"
    case inFlight = "in_flight"
    case sessionReused = "session_reused"
}

@MainActor
private final class InitialLoadTracker {
    private let screen: String
    private(set) var hasLoadedInitialData = false
    private(set) var isInFlight = false

    init(screen: String) {
        self.screen = screen
    }

    func begin(force: Bool, trigger: String) -> Bool {
        if isInFlight {
            debugSkip(trigger: trigger, reason: .inFlight)
            return false
        }
        if !force, hasLoadedInitialData {
            debugSkip(trigger: trigger, reason: .alreadyLoaded)
            return false
        }
        isInFlight = true
        debugStart(trigger: trigger)
        return true
    }

    func finish(success: Bool) {
        isInFlight = false
        if success {
            hasLoadedInitialData = true
        }
    }

    func reset() {
        hasLoadedInitialData = false
        isInFlight = false
    }

    func logSessionReused(trigger: String) {
        debugSkip(trigger: trigger, reason: .sessionReused)
    }

    private func debugStart(trigger: String) {
        #if DEBUG
        print("[InitialLoad] screen=\(screen) trigger=\(trigger) started")
        #endif
    }

    private func debugSkip(trigger: String, reason: InitialLoadSkipReason) {
        #if DEBUG
        print("[InitialLoad] screen=\(screen) trigger=\(trigger) skipped reason=\(reason.rawValue)")
        #endif
    }
}

private func debugSkipDeletedGroupReload(groupID: String) {
    #if DEBUG
    print("[InitialLoad] skip deleted group reload groupId=\(groupID)")
    #endif
}

@MainActor
final class AppSessionViewModel: ObservableObject {
    private struct PendingAuthAction {
        let requirement: AuthRequirement
        let action: (@MainActor () -> Void)?
    }

    @Published var state: SessionState = .bootstrapping
    @Published var selectedTab: AppTab = .home
    @Published var actionState: AsyncActionState = .idle
    @Published var authPrompt: AuthPromptContext?
    @Published private(set) var onboardingPresentationState: OnboardingPresentationState = .unresolved
    @Published private(set) var activeModal: AppModalKind?
    @Published private(set) var riotAccountsViewState: RiotLinkedAccountsViewState = .loading
    @Published private(set) var riotLinkedDataRevision = 0

    let container: AppContainer
    private(set) var userSession: UserSession?
    private var pendingAuthAction: PendingAuthAction?
    private var deferredAuthPrompt: AuthPromptContext?
    private var suppressNextAuthPromptDismissSync = false
    private var deletedGroupIDs: Set<String> = []

    init(container: AppContainer) {
        self.container = container
    }

    func debugLog(_ message: String) {
        #if DEBUG
        print("[AppSession] \(message)")
        #endif
    }

    var authTokens: AuthTokens? {
        userSession?.authTokens
    }

    var profile: UserProfile? {
        userSession?.user
    }

    var currentUserID: String? {
        userSession?.user.id ?? userSession?.authTokens.user.id
    }

    var isAuthenticated: Bool {
        if case .authenticated = state {
            return true
        }
        return false
    }

    var isGuest: Bool {
        if case .guest = state {
            return true
        }
        return false
    }

    var hasCompletedOnboarding: Bool {
        onboardingPresentationState == .completed
    }

    var shouldPresentOnboarding: Bool {
        onboardingPresentationState == .required && !isAuthenticated
    }

    var dataScopeKey: String {
        userSession.map { "authenticated:\($0.user.id)" } ?? "guest"
    }

    func bootstrap() async {
        guard case .bootstrapping = state else { return }
        await bootstrapLiveSession()
    }

    private func bootstrapLiveSession() async {
        let persistedTokens = await container.authRepository.loadPersistedTokens()

        guard let persistedTokens else {
            syncOnboardingPresentation(hasAuthenticatedSession: false)
            updateRiotAccountsViewState(.noLinkedAccounts)
            debugLog("bootstrap completed without persisted tokens; session changed to guest")
            state = .guest
            return
        }

        do {
            let profile = try await container.profileRepository.me()
            let session = UserSession(authTokens: persistedTokens, user: profile)
            userSession = session
            syncOnboardingPresentation(hasAuthenticatedSession: true)
            updateRiotAccountsViewState(.loading)
            debugLog("bootstrap restored authenticated session for user \(session.user.id)")
            state = .authenticated(session)
        } catch {
            await container.authRepository.signOut()
            userSession = nil
            syncOnboardingPresentation(hasAuthenticatedSession: false)
            updateRiotAccountsViewState(.noLinkedAccounts)
            debugLog("bootstrap failed to restore session; falling back to guest")
            state = .guest
        }
    }

    func completeGuestOnboarding(resetTabSelection: Bool = true) {
        debugLog(resetTabSelection ? "continueAsGuest tapped" : "onboarding completed by authenticated session")
        container.localStore.setOnboardingStatus(.completed)
        onboardingPresentationState = .completed
        if resetTabSelection {
            selectedTab = .home
        }
        if isAuthenticated {
            debugLog("guest onboarding flag completed while authenticated; keeping current session")
            return
        }
        debugLog("guest onboarding completed; session changed to guest")
        state = .guest
    }

    func beginAuthenticating() {
        state = .authenticating
    }

    func restoreGuestSession() {
        userSession = nil
        updateRiotAccountsViewState(.noLinkedAccounts)
        debugLog("session changed to guest")
        state = .guest
    }

    func requireAuthentication(
        for requirement: AuthRequirement,
        perform action: (@MainActor () -> Void)? = nil
    ) {
        if isAuthenticated {
            action?()
            return
        }

        if let action {
            pendingAuthAction = PendingAuthAction(requirement: requirement, action: action)
            presentLoginPrompt(AuthPromptContext(requirement: requirement), replacingExisting: true)
            return
        }

        if pendingAuthAction == nil {
            pendingAuthAction = PendingAuthAction(requirement: requirement, action: nil)
        }

        if authPrompt == nil, deferredAuthPrompt == nil {
            presentLoginPrompt(AuthPromptContext(requirement: requirement), replacingExisting: false)
        }
    }

    func requireReauthentication(
        for requirement: AuthRequirement,
        perform action: (@MainActor () -> Void)? = nil
    ) {
        if isAuthenticated {
            restoreGuestSession()
        }
        requireAuthentication(for: requirement, perform: action)
    }

    func openProtectedRoute(_ route: AppRoute, requirement: AuthRequirement, router: AppRouter) {
        requireAuthentication(for: requirement) {
            router.push(route)
        }
    }

    func canAccessGroupSummary(_ group: GroupSummary) -> Bool {
        group.isAccessible(knownMember: container.localStore.containsGroup(id: group.id))
    }

    func openGroupDetailIfAccessible(_ group: GroupSummary, router: AppRouter) {
        guard canAccessGroupSummary(group) else {
            actionState = .failure("참여 중인 그룹만 확인할 수 있어요.")
            return
        }

        openProtectedRoute(.groupDetail(group.id), requirement: .groupManagement, router: router)
    }

    func markGroupContextDeleted(_ groupID: String) {
        deletedGroupIDs.insert(groupID)
        container.localStore.removeGroup(id: groupID)
    }

    func isDeletedGroupContext(_ groupID: String) -> Bool {
        deletedGroupIDs.contains(groupID)
    }

    func hasValidGroupContext(_ groupID: String?) -> Bool {
        guard let groupID else { return false }
        return !deletedGroupIDs.contains(groupID) && container.localStore.containsGroup(id: groupID)
    }

    func preferredGroupContextID() -> String? {
        return container.localStore.storedGroupIDs.first { !deletedGroupIDs.contains($0) }
    }

    func requestModalPresentation(_ modal: AppModalKind) {
        guard activeModal != modal else { return }
        debugLog("present \(modal.debugName) requested")
        activeModal = modal
    }

    func handleModalDismissed(_ modal: AppModalKind) {
        if activeModal == modal {
            activeModal = nil
        }
        debugLog("\(modal.debugName) dismissed by user")
        guard modal != .loginPrompt else { return }
        presentDeferredLoginPromptIfPossible()
    }

    func syncAuthPromptPresentation(_ prompt: AuthPromptContext?) {
        guard prompt == nil else {
            requestModalPresentation(.loginPrompt)
            return
        }

        if suppressNextAuthPromptDismissSync {
            suppressNextAuthPromptDismissSync = false
            return
        }

        if activeModal == .loginPrompt {
            activeModal = nil
        }
        pendingAuthAction = nil
        deferredAuthPrompt = nil
        debugLog("loginPrompt dismissed by user")
    }

    func dismissAuthPrompt() {
        clearAuthPrompt(userInitiated: true)
    }

    func resumePendingAuthActionIfNeeded() {
        consumePendingAuthAction()?()
    }

    @discardableResult
    func handleProtectedActionError(
        _ error: UserFacingError,
        requirement: AuthRequirement,
        actionState: inout AsyncActionState
    ) -> Bool {
        if error.requiresAuthentication {
            requireReauthentication(for: requirement)
            return true
        }

        actionState = .failure(error.message)
        return error.isForbiddenFeature || error.isRateLimited
    }

    @discardableResult
    func handleProtectedLoadError<Value>(
        _ error: UserFacingError,
        requirement: AuthRequirement,
        state: inout ScreenLoadState<Value>,
        fallbackMessage: String
    ) -> Bool {
        if error.requiresAuthentication {
            requireReauthentication(for: requirement)
            state = .empty(fallbackMessage)
            return true
        }

        state = .error(error)
        return error.isForbiddenFeature || error.isRateLimited
    }

    func refreshProfile() async {
        guard let authTokens else { return }
        do {
            let profile = try await container.profileRepository.me()
            let session = UserSession(authTokens: authTokens, user: profile)
            userSession = session
            state = .authenticated(session)
        } catch let error as UserFacingError {
            if error.requiresAuthentication {
                requireReauthentication(for: .settings)
                return
            }
            actionState = .failure(error.message)
        } catch {
            actionState = .failure("프로필 새로고침에 실패했습니다")
        }
    }

    func updateAuthenticatedProfile(_ profile: UserProfile) {
        guard let authTokens else { return }
        let session = UserSession(authTokens: authTokens, user: profile)
        userSession = session
        state = .authenticated(session)
    }

    func refreshRiotAccountsViewState(
        force: Bool = false,
        invalidateDependents: Bool = false
    ) async -> RiotLinkedAccountsViewState {
        guard isAuthenticated else {
            updateRiotAccountsViewState(.noLinkedAccounts, invalidateDependents: invalidateDependents)
            return riotAccountsViewState
        }

        if !force {
            switch riotAccountsViewState {
            case .noLinkedAccounts, .loaded:
                return riotAccountsViewState
            case .loading, .error:
                break
            }
        }

        updateRiotAccountsViewState(.loading)

        do {
            let accounts = try await container.riotRepository.list()
            let nextState = RiotLinkedAccountsViewState(accounts: accounts)
            updateRiotAccountsViewState(nextState, invalidateDependents: invalidateDependents)
            return nextState
        } catch let error as UserFacingError {
            let mappedError = error.serverContractMapped
            updateRiotAccountsViewState(.error(mappedError), invalidateDependents: invalidateDependents)
            return .error(mappedError)
        } catch {
            let mappedError = UserFacingError(
                title: "Riot ID 로딩 실패",
                message: "Riot ID를 불러오지 못했습니다."
            )
            updateRiotAccountsViewState(.error(mappedError), invalidateDependents: invalidateDependents)
            return .error(mappedError)
        }
    }

    func applyRiotAccounts(_ accounts: [RiotAccount], invalidateDependents: Bool = false) {
        updateRiotAccountsViewState(
            RiotLinkedAccountsViewState(accounts: accounts),
            invalidateDependents: invalidateDependents
        )
    }

    func signOut(router: AppRouter) async {
        await container.authRepository.signOut()
        router.reset()
        userSession = nil
        selectedTab = .home
        pendingAuthAction = nil
        deferredAuthPrompt = nil
        clearAuthPrompt(userInitiated: false)
        syncOnboardingPresentation(hasAuthenticatedSession: false)
        updateRiotAccountsViewState(.noLinkedAccounts)
        debugLog("signOut completed; route reset to main home and session changed to guest")
        state = .guest
    }

    func applyAuthenticatedSession(_ session: UserSession) {
        userSession = session
        syncOnboardingPresentation(hasAuthenticatedSession: true)
        updateRiotAccountsViewState(.loading)
        debugLog("session changed to authenticated for user \(session.user.id)")
        state = .authenticated(session)
    }

    func consumePendingAuthAction() -> (@MainActor () -> Void)? {
        let action = pendingAuthAction?.action
        pendingAuthAction = nil
        deferredAuthPrompt = nil
        clearAuthPrompt(userInitiated: false)
        return action
    }

    private func presentLoginPrompt(_ prompt: AuthPromptContext, replacingExisting: Bool) {
        if let activeModal, activeModal != .loginPrompt {
            if replacingExisting || deferredAuthPrompt == nil {
                deferredAuthPrompt = prompt
            }
            debugLog("login prompt suppressed because \(activeModal.debugName) is active")
            return
        }

        if replacingExisting || authPrompt == nil {
            authPrompt = prompt
        }
    }

    private func presentDeferredLoginPromptIfPossible() {
        guard authPrompt == nil, activeModal == nil, let deferredAuthPrompt else { return }
        self.deferredAuthPrompt = nil
        debugLog("presenting login prompt after dismiss")
        authPrompt = deferredAuthPrompt
    }

    private func updateRiotAccountsViewState(
        _ nextState: RiotLinkedAccountsViewState,
        invalidateDependents: Bool = false
    ) {
        riotAccountsViewState = nextState
        if invalidateDependents {
            riotLinkedDataRevision &+= 1
        }
    }

    private func clearAuthPrompt(userInitiated: Bool) {
        let hadAuthPrompt = authPrompt != nil
        suppressNextAuthPromptDismissSync = hadAuthPrompt
        authPrompt = nil
        if activeModal == .loginPrompt {
            activeModal = nil
        }

        guard userInitiated else { return }
        pendingAuthAction = nil
        deferredAuthPrompt = nil
        debugLog("loginPrompt dismissed by user")
    }

    private func syncOnboardingPresentation(hasAuthenticatedSession: Bool) {
        let normalizationResult = container.localStore.resolveOnboardingStatus(
            hasAuthenticatedSession: hasAuthenticatedSession
        )

        switch normalizationResult.status {
        case .pending:
            onboardingPresentationState = .required
        case .completed:
            onboardingPresentationState = .completed
        }

        let normalizationLabel = normalizationResult.status.rawValue
        let sourceLabel = normalizationResult.source.rawValue
        if normalizationResult.didMigrate {
            debugLog("onboarding normalized to \(normalizationLabel) via \(sourceLabel)")
        } else {
            debugLog("onboarding resolved as \(normalizationLabel)")
        }
    }
}

// MARK: - Root View Models

enum GroupCreationFlowResult {
    case success(GroupSummary)
    case failure(String)
    case requiresAuthentication
}

enum RecruitPostCreationFlowResult {
    case success(RecruitPost)
    case failure(String)
    case invalidGroupContext(String)
    case requiresAuthentication
}

enum RecruitBoardLoadTrigger: String {
    case screenAppear = "screen_appear"
    case retry = "retry"
    case sessionScopeChange = "session_scope_change"
    case createSheetDismissed = "create_sheet_dismissed"
    case selectedTypeChanged = "type_switch"
    case filtersChanged = "filters_changed"
    case postUpdated = "post_updated"
    case postDeleted = "post_deleted"
}

enum RecruitBoardSelectedTypeChangeReason: String {
    case initialState = "initial_state"
    case userSelection = "user_selection"
    case createSuccess = "create_success"
    case reset = "reset"
}

enum RecruitBoardFilterChangeReason: String {
    case date = "date"
    case positions = "positions"
    case regions = "regions"
    case tags = "tags"
    case reset = "reset"
}

enum RecruitDetailLoadTrigger: String {
    case screenAppear = "screen_appear"
    case retry = "retry"
}

private enum RecruitDetailErrorType: String {
    case authRequired = "auth_required"
    case forbidden = "forbidden"
    case notFound = "not_found"
    case transient = "transient"
    case other = "other"
}

private enum RecruitDetailMutationErrorType: String {
    case authRequired = "auth_required"
    case forbidden = "forbidden"
    case notFound = "not_found"
    case conflict = "conflict"
    case server = "server"
    case other = "other"
}

enum RecruitApplyCapability: Equatable {
    case unknown
    case available
    case unavailable(String)

    var note: String? {
        switch self {
        case .unknown:
            return "참가 신청은 서버 지원 여부에 따라 동작합니다."
        case .available:
            return "참가 신청이 가능하면 즉시 요청을 보내고 상세 화면을 새로고칩니다."
        case let .unavailable(message):
            return message
        }
    }
}

struct RecruitDetailViewState: Equatable {
    let postID: String
    let groupID: String
    let postType: RecruitingPostType
    let title: String
    let groupName: String
    let authorName: String?
    let requiredPositionsText: String
    let statusText: String
    let moodTagsText: String
    let scheduledAtText: String
    let bodyText: String
    let isOwner: Bool
}

private enum RecruitOptionCatalog {
    static let positions = ["TOP", "JUNGLE", "MID", "ADC", "SUPPORT"]
    static let regions = ["서울", "경기", "인천", "부산", "대구", "광주", "대전", "울산", "세종", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주"]
    static let moodTags = ["빡겜", "즐겜", "친목", "초보환영", "주말", "평일", "급구"]
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<HomeContentState> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "home")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        state = .loading

        if let profile = session.profile, let userID = session.currentUserID {
            do {
                let groups = try await loadTrackedGroups()
                let currentMatch = try await loadCurrentMatch()
                let posts = try await loadRecruitingPostsForHome(isAuthenticated: true)
                let riotAccountsViewState = await session.refreshRiotAccountsViewState(force: force)
                if case let .error(error) = riotAccountsViewState, error.requiresAuthentication {
                    throw error
                }
                let power: PowerProfile?
                if riotAccountsViewState.hasLinkedAccounts {
                    power = try? await session.container.profileRepository.powerProfile(userID: userID)
                } else {
                    power = nil
                }
                let history = try await session.container.profileRepository.history(userID: userID, limit: 1)
                let snapshot = HomeSnapshot(
                    profile: profile,
                    riotAccountsViewState: riotAccountsViewState,
                    power: power,
                    groups: groups,
                    currentMatch: currentMatch,
                    latestHistory: history.first,
                    recruitingPosts: Array(posts.prefix(4))
                )

                if groups.isEmpty && currentMatch == nil && snapshot.latestHistory == nil && posts.isEmpty {
                    state = .empty("홈 집계에 사용할 데이터가 아직 없습니다.\n그룹을 만들거나 모집글을 확인해 흐름을 시작해주세요.")
                } else {
                    state = .content(.authenticated(snapshot))
                }
                didSucceed = true
            } catch let error as UserFacingError {
                session.handleProtectedLoadError(
                    error,
                    requirement: .profileSync,
                    state: &state,
                    fallbackMessage: "로그인 후 홈 정보를 다시 확인할 수 있어요."
                )
            } catch {
                state = .error(UserFacingError(title: "홈 로딩 실패", message: "홈 데이터를 불러오지 못했습니다."))
            }
            return
        }

        let groups = ((try? await session.container.groupRepository.listPublic()) ?? []).filterPubliclyVisible()
        let posts = (try? await loadRecruitingPostsForHome(isAuthenticated: false)) ?? []
        let guestSnapshot = GuestHomeSnapshot(
            groups: Array(groups.prefix(4)),
            currentMatch: nil,
            latestLocalResult: session.container.localStore.localMatchRecords.first,
            recruitingPosts: Array(posts.prefix(4))
        )

        if groups.isEmpty && guestSnapshot.latestLocalResult == nil && posts.isEmpty {
            state = .empty("아직 둘러볼 공개 그룹이나 모집글이 없습니다.\n공개 그룹을 확인하거나 실제 내전 흐름을 시작해 보세요.")
        } else {
            state = .content(.guest(guestSnapshot))
        }
        didSucceed = true
    }

    func refresh() async {
        guard let current = state.value else {
            await load(force: true, trigger: "pull_to_refresh")
            return
        }
        state = .refreshing(current)
        await load(force: true, trigger: "pull_to_refresh")
    }

    func reset() {
        state = .initial
        initialLoadTracker.reset()
    }

    private func loadTrackedGroups() async throws -> [GroupSummary] {
        let knownMemberGroupIDs = Set(session.container.localStore.storedGroupIDs)
        var groups: [GroupSummary] = []
        for id in session.container.localStore.storedGroupIDs {
            if session.isDeletedGroupContext(id) {
                session.markGroupContextDeleted(id)
                debugSkipDeletedGroupReload(groupID: id)
                continue
            }
            do {
                let group = try await session.container.groupRepository.detail(groupID: id)
                groups.append(group)
            } catch let error as UserFacingError {
                if error.requiresAuthentication {
                    throw error
                }
                if error.isGroupNotFoundResource {
                    session.markGroupContextDeleted(id)
                    debugSkipDeletedGroupReload(groupID: id)
                }
            }
        }
        return groups.filterAccessible(knownMemberGroupIDs: knownMemberGroupIDs)
    }

    private func loadCurrentMatch() async throws -> Match? {
        guard let context = session.container.localStore.recentMatches.first else { return nil }
        return try await session.container.matchRepository.detail(matchID: context.matchID)
    }

    private func loadRecruitingPostsForHome(isAuthenticated: Bool) async throws -> [RecruitPost] {
        do {
            if isAuthenticated {
                return try await session.container.recruitingRepository.list(status: .open)
            }
            return try await session.container.recruitingRepository.listPublic(status: .open)
        } catch let error as UserFacingError {
            if isAuthenticated, error.requiresAuthentication {
                throw error
            }
            debugHomeLoad(
                "recruiting section failed but screen continues endpoint=\(error.endpoint ?? "nil") status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)"
            )
            return []
        } catch {
            debugHomeLoad("recruiting section failed but screen continues endpoint=unknown status=nil message=\(error.localizedDescription)")
            return []
        }
    }

    private func debugHomeLoad(_ message: String) {
#if DEBUG
        print("[HomeLoad] \(message)")
#endif
    }
}

@MainActor
final class GroupMainViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<[GroupSummary]> = .initial
    @Published var actionState: AsyncActionState = .idle

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "group")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        state = .loading
        if session.isGuest {
            do {
                let groups = try await session.container.groupRepository.listPublic()
                let visibleGroups = groups.filterPubliclyVisible()
                state = visibleGroups.isEmpty
                    ? .empty("공개 그룹이 아직 없습니다.\n나중에 다시 확인하거나 로그인 후 직접 그룹을 만들어 보세요.")
                    : .content(visibleGroups)
                didSucceed = true
            } catch let error as UserFacingError {
                state = .error(error)
            } catch {
                state = .error(UserFacingError(title: "그룹 로딩 실패", message: "공개 그룹 목록을 불러오지 못했습니다."))
            }
            return
        }

        do {
            let knownMemberGroupIDs = Set(session.container.localStore.storedGroupIDs)
            var groups: [GroupSummary] = []
            for id in session.container.localStore.storedGroupIDs {
                if session.isDeletedGroupContext(id) {
                    session.markGroupContextDeleted(id)
                    debugSkipDeletedGroupReload(groupID: id)
                    continue
                }
                do {
                    let group = try await session.container.groupRepository.detail(groupID: id)
                    groups.append(group)
                } catch let error as UserFacingError {
                    if error.requiresAuthentication {
                        throw error
                    }
                    if error.isGroupNotFoundResource {
                        session.markGroupContextDeleted(id)
                        debugSkipDeletedGroupReload(groupID: id)
                    }
                }
            }
            let accessibleGroups = groups.filterAccessible(knownMemberGroupIDs: knownMemberGroupIDs)
            state = accessibleGroups.isEmpty
                ? .empty("추적 중인 그룹이 없습니다.\n그룹을 생성하면 이 탭에서 다시 불러옵니다.")
                : .content(accessibleGroups)
            didSucceed = true
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .groupManagement,
                state: &state,
                fallbackMessage: "로그인 후 그룹 목록을 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "그룹 로딩 실패", message: "그룹 목록을 불러오지 못했습니다."))
        }
    }

    func createGroup(name: String, description: String, tags: [String]) async -> GroupCreationFlowResult {
        actionState = .inProgress("그룹을 생성하는 중입니다")
        debugCreateGroup("request POST /groups")
        do {
            let group = try await session.container.groupRepository.create(
                name: name,
                description: description.isEmpty ? nil : description,
                visibility: .private,
                joinPolicy: .inviteOnly,
                tags: tags
            )
            session.container.localStore.trackGroup(id: group.id, name: group.name)
            session.container.localStore.appendNotification(title: "그룹 생성", body: "\(group.name) 그룹이 생성되었습니다.", symbol: "person.3.fill")
            await load(force: true, trigger: "group_created_refresh")
            actionState = .success("그룹이 생성되었습니다")
            debugCreateGroup("response success groupId=\(group.id)")
            return .success(group)
        } catch let error as UserFacingError {
            debugCreateGroup("response failure: \(error.message)")
            actionState = .idle
            if error.requiresAuthentication {
                session.requireReauthentication(for: .groupManagement)
                return .requiresAuthentication
            }
            return .failure(error.message)
        } catch {
            debugCreateGroup("response failure: 그룹 생성에 실패했습니다")
            actionState = .idle
            return .failure("그룹 생성에 실패했습니다")
        }
    }

    func handleGroupUpdated(_ group: GroupSummary) {
        session.container.localStore.trackGroup(id: group.id, name: group.name)
        guard let groups = state.value else { return }
        let updatedGroups = groups.map { existingGroup in
            existingGroup.id == group.id ? group : existingGroup
        }
        state = .content(updatedGroups)
        actionState = .success("내전 방 정보가 수정되었습니다")
    }

    func handleGroupDeleted(groupID: String) {
        session.markGroupContextDeleted(groupID)
        guard let groups = state.value else {
            actionState = .success("내전 방이 삭제되었습니다")
            return
        }
        let remainingGroups = groups.filter { $0.id != groupID }
        state = remainingGroups.isEmpty
            ? .empty("추적 중인 그룹이 없습니다.\n그룹을 생성하면 이 탭에서 다시 불러옵니다.")
            : .content(remainingGroups)
        actionState = .success("내전 방이 삭제되었습니다")
    }

    func reset() {
        state = .initial
        actionState = .idle
        initialLoadTracker.reset()
    }

    private func debugCreateGroup(_ message: String) {
        #if DEBUG
        print("[CreateGroup] \(message)")
        #endif
    }
}

@MainActor
final class RecruitBoardViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<RecruitBoardSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle
    @Published var selectedType: RecruitingPostType
    @Published private(set) var filterState = RecruitBoardFilterState.defaultValue

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "recruit")
    private var pendingForcedLoadTrigger: RecruitBoardLoadTrigger?
    private var lastLoadedQuery: RecruitPostListQuery?

    init(session: AppSessionViewModel) {
        self.session = session
        self.selectedType = session.container.localStore.recruitFilterType
        debugRecruitScreen(
            "selectedPostType initial value=\(selectedType.rawValue) reason=\(RecruitBoardSelectedTypeChangeReason.initialState.rawValue)"
        )
    }

    func load(force: Bool = false, trigger: RecruitBoardLoadTrigger) async {
        let requestedType = selectedType
        let requestedFilterState = filterState
        let query = buildListQuery(for: requestedType, filters: requestedFilterState)
        if !force, let lastLoadedQuery, lastLoadedQuery == query, state.value != nil {
            debugRecruitScreen("ignored duplicate load trigger=\(trigger.rawValue) currentPostType=\(requestedType.rawValue)")
            return
        }
        debugRecruitScreen(
            "load trigger=\(trigger.rawValue) currentPostType=\(requestedType.rawValue) force=\(force) query=\(debugDescription(for: query))"
        )
        if force, initialLoadTracker.isInFlight {
            pendingForcedLoadTrigger = trigger
            debugRecruitScreen("queuedLoad trigger=\(trigger.rawValue) currentPostType=\(requestedType.rawValue)")
            return
        }
        guard initialLoadTracker.begin(force: force, trigger: trigger.rawValue) else { return }
        var didSucceed = false
        defer {
            initialLoadTracker.finish(success: didSucceed)
            if let pendingForcedLoadTrigger {
                self.pendingForcedLoadTrigger = nil
                Task { await self.load(force: true, trigger: pendingForcedLoadTrigger) }
            }
        }
        if force, let current = state.value {
            state = .refreshing(current)
        } else {
            state = .loading
        }
        do {
            let posts: [RecruitPost]
            if session.isGuest {
                posts = try await session.container.recruitingRepository.listPublic(query: query)
            } else {
                posts = try await session.container.recruitingRepository.list(query: query)
            }
            let groupMetadata = await resolveGroupMetadata(for: posts)
            let filteredPosts = applyClientSideFilters(
                posts,
                query: query,
                groupRegionsByID: groupMetadata.groupRegionsByID
            )
            guard requestedType == selectedType, requestedFilterState == filterState else {
                debugRecruitScreen(
                    "discardLoadResult requestedPostType=\(requestedType.rawValue) currentPostType=\(selectedType.rawValue) trigger=\(trigger.rawValue)"
                )
                return
            }
            let snapshot = RecruitBoardSnapshot(
                selectedType: requestedType,
                filterState: requestedFilterState,
                posts: filteredPosts,
                groupNamesByID: groupMetadata.groupNamesByID,
                groupRegionsByID: groupMetadata.groupRegionsByID
            )
            state = filteredPosts.isEmpty ? .empty("현재 조건에 맞는 모집글이 없습니다.") : .content(snapshot)
            lastLoadedQuery = query
            didSucceed = true
        } catch let error as UserFacingError {
            if session.isAuthenticated {
                session.handleProtectedLoadError(
                    error,
                    requirement: .recruitingWrite,
                    state: &state,
                    fallbackMessage: "로그인 후 모집 목록을 다시 확인할 수 있어요."
                )
            } else {
                state = .error(error)
            }
        } catch {
            state = .error(UserFacingError(title: "모집 로딩 실패", message: "모집 목록을 불러오지 못했습니다."))
        }
    }

    func switchType(_ type: RecruitingPostType) async {
        debugRecruitScreen("segment tap target=\(type.rawValue)")
        guard updateSelectedTypeIfNeeded(type, reason: .userSelection) else { return }
        await load(force: true, trigger: .selectedTypeChanged)
    }

    func applyFilters(_ nextFilterState: RecruitBoardFilterState, reason: RecruitBoardFilterChangeReason) async {
        guard updateFilterStateIfNeeded(nextFilterState, reason: reason) else { return }
        await load(force: true, trigger: .filtersChanged)
    }

    func resolveCreatePostGroupContext() -> String? {
        guard let groupID = session.preferredGroupContextID(), session.hasValidGroupContext(groupID) else {
            handleInvalidCreatePostGroupContext(message: createPostGroupContextErrorMessage())
            return nil
        }
        return groupID
    }

    func validateCreatePostGroupContext(_ groupID: String?) -> String? {
        guard let groupID, session.hasValidGroupContext(groupID) else {
            handleInvalidCreatePostGroupContext(message: createPostGroupContextErrorMessage())
            return nil
        }
        return groupID
    }

    func createPost(groupID: String, title: String, body: String, tags: [String], scheduledAt: Date?, positions: [String]) async -> RecruitPostCreationFlowResult {
        guard session.hasValidGroupContext(groupID) else {
            let message = createPostGroupContextErrorMessage()
            handleInvalidCreatePostGroupContext(message: message)
            return .invalidGroupContext(message)
        }

        actionState = .inProgress("모집글을 등록하는 중입니다")
        debugCreateRecruitingPost("request POST /recruiting-posts groupId=\(groupID)")
        let requestedType = selectedType
        do {
            let post = try await session.container.recruitingRepository.create(
                groupID: groupID,
                type: requestedType,
                title: title,
                body: body.isEmpty ? nil : body,
                tags: tags,
                scheduledAt: scheduledAt,
                requiredPositions: positions
            )
            session.container.localStore.appendNotification(title: "모집글 등록", body: "\(post.title) 글이 등록되었습니다.", symbol: "megaphone.fill")
            actionState = .success("모집글이 등록되었습니다")
            debugCreateRecruitingPost("response success postId=\(post.id) postType=\(post.postType.rawValue)")
            return .success(post)
        } catch let error as UserFacingError {
            debugCreateRecruitingPost("response failure: \(error.message)")
            actionState = .idle
            if error.isGroupNotFoundResource {
                session.markGroupContextDeleted(groupID)
                handleInvalidCreatePostGroupContext(message: error.message)
                return .invalidGroupContext(error.message)
            }
            if error.requiresAuthentication {
                session.requireReauthentication(for: .recruitingWrite)
                return .requiresAuthentication
            }
            return .failure(error.message)
        } catch {
            debugCreateRecruitingPost("response failure: 모집글 등록에 실패했습니다")
            actionState = .idle
            return .failure("모집글 등록에 실패했습니다")
        }
    }

    func handleCreateSuccess(_ post: RecruitPost) {
        debugRecruitScreen("createSuccess postId=\(post.id) postType=\(post.postType.rawValue)")
        _ = updateSelectedTypeIfNeeded(post.postType, reason: .createSuccess)
        guard filterState.isDefault else { return }
        let existingPosts = currentPosts(for: post.postType)
        let mergedPosts = [post] + existingPosts.filter { $0.id != post.id }
        let existingSnapshot = currentSnapshot(for: post.postType)
        var groupNamesByID = existingSnapshot?.groupNamesByID ?? [:]
        if let groupName = session.container.localStore.groupName(for: post.groupID) {
            groupNamesByID[post.groupID] = groupName
        }
        state = .content(
            RecruitBoardSnapshot(
                selectedType: post.postType,
                filterState: filterState,
                posts: mergedPosts,
                groupNamesByID: groupNamesByID,
                groupRegionsByID: existingSnapshot?.groupRegionsByID ?? [:]
            )
        )
    }

    func handleUpdateSuccess(_ post: RecruitPost) {
        debugRecruitScreen("updateSuccess postId=\(post.id) postType=\(post.postType.rawValue)")
        actionState = .success("모집글이 수정되었습니다")

        guard selectedType == post.postType, let snapshot = currentSnapshot(for: selectedType) else { return }
        let updatedPosts = snapshot.posts.map { existingPost in
            existingPost.id == post.id ? post : existingPost
        }
        let updatedSnapshot = RecruitBoardSnapshot(
            selectedType: snapshot.selectedType,
            filterState: snapshot.filterState,
            posts: updatedPosts,
            groupNamesByID: snapshot.groupNamesByID,
            groupRegionsByID: snapshot.groupRegionsByID
        )
        state = updatedPosts.isEmpty ? .empty("현재 조건에 맞는 모집글이 없습니다.") : .content(updatedSnapshot)
        Task { await load(force: true, trigger: .postUpdated) }
    }

    func handleDeleteSuccess(_ post: RecruitPost) {
        debugRecruitScreen("deleteSuccess postId=\(post.id) postType=\(post.postType.rawValue)")
        actionState = .success("모집글이 삭제되었습니다")

        guard selectedType == post.postType, let snapshot = currentSnapshot(for: selectedType) else { return }

        let remainingPosts = snapshot.posts.filter { $0.id != post.id }
        state = remainingPosts.isEmpty
            ? .empty("현재 조건에 맞는 모집글이 없습니다.")
            : .content(
                RecruitBoardSnapshot(
                    selectedType: selectedType,
                    filterState: filterState,
                    posts: remainingPosts,
                    groupNamesByID: snapshot.groupNamesByID,
                    groupRegionsByID: snapshot.groupRegionsByID
                )
            )

        Task { await load(force: true, trigger: .postDeleted) }
    }

    func reset() {
        state = .initial
        actionState = .idle
        syncSelectedTypeFromStoredPreference(reason: .reset)
        filterState = .defaultValue
        initialLoadTracker.reset()
        pendingForcedLoadTrigger = nil
        lastLoadedQuery = nil
    }

    private func debugCreateRecruitingPost(_ message: String) {
        #if DEBUG
        print("[CreateRecruitingPost] \(message)")
        #endif
    }

    private func updateSelectedTypeIfNeeded(
        _ type: RecruitingPostType,
        reason: RecruitBoardSelectedTypeChangeReason,
        persist: Bool = true
    ) -> Bool {
        let oldValue = selectedType
        guard oldValue != type else {
            debugRecruitScreen("ignored duplicate selectedPostType=\(type.rawValue) reason=\(reason.rawValue)")
            return false
        }
        selectedType = type
        if persist {
            session.container.localStore.setRecruitFilterType(type)
        }
        debugRecruitScreen("selectedPostType changed \(oldValue.rawValue) -> \(type.rawValue) reason=\(reason.rawValue)")
        return true
    }

    private func updateFilterStateIfNeeded(
        _ nextFilterState: RecruitBoardFilterState,
        reason: RecruitBoardFilterChangeReason
    ) -> Bool {
        guard filterState != nextFilterState else {
            debugRecruitScreen("ignored duplicate filters reason=\(reason.rawValue) query=\(debugDescription(for: buildListQuery(for: selectedType, filters: nextFilterState)))")
            return false
        }
        filterState = nextFilterState
        let query = buildListQuery(for: selectedType, filters: nextFilterState)
        debugRecruitScreen("filter changed reason=\(reason.rawValue) query=\(debugDescription(for: query))")
        return true
    }

    private func syncSelectedTypeFromStoredPreference(reason: RecruitBoardSelectedTypeChangeReason) {
        let storedType = session.container.localStore.recruitFilterType
        if selectedType == storedType {
            return
        }
        let oldValue = selectedType
        selectedType = storedType
        debugRecruitScreen("selectedPostType changed \(oldValue.rawValue) -> \(storedType.rawValue) reason=\(reason.rawValue)")
    }

    private func currentPosts(for type: RecruitingPostType) -> [RecruitPost] {
        guard let snapshot = currentSnapshot(for: type) else { return [] }
        return snapshot.posts
    }

    private func currentSnapshot(for type: RecruitingPostType) -> RecruitBoardSnapshot? {
        guard let snapshot = state.value, snapshot.selectedType == type else { return nil }
        return snapshot
    }

    private func buildListQuery(for type: RecruitingPostType, filters: RecruitBoardFilterState) -> RecruitPostListQuery {
        let calendar = Calendar.current
        let sortedPositions = filters.selectedPositions.sorted()
        let sortedRegions = filters.selectedRegions.sorted()
        let sortedTags = filters.selectedTags.sorted()
        let dateFilter = filters.selectedDateFilter

        let scheduledFrom: Date?
        let scheduledTo: Date?
        switch dateFilter.preset {
        case .all:
            scheduledFrom = nil
            scheduledTo = nil
        case .today:
            scheduledFrom = calendar.startOfDay(for: Date())
            scheduledTo = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: scheduledFrom!)
        case .thisWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
            scheduledFrom = interval?.start
            scheduledTo = interval?.end.addingTimeInterval(-1)
        case .specificDate:
            let startOfDay = calendar.startOfDay(for: dateFilter.selectedDate)
            scheduledFrom = startOfDay
            scheduledTo = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)
        }

        return RecruitPostListQuery(
            postType: type,
            status: .open,
            scheduledFrom: scheduledFrom,
            scheduledTo: scheduledTo,
            requiredPositions: sortedPositions,
            regions: sortedRegions,
            tags: sortedTags,
            includeUnscheduledPosts: dateFilter.includesUnscheduledPosts
        )
    }

    private func resolveGroupMetadata(for posts: [RecruitPost]) async -> (groupNamesByID: [String: String], groupRegionsByID: [String: String]) {
        let uniqueGroupIDs = Array(Set(posts.map(\.groupID)))
        var groupNamesByID: [String: String] = [:]
        var groupRegionsByID: [String: String] = [:]

        for groupID in uniqueGroupIDs {
            if let cachedGroupName = session.container.localStore.groupName(for: groupID) {
                groupNamesByID[groupID] = cachedGroupName
            }
        }

        guard session.isAuthenticated, !uniqueGroupIDs.isEmpty else {
            return (groupNamesByID, groupRegionsByID)
        }

        if let groups = try? await session.container.groupRepository.details(groupIDs: uniqueGroupIDs) {
            for group in groups {
                groupNamesByID[group.id] = group.name
                if let region = extractRegion(from: group.tags) {
                    groupRegionsByID[group.id] = region
                }
            }
        }

        return (groupNamesByID, groupRegionsByID)
    }

    private func applyClientSideFilters(
        _ posts: [RecruitPost],
        query: RecruitPostListQuery,
        groupRegionsByID: [String: String]
    ) -> [RecruitPost] {
        posts.filter { post in
            if !query.requiredPositions.isEmpty && Set(post.requiredPositions).intersection(query.requiredPositions).isEmpty {
                return false
            }
            if !query.tags.isEmpty && Set(post.tags).intersection(query.tags).isEmpty {
                return false
            }
            if !query.regions.isEmpty {
                guard let region = groupRegionsByID[post.groupID], query.regions.contains(region) else {
                    return false
                }
            }
            if query.scheduledFrom != nil || query.scheduledTo != nil {
                guard let scheduledAt = post.scheduledAt else {
                    return query.includeUnscheduledPosts
                }
                if let scheduledFrom = query.scheduledFrom, scheduledAt < scheduledFrom {
                    return false
                }
                if let scheduledTo = query.scheduledTo, scheduledAt > scheduledTo {
                    return false
                }
            }
            return true
        }
    }

    private func extractRegion(from tags: [String]) -> String? {
        tags.first(where: { RecruitOptionCatalog.regions.contains($0) })
    }

    private func debugDescription(for query: RecruitPostListQuery) -> String {
        let positions = query.requiredPositions.isEmpty ? "-" : query.requiredPositions.joined(separator: ",")
        let regions = query.regions.isEmpty ? "-" : query.regions.joined(separator: ",")
        let tags = query.tags.isEmpty ? "-" : query.tags.joined(separator: ",")
        let scheduledFrom = query.scheduledFrom?.shortDateText ?? "-"
        let scheduledTo = query.scheduledTo?.shortDateText ?? "-"
        return "type=\(query.postType?.rawValue ?? "-") positions=\(positions) regions=\(regions) tags=\(tags) scheduledFrom=\(scheduledFrom) scheduledTo=\(scheduledTo) includeUnscheduled=\(query.includeUnscheduledPosts)"
    }

    private func handleInvalidCreatePostGroupContext(message: String) {
        debugCreateRecruitingPost("blocked because group context is invalid")
        actionState = .failure(message)
    }

    private func createPostGroupContextErrorMessage() -> String {
        session.container.localStore.storedGroupIDs.isEmpty
            ? "모집글을 연결할 그룹이 없습니다. 먼저 그룹을 생성해주세요."
            : "삭제되었거나 존재하지 않는 그룹입니다."
    }

    private func debugRecruitScreen(_ message: String) {
        #if DEBUG
        print("[RecruitScreen] \(message)")
        #endif
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<HistoryContentState> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "history")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        let localItems = session.container.localStore.localMatchRecords

        guard let userID = session.currentUserID else {
            if localItems.isEmpty {
                state = .empty("로컬에 저장된 경기 기록이 없습니다.\n경기 결과를 저장하면 이 탭에서 다시 확인할 수 있어요.")
            } else {
                state = .content(.guest(localItems))
            }
            didSucceed = true
            return
        }

        state = .loading
        do {
            let items = try await session.container.profileRepository.history(userID: userID, limit: 30)
            state = items.isEmpty ? .empty("아직 기록된 내전이 없습니다.") : .content(.authenticated(items))
            didSucceed = true
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .profileHistory,
                state: &state,
                fallbackMessage: "로그인 후 기록을 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "기록 로딩 실패", message: "경기 기록을 불러오지 못했습니다."))
        }
    }

    func reset() {
        state = .initial
        initialLoadTracker.reset()
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<ProfileContentState> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "profile")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        guard let userID = session.currentUserID else {
            let guestSnapshot = GuestProfileSnapshot(
                localResults: session.container.localStore.localMatchRecords,
                trackedGroupCount: session.container.localStore.storedGroupIDs.count,
                notificationCount: session.container.localStore.notifications.count
            )
            state = .content(.guest(guestSnapshot))
            didSucceed = true
            return
        }

        state = .loading

        do {
            let profile: UserProfile
            if !force, let existingProfile = session.profile {
                profile = existingProfile
                initialLoadTracker.logSessionReused(trigger: trigger)
            } else {
                profile = try await session.container.profileRepository.me()
                session.updateAuthenticatedProfile(profile)
            }
            let riotAccountsViewState = await session.refreshRiotAccountsViewState(force: force)
            if case let .error(error) = riotAccountsViewState, error.requiresAuthentication {
                throw error
            }

            let power: PowerProfile?
            let history: [MatchHistoryItem]
            if riotAccountsViewState.hasLinkedAccounts {
                power = try? await session.container.profileRepository.powerProfile(userID: userID)
                history = (try? await session.container.profileRepository.history(userID: userID, limit: 10)) ?? []
            } else {
                power = nil
                history = []
            }

            state = .content(
                .authenticated(
                    ProfileSnapshot(
                        profile: profile,
                        riotAccountsViewState: riotAccountsViewState,
                        power: power,
                        history: history
                    )
                )
            )
            didSucceed = true
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .settings,
                state: &state,
                fallbackMessage: "로그인 후 프로필을 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "프로필 로딩 실패", message: "프로필을 불러오지 못했습니다."))
        }
    }

    func reset() {
        state = .initial
        initialLoadTracker.reset()
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case searching
        case results(SearchResponse)
        case empty(String)
        case error(UserFacingError)
    }

    @Published private(set) var state: ViewState = .idle
    @Published private(set) var recentSearchKeywords: [RecentSearchKeyword] = []

    private let session: AppSessionViewModel
    private var searchTask: Task<Void, Never>?

    init(session: AppSessionViewModel) {
        self.session = session
        self.recentSearchKeywords = session.container.localStore.recentSearchKeywords
    }

    func refreshRecentSearchKeywords() {
        recentSearchKeywords = session.container.localStore.recentSearchKeywords
    }

    func updateQuery(_ rawQuery: String) {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !trimmedQuery.isEmpty else {
            state = .idle
            refreshRecentSearchKeywords()
            return
        }

        state = .searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmedQuery, forceRefresh: false)
        }
    }

    func submitSearch(_ rawQuery: String) {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            state = .idle
            return
        }

        recordRecentSearchKeyword(trimmedQuery)
        searchTask?.cancel()
        searchTask = Task {
            await performSearch(trimmedQuery, forceRefresh: true)
        }
    }

    func deleteRecentSearchKeyword(id: String) {
        session.container.localStore.deleteRecentSearchKeyword(id: id)
        refreshRecentSearchKeywords()
    }

    func clearRecentSearchKeywords() {
        session.container.localStore.clearRecentSearchKeywords()
        refreshRecentSearchKeywords()
    }

    func recordRecentSearchKeyword(_ keyword: String) {
        session.container.localStore.recordRecentSearchKeyword(keyword)
        refreshRecentSearchKeywords()
    }

    func cancelPendingSearch() {
        searchTask?.cancel()
    }

    private func performSearch(_ query: String, forceRefresh: Bool) async {
        let linkedRiotAccounts: [RiotAccount]
        if session.isAuthenticated {
            let riotAccountsViewState = await session.refreshRiotAccountsViewState(force: forceRefresh)
            switch riotAccountsViewState {
            case let .loaded(accounts):
                linkedRiotAccounts = accounts
            default:
                linkedRiotAccounts = []
            }
        } else {
            linkedRiotAccounts = []
        }

        let response = await session.container.searchUseCase.execute(
            query: query,
            linkedRiotAccounts: linkedRiotAccounts,
            forceRefresh: forceRefresh
        )

        guard !Task.isCancelled else { return }

        if response.isEmpty {
            state = .empty("검색 결과가 없습니다")
        } else {
            state = .results(response)
        }
    }
}

fileprivate enum PowerAccentTone: Hashable {
    case blue
    case green
    case gold
    case purple
    case orange
    case red
    case muted

    var color: Color {
        switch self {
        case .blue:
            return AppPalette.accentBlue
        case .green:
            return AppPalette.accentGreen
        case .gold:
            return AppPalette.accentGold
        case .purple:
            return AppPalette.accentPurple
        case .orange:
            return AppPalette.accentOrange
        case .red:
            return AppPalette.accentRed
        case .muted:
            return AppPalette.textMuted
        }
    }

    var badgeBackground: Color {
        switch self {
        case .green:
            return Color(hex: 0x162D1F)
        case .red:
            return Color(hex: 0x2D1A1A)
        case .blue:
            return Color(hex: 0x162035)
        case .gold:
            return Color(hex: 0x2B2111)
        case .purple:
            return Color(hex: 0x241B35)
        case .orange:
            return Color(hex: 0x2E2114)
        case .muted:
            return AppPalette.bgTertiary
        }
    }
}

fileprivate enum PowerDeltaDirection: Hashable {
    case up
    case down
    case neutral
}

fileprivate struct PowerDeltaViewState: Hashable {
    let text: String
    let direction: PowerDeltaDirection
    let tone: PowerAccentTone

    var symbolName: String? {
        switch direction {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .neutral:
            return nil
        }
    }
}

fileprivate struct PowerComponentRowViewState: Hashable, Identifiable {
    let id: String
    let title: String
    let shortMetricLabel: String
    let scoreText: String
    let description: String
    let progress: Double
    let tone: PowerAccentTone
    let delta: PowerDeltaViewState?
}

fileprivate struct PowerTimelineItemViewState: Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let metricText: String
    let tone: PowerAccentTone
}

fileprivate struct PowerTipItemViewState: Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let symbolName: String
    let tone: PowerAccentTone
}

fileprivate struct PowerFAQItemViewState: Hashable, Identifiable {
    let id: String
    let question: String
}

fileprivate struct PowerCalculationFactorViewState: Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let tone: PowerAccentTone
}

fileprivate struct PowerCalculationSheetViewState: Hashable {
    let title: String
    let summaryText: String
    let highlightText: String
    let factors: [PowerCalculationFactorViewState]
    let noteTitle: String
    let notes: [String]
}

fileprivate struct PowerOverviewViewState: Hashable {
    let scoreText: String
    let scoreLabel: String
    let tierText: String?
    let change: PowerDeltaViewState?
    let changeCaptionText: String?
    let percentileText: String?
    let supportingText: String
    let insightText: String
    let components: [PowerComponentRowViewState]
    let isPlaceholder: Bool
}

fileprivate struct HomePowerCardViewState: Hashable {
    let overview: PowerOverviewViewState
}

fileprivate struct PowerDetailViewState: Hashable {
    let overview: PowerOverviewViewState
    let timeline: [PowerTimelineItemViewState]
    let tips: [PowerTipItemViewState]
    let faqs: [PowerFAQItemViewState]
    let calculationSheet: PowerCalculationSheetViewState
}

fileprivate enum GroupMemberPowerSource: Hashable {
    case snapshot
    case liveFallback
    case unavailable
}

fileprivate struct GroupMemberPowerRowViewState: Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let powerText: String
    let powerLabel: String
    let source: GroupMemberPowerSource
}

fileprivate struct GroupPowerGuideViewState: Hashable {
    let title: String
    let message: String
}

fileprivate enum PowerViewStateBuilder {
    static func home(power: PowerProfile?, hasLinkedRiotAccount: Bool) -> HomePowerCardViewState {
        HomePowerCardViewState(
            overview: overview(
                power: power,
                history: [],
                hasLinkedRiotAccount: hasLinkedRiotAccount,
                showsTier: false
            )
        )
    }

    static func detail(power: PowerProfile?, history: [MatchHistoryItem], hasLinkedRiotAccount: Bool) -> PowerDetailViewState {
        let overview = overview(
            power: power,
            history: history,
            hasLinkedRiotAccount: hasLinkedRiotAccount,
            showsTier: true
        )

        return PowerDetailViewState(
            overview: overview,
            timeline: timeline(power: power, history: history, components: overview.components),
            tips: tips(power: power, history: history),
            faqs: [
                PowerFAQItemViewState(id: "game-change", question: "왜 한 경기로 점수가 많이 안 변하나요?"),
                PowerFAQItemViewState(id: "group-diff", question: "그룹 파워와 홈 파워가 다른 이유는?"),
                PowerFAQItemViewState(id: "mmr", question: "내전 MMR은 어떻게 결정되나요?"),
            ],
            calculationSheet: calculationSheet()
        )
    }

    static func groupGuide() -> GroupPowerGuideViewState {
        GroupPowerGuideViewState(
            title: "그룹 파워 vs 홈 파워",
            message: "그룹 화면에서는 마지막 내전 기준 스냅샷을 우선 보여주고, 스냅샷이 없으면 최신 종합 파워를 대신 보여줘요. 최신 종합 파워는 프로필에서 확인할 수 있어요."
        )
    }

    static func groupMember(member: GroupMember, powerProfile: PowerProfile?) -> GroupMemberPowerRowViewState {
        // TODO: Replace this latest-profile fallback with group-scoped snapshot power when the
        // group members API exposes fields such as snapshotPower, snapshotTimestamp, and
        // preferredPositions. The current response only gives us the member identity + role.
        let source: GroupMemberPowerSource = powerProfile == nil ? .unavailable : .liveFallback
        let powerText = powerProfile.map { String(Int($0.overallPower.rounded())) } ?? "--"
        let powerLabel: String
        switch source {
        case .snapshot:
            powerLabel = "스냅샷"
        case .liveFallback:
            powerLabel = "최신"
        case .unavailable:
            powerLabel = "대기"
        }

        let roleText: String
        switch member.role {
        case .owner:
            roleText = "방장"
        case .admin:
            roleText = "운영진"
        case .member:
            roleText = "멤버"
        }

        let subtitle: String
        switch source {
        case .snapshot:
            subtitle = "\(roleText) · 파워 \(powerText)"
        case .liveFallback:
            subtitle = "\(roleText) · 최신 파워 \(powerText)"
        case .unavailable:
            subtitle = "\(roleText) · 파워 정보 없음"
        }

        return GroupMemberPowerRowViewState(
            id: member.id,
            name: member.nickname,
            subtitle: subtitle,
            powerText: powerText,
            powerLabel: powerLabel,
            source: source
        )
    }

    private static func overview(
        power: PowerProfile?,
        history: [MatchHistoryItem],
        hasLinkedRiotAccount: Bool,
        showsTier: Bool
    ) -> PowerOverviewViewState {
        guard let power else {
            return PowerOverviewViewState(
                scoreText: "--",
                scoreLabel: "종합 파워",
                tierText: nil,
                change: nil,
                changeCaptionText: nil,
                percentileText: nil,
                supportingText: hasLinkedRiotAccount
                    ? "최근 경기와 결과 입력이 쌓이면 파워가 계산돼요"
                    : "Riot ID를 추가하면 파워 프로필을 확인할 수 있어요",
                insightText: hasLinkedRiotAccount
                    ? "파워를 계산할 데이터가 아직 충분하지 않아요"
                    : "추가한 Riot ID가 없어요",
                components: placeholderComponents(),
                isPlaceholder: true
            )
        }

        let overallScore = Int(power.overallPower.rounded())
        let totalDelta = Int((power.overallPower - power.basePower).rounded())
        let percentile = estimatedPercentile(from: power)
        let components = componentRows(power: power, history: history, totalDelta: totalDelta, percentile: percentile)

        return PowerOverviewViewState(
            scoreText: String(overallScore),
            scoreLabel: "종합 파워",
            tierText: showsTier ? tierText(for: overallScore) : nil,
            change: deltaState(from: totalDelta, tone: totalDelta >= 0 ? .green : .red),
            changeCaptionText: totalDelta == 0 ? nil : "지난 주 대비",
            percentileText: "상위 \(percentile)%",
            supportingText: hasLinkedRiotAccount
                ? "최근 10경기 기준 · Riot 참고 데이터 반영"
                : "최근 10경기 기준 · 내전 기록 기반 추정",
            insightText: insightText(power: power),
            components: components,
            isPlaceholder: false
        )
    }

    private static func placeholderComponents() -> [PowerComponentRowViewState] {
        [
            PowerComponentRowViewState(
                id: "form",
                title: "최근 폼",
                shortMetricLabel: "폼",
                scoreText: "--",
                description: "최근 경기 데이터가 쌓이면 자동으로 계산돼요",
                progress: 0.28,
                tone: .blue,
                delta: nil
            ),
            PowerComponentRowViewState(
                id: "stability",
                title: "안정성",
                shortMetricLabel: "안정",
                scoreText: "--",
                description: "포지션 편차와 경기 편차가 충분히 쌓이면 반영돼요",
                progress: 0.34,
                tone: .green,
                delta: nil
            ),
            PowerComponentRowViewState(
                id: "carry",
                title: "캐리 기여",
                shortMetricLabel: "캐리",
                scoreText: "--",
                description: "핵심 교전과 딜 기여 데이터가 반영될 예정이에요",
                progress: 0.30,
                tone: .gold,
                delta: nil
            ),
            PowerComponentRowViewState(
                id: "team",
                title: "팀 기여도",
                shortMetricLabel: "팀",
                scoreText: "--",
                description: "오브젝트와 팀 시너지가 충분히 쌓이면 반영돼요",
                progress: 0.32,
                tone: .purple,
                delta: nil
            ),
            PowerComponentRowViewState(
                id: "mmr",
                title: "내전 MMR",
                shortMetricLabel: "MMR",
                scoreText: "--",
                description: "내전 결과와 Riot 참고 데이터가 반영되면 계산돼요",
                progress: 0.26,
                tone: .orange,
                delta: nil
            ),
        ]
    }

    private static func componentRows(
        power: PowerProfile,
        history: [MatchHistoryItem],
        totalDelta: Int,
        percentile: Int
    ) -> [PowerComponentRowViewState] {
        let streak = resultStreak(from: history)
        let formDelta = clampedDelta(Int((Double(totalDelta) * 0.67).rounded()))
        let stabilityDelta = power.stability >= 80 ? 1 : (power.stability < 55 ? -1 : 0)
        let carryDelta = power.carry <= power.overallPower - 6 ? -1 : (power.carry >= power.overallPower + 8 ? 1 : 0)
        let teamDelta = power.teamContribution >= power.overallPower + 4 ? 1 : (power.teamContribution <= power.overallPower - 5 ? -1 : 0)

        let formDescription: String
        if streak.count >= 2, streak.result == "WIN" {
            formDescription = "최근 \(streak.count)경기 연속 승리로 상승 중"
        } else if streak.count >= 2, streak.result == "LOSE" {
            formDescription = "최근 경기 결과가 반영되며 조정 중"
        } else {
            formDescription = "최근 경기 결과가 폼에 반영되고 있어요"
        }

        let stabilityDescription = power.stability >= 80
            ? "포지션 편차가 적어 안정적이에요"
            : "경기별 편차가 있어 조금 더 데이터가 필요해요"
        let carryDescription = carryDelta < 0
            ? "최근 캐리력이 약간 하락했어요"
            : "핵심 교전 기여가 반영되고 있어요"
        let teamDescription = teamDelta > 0
            ? "팀원과의 시너지가 높아요"
            : "오브젝트와 팀 플레이 기여가 반영돼요"
        let mmrDescription = "상위 \(max(5, percentile - 3))% 수준의 내전 실력이에요"

        return [
            PowerComponentRowViewState(
                id: "form",
                title: "최근 폼",
                shortMetricLabel: "폼",
                scoreText: String(Int(power.formScore.rounded())),
                description: formDescription,
                progress: normalizedScore(power.formScore),
                tone: .blue,
                delta: deltaState(from: formDelta, tone: formDelta >= 0 ? .green : .red)
            ),
            PowerComponentRowViewState(
                id: "stability",
                title: "안정성",
                shortMetricLabel: "안정",
                scoreText: String(Int(power.stability.rounded())),
                description: stabilityDescription,
                progress: normalizedScore(power.stability),
                tone: .green,
                delta: deltaState(from: stabilityDelta, tone: stabilityDelta >= 0 ? .green : .red)
            ),
            PowerComponentRowViewState(
                id: "carry",
                title: "캐리 기여",
                shortMetricLabel: "캐리",
                scoreText: String(Int(power.carry.rounded())),
                description: carryDescription,
                progress: normalizedScore(power.carry),
                tone: .gold,
                delta: deltaState(from: carryDelta, tone: carryDelta >= 0 ? .green : .red)
            ),
            PowerComponentRowViewState(
                id: "team",
                title: "팀 기여도",
                shortMetricLabel: "팀",
                scoreText: String(Int(power.teamContribution.rounded())),
                description: teamDescription,
                progress: normalizedScore(power.teamContribution),
                tone: .purple,
                delta: deltaState(from: teamDelta, tone: teamDelta >= 0 ? .green : .red)
            ),
            PowerComponentRowViewState(
                id: "mmr",
                title: "내전 MMR",
                shortMetricLabel: "MMR",
                scoreText: NumberFormatter.powerMMR.string(from: NSNumber(value: Int(power.inhouseMMR.rounded()))) ?? String(Int(power.inhouseMMR.rounded())),
                description: mmrDescription,
                progress: normalizedMMR(power.inhouseMMR),
                tone: .orange,
                delta: nil
            ),
        ]
    }

    private static func timeline(
        power: PowerProfile?,
        history: [MatchHistoryItem],
        components: [PowerComponentRowViewState]
    ) -> [PowerTimelineItemViewState] {
        guard power != nil else {
            return [
                PowerTimelineItemViewState(
                    id: "placeholder",
                    title: "최근 반영 내역을 준비 중이에요",
                    description: "경기 결과가 쌓이면 변화 로그가 여기에 표시돼요",
                    metricText: "대기",
                    tone: .muted
                ),
            ]
        }

        let items = Array(history.prefix(3))
        let formMetric = timelineMetric(for: components, id: "form", fallback: "+1")
        let stabilityMetric = timelineMetric(for: components, id: "stability", fallback: "+1")
        let carryMetric = timelineMetric(for: components, id: "carry", fallback: "-1")

        if items.isEmpty {
            return [
                PowerTimelineItemViewState(
                    id: "no-history",
                    title: "최근 반영 내역이 아직 없어요",
                    description: "경기 결과를 입력하면 파워 변화 로그가 쌓여요",
                    metricText: "대기",
                    tone: .muted
                ),
            ]
        }

        return items.enumerated().map { index, item in
            switch index {
            case 0:
                return PowerTimelineItemViewState(
                    id: item.id,
                    title: "\(item.scheduledAt.powerTimelineDateText) 경기 결과 반영",
                    description: item.result == "WIN" ? "최근 승리 흐름이 폼에 반영됐어요" : "최근 경기 결과가 폼 지표에 반영됐어요",
                    metricText: "폼 \(formMetric)",
                    tone: .green
                )
            case 1:
                return PowerTimelineItemViewState(
                    id: item.id,
                    title: "\(item.scheduledAt.powerTimelineDateText) 안정성 업데이트",
                    description: "포지션 일관성과 경기 편차가 함께 조정됐어요",
                    metricText: "안정 \(stabilityMetric)",
                    tone: .blue
                )
            default:
                return PowerTimelineItemViewState(
                    id: item.id,
                    title: "\(item.scheduledAt.powerTimelineDateText) 결과 입력 반영",
                    description: item.result == "WIN" ? "최근 기여도가 다시 반영됐어요" : "팀 내 기여 비중이 조정됐어요",
                    metricText: "캐리 \(carryMetric)",
                    tone: carryMetric.hasPrefix("-") ? .red : .gold
                )
            }
        }
    }

    private static func tips(power: PowerProfile?, history: [MatchHistoryItem]) -> [PowerTipItemViewState] {
        var tips: [PowerTipItemViewState] = []

        if history.count < 10 {
            tips.append(
                PowerTipItemViewState(
                    id: "results",
                    title: "결과 입력을 꾸준히 쌓으세요",
                    description: "경기 데이터가 쌓일수록 정확도와 신뢰도가 높아져요",
                    symbolName: "target",
                    tone: .blue
                )
            )
        }

        if (power?.formScore ?? 0) < 75 {
            tips.append(
                PowerTipItemViewState(
                    id: "form",
                    title: "최근 승률과 기여도를 개선하세요",
                    description: "최근 경기 승률이 오르면 '최근 폼' 점수가 상승해요",
                    symbolName: "chart.line.uptrend.xyaxis",
                    tone: .green
                )
            )
        }

        if (power?.stability ?? 0) < 80 {
            tips.append(
                PowerTipItemViewState(
                    id: "stability",
                    title: "포지션 편차를 줄이세요",
                    description: "같은 포지션을 자주 플레이하면 안정성 점수가 올라가요",
                    symbolName: "shield",
                    tone: .purple
                )
            )
        }

        let defaults = [
            PowerTipItemViewState(
                id: "results",
                title: "결과 입력을 꾸준히 쌓으세요",
                description: "경기 데이터가 쌓일수록 정확도와 신뢰도가 높아져요",
                symbolName: "target",
                tone: .blue
            ),
            PowerTipItemViewState(
                id: "form",
                title: "최근 승률과 기여도를 개선하세요",
                description: "최근 경기 승률이 오르면 '최근 폼' 점수가 상승해요",
                symbolName: "chart.line.uptrend.xyaxis",
                tone: .green
            ),
            PowerTipItemViewState(
                id: "stability",
                title: "포지션 편차를 줄이세요",
                description: "같은 포지션을 자주 플레이하면 안정성 점수가 올라가요",
                symbolName: "shield",
                tone: .purple
            ),
        ]

        for item in defaults where tips.count < 3 && tips.contains(where: { $0.id == item.id }) == false {
            tips.append(item)
        }

        return Array(tips.prefix(3))
    }

    static func calculationSheet() -> PowerCalculationSheetViewState {
        PowerCalculationSheetViewState(
            title: "파워는 어떻게 계산되나요?",
            summaryText: "파워는 여러 경기 데이터를 종합적으로 분석해서 계산돼요. 한 경기 결과만으로 크게 바뀌지 않아요.",
            highlightText: "최근 경기, 꾸준함, 팀 기여, 내전 MMR 등을 함께 반영해요.",
            factors: [
                PowerCalculationFactorViewState(
                    id: "form",
                    title: "최근 폼",
                    description: "최근 경기에서의 승률과 활약도를 반영해요. 최근 결과일수록 더 큰 비중을 가져요.",
                    tone: .blue
                ),
                PowerCalculationFactorViewState(
                    id: "stability",
                    title: "안정성",
                    description: "경기마다 퍼포먼스가 얼마나 일관적인지 평가해요. 편차가 적으면 높은 점수를 받아요.",
                    tone: .green
                ),
                PowerCalculationFactorViewState(
                    id: "carry",
                    title: "캐리 기여",
                    description: "팀 내 딜 비중, 핵심 교전 기여도 등 개인 캐리력을 반영해요.",
                    tone: .gold
                ),
                PowerCalculationFactorViewState(
                    id: "team",
                    title: "팀 기여도",
                    description: "비전 점수, 오브젝트 참여, 팀원과의 시너지를 종합해요.",
                    tone: .purple
                ),
                PowerCalculationFactorViewState(
                    id: "mmr",
                    title: "내전 MMR",
                    description: "내전 매칭 결과를 기반으로 산출되는 실력 지표예요. Riot 참고 데이터도 함께 반영돼요.",
                    tone: .orange
                ),
            ],
            noteTitle: "알아두세요",
            notes: [
                "파워는 충분한 경기 데이터가 쌓여야 정확해져요. 경기 수가 적으면 신뢰도가 낮을 수 있어요.",
                "그룹 화면에 표시되는 파워는 마지막 참여 시점의 스냅샷이에요. 최신 파워는 홈 프로필에서 확인하세요.",
            ]
        )
    }

    private static func insightText(power: PowerProfile) -> String {
        if power.teamContribution > power.formScore + 5 {
            return "팀 기여도는 높지만 최근 폼이 약간 내려갔어요"
        }
        if power.formScore >= 78, power.teamContribution >= 78 {
            return "최근 폼과 팀 기여가 함께 올라가고 있어요"
        }
        if power.stability < 65 {
            return "포지션과 경기 편차를 줄이면 파워가 더 안정적으로 올라가요"
        }
        return "최근 경기, 팀 기여, 내전 MMR이 종합적으로 반영되고 있어요"
    }

    private static func tierText(for score: Int) -> String {
        switch score {
        case 85...:
            return "최상급"
        case 70...84:
            return "고급"
        case 55...69:
            return "중급"
        default:
            return "성장중"
        }
    }

    private static func normalizedScore(_ score: Double) -> Double {
        min(max(score / 100, 0.12), 1)
    }

    private static func normalizedMMR(_ mmr: Double) -> Double {
        min(max((mmr - 800) / 900, 0.18), 1)
    }

    private static func deltaState(from delta: Int, tone: PowerAccentTone) -> PowerDeltaViewState? {
        guard delta != 0 else { return nil }
        return PowerDeltaViewState(
            text: delta > 0 ? "+\(delta)" : "\(delta)",
            direction: delta > 0 ? .up : .down,
            tone: tone
        )
    }

    private static func timelineMetric(
        for components: [PowerComponentRowViewState],
        id: String,
        fallback: String
    ) -> String {
        components.first(where: { $0.id == id })?.delta?.text ?? fallback
    }

    private static func resultStreak(from history: [MatchHistoryItem]) -> (count: Int, result: String) {
        guard let first = history.first else { return (0, "") }
        let streak = history.prefix { $0.result == first.result }.count
        return (streak, first.result)
    }

    private static func clampedDelta(_ delta: Int) -> Int {
        max(-3, min(3, delta))
    }

    private static func estimatedPercentile(from power: PowerProfile) -> Int {
        max(1, 100 - Int((power.overallPower * 1.08).rounded()))
    }
}

private extension NumberFormatter {
    static let powerMMR: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

private extension Date {
    var powerTimelineDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter.string(from: self)
    }
}

@MainActor
// Power detail view state types are file-local, so the view model must stay file-local too.
fileprivate final class PowerDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<PowerDetailViewState> = .initial

    private let session: AppSessionViewModel
    private let targetUserID: String?
    private let displayName: String
    private let initialLoadTracker: InitialLoadTracker

    init(
        session: AppSessionViewModel,
        targetUserID: String? = nil,
        displayName: String? = nil
    ) {
        self.session = session
        self.targetUserID = targetUserID
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = normalizedDisplayName.isEmpty ? "멤버 프로필" : normalizedDisplayName
        self.initialLoadTracker = InitialLoadTracker(screen: targetUserID == nil ? "power_detail" : "member_profile")
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }

        let isCurrentUser = targetUserID == nil || targetUserID == session.currentUserID
        let resolvedUserID = targetUserID ?? session.currentUserID

        guard let userID = resolvedUserID else {
            state = .empty("로그인 후 \(displayName)을 확인할 수 있어요.")
            didSucceed = true
            return
        }

        state = .loading

        if !isCurrentUser {
            #if DEBUG
            print("[RouteFetch] fetch started screen=member_profile userID=\(userID)")
            #endif
            let power = try? await session.container.profileRepository.powerProfile(userID: userID)
            let history = (try? await session.container.profileRepository.history(userID: userID, limit: 10)) ?? []
            if power == nil && history.isEmpty {
                state = .empty("\(displayName)의 공개 프로필 데이터가 아직 없습니다.")
            } else {
                state = .content(
                    PowerViewStateBuilder.detail(
                        power: power,
                        history: history,
                        hasLinkedRiotAccount: power != nil || !history.isEmpty
                    )
                )
            }
            #if DEBUG
            print("[RouteFetch] fetch success screen=member_profile userID=\(userID) historyCount=\(history.count) hasPower=\(power != nil)")
            #endif
            didSucceed = true
            return
        }

        let riotAccountsViewState = await session.refreshRiotAccountsViewState(force: force)
        if case let .error(error) = riotAccountsViewState, error.requiresAuthentication {
            session.handleProtectedLoadError(
                error,
                requirement: .riotAccount,
                state: &state,
                fallbackMessage: "로그인 후 파워 상세를 다시 확인할 수 있어요."
            )
            return
        }

        guard riotAccountsViewState.hasLinkedAccounts else {
            state = .empty("Riot ID를 추가하면 내전 전적과 파워 프로필을 확인할 수 있어요.")
            didSucceed = true
            return
        }

        let power = try? await session.container.profileRepository.powerProfile(userID: userID)
        let history = (try? await session.container.profileRepository.history(userID: userID, limit: 10)) ?? []

        state = .content(
            PowerViewStateBuilder.detail(
                power: power,
                history: history,
                hasLinkedRiotAccount: true
            )
        )
        didSucceed = true
    }

    func refresh() async {
        guard let current = state.value else {
            await load(force: true, trigger: "pull_to_refresh")
            return
        }
        state = .refreshing(current)
        await load(force: true, trigger: "pull_to_refresh")
    }

    func reset() {
        state = .initial
        initialLoadTracker.reset()
    }
}

struct HomeUpcomingMatchItem: Hashable, Identifiable {
    let match: Match
    let groupName: String

    var id: String { match.id }
}

@MainActor
fileprivate final class HomeUpcomingMatchesViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<[HomeUpcomingMatchItem]> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "home_upcoming_matches")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        state = .loading

        let contexts = session.container.localStore.recentMatches
        guard !contexts.isEmpty else {
            state = .empty("추적 중인 예정된 내전이 없습니다.")
            didSucceed = true
            return
        }

        var items: [HomeUpcomingMatchItem] = []
        for context in contexts {
            guard let match = try? await session.container.matchRepository.detail(matchID: context.matchID) else { continue }
            if [.confirmed, .disputed, .closed].contains(match.status) {
                continue
            }
            items.append(HomeUpcomingMatchItem(match: match, groupName: context.groupName))
        }

        items.sort { lhs, rhs in
            let leftDate = lhs.match.scheduledAt ?? .distantFuture
            let rightDate = rhs.match.scheduledAt ?? .distantFuture
            if leftDate == rightDate {
                return lhs.groupName < rhs.groupName
            }
            return leftDate < rightDate
        }

        state = items.isEmpty
            ? .empty("예정된 내전으로 표시할 항목이 없습니다.")
            : .content(items)
        didSucceed = true
    }
}

@MainActor
fileprivate final class HomeGroupsViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<[GroupSummary]> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "home_groups")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        state = .loading

        do {
            let groups: [GroupSummary]
            if session.isGuest {
                groups = (try await session.container.groupRepository.listPublic()).filterPubliclyVisible()
            } else {
                let trackedIDs = session.container.localStore.storedGroupIDs
                var loadedGroups: [GroupSummary] = []
                for id in trackedIDs {
                    if session.isDeletedGroupContext(id) {
                        session.markGroupContextDeleted(id)
                        debugSkipDeletedGroupReload(groupID: id)
                        continue
                    }
                    do {
                        let group = try await session.container.groupRepository.detail(groupID: id)
                        loadedGroups.append(group)
                    } catch let error as UserFacingError {
                        if error.requiresAuthentication {
                            throw error
                        }
                        if error.isGroupNotFoundResource {
                            session.markGroupContextDeleted(id)
                            debugSkipDeletedGroupReload(groupID: id)
                        }
                    }
                }
                groups = loadedGroups.filterAccessible(knownMemberGroupIDs: Set(trackedIDs))
            }

            state = groups.isEmpty
                ? .empty(session.isGuest ? "표시할 공개 그룹이 없습니다." : "참여 중인 그룹이 없습니다.")
                : .content(groups)
            didSucceed = true
        } catch let error as UserFacingError {
            if session.isAuthenticated {
                session.handleProtectedLoadError(
                    error,
                    requirement: .groupManagement,
                    state: &state,
                    fallbackMessage: "로그인 후 그룹 목록을 다시 확인할 수 있어요."
                )
            } else {
                state = .error(error)
            }
        } catch {
            state = .error(UserFacingError(title: "그룹 목록 로딩 실패", message: "그룹 목록을 불러오지 못했습니다."))
        }
    }
}

@MainActor
fileprivate final class HomeRecentMatchesViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<[MatchHistoryItem]> = .initial

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "home_recent_matches")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        guard let userID = session.currentUserID else {
            state = .empty("로그인 후 최근 경기 전체 목록을 확인할 수 있어요.")
            didSucceed = true
            return
        }

        state = .loading
        do {
            let items = try await session.container.profileRepository.history(userID: userID, limit: 30)
            state = items.isEmpty ? .empty("최근 경기 기록이 없습니다.") : .content(items)
            didSucceed = true
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .profileHistory,
                state: &state,
                fallbackMessage: "로그인 후 최근 경기 전체 목록을 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "최근 경기 로딩 실패", message: "최근 경기 목록을 불러오지 못했습니다."))
        }
    }
}

// MARK: - Restored Shell View Models

enum GroupDetailLoadTrigger: String {
    case screenAppear = "screen_appear"
    case retry = "retry"
    case memberInvited = "member_invited"
    case groupUpdated = "group_updated"
}

private enum GroupDetailMutationErrorType: String {
    case authRequired = "auth_required"
    case forbidden = "forbidden"
    case notFound = "not_found"
    case conflict = "conflict"
    case server = "server"
    case other = "other"
}

@MainActor
final class GroupDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<GroupDetailSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle

    private let session: AppSessionViewModel
    private var activeLoadToken = 0
    private var isGroupContextActive = true
    let groupID: String

    var isEditVisible: Bool {
        guard let snapshot = state.value else { return false }
        return canManage(snapshot)
    }

    var isDeleteVisible: Bool {
        isEditVisible
    }

    var isMutationInFlight: Bool {
        if case .inProgress = actionState {
            return true
        }
        return false
    }

    init(session: AppSessionViewModel, groupID: String) {
        self.session = session
        self.groupID = groupID
    }

    func load(force: Bool = false, trigger: GroupDetailLoadTrigger = .screenAppear) async {
        guard canUseGroupContextForRequests(trigger: trigger) else { return }
        if !force, case .content = state { return }
        let loadToken = beginLoad()
        debugGroupDetail("load trigger=\(trigger.rawValue) groupId=\(groupID)")
        #if DEBUG
        print("[RouteFetch] fetch started screen=group_detail groupID=\(groupID)")
        #endif
        if force, let current = state.value {
            state = .refreshing(current)
        } else {
            state = .loading
        }
        do {
            let group = try await session.container.groupRepository.detail(groupID: groupID)
            guard isCurrentLoad(loadToken) else { return }
            let members = try await session.container.groupRepository.members(groupID: groupID)
            guard isCurrentLoad(loadToken) else { return }
            let latestHistory: [MatchHistoryItem]?
            if let userID = session.currentUserID {
                latestHistory = try? await session.container.profileRepository.history(
                    userID: userID,
                    groupID: groupID,
                    limit: 1
                )
            } else {
                latestHistory = nil
            }
            guard isCurrentLoad(loadToken) else { return }
            let powerProfiles = await loadPowerProfiles(for: members.map(\.userID))
            guard isCurrentLoad(loadToken) else { return }
            let snapshot = GroupDetailSnapshot(
                group: group,
                members: members,
                latestMatch: latestHistory?.first,
                powerProfiles: powerProfiles
            )
            state = .content(snapshot)
            if isCurrentUserMember(of: group, members: members) {
                session.container.localStore.trackGroup(id: groupID, name: group.name)
            } else {
                session.container.localStore.removeGroup(id: groupID)
            }
            logManagementVisibility(for: snapshot)
            #if DEBUG
            print("[RouteFetch] fetch success screen=group_detail groupID=\(groupID) source=live members=\(members.count)")
            #endif
        } catch let error as UserFacingError {
            guard isCurrentLoad(loadToken) else { return }
            #if DEBUG
            print("[RouteFetch] fetch failure screen=group_detail groupID=\(groupID) source=live status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)")
            #endif
            if error.isGroupNotFoundResource {
                clearActiveGroupContext()
                state = .error(error)
                return
            }
            session.handleProtectedLoadError(
                error,
                requirement: .groupManagement,
                state: &state,
                fallbackMessage: "로그인 후 그룹 상세를 다시 확인할 수 있어요."
            )
        } catch {
            guard isCurrentLoad(loadToken) else { return }
            #if DEBUG
            print("[RouteFetch] fetch failure screen=group_detail groupID=\(groupID) source=live status=nil message=\(error.localizedDescription)")
            #endif
            state = .error(UserFacingError(title: "그룹 상세 로딩 실패", message: "그룹 정보를 불러오지 못했습니다."))
        }
    }

    func createMatch() async -> Match? {
        guard ensureActiveGroupContextForMutation() else { return nil }
        actionState = .inProgress("내전 로비를 생성하는 중입니다")
        do {
            let match = try await session.container.matchRepository.create(groupID: groupID, title: "내전 로비")
            if let group = state.value?.group {
                session.container.localStore.trackMatch(
                    RecentMatchContext(matchID: match.id, groupID: groupID, groupName: group.name, createdAt: Date())
                )
            }
            session.container.localStore.appendNotification(title: "내전 생성", body: "새 내전 로비가 생성되었습니다.", symbol: "shield.lefthalf.filled")
            actionState = .success("내전 로비가 생성되었습니다")
            return match
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .matchSave, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("내전 생성에 실패했습니다")
            return nil
        }
    }

    func updateGroup(
        name: String,
        description: String,
        visibility: GroupVisibility,
        joinPolicy: JoinPolicy,
        tags: [String]
    ) async -> GroupSummary? {
        guard ensureActiveGroupContextForMutation() else { return nil }
        guard let snapshot = state.value, canManage(snapshot) else {
            actionState = .failure("방장 또는 운영진만 내전 방을 수정할 수 있습니다.")
            return nil
        }

        actionState = .inProgress("내전 방 정보를 저장하는 중입니다")
        debugGroupDetail("request PATCH /groups/\(groupID)")

        do {
            let updatedGroup = try await session.container.groupRepository.update(
                groupID: groupID,
                name: name,
                description: description.isEmpty ? nil : description,
                visibility: visibility,
                joinPolicy: joinPolicy,
                tags: tags
            )
            let updatedSnapshot = GroupDetailSnapshot(
                group: updatedGroup,
                members: snapshot.members,
                latestMatch: snapshot.latestMatch,
                powerProfiles: snapshot.powerProfiles
            )
            state = .content(updatedSnapshot)
            session.container.localStore.trackGroup(id: updatedGroup.id, name: updatedGroup.name)
            actionState = .success("내전 방 정보가 수정되었습니다")
            logManagementVisibility(for: updatedSnapshot)
            return updatedGroup
        } catch let error as UserFacingError {
            let errorType = mutationErrorType(for: error)
            debugGroupDetail(
                "response failure endpoint=/groups/\(groupID) groupId=\(groupID) responseCode=\(error.statusCode.map(String.init) ?? "nil") mappedErrorType=\(errorType.rawValue)"
            )
            if errorType == .notFound {
                debugGroupDetail("endpoint_missing_possible endpoint=/groups/\(groupID) groupId=\(groupID)")
            }
            if error.requiresAuthentication {
                actionState = .idle
                session.requireReauthentication(for: .groupManagement)
                return nil
            }
            actionState = .failure(message(for: errorType, operation: "update", error: error))
            return nil
        } catch {
            debugGroupDetail("response failure endpoint=/groups/\(groupID) groupId=\(groupID) responseCode=nil mappedErrorType=\(GroupDetailMutationErrorType.other.rawValue)")
            actionState = .failure("내전 방 수정에 실패했습니다. 잠시 후 다시 시도해 주세요.")
            return nil
        }
    }

    func deleteGroup() async -> String? {
        guard ensureActiveGroupContextForMutation() else { return nil }
        guard let snapshot = state.value, canManage(snapshot) else {
            actionState = .failure("방장 또는 운영진만 내전 방을 삭제할 수 있습니다.")
            return nil
        }
        guard !isMutationInFlight else { return nil }

        actionState = .inProgress("내전 방을 삭제하는 중입니다")
        debugGroupDetail("request DELETE /groups/\(groupID)")

        do {
            try await session.container.groupRepository.delete(groupID: groupID)
            debugGroupDetail("delete success groupId=\(groupID)")
            clearActiveGroupContext()
            actionState = .success("내전 방이 삭제되었습니다")
            return groupID
        } catch let error as UserFacingError {
            let errorType = mutationErrorType(for: error)
            debugGroupDetail(
                "response failure endpoint=/groups/\(groupID) groupId=\(groupID) responseCode=\(error.statusCode.map(String.init) ?? "nil") mappedErrorType=\(errorType.rawValue)"
            )
            if errorType == .notFound {
                debugGroupDetail("endpoint_missing_possible endpoint=/groups/\(groupID) groupId=\(groupID)")
            }
            if error.requiresAuthentication {
                actionState = .idle
                session.requireReauthentication(for: .groupManagement)
                return nil
            }
            actionState = .failure(message(for: errorType, operation: "delete", error: error))
            return nil
        } catch {
            debugGroupDetail("response failure endpoint=/groups/\(groupID) groupId=\(groupID) responseCode=nil mappedErrorType=\(GroupDetailMutationErrorType.other.rawValue)")
            actionState = .failure("내전 방 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.")
            return nil
        }
    }

    func inviteMember(userID: String) async {
        guard ensureActiveGroupContextForMutation() else { return }
        actionState = .inProgress("멤버를 초대하는 중입니다")
        do {
            _ = try await session.container.groupRepository.addMember(groupID: groupID, userID: userID)
            actionState = .success("멤버가 추가되었습니다")
            await load(force: true, trigger: .memberInvited)
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .groupManagement, actionState: &actionState)
        } catch {
            actionState = .failure("멤버 추가에 실패했습니다")
        }
    }

    private func canManage(_ snapshot: GroupDetailSnapshot) -> Bool {
        guard let currentUserID = session.currentUserID else { return false }
        if snapshot.group.ownerUserID == currentUserID {
            return true
        }
        guard let currentMember = snapshot.members.first(where: { $0.userID == currentUserID }) else {
            return false
        }
        return currentMember.role == .owner || currentMember.role == .admin
    }

    private func isCurrentUserMember(of group: GroupSummary, members: [GroupMember]) -> Bool {
        guard let currentUserID = session.currentUserID else { return false }
        if group.ownerUserID == currentUserID {
            return true
        }
        return members.contains { $0.userID == currentUserID }
    }

    private func logManagementVisibility(for snapshot: GroupDetailSnapshot) {
        let canEdit = canManage(snapshot)
        debugGroupDetail("edit visible canEdit=\(canEdit)")
        debugGroupDetail("delete visible canDelete=\(canEdit)")
    }

    private func mutationErrorType(for error: UserFacingError) -> GroupDetailMutationErrorType {
        if error.requiresAuthentication {
            return .authRequired
        }
        switch error.statusCode {
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case let statusCode? where statusCode >= 500:
            return .server
        default:
            return .other
        }
    }

    private func message(for errorType: GroupDetailMutationErrorType, operation: String, error: UserFacingError) -> String {
        if error.isGroupNotFoundResource {
            return error.message
        }

        switch (operation, errorType) {
        case ("update", .forbidden):
            return "방장 또는 운영진만 내전 방을 수정할 수 있습니다."
        case ("update", .notFound):
            return "수정할 내전 방을 찾을 수 없거나 서버에서 수정 기능을 아직 지원하지 않습니다."
        case ("update", .conflict):
            return "현재 방 상태에서는 수정할 수 없습니다. 잠시 후 다시 시도해 주세요."
        case ("update", .server), ("update", .other):
            return "내전 방 수정에 실패했습니다. 잠시 후 다시 시도해 주세요."
        case ("delete", .forbidden):
            return "방장 또는 운영진만 내전 방을 삭제할 수 있습니다."
        case ("delete", .notFound):
            return "이미 삭제되었거나 서버에서 삭제 기능을 아직 지원하지 않습니다."
        case ("delete", .conflict):
            return "진행 중인 상태 때문에 내전 방을 삭제할 수 없습니다."
        case ("delete", .server), ("delete", .other):
            return "내전 방 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요."
        case (_, .authRequired):
            return "로그인이 필요합니다."
        default:
            return "요청 처리에 실패했습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    private func canUseGroupContextForRequests(trigger: GroupDetailLoadTrigger) -> Bool {
        guard isGroupContextActive, !session.isDeletedGroupContext(groupID) else {
            debugSkipDeletedGroupReload(groupID: groupID)
            debugGroupDetail("load skipped trigger=\(trigger.rawValue) groupId=\(groupID)")
            return false
        }
        return true
    }

    private func beginLoad() -> Int {
        activeLoadToken += 1
        return activeLoadToken
    }

    private func isCurrentLoad(_ loadToken: Int) -> Bool {
        loadToken == activeLoadToken && isGroupContextActive && !session.isDeletedGroupContext(groupID)
    }

    private func ensureActiveGroupContextForMutation() -> Bool {
        guard isGroupContextActive, !session.isDeletedGroupContext(groupID) else {
            actionState = .failure("삭제되었거나 존재하지 않는 그룹입니다.")
            return false
        }
        return true
    }

    private func clearActiveGroupContext() {
        guard isGroupContextActive || !session.isDeletedGroupContext(groupID) else { return }
        isGroupContextActive = false
        session.markGroupContextDeleted(groupID)
        debugGroupDetail("clear active group context groupId=\(groupID)")
        cancelStaleRequests()
        state = .empty("삭제된 그룹입니다.")
    }

    private func cancelStaleRequests() {
        activeLoadToken += 1
        debugGroupDetail("cancel stale requests groupId=\(groupID)")
    }

    private func loadPowerProfiles(for userIDs: [String]) async -> [String: PowerProfile] {
        var profiles: [String: PowerProfile] = [:]
        for userID in Set(userIDs) {
            if let profile = try? await session.container.profileRepository.powerProfile(userID: userID) {
                profiles[userID] = profile
            }
        }
        return profiles
    }

    private func debugGroupDetail(_ message: String) {
        #if DEBUG
        print("[GroupDetail] \(message)")
        #endif
    }
}

@MainActor
final class MatchDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<MatchDetailSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle

    private let session: AppSessionViewModel
    let matchID: String

    init(session: AppSessionViewModel, matchID: String) {
        self.session = session
        self.matchID = matchID
    }

    func load(force: Bool = false) async {
        if !force, case .content = state { return }
        #if DEBUG
        print("[RouteFetch] fetch started screen=match_detail matchID=\(matchID)")
        #endif
        state = .loading
        do {
            let match = try await session.container.matchRepository.detail(matchID: matchID)
            let result = try? await session.container.matchRepository.result(matchID: matchID)
            let cache = session.container.localStore.cachedResults[matchID]
            state = .content(MatchDetailSnapshot(match: match, result: result, cachedMetadata: cache))
            #if DEBUG
            print("[RouteFetch] fetch success screen=match_detail matchID=\(matchID) source=live")
            #endif
        } catch let error as UserFacingError {
            #if DEBUG
            print("[RouteFetch] fetch failure screen=match_detail matchID=\(matchID) source=live status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)")
            #endif
            session.handleProtectedLoadError(
                error,
                requirement: .resultSave,
                state: &state,
                fallbackMessage: "로그인 후 경기 상세를 다시 확인할 수 있어요."
            )
        } catch {
            #if DEBUG
            print("[RouteFetch] fetch failure screen=match_detail matchID=\(matchID) source=live status=nil message=\(error.localizedDescription)")
            #endif
            state = .error(UserFacingError(title: "경기 상세 로딩 실패", message: "경기 상세를 불러오지 못했습니다."))
        }
    }

    func rematch() async -> Match? {
        guard let snapshot = state.value else { return nil }
        guard snapshot.match.players.isEmpty == false else {
            actionState = .failure("재매칭할 참가자 정보가 없습니다.")
            return nil
        }
        actionState = .inProgress("같은 인원으로 재매칭을 준비하는 중입니다")
        do {
            let repository = session.container.matchRepository
            let localStore = session.container.localStore
            let preferredMode = snapshot.match.balanceMode ?? .balanced
            let originalSignature = currentCompositionSignature(for: snapshot.match)

            let newMatch = try await repository.create(groupID: snapshot.match.groupID, title: "재매칭")
            _ = try await repository.addPlayers(
                matchID: newMatch.id,
                players: snapshot.match.players.map {
                    MatchPlayerInputDTO(
                        userId: $0.userID,
                        riotAccountId: nil,
                        participationStatus: .accepted,
                        sameTeamPreferenceUserIds: [],
                        avoidTeamPreferenceUserIds: [],
                        isCaptain: $0.isCaptain
                    )
                }
            )

            let lockedMatch = try await repository.lock(matchID: newMatch.id)
            _ = try await repository.autoBalance(matchID: newMatch.id, mode: preferredMode)
            _ = try await ensureDifferentCandidateIfNeeded(
                repository: repository,
                matchID: newMatch.id,
                preferredMode: preferredMode,
                originalSignature: originalSignature
            )

            localStore.trackMatch(
                RecentMatchContext(
                    matchID: newMatch.id,
                    groupID: newMatch.groupID,
                    groupName: groupName(for: newMatch.groupID),
                    createdAt: lockedMatch.scheduledAt ?? Date()
                )
            )
            localStore.appendNotification(
                title: "재매칭 생성",
                body: "같은 인원으로 새 추천 조합을 생성했습니다.",
                symbol: "arrow.triangle.2.circlepath"
            )
            actionState = .success("새 추천 조합을 생성했습니다")
            return newMatch
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .matchSave, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("재매칭 생성에 실패했습니다")
            return nil
        }
    }

    func groupName(for groupID: String) -> String {
        if let name = session.container.localStore.groupName(for: groupID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        if let recentGroupName = session.container.localStore.recentMatches
            .first(where: { $0.groupID == groupID })?
            .groupName
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !recentGroupName.isEmpty {
            return recentGroupName
        }

        return "내전"
    }

    private func ensureDifferentCandidateIfNeeded(
        repository: MatchRepository,
        matchID: String,
        preferredMode: BalanceMode,
        originalSignature: String?
    ) async throws -> Match {
        guard let originalSignature else {
            return try await repository.detail(matchID: matchID)
        }

        var refreshedMatch = try await repository.detail(matchID: matchID)
        var excludedCandidateIDs: Set<String> = []

        for _ in 0..<3 {
            if let candidate = preferredCandidate(in: refreshedMatch, mode: preferredMode) {
                if candidateSignature(candidate) != originalSignature {
                    return refreshedMatch
                }
                excludedCandidateIDs.insert(candidate.candidateID)
            } else {
                return refreshedMatch
            }

            _ = try await repository.reroll(
                matchID: matchID,
                mode: preferredMode,
                excludeCandidateIDs: Array(excludedCandidateIDs)
            )
            refreshedMatch = try await repository.detail(matchID: matchID)
        }

        return refreshedMatch
    }

    private func preferredCandidate(in match: Match, mode: BalanceMode) -> MatchCandidate? {
        if let selectedCandidateNo = match.selectedCandidateNo,
           let selectedCandidate = match.candidates.first(where: { $0.candidateNo == selectedCandidateNo }) {
            return selectedCandidate
        }
        return match.candidates.first(where: { $0.type == mode }) ?? match.candidates.first
    }

    private func currentCompositionSignature(for match: Match) -> String? {
        let assignedPlayers = match.players.compactMap { player -> CandidatePlayer? in
            guard let teamSide = player.teamSide, let assignedRole = player.assignedRole else { return nil }
            return CandidatePlayer(
                userID: player.userID,
                nickname: player.nickname,
                teamSide: teamSide,
                assignedRole: assignedRole,
                rolePower: 0,
                isOffRole: false
            )
        }

        guard assignedPlayers.count == match.players.count else { return nil }
        let blueTeam = assignedPlayers.filter { $0.teamSide == .blue }
        let redTeam = assignedPlayers.filter { $0.teamSide == .red }
        guard blueTeam.isEmpty == false, redTeam.isEmpty == false else { return nil }

        let candidate = MatchCandidate(
            candidateID: "current-match",
            candidateNo: 0,
            type: match.balanceMode ?? .balanced,
            score: 0,
            metrics: CandidateMetrics(
                teamPowerGap: 0,
                laneMatchupGap: 0,
                offRolePenalty: 0,
                repeatTeamPenalty: 0,
                preferenceViolationPenalty: 0,
                volatilityClusterPenalty: 0
            ),
            teamAPower: 0,
            teamBPower: 0,
            offRoleCount: 0,
            explanationTags: [],
            teamA: blueTeam,
            teamB: redTeam
        )
        return candidateSignature(candidate)
    }

    private func candidateSignature(_ candidate: MatchCandidate) -> String {
        let blueSignature = candidate.teamA
            .sorted { $0.assignedRole.rawValue < $1.assignedRole.rawValue }
            .map { "\($0.userID):\($0.assignedRole.rawValue)" }
            .joined(separator: "|")
        let redSignature = candidate.teamB
            .sorted { $0.assignedRole.rawValue < $1.assignedRole.rawValue }
            .map { "\($0.userID):\($0.assignedRole.rawValue)" }
            .joined(separator: "|")
        return "\(candidate.type.rawValue)#blue[\(blueSignature)]#red[\(redSignature)]"
    }
}

@MainActor
final class RiotAccountsViewModel: ObservableObject {
    @Published var state: ScreenLoadState<RiotAccountSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle
    @Published var syncInProgressIDs: Set<String> = []
    @Published var unlinkInProgressIDs: Set<String> = []
    @Published var isConnecting = false

    private let session: AppSessionViewModel

    init(session: AppSessionViewModel) {
        self.session = session
    }

    private var currentAccounts: [RiotAccount] {
        state.value?.accounts ?? []
    }

    private func setAccounts(
        _ accounts: [RiotAccount],
        syncSession: Bool = true,
        invalidateDependents: Bool = false
    ) {
        if syncSession {
            session.applyRiotAccounts(accounts, invalidateDependents: invalidateDependents)
        }
        let snapshot = RiotAccountSnapshot(accounts: accounts, syncInProgressIDs: syncInProgressIDs)
        state = accounts.isEmpty ? .empty("추가한 Riot ID가 없습니다.") : .content(snapshot)
    }

    private func applyRiotAccountsViewState(_ riotAccountsViewState: RiotLinkedAccountsViewState) {
        switch riotAccountsViewState {
        case .loading:
            state = .loading
        case .noLinkedAccounts:
            setAccounts([], syncSession: false)
        case let .loaded(accounts):
            setAccounts(accounts, syncSession: false)
            observeSyncStatusesIfNeeded(for: accounts)
        case let .error(error):
            state = .error(error)
        }
    }

    private func updateAccount(id: String, transform: (RiotAccount) -> RiotAccount) {
        let updatedAccounts = currentAccounts.map { account in
            account.id == id ? transform(account) : account
        }
        guard updatedAccounts != currentAccounts else { return }
        setAccounts(updatedAccounts)
    }

    private func accountsAfterAdding(_ addedAccount: RiotAccount) -> [RiotAccount] {
        let preservedAccounts = currentAccounts
            .filter { $0.id != addedAccount.id }
            .map { account in
                addedAccount.isPrimary ? account.withPrimary(false) : account
            }
        return preservedAccounts + [addedAccount]
    }

    private func observeSyncStatusesIfNeeded(for accounts: [RiotAccount]) {
        for account in accounts where account.syncStatus.isInFlight && !syncInProgressIDs.contains(account.id) {
            syncInProgressIDs.insert(account.id)
            Task { [weak self] in
                await self?.pollSyncStatus(for: account.id, showCompletionBanner: false)
            }
        }
    }

    private func pollSyncStatus(for accountID: String, showCompletionBanner: Bool) async {
        defer { syncInProgressIDs.remove(accountID) }

        for attempt in 0..<6 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            guard session.isAuthenticated else { return }

            do {
                let syncState = try await session.container.riotRepository.syncStatus(accountID: accountID)
                var updatedAccount: RiotAccount?
                updateAccount(id: accountID) { account in
                    let nextAccount = account.withSyncStatus(syncState)
                    updatedAccount = nextAccount
                    return nextAccount
                }

                guard let updatedAccount else { return }
                if !syncState.syncStatus.isInFlight {
                    if showCompletionBanner {
                        if updatedAccount.syncUIState.isFailure {
                            actionState = .failure(updatedAccount.syncStatusSummary)
                        } else {
                            actionState = .success("동기화가 완료되었습니다")
                        }
                    }
                    return
                }
            } catch let error as UserFacingError {
                if showCompletionBanner {
                    actionState = .failure(error.message)
                }
                return
            } catch {
                if showCompletionBanner {
                    actionState = .failure("동기화 상태를 확인하지 못했습니다")
                }
                return
            }
        }

        if showCompletionBanner {
            actionState = .success("동기화 요청이 접수되었습니다. 잠시 후 상태를 다시 확인해 주세요.")
        }
    }

    func load(force: Bool = false) async {
        guard session.isAuthenticated else {
            state = .empty("로그인하면 Riot ID 추가와 동기화를 사용할 수 있어요.")
            return
        }
        if !force, case .content = state { return }
        let riotAccountsViewState = await session.refreshRiotAccountsViewState(force: force)
        if case let .error(error) = riotAccountsViewState, error.requiresAuthentication {
            session.handleProtectedLoadError(
                error,
                requirement: .riotAccount,
                state: &state,
                fallbackMessage: "로그인 후 Riot ID 목록을 다시 확인할 수 있어요."
            )
            return
        }
        applyRiotAccountsViewState(riotAccountsViewState)
    }

    func connect(gameName: String, tagLine: String, region: String, isPrimary: Bool) async -> Bool {
        guard session.isAuthenticated else {
            actionState = .failure("로그인 후 Riot ID를 추가할 수 있어요.")
            return false
        }

        let normalizedGameName = RiotAccountInputValidator.normalizedGameName(gameName)
        let normalizedTagLine = RiotAccountInputValidator.normalizedTagLine(tagLine)
        isConnecting = true
        defer { isConnecting = false }

        actionState = .inProgress("Riot ID를 추가하는 중입니다")
        do {
            let addedAccount = try await session.container.riotRepository.connect(
                gameName: normalizedGameName,
                tagLine: normalizedTagLine,
                region: region.lowercased(),
                isPrimary: isPrimary
            )

            let optimisticAccounts = accountsAfterAdding(addedAccount)
            setAccounts(optimisticAccounts, invalidateDependents: true)

            let riotAccountsViewState = await session.refreshRiotAccountsViewState(
                force: true,
                invalidateDependents: true
            )
            switch riotAccountsViewState {
            case .loading:
                setAccounts(optimisticAccounts, invalidateDependents: true)
            case .noLinkedAccounts, .loaded:
                applyRiotAccountsViewState(riotAccountsViewState)
            case .error:
                setAccounts(optimisticAccounts, invalidateDependents: true)
            }
            actionState = .success("Riot ID를 추가했습니다")
            return true
        } catch let error as UserFacingError {
            if error.serverContractCode == .riotAccountAlreadyAddedByThisUser {
                let riotAccountsViewState = await session.refreshRiotAccountsViewState(
                    force: true,
                    invalidateDependents: true
                )
                applyRiotAccountsViewState(riotAccountsViewState)
            }
            session.handleProtectedActionError(error, requirement: .riotAccount, actionState: &actionState)
            return false
        } catch {
            actionState = .failure("Riot ID 추가에 실패했습니다")
            return false
        }
    }

    func sync(id: String) async {
        guard session.isAuthenticated else {
            actionState = .failure("로그인 후 Riot ID 동기화를 사용할 수 있어요.")
            return
        }
        syncInProgressIDs.insert(id)
        actionState = .inProgress("동기화를 요청하는 중입니다")
        do {
            let requestedAt = Date()
            let accepted = try await session.container.riotRepository.sync(accountID: id)
            updateAccount(id: id) { account in
                account.withSyncAccepted(accepted, requestedAt: requestedAt)
            }
            session.container.localStore.appendNotification(title: "Riot 동기화 요청", body: "Riot ID 동기화가 큐에 등록되었습니다.", symbol: "arrow.clockwise")
            actionState = .success("동기화 요청을 보냈습니다")
            await pollSyncStatus(for: id, showCompletionBanner: true)
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .riotAccount, actionState: &actionState)
            syncInProgressIDs.remove(id)
        } catch {
            actionState = .failure("동기화 요청에 실패했습니다")
            syncInProgressIDs.remove(id)
        }
    }

    func unlink(account: RiotAccount) async {
        guard session.isAuthenticated else {
            actionState = .failure("로그인 후 Riot ID를 목록에서 제거할 수 있어요.")
            return
        }
        guard !unlinkInProgressIDs.contains(account.id) else { return }

        let previousAccounts = currentAccounts
        unlinkInProgressIDs.insert(account.id)
        syncInProgressIDs.remove(account.id)
        setAccounts(
            previousAccounts.filter { $0.id != account.id },
            invalidateDependents: true
        )
        actionState = .inProgress("Riot ID를 목록에서 제거하는 중입니다")

        do {
            try await session.container.riotRepository.unlink(accountID: account.id)
            actionState = .success("Riot ID를 목록에서 제거했습니다")
            let riotAccountsViewState = await session.refreshRiotAccountsViewState(
                force: true,
                invalidateDependents: true
            )
            applyRiotAccountsViewState(riotAccountsViewState)
        } catch let error as UserFacingError {
            setAccounts(previousAccounts, invalidateDependents: true)
            session.handleProtectedActionError(error, requirement: .riotAccount, actionState: &actionState)
        } catch {
            setAccounts(previousAccounts, invalidateDependents: true)
            actionState = .failure("Riot ID 제거에 실패했습니다")
        }

        unlinkInProgressIDs.remove(account.id)
    }
}

@MainActor
final class RecruitDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<RecruitDetailViewState> = .initial
    @Published var actionState: AsyncActionState = .idle
    @Published private(set) var applyCapability: RecruitApplyCapability = .unknown

    private let session: AppSessionViewModel
    let postID: String
    private var loadedPost: RecruitPost?

    var isEditVisible: Bool {
        state.value?.isOwner ?? false
    }

    var isDeleteVisible: Bool {
        state.value?.isOwner ?? false
    }

    var isMutationInFlight: Bool {
        if case .inProgress = actionState {
            return true
        }
        return false
    }

    var isDeleteInFlight: Bool {
        isMutationInFlight
    }

    var isApplyButtonEnabled: Bool {
        guard let loadedPost else { return false }
        guard loadedPost.status == .open else { return false }
        if case .inProgress = actionState {
            return false
        }
        if case .unavailable = applyCapability {
            return false
        }
        return true
    }

    var applyCapabilityNote: String? {
        applyCapability.note
    }

    var isCreateMatchButtonEnabled: Bool {
        guard let loadedPost else { return false }
        guard loadedPost.status == .open else { return false }
        if case .inProgress = actionState {
            return false
        }
        return true
    }

    init(session: AppSessionViewModel, postID: String) {
        self.session = session
        self.postID = postID
    }

    func load(force: Bool = false, trigger: RecruitDetailLoadTrigger = .screenAppear) async {
        if !force, case .content = state { return }
        debugRecruitDetail("requested postId=\(postID) trigger=\(trigger.rawValue)")
        #if DEBUG
        print("[RouteFetch] fetch started screen=recruit_detail postID=\(postID)")
        #endif
        if force, let current = state.value {
            state = .refreshing(current)
        } else {
            state = .loading
        }
        do {
            let post = try await session.container.recruitingRepository.detail(postID: postID)
            loadedPost = post
            applyCapability = .unknown
            let viewState = await buildViewState(from: post)
            debugRecruitDetail("response status=200")
            state = .content(viewState)
            #if DEBUG
            print("[RouteFetch] fetch success screen=recruit_detail postID=\(postID) source=live groupID=\(post.groupID)")
            #endif
        } catch let error as UserFacingError {
            debugRecruitDetail("response status=\(error.statusCode.map(String.init) ?? "nil")")
            let mappedErrorType = recruitDetailErrorType(for: error)
            debugRecruitDetail("mapped error type=\(mappedErrorType.rawValue)")
            #if DEBUG
            print("[RouteFetch] fetch failure screen=recruit_detail postID=\(postID) source=live status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)")
            #endif
            switch mappedErrorType {
            case .authRequired:
                session.handleProtectedLoadError(
                    error,
                    requirement: .recruitingWrite,
                    state: &state,
                    fallbackMessage: "로그인 후 모집 상세를 다시 확인할 수 있어요."
                )
            case .forbidden:
                state = .error(
                    UserFacingError(
                        title: "권한이 없어요",
                        message: "이 모집글을 볼 수 있는 권한이 없습니다.",
                        code: error.code,
                        provider: error.provider,
                        statusCode: error.statusCode,
                        details: error.details
                    )
                )
            case .notFound:
                state = .empty("이 모집글을 찾을 수 없습니다.")
            case .transient, .other:
                state = .error(
                    UserFacingError(
                        title: "모집 상세 로딩 실패",
                        message: "모집 상세를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.",
                        code: error.code,
                        provider: error.provider,
                        statusCode: error.statusCode,
                        details: error.details
                    )
                )
            }
        } catch {
            debugRecruitDetail("response status=nil")
            debugRecruitDetail("mapped error type=\(RecruitDetailErrorType.other.rawValue)")
            #if DEBUG
            print("[RouteFetch] fetch failure screen=recruit_detail postID=\(postID) source=live status=nil message=\(error.localizedDescription)")
            #endif
            state = .error(UserFacingError(title: "모집 상세 로딩 실패", message: "모집 상세를 불러오지 못했습니다."))
        }
    }

    func applyToRecruit() async -> RecruitPost? {
        guard let post = loadedPost else { return nil }
        guard post.status == .open else {
            applyCapability = .unavailable("모집이 종료되어 더 이상 참가 신청을 받을 수 없습니다.")
            return nil
        }

        actionState = .inProgress("참가 신청을 보내는 중입니다")
        debugRecruitDetail("request apply postId=\(post.id)")

        do {
            let updatedPost = try await session.container.recruitingRepository.apply(postID: post.id)
            loadedPost = updatedPost
            applyCapability = .available
            state = .content(await buildViewState(from: updatedPost))
            actionState = .success("참가 신청을 보냈습니다")
            return updatedPost
        } catch let error as UserFacingError {
            if error.requiresAuthentication {
                actionState = .idle
                session.requireReauthentication(for: .recruitingWrite)
                return nil
            }
            if session.container.recruitingRepository.isCapabilityUnavailable(error) {
                applyCapability = .unavailable("현재 서버에서 참가 신청 기능을 아직 지원하지 않습니다.")
                actionState = .idle
                return nil
            }
            actionState = .failure(error.message)
            return nil
        } catch {
            actionState = .failure("참가 신청에 실패했습니다")
            return nil
        }
    }

    func createMatch() async -> Match? {
        guard let post = loadedPost else { return nil }
        guard post.status == .open else {
            actionState = .failure("모집이 종료되어 내전을 생성할 수 없습니다.")
            return nil
        }
        actionState = .inProgress("모집글 기반 내전을 생성하는 중입니다")
        do {
            let match = try await session.container.matchRepository.create(groupID: post.groupID, title: post.title)
            session.container.localStore.trackMatch(
                RecentMatchContext(
                    matchID: match.id,
                    groupID: post.groupID,
                    groupName: state.value?.groupName ?? "모집 연결 그룹",
                    createdAt: Date()
                )
            )
            session.container.localStore.appendNotification(
                title: "모집 기반 내전 생성",
                body: "\(post.title) 모집글에서 새 내전 로비를 생성했습니다.",
                symbol: "shield.lefthalf.filled"
            )
            actionState = .success("내전이 생성되었습니다")
            return match
        } catch let error as UserFacingError {
            if error.statusCode == 404 {
                actionState = .failure("연결된 그룹을 찾을 수 없거나 서버에서 내전 생성 기능을 아직 지원하지 않습니다.")
                return nil
            }
            session.handleProtectedActionError(error, requirement: .matchSave, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("내전 생성에 실패했습니다")
            return nil
        }
    }

    fileprivate func makeEditorDraft() -> RecruitEditorDraft? {
        guard let loadedPost else { return nil }
        return RecruitEditorDraft(postType: loadedPost.postType, post: loadedPost)
    }

    func updatePost(
        title: String,
        body: String,
        tags: [String],
        scheduledAt: Date?,
        requiredPositions: [String]
    ) async -> RecruitPost? {
        guard let post = loadedPost, isOwner(of: post) else {
            actionState = .failure("작성자 본인만 모집글을 수정할 수 있습니다.")
            return nil
        }
        guard !isDeleteInFlight else { return nil }

        actionState = .inProgress("모집글을 수정하는 중입니다")
        debugRecruitDetail("request PATCH /recruiting-posts/\(post.id)")

        do {
            let updatedPost = try await session.container.recruitingRepository.update(
                postID: post.id,
                type: post.postType,
                title: title,
                body: body.isEmpty ? nil : body,
                tags: tags,
                scheduledAt: scheduledAt,
                requiredPositions: requiredPositions
            )
            loadedPost = updatedPost
            let viewState = await buildViewState(from: updatedPost)
            state = .content(viewState)
            actionState = .success("모집글이 수정되었습니다")
            return updatedPost
        } catch let error as UserFacingError {
            let errorType = mutationErrorType(for: error)
            debugRecruitDetail(
                "response failure endpoint=/recruiting-posts/\(post.id) postId=\(post.id) responseCode=\(error.statusCode.map(String.init) ?? "nil") mappedErrorType=\(errorType.rawValue)"
            )
            if errorType == .notFound {
                debugRecruitDetail("endpoint_missing_possible endpoint=/recruiting-posts/\(post.id) postId=\(post.id)")
            }
            if error.requiresAuthentication {
                actionState = .idle
                session.requireReauthentication(for: .recruitingWrite)
                return nil
            }
            actionState = .failure(message(for: errorType, operation: "update"))
            return nil
        } catch {
            debugRecruitDetail("response failure endpoint=/recruiting-posts/\(postID) postId=\(postID) responseCode=nil mappedErrorType=\(RecruitDetailMutationErrorType.other.rawValue)")
            actionState = .failure("모집글 수정에 실패했습니다. 잠시 후 다시 시도해 주세요.")
            return nil
        }
    }

    func beginDeleteConfirmation() -> Bool {
        guard !isDeleteInFlight, let post = loadedPost, isOwner(of: post) else { return false }
        debugRecruitDetail("delete tap postId=\(post.id)")
        return true
    }

    func deletePost() async -> RecruitPost? {
        guard !isDeleteInFlight else {
            debugRecruitDetail("delete ignored reason=in_flight postId=\(postID)")
            return nil
        }
        guard let post = loadedPost else { return nil }
        guard isOwner(of: post) else {
            debugRecruitDetail("delete blocked reason=not_owner postId=\(post.id)")
            actionState = .failure("작성자 본인만 모집글을 삭제할 수 있습니다.")
            return nil
        }

        actionState = .inProgress("모집글을 삭제하는 중입니다")
        debugRecruitDetail("delete confirm")
        debugRecruitDetail("request DELETE /recruiting-posts/\(post.id)")

        do {
            try await session.container.recruitingRepository.delete(postID: post.id)
            loadedPost = nil
            actionState = .success("모집글이 삭제되었습니다")
            debugRecruitDetail("response success")
            debugRecruitDetail("delete success postId=\(post.id)")
            return post
        } catch let error as UserFacingError {
            let errorType = mutationErrorType(for: error)
            debugRecruitDetail(
                "response failure endpoint=/recruiting-posts/\(post.id) postId=\(post.id) responseCode=\(error.statusCode.map(String.init) ?? "nil") mappedErrorType=\(errorType.rawValue)"
            )
            if errorType == .notFound {
                debugRecruitDetail("endpoint_missing_possible endpoint=/recruiting-posts/\(post.id) postId=\(post.id)")
            }
            if error.requiresAuthentication {
                actionState = .idle
                session.requireReauthentication(for: .recruitingWrite)
                return nil
            }
            actionState = .failure(message(for: errorType, operation: "delete"))
            return nil
        } catch {
            debugRecruitDetail("response failure endpoint=/recruiting-posts/\(postID) postId=\(postID) responseCode=nil mappedErrorType=\(RecruitDetailMutationErrorType.other.rawValue)")
            actionState = .failure("모집글 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.")
            return nil
        }
    }

    func didNavigateBackAfterDelete() {
        debugRecruitDetail("navigate back after delete")
    }

    private func recruitDetailErrorType(for error: UserFacingError) -> RecruitDetailErrorType {
        if error.requiresAuthentication {
            return .authRequired
        }
        if error.statusCode == 404 {
            return .notFound
        }
        if error.statusCode == 403 || error.isForbiddenFeature {
            return .forbidden
        }
        if let statusCode = error.statusCode, statusCode >= 500 {
            return .transient
        }
        return .other
    }

    private func mutationErrorType(for error: UserFacingError) -> RecruitDetailMutationErrorType {
        if error.requiresAuthentication {
            return .authRequired
        }
        switch error.statusCode {
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case let statusCode? where statusCode >= 500:
            return .server
        default:
            return .other
        }
    }

    private func message(for errorType: RecruitDetailMutationErrorType, operation: String) -> String {
        switch (operation, errorType) {
        case ("update", .forbidden):
            return "작성자 본인만 모집글을 수정할 수 있습니다."
        case ("update", .notFound):
            return "수정할 모집글을 찾을 수 없거나 서버에서 수정 기능을 아직 지원하지 않습니다."
        case ("update", .conflict):
            return "현재 모집 상태에서는 수정할 수 없습니다."
        case ("update", .server), ("update", .other):
            return "모집글 수정에 실패했습니다. 잠시 후 다시 시도해 주세요."
        case ("delete", .forbidden):
            return "작성자 본인만 모집글을 삭제할 수 있습니다."
        case ("delete", .notFound):
            return "이미 삭제되었거나 서버에서 삭제 기능을 아직 지원하지 않습니다."
        case ("delete", .conflict):
            return "현재 모집 상태에서는 삭제할 수 없습니다."
        case ("delete", .server), ("delete", .other):
            return "모집글 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요."
        case (_, .authRequired):
            return "로그인이 필요합니다."
        default:
            return "요청 처리에 실패했습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    private func buildViewState(from post: RecruitPost) async -> RecruitDetailViewState {
        let groupName = await resolveGroupName(for: post.groupID)
        let authorName = resolveAuthorName(from: post.createdBy)
        let viewState = RecruitDetailViewState(
            postID: post.id,
            groupID: post.groupID,
            postType: post.postType,
            title: post.title,
            groupName: groupName,
            authorName: authorName,
            requiredPositionsText: joinedDisplayValue(post.requiredPositions, fallback: "미정"),
            statusText: displayStatusText(for: post.status),
            moodTagsText: joinedDisplayValue(post.tags, fallback: "미설정"),
            scheduledAtText: post.scheduledAt?.shortDateText ?? "미정",
            bodyText: normalizedDisplayValue(post.body) ?? "상세 설명이 없습니다.",
            isOwner: isOwner(of: post)
        )
        debugRecruitDetail("render title=\(viewState.title)")
        debugRecruitDetail("render groupName=\(viewState.groupName)")
        debugRecruitDetail("edit visible isOwner=\(viewState.isOwner)")
        debugRecruitDetail("delete visible isOwner=\(viewState.isOwner)")
        return viewState
    }

    private func resolveGroupName(for groupID: String) async -> String {
        if let cachedGroupName = normalizedDisplayValue(session.container.localStore.groupName(for: groupID)) {
            return cachedGroupName
        }
        if let group = try? await session.container.groupRepository.detail(groupID: groupID) {
            if let fetchedGroupName = normalizedDisplayValue(group.name) {
                return fetchedGroupName
            }
        }
        return "그룹 정보 없음"
    }

    private func resolveAuthorName(from createdBy: String?) -> String? {
        guard let normalizedValue = normalizedDisplayValue(createdBy) else { return nil }
        if normalizedValue == session.currentUserID {
            return normalizedDisplayValue(session.profile?.nickname) ?? "나"
        }
        if looksLikeInternalIdentifier(normalizedValue) {
            return nil
        }
        return normalizedValue
    }

    private func isOwner(of post: RecruitPost) -> Bool {
        guard
            let currentUserID = session.currentUserID,
            let createdBy = normalizedDisplayValue(post.createdBy)
        else {
            return false
        }
        return createdBy == currentUserID
    }

    private func joinedDisplayValue(_ values: [String], fallback: String) -> String {
        let normalizedValues = values.compactMap(normalizedDisplayValue)
        return normalizedValues.isEmpty ? fallback : normalizedValues.joined(separator: ", ")
    }

    private func normalizedDisplayValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func displayStatusText(for status: RecruitingPostStatus) -> String {
        status == .open ? "모집 중" : status.rawValue
    }

    private func looksLikeInternalIdentifier(_ value: String) -> Bool {
        if value.contains("-") || value.contains("_") {
            return true
        }
        if value.range(of: "^[A-Za-z0-9]{16,}$", options: .regularExpression) != nil {
            return true
        }
        if value.range(of: "^[0-9a-fA-F-]{8,}$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func debugRecruitDetail(_ message: String) {
        #if DEBUG
        print("[RecruitDetail] \(message)")
        #endif
    }
}

struct AppShellView: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var groupViewModel: GroupMainViewModel
    @StateObject private var recruitViewModel: RecruitBoardViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @State private var lastSessionScopeKey: String?

    init(session: AppSessionViewModel, router: AppRouter) {
        self.session = session
        self.router = router
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(session: session))
        _groupViewModel = StateObject(wrappedValue: GroupMainViewModel(session: session))
        _recruitViewModel = StateObject(wrappedValue: RecruitBoardViewModel(session: session))
        _historyViewModel = StateObject(wrappedValue: HistoryViewModel(session: session))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(session: session))
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AppTabBar(selectedTab: session.selectedTab) { tab in
                        session.selectedTab = tab
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(route)
                }
                .sheet(item: $session.authPrompt) { prompt in
                    AuthGateSheet(session: session, prompt: prompt)
                }
                .task(id: session.dataScopeKey) {
                    guard lastSessionScopeKey != session.dataScopeKey else { return }
                    lastSessionScopeKey = session.dataScopeKey
                    resetViewModelsForSessionChange()
                    await loadSelectedTab(force: true, trigger: .sessionScopeChange)
                }
                .task(id: session.riotLinkedDataRevision) {
                    guard session.riotLinkedDataRevision > 0 else { return }
                    homeViewModel.reset()
                    profileViewModel.reset()
                    if session.selectedTab == .home || session.selectedTab == .profile {
                        await loadSelectedTab(force: true, trigger: .riotLinkedDataRevision)
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch session.selectedTab {
        case .home:
            HomeScreen(viewModel: homeViewModel, session: session, router: router)
        case .match:
            GroupMainScreen(viewModel: groupViewModel, session: session, router: router)
        case .recruit:
            RecruitBoardScreen(viewModel: recruitViewModel, session: session, router: router)
        case .history:
            HistoryScreen(viewModel: historyViewModel, session: session, router: router)
        case .profile:
            ProfileScreen(viewModel: profileViewModel, session: session, router: router)
        }
    }

    private func destinationView(_ route: AppRoute) -> some View {
        logDestinationBuilt(route)
        return buildDestinationView(route)
    }

    @ViewBuilder
    private func buildDestinationView(_ route: AppRoute) -> some View {
        switch route {
        case .search:
            SearchScreen(viewModel: SearchViewModel(session: session), session: session, router: router, onBack: router.pop)
        case .notifications:
            NotificationsScreen(store: session.container.localStore, onBack: router.pop)
        case .riotAccounts:
            RiotAccountsScreen(viewModel: RiotAccountsViewModel(session: session), session: session, onBack: router.pop)
        case .settings:
            SettingsScreen(session: session, router: router, onBack: router.pop)
        case .homeUpcomingMatches:
            HomeUpcomingMatchesScreen(
                viewModel: HomeUpcomingMatchesViewModel(session: session),
                router: router,
                onBack: router.pop
            )
        case .homeGroups:
            HomeGroupsScreen(
                viewModel: HomeGroupsViewModel(session: session),
                session: session,
                router: router,
                onBack: router.pop
            )
        case .powerDetail:
            PowerDetailScreen(
                viewModel: PowerDetailViewModel(session: session),
                title: "파워 상세",
                emptyTitle: "파워 상세",
                onBack: router.pop
            )
        case let .memberProfile(userID, nickname):
            PowerDetailScreen(
                viewModel: PowerDetailViewModel(
                    session: session,
                    targetUserID: userID,
                    displayName: nickname
                ),
                title: nickname.isEmpty ? "멤버 프로필" : nickname,
                emptyTitle: "멤버 프로필",
                onBack: router.pop
            )
        case .homeRecentMatches:
            HomeRecentMatchesScreen(
                viewModel: HomeRecentMatchesViewModel(session: session),
                router: router,
                onBack: router.pop
            )
        case let .groupDetail(groupID):
            GroupDetailScreen(
                viewModel: GroupDetailViewModel(session: session, groupID: groupID),
                router: router,
                onGroupUpdated: { updatedGroup in
                    groupViewModel.handleGroupUpdated(updatedGroup)
                },
                onGroupDeleted: { deletedGroupID in
                    homeViewModel.reset()
                    profileViewModel.reset()
                    groupViewModel.handleGroupDeleted(groupID: deletedGroupID)
                }
            )
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
        case let .manualAdjust(matchID, draft):
            ManualAdjustFeatureView(
                store: Store(
                    initialState: ManualAdjustFeature.State(matchID: matchID, draft: draft)
                ) {
                    ManualAdjustFeature()
                } withDependencies: {
                    $0.appContainer = { session.container }
                },
                onBack: router.pop,
                onSaved: router.pop
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
        case let .matchDetail(matchID):
            MatchDetailScreen(viewModel: MatchDetailViewModel(session: session, matchID: matchID), router: router)
        case let .recruitDetail(postID):
            RecruitDetailScreen(
                viewModel: RecruitDetailViewModel(session: session, postID: postID),
                router: router,
                onUpdateSuccess: { updatedPost in
                    recruitViewModel.handleUpdateSuccess(updatedPost)
                },
                onDeleteSuccess: { deletedPost in
                    recruitViewModel.handleDeleteSuccess(deletedPost)
                }
            )
        }
    }

    private func loadSelectedTab(force: Bool = false, trigger: AppShellLoadTrigger) async {
        switch session.selectedTab {
        case .home:
            await homeViewModel.load(force: force, trigger: trigger.rawValue)
        case .match:
            await groupViewModel.load(force: force, trigger: trigger.rawValue)
        case .recruit:
            await recruitViewModel.load(force: force, trigger: trigger.recruitBoardTrigger)
        case .history:
            await historyViewModel.load(force: force, trigger: trigger.rawValue)
        case .profile:
            await profileViewModel.load(force: force, trigger: trigger.rawValue)
        }
    }

    private func resetViewModelsForSessionChange() {
        homeViewModel.reset()
        groupViewModel.reset()
        recruitViewModel.reset()
        historyViewModel.reset()
        profileViewModel.reset()
    }

    private func logDestinationBuilt(_ route: AppRoute) {
#if DEBUG
        print("[Route] destination built route=\(route.debugDescription)")
#endif
    }
}

private enum AppShellLoadTrigger: String {
    case sessionScopeChange = "session_scope_change"
    case riotLinkedDataRevision = "riot_linked_data_revision"

    var recruitBoardTrigger: RecruitBoardLoadTrigger {
        switch self {
        case .sessionScopeChange:
            return .sessionScopeChange
        case .riotLinkedDataRevision:
            return .screenAppear
        }
    }
}

struct HomeScreen: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        TabRootScaffold(
            title: "내전 메이커",
            leadingAction: notificationsHeaderAction,
            trailingAction: searchHeaderAction
        ) {
            content
                .task { await viewModel.load() }
        }
    }

    private var notificationsHeaderAction: TabHeaderAction {
        TabHeaderAction(systemName: "bell", accessibilityLabel: "알림") {
            session.openProtectedRoute(.notifications, requirement: .notifications, router: router)
        }
    }

    private var searchHeaderAction: TabHeaderAction {
        TabHeaderAction(systemName: "magnifyingglass", accessibilityLabel: "검색") {
            router.push(.search)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .initial, .loading:
            LoadingStateView(title: "홈 데이터를 준비 중입니다")
        case let .error(error):
            ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
        case let .empty(message):
            ScrollView {
                StatusBarView()
                EmptyStateView(title: "홈", message: message, actionTitle: "그룹 탭으로 이동") {
                    session.selectedTab = .match
                }
            }
        case let .refreshing(contentState), let .content(contentState):
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("오늘의 내전을 시작하세요")
                                .font(AppTypography.heading(18, weight: .bold))
                            Text("10명을 모아 자동 밸런스 팀을 생성합니다")
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textSecondary)
                            Button {
                                session.selectedTab = .match
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("내전 만들기")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 124)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x1A2744), AppPalette.bgPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        let groups = groups(for: contentState)
                        let currentMatch = currentMatch(for: contentState)

                        HStack(spacing: 8) {
                            quickAction(symbol: "person.3.fill", title: "10명\n모으기", tint: AppPalette.accentBlue) {
                                session.selectedTab = .match
                            }
                            quickAction(symbol: "arrow.left.arrow.right", title: "팀 자동\n생성", tint: AppPalette.accentPurple) {
                                if let match = currentMatch {
                                    router.push(.teamBalance(groupID: match.groupID, matchID: match.id))
                                } else {
                                    session.selectedTab = .match
                                }
                            }
                            quickAction(symbol: "checkmark.circle", title: "결과\n입력", tint: AppPalette.accentGreen) {
                                if let match = currentMatch {
                                    router.push(.matchResult(matchID: match.id))
                                } else {
                                    session.selectedTab = .match
                                }
                            }
                            quickAction(symbol: "megaphone", title: "상대팀\n모집", tint: AppPalette.accentOrange) {
                                session.selectedTab = .recruit
                            }
                        }

                        homeContentSection(title: "예정된 내전") {
                            openHomeSection(.homeUpcomingMatches, section: "예정된 내전", destination: "전체 예정 내전 목록")
                        } content: {
                            if let match = currentMatch {
                                Button {
                                    router.push(.matchLobby(groupID: match.groupID, matchID: match.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(groups.first(where: { $0.id == match.groupID })?.name ?? "롤내전모임")
                                                .font(AppTypography.body(14, weight: .semibold))
                                            Spacer()
                                            Text(match.scheduledAt?.shortDateText ?? "예정 미정")
                                                .font(AppTypography.body(12, weight: .semibold))
                                                .foregroundStyle(AppPalette.accentBlue)
                                        }
                                        Text("\(match.acceptedCount)/10명 모집 중 · TOP, SUP 필요")
                                            .font(AppTypography.body(11))
                                            .foregroundStyle(AppPalette.textSecondary)
                                        ProgressView(value: Double(match.acceptedCount), total: 10)
                                            .tint(AppPalette.accentBlue)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppPalette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        homeContentSection(title: "최근 참여 그룹") {
                            openHomeSection(.homeGroups, section: "최근 참여 그룹", destination: "전체 그룹/참여 그룹 목록")
                        } content: {
                            HStack(spacing: 10) {
                                ForEach(Array(groups.prefix(2))) { group in
                                    Button {
                                        session.openGroupDetailIfAccessible(group, router: router)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(group.name)
                                                .font(AppTypography.body(13, weight: .semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                                .lineLimit(1)
                                            Text("\(group.memberCount)명 · \(group.tags.first ?? "서울")")
                                                .font(AppTypography.body(10))
                                                .foregroundStyle(AppPalette.textMuted)
                                            Text(group.description ?? "최근 내전 준비 중")
                                                .font(AppTypography.body(10))
                                                .foregroundStyle(AppPalette.textSecondary)
                                                .lineLimit(2)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .appPanel(background: AppPalette.bgCard, radius: 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        switch contentState {
                        case let .authenticated(snapshot):
                            homeContentSection(
                                title: "내 파워 프로필",
                                trailing: powerSectionTrailingText(for: snapshot.riotAccountsViewState)
                            ) {
                                openPowerSection(for: snapshot.riotAccountsViewState)
                            } content: {
                                powerSummaryCard(
                                    profile: snapshot.profile,
                                    power: snapshot.power,
                                    riotAccountsViewState: snapshot.riotAccountsViewState
                                )
                            }

                            homeContentSection(title: "최근 경기") {
                                openHomeSection(.homeRecentMatches, section: "최근 경기", destination: "최근 경기 전체 목록")
                            } content: {
                                if let latestHistory = snapshot.latestHistory {
                                    Button {
                                        router.push(.matchDetail(matchID: latestHistory.matchID))
                                    } label: {
                                        MatchCardView(
                                            title: snapshot.groups.first?.name ?? "롤내전모임",
                                            dateText: latestHistory.scheduledAt.dottedDateText,
                                            isWin: latestHistory.result == "WIN",
                                            blueSummary: "블루 팀",
                                            redSummary: "레드 팀",
                                            detail: "KDA \(latestHistory.kda) · MMR \(Int(latestHistory.deltaMMR))"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    guestBenefitCard(
                                        title: "아직 계정 기록이 없어요",
                                        message: "경기 결과를 저장하면 최근 내전 성적이 여기에 쌓입니다.",
                                        buttonTitle: "결과 입력하러 가기"
                                    ) {
                                        if let match = currentMatch {
                                            router.push(.matchResult(matchID: match.id))
                                        } else {
                                            session.selectedTab = .match
                                        }
                                    }
                                }
                            }
                        case let .guest(snapshot):
                            SectionHeaderView(title: "로그인하면 더 편해요")
                            guestBenefitCard(
                                title: "찜, 동기화, 기기 간 이어하기",
                                message: "지금은 로컬 저장만 사용할 수 있어요. 로그인하면 기록 저장, 공유, 이어하기가 계정에 연결됩니다.",
                                buttonTitle: "로그인하고 동기화"
                            ) {
                                session.requireAuthentication(for: .profileSync)
                            }

                            SectionHeaderView(title: "최근 로컬 저장")
                            if let latestLocal = snapshot.latestLocalResult {
                                MatchCardView(
                                    title: latestLocal.groupName,
                                    dateText: latestLocal.savedAt.dottedDateText,
                                    isWin: latestLocal.winningTeam == .blue,
                                    blueSummary: "승리 팀 \(latestLocal.winningTeam == .blue ? "블루" : "레드")",
                                    redSummary: "밸런스 \(latestLocal.balanceRating)/5",
                                    detail: "로컬 저장 · MVP \(latestLocal.mvpUserID)"
                                )
                            } else {
                                guestBenefitCard(
                                    title: "아직 로컬 기록이 없어요",
                                    message: "경기 결과를 저장하면 이 탭에서 최근 내전 흐름을 다시 확인할 수 있어요.",
                                    buttonTitle: "결과 입력하러 가기"
                                ) {
                                    if let match = currentMatch {
                                        router.push(.matchResult(matchID: match.id))
                                    } else {
                                        session.selectedTab = .match
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
            .refreshable { await viewModel.refresh() }
        }
    }

    private func quickAction(symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(AppPalette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func openHomeSection(_ route: AppRoute, section: String, destination: String) {
        #if DEBUG
        print("[HomeSectionMore] section=\(section) destination=\(destination)")
        #endif
        router.push(route)
    }

    private func openPowerSection(for riotAccountsViewState: RiotLinkedAccountsViewState) {
        if riotAccountsViewState.hasLinkedAccounts {
            openHomeSection(.powerDetail, section: "내 파워 프로필", destination: "파워 프로필 상세 화면")
        } else {
            router.push(.riotAccounts)
        }
    }

    private func groups(for content: HomeContentState) -> [GroupSummary] {
        switch content {
        case let .guest(snapshot):
            return snapshot.groups
        case let .authenticated(snapshot):
            return snapshot.groups
        }
    }

    private func currentMatch(for content: HomeContentState) -> Match? {
        switch content {
        case let .guest(snapshot):
            return snapshot.currentMatch
        case let .authenticated(snapshot):
            return snapshot.currentMatch
        }
    }

    private func homeContentSection<Content: View>(
        title: String,
        trailing: String = "더보기",
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: title, trailing: trailing, onTap: onTap)
            content()
        }
    }

    private func powerSummaryCard(
        profile: UserProfile,
        power: PowerProfile?,
        riotAccountsViewState: RiotLinkedAccountsViewState
    ) -> some View {
        switch riotAccountsViewState {
        case .noLinkedAccounts:
            return AnyView(
                riotPowerEmptyCard(
                    title: "추가한 Riot ID가 없어요",
                    message: "Riot ID를 추가하면 내전 전적과 파워 프로필을 확인할 수 있어요",
                    buttonTitle: "Riot ID 추가하기"
                ) {
                    router.push(.riotAccounts)
                }
            )
        case let .error(error):
            return AnyView(
                riotPowerEmptyCard(
                    title: "Riot ID 상태를 확인하지 못했어요",
                    message: error.message,
                    buttonTitle: "Riot ID 관리 열기"
                ) {
                    router.push(.riotAccounts)
                }
            )
        case .loading:
            return AnyView(
                riotPowerEmptyCard(
                    title: "Riot ID 목록을 확인하는 중이에요",
                    message: "추가한 Riot ID를 확인한 뒤 파워 프로필을 보여드릴게요",
                    buttonTitle: "Riot ID 관리 열기"
                ) {
                    router.push(.riotAccounts)
                }
            )
        case .loaded:
            let overview = PowerViewStateBuilder.home(
                power: power,
                hasLinkedRiotAccount: riotAccountsViewState.hasLinkedAccounts
            ).overview

            return AnyView(
                Button {
                    openHomeSection(.powerDetail, section: "내 파워 프로필", destination: "파워 프로필 상세 화면")
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(overview.scoreText)
                                    .font(AppTypography.heading(42, weight: .heavy))
                                    .foregroundStyle(AppPalette.accentBlue)
                                Text(overview.scoreLabel)
                                    .font(AppTypography.body(11))
                                    .foregroundStyle(AppPalette.textMuted)
                            }

                            Spacer(minLength: 16)

                            VStack(alignment: .trailing, spacing: 8) {
                                if let delta = overview.change {
                                    powerHomeDeltaBadge(delta, caption: overview.changeCaptionText)
                                }

                                if let percentileText = overview.percentileText {
                                    Text(percentileText)
                                        .font(AppTypography.body(11, weight: .semibold))
                                        .foregroundStyle(AppPalette.accentGold)
                                }
                            }
                        }

                        Text(overview.isPlaceholder ? "\(profile.nickname)님의 경기 결과가 쌓이면 파워가 계산돼요." : overview.insightText)
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Text("상세 보기")
                                .font(AppTypography.body(13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AppPalette.textPrimary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x16284C), Color(hex: 0x111824)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            )
        }
    }

    private func powerSectionTrailingText(for riotAccountsViewState: RiotLinkedAccountsViewState) -> String {
        switch riotAccountsViewState {
        case .loaded:
            return "상세 보기 >"
        case .noLinkedAccounts:
            return "Riot ID 추가 >"
        case .loading, .error:
            return "Riot ID 관리 >"
        }
    }

    private func riotPowerEmptyCard(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.accentBlue)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(AppTypography.heading(16, weight: .bold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Text(message)
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(buttonTitle, action: action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x16284C), Color(hex: 0x111824)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func guestBenefitCard(title: String, message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.heading(15, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }

    private func powerHomeDeltaBadge(_ delta: PowerDeltaViewState, caption: String?) -> some View {
        HStack(spacing: 4) {
            if let symbolName = delta.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(delta.text)
                .font(AppTypography.body(11, weight: .semibold))
            if let caption {
                Text(caption)
                    .font(AppTypography.body(10, weight: .medium))
            }
        }
        .foregroundStyle(delta.tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(delta.tone.badgeBackground)
        .clipShape(Capsule())
    }
}

fileprivate struct PowerMetricBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppPalette.border.opacity(0.88))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(16, geometry.size.width * max(0.08, min(progress, 1))))
            }
        }
        .frame(height: 4)
    }
}

fileprivate struct PowerSection<Content: View>: View {
    let title: String
    let spacing: CGFloat
    let content: Content

    init(title: String, spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.title = title
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(AppTypography.heading(17, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)
            content
        }
    }
}

fileprivate struct GroupPowerGuideCard: View {
    let guide: GroupPowerGuideViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.accentBlue)
                Text(guide.title)
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
            }

            Text(guide.message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x101B31))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.accentBlue.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct GroupPowerMemberRow: View {
    let row: GroupMemberPowerRowViewState

    private var powerColor: Color {
        switch row.source {
        case .snapshot:
            return AppPalette.accentBlue
        case .liveFallback:
            return AppPalette.accentBlue
        case .unavailable:
            return AppPalette.textMuted
        }
    }

    private var labelColor: Color {
        switch row.source {
        case .snapshot:
            return AppPalette.textMuted
        case .liveFallback:
            return AppPalette.textMuted
        case .unavailable:
            return AppPalette.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppPalette.bgElevated)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(AppTypography.body(14, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(row.subtitle)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.powerText)
                    .font(AppTypography.heading(20, weight: .bold))
                    .foregroundStyle(powerColor)
                Text(row.powerLabel)
                    .font(AppTypography.body(10))
                    .foregroundStyle(labelColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct DimmedBottomSheet<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    var maxHeightRatio: CGFloat = 0.72
    let content: Content

    @GestureState private var dragOffset: CGFloat = 0

    init(
        title: String,
        onDismiss: @escaping () -> Void,
        maxHeightRatio: CGFloat = 0.72,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onDismiss = onDismiss
        self.maxHeightRatio = maxHeightRatio
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 38, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 14)

                    HStack {
                        Text(title)
                            .font(AppTypography.heading(18, weight: .bold))
                            .foregroundStyle(AppPalette.textPrimary)
                        Spacer()
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.textMuted)
                                .frame(width: 28, height: 28)
                                .background(AppPalette.bgTertiary.opacity(0.92))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    ScrollView(showsIndicators: false) {
                        content
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(
                    maxHeight: min(geometry.size.height - 20, max(320, geometry.size.height * maxHeightRatio)),
                    alignment: .top
                )
                .background(AppPalette.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .updating($dragOffset) { value, state, _ in
                            if value.translation.height > 0 {
                                state = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 120 {
                                dismiss()
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            onDismiss()
        }
    }
}

fileprivate struct HomeUpcomingMatchesScreen: View {
    @StateObject private var viewModel: HomeUpcomingMatchesViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void

    init(viewModel: HomeUpcomingMatchesViewModel, router: AppRouter, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.router = router
        self.onBack = onBack
    }

    var body: some View {
        screenScaffold(title: "예정된 내전", onBack: onBack, rightSystemImage: nil) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "예정된 내전을 불러오는 중입니다")
                        .task { await viewModel.load(trigger: "screen_appear") }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: "retry") } }
                case let .empty(message):
                    EmptyStateView(title: "예정된 내전", message: message)
                case let .content(items), let .refreshing(items):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(items) { item in
                                Button {
                                    #if DEBUG
                                    print("[HomeSectionMore] itemTap=예정된 내전 matchID=\(item.match.id)")
                                    #endif
                                    router.push(.matchLobby(groupID: item.match.groupID, matchID: item.match.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 10) {
                                            Text(item.groupName)
                                                .font(AppTypography.body(15, weight: .semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                            Spacer()
                                            Text(item.match.scheduledAt?.shortDateText ?? "예정 미정")
                                                .font(AppTypography.body(12, weight: .semibold))
                                                .foregroundStyle(AppPalette.accentBlue)
                                        }

                                        HStack(spacing: 10) {
                                            upcomingMatchBadge(item.match.status.title, tint: item.match.status.tint)
                                            Text("\(item.match.acceptedCount)/10명 참여")
                                                .font(AppTypography.body(12))
                                                .foregroundStyle(AppPalette.textSecondary)
                                        }

                                        ProgressView(value: Double(item.match.acceptedCount), total: 10)
                                            .tint(AppPalette.accentBlue)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .appPanel(background: AppPalette.bgCard, radius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
    }

    private func upcomingMatchBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppPalette.bgTertiary)
            .clipShape(Capsule())
    }
}

fileprivate struct HomeGroupsScreen: View {
    @StateObject private var viewModel: HomeGroupsViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void

    init(
        viewModel: HomeGroupsViewModel,
        session: AppSessionViewModel,
        router: AppRouter,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.session = session
        self.router = router
        self.onBack = onBack
    }

    var body: some View {
        screenScaffold(title: "참여 그룹", onBack: onBack, rightSystemImage: nil) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "그룹 목록을 불러오는 중입니다")
                        .task { await viewModel.load(trigger: "screen_appear") }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: "retry") } }
                case let .empty(message):
                    EmptyStateView(title: "참여 그룹", message: message)
                case let .content(groups), let .refreshing(groups):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(groups) { group in
                                Button {
                                    #if DEBUG
                                    print("[HomeSectionMore] itemTap=최근 참여 그룹 groupID=\(group.id)")
                                    #endif
                                    session.openGroupDetailIfAccessible(group, router: router)
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(group.name)
                                                .font(AppTypography.body(16, weight: .semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                            Spacer()
                                            if let firstTag = group.tags.first {
                                                Text(firstTag)
                                                    .font(AppTypography.body(11, weight: .semibold))
                                                    .foregroundStyle(AppPalette.accentGreen)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(AppPalette.bgTertiary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text("멤버 \(group.memberCount)명 · 최근 내전 \(group.recentMatches)회")
                                            .font(AppTypography.body(12))
                                            .foregroundStyle(AppPalette.textSecondary)
                                        if let description = group.description, !description.isEmpty {
                                            Text(description)
                                                .font(AppTypography.body(12))
                                                .foregroundStyle(AppPalette.textMuted)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .appPanel(background: AppPalette.bgCard, radius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
    }
}

fileprivate struct PowerDetailScreen: View {
    @StateObject private var viewModel: PowerDetailViewModel
    let title: String
    let emptyTitle: String
    let onBack: () -> Void
    @State private var showsCalculationSheet = false

    init(
        viewModel: PowerDetailViewModel,
        title: String = "파워 상세",
        emptyTitle: String = "파워 상세",
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.title = title
        self.emptyTitle = emptyTitle
        self.onBack = onBack
    }

    var body: some View {
        screenScaffold(title: title, onBack: onBack, rightSystemImage: nil) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "파워 프로필을 불러오는 중입니다")
                        .task { await viewModel.load(trigger: "screen_appear") }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: "retry") } }
                case let .empty(message):
                    EmptyStateView(title: emptyTitle, message: message)
                case let .content(detail), let .refreshing(detail):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            overviewCard(detail.overview)
                            insightCard(detail.overview.insightText)

                            PowerSection(title: "파워 구성 요소", spacing: 8) {
                                VStack(spacing: 8) {
                                    ForEach(detail.overview.components) { component in
                                        componentRow(component)
                                    }
                                }
                            }

                            PowerSection(title: "최근 변화 내역", spacing: 8) {
                                VStack(spacing: 8) {
                                    ForEach(detail.timeline) { item in
                                        timelineRow(item)
                                    }
                                }
                            }

                            PowerSection(title: "파워 올리는 방법", spacing: 8) {
                                VStack(spacing: 8) {
                                    ForEach(detail.tips) { tip in
                                        tipRow(tip)
                                    }
                                }
                            }

                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                    showsCalculationSheet = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles.rectangle.stack")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("파워 계산 방식 자세히 보기")
                                        .font(AppTypography.body(14, weight: .semibold))
                                }
                                .foregroundStyle(AppPalette.accentBlue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AppPalette.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppPalette.border, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            PowerSection(title: "자주 묻는 질문", spacing: 8) {
                                VStack(spacing: 8) {
                                    ForEach(detail.faqs) { faq in
                                        faqRow(faq)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .overlay {
            if showsCalculationSheet {
                let sheetState = (viewModel.state.value?.calculationSheet) ?? PowerViewStateBuilder.calculationSheet()
                DimmedBottomSheet(
                    title: sheetState.title,
                    onDismiss: { showsCalculationSheet = false },
                    maxHeightRatio: 0.66
                ) {
                    calculationSheetContent(sheetState)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showsCalculationSheet)
    }

    private func overviewCard(_ overview: PowerOverviewViewState) -> some View {
        VStack(spacing: 12) {
            Text(overview.scoreText)
                .font(AppTypography.heading(54, weight: .heavy))
                .foregroundStyle(AppPalette.accentBlue)
            Text(overview.scoreLabel)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textMuted)
            if let tierText = overview.tierText {
                Text(tierText)
                    .font(AppTypography.body(11, weight: .semibold))
                    .foregroundStyle(AppPalette.bgPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppPalette.accentBlue)
                    .clipShape(Capsule())
            }
            HStack(spacing: 8) {
                if let delta = overview.change {
                    deltaBadge(delta, caption: overview.changeCaptionText)
                }
                if let percentileText = overview.percentileText {
                    Text(percentileText)
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(AppPalette.accentGold)
                }
            }
            .frame(maxWidth: .infinity)
            Text(overview.supportingText)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x152748), Color(hex: 0x101826)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func insightCard(_ insightText: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.accentGold)
                .frame(width: 18, height: 18)
            Text(insightText)
                .font(AppTypography.body(12, weight: .medium))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func componentRow(_ component: PowerComponentRowViewState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(component.tone.color)
                    .frame(width: 7, height: 7)
                Text(component.title)
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
                Text(component.scoreText)
                    .font(AppTypography.body(18, weight: .bold))
                    .foregroundStyle(component.tone.color)
                if let delta = component.delta {
                    Text(delta.text)
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(delta.tone.color)
                }
            }
            PowerMetricBar(progress: component.progress, tint: component.tone.color)
            Text(component.description)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(14)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func timelineRow(_ item: PowerTimelineItemViewState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.tone.color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Spacer()
                    Text(item.metricText)
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(item.tone.color)
                }
                Text(item.description)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tipRow(_ tip: PowerTipItemViewState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tip.tone.badgeBackground)
                    .frame(width: 30, height: 30)
                Image(systemName: tip.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tip.tone.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(tip.description)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func faqRow(_ faq: PowerFAQItemViewState) -> some View {
        HStack(spacing: 12) {
            Text(faq.question)
                .font(AppTypography.body(13, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.textMuted)
        }
        .padding(14)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func calculationSheetContent(_ state: PowerCalculationSheetViewState) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.summaryText)
                    .font(AppTypography.body(14, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(state.highlightText)
                    .font(AppTypography.body(12, weight: .medium))
                    .foregroundStyle(AppPalette.textPrimary)
            }
            .padding(16)
            .background(AppPalette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("구성 요소별 설명")
                .font(AppTypography.heading(16, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(state.factors) { factor in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(factor.tone.color)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(factor.title)
                                .font(AppTypography.body(13, weight: .semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                            Text(factor.description)
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(state.noteTitle)
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                ForEach(state.notes, id: \.self) { note in
                    Text(note)
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(AppPalette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func deltaBadge(_ delta: PowerDeltaViewState, caption: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let symbolName = delta.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(delta.text)
                .font(AppTypography.body(11, weight: .semibold))
            if let caption {
                Text(caption)
                    .font(AppTypography.body(10, weight: .medium))
            }
        }
        .foregroundStyle(delta.tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(delta.tone.badgeBackground)
        .clipShape(Capsule())
    }
}

fileprivate struct HomeRecentMatchesScreen: View {
    @StateObject private var viewModel: HomeRecentMatchesViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void

    init(viewModel: HomeRecentMatchesViewModel, router: AppRouter, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.router = router
        self.onBack = onBack
    }

    var body: some View {
        screenScaffold(title: "최근 경기", onBack: onBack, rightSystemImage: nil) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "최근 경기 목록을 불러오는 중입니다")
                        .task { await viewModel.load(trigger: "screen_appear") }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: "retry") } }
                case let .empty(message):
                    EmptyStateView(title: "최근 경기", message: message)
                case let .content(items), let .refreshing(items):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(items) { item in
                                Button {
                                    #if DEBUG
                                    print("[HomeSectionMore] itemTap=최근 경기 matchID=\(item.matchID)")
                                    #endif
                                    router.push(.matchDetail(matchID: item.matchID))
                                } label: {
                                    MatchCardView(
                                        title: item.role.shortLabel,
                                        dateText: item.scheduledAt.dottedDateText,
                                        isWin: item.result == "WIN",
                                        blueSummary: "블루 팀",
                                        redSummary: "레드 팀",
                                        detail: "KDA \(item.kda) · MMR \(Int(item.deltaMMR))"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
    }
}

fileprivate extension MatchStatus {
    var title: String {
        switch self {
        case .draft: return "드래프트"
        case .recruiting: return "모집 중"
        case .locked: return "확정 대기"
        case .balanced: return "밸런스 완료"
        case .inProgress: return "진행 중"
        case .resultPending: return "결과 대기"
        case .confirmed: return "확정"
        case .disputed: return "이의 제기"
        case .closed: return "종료"
        }
    }

    var tint: Color {
        switch self {
        case .draft: return AppPalette.textMuted
        case .recruiting: return AppPalette.accentBlue
        case .locked: return AppPalette.accentGold
        case .balanced: return AppPalette.accentGreen
        case .inProgress: return AppPalette.accentPurple
        case .resultPending: return AppPalette.accentOrange
        case .confirmed: return AppPalette.accentGreen
        case .disputed: return AppPalette.accentRed
        case .closed: return AppPalette.textMuted
        }
    }
}

fileprivate struct SelectableChipButton: View {
    let title: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterChipView(title: title, tint: tint, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

fileprivate enum GroupEditorMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create: return "내전 방 생성"
        case .edit: return "내전 방 수정"
        }
    }

    var submitTitle: String {
        switch self {
        case .create: return "생성"
        case .edit: return "저장"
        }
    }
}

fileprivate struct GroupEditorDraft {
    var name = ""
    var description = ""
    var selectedRegion = "서울"
    var selectedMoodTags: Set<String> = ["빡겜"]
    var additionalTags = ""
    var visibility: GroupVisibility = .private
    var joinPolicy: JoinPolicy = .inviteOnly

    init(group: GroupSummary? = nil) {
        guard let group else { return }
        name = group.name
        description = group.description ?? ""
        selectedRegion = group.tags.first(where: { RecruitOptionCatalog.regions.contains($0) }) ?? "서울"
        let moodTags = Set(group.tags.filter { RecruitOptionCatalog.moodTags.contains($0) })
        selectedMoodTags = moodTags.isEmpty ? ["빡겜"] : moodTags
        additionalTags = group.tags
            .filter { !RecruitOptionCatalog.regions.contains($0) && !RecruitOptionCatalog.moodTags.contains($0) }
            .joined(separator: ",")
        visibility = group.visibility
        joinPolicy = group.joinPolicy
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAdditionalTags: [String] {
        additionalTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var composedTags: [String] {
        Array(([selectedRegion] + selectedMoodTags.sorted() + normalizedAdditionalTags).prefix(8))
    }
}

fileprivate struct GroupEditorSheet: View {
    let mode: GroupEditorMode
    @Binding var draft: GroupEditorDraft
    let errorMessage: String?
    let isSubmitting: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    private let gridColumns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("방 이름", text: $draft.name)
                    TextField("설명", text: $draft.description, axis: .vertical)
                }

                Section("지역") {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(RecruitOptionCatalog.regions, id: \.self) { region in
                            SelectableChipButton(
                                title: region,
                                tint: AppPalette.accentBlue,
                                isSelected: draft.selectedRegion == region
                            ) {
                                draft.selectedRegion = region
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("성향 태그") {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(RecruitOptionCatalog.moodTags, id: \.self) { tag in
                            SelectableChipButton(
                                title: tag,
                                tint: AppPalette.accentPurple,
                                isSelected: draft.selectedMoodTags.contains(tag)
                            ) {
                                if draft.selectedMoodTags.contains(tag) {
                                    draft.selectedMoodTags.remove(tag)
                                } else {
                                    draft.selectedMoodTags.insert(tag)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("추가 태그 (쉼표 구분)", text: $draft.additionalTags)
                }

                Section("공개 설정") {
                    Picker("공개 여부", selection: $draft.visibility) {
                        Text(GroupVisibility.private.title).tag(GroupVisibility.private)
                        Text(GroupVisibility.public.title).tag(GroupVisibility.public)
                    }
                    Picker("참여 방식", selection: $draft.joinPolicy) {
                        ForEach(JoinPolicy.allCases, id: \.self) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTypography.body(12, weight: .semibold))
                            .foregroundStyle(AppPalette.accentRed)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: onClose)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSubmit) {
                        if isSubmitting {
                            ProgressView()
                                .tint(AppPalette.accentBlue)
                        } else {
                            Text(mode.submitTitle)
                        }
                    }
                    .disabled(draft.normalizedName.count < 2 || isSubmitting)
                }
            }
        }
    }
}

fileprivate enum RecruitEditorMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create: return "모집글 작성"
        case .edit: return "모집글 수정"
        }
    }

    var submitTitle: String {
        switch self {
        case .create: return "등록"
        case .edit: return "저장"
        }
    }
}

fileprivate struct RecruitEditorDraft {
    var postType: RecruitingPostType
    var title = ""
    var body = ""
    var selectedPositions: Set<String> = ["MID", "SUPPORT"]
    var selectedTags: Set<String> = ["빡겜"]
    var additionalTags = ""
    var isScheduledAtEnabled = false
    var scheduledAt = Date()

    init(postType: RecruitingPostType, post: RecruitPost? = nil) {
        self.postType = postType
        guard let post else { return }
        self.postType = post.postType
        title = post.title
        body = post.body ?? ""
        let positions = Set(post.requiredPositions.filter { RecruitOptionCatalog.positions.contains($0) })
        selectedPositions = positions.isEmpty ? ["MID", "SUPPORT"] : positions
        let knownTags = Set(post.tags.filter { RecruitOptionCatalog.moodTags.contains($0) })
        selectedTags = knownTags.isEmpty ? ["빡겜"] : knownTags
        additionalTags = post.tags
            .filter { !RecruitOptionCatalog.moodTags.contains($0) }
            .joined(separator: ",")
        if let scheduledAt = post.scheduledAt {
            isScheduledAtEnabled = true
            self.scheduledAt = scheduledAt
        }
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAdditionalTags: [String] {
        additionalTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var requiredPositions: [String] {
        selectedPositions.sorted()
    }

    var composedTags: [String] {
        Array((selectedTags.sorted() + normalizedAdditionalTags).prefix(8))
    }

    var effectiveScheduledAt: Date? {
        isScheduledAtEnabled ? scheduledAt : nil
    }
}

fileprivate struct RecruitEditorSheet: View {
    let mode: RecruitEditorMode
    @Binding var draft: RecruitEditorDraft
    let errorMessage: String?
    let isSubmitting: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    private let gridColumns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    HStack {
                        Text("모집 유형")
                        Spacer()
                        Text(draft.postType.title)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                    TextField("제목", text: $draft.title)
                    TextField("본문", text: $draft.body, axis: .vertical)
                }

                Section("포지션") {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(RecruitOptionCatalog.positions, id: \.self) { position in
                            SelectableChipButton(
                                title: position,
                                tint: AppPalette.accentBlue,
                                isSelected: draft.selectedPositions.contains(position)
                            ) {
                                if draft.selectedPositions.contains(position) {
                                    draft.selectedPositions.remove(position)
                                } else {
                                    draft.selectedPositions.insert(position)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("성향 태그") {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(RecruitOptionCatalog.moodTags, id: \.self) { tag in
                            SelectableChipButton(
                                title: tag,
                                tint: AppPalette.accentPurple,
                                isSelected: draft.selectedTags.contains(tag)
                            ) {
                                if draft.selectedTags.contains(tag) {
                                    draft.selectedTags.remove(tag)
                                } else {
                                    draft.selectedTags.insert(tag)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("추가 태그 (쉼표 구분)", text: $draft.additionalTags)
                }

                Section("예정 시간") {
                    Toggle("예정 시간 설정", isOn: $draft.isScheduledAtEnabled)
                    if draft.isScheduledAtEnabled {
                        DatePicker("예정 시간", selection: $draft.scheduledAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTypography.body(12, weight: .semibold))
                            .foregroundStyle(AppPalette.accentRed)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: onClose)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSubmit) {
                        if isSubmitting {
                            ProgressView()
                                .tint(AppPalette.accentBlue)
                        } else {
                            Text(mode.submitTitle)
                        }
                    }
                    .disabled(draft.normalizedTitle.count < 2 || draft.requiredPositions.isEmpty || isSubmitting)
                }
            }
        }
    }
}

fileprivate enum RecruitFilterSheet: String, Identifiable {
    case date
    case positions
    case regions
    case tags

    var id: String { rawValue }
}

struct GroupMainScreen: View {
    private enum ActiveSheet: String, Identifiable {
        case createGroup

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: GroupMainViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var activeSheet: ActiveSheet?
    @State private var groupEditorDraft = GroupEditorDraft()
    @State private var createGroupErrorMessage: String?
    @State private var pendingCreatedGroupID: String?

    var body: some View {
        TabRootScaffold(title: AppTab.match.title, trailingAction: createGroupHeaderAction) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "그룹을 불러오는 중입니다")
                        .task { await viewModel.load() }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
                case let .empty(message):
                    VStack(spacing: 0) {
                        StatusBarView()
                        EmptyStateView(title: "그룹", message: message, actionTitle: "그룹 생성") {
                            presentCreateGroupEntry(source: "empty_state")
                        }
                    }
                case let .content(groups), let .refreshing(groups):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            VStack(spacing: 16) {
                                ForEach(groups) { group in
                                    Button {
                                        session.openGroupDetailIfAccessible(group, router: router)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(group.name)
                                                    .font(AppTypography.body(16, weight: .semibold))
                                                Spacer()
                                                if group.tags.contains("빡겜") {
                                                    tagBadge("빡겜", tint: AppPalette.accentGreen)
                                                }
                                            }
                                            Text("멤버 \(group.memberCount)명 · \(group.tags.joined(separator: " · "))")
                                                .font(AppTypography.body(13))
                                                .foregroundStyle(AppPalette.textSecondary)
                                            Text("최근 내전: \(group.recentMatches > 0 ? "\(group.recentMatches)회 진행" : "기록 없음")")
                                                .font(AppTypography.body(12))
                                                .foregroundStyle(group.recentMatches > 0 ? AppPalette.accentBlue : AppPalette.textMuted)
                                        }
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(AppPalette.bgCard)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                    }
                    .refreshable { await viewModel.load(force: true) }
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: handleCreateGroupSheetDismissed) { sheet in
            switch sheet {
            case .createGroup:
                groupCreationSheet
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            guard newValue == .createGroup else { return }
            debugCreateGroup("showModal=createGroup")
            session.requestModalPresentation(.groupCreate)
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
    }

    private var createGroupHeaderAction: TabHeaderAction {
        TabHeaderAction(systemName: "plus", accessibilityLabel: "그룹 생성") {
            presentCreateGroupEntry(source: "header")
        }
    }

    private var groupCreationSheet: some View {
        GroupEditorSheet(
            mode: .create,
            draft: $groupEditorDraft,
            errorMessage: createGroupErrorMessage,
            isSubmitting: isCreateGroupSubmitInFlight,
            onClose: { dismissCreateGroupSheet(reason: "close_button") },
            onSubmit: submitCreateGroup
        )
    }

    private var isCreateGroupSubmitInFlight: Bool {
        if case .inProgress = viewModel.actionState {
            return true
        }
        return false
    }

    private var isCreateGroupSubmitDisabled: Bool {
        groupEditorDraft.normalizedName.count < 2 || isCreateGroupSubmitInFlight
    }

    private func presentCreateGroupEntry(source: String) {
        debugCreateGroup("entryTap source=\(source)")
        createGroupErrorMessage = nil
        guard session.isAuthenticated else {
            debugCreateGroup("auth=guest")
            debugCreateGroup("showModal=loginPrompt")
            session.requireAuthentication(for: .groupManagement)
            return
        }
        debugCreateGroup("auth=authenticated")
        resetCreateGroupDraft()
        activeSheet = .createGroup
    }

    private func submitCreateGroup() {
        debugCreateGroup("tap")
        createGroupErrorMessage = nil

        guard groupEditorDraft.normalizedName.count >= 2 else {
            debugCreateGroup("validation=failed reason=name_too_short")
            createGroupErrorMessage = "그룹 이름은 2자 이상 입력해주세요."
            debugCreateGroup("showInlineError")
            return
        }

        debugCreateGroup("validation=passed")

        guard session.isAuthenticated else {
            debugCreateGroup("auth=guest")
            debugCreateGroup("showModal=loginPrompt")
            session.requireAuthentication(for: .groupManagement)
            dismissCreateGroupSheet(reason: "auth_required")
            return
        }

        debugCreateGroup("auth=authenticated")

        Task {
            let result = await viewModel.createGroup(
                name: groupEditorDraft.normalizedName,
                description: groupEditorDraft.normalizedDescription,
                tags: groupEditorDraft.composedTags
            )

            switch result {
            case let .success(group):
                pendingCreatedGroupID = group.id
                dismissCreateGroupSheet(reason: "success")
            case let .failure(message):
                createGroupErrorMessage = message
                debugCreateGroup("showInlineError")
            case .requiresAuthentication:
                debugCreateGroup("auth=reauthentication_required")
                dismissCreateGroupSheet(reason: "reauthentication_required")
            }
        }
    }

    private func dismissCreateGroupSheet(reason: String) {
        guard activeSheet != nil else { return }
        debugCreateGroup("dismiss requested reason=\(reason)")
        activeSheet = nil
    }

    private func handleCreateGroupSheetDismissed() {
        debugCreateGroup("dismiss")
        session.handleModalDismissed(.groupCreate)
        resetCreateGroupDraft()
        if let pendingCreatedGroupID {
            self.pendingCreatedGroupID = nil
            router.push(.groupDetail(pendingCreatedGroupID))
        }
    }

    private func resetCreateGroupDraft() {
        groupEditorDraft = GroupEditorDraft()
        createGroupErrorMessage = nil
    }

    private func debugCreateGroup(_ message: String) {
        #if DEBUG
        print("[CreateGroup] \(message)")
        #endif
    }

    private func tagBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(AppPalette.bgPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint)
            .clipShape(Capsule())
    }
}

struct GroupDetailScreen: View {
    @ObservedObject var viewModel: GroupDetailViewModel
    @ObservedObject var router: AppRouter
    let onGroupUpdated: (GroupSummary) -> Void
    let onGroupDeleted: (String) -> Void
    @State private var inviteUserID = ""
    @State private var showsInviteSheet = false
    @State private var showsPowerGuideSheet = false
    @State private var showsManagementDialog = false
    @State private var showsDeleteConfirmation = false
    @State private var showsEditorSheet = false
    @State private var groupEditorDraft = GroupEditorDraft()
    @State private var groupEditorErrorMessage: String?

    var body: some View {
        screenScaffold(
            title: "롤내전모임",
            onBack: router.pop,
            rightSystemImage: viewModel.isEditVisible ? "ellipsis.circle" : nil,
            onRightTap: { showsManagementDialog = true }
        ) {
            switch viewModel.state {
            case .initial:
                LoadingStateView(title: "그룹 상세를 불러오는 중입니다")
                    .task { await viewModel.load(trigger: .screenAppear) }
            case .loading:
                LoadingStateView(title: "그룹 상세를 불러오는 중입니다")
            case let .error(error):
                ErrorStateView(
                    error: error,
                    retry: { Task { await viewModel.load(force: true, trigger: .retry) } },
                    secondaryAction: error.isGroupNotFoundResource
                        ? ErrorStateAction(title: "목록으로 돌아가기", action: dismissInvalidGroupContext)
                        : nil
                )
            case .empty:
                EmptyStateView(title: "그룹", message: "표시할 그룹이 없습니다.")
            case let .content(snapshot), let .refreshing(snapshot):
                let guide = PowerViewStateBuilder.groupGuide()
                let memberRows = snapshot.members.map { member in
                    PowerViewStateBuilder.groupMember(
                        member: member,
                        powerProfile: snapshot.powerProfiles[member.userID]
                    )
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(snapshot.group.name)
                                    .font(AppTypography.heading(18, weight: .bold))
                                Spacer()
                                tagBadge(snapshot.group.tags.first ?? "그룹")
                            }
                            if let description = snapshot.group.description {
                                Text(description)
                                    .font(AppTypography.body(13))
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                            HStack(spacing: 16) {
                                statBlock("\(snapshot.group.memberCount)", label: "멤버")
                                statBlock("\(snapshot.group.recentMatches)", label: "내전")
                                statBlock(snapshot.group.tags.first ?? "-", label: "성향")
                            }
                        }
                        .padding(16)
                        .background(AppPalette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack(spacing: 8) {
                            Button("내전 생성") {
                                Task {
                                    if let match = await viewModel.createMatch() {
                                        router.push(.matchLobby(groupID: viewModel.groupID, matchID: match.id))
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button("멤버 초대") {
                                showsInviteSheet = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("멤버 (\(snapshot.members.count))")
                                    .font(AppTypography.heading(16, weight: .bold))
                                    .foregroundStyle(AppPalette.textPrimary)
                                Spacer()
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                        showsPowerGuideSheet = true
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("파워 기준 안내")
                                            .font(AppTypography.body(12, weight: .semibold))
                                    }
                                    .foregroundStyle(AppPalette.accentBlue)
                                }
                                .buttonStyle(.plain)
                            }

                            GroupPowerGuideCard(guide: guide)

                            VStack(spacing: 8) {
                                ForEach(memberRows) { row in
                                    GroupPowerMemberRow(row: row)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeaderView(title: "지난 내전", showsTrailing: false)
                            if let history = snapshot.latestMatch {
                                Button {
                                    router.push(.matchDetail(matchID: history.matchID))
                                } label: {
                                    MatchCardView(
                                        title: snapshot.group.name,
                                        dateText: history.scheduledAt.dottedDateText,
                                        isWin: history.result == "WIN",
                                        blueSummary: "블루 팀",
                                        redSummary: "레드 팀",
                                        detail: "KDA \(history.kda) · \(history.role.shortLabel)"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("그룹 단위 최근 경기 목록 API가 없어 현재는 내 기록 기준 최근 경기만 표시합니다.")
                                    .font(AppTypography.body(12))
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showsInviteSheet) {
            NavigationStack {
                Form {
                    TextField("추가할 사용자 ID", text: $inviteUserID)
                    Text("실제 서버는 userId 기반 멤버 추가만 지원합니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기") { showsInviteSheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("추가") {
                            Task {
                                await viewModel.inviteMember(userID: inviteUserID)
                                showsInviteSheet = false
                            }
                        }
                        .disabled(inviteUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showsEditorSheet, onDismiss: clearGroupEditorError) {
            GroupEditorSheet(
                mode: .edit,
                draft: $groupEditorDraft,
                errorMessage: groupEditorErrorMessage,
                isSubmitting: viewModel.isMutationInFlight,
                onClose: { showsEditorSheet = false },
                onSubmit: submitGroupUpdate
            )
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
        .overlay {
            if showsPowerGuideSheet {
                let guide = PowerViewStateBuilder.groupGuide()
                DimmedBottomSheet(
                    title: guide.title,
                    onDismiss: { showsPowerGuideSheet = false },
                    maxHeightRatio: 0.42
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupPowerGuideCard(guide: guide)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("안내")
                                .font(AppTypography.body(13, weight: .semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                            Text("그룹 화면에 보이는 값은 멤버 구성이 바뀌지 않도록 비교 기준을 유지하기 위한 그룹 기준 파워예요. 그룹 스냅샷이 아직 없으면 최신 종합 파워로 대체되고, 홈과 프로필에서는 개인 최신 종합 파워를 확인할 수 있어요.")
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(AppPalette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .confirmationDialog("내전 방 관리", isPresented: $showsManagementDialog, titleVisibility: .visible) {
            Button("수정") { presentGroupEditor() }
            Button("삭제", role: .destructive) { showsDeleteConfirmation = true }
            Button("취소", role: .cancel) {}
        }
        .alert("이 내전 방을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task { await confirmGroupDelete() }
            }
        } message: {
            Text("삭제한 내전 방은 복구할 수 없습니다.")
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showsPowerGuideSheet)
    }

    private func statBlock(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.heading(18, weight: .bold))
            Text(label)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(AppPalette.accentGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppPalette.bgTertiary)
            .clipShape(Capsule())
    }

    private func presentGroupEditor() {
        guard let snapshot = viewModel.state.value else { return }
        groupEditorDraft = GroupEditorDraft(group: snapshot.group)
        groupEditorErrorMessage = nil
        showsEditorSheet = true
    }

    private func submitGroupUpdate() {
        groupEditorErrorMessage = nil
        Task {
            let updatedGroup = await viewModel.updateGroup(
                name: groupEditorDraft.normalizedName,
                description: groupEditorDraft.normalizedDescription,
                visibility: groupEditorDraft.visibility,
                joinPolicy: groupEditorDraft.joinPolicy,
                tags: groupEditorDraft.composedTags
            )
            if let updatedGroup {
                onGroupUpdated(updatedGroup)
                showsEditorSheet = false
                return
            }
            if case let .failure(message) = viewModel.actionState {
                groupEditorErrorMessage = message
            }
        }
    }

    private func confirmGroupDelete() async {
        guard let deletedGroupID = await viewModel.deleteGroup() else { return }
        showsDeleteConfirmation = false
        showsManagementDialog = false
        showsEditorSheet = false
        onGroupDeleted(deletedGroupID)
        router.removeRoutes(referencingGroupID: deletedGroupID)
    }

    private func clearGroupEditorError() {
        groupEditorErrorMessage = nil
    }

    private func dismissInvalidGroupContext() {
        onGroupDeleted(viewModel.groupID)
        router.removeRoutes(referencingGroupID: viewModel.groupID)
    }
}

struct RecruitBoardScreen: View {
    private enum ActiveSheet: String, Identifiable {
        case createPost

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: RecruitBoardViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var activeSheet: ActiveSheet?
    @State private var recruitEditorDraft = RecruitEditorDraft(postType: .memberRecruit)
    @State private var createPostErrorMessage: String?
    @State private var pendingCreatedPost: RecruitPost?
    @State private var activeCreateGroupID: String?
    @State private var activeFilterSheet: RecruitFilterSheet?
    @State private var filterDraft = RecruitBoardFilterState.defaultValue

    var body: some View {
        TabRootScaffold(title: AppTab.recruit.title, trailingAction: createRecruitHeaderAction) {
            Group {
                switch viewModel.state {
                case .initial:
                    LoadingStateView(title: "모집글을 불러오는 중입니다")
                        .task { await viewModel.load(trigger: .screenAppear) }
                case .loading:
                    LoadingStateView(title: "모집글을 불러오는 중입니다")
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: .retry) } }
                case let .empty(message):
                    recruitBoardContent(snapshot: nil, emptyMessage: message)
                case let .content(snapshot), let .refreshing(snapshot):
                    recruitBoardContent(snapshot: snapshot, emptyMessage: nil)
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: handleCreateRecruitSheetDismissed) { sheet in
            switch sheet {
            case .createPost:
                createSheet
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            guard newValue == .createPost else { return }
            debugCreateRecruitingPost("showModal=createRecruitingPost")
            session.requestModalPresentation(.recruitCreate)
        }
        .onAppear {
            debugRecruitScreen("onAppear currentPostType=\(viewModel.selectedType.rawValue)")
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
        .overlay {
            if let activeFilterSheet {
                DimmedBottomSheet(
                    title: filterSheetTitle(for: activeFilterSheet),
                    onDismiss: { self.activeFilterSheet = nil },
                    maxHeightRatio: 0.66
                ) {
                    filterSheetContent(activeFilterSheet)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: activeFilterSheet)
    }

    private var createRecruitHeaderAction: TabHeaderAction {
        TabHeaderAction(systemName: "square.and.pencil", accessibilityLabel: "모집글 작성") {
            presentCreateRecruitEntry(source: "header")
        }
    }

    private func typeButton(_ type: RecruitingPostType) -> some View {
        Button {
            Task { await viewModel.switchType(type) }
        } label: {
            Text(type.title)
                .font(AppTypography.body(13, weight: viewModel.selectedType == type ? .semibold : .regular))
                .foregroundStyle(viewModel.selectedType == type ? Color.white : AppPalette.textMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(viewModel.selectedType == type ? AppPalette.accentBlue : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var createSheet: some View {
        RecruitEditorSheet(
            mode: .create,
            draft: $recruitEditorDraft,
            errorMessage: createPostErrorMessage,
            isSubmitting: isCreateRecruitSubmitInFlight,
            onClose: { dismissCreateRecruitSheet(reason: "close_button") },
            onSubmit: submitCreateRecruitingPost
        )
    }

    private var isCreateRecruitSubmitInFlight: Bool {
        if case .inProgress = viewModel.actionState {
            return true
        }
        return false
    }

    private func presentCreateRecruitEntry(source: String) {
        debugCreateRecruitingPost("entryTap source=\(source)")
        createPostErrorMessage = nil
        guard session.isAuthenticated else {
            debugCreateRecruitingPost("auth=guest")
            debugCreateRecruitingPost("showModal=loginPrompt")
            session.requireAuthentication(for: .recruitingWrite)
            return
        }
        debugCreateRecruitingPost("auth=authenticated")
        guard let groupID = viewModel.resolveCreatePostGroupContext() else { return }
        resetCreateRecruitDraft()
        activeCreateGroupID = groupID
        activeSheet = .createPost
    }

    private func submitCreateRecruitingPost() {
        debugCreateRecruitingPost("tap")
        createPostErrorMessage = nil

        guard recruitEditorDraft.normalizedTitle.count >= 2 else {
            debugCreateRecruitingPost("validation=failed reason=title_too_short")
            createPostErrorMessage = "제목은 2자 이상 입력해주세요."
            debugCreateRecruitingPost("showInlineError")
            return
        }

        guard !recruitEditorDraft.requiredPositions.isEmpty else {
            debugCreateRecruitingPost("validation=failed reason=positions_empty")
            createPostErrorMessage = "최소 한 개 이상의 포지션을 입력해주세요."
            debugCreateRecruitingPost("showInlineError")
            return
        }

        guard let groupID = viewModel.validateCreatePostGroupContext(activeCreateGroupID) else {
            dismissCreateRecruitSheet(reason: "invalid_group_context")
            return
        }

        debugCreateRecruitingPost("validation=passed")

        guard session.isAuthenticated else {
            debugCreateRecruitingPost("auth=guest")
            debugCreateRecruitingPost("showModal=loginPrompt")
            session.requireAuthentication(for: .recruitingWrite)
            dismissCreateRecruitSheet(reason: "auth_required")
            return
        }

        debugCreateRecruitingPost("auth=authenticated")

        Task {
            let result = await viewModel.createPost(
                groupID: groupID,
                title: recruitEditorDraft.normalizedTitle,
                body: recruitEditorDraft.normalizedBody,
                tags: recruitEditorDraft.composedTags,
                scheduledAt: recruitEditorDraft.effectiveScheduledAt,
                positions: recruitEditorDraft.requiredPositions
            )

            switch result {
            case let .success(post):
                pendingCreatedPost = post
                dismissCreateRecruitSheet(reason: "success")
            case .invalidGroupContext:
                dismissCreateRecruitSheet(reason: "invalid_group_context")
            case let .failure(message):
                createPostErrorMessage = message
                debugCreateRecruitingPost("showInlineError")
            case .requiresAuthentication:
                debugCreateRecruitingPost("auth=reauthentication_required")
                dismissCreateRecruitSheet(reason: "reauthentication_required")
            }
        }
    }

    private func dismissCreateRecruitSheet(reason: String) {
        guard activeSheet != nil else { return }
        debugCreateRecruitingPost("dismiss requested reason=\(reason)")
        activeSheet = nil
    }

    private func handleCreateRecruitSheetDismissed() {
        debugCreateRecruitingPost("dismiss")
        debugRecruitScreen("dismiss create sheet")
        session.handleModalDismissed(.recruitCreate)
        resetCreateRecruitDraft()
        activeCreateGroupID = nil
        if let pendingCreatedPost {
            self.pendingCreatedPost = nil
            viewModel.handleCreateSuccess(pendingCreatedPost)
            Task {
                await viewModel.load(force: true, trigger: .createSheetDismissed)
            }
        }
    }

    private func resetCreateRecruitDraft() {
        recruitEditorDraft = RecruitEditorDraft(postType: viewModel.selectedType)
        createPostErrorMessage = nil
    }

    @ViewBuilder
    private func recruitBoardContent(snapshot: RecruitBoardSnapshot?, emptyMessage: String?) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    HStack(spacing: 4) {
                        typeButton(.memberRecruit)
                        typeButton(.opponentRecruit)
                    }
                    .padding(3)
                    .background(AppPalette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(.date, title: dateFilterChipTitle)
                            filterChip(.positions, title: positionsFilterChipTitle)
                            filterChip(.regions, title: regionsFilterChipTitle)
                            filterChip(.tags, title: tagsFilterChipTitle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let snapshot {
                        ForEach(snapshot.posts) { post in
                            recruitPostCard(post, snapshot: snapshot)
                        }
                    } else if let emptyMessage {
                        EmptyStateView(title: "모집", message: emptyMessage, actionTitle: "글 작성") {
                            presentCreateRecruitEntry(source: "empty_state")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
    }

    private func recruitPostCard(_ post: RecruitPost, snapshot: RecruitBoardSnapshot) -> some View {
        Button {
            debugRecruitScreen("navigate detail postId=\(post.id)")
            session.openProtectedRoute(.recruitDetail(postID: post.id), requirement: .recruitingWrite, router: router)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(post.title)
                        .font(AppTypography.body(14, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Spacer()
                    if post.tags.contains("급구") {
                        Text("급구")
                            .font(AppTypography.body(11, weight: .semibold))
                            .foregroundStyle(AppPalette.bgPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppPalette.accentGreen)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(snapshot.groupNamesByID[post.groupID] ?? "그룹 정보 없음")
                    if let region = snapshot.groupRegionsByID[post.groupID] {
                        Text(region)
                    }
                    if let scheduledAt = post.scheduledAt {
                        Text(scheduledAt.shortDateText)
                            .foregroundStyle(post.tags.contains("급구") ? AppPalette.accentRed : AppPalette.accentBlue)
                    }
                }
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)

                HStack(spacing: 6) {
                    ForEach(post.requiredPositions, id: \.self) { value in
                        Text(value)
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppPalette.bgTertiary)
                            .clipShape(Capsule())
                    }
                    ForEach(post.tags.filter { !$0.isEmpty }, id: \.self) { value in
                        Text(value)
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.accentPurple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppPalette.bgTertiary)
                            .clipShape(Capsule())
                    }
                }
                Text(post.status == .open ? "모집 중" : post.status.rawValue)
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(post.tags.contains("급구") ? AppPalette.accentRed : AppPalette.accentOrange)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(post.tags.contains("급구") ? AppPalette.accentGreen : AppPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ sheet: RecruitFilterSheet, title: String) -> some View {
        Button {
            filterDraft = viewModel.filterState
            activeFilterSheet = sheet
        } label: {
            FilterChipView(title: title, tint: filterChipTint(for: sheet), isSelected: isFilterActive(sheet))
        }
        .buttonStyle(.plain)
    }

    private var dateFilterChipTitle: String {
        let dateFilter = viewModel.filterState.selectedDateFilter
        switch dateFilter.preset {
        case .all:
            return dateFilter.includesUnscheduledPosts ? "날짜" : "날짜 · 미정 제외"
        case .today:
            return "오늘"
        case .thisWeek:
            return "이번 주"
        case .specificDate:
            return dateFilter.selectedDate.shortDateText
        }
    }

    private var positionsFilterChipTitle: String {
        let count = viewModel.filterState.selectedPositions.count
        return count == 0 ? "포지션" : "포지션 \(count)"
    }

    private var regionsFilterChipTitle: String {
        let regions = viewModel.filterState.selectedRegions.sorted()
        switch regions.count {
        case 0:
            return "지역"
        case 1:
            return regions[0]
        default:
            return "지역 \(regions.count)"
        }
    }

    private var tagsFilterChipTitle: String {
        let count = viewModel.filterState.selectedTags.count
        return count == 0 ? "성향" : "성향 \(count)"
    }

    private func filterChipTint(for sheet: RecruitFilterSheet) -> Color {
        switch sheet {
        case .date, .positions:
            return AppPalette.accentBlue
        case .regions, .tags:
            return AppPalette.accentPurple
        }
    }

    private func isFilterActive(_ sheet: RecruitFilterSheet) -> Bool {
        switch sheet {
        case .date:
            return !viewModel.filterState.selectedDateFilter.isDefault
        case .positions:
            return !viewModel.filterState.selectedPositions.isEmpty
        case .regions:
            return !viewModel.filterState.selectedRegions.isEmpty
        case .tags:
            return !viewModel.filterState.selectedTags.isEmpty
        }
    }

    private func filterSheetTitle(for sheet: RecruitFilterSheet) -> String {
        switch sheet {
        case .date: return "날짜 필터"
        case .positions: return "포지션 필터"
        case .regions: return "지역 필터"
        case .tags: return "성향 필터"
        }
    }

    @ViewBuilder
    private func filterSheetContent(_ sheet: RecruitFilterSheet) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch sheet {
            case .date:
                dateFilterContent
            case .positions:
                selectionFilterContent(
                    options: RecruitOptionCatalog.positions,
                    selectedValues: filterDraft.selectedPositions,
                    tint: AppPalette.accentBlue
                ) { toggleFilterSelection($0, sheet: .positions) }
            case .regions:
                selectionFilterContent(
                    options: RecruitOptionCatalog.regions,
                    selectedValues: filterDraft.selectedRegions,
                    tint: AppPalette.accentPurple
                ) { toggleFilterSelection($0, sheet: .regions) }
            case .tags:
                selectionFilterContent(
                    options: RecruitOptionCatalog.moodTags,
                    selectedValues: filterDraft.selectedTags,
                    tint: AppPalette.accentPurple
                ) { toggleFilterSelection($0, sheet: .tags) }
            }

            HStack(spacing: 10) {
                Button("취소") {
                    activeFilterSheet = nil
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("초기화") {
                    resetFilterDraft(sheet)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("적용") {
                    applyFilterDraft(sheet)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var dateFilterContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(RecruitDateFilterPreset.allCases, id: \.self) { preset in
                    SelectableChipButton(
                        title: dateFilterPresetTitle(preset),
                        tint: AppPalette.accentBlue,
                        isSelected: filterDraft.selectedDateFilter.preset == preset
                    ) {
                        filterDraft.selectedDateFilter.preset = preset
                    }
                }
            }
            Toggle("예정 시간 미정 글 포함", isOn: $filterDraft.selectedDateFilter.includesUnscheduledPosts)
                .tint(AppPalette.accentBlue)
            if filterDraft.selectedDateFilter.preset == .specificDate {
                DatePicker(
                    "날짜 선택",
                    selection: $filterDraft.selectedDateFilter.selectedDate,
                    displayedComponents: .date
                )
            }
        }
    }

    private func selectionFilterContent(
        options: [String],
        selectedValues: Set<String>,
        tint: Color,
        onToggle: @escaping (String) -> Void
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { value in
                SelectableChipButton(title: value, tint: tint, isSelected: selectedValues.contains(value)) {
                    onToggle(value)
                }
            }
        }
    }

    private func dateFilterPresetTitle(_ preset: RecruitDateFilterPreset) -> String {
        switch preset {
        case .all: return "전체"
        case .today: return "오늘"
        case .thisWeek: return "이번 주"
        case .specificDate: return "날짜 선택"
        }
    }

    private func toggleFilterSelection(_ value: String, sheet: RecruitFilterSheet) {
        switch sheet {
        case .positions:
            if filterDraft.selectedPositions.contains(value) {
                filterDraft.selectedPositions.remove(value)
            } else {
                filterDraft.selectedPositions.insert(value)
            }
        case .regions:
            if filterDraft.selectedRegions.contains(value) {
                filterDraft.selectedRegions.remove(value)
            } else {
                filterDraft.selectedRegions.insert(value)
            }
        case .tags:
            if filterDraft.selectedTags.contains(value) {
                filterDraft.selectedTags.remove(value)
            } else {
                filterDraft.selectedTags.insert(value)
            }
        case .date:
            break
        }
    }

    private func resetFilterDraft(_ sheet: RecruitFilterSheet) {
        switch sheet {
        case .date:
            filterDraft.selectedDateFilter = RecruitDateFilter()
        case .positions:
            filterDraft.selectedPositions.removeAll()
        case .regions:
            filterDraft.selectedRegions.removeAll()
        case .tags:
            filterDraft.selectedTags.removeAll()
        }
    }

    private func applyFilterDraft(_ sheet: RecruitFilterSheet) {
        let reason: RecruitBoardFilterChangeReason
        switch sheet {
        case .date: reason = .date
        case .positions: reason = .positions
        case .regions: reason = .regions
        case .tags: reason = .tags
        }
        Task {
            await viewModel.applyFilters(filterDraft, reason: reason)
            activeFilterSheet = nil
        }
    }

    private func debugCreateRecruitingPost(_ message: String) {
        #if DEBUG
        print("[CreateRecruitingPost] \(message)")
        #endif
    }

    private func debugRecruitScreen(_ message: String) {
        #if DEBUG
        print("[RecruitScreen] \(message)")
        #endif
    }
}

struct RecruitDetailScreen: View {
    @ObservedObject var viewModel: RecruitDetailViewModel
    @ObservedObject var router: AppRouter
    let onUpdateSuccess: (RecruitPost) -> Void
    let onDeleteSuccess: (RecruitPost) -> Void
    @State private var isDeleteConfirmationPresented = false
    @State private var isManagementDialogPresented = false
    @State private var isEditorPresented = false
    @State private var recruitEditorDraft = RecruitEditorDraft(postType: .memberRecruit)
    @State private var recruitEditorErrorMessage: String?

    var body: some View {
        screenScaffold(
            title: "모집 상세",
            onBack: router.pop,
            rightSystemImage: viewModel.isEditVisible || viewModel.isDeleteVisible ? "ellipsis.circle" : nil,
            onRightTap: { isManagementDialogPresented = true }
        ) {
            switch viewModel.state {
            case .initial:
                LoadingStateView(title: "모집 상세를 불러오는 중입니다")
                    .task { await viewModel.load(trigger: .screenAppear) }
            case .loading:
                LoadingStateView(title: "모집 상세를 불러오는 중입니다")
            case let .error(error):
                ErrorStateView(error: error) { Task { await viewModel.load(force: true, trigger: .retry) } }
            case let .empty(message):
                EmptyStateView(title: "모집 상세", message: message)
            case let .content(post), let .refreshing(post):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.title)
                                .font(AppTypography.heading(18, weight: .bold))
                            HStack(spacing: 12) {
                                Text(post.groupName)
                                Text(post.scheduledAtText)
                                if let authorName = post.authorName {
                                    Text(authorName)
                                }
                            }
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("모집 정보")
                                .font(AppTypography.body(14, weight: .semibold))
                            infoRow("필요 포지션", value: post.requiredPositionsText)
                            infoRow("상태", value: post.statusText)
                            infoRow("분위기", value: post.moodTagsText)
                            infoRow("예정 시간", value: post.scheduledAtText)
                        }
                        .padding(16)
                        .background(AppPalette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("상세 설명")
                                .font(AppTypography.heading(15, weight: .bold))
                            Text(post.bodyText)
                                .font(AppTypography.body(13))
                                .foregroundStyle(AppPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("참가 신청") {
                            Task {
                                if let updatedPost = await viewModel.applyToRecruit() {
                                    onUpdateSuccess(updatedPost)
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.isApplyButtonEnabled)

                        Button("내전 생성") {
                            Task {
                                if let match = await viewModel.createMatch() {
                                    router.push(.matchLobby(groupID: post.groupID, matchID: match.id))
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(fill: AppPalette.accentPurple))
                        .disabled(!viewModel.isCreateMatchButtonEnabled)
                        .frame(maxWidth: 120)
                    }

                    if let note = viewModel.applyCapabilityNote {
                        Text(note)
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppPalette.bgSecondary)
            }
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: clearRecruitEditorError) {
            RecruitEditorSheet(
                mode: .edit,
                draft: $recruitEditorDraft,
                errorMessage: recruitEditorErrorMessage,
                isSubmitting: viewModel.isMutationInFlight,
                onClose: { isEditorPresented = false },
                onSubmit: submitRecruitUpdate
            )
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
        .confirmationDialog("모집글 관리", isPresented: $isManagementDialogPresented, titleVisibility: .visible) {
            if viewModel.isEditVisible {
                Button("수정") { presentRecruitEditor() }
            }
            if viewModel.isDeleteVisible {
                Button("삭제", role: .destructive) { promptDeleteConfirmation() }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("이 모집글을 삭제할까요?", isPresented: $isDeleteConfirmationPresented) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task { await confirmDelete() }
            }
        } message: {
            Text("삭제한 모집글은 복구할 수 없습니다.")
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(AppTypography.body(13))
    }

    private func promptDeleteConfirmation() {
        guard viewModel.beginDeleteConfirmation() else { return }
        isDeleteConfirmationPresented = true
    }

    private func presentRecruitEditor() {
        guard let draft = viewModel.makeEditorDraft() else { return }
        recruitEditorDraft = draft
        recruitEditorErrorMessage = nil
        isEditorPresented = true
    }

    private func submitRecruitUpdate() {
        recruitEditorErrorMessage = nil
        Task {
            let updatedPost = await viewModel.updatePost(
                title: recruitEditorDraft.normalizedTitle,
                body: recruitEditorDraft.normalizedBody,
                tags: recruitEditorDraft.composedTags,
                scheduledAt: recruitEditorDraft.effectiveScheduledAt,
                requiredPositions: recruitEditorDraft.requiredPositions
            )
            if let updatedPost {
                onUpdateSuccess(updatedPost)
                isEditorPresented = false
                return
            }
            if case let .failure(message) = viewModel.actionState {
                recruitEditorErrorMessage = message
            }
        }
    }

    private func confirmDelete() async {
        guard let deletedPost = await viewModel.deletePost() else { return }
        onDeleteSuccess(deletedPost)
        viewModel.didNavigateBackAfterDelete()
        router.pop()
    }

    private func clearRecruitEditorError() {
        recruitEditorErrorMessage = nil
    }
}

struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        TabRootScaffold(title: AppTab.history.title) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "경기 기록을 불러오는 중입니다")
                        .task { await viewModel.load() }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
                case let .empty(message):
                    VStack(spacing: 0) {
                        StatusBarView()
                        EmptyStateView(title: "기록", message: message)
                    }
                case let .content(content), let .refreshing(content):
                    historyContent(content)
                }
            }
        }
    }

    @ViewBuilder
    private func historyContent(_ content: HistoryContentState) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        FilterChipView(title: "전체", tint: AppPalette.accentBlue, isSelected: true)
                        FilterChipView(title: "최근", tint: AppPalette.textSecondary)
                        FilterChipView(title: "로컬", tint: AppPalette.textSecondary)
                        FilterChipView(title: "저장", tint: AppPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    switch content {
                    case let .authenticated(items):
                        ForEach(items) { item in
                            Button {
                                router.push(.matchDetail(matchID: item.matchID))
                            } label: {
                                MatchCardView(
                                    title: item.role.shortLabel,
                                    dateText: item.scheduledAt.dottedDateText,
                                    isWin: item.result == "WIN",
                                    blueSummary: "블루 팀",
                                    redSummary: "레드 팀",
                                    detail: "KDA \(item.kda) · MMR \(Int(item.deltaMMR))"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    case let .guest(items):
                        guestHistoryHint

                        ForEach(items) { item in
                            MatchCardView(
                                title: item.groupName,
                                dateText: item.savedAt.dottedDateText,
                                isWin: item.winningTeam == .blue,
                                blueSummary: "승리 팀 \(item.winningTeam == .blue ? "블루" : "레드")",
                                redSummary: "밸런스 \(item.balanceRating)/5",
                                detail: "로컬 저장 · MVP \(item.mvpUserID)"
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
    }

    private var guestHistoryHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("게스트 기록")
                .font(AppTypography.heading(15, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)
            Text("지금 보이는 기록은 이 기기에만 저장됩니다. 로그인하면 기록 저장과 기기 간 이어하기를 사용할 수 있어요.")
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("로그인하고 기록 동기화") {
                session.requireAuthentication(for: .profileHistory)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }
}

struct MatchDetailScreen: View {
    @ObservedObject var viewModel: MatchDetailViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        screenScaffold(title: "경기 상세", onBack: router.pop) {
            switch viewModel.state {
            case .initial, .loading:
                LoadingStateView(title: "경기 상세를 불러오는 중입니다")
                    .task { await viewModel.load() }
            case let .error(error):
                ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
            case .empty:
                EmptyStateView(title: "경기 상세", message: "경기 데이터를 찾을 수 없습니다.")
            case let .content(snapshot), let .refreshing(snapshot):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        resultSummaryCard(snapshot)

                        HStack(alignment: .top, spacing: 10) {
                            teamCard(side: .blue, snapshot: snapshot)
                            teamCard(side: .red, snapshot: snapshot)
                        }

                        powerDeltaSection(snapshot)
                    }
                    .padding(16)
                }

                Button("같은 인원으로 재매칭") {
                    Task {
                        if let match = await viewModel.rematch() {
                            router.push(.teamBalance(groupID: snapshot.match.groupID, matchID: match.id))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppPalette.accentPurple))
                .disabled(isActionInFlight)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppPalette.bgSecondary)
            }
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
    }

    private var isActionInFlight: Bool {
        if case .inProgress = viewModel.actionState {
            return true
        }
        return false
    }

    private func resultSummaryCard(_ snapshot: MatchDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.match.scheduledAt?.dottedDateText ?? Date().dottedDateText)
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(AppPalette.textMuted)
                    Text(viewModel.groupName(for: snapshot.match.groupID))
                        .font(AppTypography.heading(18, weight: .bold))
                        .foregroundStyle(AppPalette.textPrimary)
                }
                Spacer()
                resultBadge(snapshot)
            }

            HStack(alignment: .center, spacing: 12) {
                teamHeadline(title: "블루팀", tint: AppPalette.teamBlue)
                Text("VS")
                    .font(AppTypography.heading(15, weight: .bold))
                    .foregroundStyle(AppPalette.textMuted)
                teamHeadline(title: "레드팀", tint: AppPalette.teamRed)
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 10) {
                summaryTile(label: "MVP", value: mvpName(for: snapshot), tint: AppPalette.accentGold)
                summaryTile(label: "예측 밸런스", value: predictedBalanceText(for: snapshot), tint: AppPalette.accentBlue)
                summaryTile(label: "게임 밸런스", value: gameBalanceText(for: snapshot), tint: AppPalette.accentGreen)
                summaryTile(label: "실제 결과", value: actualResultText(for: snapshot), tint: winnerColor(for: snapshot))
            }

            if snapshot.cachedMetadata == nil {
                Text("MVP와 게임 밸런스는 이 기기에 저장된 기록이 있을 때만 표시됩니다.")
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1A2744), AppPalette.bgPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func summaryTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.body(10, weight: .semibold))
                .foregroundStyle(AppPalette.textMuted)
            Text(value)
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(value == "기록 없음" || value == "계산 전" ? AppPalette.textSecondary : tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appPanel(background: AppPalette.bgCard.opacity(0.92), radius: 12)
    }

    private func resultBadge(_ snapshot: MatchDetailSnapshot) -> some View {
        Text(resultStatusText(for: snapshot))
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(AppPalette.bgPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(resultStatusColor(for: snapshot))
            .clipShape(Capsule())
    }

    private func teamHeadline(title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTypography.heading(18, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
    }

    private func teamCard(side: TeamSide, snapshot: MatchDetailSnapshot) -> some View {
        let players = teamPlayers(side: side, snapshot: snapshot)
        let tint = side == .blue ? AppPalette.teamBlue : AppPalette.teamRed
        let background = side == .blue ? Color(hex: 0x0D1B2A) : Color(hex: 0x2A0D0D)

        return VStack(spacing: 0) {
            HStack {
                Text(side == .blue ? "블루 팀" : "레드 팀")
                    .font(AppTypography.heading(13, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                if winningTeam(for: snapshot) == side {
                    Text("WIN")
                        .font(AppTypography.body(10, weight: .bold))
                        .foregroundStyle(AppPalette.bgPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppPalette.accentGold)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(tint)

            VStack(spacing: 1) {
                ForEach(players, id: \.0.id) { player, stat in
                    HStack(spacing: 8) {
                        Text(player.assignedRole?.shortLabel ?? "-")
                            .font(AppTypography.body(10, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 30, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(player.nickname)
                                    .font(AppTypography.body(12, weight: .semibold))
                                    .foregroundStyle(AppPalette.textPrimary)
                                if isMVP(player: player, snapshot: snapshot) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(AppPalette.accentGold)
                                }
                            }
                            Text(statLine(for: stat))
                                .font(AppTypography.body(10))
                                .foregroundStyle(stat == nil ? AppPalette.textMuted : AppPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(isMVP(player: player, snapshot: snapshot) ? tint.opacity(0.16) : background.opacity(0.96))
                }
            }
            .background(background)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func powerDeltaSection(_ snapshot: MatchDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("파워 변화량")
                .font(AppTypography.heading(15, weight: .bold))
            VStack(spacing: 8) {
                ForEach(sortedPlayers(for: snapshot.match)) { player in
                    let delta = deltaText(for: player, snapshot: snapshot)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.nickname)
                                .font(AppTypography.body(13, weight: .semibold))
                            Text(player.assignedRole?.shortLabel ?? "포지션 미정")
                                .font(AppTypography.body(10))
                                .foregroundStyle(AppPalette.textMuted)
                        }
                        Spacer()
                        Text(delta ?? "계산 전")
                            .font(AppTypography.body(13, weight: .semibold))
                            .foregroundStyle(deltaColor(for: player, snapshot: snapshot))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .appPanel(background: AppPalette.bgTertiary, radius: 10)
                }
            }
        }
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 14)
    }

    private func teamPlayers(side: TeamSide, snapshot: MatchDetailSnapshot) -> [(MatchPlayer, MatchStat?)] {
        let players = snapshot.match.players
            .filter { $0.teamSide == side }
            .sorted { roleOrder($0.assignedRole) < roleOrder($1.assignedRole) }
        return players.map { player in
            (player, snapshot.result?.players.first(where: { $0.userID == player.userID }))
        }
    }

    private func sortedPlayers(for match: Match) -> [MatchPlayer] {
        match.players.sorted { left, right in
            let leftSideOrder = left.teamSide == .blue ? 0 : 1
            let rightSideOrder = right.teamSide == .blue ? 0 : 1
            if leftSideOrder == rightSideOrder {
                return roleOrder(left.assignedRole) < roleOrder(right.assignedRole)
            }
            return leftSideOrder < rightSideOrder
        }
    }

    private func roleOrder(_ role: Position?) -> Int {
        switch role {
        case .top: return 0
        case .jungle: return 1
        case .mid: return 2
        case .adc: return 3
        case .support: return 4
        case .fill: return 5
        case nil: return 6
        }
    }

    private func statLine(for stat: MatchStat?) -> String {
        guard let stat else { return "기록 없음" }
        return "KDA \(stat.kills)/\(stat.deaths)/\(stat.assists)"
    }

    private func resultStatusText(for snapshot: MatchDetailSnapshot) -> String {
        if let winner = winningTeam(for: snapshot) {
            return "\(winner.title) 승리"
        }
        return snapshot.result?.resultStatus.title ?? "결과 대기"
    }

    private func resultStatusColor(for snapshot: MatchDetailSnapshot) -> Color {
        if let winner = winningTeam(for: snapshot) {
            return winner == .blue ? AppPalette.teamBlue : AppPalette.teamRed
        }
        switch snapshot.result?.resultStatus {
        case .confirmed:
            return AppPalette.accentBlue
        case .partial:
            return AppPalette.accentGreen
        case .disputed:
            return AppPalette.accentOrange
        case nil:
            return AppPalette.textMuted
        }
    }

    private func winnerColor(for snapshot: MatchDetailSnapshot) -> Color {
        guard let winner = winningTeam(for: snapshot) else { return AppPalette.textSecondary }
        return winner == .blue ? AppPalette.teamBlue : AppPalette.teamRed
    }

    private func winningTeam(for snapshot: MatchDetailSnapshot) -> TeamSide? {
        snapshot.result?.winningTeam ?? snapshot.cachedMetadata?.winningTeam
    }

    private func mvpName(for snapshot: MatchDetailSnapshot) -> String {
        guard let userID = snapshot.cachedMetadata?.mvpUserID else { return "기록 없음" }
        return snapshot.match.players.first(where: { $0.userID == userID })?.nickname ?? "기록 없음"
    }

    private func isMVP(player: MatchPlayer, snapshot: MatchDetailSnapshot) -> Bool {
        snapshot.cachedMetadata?.mvpUserID == player.userID
    }

    private func predictedBalanceText(for snapshot: MatchDetailSnapshot) -> String {
        guard let candidate = selectedCandidate(in: snapshot.match) else { return "계산 전" }
        let gap = abs(candidate.teamAPower - candidate.teamBPower)
        if gap <= 4 {
            return "접전 예상"
        }
        return candidate.teamAPower > candidate.teamBPower ? "블루 우세" : "레드 우세"
    }

    private func gameBalanceText(for snapshot: MatchDetailSnapshot) -> String {
        guard let rating = snapshot.cachedMetadata?.balanceRating else { return "기록 없음" }
        switch rating {
        case ...2:
            return "한쪽 우세"
        case 3...4:
            return "살짝 우세"
        default:
            return "접전"
        }
    }

    private func actualResultText(for snapshot: MatchDetailSnapshot) -> String {
        guard let winner = winningTeam(for: snapshot) else { return "기록 없음" }
        return "\(winner.title) 승리"
    }

    private func selectedCandidate(in match: Match) -> MatchCandidate? {
        if let candidateNo = match.selectedCandidateNo,
           let candidate = match.candidates.first(where: { $0.candidateNo == candidateNo }) {
            return candidate
        }
        return match.candidates.first(where: { $0.type == (match.balanceMode ?? .balanced) }) ?? match.candidates.first
    }

    private func deltaText(for player: MatchPlayer, snapshot: MatchDetailSnapshot) -> String? {
        guard
            let result = snapshot.result,
            let teamSide = player.teamSide,
            let winningTeam = result.winningTeam
        else {
            return nil
        }

        let confidence: Double
        switch result.resultStatus {
        case .confirmed:
            confidence = 1
        case .partial:
            confidence = 0.5
        case .disputed:
            confidence = 0
        }

        guard confidence > 0 else { return nil }

        let didWin = winningTeam == teamSide
        let value = Int((didWin ? 18 : -18) * confidence)
        return value >= 0 ? "+\(value)" : "\(value)"
    }

    private func deltaColor(for player: MatchPlayer, snapshot: MatchDetailSnapshot) -> Color {
        guard let delta = deltaText(for: player, snapshot: snapshot) else { return AppPalette.textMuted }
        return delta.hasPrefix("+") ? AppPalette.accentGreen : AppPalette.accentRed
    }
}

struct SearchScreen: View {
    @StateObject private var viewModel: SearchViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    init(
        viewModel: SearchViewModel,
        session: AppSessionViewModel,
        router: AppRouter,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.session = session
        self.router = router
        self.onBack = onBack
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        screenScaffold(title: "검색", onBack: onBack, rightSystemImage: nil) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    searchFieldCard

                    if trimmedSearchText.isEmpty {
                        searchIntroCard
                        recentSearchSection
                    } else {
                        resultContent
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            viewModel.refreshRecentSearchKeywords()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFieldFocused = true
            }
        }
        .onDisappear {
            viewModel.cancelPendingSearch()
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.updateQuery(newValue)
        }
    }

    private var searchFieldCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppPalette.textSecondary)

            TextField("Riot ID, 그룹, 모집글 검색", text: $searchText)
                .font(AppTypography.body(15))
                .foregroundStyle(AppPalette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    viewModel.submitSearch(searchText)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppPalette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AppPalette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var searchIntroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("바로 찾기")
                .font(AppTypography.heading(18, weight: .bold))

            Text("연결한 Riot ID, 공개 그룹, 모집글을 한 번에 확인할 수 있습니다.")
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                introRow(
                    badge: "Riot ID",
                    title: "내 계정에 연결한 Riot ID 검색",
                    description: session.isAuthenticated
                        ? "기준 Riot ID와 참고 Riot ID를 빠르게 다시 열 수 있습니다."
                        : "로그인 후 연결한 Riot ID를 검색 결과에 함께 표시합니다."
                )
                introRow(
                    badge: "GROUP",
                    title: "공개 그룹 검색",
                    description: "그룹 이름, 설명, 태그를 기준으로 찾아볼 수 있습니다."
                )
                introRow(
                    badge: "RECRUIT",
                    title: "모집글 검색",
                    description: "제목, 본문, 포지션 태그를 기준으로 현재 공개 모집글을 찾습니다."
                )
            }
        }
        .padding(18)
        .appPanel(background: AppPalette.bgCard, radius: 14)
    }

    @ViewBuilder
    private var recentSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 검색어")
                    .font(AppTypography.heading(16, weight: .bold))
                Spacer()
                if !viewModel.recentSearchKeywords.isEmpty {
                    Button("전체 삭제") {
                        viewModel.clearRecentSearchKeywords()
                    }
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(AppPalette.accentRed)
                }
            }

            if viewModel.recentSearchKeywords.isEmpty {
                emptySearchCard(
                    title: "최근 검색어가 없습니다",
                    message: "검색어를 입력하면 이 기기에 최근 검색어가 저장됩니다."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.recentSearchKeywords) { keyword in
                        HStack(spacing: 12) {
                            Button {
                                searchText = keyword.keyword
                                isSearchFieldFocused = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(AppPalette.textMuted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(keyword.keyword)
                                            .font(AppTypography.body(13, weight: .semibold))
                                            .foregroundStyle(AppPalette.textPrimary)
                                        Text(keyword.searchedAt.shortDateText)
                                            .font(AppTypography.body(10))
                                            .foregroundStyle(AppPalette.textMuted)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.deleteRecentSearchKeyword(id: keyword.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppPalette.textMuted)
                                    .frame(width: 24, height: 24)
                                    .background(AppPalette.bgSecondary)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .appPanel(background: AppPalette.bgCard, radius: 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch viewModel.state {
        case .idle:
            emptySearchCard(
                title: "검색어를 입력해 주세요",
                message: "불필요한 연속 검색을 줄이기 위해 입력을 잠시 멈추면 검색합니다."
            )
        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppPalette.accentBlue)
                Text("검색 중입니다")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
                Spacer()
            }
            .padding(16)
            .appPanel(background: AppPalette.bgCard, radius: 12)
        case let .results(response):
            VStack(alignment: .leading, spacing: 16) {
                Text("검색 결과")
                    .font(AppTypography.heading(16, weight: .bold))

                ForEach(response.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title)
                                .font(AppTypography.body(14, weight: .semibold))
                            Spacer()
                            Text("\(section.items.count)건")
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textMuted)
                        }

                        ForEach(section.items) { item in
                            Button {
                                handleSelection(of: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(AppTypography.body(14, weight: .semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                            Text(item.subtitle)
                                                .font(AppTypography.body(12))
                                                .foregroundStyle(AppPalette.textSecondary)
                                        }
                                        Spacer()
                                        if session.isGuest, item.destination != .riotAccounts {
                                            Text("로그인 필요")
                                                .font(AppTypography.body(10, weight: .semibold))
                                                .foregroundStyle(AppPalette.accentGold)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppPalette.bgSecondary)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    if let supportingText = item.supportingText, !supportingText.isEmpty {
                                        Text(supportingText)
                                            .font(AppTypography.body(11))
                                            .foregroundStyle(AppPalette.textMuted)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    if !item.tags.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(item.tags, id: \.self) { tag in
                                                    Text(tag)
                                                        .font(AppTypography.body(10, weight: .semibold))
                                                        .foregroundStyle(tag == "기준 Riot ID" ? AppPalette.accentGold : AppPalette.accentBlue)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(AppPalette.bgSecondary)
                                                        .clipShape(Capsule())
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .appPanel(background: AppPalette.bgCard, radius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        case let .empty(message):
            VStack(spacing: 14) {
                emptySearchCard(
                    title: message,
                    message: "다른 검색어를 입력하거나 최근 검색어에서 다시 시작해 주세요."
                )
                if !viewModel.recentSearchKeywords.isEmpty {
                    recentSearchSection
                }
            }
        case let .error(error):
            ErrorStateView(error: error) {
                viewModel.submitSearch(searchText)
            }
        }
    }

    private func introRow(badge: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(AppTypography.body(10, weight: .semibold))
                .foregroundStyle(AppPalette.accentBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppPalette.bgSecondary)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(description)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func emptySearchCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(14, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }

    private func handleSelection(of item: SearchResultItem) {
        if !trimmedSearchText.isEmpty {
            viewModel.recordRecentSearchKeyword(trimmedSearchText)
        }
        isSearchFieldFocused = false
        guard item.destination.isAccessible else {
            session.actionState = .failure("참여 중인 그룹만 확인할 수 있어요.")
            return
        }
        session.openProtectedRoute(
            item.destination.route,
            requirement: item.destination.authRequirement,
            router: router
        )
    }
}

struct ProfileScreen: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        TabRootScaffold(title: AppTab.profile.title, trailingAction: settingsHeaderAction) {
            Group {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "프로필을 불러오는 중입니다")
                        .task { await viewModel.load() }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
                case let .empty(message):
                    VStack(spacing: 0) {
                        StatusBarView()
                        EmptyStateView(title: "프로필", message: message)
                    }
                case let .content(content), let .refreshing(content):
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            VStack(spacing: 20) {
                                switch content {
                                case let .authenticated(snapshot):
                                    authenticatedProfileContent(snapshot)
                                case let .guest(snapshot):
                                    guestProfileContent(snapshot)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    private var settingsHeaderAction: TabHeaderAction {
        TabHeaderAction(systemName: "gearshape", accessibilityLabel: "설정") {
            router.push(.settings)
        }
    }

    @ViewBuilder
    private func authenticatedProfileContent(_ snapshot: ProfileSnapshot) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(AppPalette.bgElevated)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.profile.nickname)
                    .font(AppTypography.heading(24, weight: .bold))
                Text(snapshot.riotAccountsViewState.primaryAccount.map { "\($0.riotGameName)#\($0.tagLine)" } ?? snapshot.profile.email)
                    .font(AppTypography.body(13))
                    .foregroundStyle(AppPalette.textSecondary)
                HStack(spacing: 8) {
                    tagLabel(snapshot.profile.primaryPosition?.shortLabel ?? "MID", tint: AppPalette.accentBlue)
                    tagLabel(snapshot.profile.secondaryPosition?.shortLabel ?? "TOP", tint: AppPalette.accentPurple)
                }
            }
            Spacer()
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("추가한 Riot ID")
                    .font(AppTypography.body(14, weight: .semibold))
                Spacer()
                Button("관리") {
                    router.push(.riotAccounts)
                }
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(AppPalette.accentBlue)
            }
            switch snapshot.riotAccountsViewState {
            case let .loaded(accounts):
                ForEach(accounts.prefix(2)) { account in
                    HStack {
                        tagLabel(account.isPrimary ? "기준" : "참고", tint: account.isPrimary ? AppPalette.accentGold : AppPalette.textMuted)
                        Text("\(account.riotGameName)#\(account.tagLine)")
                            .font(AppTypography.body(12, weight: .semibold))
                        Spacer()
                        Text(account.verificationStatus.title)
                            .font(AppTypography.body(12))
                            .foregroundStyle(account.isPrimary ? AppPalette.accentGold : AppPalette.textSecondary)
                    }
                }
            case .noLinkedAccounts:
                profileRiotAccountsEmptyState(
                    title: "추가한 Riot ID가 없어요",
                    message: "게임 이름과 태그라인을 입력해 Riot ID를 추가해 주세요."
                )
            case let .error(error):
                profileRiotAccountsEmptyState(
                    title: "Riot ID를 확인하지 못했어요",
                    message: error.message
                )
            case .loading:
                profileRiotAccountsEmptyState(
                    title: "Riot ID 목록을 확인하는 중이에요",
                    message: "잠시 후 Riot ID 목록을 다시 보여드릴게요."
                )
            }
        }
        .padding(16)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        if snapshot.riotAccountsViewState.hasLinkedAccounts {
            if let power = snapshot.power {
                VStack(alignment: .leading, spacing: 14) {
                    Text("파워 프로필")
                        .font(AppTypography.heading(16, weight: .bold))
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(power.overallPower.rounded()))")
                                .font(AppTypography.heading(40, weight: .heavy))
                                .foregroundStyle(AppPalette.accentBlue)
                            Text("종합 파워")
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textMuted)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            profileStat("최근 폼", value: Int(power.formScore.rounded()), tint: AppPalette.textPrimary)
                            profileStat("안정성", value: Int(power.stability.rounded()), tint: AppPalette.textSecondary)
                            profileStat("캐리 기여", value: Int(power.carry.rounded()), tint: AppPalette.textSecondary)
                            profileStat("팀 기여도", value: Int(power.teamContribution.rounded()), tint: AppPalette.textSecondary)
                            profileStat("내전 MMR", value: Int(power.inhouseMMR.rounded()), tint: AppPalette.accentGold)
                        }
                    }
                    Text("라인별 파워")
                        .font(AppTypography.body(13, weight: .semibold))
                    ForEach([Position.top, .jungle, .mid, .adc, .support], id: \.self) { role in
                        profileLanePowerRow(role: role, lanePower: power.lanePower[role])
                    }
                }
                .padding(16)
                .background(AppPalette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("최근 내전 성적")
                    .font(AppTypography.heading(16, weight: .bold))
                HStack(spacing: 8) {
                    recentStat(title: "최근 전적", value: "\(snapshot.history.filter { $0.result == "WIN" }.count)승 \(snapshot.history.filter { $0.result == "LOSE" }.count)패", tint: AppPalette.textPrimary)
                    recentStat(title: "승률", value: winRateText(snapshot.history), tint: AppPalette.accentGreen)
                    recentStat(title: "연속", value: streakText(snapshot.history), tint: AppPalette.accentGold)
                }
            }
        } else if case let .error(error) = snapshot.riotAccountsViewState {
            riotProfileEmptyStateCard(
                title: "Riot ID 상태를 확인하지 못했어요",
                message: error.message
            )
        } else if case .loading = snapshot.riotAccountsViewState {
            riotProfileEmptyStateCard(
                title: "Riot ID 목록을 확인하는 중이에요",
                message: "추가한 Riot ID를 확인한 뒤 파워 프로필을 보여드릴게요."
            )
        } else {
            riotProfileEmptyStateCard(
                title: "Riot ID를 추가하면 확인할 수 있어요",
                message: "내전 전적과 파워 프로필이 기준 Riot ID와 참고 데이터 기준으로 표시됩니다."
            )
        }
    }

    @ViewBuilder
    private func guestProfileContent(_ snapshot: GuestProfileSnapshot) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(AppPalette.bgElevated)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("게스트로 사용 중")
                    .font(AppTypography.heading(24, weight: .bold))
                Text("로그인하면 기록 동기화, 찜, 공유 기능을 사용할 수 있어요")
                    .font(AppTypography.body(13))
                    .foregroundStyle(AppPalette.textSecondary)
                HStack(spacing: 8) {
                    tagLabel("GUEST", tint: AppPalette.accentBlue)
                    tagLabel("LOCAL", tint: AppPalette.textMuted)
                }
            }
            Spacer()
        }

        AuthInlineAccessCard(
            session: session,
            title: "선택 로그인",
            message: "Apple 또는 Google 로그인으로 로컬 기록을 계정에 연결하고, 기기 간 이어하기를 사용할 수 있어요."
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("연결 가능한 기능")
                    .font(AppTypography.body(14, weight: .semibold))
                Spacer()
                Button("로그인 안내") {
                    session.requireAuthentication(for: .riotAccount)
                }
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(AppPalette.accentBlue)
            }
            HStack {
                tagLabel("동기화", tint: AppPalette.accentGold)
                Text("Riot ID 추가와 프로필 저장은 로그인 후 사용할 수 있어요.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
            }
            HStack {
                tagLabel("공유", tint: AppPalette.accentPurple)
                Text("내전 기록 공유 링크와 찜 목록 저장도 계정에 연결됩니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .padding(16)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 14) {
            Text("로컬 사용 현황")
                .font(AppTypography.heading(16, weight: .bold))
            HStack(spacing: 8) {
                recentStat(title: "로컬 기록", value: "\(snapshot.localResults.count)개", tint: AppPalette.textPrimary)
                recentStat(title: "최근 그룹", value: "\(snapshot.trackedGroupCount)개", tint: AppPalette.accentBlue)
                recentStat(title: "알림", value: "\(snapshot.notificationCount)개", tint: AppPalette.accentGold)
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("최근 로컬 저장")
                .font(AppTypography.heading(16, weight: .bold))
            if let latest = snapshot.localResults.first {
                MatchCardView(
                    title: latest.groupName,
                    dateText: latest.savedAt.dottedDateText,
                    isWin: latest.winningTeam == .blue,
                    blueSummary: "승리 팀 \(latest.winningTeam == .blue ? "블루" : "레드")",
                    redSummary: "밸런스 \(latest.balanceRating)/5",
                    detail: "로컬 저장 · MVP \(latest.mvpUserID)"
                )
            } else {
                Text("아직 로컬에 저장된 내전 기록이 없습니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppPalette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func tagLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppPalette.bgTertiary)
            .clipShape(Capsule())
    }

    private func profileStat(_ label: String, value: Int, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text("\(value)")
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func recentStat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.heading(15, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func profileRiotAccountsEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(14, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func riotProfileEmptyStateCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.heading(16, weight: .bold))
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Riot ID 추가하기") {
                router.push(.riotAccounts)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func profileLanePowerRow(role: Position, lanePower: Double?) -> some View {
        HStack(spacing: 8) {
            Text(role.shortLabel)
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(role == .mid ? AppPalette.accentBlue : AppPalette.textSecondary)
                .frame(width: 32, alignment: .leading)
            ProgressView(value: max(lanePower ?? 0, 0), total: 100)
                .tint(laneTint(role))
            Text(lanePower.map { "\(Int($0.rounded()))" } ?? "--")
                .font(AppTypography.body(12, weight: .semibold))
        }
    }

    private func laneTint(_ role: Position) -> Color {
        switch role {
        case .top: return AppPalette.teamBlue
        case .jungle: return AppPalette.accentPurple
        case .mid: return AppPalette.accentBlue
        case .adc: return AppPalette.accentOrange
        case .support: return AppPalette.accentGreen
        case .fill: return AppPalette.textMuted
        }
    }

    private func winRateText(_ items: [MatchHistoryItem]) -> String {
        guard !items.isEmpty else { return "0%" }
        let winCount = items.filter { $0.result == "WIN" }.count
        return String(format: "%.1f%%", Double(winCount) / Double(items.count) * 100)
    }

    private func streakText(_ items: [MatchHistoryItem]) -> String {
        guard let first = items.first else { return "0연승" }
        let target = first.result
        let streak = items.prefix(while: { $0.result == target }).count
        return "\(streak)\(target == "WIN" ? "연승" : "연패")"
    }
}

struct RiotAccountsScreen: View {
    @StateObject var viewModel: RiotAccountsViewModel
    @ObservedObject var session: AppSessionViewModel
    let onBack: () -> Void
    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var isPrimary = true
    @State private var hasAttemptedSubmit = false
    @State private var pendingUnlinkAccount: RiotAccount?
    @FocusState private var focusedField: RiotAccountInputField?

    var body: some View {
        screenScaffold(title: "Riot ID 관리", onBack: onBack, rightSystemImage: nil) {
            if session.isGuest {
                guestContent
            } else {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "Riot ID를 불러오는 중입니다")
                        .task { await viewModel.load() }
                case let .error(error):
                    ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
                case .empty:
                    formContent(accounts: [])
                case let .content(snapshot), let .refreshing(snapshot):
                    formContent(accounts: snapshot.accounts)
                }
            }
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
        .alert(
            "이 Riot ID를 목록에서 제거할까요?",
            isPresented: Binding(
                get: { pendingUnlinkAccount != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingUnlinkAccount = nil
                    }
                }
            ),
            presenting: pendingUnlinkAccount
        ) { account in
            Button("취소", role: .cancel) {
                pendingUnlinkAccount = nil
            }
            Button("제거", role: .destructive) {
                pendingUnlinkAccount = nil
                Task { await viewModel.unlink(account: account) }
            }
        } message: { account in
            Text(unlinkConfirmationMessage(for: account, accounts: managedAccounts))
        }
    }

    private var managedAccounts: [RiotAccount] {
        viewModel.state.value?.accounts ?? []
    }

    private var normalizedGameName: String {
        RiotAccountInputValidator.normalizedGameName(gameName)
    }

    private var normalizedTagLine: String {
        RiotAccountInputValidator.normalizedTagLine(tagLine)
    }

    private var gameNameValidationState: FieldValidationState {
        let shouldValidate = hasAttemptedSubmit || !gameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return shouldValidate ? RiotAccountInputValidator.validateGameName(gameName) : .idle
    }

    private var tagLineValidationState: FieldValidationState {
        let shouldValidate = hasAttemptedSubmit || !tagLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return shouldValidate ? RiotAccountInputValidator.validateTagLine(tagLine) : .idle
    }

    private var canSubmitConnection: Bool {
        !viewModel.isConnecting
    }

    private var guestContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Riot ID는 공개 Riot API 기반 참고 데이터로 사용됩니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                AuthInlineAccessCard(
                    session: session,
                    title: "로그인 후 Riot ID 관리",
                    message: "Riot ID 추가, 기준 Riot ID 설정, 전적 동기화는 로그인 후 사용할 수 있어요."
                )
            }
            .padding(24)
        }
    }

    private func formContent(accounts: [RiotAccount]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppPalette.accentBlue)
                        Text("Riot API 데이터는 참고용이며, 내전 기록이 핵심 지표입니다.")
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                    }

                    Text("입력한 Riot ID는 이 계정의 밸런스 계산과 참고 정보 표시 기준으로 사용할 수 있습니다.")
                        .font(AppTypography.body(11))
                        .foregroundStyle(AppPalette.textMuted)

                    Text("본인 인증 기반 연동이 아니라 공개 Riot ID 기준 참고 데이터로 동작합니다.")
                        .font(AppTypography.body(11))
                        .foregroundStyle(AppPalette.textMuted)

                    Text("입력 예시: Hide on bush#KR1")
                        .font(AppTypography.body(12, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text("게임 이름과 태그라인을 나눠 입력해 주세요. KR1은 태그라인이며, 플랫폼 코드를 따로 입력하지 않습니다.")
                        .font(AppTypography.body(11))
                        .foregroundStyle(AppPalette.textMuted)
                }
                .padding(14)
                .background(Color(hex: 0x1A2744))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 14) {
                    Text("새 Riot ID 추가")
                        .font(AppTypography.heading(16, weight: .bold))

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("게임 이름")
                                .font(AppTypography.body(13, weight: .semibold))
                            TextField("예: Hide on bush", text: $gameName)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .gameName)
                                .onSubmit { focusedField = .tagLine }
                            validationMessage(
                                state: gameNameValidationState,
                                helperText: "Riot ID의 게임 이름 부분을 입력해 주세요."
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("태그라인")
                                .font(AppTypography.body(13, weight: .semibold))
                            TextField("예: KR1", text: $tagLine)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                                .submitLabel(.done)
                                .focused($focusedField, equals: .tagLine)
                                .onSubmit { submitConnection() }
                            validationMessage(
                                state: tagLineValidationState,
                                helperText: "# 없이 KR1처럼 입력해 주세요."
                            )
                        }
                        .frame(width: 124)
                    }

                    Toggle("기준 Riot ID로 설정", isOn: $isPrimary)
                        .tint(AppPalette.accentBlue)

                    Button {
                        submitConnection()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isConnecting {
                                ProgressView()
                                    .tint(AppPalette.bgPrimary)
                            }
                            Text(viewModel.isConnecting ? "추가 중" : "추가하기")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmitConnection)
                    .opacity(canSubmitConnection ? 1 : 0.72)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("추가한 Riot ID")
                        .font(AppTypography.heading(16, weight: .bold))

                    if accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("추가한 Riot ID가 없습니다")
                                .font(AppTypography.body(14, weight: .semibold))
                            Text("게임 이름과 태그라인을 입력해 Riot ID를 추가하면, 밸런스 계산 기준과 참고 데이터를 여기서 확인할 수 있어요.")
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppPalette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(accounts) { account in
                            let isSyncing = viewModel.syncInProgressIDs.contains(account.id) || account.syncStatus.isInFlight
                            let isUnlinking = viewModel.unlinkInProgressIDs.contains(account.id)

                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Text(account.isPrimary ? "기준" : "참고")
                                                .font(AppTypography.body(11, weight: .semibold))
                                                .foregroundStyle(account.isPrimary ? AppPalette.bgPrimary : AppPalette.textSecondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(account.isPrimary ? AppPalette.accentGold : AppPalette.bgTertiary)
                                                .clipShape(Capsule())
                                            Text(account.displayName)
                                                .font(AppTypography.body(14, weight: .semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                        }

                                        Text("\(account.region.uppercased()) · \(account.verificationStatus.title)")
                                            .font(AppTypography.body(12))
                                            .foregroundStyle(AppPalette.textSecondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 8) {
                                        Button(isSyncing ? "동기화 중" : "Sync") {
                                            Task { await viewModel.sync(id: account.id) }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(AppPalette.accentBlue)
                                        .disabled(isSyncing || isUnlinking)

                                        Button(isUnlinking ? "제거 중" : "제거") {
                                            pendingUnlinkAccount = account
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(AppPalette.accentRed)
                                        .disabled(isSyncing || isUnlinking)
                                    }
                                }

                                infoRow(title: "동기화 상태") {
                                    HStack(spacing: 8) {
                                        statusPill(for: account.syncUIState)
                                        if isSyncing {
                                            ProgressView()
                                                .controlSize(.small)
                                                .tint(statusTint(for: account.syncUIState))
                                        }
                                    }
                                }

                                infoRow(
                                    title: "마지막 동기화",
                                    value: account.lastSyncedAt?.shortDateText
                                        ?? account.lastSyncSucceededAt?.shortDateText
                                        ?? "없음"
                                )

                                infoRow(
                                    title: account.syncUIState.isFailure ? "마지막 실패" : "마지막 요청",
                                    value: account.syncUIState.isFailure
                                        ? (account.lastSyncFailedAt?.shortDateText ?? account.lastSyncRequestedAt?.shortDateText ?? "없음")
                                        : (account.lastSyncRequestedAt?.shortDateText ?? "없음")
                                )

                                infoRow(
                                    title: account.syncUIState.isFailure ? "실패 원인" : "상태 설명",
                                    value: account.syncStatusSummary,
                                    tint: account.syncUIState.isFailure ? statusTint(for: account.syncUIState) : AppPalette.textSecondary
                                )
                            }
                            .padding(16)
                            .background(AppPalette.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(account.isPrimary ? AppPalette.accentGold : AppPalette.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("여러 Riot ID 활용 기준")
                        .font(AppTypography.body(13, weight: .semibold))
                    Text("기준 Riot ID의 데이터가 우선 반영되며, 다른 Riot ID는 참고용 데이터로 함께 볼 수 있습니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                    Text("실제 계산 로직과 가중치는 서버 기준을 따르며, 클라이언트는 이해를 돕기 위한 설명을 제공합니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .padding(16)
                .background(AppPalette.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func validationMessage(state: FieldValidationState, helperText: String) -> some View {
        HStack(spacing: 6) {
            if let iconName = state.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.tint)
            }

            Text(state.message ?? helperText)
                .font(AppTypography.body(11))
                .foregroundStyle(state.message == nil ? AppPalette.textMuted : state.tint)

            Spacer()
        }
        .frame(minHeight: 18, alignment: .leading)
    }

    @ViewBuilder
    private func infoRow(title: String, value: String, tint: Color = AppPalette.textPrimary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(AppTypography.body(11, weight: .semibold))
                .foregroundStyle(AppPalette.textMuted)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(AppTypography.body(12))
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func infoRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(AppTypography.body(11, weight: .semibold))
                .foregroundStyle(AppPalette.textMuted)
                .frame(width: 72, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
    }

    private func statusTint(for state: RiotSyncUIState) -> Color {
        switch state {
        case .pending:
            return AppPalette.textSecondary
        case .syncing:
            return AppPalette.accentBlue
        case .success:
            return AppPalette.accentGreen
        case .accountNotFound, .invalidInput:
            return AppPalette.accentOrange
        case .serverConfiguration:
            return AppPalette.accentPurple
        case .failure:
            return AppPalette.accentRed
        }
    }

    private func statusBackground(for state: RiotSyncUIState) -> Color {
        switch state {
        case .pending:
            return AppPalette.bgTertiary
        default:
            return statusTint(for: state).opacity(0.16)
        }
    }

    private func statusPill(for state: RiotSyncUIState) -> some View {
        Text(state.title)
            .font(AppTypography.body(11, weight: .semibold))
            .foregroundStyle(statusTint(for: state))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusBackground(for: state))
            .clipShape(Capsule())
    }

    private func submitConnection() {
        hasAttemptedSubmit = true
        focusedField = nil

        guard gameNameValidationState.isValid else {
            focusedField = .gameName
            return
        }

        guard tagLineValidationState.isValid else {
            focusedField = .tagLine
            return
        }

        Task {
            let didConnect = await viewModel.connect(
                gameName: normalizedGameName,
                tagLine: normalizedTagLine,
                region: RiotAccountInputValidator.region,
                isPrimary: isPrimary
            )

            if didConnect {
                gameName = ""
                tagLine = ""
                isPrimary = false
                hasAttemptedSubmit = false
            }
        }
    }

    private func unlinkConfirmationMessage(for account: RiotAccount, accounts: [RiotAccount]) -> String {
        var parts = ["제거하면 이 Riot ID의 동기화 정보와 목록 표시가 함께 사라집니다."]
        if account.isPrimary {
            if accounts.count <= 1 {
                parts.append("현재 기준 Riot ID가 이 항목뿐이라 제거 후에는 추가한 Riot ID가 없는 상태가 될 수 있습니다.")
            } else {
                parts.append("기준 Riot ID를 제거하면 어떤 Riot ID를 기준으로 볼지는 서버 정책에 따라 다시 정리됩니다.")
            }
        }
        return parts.joined(separator: " ")
    }
}

private enum RiotAccountInputField: Hashable {
    case gameName
    case tagLine
}

struct NotificationsScreen: View {
    let store: AppLocalStore
    let onBack: () -> Void
    @State private var notifications: [NotificationEntry] = []

    var body: some View {
        screenScaffold(title: "알림", onBack: onBack, rightSystemImage: nil) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if notifications.isEmpty {
                        EmptyStateView(title: "알림", message: "새로운 알림이 아직 없습니다.")
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        if !todayNotifications.isEmpty {
                            notificationSection(title: "오늘", entries: todayNotifications)
                        }
                        if !yesterdayNotifications.isEmpty {
                            notificationSection(title: "어제", entries: yesterdayNotifications)
                        }
                    }
                }
                .padding(24)
            }
        }
        .task {
            notifications = store.notifications
        }
    }

    private var todayNotifications: [NotificationEntry] {
        let calendar = Calendar.current
        return notifications.filter { calendar.isDateInToday($0.createdAt) }
    }

    private var yesterdayNotifications: [NotificationEntry] {
        let calendar = Calendar.current
        return notifications.filter { calendar.isDateInYesterday($0.createdAt) }
    }

    private func notificationSection(title: String, entries: [NotificationEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(AppPalette.textMuted)
            ForEach(entries) { entry in
                notificationCard(entry)
            }
        }
    }

    private func notificationCard(_ entry: NotificationEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(entry.isUnread ? AppPalette.accentBlue : AppPalette.textMuted.opacity(0.28))
                .frame(width: 6, height: 6)
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppPalette.bgTertiary)
                    .frame(width: 38, height: 38)
                Image(systemName: entry.systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.isUnread ? AppPalette.accentBlue : AppPalette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(entry.title)
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Spacer()
                    Text(entry.createdAt.shortDateText)
                        .font(AppTypography.body(10))
                        .foregroundStyle(AppPalette.textMuted)
                }
                Text(entry.body)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.isUnread ? "읽지 않음" : "확인됨")
                    .font(AppTypography.body(10, weight: .semibold))
                    .foregroundStyle(entry.isUnread ? AppPalette.accentBlue : AppPalette.textMuted)
            }
            Spacer()
        }
        .padding(14)
        .appPanel(background: entry.isUnread ? Color(hex: 0x111A28) : AppPalette.bgCard, radius: 12)
    }
}

private enum SettingsSheet: Identifiable {
    case externalLink(AppExternalLink)
    case supportMail(SupportMailDraft)

    var id: String {
        switch self {
        case let .externalLink(link):
            return "external-\(link.rawValue)"
        case let .supportMail(draft):
            return "support-mail-\(draft.id.uuidString)"
        }
    }
}

struct SettingsScreen: View {
    @Environment(\.openURL) private var openURL

    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void

    @State private var isProfilePublic: Bool
    @State private var isHistoryPublic: Bool
    @State private var notificationsEnabled: Bool
    @State private var showsProfileEdit = false
    @State private var activeSheet: SettingsSheet?
    @State private var externalLinkErrorMessage: String?

    init(session: AppSessionViewModel, router: AppRouter, onBack: @escaping () -> Void) {
        self.session = session
        self.router = router
        self.onBack = onBack
        let localStore = session.container.localStore
        _isProfilePublic = State(initialValue: localStore.isProfilePublic)
        _isHistoryPublic = State(initialValue: localStore.isHistoryPublic)
        _notificationsEnabled = State(initialValue: localStore.notificationsEnabled)
    }

    private var appVersionText: String {
        let info = AppInfoDescriptor.current()
        return "\(info.appName) v\(info.appVersion) (\(info.buildNumber))"
    }

    var body: some View {
        screenScaffold(title: "설정", onBack: onBack, rightSystemImage: nil) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Text("계정, 게임 설정, 공개 범위를 한 곳에서 관리합니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if session.isGuest {
                        AuthInlineAccessCard(
                            session: session,
                            title: "로그인하고 이어쓰기",
                            message: "설정 동기화, 프로필 편집, Riot ID 관리는 로그인 후 사용할 수 있어요."
                        )

                        settingsSection(title: "계정", rows: [
                            settingsRow("로그인", subtitle: "동기화 시작", systemImage: "person.crop.circle") {
                                session.requireAuthentication(for: .settings)
                            },
                            settingsRow("Riot ID 관리", subtitle: "로그인 후 사용", systemImage: "person.text.rectangle") {
                                session.requireAuthentication(for: .riotAccount) {
                                    router.push(.riotAccounts)
                                }
                            }
                        ])

                        settingsSection(title: "게임 설정", rows: [
                            settingsRow("기본 포지션 설정", subtitle: "로그인 후 저장", systemImage: "scope", valueTint: AppPalette.accentBlue) {
                                session.requireAuthentication(for: .settings)
                            },
                            settingsRow("내전 성향", subtitle: "로그인 후 저장", systemImage: "sparkles", valueTint: AppPalette.accentPurple) {
                                session.requireAuthentication(for: .settings)
                            }
                        ])
                    } else {
                        settingsSection(title: "계정", rows: [
                            settingsRow("계정 관리", subtitle: session.profile?.email ?? "-", systemImage: "person.crop.circle") { showsProfileEdit = true },
                            settingsRow("Riot ID 관리", subtitle: "추가한 Riot ID 확인", systemImage: "person.text.rectangle") { router.push(.riotAccounts) }
                        ])

                        settingsSection(title: "게임 설정", rows: [
                            settingsRow("기본 포지션 설정", subtitle: "\(session.profile?.primaryPosition?.shortLabel ?? "MID") / \(session.profile?.secondaryPosition?.shortLabel ?? "TOP")", systemImage: "scope", valueTint: AppPalette.accentBlue) { showsProfileEdit = true },
                            settingsRow("내전 성향", subtitle: session.profile?.styleTags.joined(separator: ", ") ?? "빡겜", systemImage: "sparkles", valueTint: AppPalette.accentPurple) { showsProfileEdit = true }
                        ])
                    }

                    settingsSection(title: "알림", rows: [
                        toggleRow("알림 설정", systemImage: "bell", isOn: $notificationsEnabled)
                    ])

                    settingsSection(title: "공개 설정", rows: [
                        toggleRow("프로필 공개 범위", systemImage: "eye", isOn: $isProfilePublic),
                        toggleRow("기록 공개 범위", systemImage: "lock.shield", isOn: $isHistoryPublic)
                    ])

                    settingsSection(title: "정보", rows: [
                        settingsRow("문의하기", subtitle: "지원 페이지", systemImage: "bubble.left") {
                            activeSheet = .externalLink(.support)
                        },
                        settingsRow("이용약관", subtitle: "커뮤니티 가이드라인", systemImage: "doc.text") {
                            activeSheet = .externalLink(.terms)
                        },
                        settingsRow("개인정보처리방침", subtitle: "정책 문서", systemImage: "doc.badge.shield") {
                            activeSheet = .externalLink(.privacy)
                        }
                    ])

                    Text(appVersionText)
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textMuted)

                    if session.isAuthenticated {
                        Button("로그아웃") {
                            Task { await session.signOut(router: router) }
                        }
                        .font(AppTypography.body(15, weight: .semibold))
                        .foregroundStyle(AppPalette.accentRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppPalette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showsProfileEdit) {
            ProfileEditSheet(session: session, profile: session.profile, isPresented: $showsProfileEdit)
        }
        .sheet(item: $activeSheet) { sheet in
            settingsSheetView(sheet)
        }
        .alert(
            "문서를 열 수 없습니다",
            isPresented: Binding(
                get: { externalLinkErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        externalLinkErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                externalLinkErrorMessage = nil
            }
        } message: {
            Text(externalLinkErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            session.container.localStore.setNotificationsEnabled(newValue)
        }
        .onChange(of: isProfilePublic) { _, newValue in
            session.container.localStore.setProfilePublic(newValue)
        }
        .onChange(of: isHistoryPublic) { _, newValue in
            session.container.localStore.setHistoryPublic(newValue)
        }
    }

    @ViewBuilder
    private func settingsSheetView(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case let .externalLink(link):
            SafariSheetView(link: link) {
                handleExternalLinkLoadFailure(link)
            }
            .ignoresSafeArea()
        case let .supportMail(draft):
            SupportMailComposeSheet(draft: draft)
        }
    }

    private func settingsSection(title: String, rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(AppPalette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index != rows.count - 1 {
                        Divider().overlay(AppPalette.border)
                    }
                }
            }
        }
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func settingsRow(_ title: String, subtitle: String, systemImage: String, valueTint: Color = AppPalette.textMuted, action: @escaping () -> Void) -> AnyView {
        AnyView(
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .frame(width: 20)
                    Text(title)
                        .foregroundStyle(AppPalette.textPrimary)
                    Spacer()
                    Text(subtitle)
                        .foregroundStyle(valueTint)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppPalette.textMuted)
                }
                .font(AppTypography.body(13))
                .padding(.horizontal, 16)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
        )
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> AnyView {
        AnyView(
            Toggle(isOn: isOn) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .frame(width: 20)
                    Text(title)
                        .foregroundStyle(AppPalette.textPrimary)
                }
            }
            .font(AppTypography.body(13))
            .padding(.horizontal, 16)
            .frame(height: 48)
            .tint(AppPalette.accentBlue)
        )
    }

    private func handleExternalLinkLoadFailure(_ link: AppExternalLink) {
        activeSheet = nil

        guard link == .support else {
            externalLinkErrorMessage = "\(link.title) 페이지를 열지 못했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
            return
        }

        let draft = makeSupportMailDraft()
        if MFMailComposeViewController.canSendMail() {
            DispatchQueue.main.async {
                activeSheet = .supportMail(draft)
            }
            return
        }

        if let mailtoURL = draft.mailtoURL {
            DispatchQueue.main.async {
                openURL(mailtoURL)
            }
            return
        }

        externalLinkErrorMessage = "지원 페이지와 메일 앱을 모두 열 수 없습니다. \(AppSupportContact.emailAddress)로 직접 문의해 주세요."
    }

    private func makeSupportMailDraft() -> SupportMailDraft {
        let appInfo = AppInfoDescriptor.current()
        let versionText = "\(appInfo.appVersion) (\(appInfo.buildNumber))"
        let body = [
            "문의 유형:",
            "",
            "상세 내용:",
            "",
            "재현 순서:",
            "",
            "추가 참고 사항:",
            "",
            "---",
            "앱 이름: \(appInfo.appName)",
            "앱 버전: \(versionText)",
            "iOS 버전: \(UIDevice.current.systemVersion)",
            "기기 정보: \(currentDeviceModelDescription())",
        ].joined(separator: "\n")

        return SupportMailDraft(
            recipients: [AppSupportContact.emailAddress],
            subject: "[InhouseMaker 문의] ",
            body: body
        )
    }
}

struct SupportMailDraft: Identifiable, Hashable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

struct SafariSheetView: UIViewControllerRepresentable {
    let link: AppExternalLink
    let onInitialLoadFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInitialLoadFailure: onInitialLoadFailure)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: link.url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(hex: 0x4A9FFF)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onInitialLoadFailure: () -> Void

        init(onInitialLoadFailure: @escaping () -> Void) {
            self.onInitialLoadFailure = onInitialLoadFailure
        }

        func safariViewController(
            _ controller: SFSafariViewController,
            didCompleteInitialLoad didLoadSuccessfully: Bool
        ) {
            guard !didLoadSuccessfully else { return }
            onInitialLoadFailure()
        }
    }
}

struct SupportMailComposeSheet: UIViewControllerRepresentable {
    let draft: SupportMailDraft

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}

struct ProfileEditSheet: View {
    @ObservedObject var session: AppSessionViewModel
    let profile: UserProfile?
    @Binding var isPresented: Bool

    @State private var nickname = ""
    @State private var primary: Position = .mid
    @State private var secondary: Position = .top
    @State private var fillAvailable = false
    @State private var styles = "빡겜"

    var body: some View {
        NavigationStack {
            Form {
                TextField("닉네임", text: $nickname)
                Picker("주 포지션", selection: $primary) {
                    ForEach([Position.top, .jungle, .mid, .adc, .support], id: \.self) { position in
                        Text(position.shortLabel).tag(position)
                    }
                }
                Picker("부 포지션", selection: $secondary) {
                    ForEach([Position.top, .jungle, .mid, .adc, .support], id: \.self) { position in
                        Text(position.shortLabel).tag(position)
                    }
                }
                Toggle("전 포지션 가능", isOn: $fillAvailable)
                TextField("성향 태그", text: $styles)
            }
            .onAppear {
                nickname = profile?.nickname ?? ""
                primary = profile?.primaryPosition ?? .mid
                secondary = profile?.secondaryPosition ?? .top
                fillAvailable = profile?.isFillAvailable ?? false
                styles = profile?.styleTags.joined(separator: ", ") ?? "빡겜"
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        Task {
                            guard var current = session.profile else { return }
                            current.nickname = nickname
                            current.primaryPosition = primary
                            current.secondaryPosition = secondary
                            current.isFillAvailable = fillAvailable
                            current.styleTags = styles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            do {
                                let updated = try await session.container.profileRepository.updateProfile(current)
                                session.updateAuthenticatedProfile(updated)
                                await session.refreshProfile()
                                isPresented = false
                            } catch let error as UserFacingError {
                                session.actionState = .failure(error.message)
                            } catch {
                                session.actionState = .failure("프로필 저장에 실패했습니다")
                            }
                        }
                    }
                }
            }
        }
    }
}
