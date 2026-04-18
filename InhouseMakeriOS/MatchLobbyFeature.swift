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

        let groupID: String
        let matchID: String
        var loadState: ScreenLoadState<MatchLobbySnapshot> = .initial
        var actionState: AsyncActionState = .idle
        var selectedMemberIDs: Set<String> = []
        var showsManageSheet = false
        var shouldNavigateToTeamBalance = false
        var pendingProtectedAction: PendingProtectedAction?

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
            return match.acceptedCount >= 10 ? .ready : .underCapacity
        }
    }

    enum Action: Equatable {
        case load(force: Bool = false)
        case loadResponse(Result<MatchLobbySnapshot, UserFacingError>)
        case manageSheetPresented
        case manageSheetDismissed
        case toggleMemberSelection(String)
        case addSelectedPlayersTapped
        case addPlayersResponse(Result<MatchLobbySnapshot, UserFacingError>)
        case autoBalanceTapped
        case autoBalanceResponse(Result<MatchLobbySnapshot, UserFacingError>)
        case authRetryHandled
        case navigationHandled
    }

    @Dependency(\.appContainer) var appContainer

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                if !force, case .content = state.loadState { return .none }
                state.loadState = .loading
                let groupID = state.groupID
                let matchID = state.matchID
                let container = appContainer
                return .run { send in
#if DEBUG
                    print("[RouteFetch] fetch started screen=match_lobby groupID=\(groupID) matchID=\(matchID)")
#endif
                    do {
                        let resolvedContainer = await container()
                        let snapshot = try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
#if DEBUG
                        print("[RouteFetch] fetch success screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live players=\(snapshot.match.players.count)")
#endif
                        await send(.loadResponse(.success(snapshot)))
                    } catch let error as UserFacingError {
#if DEBUG
                        print("[RouteFetch] fetch failure screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)")
#endif
                        await send(.loadResponse(.failure(error)))
                    } catch {
#if DEBUG
                        print("[RouteFetch] fetch failure screen=match_lobby groupID=\(groupID) matchID=\(matchID) source=live status=nil message=\(error.localizedDescription)")
#endif
                        await send(.loadResponse(.failure(.unexpected("로비 로딩 실패", message: "내전 로비를 불러오지 못했습니다."))))
                    }
                }

            case let .loadResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                return .none

            case let .loadResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.loadState = .empty("로그인 후 내전 로비를 다시 열 수 있어요.")
                    state.pendingProtectedAction = .reload
                } else {
                    state.loadState = .error(error)
                }
                return .none

            case .manageSheetPresented:
                state.showsManageSheet = true
                return .none

            case .manageSheetDismissed:
                state.showsManageSheet = false
                state.selectedMemberIDs.removeAll()
                return .none

            case let .toggleMemberSelection(userID):
                if state.selectedMemberIDs.contains(userID) {
                    state.selectedMemberIDs.remove(userID)
                } else {
                    state.selectedMemberIDs.insert(userID)
                }
                return .none

            case .addSelectedPlayersTapped:
                guard !state.selectedMemberIDs.isEmpty else { return .none }
                state.actionState = .inProgress("참가자를 추가하는 중입니다")
                let groupID = state.groupID
                let matchID = state.matchID
                let userIDs = Array(state.selectedMemberIDs)
                let container = appContainer
                return .run { send in
                    do {
                        let resolvedContainer = await container()
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
                        let snapshot = try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
                        await send(.addPlayersResponse(.success(snapshot)))
                    } catch let error as UserFacingError {
                        await send(.addPlayersResponse(.failure(error)))
                    } catch {
                        await send(.addPlayersResponse(.failure(.unexpected("참가자 추가 실패", message: "참가자 추가에 실패했습니다."))))
                    }
                }

            case let .addPlayersResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                state.showsManageSheet = false
                state.selectedMemberIDs.removeAll()
                state.actionState = .success("참가자가 추가되었습니다")
                return .none

            case let .addPlayersResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .addPlayers
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .autoBalanceTapped:
                guard let snapshot = state.loadState.value else { return .none }
                state.actionState = .inProgress("자동 팀 생성을 준비하는 중입니다")
                let groupID = state.groupID
                let matchID = state.matchID
                let container = appContainer
                return .run { send in
                    do {
                        let resolvedContainer = await container()
                        await MainActor.run {
                            resolvedContainer.localStore.clearManualAdjustDraft(matchID: matchID)
                        }
                        if snapshot.match.status != .locked && snapshot.match.status != .balanced {
                            _ = try await resolvedContainer.matchRepository.lock(matchID: matchID)
                        }
                        _ = try await resolvedContainer.matchRepository.autoBalance(matchID: matchID)
                        let refreshed = try await Self.makeSnapshot(container: resolvedContainer, groupID: groupID, matchID: matchID)
                        await MainActor.run {
                            resolvedContainer.localStore.appendNotification(
                                title: "자동 밸런스 생성",
                                body: "추천 조합이 생성되었습니다.",
                                symbol: "arrow.trianglehead.2.clockwise"
                            )
                        }
                        await send(.autoBalanceResponse(.success(refreshed)))
                    } catch let error as UserFacingError {
                        await send(.autoBalanceResponse(.failure(error)))
                    } catch {
                        await send(.autoBalanceResponse(.failure(.unexpected("자동 팀 생성 실패", message: "추천 조합 생성에 실패했습니다."))))
                    }
                }

            case let .autoBalanceResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                state.actionState = .success("추천 조합이 생성되었습니다")
                state.shouldNavigateToTeamBalance = true
                return .none

            case let .autoBalanceResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .autoBalance
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .authRetryHandled:
                state.pendingProtectedAction = nil
                return .none

            case .navigationHandled:
                state.shouldNavigateToTeamBalance = false
                return .none
            }
        }
    }

    private static func makeSnapshot(container: AppContainer, groupID: String, matchID: String) async throws -> MatchLobbySnapshot {
        let group = try await container.groupRepository.detail(groupID: groupID)
        let members = try await container.groupRepository.members(groupID: groupID)
        let match = try await container.matchRepository.detail(matchID: matchID)
        let powerProfiles = await loadPowerProfiles(container: container, userIDs: match.players.map(\.userID))
        await MainActor.run {
            container.localStore.trackGroup(id: groupID)
            container.localStore.trackMatch(
                RecentMatchContext(matchID: match.id, groupID: groupID, groupName: group.name, createdAt: Date())
            )
        }
        return MatchLobbySnapshot(match: match, group: group, members: members, powerProfiles: powerProfiles)
    }

    private static func loadPowerProfiles(container: AppContainer, userIDs: [String]) async -> [String: PowerProfile] {
        var profiles: [String: PowerProfile] = [:]
        for userID in Set(userIDs) {
            if let profile = try? await container.profileRepository.powerProfile(userID: userID) {
                profiles[userID] = profile
            }
        }
        return profiles
    }
}

struct MatchLobbyFeatureView: View {
    @Bindable var store: StoreOf<MatchLobbyFeature>
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        screenScaffold(title: "내전 로비", onBack: router.pop, rightSystemImage: "ellipsis", onRightTap: { store.send(.manageSheetPresented) }) {
            switch store.loadState {
            case .initial, .loading:
                LoadingStateView(title: "내전 로비를 불러오는 중입니다")
                    .task { store.send(.load()) }
            case let .error(error):
                ErrorStateView(error: error) { store.send(.load(force: true)) }
            case .empty:
                EmptyStateView(title: "내전 로비", message: "내전 로비가 없습니다.")
            case let .content(snapshot), let .refreshing(snapshot):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(alignment: .center, spacing: 10) {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text("\(snapshot.match.acceptedCount)")
                                    .font(AppTypography.heading(42, weight: .heavy))
                                    .foregroundStyle(AppPalette.accentBlue)
                                Text("/ 10")
                                    .font(AppTypography.heading(22, weight: .semibold))
                                    .foregroundStyle(AppPalette.textMuted)
                            }
                            Text(statusLabel(for: snapshot.match))
                                .font(AppTypography.body(12))
                                .foregroundStyle(AppPalette.textSecondary)
                            ProgressView(value: Double(snapshot.match.acceptedCount), total: 10)
                                .tint(AppPalette.accentBlue)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .appPanel(background: AppPalette.bgCard, radius: 16)

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
                                        subtitle: playerSubtitle(player),
                                        powerScore: Int(snapshot.powerProfiles[player.userID]?.overallPower.rounded() ?? 0)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if snapshot.match.players.count < 10 {
                                Button {
                                    store.send(.manageSheetPresented)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.badge.plus")
                                            .foregroundStyle(AppPalette.textMuted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(10 - snapshot.match.players.count)명 더 필요")
                                                .font(AppTypography.body(13, weight: .semibold))
                                            Text("초대 또는 모집으로 로비를 채워주세요")
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
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 12)
                }

                VStack(spacing: 8) {
                    let canAutoBalance = snapshot.match.acceptedCount == 10 || snapshot.match.status == .balanced
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
                        } else {
                            Button(snapshot.match.status == .balanced ? "팀 밸런스 보기" : "자동 팀 생성") {}
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(true)
                        }

                        Button("수동 배치") {
                            router.push(.teamBalance(groupID: store.groupID, matchID: store.matchID))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(snapshot.match.acceptedCount < 10)
                    }

                    Text(bottomNote(for: snapshot.match))
                        .font(AppTypography.body(11))
                        .foregroundStyle(AppPalette.textMuted)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(AppPalette.bgSecondary)
                .sheet(
                    isPresented: Binding(
                        get: { store.showsManageSheet },
                        set: { isPresented in
                            store.send(isPresented ? .manageSheetPresented : .manageSheetDismissed)
                        }
                    )
                ) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("참가 가능한 멤버")
                                        .font(AppTypography.heading(18, weight: .bold))
                                    Text("이미 참가 중인 멤버는 비활성화되며, 선택한 멤버만 로비에 추가됩니다.")
                                        .font(AppTypography.body(12))
                                        .foregroundStyle(AppPalette.textSecondary)

                                    ForEach(snapshot.members) { member in
                                        let alreadyIncluded = snapshot.match.players.contains(where: { $0.userID == member.userID })
                                        Button {
                                            if !alreadyIncluded {
                                                store.send(.toggleMemberSelection(member.userID))
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
                                                    Text("참가 중")
                                                        .font(AppTypography.body(11, weight: .semibold))
                                                        .foregroundStyle(AppPalette.textMuted)
                                                } else if store.selectedMemberIDs.contains(member.userID) {
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
                                        .disabled(alreadyIncluded)
                                    }
                                }
                                .padding(16)
                            }

                            VStack(spacing: 8) {
                                Text("선택 \(store.selectedMemberIDs.count)명")
                                    .font(AppTypography.body(11))
                                    .foregroundStyle(AppPalette.textMuted)
                                Button("참가자 추가") {
                                    store.send(.addSelectedPlayersTapped)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(store.selectedMemberIDs.isEmpty)
                            }
                            .padding(16)
                            .background(AppPalette.bgSecondary)
                        }
                        .background(AppPalette.bgPrimary)
                        .navigationTitle("참가자 추가")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("닫기") {
                                    store.send(.manageSheetDismissed)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: Alignment.bottom) { actionBanner(store.actionState) }
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
    }

    private func statusLabel(for match: Match) -> String {
        switch match.status {
        case .balanced:
            return "추천 조합이 준비되었습니다"
        case .locked:
            return "참가가 잠겨 있어 밸런스 계산을 준비 중입니다"
        default:
            return match.acceptedCount >= 10 ? "10명이 모였습니다. 자동 팀 생성을 실행할 수 있습니다" : "참가자 모집 중 · \(requiredRolesText(for: match))"
        }
    }

    private func bottomNote(for match: Match) -> String {
        switch match.status {
        case .balanced:
            return "이미 생성된 추천 조합을 확인할 수 있습니다."
        case .locked:
            return "참가가 잠겨 있습니다. 곧 팀 밸런스 결과로 이동할 수 있습니다."
        default:
            return match.acceptedCount >= 10 ? "자동 팀 생성을 실행하면 추천 조합을 받아옵니다." : "현재는 정원 미달이라 자동 팀 생성이 비활성화됩니다."
        }
    }

    private func requiredRolesText(for match: Match) -> String {
        let trackedRoles: [Position] = [.top, .jungle, .mid, .adc, .support]
        let occupied = Set(match.players.compactMap(\.assignedRole))
        let missing = trackedRoles.filter { !occupied.contains($0) }
        guard !missing.isEmpty else { return "추가 포지션 확인 필요" }
        return missing.prefix(3).map(\.shortLabel).joined(separator: ", ") + " 필요"
    }

    private func playerSubtitle(_ player: MatchPlayer) -> String {
        let role = player.assignedRole?.shortLabel ?? "포지션 미정"
        return "\(role) · \(player.participationStatus == .accepted ? "최근 폼 공개" : "참가 확인 대기")"
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
