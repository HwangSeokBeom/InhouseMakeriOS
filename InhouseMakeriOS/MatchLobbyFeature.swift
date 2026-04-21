import ComposableArchitecture
import SwiftUI

@Reducer
struct MatchLobbyFeature {
    @ObservableState
    struct State: Equatable {
        enum PendingProtectedAction: Equatable {
            case reload
            case addPlayers
            case autoBalance
        }

        enum ManagementAction: Equatable {
            case inviteMembers
            case edit
            case delete
        }

        let groupID: String
        let matchID: String
        var loadState: ScreenLoadState<MatchLobbySnapshot> = .initial
        var actionState: AsyncActionState = .idle
        var selectedMemberIDs: Set<String> = []
        var showsManagementActionSheet = false
        var showsMemberInviteSheet = false
        var shouldNavigateToTeamBalance = false
        var pendingProtectedAction: PendingProtectedAction?
        var autoBalanceFailureMessage: String?
        var activeLoadRequestID = UUID()
        var activeAddPlayersRequestID = UUID()
        var activeAutoBalanceRequestID = UUID()

        static let targetParticipantCount = 10

        struct BalanceReadiness: Equatable {
            let participantCount: Int
            let targetCount: Int
            let missingParticipantCount: Int
            let missingPositionCount: Int

            var canAutoBalance: Bool {
                missingParticipantCount == 0 && missingPositionCount == 0
            }

            var messages: [String] {
                var items: [String] = []
                if missingParticipantCount > 0 {
                    items.append("참가자 \(missingParticipantCount)명이 더 필요해요.")
                }
                if missingPositionCount > 0 {
                    items.append("포지션 정보가 없는 참가자 \(missingPositionCount)명이 있어요.")
                }
                if items.isEmpty {
                    items.append("자동 팀 생성을 실행할 수 있어요.")
                }
                return items
            }
        }

        enum LobbyPhase: Equatable {
            case underCapacity
            case ready
            case locked
            case balanced
        }

        var lobbyPhase: LobbyPhase {
            guard let match = loadState.value?.match else { return .underCapacity }
            if match.status == .balanced { return .balanced }
            if match.status == .locked { return .locked }
            return balanceReadiness.canAutoBalance ? .ready : .underCapacity
        }

        var balanceReadiness: BalanceReadiness {
            guard let match = loadState.value?.match else {
                return BalanceReadiness(
                    participantCount: 0,
                    targetCount: Self.targetParticipantCount,
                    missingParticipantCount: Self.targetParticipantCount,
                    missingPositionCount: 0
                )
            }

            let acceptedPlayers = match.players.filter {
                $0.participationStatus == .accepted || $0.participationStatus == .lockedIn
            }
            let participantCount = acceptedPlayers.count
            let missingParticipantCount = max(0, Self.targetParticipantCount - participantCount)
            let missingPositionCount = acceptedPlayers.prefix(Self.targetParticipantCount).filter { $0.assignedRole == nil }.count

            return BalanceReadiness(
                participantCount: participantCount,
                targetCount: Self.targetParticipantCount,
                missingParticipantCount: missingParticipantCount,
                missingPositionCount: missingPositionCount
            )
        }
    }

    enum Action: Equatable {
        case load(force: Bool = false)
        case loadResponse(UUID, Result<MatchLobbySnapshot, UserFacingError>)
        case overflowTapped
        case managementActionSheetDismissed
        case managementActionSelected(State.ManagementAction)
        case memberInviteSheetPresented
        case memberInviteSheetDismissed
        case selectAllEligibleMembersTapped
        case clearSelectedMembersTapped
        case toggleMemberSelection(String)
        case addSelectedPlayersTapped
        case addPlayersResponse(UUID, Result<MatchLobbySnapshot, UserFacingError>)
        case autoBalanceTapped
        case autoBalanceResponse(UUID, Result<MatchLobbySnapshot, UserFacingError>)
        case authRetryHandled
        case navigationHandled
        case viewDisappeared
    }

    @Dependency(\.appContainer) var appContainer

    private enum CancelID {
        case load
        case addPlayers
        case autoBalance
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                if !force {
                    switch state.loadState {
                    case .content, .loading, .refreshing:
                        return .none
                    case .initial, .empty, .error:
                        break
                    }
                }
                let requestID = UUID()
                state.activeLoadRequestID = requestID
                if let current = state.loadState.value, force {
                    state.loadState = .refreshing(current)
                } else {
                    state.loadState = .loading
                }
                let groupID = state.groupID
                let matchID = state.matchID
                let container = appContainer
                return .run { send in
#if DEBUG
                    print("[RouteFetch] fetch started screen=match_lobby groupID=\(groupID) matchID=\(matchID)")
#endif
                    do {
                        let resolvedContainer = await container()
                        let snapshot = try await Self.withTimeout(
                            nanoseconds: 15_000_000_000,
                            fallback: UserFacingError(
                                title: "로비 로딩 실패",
                                message: "응답이 지연되어 내전 로비를 불러오지 못했습니다. 다시 시도해 주세요."
                            )
                        ) {
                            try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
                        }
#if DEBUG
                        print("[RouteFetch] fetch success screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live players=\(snapshot.match.players.count)")
#endif
                        await send(.loadResponse(requestID, .success(snapshot)))
                    } catch let error as UserFacingError {
#if DEBUG
                        print("[RouteFetch] fetch failure screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)")
#endif
                        await send(.loadResponse(requestID, .failure(error)))
                    } catch is CancellationError {
                        return
                    } catch {
#if DEBUG
                        print("[RouteFetch] fetch failure screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live status=nil message=\(error.localizedDescription)")
#endif
                        await send(.loadResponse(requestID, .failure(.unexpected("로비 로딩 실패", message: "내전 로비를 불러오지 못했습니다."))))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loadResponse(requestID, .success(snapshot)):
                guard requestID == state.activeLoadRequestID else { return .none }
                state.loadState = .content(snapshot)
                state.autoBalanceFailureMessage = nil
                state.selectedMemberIDs.subtract(snapshot.match.players.map(\.userID))
#if DEBUG
                print("[MatchLobby] group members refreshed count=\(snapshot.members.count)")
                print("[MatchLobby] lobby participants count=\(snapshot.match.players.count)")
#endif
                return .none

            case let .loadResponse(requestID, .failure(error)):
                guard requestID == state.activeLoadRequestID else { return .none }
                if error.requiresAuthentication {
                    state.loadState = .empty("로그인 후 내전 로비를 다시 열 수 있어요.")
                    state.pendingProtectedAction = .reload
                } else {
                    state.loadState = .error(error)
                }
                return .none

            case .overflowTapped:
                state.showsManagementActionSheet = true
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                return .none

            case .managementActionSheetDismissed:
                state.showsManagementActionSheet = false
                return .none

            case let .managementActionSelected(action):
                state.showsManagementActionSheet = false
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                switch action {
                case .inviteMembers:
                    state.showsMemberInviteSheet = true
                case .edit, .delete:
                    break
                }
                return .none

            case .memberInviteSheetPresented:
                state.showsManagementActionSheet = false
                state.showsMemberInviteSheet = true
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                return .none

            case .memberInviteSheetDismissed:
                state.showsMemberInviteSheet = false
                state.selectedMemberIDs.removeAll()
                return .none

            case .selectAllEligibleMembersTapped:
                guard let snapshot = state.loadState.value else { return .none }
                let currentPlayerUserIDs = Set(snapshot.match.players.map(\.userID))
                state.selectedMemberIDs = Set(
                    snapshot.members
                        .map(\.userID)
                        .filter { !currentPlayerUserIDs.contains($0) }
                )
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                return .none

            case .clearSelectedMembersTapped:
                state.selectedMemberIDs.removeAll()
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                return .none

            case let .toggleMemberSelection(userID):
                if state.selectedMemberIDs.contains(userID) {
                    state.selectedMemberIDs.remove(userID)
                } else {
                    state.selectedMemberIDs.insert(userID)
                }
                if case .failure = state.actionState {
                    state.actionState = .idle
                }
                return .none

            case .addSelectedPlayersTapped:
                guard !state.selectedMemberIDs.isEmpty, let snapshot = state.loadState.value else { return .none }
                state.actionState = .inProgress("참가자를 추가하는 중입니다")
                let requestID = UUID()
                state.activeAddPlayersRequestID = requestID
                let groupID = state.groupID
                let matchID = state.matchID
                let userIDs = snapshot.members
                    .map(\.userID)
                    .filter { state.selectedMemberIDs.contains($0) }
                let container = appContainer
                return .merge(
                    .cancel(id: CancelID.load),
                    .run { send in
#if DEBUG
                        print("[MatchLobby] add participants request matchID=\(matchID) count=\(userIDs.count)")
#endif
                        do {
                            let resolvedContainer = await container()
                            let snapshot = try await Self.withTimeout(
                                nanoseconds: 15_000_000_000,
                                fallback: UserFacingError(
                                    title: "참가자 추가 실패",
                                    message: "응답이 지연되어 참가자 추가를 완료하지 못했습니다. 다시 시도해 주세요."
                                )
                            ) {
                                await MainActor.run {
                                    resolvedContainer.localStore.clearManualAdjustDraft(matchID: matchID)
                                }
                                _ = try await resolvedContainer.matchRepository.addPlayers(
                                    matchID: matchID,
                                    players: userIDs.map {
                                        MatchPlayerInputDTO(
                                            userId: $0,
                                            riotAccountId: nil,
                                            participationStatus: .accepted,
                                            sameTeamPreferenceUserIds: [],
                                            avoidTeamPreferenceUserIds: [],
                                            isCaptain: false
                                        )
                                    }
                                )
                                return try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
                            }
                            await send(.addPlayersResponse(requestID, .success(snapshot)))
                        } catch let error as UserFacingError {
                            await send(.addPlayersResponse(requestID, .failure(error)))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.addPlayersResponse(requestID, .failure(.unexpected("참가자 추가 실패", message: "참가자 추가에 실패했습니다."))))
                        }
                    }
                    .cancellable(id: CancelID.addPlayers, cancelInFlight: true)
                )

            case let .addPlayersResponse(requestID, .success(snapshot)):
                guard requestID == state.activeAddPlayersRequestID else { return .none }
                state.loadState = .content(snapshot)
                state.showsMemberInviteSheet = false
                state.selectedMemberIDs.removeAll()
                state.autoBalanceFailureMessage = nil
                state.actionState = .success("참가자가 추가되었습니다")
#if DEBUG
                print("[MatchLobby] lobby participants count=\(snapshot.match.players.count)")
#endif
                return .none

            case let .addPlayersResponse(requestID, .failure(error)):
                guard requestID == state.activeAddPlayersRequestID else { return .none }
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .addPlayers
                } else {
                    state.actionState = .failure(Self.addPlayersFailureMessage(for: error))
                }
                return .none

            case .autoBalanceTapped:
                guard let snapshot = state.loadState.value else { return .none }
                let readiness = state.balanceReadiness
                guard readiness.canAutoBalance || snapshot.match.status == .balanced else {
                    let message = Self.autoBalanceUnavailableMessage(readiness: readiness)
                    state.autoBalanceFailureMessage = message
                    state.actionState = .failure(message)
#if DEBUG
                    print("[MatchLobby] auto balance blocked reason=\(message) participants=\(readiness.participantCount)/\(readiness.targetCount) missingPositions=\(readiness.missingPositionCount)")
#endif
                    return .none
                }
                state.actionState = .inProgress("자동 팀 생성을 준비하는 중입니다")
                state.autoBalanceFailureMessage = nil
                let requestID = UUID()
                state.activeAutoBalanceRequestID = requestID
                let groupID = state.groupID
                let matchID = state.matchID
                let container = appContainer
                return .merge(
                    .cancel(id: CancelID.load),
                    .run { send in
                        do {
                            let resolvedContainer = await container()
                            let refreshed = try await Self.withTimeout(
                                nanoseconds: 20_000_000_000,
                                fallback: UserFacingError(
                                    title: "자동 팀 생성 실패",
                                    message: "응답이 지연되어 추천 조합 생성에 실패했습니다. 다시 시도해 주세요."
                                )
                            ) {
                                await MainActor.run {
                                    resolvedContainer.localStore.clearManualAdjustDraft(matchID: matchID)
                                }
#if DEBUG
                                print(
                                    "[MatchLobby] auto balance request input matchID=\(matchID) status=\(snapshot.match.status.rawValue) participants=\(snapshot.match.acceptedCount) missingPositions=\(snapshot.match.players.filter { $0.assignedRole == nil }.count)"
                                )
#endif
                                if snapshot.match.status != .locked && snapshot.match.status != .balanced {
                                    _ = try await resolvedContainer.matchRepository.lock(matchID: matchID)
                                }
                                let candidates = try await resolvedContainer.matchRepository.autoBalance(matchID: matchID)
#if DEBUG
                                let emptyReason = candidates.isEmpty ? "server_returned_empty_candidates" : "nil"
                                print("[MatchLobby] auto balance response count=\(candidates.count) emptyReason=\(emptyReason)")
#endif
                                let refreshed = try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
                                await MainActor.run {
                                    resolvedContainer.localStore.appendNotification(
                                        title: "자동 밸런스 생성",
                                        body: "추천 조합이 생성되었습니다.",
                                        symbol: "arrow.trianglehead.2.clockwise"
                                    )
                                }
                                return refreshed
                            }
                            await send(.autoBalanceResponse(requestID, .success(refreshed)))
                        } catch let error as UserFacingError {
                            await send(.autoBalanceResponse(requestID, .failure(error)))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.autoBalanceResponse(requestID, .failure(.unexpected("자동 팀 생성 실패", message: "추천 조합 생성에 실패했습니다."))))
                        }
                    }
                    .cancellable(id: CancelID.autoBalance, cancelInFlight: true)
                )

            case let .autoBalanceResponse(requestID, .success(snapshot)):
                guard requestID == state.activeAutoBalanceRequestID else { return .none }
                state.loadState = .content(snapshot)
                state.actionState = .success("추천 조합이 생성되었습니다")
                state.autoBalanceFailureMessage = nil
                state.shouldNavigateToTeamBalance = true
                return .none

            case let .autoBalanceResponse(requestID, .failure(error)):
                guard requestID == state.activeAutoBalanceRequestID else { return .none }
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .autoBalance
                } else {
                    let message = Self.autoBalanceFailureMessage(for: error)
                    state.autoBalanceFailureMessage = message
                    state.actionState = .failure(message)
                }
                return .none

            case .authRetryHandled:
                state.pendingProtectedAction = nil
                return .none

            case .navigationHandled:
                state.shouldNavigateToTeamBalance = false
                return .none

            case .viewDisappeared:
                state.activeLoadRequestID = UUID()
                state.activeAddPlayersRequestID = UUID()
                state.activeAutoBalanceRequestID = UUID()
                state.showsManagementActionSheet = false
                state.showsMemberInviteSheet = false
                state.selectedMemberIDs.removeAll()
                state.pendingProtectedAction = nil
                if case .inProgress = state.actionState {
                    state.actionState = .idle
                }
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.addPlayers),
                    .cancel(id: CancelID.autoBalance)
                )
            }
        }
    }

    private static func makeSnapshot(container: AppContainer, groupID: String, matchID: String) async throws -> MatchLobbySnapshot {
#if DEBUG
        print("[MatchLobby] snapshot start groupID=\(groupID) matchID=\(matchID)")
#endif
        let group = try await container.groupRepository.detail(groupID: groupID)
#if DEBUG
        print("[MatchLobby] snapshot group loaded groupID=\(groupID) name=\(group.name)")
#endif
        let members = try await container.groupRepository.members(groupID: groupID)
#if DEBUG
        print("[MatchLobby] snapshot members loaded groupID=\(groupID) count=\(members.count)")
#endif
        let match = try await container.matchRepository.detail(matchID: matchID)
#if DEBUG
        print("[MatchLobby] snapshot match loaded matchID=\(matchID) players=\(match.players.count) status=\(match.status.rawValue)")
#endif
        let powerProfiles = await loadPowerProfiles(container: container, userIDs: match.players.map(\.userID))
#if DEBUG
        print("[MatchLobby] snapshot power profiles loaded matchID=\(matchID) count=\(powerProfiles.count)")
#endif
        let effectiveMatch = effectiveMatch(match: match, powerProfiles: powerProfiles, logContext: "MatchLobby")
#if DEBUG
        print("[MatchLobby] snapshot effective match ready matchID=\(matchID) participants=\(effectiveMatch.players.count)")
#endif
        await MainActor.run {
#if DEBUG
            print("[MatchLobby] snapshot tracking recent context matchID=\(matchID)")
#endif
            container.localStore.trackGroup(id: groupID)
            container.localStore.trackMatch(
                RecentMatchContext(matchID: match.id, groupID: groupID, groupName: group.name, createdAt: Date())
            )
        }
#if DEBUG
        print("[MatchLobby] snapshot complete matchID=\(matchID)")
#endif
        return MatchLobbySnapshot(match: effectiveMatch, group: group, members: members, powerProfiles: powerProfiles)
    }

    private static func autoBalanceUnavailableMessage(readiness: State.BalanceReadiness) -> String {
        if readiness.missingParticipantCount > 0 {
            return "자동 팀 생성에는 참가자 \(readiness.targetCount)명이 필요해요. \(readiness.missingParticipantCount)명을 더 추가해 주세요."
        }
        if readiness.missingPositionCount > 0 {
            return "포지션 정보가 없는 참가자가 있어 자동 팀 생성을 실행할 수 없어요."
        }
        return "자동 팀 생성 조건을 다시 확인해 주세요."
    }

    private static func autoBalanceFailureMessage(for error: UserFacingError) -> String {
        if error.statusCode == 400 {
            return "참가자 수와 포지션 정보를 확인한 뒤 자동 팀 생성을 다시 시도해 주세요."
        }
        if error.statusCode == 409 {
            return "현재 로비 상태에서는 자동 팀 생성을 실행할 수 없어요. 참가자 목록을 새로고침해 주세요."
        }
        return error.message
    }

    private static func addPlayersFailureMessage(for error: UserFacingError) -> String {
        if error.statusCode == 409 {
            return "이미 참가 중인 팀원이 포함되어 있어요. 참가자 목록을 확인한 뒤 다시 시도해 주세요."
        }
        if error.statusCode == 400 {
            return "추가할 팀원 정보를 다시 확인해 주세요."
        }
        return error.message
    }

    private static func withTimeout<Value>(
        nanoseconds: UInt64,
        fallback: UserFacingError,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw fallback
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private static func loadPowerProfiles(container: AppContainer, userIDs: [String]) async -> [String: PowerProfile] {
        var profiles: [String: PowerProfile] = [:]
        for userID in Set(userIDs) {
            do {
                let profile = try await container.profileRepository.powerProfile(userID: userID)
                profiles[userID] = profile
            } catch {
#if DEBUG
                print("[MatchLobby] power profile unavailable userID=\(userID) error=\(error)")
#endif
            }
        }
        return profiles
    }

    static func effectiveMatch(match: Match, powerProfiles: [String: PowerProfile], logContext: String? = nil) -> Match {
        let players = match.players.map { player -> MatchPlayer in
            guard player.assignedRole == nil,
                  let powerProfile = powerProfiles[player.userID],
                  let fallbackRole = powerProfile.resolvedPrimaryPosition else {
                return player
            }
#if DEBUG
            if let logContext {
                print(
                    "[\(logContext)] participant fallback mapping applied userID=\(player.userID) role=\(fallbackRole.rawValue) secondary=\(powerProfile.resolvedSecondaryPosition?.rawValue ?? "nil") power=\(Int(powerProfile.overallPower.rounded()))"
                )
            }
#endif
            return MatchPlayer(
                id: player.id,
                userID: player.userID,
                nickname: player.nickname,
                teamSide: player.teamSide,
                assignedRole: fallbackRole,
                participationStatus: player.participationStatus,
                isCaptain: player.isCaptain
            )
        }

        return Match(
            id: match.id,
            groupID: match.groupID,
            status: match.status,
            scheduledAt: match.scheduledAt,
            balanceMode: match.balanceMode,
            selectedCandidateNo: match.selectedCandidateNo,
            players: players,
            candidates: match.candidates
        )
    }
}

struct MatchLobbyFeatureView: View {
    private enum ManagementFollowUp: Identifiable {
        case editNotice
        case deleteConfirmation

        var id: String {
            switch self {
            case .editNotice:
                return "editNotice"
            case .deleteConfirmation:
                return "deleteConfirmation"
            }
        }

        var title: String {
            switch self {
            case .editNotice:
                return "내전 수정은 준비 중입니다"
            case .deleteConfirmation:
                return "이 내전을 삭제할까요?"
            }
        }

        var message: String {
            switch self {
            case .editNotice:
                return "현재 빌드에서는 로비 수정 UI만 정리되어 있고 실제 수정 기능은 아직 연결되지 않았습니다."
            case .deleteConfirmation:
                return "현재 빌드에서는 로비 삭제 확인 UI만 정리되어 있고 실제 삭제 기능은 아직 연결되지 않았습니다."
            }
        }
    }

    @Bindable var store: StoreOf<MatchLobbyFeature>
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @State private var inviteSearchText = ""
    @State private var recentInviteSearchKeywords: [RecentSearchKeyword] = []
    @FocusState private var isInviteSearchFieldFocused: Bool
    @State private var managementFollowUp: ManagementFollowUp?

    var body: some View {
        screenScaffold(
            title: "내전 로비",
            onBack: router.pop,
            rightSystemImage: "ellipsis",
            rightAccessibilityLabel: "참가자 관리 메뉴",
            rightAccessibilityIdentifier: "matchLobby.manageToolbar",
            onRightTap: { store.send(.overflowTapped) }
        ) {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("matchLobby.root")
                switch store.loadState {
                case .initial, .loading:
                    LoadingStateView(title: "내전 로비를 불러오는 중입니다")
                        .accessibilityIdentifier("matchLobby.loading")
                        .task { store.send(.load()) }
                case let .error(error):
                    ErrorStateView(error: error) { store.send(.load(force: true)) }
                case .empty:
                    EmptyStateView(title: "내전 로비", message: "내전 로비가 없습니다.")
                case let .content(snapshot), let .refreshing(snapshot):
                    let readiness = store.state.balanceReadiness
                    VStack(spacing: 0) {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                VStack(alignment: .center, spacing: 10) {
                                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                                        Text("\(readiness.participantCount)")
                                            .font(AppTypography.heading(42, weight: .heavy))
                                            .foregroundStyle(AppPalette.accentBlue)
                                        Text("/ \(readiness.targetCount)")
                                            .font(AppTypography.heading(22, weight: .semibold))
                                            .foregroundStyle(AppPalette.textMuted)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(readiness.participantCount)/\(readiness.targetCount)")
                                    .accessibilityIdentifier("matchLobby.participantCount")
                                    Text(statusLabel(for: snapshot.match, readiness: readiness))
                                        .font(AppTypography.body(12))
                                        .foregroundStyle(AppPalette.textSecondary)
                                    ProgressView(value: Double(readiness.participantCount), total: Double(readiness.targetCount))
                                        .tint(AppPalette.accentBlue)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                                .appPanel(background: AppPalette.bgCard, radius: 16)

                                readinessCard(readiness: readiness)

                                if let failureMessage = store.autoBalanceFailureMessage {
                                    autoBalanceFailureCard(message: failureMessage)
                                }

                                HStack(spacing: 8) {
                                    FilterChipView(title: "빡겜", tint: AppPalette.accentBlue, isSelected: true)
                                    FilterChipView(title: snapshot.group.tags.first ?? "D4+", tint: AppPalette.textSecondary)
                                    FilterChipView(title: "포지션 균형", tint: AppPalette.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .leading, spacing: 16) {
                                    Text("참가자 목록")
                                        .font(AppTypography.heading(15, weight: .bold))
                                    ForEach(snapshot.match.players) { player in
                                        Button {
                                            router.push(.memberProfile(userID: player.userID, nickname: player.nickname))
                                        } label: {
                                            lobbyPlayerCard(
                                                name: player.nickname,
                                                subtitle: playerSubtitle(player, snapshot: snapshot),
                                                powerScore: Int(snapshot.powerProfiles[player.userID]?.overallPower.rounded() ?? 0)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("matchLobby.participantRow.\(player.userID)")
                                    }

                                    if snapshot.match.players.count < MatchLobbyFeature.State.targetParticipantCount {
                                        Button {
                                            store.send(.memberInviteSheetPresented)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "person.badge.plus")
                                                    .foregroundStyle(AppPalette.textMuted)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(MatchLobbyFeature.State.targetParticipantCount - snapshot.match.players.count)명 더 필요")
                                                        .font(AppTypography.body(13, weight: .semibold))
                                                    Text("팀원을 추가해 로비를 바로 채워주세요")
                                                        .font(AppTypography.body(11))
                                                        .foregroundStyle(AppPalette.textMuted)
                                                }
                                                Spacer()
                                            }
                                            .foregroundStyle(AppPalette.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 58)
                                            .background(AppPalette.bgTertiary)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.border, style: StrokeStyle(lineWidth: 1, dash: [6])))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("참가자 관리")
                                        .accessibilityIdentifier("matchLobby.manageMembers")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .accessibilityIdentifier("matchLobby.participantList")
                            }
                            .padding(.top, 12)
                        }

                        VStack(spacing: 8) {
                            let canAutoBalance = readiness.canAutoBalance || snapshot.match.status == .balanced
                            HStack(spacing: 8) {
                                if canAutoBalance {
                                    Button(snapshot.match.status == .balanced ? "팀 밸런스 보기" : "자동 팀 생성") {
                                        if snapshot.match.status == .balanced {
                                            router.push(.teamBalance(groupID: store.groupID, matchID: store.matchID))
                                        } else {
                                            store.send(.autoBalanceTapped)
                                        }
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .accessibilityIdentifier("matchLobby.autoBalanceButton")
                                } else {
                                    Button(snapshot.match.status == .balanced ? "팀 밸런스 보기" : "자동 팀 생성") {}
                                        .buttonStyle(SecondaryButtonStyle())
                                        .accessibilityIdentifier("matchLobby.autoBalanceButton")
                                        .disabled(true)
                                }

                                Button("수동 배치") {
                                    router.push(.teamBalance(groupID: store.groupID, matchID: store.matchID))
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .accessibilityIdentifier("matchLobby.manualAssignButton")
                                .disabled(readiness.participantCount < readiness.targetCount)
                            }

                            Text(bottomNote(for: snapshot.match, readiness: readiness))
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textMuted)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(AppPalette.bgSecondary)
                    }
                    .sheet(
                        isPresented: Binding(
                            get: { store.showsMemberInviteSheet },
                            set: { isPresented in
                                store.send(isPresented ? .memberInviteSheetPresented : .memberInviteSheetDismissed)
                            }
                        )
                    ) {
                        MatchLobbyInviteSheet(
                            members: filteredInviteMembers(from: snapshot),
                            selectedMembers: snapshot.members.filter { store.selectedMemberIDs.contains($0.userID) },
                            participantUserIDs: Set(snapshot.match.players.map(\.userID)),
                            selectedUserIDs: store.selectedMemberIDs,
                            recentSearchKeywords: recentInviteSearchKeywords,
                            searchText: $inviteSearchText,
                            isSubmitting: isInviteSubmitting,
                            submissionErrorMessage: inviteSubmissionErrorMessage,
                            onClose: { store.send(.memberInviteSheetDismissed) },
                            onSelectAll: { store.send(.selectAllEligibleMembersTapped) },
                            onClearSelection: { store.send(.clearSelectedMembersTapped) },
                            onToggleMember: { userID in store.send(.toggleMemberSelection(userID)) },
                            onTapRecentSearch: applyRecentInviteSearch,
                            onDeleteRecentSearch: deleteRecentInviteSearch,
                            onClearRecentSearches: clearRecentInviteSearches,
                            onSubmitSearch: commitInviteSearch,
                            onSubmitSelection: {
                                commitInviteSearch()
                                store.send(.addSelectedPlayersTapped)
                            }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }

                if case .refreshing = store.loadState {
                    lobbyRefreshOverlay
                }

                if store.showsManagementActionSheet {
                    BottomActionSheet(
                        accessibilityIdentifier: "matchLobby.managementActionSheet",
                        actions: [
                            BottomActionSheetAction(
                                id: "inviteMembers",
                                title: "팀원 추가",
                                accessibilityIdentifier: "matchLobby.managementActionSheet.inviteMembers"
                            ) {
                                store.send(.managementActionSelected(.inviteMembers))
                            },
                            BottomActionSheetAction(
                                id: "edit",
                                title: "수정",
                                accessibilityIdentifier: "matchLobby.managementActionSheet.edit"
                            ) {
                                store.send(.managementActionSelected(.edit))
                                managementFollowUp = .editNotice
                            },
                            BottomActionSheetAction(
                                id: "delete",
                                title: "삭제",
                                role: .destructive,
                                accessibilityIdentifier: "matchLobby.managementActionSheet.delete"
                            ) {
                                store.send(.managementActionSelected(.delete))
                                managementFollowUp = .deleteConfirmation
                            },
                            BottomActionSheetAction(
                                id: "cancel",
                                title: "취소",
                                role: .cancel,
                                accessibilityIdentifier: "matchLobby.managementActionSheet.cancel",
                                action: {}
                            ),
                        ],
                        onDismiss: { store.send(.managementActionSheetDismissed) }
                    )
                }
            }
        }
        .overlay(alignment: Alignment.bottom) {
            actionBanner(store.actionState)
                .accessibilityIdentifier("matchLobby.toast")
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: store.showsManagementActionSheet)
        .task { store.send(.load()) }
        .onAppear(perform: refreshInviteSearchKeywords)
        .onChange(of: store.showsMemberInviteSheet) { _, isPresented in
            if isPresented {
                inviteSearchText = ""
                refreshInviteSearchKeywords()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isInviteSearchFieldFocused = true
                }
            } else {
                inviteSearchText = ""
                isInviteSearchFieldFocused = false
            }
        }
        .onChange(of: store.pendingProtectedAction) { _, pendingAction in
            guard let pendingAction else { return }
            switch pendingAction {
            case .reload:
                session.requireReauthentication(for: .matchSave) {
                    store.send(.load(force: true))
                }
            case .addPlayers:
                session.requireReauthentication(for: .matchSave) {
                    store.send(.addSelectedPlayersTapped)
                }
            case .autoBalance:
                session.requireReauthentication(for: .matchSave) {
                    store.send(.autoBalanceTapped)
                }
            }
            store.send(.authRetryHandled)
        }
        .onChange(of: store.shouldNavigateToTeamBalance) { _, isActive in
            if isActive {
                router.push(.teamBalance(groupID: store.groupID, matchID: store.matchID))
                store.send(.navigationHandled)
            }
        }
        .onDisappear {
            store.send(.viewDisappeared)
        }
        .alert(
            managementFollowUp?.title ?? "",
            isPresented: Binding(
                get: { managementFollowUp != nil },
                set: { isPresented in
                    if !isPresented {
                        managementFollowUp = nil
                    }
                }
            ),
            presenting: managementFollowUp
        ) { followUp in
            switch followUp {
            case .editNotice:
                Button("확인", role: .cancel) {
                    managementFollowUp = nil
                }
            case .deleteConfirmation:
                Button("취소", role: .cancel) {
                    managementFollowUp = nil
                }
                Button("삭제", role: .destructive) {
                    managementFollowUp = nil
                }
            }
        } message: { followUp in
            Text(followUp.message)
        }
    }

    private func statusLabel(for match: Match) -> String {
        statusLabel(for: match, readiness: store.state.balanceReadiness)
    }

    private func statusLabel(for match: Match, readiness: MatchLobbyFeature.State.BalanceReadiness) -> String {
        switch match.status {
        case .balanced:
            return "추천 조합이 준비되었습니다"
        case .locked:
            return "참가가 잠겨 있어 밸런스 계산을 준비 중입니다"
        default:
            return readiness.canAutoBalance ? "10명이 모였습니다. 자동 팀 생성을 실행할 수 있습니다" : "참가자 모집 중 · \(requiredRolesText(for: match))"
        }
    }

    private func bottomNote(for match: Match, readiness: MatchLobbyFeature.State.BalanceReadiness) -> String {
        switch match.status {
        case .balanced:
            return "이미 생성된 추천 조합을 확인할 수 있습니다."
        case .locked:
            return "참가가 잠겨 있습니다. 곧 팀 밸런스 결과로 이동할 수 있습니다."
        default:
            if readiness.canAutoBalance {
                return "자동 팀 생성을 실행하면 추천 조합을 받아옵니다."
            }
            return readiness.messages.joined(separator: " ")
        }
    }

    private func readinessCard(readiness: MatchLobbyFeature.State.BalanceReadiness) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: readiness.canAutoBalance ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(readiness.canAutoBalance ? AppPalette.accentGreen : AppPalette.accentGold)
                Text(readiness.canAutoBalance ? "자동 팀 생성 가능" : "자동 팀 생성 조건 확인")
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
                Text("\(readiness.participantCount)/\(readiness.targetCount)")
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(readiness.canAutoBalance ? AppPalette.accentGreen : AppPalette.accentGold)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(readiness.messages, id: \.self) { message in
                    Text(message)
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .appPanel(
            background: AppPalette.bgCard,
            radius: 12,
            stroke: readiness.canAutoBalance ? AppPalette.accentGreen.opacity(0.55) : AppPalette.border
        )
        .accessibilityIdentifier("matchLobby.readinessCard")
    }

    private func autoBalanceFailureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(AppPalette.accentRed)
                Text("자동 팀 생성 실패")
                    .font(AppTypography.body(13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
            }

            Text(message)
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("다시 시도") {
                    store.send(.autoBalanceTapped)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("참가자 추가") {
                    store.send(.memberInviteSheetPresented)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(isActionInFlight)
        }
        .padding(14)
        .appPanel(background: AppPalette.accentRed.opacity(0.12), radius: 12, stroke: AppPalette.accentRed.opacity(0.7))
        .accessibilityIdentifier("matchLobby.autoBalanceFailureCard")
    }

    private func requiredRolesText(for match: Match) -> String {
        let trackedRoles: [Position] = [.top, .jungle, .mid, .adc, .support]
        let occupied = Set(match.players.compactMap(\.assignedRole))
        let missing = trackedRoles.filter { !occupied.contains($0) }
        guard !missing.isEmpty else { return "추가 포지션 확인 필요" }
        return missing.prefix(3).map(\.shortLabel).joined(separator: ", ") + " 필요"
    }

    private func playerSubtitle(_ player: MatchPlayer, snapshot: MatchLobbySnapshot) -> String {
        let role = participantPositionText(player: player, powerProfile: snapshot.powerProfiles[player.userID])
        return "\(role) · \(player.participationStatus == .accepted ? "최근 폼 공개" : "참가 확인 대기")"
    }

    private func participantPositionText(player: MatchPlayer, powerProfile: PowerProfile?) -> String {
        var labels: [String] = []

        func appendIfNeeded(_ position: Position?) {
            guard let position else { return }
            let label = position.shortLabel
            guard !labels.contains(label) else { return }
            labels.append(label)
        }

        appendIfNeeded(player.assignedRole)
        appendIfNeeded(powerProfile?.resolvedSecondaryPosition)

        if labels.isEmpty {
            appendIfNeeded(powerProfile?.resolvedPrimaryPosition)
            appendIfNeeded(powerProfile?.resolvedSecondaryPosition)
        }

        return labels.isEmpty ? "포지션 미정" : labels.joined(separator: " / ")
    }

    private var isActionInFlight: Bool {
        if case .inProgress = store.actionState {
            return true
        }
        return false
    }

    private var isInviteSubmitting: Bool {
        store.showsMemberInviteSheet && isActionInFlight
    }

    private var inviteSubmissionErrorMessage: String? {
        guard store.showsMemberInviteSheet, case let .failure(message) = store.actionState else { return nil }
        return message
    }

    private var lobbyRefreshOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(AppPalette.accentBlue)
            Text("로비를 새로고침하는 중입니다")
                .font(AppTypography.body(12))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppPalette.bgPrimary.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 12)
        .allowsHitTesting(false)
        .accessibilityIdentifier("matchLobby.loadingOverlay")
    }

    private func filteredInviteMembers(from snapshot: MatchLobbySnapshot) -> [GroupMember] {
        let trimmedQuery = inviteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = snapshot.members
        guard !trimmedQuery.isEmpty else { return members }
        return members.filter { $0.nickname.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private func refreshInviteSearchKeywords() {
        recentInviteSearchKeywords = session.container.localStore.recentSearchKeywords
    }

    private func commitInviteSearch() {
        let trimmedQuery = inviteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        session.container.localStore.recordRecentSearchKeyword(trimmedQuery)
        refreshInviteSearchKeywords()
    }

    private func applyRecentInviteSearch(_ keyword: String) {
        inviteSearchText = keyword
        isInviteSearchFieldFocused = true
    }

    private func deleteRecentInviteSearch(_ id: String) {
        session.container.localStore.deleteRecentSearchKeyword(id: id)
        refreshInviteSearchKeywords()
    }

    private func clearRecentInviteSearches() {
        session.container.localStore.clearRecentSearchKeywords()
        refreshInviteSearchKeywords()
    }

    private func lobbyPlayerCard(name: String, subtitle: String, powerScore: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AppPalette.bgElevated)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppTypography.body(14, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(subtitle)
                    .font(AppTypography.body(10))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(powerScore)")
                    .font(AppTypography.heading(18, weight: .bold))
                    .foregroundStyle(AppPalette.accentBlue)
                Text("파워")
                    .font(AppTypography.body(9))
                    .foregroundStyle(AppPalette.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .appPanel(background: AppPalette.bgCard, radius: 10)
    }
}

private struct MatchLobbyInviteSheet: View {
    let members: [GroupMember]
    let selectedMembers: [GroupMember]
    let participantUserIDs: Set<String>
    let selectedUserIDs: Set<String>
    let recentSearchKeywords: [RecentSearchKeyword]
    @Binding var searchText: String
    let isSubmitting: Bool
    let submissionErrorMessage: String?
    let onClose: () -> Void
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onToggleMember: (String) -> Void
    let onTapRecentSearch: (String) -> Void
    let onDeleteRecentSearch: (String) -> Void
    let onClearRecentSearches: () -> Void
    let onSubmitSearch: () -> Void
    let onSubmitSelection: () -> Void
    @FocusState private var isSearchFieldFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eligibleMemberCount: Int {
        members.filter { !participantUserIDs.contains($0.userID) }.count
    }

    private var selectedSummary: String {
        guard let first = selectedMembers.first else { return "선택된 팀원이 없어요." }
        if selectedMembers.count == 1 {
            return first.nickname
        }
        return "\(first.nickname) 외 \(selectedMembers.count - 1)명"
    }

    var body: some View {
        ZStack {
            AppPalette.bgPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                searchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if trimmedSearchText.isEmpty {
                            quickAddSection
                            recentSearchSection
                        } else {
                            searchResultSection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memberInviteSheet.root")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFieldFocused = true
            }
        }
    }

    private var headerSection: some View {
        BottomSheetHeader(
            title: "팀원 추가",
            titleAccessibilityIdentifier: "memberInviteSheet.title",
            showsCloseButton: false,
            onClose: onClose
        )
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppPalette.textSecondary)

            TextField("닉네임으로 팀원 검색", text: $searchText)
                .font(AppTypography.body(15))
                .foregroundStyle(AppPalette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    onSubmitSearch()
                }
                .accessibilityIdentifier("memberInviteSheet.searchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppPalette.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
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

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("바로 추가하기")
                .font(AppTypography.heading(16, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)

            HStack(spacing: 8) {
                Text("선택 가능 \(eligibleMemberCount)명")
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(AppPalette.textSecondary)

                Spacer()

                Button("선택 해제", action: onClearSelection)
                    .buttonStyle(.plain)
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(selectedUserIDs.isEmpty ? AppPalette.textMuted : AppPalette.accentRed)
                    .disabled(selectedUserIDs.isEmpty || isSubmitting)

                Button("남은 멤버 전체 선택", action: onSelectAll)
                    .buttonStyle(.plain)
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(eligibleMemberCount == 0 ? AppPalette.textMuted : AppPalette.accentBlue)
                    .disabled(eligibleMemberCount == 0 || isSubmitting)
            }

            memberListSection(title: nil)
        }
    }

    @ViewBuilder
    private var recentSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 검색")
                    .font(AppTypography.heading(15, weight: .bold))
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
                if !recentSearchKeywords.isEmpty {
                    Button("전체 삭제", action: onClearRecentSearches)
                        .font(AppTypography.body(12, weight: .semibold))
                        .foregroundStyle(AppPalette.accentRed)
                }
            }

            if recentSearchKeywords.isEmpty {
                inviteInfoCard(
                    title: "닉네임으로 팀원을 검색해보세요.",
                    message: "최근 검색이 없으면 바로 추가 목록에서 팀원을 골라 로비에 넣을 수 있어요."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentSearchKeywords) { keyword in
                        HStack(spacing: 12) {
                            Button {
                                onTapRecentSearch(keyword.keyword)
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
                                onDeleteRecentSearch(keyword.id)
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

    private var searchResultSection: some View {
        memberListSection(title: "검색 결과")
    }

    @ViewBuilder
    private func memberListSection(title: String?) -> some View {
        if let title {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(AppTypography.heading(15, weight: .bold))
                    .foregroundStyle(AppPalette.textPrimary)
                memberRows
            }
        } else {
            memberRows
        }
    }

    private var memberRows: some View {
        Group {
            if members.isEmpty {
                inviteInfoCard(
                    title: "검색 결과가 없어요.",
                    message: "다른 닉네임으로 다시 검색해보세요."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(members) { member in
                        let alreadyIncluded = participantUserIDs.contains(member.userID)
                        let isSelected = selectedUserIDs.contains(member.userID)

                        Button {
                            if !alreadyIncluded {
                                onToggleMember(member.userID)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(AppPalette.bgElevated)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.nickname)
                                        .font(AppTypography.body(14, weight: .semibold))
                                        .foregroundStyle(alreadyIncluded ? AppPalette.textMuted : AppPalette.textPrimary)
                                    Text(alreadyIncluded ? "이미 참가 중" : "\(member.role.rawValue) · 선택 가능")
                                        .font(AppTypography.body(11))
                                        .foregroundStyle(AppPalette.textSecondary)
                                }
                                Spacer()
                                if alreadyIncluded {
                                    Text("이미 참가")
                                        .font(AppTypography.body(11, weight: .semibold))
                                        .foregroundStyle(AppPalette.textMuted)
                                } else if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppPalette.accentBlue)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(AppPalette.textMuted)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appPanel(background: alreadyIncluded ? AppPalette.bgTertiary.opacity(0.7) : AppPalette.bgCard, radius: 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(alreadyIncluded || isSubmitting)
                        .accessibilityIdentifier("matchLobby.inviteSheet.member.\(member.userID)")
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if let submissionErrorMessage {
                inviteInfoCard(
                    title: submissionErrorMessage,
                    message: "참가자 목록과 선택한 팀원을 확인한 뒤 다시 시도해 주세요."
                )
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("선택된 팀원")
                        .font(AppTypography.body(12))
                        .foregroundStyle(AppPalette.textSecondary)
                    Text(selectedSummary)
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(selectedMembers.isEmpty ? AppPalette.textMuted : AppPalette.textPrimary)
                        .lineLimit(1)
                        .accessibilityIdentifier("memberInviteSheet.selectedSummary")
                }

                Spacer()

                Text("선택 \(selectedMembers.count)명")
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(selectedMembers.isEmpty ? AppPalette.textMuted : AppPalette.accentBlue)
            }
            .padding(.horizontal, 4)

            Button(action: onSubmitSelection) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("팀원 추가")
                }
            }
            .buttonStyle(
                PrimaryButtonStyle(
                    fill: selectedMembers.isEmpty || isSubmitting
                        ? AppPalette.bgTertiary
                        : AppPalette.accentBlue
                )
            )
            .disabled(selectedMembers.isEmpty || isSubmitting)
            .accessibilityIdentifier("memberInviteSheet.submitButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(AppPalette.bgPrimary.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.border.opacity(0.8))
                .frame(height: 1)
        }
    }

    private func inviteInfoCard(title: String, message: String) -> some View {
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
}
