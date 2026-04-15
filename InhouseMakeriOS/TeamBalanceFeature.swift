import ComposableArchitecture
import SwiftUI

@Reducer
struct TeamBalanceFeature {
    @ObservableState
    struct State: Equatable {
        enum PendingProtectedAction: Equatable {
            case reload
            case reroll
            case confirmSelection
        }

        let groupID: String
        let matchID: String
        var groupName = "내전"
        var loadState: ScreenLoadState<TeamBalanceSnapshot> = .initial
        var actionState: AsyncActionState = .idle
        var selectedMode: BalanceMode = .balanced
        var preferredPositions: [String: [Position]] = [:]
        var shouldNavigateToMatchResult = false
        var pendingProtectedAction: PendingProtectedAction?

        enum BalancePhase: Equatable {
            case noCandidates
            case hasCandidates
            case rerolling
            case selected
        }

        var phase: BalancePhase {
            if shouldNavigateToMatchResult { return .selected }
            if case .inProgress = actionState { return .rerolling }
            switch loadState {
            case .empty:
                return .noCandidates
            case .content, .refreshing:
                return .hasCandidates
            case .initial, .loading, .error:
                return .noCandidates
            }
        }

        var availableModes: [BalanceMode] {
            guard let snapshot = loadState.value else { return [] }
            return Array(Set(snapshot.candidates.map(\.type))).sorted { $0.rawValue < $1.rawValue }
        }

        var selectedCandidate: MatchCandidate? {
            guard let snapshot = loadState.value else { return nil }
            return snapshot.candidates.first(where: { $0.type == selectedMode }) ?? snapshot.candidates.first
        }

        func rows(for side: TeamSide) -> [TeamBalanceRow] {
            guard let candidate = selectedCandidate else { return [] }
            let players = side == .blue ? candidate.teamA : candidate.teamB
            return players.map { player in
                TeamBalanceRow(
                    id: player.id,
                    roleLabel: player.assignedRole.shortLabel,
                    name: player.nickname,
                    score: Int(player.rolePower.rounded()),
                    isOffRole: !(preferredPositions[player.userID] ?? [player.assignedRole]).contains(player.assignedRole),
                    isHighlighted: false
                )
            }
        }

        func draftForManualAdjust() -> ManualAdjustDraft? {
            guard let candidate = selectedCandidate else { return nil }
            let blue = candidate.teamA.map { player in
                ManualAdjustRow(
                    id: player.id,
                    userID: player.userID,
                    role: player.assignedRole,
                    name: player.nickname,
                    score: Int(player.rolePower.rounded()),
                    isOffRole: !(preferredPositions[player.userID] ?? [player.assignedRole]).contains(player.assignedRole)
                )
            }
            let red = candidate.teamB.map { player in
                ManualAdjustRow(
                    id: player.id,
                    userID: player.userID,
                    role: player.assignedRole,
                    name: player.nickname,
                    score: Int(player.rolePower.rounded()),
                    isOffRole: !(preferredPositions[player.userID] ?? [player.assignedRole]).contains(player.assignedRole)
                )
            }
            return ManualAdjustDraft(blueRows: blue, redRows: red)
        }
    }

    enum Action: Equatable {
        case load(force: Bool = false)
        case loadResponse(Result<LoadPayload, UserFacingError>)
        case modeSelected(BalanceMode)
        case rerollTapped
        case rerollResponse(Result<LoadPayload, UserFacingError>)
        case confirmSelectionTapped
        case confirmSelectionSucceeded
        case confirmSelectionFailed(UserFacingError)
        case authRetryHandled
        case navigationHandled
    }

    struct LoadPayload: Equatable {
        let snapshot: TeamBalanceSnapshot
        let groupName: String
        let preferredPositions: [String: [Position]]
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
                    do {
                        let payload = try await Self.loadPayload(container: container, groupID: groupID, matchID: matchID)
                        await send(.loadResponse(.success(payload)))
                    } catch let error as UserFacingError {
                        await send(.loadResponse(.failure(error)))
                    } catch {
                        await send(.loadResponse(.failure(.unexpected("팀 밸런스 로딩 실패", message: "추천 조합을 불러오지 못했습니다."))))
                    }
                }

            case let .loadResponse(.success(payload)):
                state.groupName = payload.groupName
                state.preferredPositions = payload.preferredPositions
                state.loadState = payload.snapshot.match.candidates.isEmpty
                    ? .empty("추천 조합이 없습니다.\n로비에서 자동 팀 생성을 다시 실행해주세요.")
                    : .content(payload.snapshot)
                state.selectedMode = payload.snapshot.match.candidates.first?.type ?? .balanced
                return .none

            case let .loadResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.loadState = .empty("로그인 후 팀 밸런스를 다시 확인할 수 있어요.")
                    state.pendingProtectedAction = .reload
                } else {
                    state.loadState = .error(error)
                }
                return .none

            case let .modeSelected(mode):
                state.selectedMode = mode
                return .none

            case .rerollTapped:
                guard let candidate = state.selectedCandidate else { return .none }
                state.actionState = .inProgress("조합을 다시 생성하는 중입니다")
                let groupID = state.groupID
                let matchID = state.matchID
                let selectedMode = state.selectedMode
                let container = appContainer
                return .run { send in
                    do {
                        _ = try await container.matchRepository.reroll(
                            matchID: matchID,
                            mode: selectedMode,
                            excludeCandidateIDs: [candidate.candidateID]
                        )
                        let payload = try await Self.loadPayload(container: container, groupID: groupID, matchID: matchID)
                        await send(.rerollResponse(.success(payload)))
                    } catch let error as UserFacingError {
                        await send(.rerollResponse(.failure(error)))
                    } catch {
                        await send(.rerollResponse(.failure(.unexpected("조합 재생성 실패", message: "조합 재생성에 실패했습니다."))))
                    }
                }

            case let .rerollResponse(.success(payload)):
                state.groupName = payload.groupName
                state.preferredPositions = payload.preferredPositions
                state.loadState = payload.snapshot.match.candidates.isEmpty
                    ? .empty("추천 조합이 없습니다.\n로비에서 자동 팀 생성을 다시 실행해주세요.")
                    : .content(payload.snapshot)
                state.selectedMode = payload.snapshot.match.candidates.first?.type ?? state.selectedMode
                state.actionState = .success("새 조합이 생성되었습니다")
                return .none

            case let .rerollResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .reroll
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .confirmSelectionTapped:
                guard let candidate = state.selectedCandidate else { return .none }
                state.actionState = .inProgress("조합을 확정하는 중입니다")
                let groupID = state.groupID
                let matchID = state.matchID
                let groupName = state.groupName
                let container = appContainer
                return .run { send in
                    do {
                        _ = try await container.matchRepository.selectCandidate(matchID: matchID, candidateNo: candidate.candidateNo)
                        container.localStore.trackMatch(
                            RecentMatchContext(matchID: matchID, groupID: groupID, groupName: groupName, createdAt: Date())
                        )
                        container.localStore.appendNotification(title: "팀 확정", body: "추천 조합 \(candidate.candidateNo)번이 확정되었습니다.", symbol: "checkmark.seal.fill")
                        await send(.confirmSelectionSucceeded)
                    } catch let error as UserFacingError {
                        await send(.confirmSelectionFailed(error))
                    } catch {
                        await send(.confirmSelectionFailed(.unexpected("조합 확정 실패", message: "조합 확정에 실패했습니다.")))
                    }
                }

            case .confirmSelectionSucceeded:
                state.actionState = .success("조합이 확정되었습니다")
                state.shouldNavigateToMatchResult = true
                return .none

            case let .confirmSelectionFailed(error):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .confirmSelection
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .authRetryHandled:
                state.pendingProtectedAction = nil
                return .none

            case .navigationHandled:
                state.shouldNavigateToMatchResult = false
                return .none
            }
        }
    }

    private static func loadPayload(container: AppContainer, groupID: String, matchID: String) async throws -> LoadPayload {
        async let group = container.groupRepository.detail(groupID: groupID)
        async let match = container.matchRepository.detail(matchID: matchID)
        let (groupValue, matchValue) = try await (group, match)
        let preferred = await inferPreferredPositions(container: container, userIDs: matchValue.players.map(\.userID))
        return LoadPayload(
            snapshot: TeamBalanceSnapshot(match: matchValue, candidates: matchValue.candidates),
            groupName: groupValue.name,
            preferredPositions: preferred
        )
    }

    private static func inferPreferredPositions(container: AppContainer, userIDs: [String]) async -> [String: [Position]] {
        var map: [String: [Position]] = [:]
        for userID in userIDs {
            if let power = try? await container.profileRepository.powerProfile(userID: userID) {
                let preferred = power.lanePower
                    .sorted { $0.value > $1.value }
                    .map(\.key)
                map[userID] = Array(preferred.prefix(2))
            }
        }
        return map
    }
}

struct TeamBalanceFeatureView: View {
    @Bindable var store: StoreOf<TeamBalanceFeature>
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        screenScaffold(title: "팀 밸런스 결과", onBack: router.pop) {
            switch store.loadState {
            case .initial, .loading:
                LoadingStateView(title: "추천 조합을 불러오는 중입니다")
                    .task { store.send(.load()) }
            case let .error(error):
                ErrorStateView(error: error) { store.send(.load(force: true)) }
            case let .empty(message):
                EmptyStateView(title: "팀 밸런스 결과", message: message)
            case .content, .refreshing:
                let blueRows = store.state.rows(for: .blue)
                let redRows = store.state.rows(for: .red)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        summaryCard(candidate: store.selectedCandidate)
                        modeTabs()
                        HStack(spacing: 8) {
                            TeamColumnView(title: "블루 팀", tint: AppPalette.teamBlue, background: Color(hex: 0x0D1B2A), players: blueRows)
                            TeamColumnView(title: "레드 팀", tint: AppPalette.teamRed, background: Color(hex: 0x2A0D0D), players: redRows)
                        }
                        laneComparisonSection(blueRows: blueRows, redRows: redRows)
                    }
                    .padding(16)
                }
                VStack(spacing: 10) {
                    Button("이 조합으로 확정") {
                        store.send(.confirmSelectionTapped)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    HStack(spacing: 8) {
                        Button("다시 생성") {
                            store.send(.rerollTapped)
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("수동 조정") {
                            if let draft = store.state.draftForManualAdjust() {
                                router.push(.manualAdjust(matchID: store.matchID, draft: draft))
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    if let candidate = store.selectedCandidate {
                        Text("추천 조합 \(candidate.candidateNo)번을 확정하면 결과 입력 단계로 이동합니다.")
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppPalette.bgSecondary)
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
            case .reroll:
                session.requireReauthentication(for: .matchSave) {
                    store.send(.rerollTapped)
                }
            case .confirmSelection:
                session.requireReauthentication(for: .matchSave) {
                    store.send(.confirmSelectionTapped)
                }
            }
            store.send(.authRetryHandled)
        }
        .onChange(of: store.shouldNavigateToMatchResult) { _, isActive in
            if isActive {
                router.push(.matchResult(matchID: store.matchID))
                store.send(.navigationHandled)
            }
        }
    }

    private func summaryCard(candidate: MatchCandidate?) -> some View {
        let left = Int((candidate?.teamAPower ?? 51).rounded())
        let right = Int((candidate?.teamBPower ?? 49).rounded())
        let tags = Array((candidate?.explanationTags ?? []).prefix(2))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("예상 밸런스")
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(AppPalette.textMuted)
                    Text(abs(left - right) <= 4 ? "접전 예상" : "격차 있음")
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(AppPalette.accentGreen)
                }
                Spacer()
                if let candidate {
                    tagChip("추천 \(candidate.candidateNo)", tint: AppPalette.accentBlue)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 18) {
                VStack(spacing: 2) {
                    Text("\(left)")
                        .font(AppTypography.heading(38, weight: .heavy))
                        .foregroundStyle(AppPalette.teamBlue)
                    Text("블루 팀")
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(AppPalette.teamBlue.opacity(0.8))
                }
                Text(":")
                    .font(AppTypography.heading(26, weight: .bold))
                    .foregroundStyle(AppPalette.textMuted)
                    .padding(.bottom, 8)
                VStack(spacing: 2) {
                    Text("\(right)")
                        .font(AppTypography.heading(38, weight: .heavy))
                        .foregroundStyle(AppPalette.teamRed)
                    Text("레드 팀")
                        .font(AppTypography.body(11, weight: .semibold))
                        .foregroundStyle(AppPalette.teamRed.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                tagChip("오프포지션 \(candidate?.offRoleCount ?? 0)명", tint: AppPalette.accentOrange)
                tagChip(candidate?.type.designBadgeTitle ?? "균형형 추천", tint: AppPalette.accentBlue)
                ForEach(tags, id: \.self) { tag in
                    tagChip(tag, tint: AppPalette.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1A2744), AppPalette.bgPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func modeTabs() -> some View {
        HStack(spacing: 4) {
            ForEach(store.availableModes, id: \.self) { mode in
                Button(mode.title) {
                    store.send(.modeSelected(mode))
                }
                .font(AppTypography.body(13, weight: store.selectedMode == mode ? .semibold : .regular))
                .foregroundStyle(store.selectedMode == mode ? Color.white : AppPalette.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(store.selectedMode == mode ? AppPalette.accentBlue : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(3)
        .background(AppPalette.bgSecondary)
        .appPanel(background: AppPalette.bgSecondary, radius: 10)
    }

    private func laneComparisonSection(blueRows: [TeamBalanceRow], redRows: [TeamBalanceRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("라인별 파워 비교")
                    .font(AppTypography.heading(14, weight: .bold))
                Spacer()
                Text("역할별 영향력")
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textMuted)
            }
            VStack(spacing: 8) {
                ForEach([Position.top, .jungle, .mid, .adc, .support], id: \.self) { role in
                    let left = blueRows.first(where: { $0.roleLabel == role.shortLabel })?.score ?? 50
                    let right = redRows.first(where: { $0.roleLabel == role.shortLabel })?.score ?? 50
                    LaneComparisonBarView(
                        label: role.shortLabel,
                        leftValue: left,
                        rightValue: right,
                        leftColor: AppPalette.teamBlue,
                        rightColor: AppPalette.teamRed
                    )
                }
            }
        }
        .padding(16)
        .appPanel(background: AppPalette.bgCard, radius: 14)
    }

    private func tagChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTypography.body(11))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppPalette.bgTertiary)
            .clipShape(Capsule())
    }
}
