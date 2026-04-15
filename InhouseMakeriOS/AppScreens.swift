import AuthenticationServices
import ComposableArchitecture
import GoogleSignIn
import SwiftUI
import UIKit

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []

    func push(_ route: AppRoute) {
        if let existingIndex = path.lastIndex(of: route) {
            path = Array(path.prefix(existingIndex + 1))
            return
        }
        path.append(route)
    }

    func pop() {
        _ = path.popLast()
    }

    func reset() {
        path.removeAll()
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

    let container: AppContainer
    private(set) var userSession: UserSession?
    private var pendingAuthAction: PendingAuthAction?
    private var deferredAuthPrompt: AuthPromptContext?
    private var suppressNextAuthPromptDismissSync = false

    init(container: AppContainer) {
        self.container = container
    }

    private func debugLog(_ message: String) {
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
        let persistedTokens = await container.authRepository.loadPersistedTokens()

        guard let persistedTokens else {
            syncOnboardingPresentation(hasAuthenticatedSession: false)
            debugLog("bootstrap completed without persisted tokens; session changed to guest")
            state = .guest
            return
        }

        do {
            let profile = try await container.profileRepository.me()
            let session = UserSession(authTokens: persistedTokens, user: profile)
            userSession = session
            syncOnboardingPresentation(hasAuthenticatedSession: true)
            debugLog("bootstrap restored authenticated session for user \(session.user.id)")
            state = .authenticated(session)
        } catch {
            await container.authRepository.signOut()
            userSession = nil
            syncOnboardingPresentation(hasAuthenticatedSession: false)
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

    func signOut(router: AppRouter) async {
        await container.authRepository.signOut()
        router.reset()
        userSession = nil
        selectedTab = .home
        pendingAuthAction = nil
        deferredAuthPrompt = nil
        clearAuthPrompt(userInitiated: false)
        syncOnboardingPresentation(hasAuthenticatedSession: false)
        debugLog("signOut completed; route reset to main home and session changed to guest")
        state = .guest
    }

    func applyAuthenticatedSession(_ session: UserSession) {
        userSession = session
        syncOnboardingPresentation(hasAuthenticatedSession: true)
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
                let posts = try await session.container.recruitingRepository.list(status: .open)
                let power = try? await session.container.profileRepository.powerProfile(userID: userID)
                let history = try await session.container.profileRepository.history(userID: userID, limit: 1)
                let snapshot = HomeSnapshot(
                    profile: profile,
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

        let groups = (try? await session.container.groupRepository.listPublic()) ?? []
        let posts = (try? await session.container.recruitingRepository.listPublic(status: .open)) ?? []
        let guestSnapshot = GuestHomeSnapshot(
            groups: Array(groups.prefix(4)),
            currentMatch: nil,
            latestLocalResult: session.container.localStore.localMatchRecords.first,
            recruitingPosts: Array(posts.prefix(4))
        )

        if groups.isEmpty && guestSnapshot.latestLocalResult == nil && posts.isEmpty {
            state = .empty("아직 둘러볼 공개 그룹이나 모집글이 없습니다.\n팀 밸런스 프리뷰나 결과 프리뷰부터 시작해 보세요.")
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
        var groups: [GroupSummary] = []
        for id in session.container.localStore.storedGroupIDs {
            do {
                let group = try await session.container.groupRepository.detail(groupID: id)
                groups.append(group)
            } catch let error as UserFacingError {
                if error.requiresAuthentication {
                    throw error
                }
            }
        }
        return groups
    }

    private func loadCurrentMatch() async throws -> Match? {
        guard let context = session.container.localStore.recentMatches.first else { return nil }
        return try await session.container.matchRepository.detail(matchID: context.matchID)
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
                state = groups.isEmpty
                    ? .empty("공개 그룹이 아직 없습니다.\n나중에 다시 확인하거나 로그인 후 직접 그룹을 만들어 보세요.")
                    : .content(groups)
                didSucceed = true
            } catch let error as UserFacingError {
                state = .error(error)
            } catch {
                state = .error(UserFacingError(title: "그룹 로딩 실패", message: "공개 그룹 목록을 불러오지 못했습니다."))
            }
            return
        }

        do {
            var groups: [GroupSummary] = []
            for id in session.container.localStore.storedGroupIDs {
                do {
                    let group = try await session.container.groupRepository.detail(groupID: id)
                    groups.append(group)
                } catch let error as UserFacingError {
                    if error.requiresAuthentication {
                        throw error
                    }
                }
            }
            state = groups.isEmpty ? .empty("추적 중인 그룹이 없습니다.\n그룹을 생성하면 이 탭에서 다시 불러옵니다.") : .content(groups)
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

    func createGroup(name: String, description: String, tags: [String]) async -> GroupSummary? {
        actionState = .inProgress("그룹을 생성하는 중입니다")
        do {
            let group = try await session.container.groupRepository.create(
                name: name,
                description: description.isEmpty ? nil : description,
                visibility: .private,
                joinPolicy: .inviteOnly,
                tags: tags
            )
            session.container.localStore.trackGroup(id: group.id)
            session.container.localStore.appendNotification(title: "그룹 생성", body: "\(group.name) 그룹이 생성되었습니다.", symbol: "person.3.fill")
            await load(force: true, trigger: "group_created_refresh")
            actionState = .success("그룹이 생성되었습니다")
            return group
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .groupManagement, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("그룹 생성에 실패했습니다")
            return nil
        }
    }

    func reset() {
        state = .initial
        actionState = .idle
        initialLoadTracker.reset()
    }
}

@MainActor
final class RecruitBoardViewModel: ObservableObject {
    @Published private(set) var state: ScreenLoadState<RecruitBoardSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle
    @Published var selectedType: RecruitingPostType

    private let session: AppSessionViewModel
    private let initialLoadTracker = InitialLoadTracker(screen: "recruit")

    init(session: AppSessionViewModel) {
        self.session = session
        self.selectedType = session.container.localStore.recruitFilterType
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }
        state = .loading
        do {
            let posts: [RecruitPost]
            if session.isGuest {
                posts = try await session.container.recruitingRepository.listPublic(type: selectedType, status: .open)
            } else {
                posts = try await session.container.recruitingRepository.list(type: selectedType, status: .open)
            }
            let snapshot = RecruitBoardSnapshot(selectedType: selectedType, posts: posts)
            state = posts.isEmpty ? .empty("현재 조건에 맞는 모집글이 없습니다.") : .content(snapshot)
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
        selectedType = type
        session.container.localStore.setRecruitFilterType(type)
        await load(force: true, trigger: "type_switch")
    }

    func createPost(groupID: String, title: String, body: String, tags: [String], positions: [String]) async {
        actionState = .inProgress("모집글을 등록하는 중입니다")
        do {
            let post = try await session.container.recruitingRepository.create(
                groupID: groupID,
                type: selectedType,
                title: title,
                body: body.isEmpty ? nil : body,
                tags: tags,
                scheduledAt: nil,
                requiredPositions: positions
            )
            session.container.localStore.appendNotification(title: "모집글 등록", body: "\(post.title) 글이 등록되었습니다.", symbol: "megaphone.fill")
            actionState = .success("모집글이 등록되었습니다")
            await load(force: true, trigger: "post_created_refresh")
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .recruitingWrite, actionState: &actionState)
        } catch {
            actionState = .failure("모집글 등록에 실패했습니다")
        }
    }

    func reset() {
        state = .initial
        actionState = .idle
        selectedType = session.container.localStore.recruitFilterType
        initialLoadTracker.reset()
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
            let power = try? await session.container.profileRepository.powerProfile(userID: userID)
            let riotAccounts = (try? await session.container.riotRepository.list()) ?? []
            let history = (try? await session.container.profileRepository.history(userID: userID, limit: 10)) ?? []
            state = .content(.authenticated(ProfileSnapshot(profile: profile, power: power, riotAccounts: riotAccounts, history: history)))
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
    static func home(power: PowerProfile?) -> HomePowerCardViewState {
        HomePowerCardViewState(
            overview: overview(
                power: power,
                history: [],
                hasLinkedRiotAccount: true,
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
            message: "여기 표시되는 파워는 마지막 내전 참여 시점의 스냅샷이에요. 각 멤버의 최신 종합 파워는 프로필에서 확인할 수 있어요."
        )
    }

    static func groupMember(member: GroupMember, powerProfile: PowerProfile?) -> GroupMemberPowerRowViewState {
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
                supportingText: "최근 경기와 결과 입력이 쌓이면 파워가 계산돼요",
                insightText: "파워를 계산할 데이터가 아직 충분하지 않아요",
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
                ? "최근 10경기 기준 · 라이엇 연동 데이터 반영"
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
                description: "내전 결과와 라이엇 데이터가 연결되면 계산돼요",
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
                    description: "내전 매칭 결과를 기반으로 산출되는 실력 지표예요. 라이엇 계정 데이터도 함께 반영돼요.",
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
    private let initialLoadTracker = InitialLoadTracker(screen: "power_detail")

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false, trigger: String = "unknown") async {
        guard initialLoadTracker.begin(force: force, trigger: trigger) else { return }
        var didSucceed = false
        defer { initialLoadTracker.finish(success: didSucceed) }

        guard let userID = session.currentUserID else {
            state = .empty("로그인 후 파워 상세를 확인할 수 있어요.")
            return
        }

        state = .loading

        let power = try? await session.container.profileRepository.powerProfile(userID: userID)
        let history = (try? await session.container.profileRepository.history(userID: userID, limit: 10)) ?? []
        let riotAccounts = (try? await session.container.riotRepository.list()) ?? []

        state = .content(
            PowerViewStateBuilder.detail(
                power: power,
                history: history,
                hasLinkedRiotAccount: riotAccounts.isEmpty == false
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

// MARK: - Restored Shell View Models

@MainActor
final class GroupDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<GroupDetailSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle

    private let session: AppSessionViewModel
    let groupID: String

    init(session: AppSessionViewModel, groupID: String) {
        self.session = session
        self.groupID = groupID
    }

    func load(force: Bool = false) async {
        if !force, case .content = state { return }
        state = .loading
        do {
            let group = try await session.container.groupRepository.detail(groupID: groupID)
            let members = try await session.container.groupRepository.members(groupID: groupID)
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
            let powerProfiles = await loadPowerProfiles(for: members.map(\.userID))
            state = .content(
                GroupDetailSnapshot(
                    group: group,
                    members: members,
                    latestMatch: latestHistory?.first,
                    powerProfiles: powerProfiles
                )
            )
            session.container.localStore.trackGroup(id: groupID)
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .groupManagement,
                state: &state,
                fallbackMessage: "로그인 후 그룹 상세를 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "그룹 상세 로딩 실패", message: "그룹 정보를 불러오지 못했습니다."))
        }
    }

    func createMatch() async -> Match? {
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

    func inviteMember(userID: String) async {
        actionState = .inProgress("멤버를 초대하는 중입니다")
        do {
            _ = try await session.container.groupRepository.addMember(groupID: groupID, userID: userID)
            actionState = .success("멤버가 추가되었습니다")
            await load(force: true)
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .groupManagement, actionState: &actionState)
        } catch {
            actionState = .failure("멤버 추가에 실패했습니다")
        }
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
        state = .loading
        do {
            let match = try await session.container.matchRepository.detail(matchID: matchID)
            let result = try? await session.container.matchRepository.result(matchID: matchID)
            let cache = session.container.localStore.cachedResults[matchID]
            state = .content(MatchDetailSnapshot(match: match, result: result, cachedMetadata: cache))
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .resultSave,
                state: &state,
                fallbackMessage: "로그인 후 경기 상세를 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "경기 상세 로딩 실패", message: "경기 상세를 불러오지 못했습니다."))
        }
    }

    func rematch() async -> Match? {
        guard let snapshot = state.value else { return nil }
        actionState = .inProgress("같은 인원으로 재매칭을 준비하는 중입니다")
        do {
            let newMatch = try await session.container.matchRepository.create(groupID: snapshot.match.groupID, title: "재매칭")
            _ = try await session.container.matchRepository.addPlayers(
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
            actionState = .success("재매칭 로비를 생성했습니다")
            return newMatch
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .matchSave, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("재매칭 생성에 실패했습니다")
            return nil
        }
    }
}

@MainActor
final class RiotAccountsViewModel: ObservableObject {
    @Published var state: ScreenLoadState<RiotAccountSnapshot> = .initial
    @Published var actionState: AsyncActionState = .idle
    @Published var syncInProgressIDs: Set<String> = []

    private let session: AppSessionViewModel

    init(session: AppSessionViewModel) {
        self.session = session
    }

    func load(force: Bool = false) async {
        guard session.isAuthenticated else {
            state = .empty("로그인하면 Riot 계정 연동과 동기화를 사용할 수 있어요.")
            return
        }
        if !force, case .content = state { return }
        state = .loading
        do {
            let accounts = try await session.container.riotRepository.list()
            let snapshot = RiotAccountSnapshot(accounts: accounts, syncInProgressIDs: syncInProgressIDs)
            state = accounts.isEmpty ? .empty("연결된 Riot 계정이 없습니다.") : .content(snapshot)
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .riotAccount,
                state: &state,
                fallbackMessage: "로그인 후 Riot 계정을 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "Riot 계정 로딩 실패", message: "Riot 계정을 불러오지 못했습니다."))
        }
    }

    func connect(gameName: String, tagLine: String, region: String, isPrimary: Bool) async {
        guard session.isAuthenticated else {
            actionState = .failure("로그인 후 Riot 계정을 연결할 수 있어요.")
            return
        }
        actionState = .inProgress("계정을 연결하는 중입니다")
        do {
            _ = try await session.container.riotRepository.connect(
                gameName: gameName,
                tagLine: tagLine,
                region: region,
                isPrimary: isPrimary
            )
            actionState = .success("계정이 연결되었습니다")
            await load(force: true)
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .riotAccount, actionState: &actionState)
        } catch {
            actionState = .failure("계정 연결에 실패했습니다")
        }
    }

    func sync(id: String) async {
        guard session.isAuthenticated else {
            actionState = .failure("로그인 후 Riot 계정 동기화를 사용할 수 있어요.")
            return
        }
        syncInProgressIDs.insert(id)
        actionState = .inProgress("동기화를 요청하는 중입니다")
        do {
            try await session.container.riotRepository.sync(accountID: id)
            session.container.localStore.appendNotification(title: "Riot 동기화 요청", body: "Riot 계정 동기화가 큐에 등록되었습니다.", symbol: "arrow.clockwise")
            actionState = .success("동기화 요청을 보냈습니다")
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .riotAccount, actionState: &actionState)
        } catch {
            actionState = .failure("동기화 요청에 실패했습니다")
        }
        syncInProgressIDs.remove(id)
        await load(force: true)
    }
}

@MainActor
final class RecruitDetailViewModel: ObservableObject {
    @Published var state: ScreenLoadState<RecruitPost> = .initial
    @Published var actionState: AsyncActionState = .idle

    private let session: AppSessionViewModel
    let postID: String

    init(session: AppSessionViewModel, postID: String) {
        self.session = session
        self.postID = postID
    }

    func load(force: Bool = false) async {
        if !force, case .content = state { return }
        state = .loading
        do {
            let post = try await session.container.recruitingRepository.detail(postID: postID)
            state = .content(post)
        } catch let error as UserFacingError {
            session.handleProtectedLoadError(
                error,
                requirement: .recruitingWrite,
                state: &state,
                fallbackMessage: "로그인 후 모집 상세를 다시 확인할 수 있어요."
            )
        } catch {
            state = .error(UserFacingError(title: "모집 상세 로딩 실패", message: "모집 상세를 불러오지 못했습니다."))
        }
    }

    func createMatch() async -> Match? {
        guard let post = state.value else { return nil }
        actionState = .inProgress("모집글 기반 내전을 생성하는 중입니다")
        do {
            let match = try await session.container.matchRepository.create(groupID: post.groupID, title: post.title)
            actionState = .success("내전이 생성되었습니다")
            return match
        } catch let error as UserFacingError {
            session.handleProtectedActionError(error, requirement: .matchSave, actionState: &actionState)
            return nil
        } catch {
            actionState = .failure("내전 생성에 실패했습니다")
            return nil
        }
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
            VStack(spacing: 0) {
                rootContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                AppTabBar(selectedTab: session.selectedTab) { tab in
                    session.selectedTab = tab
                    Task {
                        await loadSelectedTab()
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destinationView(route)
            }
            .sheet(item: $session.authPrompt) { prompt in
                AuthGateSheet(session: session, prompt: prompt)
            }
            .task(id: session.dataScopeKey) {
                resetViewModelsForSessionChange()
                await loadSelectedTab(force: true)
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

    @ViewBuilder
    private func destinationView(_ route: AppRoute) -> some View {
        switch route {
        case .notifications:
            NotificationsScreen(store: session.container.localStore, onBack: router.pop)
        case .riotAccounts:
            RiotAccountsScreen(viewModel: RiotAccountsViewModel(session: session), session: session, onBack: router.pop)
        case .settings:
            SettingsScreen(session: session, router: router, onBack: router.pop)
        case let .groupDetail(groupID):
            GroupDetailScreen(viewModel: GroupDetailViewModel(session: session, groupID: groupID), router: router)
        case let .matchLobby(groupID, matchID):
            MatchLobbyFeatureView(
                store: Store(
                    initialState: MatchLobbyFeature.State(groupID: groupID, matchID: matchID)
                ) {
                    MatchLobbyFeature()
                } withDependencies: {
                    $0.appContainer = session.container
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
                    $0.appContainer = session.container
                },
                session: session,
                router: router
            )
        case .teamBalancePreview:
            TeamBalancePreviewScreen(session: session, router: router)
        case let .manualAdjust(matchID, draft):
            ManualAdjustFeatureView(
                store: Store(
                    initialState: ManualAdjustFeature.State(matchID: matchID, draft: draft)
                ) {
                    ManualAdjustFeature()
                },
                onBack: router.pop
            )
        case let .matchResult(matchID):
            MatchResultFeatureView(
                store: Store(
                    initialState: MatchResultFeature.State(matchID: matchID)
                ) {
                    MatchResultFeature()
                } withDependencies: {
                    $0.appContainer = session.container
                },
                session: session,
                router: router
            )
        case .resultPreview:
            ResultPreviewScreen(session: session, router: router)
        case let .matchDetail(matchID):
            MatchDetailScreen(viewModel: MatchDetailViewModel(session: session, matchID: matchID), router: router)
        case let .recruitDetail(postID):
            RecruitDetailScreen(viewModel: RecruitDetailViewModel(session: session, postID: postID), router: router)
        }
    }

    private func loadSelectedTab(force: Bool = false) async {
        switch session.selectedTab {
        case .home:
            await homeViewModel.load(force: force)
        case .match:
            await groupViewModel.load(force: force)
        case .recruit:
            await recruitViewModel.load(force: force)
        case .history:
            await historyViewModel.load(force: force)
        case .profile:
            await profileViewModel.load(force: force)
        }
    }

    private func resetViewModelsForSessionChange() {
        homeViewModel.reset()
        groupViewModel.reset()
        recruitViewModel.reset()
        historyViewModel.reset()
        profileViewModel.reset()
    }
}

struct HomeScreen: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        content
            .task { await viewModel.load() }
            .navigationTitle("내전 메이커")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        session.openProtectedRoute(.notifications, requirement: .notifications, router: router)
                    } label: {
                        Image(systemName: "bell")
                    }

                    Button {} label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .appNavigationBarStyle(.large)
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
                                    router.push(.teamBalancePreview)
                                }
                            }
                            quickAction(symbol: "checkmark.circle", title: "결과\n입력", tint: AppPalette.accentGreen) {
                                if let match = currentMatch {
                                    router.push(.matchResult(matchID: match.id))
                                } else {
                                    router.push(.resultPreview)
                                }
                            }
                            quickAction(symbol: "megaphone", title: "상대팀\n모집", tint: AppPalette.accentOrange) {
                                session.selectedTab = .recruit
                            }
                        }

                        SectionHeaderView(title: "예정된 내전") {}
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

                        SectionHeaderView(title: "최근 참여 그룹")
                        HStack(spacing: 10) {
                            ForEach(Array(groups.prefix(2))) { group in
                                Button {
                                    session.openProtectedRoute(.groupDetail(group.id), requirement: .groupManagement, router: router)
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

                        switch contentState {
                        case let .authenticated(snapshot):
                            SectionHeaderView(title: "내 파워 프로필")
                            powerSummaryCard(profile: snapshot.profile, power: snapshot.power)

                            SectionHeaderView(title: "최근 경기")
                            if let latestHistory = snapshot.latestHistory {
                                MatchCardView(
                                    title: snapshot.groups.first?.name ?? "롤내전모임",
                                    dateText: latestHistory.scheduledAt.dottedDateText,
                                    isWin: latestHistory.result == "WIN",
                                    blueSummary: "블루 팀",
                                    redSummary: "레드 팀",
                                    detail: "KDA \(latestHistory.kda) · MMR \(Int(latestHistory.deltaMMR))"
                                )
                            } else {
                                guestBenefitCard(
                                    title: "아직 계정 기록이 없어요",
                                    message: "경기 결과를 저장하면 최근 내전 성적이 여기에 쌓입니다.",
                                    buttonTitle: "결과 입력하러 가기"
                                ) {
                                    if let match = currentMatch {
                                        router.push(.matchResult(matchID: match.id))
                                    } else {
                                        router.push(.resultPreview)
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
                                        router.push(.resultPreview)
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

    private func powerSummaryCard(profile: UserProfile, power: PowerProfile?) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Int((power?.overallPower ?? 76).rounded()))")
                    .font(AppTypography.heading(40, weight: .heavy))
                    .foregroundStyle(AppPalette.accentBlue)
                Text("종합 파워")
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textMuted)
                Text(profile.nickname)
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(AppPalette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                statRow(label: "최근 폼", value: Int((power?.formScore ?? 76).rounded()), tint: AppPalette.textPrimary)
                statRow(label: "안정성", value: Int((power?.stability ?? 82).rounded()), tint: AppPalette.textSecondary)
                statRow(label: "캐리 기여", value: Int((power?.carry ?? 71).rounded()), tint: AppPalette.textSecondary)
                statRow(label: "팀 기여도", value: Int((power?.teamContribution ?? 85).rounded()), tint: AppPalette.textSecondary)
                statRow(label: "내전 MMR", value: Int((power?.inhouseMMR ?? 1420).rounded()), tint: AppPalette.accentGold)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(background: AppPalette.bgCard, radius: 12)
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

    private func statRow(label: String, value: Int, tint: Color) -> some View {
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
}

struct GroupMainScreen: View {
    @ObservedObject var viewModel: GroupMainViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var showsCreateSheet = false
    @State private var newGroupName = ""
    @State private var newGroupDescription = ""
    @State private var newGroupTags = "빡겜,서울"

    var body: some View {
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
                        showsCreateSheet = true
                    }
                }
                .sheet(isPresented: $showsCreateSheet) { groupCreationSheet }
            case let .content(groups), let .refreshing(groups):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 16) {
                            ForEach(groups) { group in
                                Button {
                                    session.openProtectedRoute(.groupDetail(group.id), requirement: .groupManagement, router: router)
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
                .sheet(isPresented: $showsCreateSheet) { groupCreationSheet }
                .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
            }
        }
        .navigationTitle("그룹")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .appNavigationBarStyle(.large)
    }

    private var groupCreationSheet: some View {
        NavigationStack {
            Form {
                TextField("그룹 이름", text: $newGroupName)
                TextField("설명", text: $newGroupDescription, axis: .vertical)
                TextField("태그 (쉼표 구분)", text: $newGroupTags)
                Text("실제 서버에는 그룹 목록 API가 없어, 생성 또는 방문한 groupId를 클라이언트에 저장한 뒤 이 탭에서 다시 조회합니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.bgPrimary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { showsCreateSheet = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("생성") {
                        let action: @MainActor () -> Void = {
                            Task {
                                let created = await viewModel.createGroup(
                                    name: newGroupName,
                                    description: newGroupDescription,
                                    tags: newGroupTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                )
                                if let created {
                                    showsCreateSheet = false
                                    router.push(.groupDetail(created.id))
                                }
                            }
                        }
                        session.requireAuthentication(for: .groupManagement, perform: action)
                    }
                    .disabled(newGroupName.count < 2)
                }
            }
        }
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
    @State private var inviteUserID = ""
    @State private var showsInviteSheet = false

    var body: some View {
        screenScaffold(title: "롤내전모임", onBack: router.pop) {
            switch viewModel.state {
            case .initial, .loading:
                LoadingStateView(title: "그룹 상세를 불러오는 중입니다")
                    .task { await viewModel.load() }
            case let .error(error):
                ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
            case .empty:
                EmptyStateView(title: "그룹", message: "표시할 그룹이 없습니다.")
            case let .content(snapshot), let .refreshing(snapshot):
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
                            Text("멤버 (\(snapshot.members.count))")
                                .font(AppTypography.heading(16, weight: .bold))
                            ForEach(Array(snapshot.members.prefix(6))) { member in
                                PlayerCardView(
                                    name: member.nickname,
                                    subtitle: "\(roleText(for: member.role)) · \(snapshot.powerProfiles[member.userID] == nil ? "파워 미연동" : "파워 프로필 연동")",
                                    powerScore: Int(snapshot.powerProfiles[member.userID]?.overallPower.rounded() ?? 0)
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeaderView(title: "지난 내전", showsTrailing: false)
                            if let history = snapshot.latestMatch {
                                MatchCardView(
                                    title: snapshot.group.name,
                                    dateText: history.scheduledAt.dottedDateText,
                                    isWin: history.result == "WIN",
                                    blueSummary: "블루 팀",
                                    redSummary: "레드 팀",
                                    detail: "KDA \(history.kda) · \(history.role.shortLabel)"
                                )
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
                    ToolbarItem(placement: .topBarLeading) { Button("닫기") { showsInviteSheet = false } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("추가") {
                            Task {
                                await viewModel.inviteMember(userID: inviteUserID)
                                showsInviteSheet = false
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
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

    private func roleText(for role: GroupRole) -> String {
        switch role {
        case .owner:
            return "방장"
        case .admin:
            return "운영진"
        case .member:
            return "멤버"
        }
    }
}

struct RecruitBoardScreen: View {
    @ObservedObject var viewModel: RecruitBoardViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var showsCreateSheet = false
    @State private var createTitle = ""
    @State private var createBody = ""
    @State private var createPositions = "MID,SUP"

    var body: some View {
        Group {
            switch viewModel.state {
            case .initial, .loading:
                LoadingStateView(title: "모집글을 불러오는 중입니다")
                    .task { await viewModel.load() }
            case let .error(error):
                ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
            case let .empty(message):
                VStack(spacing: 0) {
                    StatusBarView()
                    EmptyStateView(title: "모집", message: message, actionTitle: "글 작성") {
                        showsCreateSheet = true
                    }
                }
                .sheet(isPresented: $showsCreateSheet) { createSheet }
            case let .content(snapshot), let .refreshing(snapshot):
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

                            HStack(spacing: 8) {
                                FilterChipView(title: "날짜", tint: AppPalette.textMuted)
                                FilterChipView(title: "포지션", tint: AppPalette.textMuted)
                                FilterChipView(title: "지역", tint: AppPalette.textMuted)
                                FilterChipView(title: "성향", tint: AppPalette.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(snapshot.posts) { post in
                                Button {
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
                                            Text(post.groupID)
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
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }
                .sheet(isPresented: $showsCreateSheet) { createSheet }
                .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
            }
        }
        .navigationTitle("모집")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCreateSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .appNavigationBarStyle(.large)
    }

    private func typeButton(_ type: RecruitingPostType) -> some View {
        Button(type.title) {
            Task { await viewModel.switchType(type) }
        }
        .font(AppTypography.body(13, weight: viewModel.selectedType == type ? .semibold : .regular))
        .foregroundStyle(viewModel.selectedType == type ? Color.white : AppPalette.textMuted)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(viewModel.selectedType == type ? AppPalette.accentBlue : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("제목", text: $createTitle)
                TextField("본문", text: $createBody, axis: .vertical)
                TextField("포지션 (쉼표 구분)", text: $createPositions)
                Text("모집글 생성은 실제 서버를 호출합니다. groupId는 로컬에 저장된 첫 그룹을 사용합니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { showsCreateSheet = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("등록") {
                        let action: @MainActor () -> Void = {
                            Task {
                                guard let groupID = session.container.localStore.storedGroupIDs.first else {
                                    viewModel.actionState = .failure("모집글을 연결할 그룹이 없습니다. 먼저 로그인 후 그룹을 생성해주세요.")
                                    return
                                }
                                await viewModel.createPost(
                                    groupID: groupID,
                                    title: createTitle,
                                    body: createBody,
                                    tags: ["빡겜"],
                                    positions: createPositions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                )
                                showsCreateSheet = false
                            }
                        }
                        session.requireAuthentication(for: .recruitingWrite, perform: action)
                    }
                    .disabled(createTitle.count < 2)
                }
            }
        }
    }
}

struct RecruitDetailScreen: View {
    @ObservedObject var viewModel: RecruitDetailViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        screenScaffold(title: "모집 상세", onBack: router.pop) {
            switch viewModel.state {
            case .initial, .loading:
                LoadingStateView(title: "모집 상세를 불러오는 중입니다")
                    .task { await viewModel.load() }
            case let .error(error):
                ErrorStateView(error: error) { Task { await viewModel.load(force: true) } }
            case .empty:
                EmptyStateView(title: "모집 상세", message: "모집글을 찾을 수 없습니다.")
            case let .content(post), let .refreshing(post):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.title)
                                .font(AppTypography.heading(18, weight: .bold))
                            HStack(spacing: 12) {
                                Text(post.groupID)
                                if let scheduledAt = post.scheduledAt {
                                    Text(scheduledAt.shortDateText)
                                }
                                Text(post.createdBy ?? "작성자 미상")
                            }
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("모집 정보")
                                .font(AppTypography.body(14, weight: .semibold))
                            infoRow("필요 포지션", value: post.requiredPositions.joined(separator: ", "))
                            infoRow("상태", value: post.status.rawValue)
                            infoRow("분위기", value: post.tags.joined(separator: ", "))
                            infoRow("예상 시간", value: post.scheduledAt?.shortDateText ?? "미정")
                        }
                        .padding(16)
                        .background(AppPalette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("상세 설명")
                                .font(AppTypography.heading(15, weight: .bold))
                            Text(post.body ?? "상세 설명이 없습니다.")
                                .font(AppTypography.body(13))
                                .foregroundStyle(AppPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 8) {
                    Button("참가 신청") {
                        viewModel.actionState = .failure("실제 서버에 참가 신청 endpoint가 없어 현재 단계에서는 지원하지 않습니다.")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("내전 생성") {
                        Task {
                            if let match = await viewModel.createMatch() {
                                router.push(.matchLobby(groupID: post.groupID, matchID: match.id))
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: AppPalette.accentPurple))
                    .frame(maxWidth: 120)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppPalette.bgSecondary)
            }
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
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
}

struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
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
        .navigationTitle("기록")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .appNavigationBarStyle(.large)
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
                    VStack(spacing: 14) {
                        VStack(spacing: 10) {
                            Text(snapshot.match.scheduledAt?.dottedDateText ?? Date().dottedDateText)
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textMuted)
                            HStack(spacing: 16) {
                                Text("블루")
                                    .foregroundStyle(AppPalette.teamBlue)
                                Text("VS")
                                    .foregroundStyle(AppPalette.textSecondary)
                                Text("레드")
                                    .foregroundStyle(AppPalette.teamRed)
                            }
                            .font(AppTypography.heading(18, weight: .bold))
                            if let result = snapshot.result {
                                Text(result.resultStatus.title)
                                    .font(AppTypography.body(12))
                                    .foregroundStyle(AppPalette.accentGreen)
                            }
                            if let cache = snapshot.cachedMetadata {
                                HStack(spacing: 16) {
                                    overviewStat("예상 밸런스", value: "\(cache.balanceRating)/5")
                                    overviewStat("승리 팀", value: cache.winningTeam.title)
                                    overviewStat("MVP", value: mvpName(cache.mvpUserID, match: snapshot.match))
                                }
                            } else {
                                Text("서버 결과 상세 응답에는 MVP와 체감 밸런스가 포함되지 않아, 클라이언트에서 저장한 값이 있을 때만 표시합니다.")
                                    .font(AppTypography.body(12))
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x1A2744), AppPalette.bgPrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        if let result = snapshot.result {
                            HStack(spacing: 8) {
                                statsColumn(title: "블루 팀", tint: AppPalette.teamBlue, players: teamPlayers(side: .blue, match: snapshot.match, result: result))
                                statsColumn(title: "레드 팀", tint: AppPalette.teamRed, players: teamPlayers(side: .red, match: snapshot.match, result: result))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("파워 변화량")
                                .font(AppTypography.heading(14, weight: .bold))
                            VStack(spacing: 6) {
                                ForEach(snapshot.match.players) { player in
                                    HStack {
                                        Text(player.nickname)
                                        Spacer()
                                        Text(deltaText(for: player, snapshot: snapshot))
                                            .foregroundStyle(deltaColor(for: player, snapshot: snapshot))
                                    }
                                    .font(AppTypography.body(13, weight: .semibold))
                                }
                            }
                            .padding(14)
                            .background(AppPalette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                }

                Button("같은 인원으로 재매칭") {
                    Task {
                        if let match = await viewModel.rematch() {
                            router.push(.matchLobby(groupID: snapshot.match.groupID, matchID: match.id))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppPalette.accentPurple))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppPalette.bgSecondary)
            }
        }
        .overlay(alignment: .bottom) { actionBanner(viewModel.actionState) }
    }

    private func overviewStat(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
            Text(value)
                .font(AppTypography.body(13, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
        }
    }

    private func statsColumn(title: String, tint: Color, players: [(MatchPlayer, MatchStat?)]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(AppTypography.heading(12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(tint)
            VStack(spacing: 0) {
                ForEach(players, id: \.0.id) { player, stat in
                    HStack {
                        Text(player.assignedRole?.shortLabel ?? "-")
                            .font(AppTypography.body(9, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 26, alignment: .leading)
                        Text(player.nickname)
                            .font(AppTypography.body(11, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(stat?.kills ?? 0)/\(stat?.deaths ?? 0)/\(stat?.assists ?? 0)")
                            .font(AppTypography.body(11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                }
            }
            .background(title.contains("블루") ? Color(hex: 0x0D1B2A) : Color(hex: 0x2A0D0D))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func teamPlayers(side: TeamSide, match: Match, result: MatchResult) -> [(MatchPlayer, MatchStat?)] {
        match.players
            .filter { $0.teamSide == side }
            .map { player in
                (player, result.players.first(where: { $0.userID == player.userID }))
            }
    }

    private func deltaText(for player: MatchPlayer, snapshot: MatchDetailSnapshot) -> String {
        guard let result = snapshot.result, let teamSide = player.teamSide else { return "±0" }
        let confidence: Double = result.resultStatus == .confirmed ? 1 : result.resultStatus == .partial ? 0.5 : 0
        let didWin = result.winningTeam == teamSide
        let value = Int((didWin ? 18 : -18) * confidence)
        return value >= 0 ? "+\(value)" : "\(value)"
    }

    private func deltaColor(for player: MatchPlayer, snapshot: MatchDetailSnapshot) -> Color {
        deltaText(for: player, snapshot: snapshot).hasPrefix("+") ? AppPalette.accentGreen : AppPalette.accentRed
    }

    private func mvpName(_ userID: String, match: Match) -> String {
        match.players.first(where: { $0.userID == userID })?.nickname ?? "미상"
    }
}

struct TeamBalancePreviewScreen: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var draft: TeamBalancePreviewDraft
    @State private var actionState: AsyncActionState = .idle
    @State private var remotePreviewResult: TeamBalancePreviewResult?
    @State private var previewStatusMessage: String?
    @State private var previewSyncTask: Task<Void, Never>?

    init(session: AppSessionViewModel, router: AppRouter) {
        self.session = session
        self.router = router
        _draft = State(initialValue: session.container.localStore.teamBalancePreviewDraft)
    }

    private var previewResult: TeamBalancePreviewResult? {
        remotePreviewResult ?? draft.makePreviewResult()
    }

    var body: some View {
        screenScaffold(title: "팀 밸런스 프리뷰", onBack: router.pop) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    previewIntroCard(
                        badge: "PREVIEW",
                        title: "게스트 팀 밸런스 프리뷰",
                        message: "로그인 없이 임시 로스터를 구성해 팀 밸런스를 확인할 수 있어요. 이 화면의 입력값과 결과는 실제 매치에 저장되지 않고, 이 기기에만 임시 저장됩니다."
                    )

                    if let previewStatusMessage {
                        previewStatusCard(message: previewStatusMessage)
                    }

                    sectionCard(title: "밸런스 모드", spacing: 8) {
                        HStack(spacing: 8) {
                            previewModeButton(.balanced)
                            previewModeButton(.positionFirst)
                            previewModeButton(.skillFirst)
                        }
                    }

                    sectionCard(title: "임시 로스터", spacing: 10) {
                        ForEach($draft.players) { $player in
                            VStack(spacing: 10) {
                                TextField("닉네임", text: $player.name)
                                    .textFieldStyle(.roundedBorder)

                                HStack(spacing: 10) {
                                    Picker("포지션", selection: $player.preferredPosition) {
                                        ForEach([Position.top, .jungle, .mid, .adc, .support], id: \.self) { position in
                                            Text(position.shortLabel).tag(position)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Stepper(value: $player.score, in: 40 ... 100, step: 1) {
                                        Text("점수 \(player.score)")
                                            .font(AppTypography.body(12, weight: .semibold))
                                    }
                                }
                            }
                            .padding(12)
                            .appPanel(background: AppPalette.bgCard, radius: 10)
                        }
                    }

                    if let previewResult {
                        sectionCard(title: "프리뷰 결과", spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("블루 \(previewResult.blueTotal)")
                                        .font(AppTypography.heading(22, weight: .heavy))
                                        .foregroundStyle(AppPalette.teamBlue)
                                    Text("레드 \(previewResult.redTotal)")
                                        .font(AppTypography.body(13, weight: .semibold))
                                        .foregroundStyle(AppPalette.teamRed)
                                }
                                Spacer()
                                Text(previewResult.headline)
                                    .font(AppTypography.body(13, weight: .semibold))
                                    .foregroundStyle(AppPalette.accentGold)
                            }

                            HStack(spacing: 10) {
                                previewTeamColumn(title: "블루", tint: AppPalette.teamBlue, players: previewResult.bluePlayers)
                                previewTeamColumn(title: "레드", tint: AppPalette.teamRed, players: previewResult.redPlayers)
                            }
                        }
                    }

                    sectionCard(title: "다음 액션", spacing: 10) {
                        Button("결과 프리뷰로 이어서 보기") {
                            let nextDraft = previewResult.map(ResultPreviewDraft.defaultValue(from:)) ?? .defaultValue(from: draft)
                            session.container.localStore.setResultPreviewDraft(nextDraft)
                            router.push(.resultPreview)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        HStack(spacing: 8) {
                            Button("샘플로 초기화") {
                                draft = .defaultValue
                                actionState = .success("샘플 로스터로 초기화했습니다.")
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("로그인 후 실제 매치로 저장") {
                                session.requireAuthentication(for: .matchSave)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        Text("프리뷰 로스터와 최근 입력값은 이 기기에서만 유지됩니다. 로그인 후에도 자동 저장되지 않으며, 원할 때만 실제 매치 생성으로 이어집니다.")
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
        }
        .overlay(alignment: .bottom) { actionBanner(actionState) }
        .onAppear {
            schedulePreviewRefresh(immediate: true)
        }
        .onDisappear {
            previewSyncTask?.cancel()
        }
        .onChange(of: draft) { _, newValue in
            session.container.localStore.setTeamBalancePreviewDraft(newValue)
            schedulePreviewRefresh()
        }
    }

    private func previewIntroCard(badge: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(badge)
                .font(AppTypography.body(10, weight: .semibold))
                .foregroundStyle(AppPalette.accentGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppPalette.bgTertiary)
                .clipShape(Capsule())
            Text(title)
                .font(AppTypography.heading(18, weight: .bold))
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }

    private func previewStatusCard(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(AppPalette.accentBlue)
            Text(message)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .appPanel(background: AppPalette.bgSecondary, radius: 10)
    }

    private func sectionCard<Content: View>(title: String, spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(AppTypography.heading(16, weight: .bold))
            content()
        }
        .padding(14)
        .appPanel(background: AppPalette.bgSecondary, radius: 12)
    }

    private func previewModeButton(_ mode: BalanceMode) -> some View {
        Button {
            draft.selectedMode = mode
        } label: {
            Text(mode.title)
                .font(AppTypography.body(12, weight: draft.selectedMode == mode ? .semibold : .regular))
                .foregroundStyle(draft.selectedMode == mode ? Color.white : AppPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(draft.selectedMode == mode ? AppPalette.accentBlue : AppPalette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func previewTeamColumn(title: String, tint: Color, players: [PreviewRosterPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(13, weight: .semibold))
                .foregroundStyle(tint)
            ForEach(players) { player in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.sanitizedName)
                            .font(AppTypography.body(12, weight: .semibold))
                        Text(player.preferredPosition.shortLabel)
                            .font(AppTypography.body(10))
                            .foregroundStyle(AppPalette.textMuted)
                    }
                    Spacer()
                    Text("\(player.clampedScore)")
                        .font(AppTypography.body(12, weight: .semibold))
                }
                .padding(10)
                .appPanel(background: AppPalette.bgCard, radius: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func schedulePreviewRefresh(immediate: Bool = false) {
        previewSyncTask?.cancel()
        let draftSnapshot = draft
        if !draftSnapshot.isReady {
            remotePreviewResult = nil
            previewStatusMessage = "10명 로스터를 채우면 서버 프리뷰 기준으로 조합을 확인할 수 있어요."
            return
        }
        previewSyncTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            await refreshPreview(for: draftSnapshot)
        }
    }

    @MainActor
    private func refreshPreview(for draftSnapshot: TeamBalancePreviewDraft) async {
        do {
            let result = try await session.container.matchRepository.previewBalance(draft: draftSnapshot)
            guard !Task.isCancelled else { return }
            remotePreviewResult = result
            previewStatusMessage = "서버 프리뷰 기준으로 계산된 조합입니다."
        } catch let error as UserFacingError {
            guard !Task.isCancelled else { return }
            remotePreviewResult = nil
            previewStatusMessage = error.isRateLimited
                ? "프리뷰 요청이 많아요. 잠시 후 다시 확인해 주세요."
                : "서버 프리뷰를 확인하지 못해 이 기기 계산 결과를 보여주고 있어요."
        } catch {
            guard !Task.isCancelled else { return }
            remotePreviewResult = nil
            previewStatusMessage = "서버 프리뷰를 확인하지 못해 이 기기 계산 결과를 보여주고 있어요."
        }
    }
}

struct ResultPreviewScreen: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var draft: ResultPreviewDraft
    @State private var actionState: AsyncActionState = .idle
    @State private var previewValidation: ResultPreviewValidation?
    @State private var previewValidationMessage: String?
    @State private var previewValidationTask: Task<Void, Never>?

    init(session: AppSessionViewModel, router: AppRouter) {
        self.session = session
        self.router = router
        _draft = State(initialValue: session.container.localStore.resultPreviewDraft)
    }

    private var isBusy: Bool {
        if case .inProgress = actionState {
            return true
        }
        return false
    }

    var body: some View {
        screenScaffold(title: "결과 프리뷰", onBack: router.pop) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    previewIntroCard(
                        badge: "LOCAL PREVIEW",
                        title: "게스트 결과 입력 프리뷰",
                        message: "지금 입력하는 결과는 실제 전적에 반영되지 않습니다. 게스트 상태에서는 이 기기에만 임시 저장되고, 로그인 후 명시적으로 계정 저장을 선택할 때만 실제 저장 흐름으로 이어집니다."
                    )

                    if let previewValidationMessage {
                        previewValidationCard(
                            message: previewValidationMessage,
                            isValid: previewValidation?.isValid ?? false
                        )
                    }

                    sectionCard(title: "승리 팀", spacing: 8) {
                        HStack(spacing: 8) {
                            resultTeamButton(.blue, title: "블루 승리", tint: AppPalette.teamBlue)
                            resultTeamButton(.red, title: "레드 승리", tint: AppPalette.teamRed)
                        }
                    }

                    sectionCard(title: "MVP", spacing: 8) {
                        ForEach(draft.mvpCandidates) { player in
                            Button {
                                draft.selectedMVPPlayerID = player.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.name)
                                            .font(AppTypography.body(13, weight: .semibold))
                                        Text("\(player.teamSide == .blue ? "블루" : "레드") · \(player.role.shortLabel)")
                                            .font(AppTypography.body(11))
                                            .foregroundStyle(AppPalette.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: draft.selectedMVPPlayerID == player.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.selectedMVPPlayerID == player.id ? AppPalette.accentGold : AppPalette.textMuted)
                                }
                                .padding(12)
                                .appPanel(background: AppPalette.bgCard, radius: 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionCard(title: "체감 밸런스", spacing: 8) {
                        HStack(spacing: 8) {
                            resultBalanceButton(title: "한쪽 우세", value: 1)
                            resultBalanceButton(title: "살짝 우세", value: 3)
                            resultBalanceButton(title: "접전", value: 5)
                        }
                    }

                    HStack(spacing: 10) {
                        resultPlayersColumn(title: "블루", tint: AppPalette.teamBlue, players: draft.players.filter { $0.teamSide == .blue })
                        resultPlayersColumn(title: "레드", tint: AppPalette.teamRed, players: draft.players.filter { $0.teamSide == .red })
                    }

                    sectionCard(title: "다음 액션", spacing: 10) {
                        Button("이 기기에 임시 저장") {
                            Task { await saveLocally() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isBusy)

                        HStack(spacing: 8) {
                            Button("밸런스 프리뷰 다시 보기") {
                                router.push(.teamBalancePreview)
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("로그인 후 계정에 저장") {
                                session.requireAuthentication(for: .resultSave)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        Text("게스트 프리뷰 기록은 프로필과 기록 탭의 로컬 영역에서만 보입니다. 로그인 직후 자동 업로드되지는 않습니다.")
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
        }
        .overlay(alignment: .bottom) { actionBanner(actionState) }
        .onAppear {
            schedulePreviewValidation(immediate: true)
        }
        .onDisappear {
            previewValidationTask?.cancel()
        }
        .onChange(of: draft) { _, newValue in
            if !newValue.mvpCandidates.contains(where: { newValue.selectedMVPPlayerID == $0.id }) {
                draft.selectedMVPPlayerID = newValue.mvpCandidates.first?.id
            }
            session.container.localStore.setResultPreviewDraft(draft)
            schedulePreviewValidation()
        }
    }

    private func saveLocally() async {
        guard let selectedPlayer = draft.mvpCandidates.first(where: { draft.selectedMVPPlayerID == $0.id }) ?? draft.mvpCandidates.first else {
            actionState = .failure("MVP를 선택해 주세요.")
            return
        }

        actionState = .inProgress("서버 프리뷰를 확인하는 중입니다")
        do {
            let validation = try await session.container.matchRepository.previewResult(draft: draft)
            previewValidation = validation
            previewValidationMessage = validation.message
            guard validation.isValid else {
                actionState = .failure(validation.message)
                return
            }
        } catch let error as UserFacingError {
            let message = error.isRateLimited
                ? "프리뷰 요청이 많아요. 잠시 후 다시 저장해 주세요."
                : "서버 프리뷰를 확인한 뒤 저장할 수 있어요. 잠시 후 다시 시도해 주세요."
            previewValidation = nil
            previewValidationMessage = message
            actionState = .failure(message)
            return
        } catch {
            previewValidation = nil
            previewValidationMessage = "서버 프리뷰를 확인한 뒤 저장할 수 있어요. 잠시 후 다시 시도해 주세요."
            actionState = .failure("서버 프리뷰를 확인한 뒤 저장할 수 있어요. 잠시 후 다시 시도해 주세요.")
            return
        }

        let matchID = "guest-preview-\(UUID().uuidString)"
        session.container.localStore.trackMatch(
            RecentMatchContext(
                matchID: matchID,
                groupID: "guest-preview",
                groupName: "게스트 프리뷰",
                createdAt: Date()
            )
        )
        session.container.localStore.cacheResult(
            matchID: matchID,
            metadata: CachedResultMetadata(
                winningTeam: draft.winningTeam,
                mvpUserID: selectedPlayer.name,
                balanceRating: draft.balanceRating,
                updatedAt: Date()
            )
        )
        session.container.localStore.appendNotification(
            title: "게스트 결과 저장",
            body: "프리뷰 결과가 이 기기에만 임시 저장되었습니다.",
            symbol: "externaldrive.fill.badge.checkmark"
        )
        actionState = .success("프리뷰 결과를 이 기기에 임시 저장했습니다.")
    }

    private func previewIntroCard(badge: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(badge)
                .font(AppTypography.body(10, weight: .semibold))
                .foregroundStyle(AppPalette.accentGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppPalette.bgTertiary)
                .clipShape(Capsule())
            Text(title)
                .font(AppTypography.heading(18, weight: .bold))
            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }

    private func previewValidationCard(message: String, isValid: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isValid ? AppPalette.accentGreen : AppPalette.accentOrange)
            Text(message)
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .appPanel(background: AppPalette.bgSecondary, radius: 10)
    }

    private func sectionCard<Content: View>(title: String, spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(AppTypography.heading(16, weight: .bold))
            content()
        }
        .padding(14)
        .appPanel(background: AppPalette.bgSecondary, radius: 12)
    }

    private func resultTeamButton(_ side: TeamSide, title: String, tint: Color) -> some View {
        Button {
            draft.winningTeam = side
            draft.selectedMVPPlayerID = draft.mvpCandidates.first?.id
        } label: {
            Text(title)
                .font(AppTypography.body(12, weight: draft.winningTeam == side ? .semibold : .regular))
                .foregroundStyle(draft.winningTeam == side ? Color.white : AppPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(draft.winningTeam == side ? tint : AppPalette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func resultBalanceButton(title: String, value: Int) -> some View {
        Button {
            draft.balanceRating = value
        } label: {
            Text(title)
                .font(AppTypography.body(12, weight: draft.balanceRating == value ? .semibold : .regular))
                .foregroundStyle(draft.balanceRating == value ? Color.white : AppPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(draft.balanceRating == value ? AppPalette.accentGreen : AppPalette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func resultPlayersColumn(title: String, tint: Color, players: [ResultPreviewPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body(13, weight: .semibold))
                .foregroundStyle(tint)
            ForEach(players) { player in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(AppTypography.body(12, weight: .semibold))
                        Text(player.role.shortLabel)
                            .font(AppTypography.body(10))
                            .foregroundStyle(AppPalette.textMuted)
                    }
                    Spacer()
                    if draft.selectedMVPPlayerID == player.id {
                        Image(systemName: "star.fill")
                            .foregroundStyle(AppPalette.accentGold)
                    }
                }
                .padding(10)
                .appPanel(background: AppPalette.bgCard, radius: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func schedulePreviewValidation(immediate: Bool = false) {
        previewValidationTask?.cancel()
        let draftSnapshot = draft
        previewValidationTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            await refreshPreviewValidation(for: draftSnapshot)
        }
    }

    @MainActor
    private func refreshPreviewValidation(for draftSnapshot: ResultPreviewDraft) async {
        do {
            let validation = try await session.container.matchRepository.previewResult(draft: draftSnapshot)
            guard !Task.isCancelled else { return }
            previewValidation = validation
            previewValidationMessage = validation.message
        } catch let error as UserFacingError {
            guard !Task.isCancelled else { return }
            previewValidation = nil
            previewValidationMessage = error.isRateLimited
                ? "프리뷰 요청이 많아요. 잠시 후 다시 확인해 주세요."
                : "서버 프리뷰 확인이 지연되고 있어요. 입력값은 이 기기에만 임시 보관됩니다."
        } catch {
            guard !Task.isCancelled else { return }
            previewValidation = nil
            previewValidationMessage = "서버 프리뷰 확인이 지연되고 있어요. 입력값은 이 기기에만 임시 보관됩니다."
        }
    }
}

struct ProfileScreen: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
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
        .navigationTitle("프로필")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .appNavigationBarStyle(.large)
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
                Text(snapshot.riotAccounts.first.map { "\($0.riotGameName)#\($0.tagLine)" } ?? snapshot.profile.email)
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
                Text("연결된 Riot 계정")
                    .font(AppTypography.body(14, weight: .semibold))
                Spacer()
                Button("관리") {
                    router.push(.riotAccounts)
                }
                .font(AppTypography.body(12, weight: .semibold))
                .foregroundStyle(AppPalette.accentBlue)
            }
            ForEach(snapshot.riotAccounts.prefix(2)) { account in
                HStack {
                    tagLabel(account.isPrimary ? "대표" : "참고", tint: account.isPrimary ? AppPalette.accentGold : AppPalette.textMuted)
                    Text("\(account.riotGameName)#\(account.tagLine)")
                        .font(AppTypography.body(12, weight: .semibold))
                    Spacer()
                    Text(account.verificationStatus.title)
                        .font(AppTypography.body(12))
                        .foregroundStyle(account.isPrimary ? AppPalette.accentGold : AppPalette.textSecondary)
                }
            }
        }
        .padding(16)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))

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
                    HStack(spacing: 8) {
                        Text(role.shortLabel)
                            .font(AppTypography.body(12, weight: .semibold))
                            .foregroundStyle(role == .mid ? AppPalette.accentBlue : AppPalette.textSecondary)
                            .frame(width: 32, alignment: .leading)
                        ProgressView(value: power.lanePower[role] ?? 50, total: 100)
                            .tint(laneTint(role))
                        Text("\(Int((power.lanePower[role] ?? 50).rounded()))")
                            .font(AppTypography.body(12, weight: .semibold))
                    }
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
                Text("Riot 계정 연동과 프로필 저장은 로그인 후 사용할 수 있어요.")
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
    @State private var tagLine = "KR1"
    @State private var region = "kr"
    @State private var isPrimary = true

    var body: some View {
        screenScaffold(title: "Riot 계정 관리", onBack: onBack, rightSystemImage: nil) {
            if session.isGuest {
                guestContent
            } else {
                switch viewModel.state {
                case .initial, .loading:
                    LoadingStateView(title: "Riot 계정을 불러오는 중입니다")
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
    }

    private var guestContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Riot 계정 연동은 계정 귀속 기능입니다.")
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                AuthInlineAccessCard(
                    session: session,
                    title: "로그인 후 Riot 계정 연동",
                    message: "대표 계정 설정, 전적 동기화, 프로필 연결은 로그인 후 사용할 수 있어요."
                )
            }
            .padding(24)
        }
    }

    private func formContent(accounts: [RiotAccount]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppPalette.accentBlue)
                    Text("Riot API 데이터는 참고용이며, 내전 기록이 핵심 지표입니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .padding(14)
                .background(Color(hex: 0x1A2744))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 10) {
                    Text("새 계정 추가")
                        .font(AppTypography.heading(16, weight: .bold))
                    HStack(spacing: 8) {
                        TextField("Riot ID", text: $gameName)
                            .textFieldStyle(.roundedBorder)
                        TextField("태그", text: $tagLine)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    Toggle("대표 계정으로 설정", isOn: $isPrimary)
                        .tint(AppPalette.accentBlue)
                    Button("연결하기") {
                        Task { await viewModel.connect(gameName: gameName, tagLine: tagLine, region: region, isPrimary: isPrimary) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("연결된 계정")
                        .font(AppTypography.heading(16, weight: .bold))
                    ForEach(accounts) { account in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(account.isPrimary ? "대표" : "참고")
                                        .font(AppTypography.body(11, weight: .semibold))
                                        .foregroundStyle(account.isPrimary ? AppPalette.bgPrimary : AppPalette.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(account.isPrimary ? AppPalette.accentGold : AppPalette.bgTertiary)
                                        .clipShape(Capsule())
                                    Text(account.displayName)
                                        .font(AppTypography.body(14, weight: .semibold))
                                }
                                Text("\(account.region.uppercased()) · \(account.verificationStatus.title)")
                                    .font(AppTypography.body(12))
                                    .foregroundStyle(AppPalette.textSecondary)
                                Text(account.syncStatusSummary)
                                    .font(AppTypography.body(11))
                                    .foregroundStyle(account.syncUIState.isFailure ? AppPalette.accentRed : AppPalette.textMuted)
                                Text("마지막 동기화: \(account.syncStatusTimestamp?.shortDateText ?? "없음")")
                                    .font(AppTypography.body(11))
                                    .foregroundStyle(AppPalette.textMuted)
                            }
                            Spacer()
                            Button(viewModel.syncInProgressIDs.contains(account.id) ? "동기화 중" : "Sync") {
                                Task { await viewModel.sync(id: account.id) }
                            }
                            .buttonStyle(.bordered)
                            .tint(AppPalette.accentBlue)
                            .disabled(viewModel.syncInProgressIDs.contains(account.id))
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("여러 계정 합산 기준")
                        .font(AppTypography.body(13, weight: .semibold))
                    Text("대표 계정의 티어·전적이 주 기준이며, 참고 계정은 라인별 성과 데이터를 보완합니다. 실제 서버는 대표/참고 가중치를 노출하지 않으므로 현재 클라이언트는 설명성 UI만 제공합니다.")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .padding(16)
                .background(AppPalette.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }
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

struct SettingsScreen: View {
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    let onBack: () -> Void
    @State private var isProfilePublic = true
    @State private var isHistoryPublic = true
    @State private var notificationsEnabled = true
    @State private var showsProfileEdit = false

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
                            message: "설정 동기화, 프로필 편집, Riot 계정 연동은 로그인 후 사용할 수 있어요."
                        )

                        settingsSection(title: "계정", rows: [
                            settingsRow("로그인", subtitle: "동기화 시작", systemImage: "person.crop.circle") {
                                session.requireAuthentication(for: .settings)
                            },
                            settingsRow("Riot 계정 관리", subtitle: "로그인 후 사용", systemImage: "person.text.rectangle") {
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
                            settingsRow("Riot 계정 관리", subtitle: "연결 계정 확인", systemImage: "person.text.rectangle") { router.push(.riotAccounts) }
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
                        settingsRow("문의하기", subtitle: "준비 중", systemImage: "bubble.left") {},
                        settingsRow("이용약관", subtitle: "준비 중", systemImage: "doc.text") {},
                        settingsRow("개인정보처리방침", subtitle: "준비 중", systemImage: "doc.badge.shield") {}
                    ])

                    Text("내전 메이커 v1.0.0")
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
