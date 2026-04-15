import ComposableArchitecture
import SwiftUI

@Reducer
struct ManualAdjustFeature {
    @ObservableState
    struct State: Equatable {
        let matchID: String
        var blueRows: [ManualAdjustRow]
        var redRows: [ManualAdjustRow]
        var actionState: AsyncActionState = .idle

        init(matchID: String, draft: ManualAdjustDraft) {
            self.matchID = matchID
            self.blueRows = draft.blueRows
            self.redRows = draft.redRows
        }

        var blueTotal: Int { blueRows.map(\.score).reduce(0, +) }
        var redTotal: Int { redRows.map(\.score).reduce(0, +) }

        var balanceText: String {
            let total = max(blueTotal + redTotal, 1)
            let blue = Int((Double(blueTotal) / Double(total) * 100).rounded())
            let red = max(0, 100 - blue)
            return "블루 \(blue) : \(red) 레드"
        }

        var warningMessages: [String] {
            var items: [String] = []
            if blueTotal != redTotal {
                let pointGap = abs(blueTotal - redTotal)
                items.append("총합 밸런스 \(blueTotal > redTotal ? "블루 우세" : "레드 우세") (\(pointGap)점 차)")
            }
            if let biggestGap = laneGapWarning {
                items.append(biggestGap)
            }
            let offRoleCount = (blueRows + redRows).filter(\.isOffRole).count
            if offRoleCount > 0 {
                items.append("오프포지션 \(offRoleCount)명 발생")
            }
            return items
        }

        private var laneGapWarning: String? {
            let pairs = Dictionary(uniqueKeysWithValues: blueRows.map { ($0.role, $0.score) })
            let redPairs = Dictionary(uniqueKeysWithValues: redRows.map { ($0.role, $0.score) })
            let gaps = Position.allCases.compactMap { role -> (Position, Int, Int, Int)? in
                guard let left = pairs[role], let right = redPairs[role] else { return nil }
                return (role, left, right, abs(left - right))
            }
            guard let largest = gaps.max(by: { $0.3 < $1.3 }), largest.3 >= 8 else { return nil }
            return "\(largest.0.shortLabel) 라인 격차 큼 (\(largest.1) vs \(largest.2))"
        }
    }

    enum Action: Equatable {
        case swapTapped(ManualAdjustRow)
        case saveTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .swapTapped(row):
                if let index = state.blueRows.firstIndex(of: row), let target = state.redRows.first(where: { $0.role == row.role }) {
                    state.blueRows[index] = target
                    if let redIndex = state.redRows.firstIndex(of: target) {
                        state.redRows[redIndex] = row
                    }
                } else if let index = state.redRows.firstIndex(of: row), let target = state.blueRows.first(where: { $0.role == row.role }) {
                    state.redRows[index] = target
                    if let blueIndex = state.blueRows.firstIndex(of: target) {
                        state.blueRows[blueIndex] = row
                    }
                }
                return .none

            case .saveTapped:
                // TODO: InhouseMakerCoreServer에 수동 팀 조정 저장 endpoint가 생기면
                // 여기서 local-only 성공 메시지를 서버 저장 effect로 교체.
                state.actionState = .success("서버 저장 API가 없어 현재 단계에서는 로컬 상태로만 반영됩니다.")
                return .none
            }
        }
    }
}

struct ManualAdjustFeatureView: View {
    @Bindable var store: StoreOf<ManualAdjustFeature>
    let onBack: () -> Void

    var body: some View {
        screenScaffold(title: "수동 팀 조정", onBack: onBack) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppPalette.accentOrange)
                            Text("밸런스 경고")
                                .font(AppTypography.body(12, weight: .semibold))
                                .foregroundStyle(AppPalette.accentOrange)
                        }
                        ForEach(store.warningMessages.isEmpty ? ["현재 큰 경고가 없습니다."] : store.warningMessages, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appPanel(background: Color(hex: 0x2A1A0A), radius: 10, stroke: AppPalette.accentOrange)

                    VStack(spacing: 6) {
                        Text(store.balanceText)
                            .font(AppTypography.heading(22, weight: .heavy))
                            .foregroundStyle(AppPalette.teamBlue)

                        Text("플레이어를 탭하면 같은 라인의 반대 팀 선수와 즉시 교체합니다")
                            .font(AppTypography.body(11))
                            .foregroundStyle(AppPalette.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

                    HStack(spacing: 8) {
                        manualColumn(title: "블루 팀", tint: AppPalette.teamBlue, rows: store.blueRows)
                        manualColumn(title: "레드 팀", tint: AppPalette.teamRed, rows: store.redRows)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accentPurple)
                            .frame(width: 24, height: 24)
                            .background(AppPalette.accentPurple.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("스왑 안내")
                                .font(AppTypography.body(12, weight: .semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                            Text("동일 라인 기준 즉시 스왑만 지원합니다. 서버 저장 API가 없어 현재는 로컬 상태로만 유지됩니다.")
                                .font(AppTypography.body(11))
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                    }
                    .padding(14)
                    .appPanel(background: AppPalette.bgCard, radius: 10)
                }
                .padding(16)
            }

            VStack(spacing: 8) {
                Button("변경 저장") {
                    store.send(.saveTapped)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("자동 밸런스 복귀") {
                    onBack()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppPalette.bgSecondary)
        }
        .overlay(alignment: Alignment.bottom) { actionBanner(store.actionState) }
    }

    private func manualColumn(title: String, tint: Color, rows: [ManualAdjustRow]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(AppTypography.heading(12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(tint)

            VStack(spacing: 1) {
                ForEach(rows) { row in
                    Button {
                        store.send(.swapTapped(row))
                    } label: {
                        HStack(spacing: 4) {
                            Text(row.role.shortLabel)
                                .font(AppTypography.body(9, weight: .bold))
                                .foregroundStyle(tint)
                                .frame(width: 26, alignment: .leading)
                            HStack(spacing: 4) {
                                Text(row.name)
                                    .font(AppTypography.body(10, weight: .semibold))
                                    .foregroundStyle(row.isOffRole ? AppPalette.accentGold : AppPalette.textPrimary)
                                if row.isOffRole {
                                    Text("OFF")
                                        .font(AppTypography.body(7, weight: .bold))
                                        .foregroundStyle(AppPalette.bgPrimary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(AppPalette.accentOrange)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            Spacer()
                            Text("\(row.score)")
                                .font(AppTypography.heading(11, weight: .bold))
                                .foregroundStyle(row.isOffRole ? AppPalette.accentGold : tint)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(row.isOffRole ? tint.opacity(0.14) : (title.contains("블루") ? Color(hex: 0x0D1B2A) : Color(hex: 0x2A0D0D)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
