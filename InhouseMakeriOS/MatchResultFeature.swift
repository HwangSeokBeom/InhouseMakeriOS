import ComposableArchitecture
import SwiftUI

@Reducer
struct MatchResultFeature {
    @ObservableState
    struct State: Equatable {
        enum PendingProtectedAction: Equatable {
            case reload
            case submit
            case requestChange
        }

        enum Mode: Equatable {
            case quick
            case detailed
        }

        struct KDAInput: Equatable, Hashable {
            var kills: String = "0"
            var deaths: String = "0"
            var assists: String = "0"

            func validated() -> (Int, Int, Int) {
                (Int(kills) ?? 0, Int(deaths) ?? 0, Int(assists) ?? 0)
            }
        }

        enum ResultPhase: Equatable {
            case draft
            case partial
            case confirmed
            case disputed
        }

        let matchID: String
        var loadState: ScreenLoadState<MatchDetailSnapshot> = .initial
        var actionState: AsyncActionState = .idle
        var mode: Mode = .quick
        var winningTeam: TeamSide = .blue
        var selectedMVPUserID: String?
        var laneResults: [String: TeamSide?] = ["TOP": .blue, "JGL": .red, "MID": .blue, "BOT": nil]
        var balanceFeeling = 5
        var kdaInputs: [String: KDAInput] = [:]
        var pendingProtectedAction: PendingProtectedAction?

        var isActionInFlight: Bool {
            if case .inProgress = actionState {
                return true
            }
            return false
        }

        var mvpCandidates: [MatchPlayer] {
            guard let snapshot = loadState.value else { return [] }
            return snapshot.match.players.filter { $0.teamSide == winningTeam }
        }

        var resultPhase: ResultPhase {
            guard let result = loadState.value?.result else { return .draft }
            switch result.resultStatus {
            case .partial: return .partial
            case .confirmed: return .confirmed
            case .disputed: return .disputed
            }
        }
    }

    enum StatField: Equatable, Hashable {
        case kills
        case deaths
        case assists
    }

    enum Action: Equatable {
        case load(force: Bool = false)
        case loadResponse(Result<MatchDetailSnapshot, UserFacingError>)
        case modeSelected(State.Mode)
        case winningTeamSelected(TeamSide)
        case mvpSelected(String)
        case laneResultSelected(key: String, winner: TeamSide?)
        case balanceFeelingSelected(Int)
        case kdaChanged(userID: String, field: StatField, value: String)
        case saveLocallyTapped
        case saveLocallyResponse(Result<CachedResultMetadata, UserFacingError>)
        case submitTapped
        case submitResponse(Result<MatchDetailSnapshot, UserFacingError>)
        case requestChangeTapped
        case requestChangeResponse(Result<MatchDetailSnapshot, UserFacingError>)
        case authRetryHandled
        case shareLinkTapped
    }

    @Dependency(\.appContainer) var appContainer

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                if !force, case .content = state.loadState { return .none }
                state.loadState = .loading
                let matchID = state.matchID
                let container = appContainer
                return .run { send in
                    do {
                        let resolvedContainer = await container()
                        let snapshot = try await Self.makeSnapshot(container: resolvedContainer, matchID: matchID)
                        await send(.loadResponse(.success(snapshot)))
                    } catch let error as UserFacingError {
                        await send(.loadResponse(.failure(error)))
                    } catch {
                        await send(.loadResponse(.failure(.unexpected("결과 입력 로딩 실패", message: "경기 결과 입력 화면을 준비하지 못했습니다."))))
                    }
                }

            case let .loadResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                state.winningTeam = snapshot.result?.winningTeam ?? snapshot.cachedMetadata?.winningTeam ?? .blue
                state.selectedMVPUserID = snapshot.cachedMetadata?.mvpUserID
                state.balanceFeeling = snapshot.cachedMetadata?.balanceRating ?? 5
                if state.selectedMVPUserID == nil {
                    state.selectedMVPUserID = snapshot.match.players.first(where: { $0.teamSide == state.winningTeam })?.userID
                }
                for player in snapshot.match.players {
                    let existingStat = snapshot.result?.players.first(where: { $0.userID == player.userID })
                    state.kdaInputs[player.userID] = State.KDAInput(
                        kills: existingStat.map { String($0.kills) } ?? "0",
                        deaths: existingStat.map { String($0.deaths) } ?? "0",
                        assists: existingStat.map { String($0.assists) } ?? "0"
                    )
                }
                return .none

            case let .loadResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.loadState = .empty("로그인 후 경기 결과 화면을 다시 열 수 있어요.")
                    state.pendingProtectedAction = .reload
                } else {
                    state.loadState = .error(error)
                }
                return .none

            case let .modeSelected(mode):
                state.mode = mode
                return .none

            case let .winningTeamSelected(team):
                state.winningTeam = team
                state.selectedMVPUserID = state.mvpCandidates.first?.userID
                return .none

            case let .mvpSelected(userID):
                state.selectedMVPUserID = userID
                return .none

            case let .laneResultSelected(key, winner):
                state.laneResults[key] = winner
                return .none

            case let .balanceFeelingSelected(value):
                state.balanceFeeling = value
                return .none

            case let .kdaChanged(userID, field, value):
                var current = state.kdaInputs[userID] ?? .init()
                switch field {
                case .kills:
                    current.kills = value
                case .deaths:
                    current.deaths = value
                case .assists:
                    current.assists = value
                }
                state.kdaInputs[userID] = current
                return .none

            case .saveLocallyTapped:
                guard !state.isActionInFlight else { return .none }
                guard let snapshot = state.loadState.value else { return .none }
                guard let mvpUserID = state.selectedMVPUserID else {
                    state.actionState = .failure("MVP를 선택해주세요.")
                    return .none
                }

                let matchID = state.matchID
                let winningTeam = state.winningTeam
                let balanceFeeling = state.balanceFeeling
                let snapshotMatchID = snapshot.match.id
                let metadata = CachedResultMetadata(
                    winningTeam: winningTeam,
                    mvpUserID: mvpUserID,
                    balanceRating: balanceFeeling,
                    updatedAt: Date()
                )

                state.actionState = .inProgress("이 기기에 저장하는 중입니다")

                return .run { send in
                    let container = await appContainer()
                    await MainActor.run {
                        container.localStore.cacheResult(matchID: matchID, metadata: metadata)
                        container.localStore.appendNotification(
                            title: "로컬 저장",
                            body: "\(snapshotMatchID) 결과가 이 기기에 저장되었습니다.",
                            symbol: "externaldrive.fill.badge.checkmark"
                        )
                    }
                    await send(.saveLocallyResponse(.success(metadata)))
                }

            case let .saveLocallyResponse(.success(metadata)):
                if let snapshot = state.loadState.value {
                    state.loadState = .content(
                        MatchDetailSnapshot(match: snapshot.match, result: snapshot.result, cachedMetadata: metadata)
                    )
                }
                state.actionState = .success("결과가 이 기기에 저장되었습니다")
                return .none

            case let .saveLocallyResponse(.failure(error)):
                state.actionState = .failure(error.message)
                return .none

            case .submitTapped:
                guard !state.isActionInFlight else { return .none }
                guard let snapshot = state.loadState.value else { return .none }
                guard let mvpUserID = state.selectedMVPUserID else {
                    state.actionState = .failure("MVP를 선택해주세요.")
                    return .none
                }

                state.actionState = .inProgress("결과를 저장하는 중입니다")
                let matchID = state.matchID
                let winningTeam = state.winningTeam
                let balanceFeeling = state.balanceFeeling
                let laneResults = state.laneResults
                let kdaInputs = state.kdaInputs
                let container = appContainer
                return .run { send in
                    do {
                        let resolvedContainer = await container()
                        let payload = QuickResultRequestDTO(
                            winningTeam: winningTeam,
                            mvpUserId: mvpUserID,
                            balanceRating: balanceFeeling,
                            players: Self.makePlayerPayloads(
                                match: snapshot.match,
                                selectedMVPUserID: mvpUserID,
                                laneResults: laneResults,
                                kdaInputs: kdaInputs
                            )
                        )
                        let submission = try await resolvedContainer.matchRepository.submitQuickResult(matchID: matchID, payload: payload)
                        await MainActor.run {
                            resolvedContainer.localStore.cacheResult(
                                matchID: matchID,
                                metadata: CachedResultMetadata(
                                    winningTeam: winningTeam,
                                    mvpUserID: mvpUserID,
                                    balanceRating: balanceFeeling,
                                    updatedAt: Date()
                                )
                            )
                            resolvedContainer.localStore.appendNotification(
                                title: "결과 저장",
                                body: "결과가 \(submission.status.title) 상태로 저장되었습니다.",
                                symbol: "checkmark.circle.fill"
                            )
                        }
                        let refreshed = try await Self.makeSnapshot(container: resolvedContainer, matchID: matchID)
                        await send(.submitResponse(.success(refreshed)))
                    } catch let error as UserFacingError {
                        await send(.submitResponse(.failure(error)))
                    } catch {
                        await send(.submitResponse(.failure(.unexpected("결과 저장 실패", message: "결과 저장에 실패했습니다."))))
                    }
                }

            case let .submitResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                state.actionState = .success("결과가 저장되었습니다")
                return .none

            case let .submitResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .submit
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .requestChangeTapped:
                guard !state.isActionInFlight else { return .none }
                guard let resultID = state.loadState.value?.result?.id else {
                    state.actionState = .failure("수정 요청할 기존 결과가 없습니다.")
                    return .none
                }
                state.actionState = .inProgress("수정 요청을 전송하는 중입니다")
                let matchID = state.matchID
                let container = appContainer
                return .run { send in
                    do {
                        let resolvedContainer = await container()
                        _ = try await resolvedContainer.matchRepository.confirmResult(
                            matchID: matchID,
                            resultID: resultID,
                            action: .suggestChange,
                            comment: "클라이언트에서 수정 요청"
                        )
                        let refreshed = try await Self.makeSnapshot(container: resolvedContainer, matchID: matchID)
                        await send(.requestChangeResponse(.success(refreshed)))
                    } catch let error as UserFacingError {
                        await send(.requestChangeResponse(.failure(error)))
                    } catch {
                        await send(.requestChangeResponse(.failure(.unexpected("수정 요청 실패", message: "수정 요청에 실패했습니다."))))
                    }
                }

            case let .requestChangeResponse(.success(snapshot)):
                state.loadState = .content(snapshot)
                state.actionState = .success("수정 요청을 보냈습니다")
                return .none

            case let .requestChangeResponse(.failure(error)):
                if error.requiresAuthentication {
                    state.actionState = .idle
                    state.pendingProtectedAction = .requestChange
                } else {
                    state.actionState = .failure(error.message)
                }
                return .none

            case .authRetryHandled:
                state.pendingProtectedAction = nil
                return .none

            case .shareLinkTapped:
                guard !state.isActionInFlight else { return .none }
                state.actionState = .success("공유 링크 기능은 곧 연결됩니다")
                return .none
            }
        }
    }

    private static func makeSnapshot(container: AppContainer, matchID: String) async throws -> MatchDetailSnapshot {
        let match = try await container.matchRepository.detail(matchID: matchID)
        let result = try? await container.matchRepository.result(matchID: matchID)
        let cache = await MainActor.run { container.localStore.cachedResults[matchID] }
        return MatchDetailSnapshot(match: match, result: result, cachedMetadata: cache)
    }

    private static func makePlayerPayloads(
        match: Match,
        selectedMVPUserID: String,
        laneResults: [String: TeamSide?],
        kdaInputs: [String: State.KDAInput]
    ) -> [QuickResultPlayerDTO] {
        match.players.map { player in
            let input = kdaInputs[player.userID] ?? State.KDAInput()
            let values = input.validated()
            return QuickResultPlayerDTO(
                userId: player.userID,
                kills: values.0,
                deaths: values.1,
                assists: values.2,
                laneResult: laneResult(for: player, laneResults: laneResults),
                contributionRating: player.userID == selectedMVPUserID ? 5 : nil
            )
        }
    }

    private static func laneResult(for player: MatchPlayer, laneResults: [String: TeamSide?]) -> LaneResult {
        guard let role = player.assignedRole, let side = player.teamSide else { return .unknown }
        switch role {
        case .top:
            return laneOutcome(for: "TOP", side: side, laneResults: laneResults)
        case .jungle:
            return laneOutcome(for: "JGL", side: side, laneResults: laneResults)
        case .mid:
            return laneOutcome(for: "MID", side: side, laneResults: laneResults)
        case .adc, .support:
            return laneOutcome(for: "BOT", side: side, laneResults: laneResults)
        case .fill:
            return .unknown
        }
    }

    private static func laneOutcome(for key: String, side: TeamSide, laneResults: [String: TeamSide?]) -> LaneResult {
        guard let winner = laneResults[key] else { return .even }
        return winner == side ? .win : .lose
    }
}

struct MatchResultFeatureView: View {
    private struct KDAFocusField: Hashable {
        let userID: String
        let field: MatchResultFeature.StatField
    }

    @Bindable var store: StoreOf<MatchResultFeature>
    @ObservedObject var session: AppSessionViewModel
    @ObservedObject var router: AppRouter
    @FocusState private var focusedField: KDAFocusField?

    var body: some View {
        screenScaffold(title: "경기 결과 입력", onBack: router.pop, rightSystemImage: nil) {
            switch store.loadState {
            case .initial, .loading:
                LoadingStateView(title: "결과 입력 화면을 준비하는 중입니다")
                    .task { store.send(.load()) }
            case let .error(error):
                ErrorStateView(error: error) { store.send(.load(force: true)) }
            case .empty:
                EmptyStateView(title: "경기 결과 입력", message: "결과를 입력할 매치가 없습니다.")
            case let .content(snapshot), let .refreshing(snapshot):
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(spacing: 4) {
                            modeButton("간편 입력", isSelected: store.mode == .quick) { selectMode(.quick) }
                            modeButton("상세 입력", isSelected: store.mode == .detailed) { selectMode(.detailed) }
                        }
                        .padding(3)
                        .appPanel(background: AppPalette.bgSecondary, radius: 10)

                        sectionCard(title: "승리 팀 선택", spacing: 10) {
                            HStack(spacing: 10) {
                                teamSelectButton(title: "블루 팀 승리", icon: "crown.fill", tint: AppPalette.teamBlue, isSelected: store.winningTeam == .blue) {
                                    store.send(.winningTeamSelected(.blue))
                                }
                                teamSelectButton(title: "레드 팀 승리", icon: nil, tint: AppPalette.bgTertiary, isSelected: store.winningTeam == .red) {
                                    store.send(.winningTeamSelected(.red))
                                }
                            }
                        }

                        sectionCard(title: "MVP 선택", spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(store.mvpCandidates) { player in
                                        Button {
                                            store.send(.mvpSelected(player.userID))
                                        } label: {
                                            Text(player.nickname.replacingOccurrences(of: " ", with: "\n"))
                                                .font(AppTypography.body(10, weight: store.selectedMVPUserID == player.userID ? .semibold : .regular))
                                            .foregroundStyle(store.selectedMVPUserID == player.userID ? AppPalette.bgPrimary : AppPalette.textSecondary)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 66)
                                            .padding(.vertical, 8)
                                            .background(store.selectedMVPUserID == player.userID ? AppPalette.accentGold : AppPalette.bgTertiary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(store.selectedMVPUserID == player.userID ? .clear : AppPalette.border, lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        sectionCard(title: "라인별 승패", spacing: 8) {
                            ForEach(["TOP", "JGL", "MID", "BOT"], id: \.self) { role in
                                HStack(spacing: 8) {
                                    Text(role)
                                        .font(AppTypography.body(11, weight: .bold))
                                        .foregroundStyle(AppPalette.textSecondary)
                                        .frame(width: 38, alignment: .leading)
                                    laneButton("블루 승", color: AppPalette.teamBlue, isSelected: store.laneResults[role] == .blue) {
                                        store.send(.laneResultSelected(key: role, winner: .blue))
                                    }
                                    laneButton("레드 승", color: AppPalette.teamRed, isSelected: store.laneResults[role] == .red) {
                                        store.send(.laneResultSelected(key: role, winner: .red))
                                    }
                                    laneButton("비슷", color: AppPalette.accentGold, isSelected: store.laneResults[role] == nil) {
                                        store.send(.laneResultSelected(key: role, winner: nil))
                                    }
                                }
                                .frame(height: 38)
                            }
                        }

                        sectionCard(title: "체감 밸런스", spacing: 8) {
                            HStack(spacing: 8) {
                                feelingButton("한쪽 우세", value: 1)
                                feelingButton("살짝 우세", value: 3)
                                feelingButton("접전", value: 5)
                            }
                        }

                        if store.mode == .detailed {
                            sectionCard(title: "상세 입력 (K / D / A)", spacing: 8) {
                                ForEach(snapshot.match.players) { player in
                                    HStack {
                                        Text(player.nickname)
                                            .font(AppTypography.body(12, weight: .semibold))
                                            .frame(width: 110, alignment: .leading)
                                        numberField(
                                            "K",
                                            binding: Binding(
                                                get: { store.kdaInputs[player.userID]?.kills ?? "0" },
                                                set: { store.send(.kdaChanged(userID: player.userID, field: .kills, value: $0)) }
                                            ),
                                            focusField: KDAFocusField(userID: player.userID, field: .kills)
                                        )
                                        numberField(
                                            "D",
                                            binding: Binding(
                                                get: { store.kdaInputs[player.userID]?.deaths ?? "0" },
                                                set: { store.send(.kdaChanged(userID: player.userID, field: .deaths, value: $0)) }
                                            ),
                                            focusField: KDAFocusField(userID: player.userID, field: .deaths)
                                        )
                                        numberField(
                                            "A",
                                            binding: Binding(
                                                get: { store.kdaInputs[player.userID]?.assists ?? "0" },
                                                set: { store.send(.kdaChanged(userID: player.userID, field: .assists, value: $0)) }
                                            ),
                                            focusField: KDAFocusField(userID: player.userID, field: .assists)
                                        )
                                    }
                                }
                            }
                        } else {
                            Text("실제 서버의 quick result API는 K/D/A를 필수로 요구합니다. 현재 간편 입력에서는 미입력 값을 0/0/0으로 저장하고, 상세 입력 탭에서 직접 수정할 수 있습니다.")
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textSecondary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appPanel(background: AppPalette.bgCard, radius: 12)
                        }

                        resultStatusBanner(store.resultPhase)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.immediately)

                VStack(spacing: 8) {
                    if session.isAuthenticated {
                        HStack(spacing: 8) {
                            Button("내 계정에 저장") {
                                focusedField = nil
                                store.send(.submitTapped)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(store.isActionInFlight)

                            Button("공유 링크") {
                                focusedField = nil
                                store.send(.shareLinkTapped)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(maxWidth: 108)
                            .disabled(store.isActionInFlight)
                        }

                        Button("수정 요청") {
                            focusedField = nil
                            store.send(.requestChangeTapped)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(store.isActionInFlight)
                    } else {
                        HStack(spacing: 8) {
                            Button("로컬에 저장") {
                                focusedField = nil
                                store.send(.saveLocallyTapped)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(store.isActionInFlight)

                            Button("로그인하고 계정 저장") {
                                focusedField = nil
                                session.requireAuthentication(for: .resultSave) {
                                    store.send(.submitTapped)
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(store.isActionInFlight)
                        }

                        Button("로그인하고 공유하기") {
                            focusedField = nil
                            session.requireAuthentication(for: .shareRecord) {
                                store.send(.shareLinkTapped)
                            }
                        }
                        .font(AppTypography.body(13, weight: .semibold))
                        .foregroundStyle(AppPalette.textSecondary)
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
                session.requireReauthentication(for: .resultSave) {
                    store.send(.load(force: true))
                }
            case .submit:
                session.requireReauthentication(for: .resultSave) {
                    store.send(.submitTapped)
                }
            case .requestChange:
                session.requireReauthentication(for: .resultSave) {
                    store.send(.requestChangeTapped)
                }
            }
            store.send(.authRetryHandled)
        }
    }

    private func sectionCard<Content: View>(title: String, spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(AppTypography.heading(16, weight: .bold))
            content()
        }
        .padding(14)
        .appPanel(background: AppPalette.bgCard, radius: 12)
    }

    private func resultStatusBanner(_ phase: MatchResultFeature.State.ResultPhase) -> some View {
        HStack(spacing: 10) {
            Image(systemName: phase == .disputed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(statusTint(phase))
            VStack(alignment: .leading, spacing: 2) {
                Text("기록 상태")
                    .font(AppTypography.body(11, weight: .semibold))
                    .foregroundStyle(AppPalette.textMuted)
                Text(title(for: phase))
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(statusTint(phase))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appPanel(background: statusTint(phase).opacity(0.14), radius: 10, stroke: statusTint(phase))
    }

    private func modeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.body(13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : AppPalette.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isSelected ? AppPalette.accentBlue : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func teamSelectButton(title: String, icon: String?, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.body(14, weight: .bold))
            }
            .foregroundStyle(isSelected ? Color.white : AppPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? tint : AppPalette.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white.opacity(0.25) : AppPalette.border, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func laneButton(_ title: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.body(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? (color == AppPalette.accentGold ? AppPalette.bgPrimary : Color.white) : AppPalette.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isSelected ? color : AppPalette.bgTertiary)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? .clear : AppPalette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func feelingButton(_ title: String, value: Int) -> some View {
        Button(title) {
            store.send(.balanceFeelingSelected(value))
        }
        .font(AppTypography.body(12, weight: store.balanceFeeling == value ? .semibold : .regular))
        .foregroundStyle(store.balanceFeeling == value ? (value == 5 ? AppPalette.bgPrimary : Color.white) : AppPalette.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(store.balanceFeeling == value ? (value == 5 ? AppPalette.accentGreen : AppPalette.bgTertiary) : AppPalette.bgTertiary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(store.balanceFeeling == value ? .clear : AppPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func numberField(
        _ placeholder: String,
        binding: Binding<String>,
        focusField: KDAFocusField
    ) -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 52)
            .focused($focusedField, equals: focusField)
    }

    private func selectMode(_ mode: MatchResultFeature.State.Mode) {
        focusedField = nil
        store.send(.modeSelected(mode))
    }

    private func title(for phase: MatchResultFeature.State.ResultPhase) -> String {
        switch phase {
        case .draft: return "초안"
        case .partial: return ResultStatus.partial.title
        case .confirmed: return ResultStatus.confirmed.title
        case .disputed: return ResultStatus.disputed.title
        }
    }

    private func statusTint(_ phase: MatchResultFeature.State.ResultPhase) -> Color {
        switch phase {
        case .draft, .partial:
            return AppPalette.accentGreen
        case .confirmed:
            return AppPalette.accentBlue
        case .disputed:
            return AppPalette.accentRed
        }
    }
}
