import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case home
    case match
    case recruit
    case history
    case profile

    var title: String {
        switch self {
        case .home: return "홈"
        case .match: return "내전"
        case .recruit: return "모집"
        case .history: return "기록"
        case .profile: return "프로필"
        }
    }
}

enum AppRoute: Hashable {
    case notifications
    case riotAccounts
    case settings
    case groupDetail(String)
    case matchLobby(groupID: String, matchID: String)
    case teamBalance(groupID: String, matchID: String)
    case teamBalancePreview
    case manualAdjust(matchID: String, draft: ManualAdjustDraft)
    case matchResult(matchID: String)
    case resultPreview
    case matchDetail(matchID: String)
    case recruitDetail(postID: String)
}

enum ScreenLoadState<Value> {
    case initial
    case loading
    case refreshing(Value)
    case content(Value)
    case empty(String)
    case error(UserFacingError)

    var value: Value? {
        switch self {
        case let .refreshing(value), let .content(value):
            return value
        case .initial, .loading, .empty, .error:
            return nil
        }
    }
}

extension ScreenLoadState: Equatable where Value: Equatable {
    static func == (lhs: ScreenLoadState<Value>, rhs: ScreenLoadState<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial), (.loading, .loading):
            return true
        case let (.refreshing(left), .refreshing(right)):
            return left == right
        case let (.content(left), .content(right)):
            return left == right
        case let (.empty(left), .empty(right)):
            return left == right
        case let (.error(left), .error(right)):
            return left == right
        default:
            return false
        }
    }
}

enum AsyncActionState: Equatable {
    case idle
    case inProgress(String)
    case success(String)
    case failure(String)
}

enum ServerContractErrorCode: Equatable {
    case socialTokenInvalid
    case accountExistsWithApple
    case accountExistsWithGoogle
    case authProviderMismatch
    case invalidCredentials
    case emailAuthDisabled
    case passwordAuthDisabled
    case authRequired
    case forbiddenFeature
    case rateLimited
    case unknown(String?)

    static func resolve(code: String?, statusCode: Int?) -> Self {
        let normalizedCode = code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased() ?? ""

        switch normalizedCode {
        case let code where code.contains("SOCIAL_TOKEN_INVALID"):
            return .socialTokenInvalid
        case let code where code.contains("ACCOUNT_EXISTS_WITH_APPLE"):
            return .accountExistsWithApple
        case let code where code.contains("ACCOUNT_EXISTS_WITH_GOOGLE"):
            return .accountExistsWithGoogle
        case let code where code.contains("AUTH_PROVIDER_MISMATCH"):
            return .authProviderMismatch
        case let code where code.contains("INVALID_CREDENTIALS"):
            return .invalidCredentials
        case let code where code.contains("EMAIL_AUTH_DISABLED"):
            return .emailAuthDisabled
        case let code where code.contains("PASSWORD_AUTH_DISABLED"):
            return .passwordAuthDisabled
        case let code where code.contains("AUTH_REQUIRED"):
            return .authRequired
        case let code where code.contains("FORBIDDEN_FEATURE"):
            return .forbiddenFeature
        case let code where code.contains("RATE_LIMITED"):
            return .rateLimited
        default:
            if statusCode == 429 {
                return .rateLimited
            }
            return .unknown(code)
        }
    }
}

struct UserFacingError: Error, Equatable {
    let title: String
    let message: String
    var code: String?
    var provider: String?
    var statusCode: Int?
    var details: [String: JSONValue]?

    init(
        title: String,
        message: String,
        code: String? = nil,
        provider: String? = nil,
        statusCode: Int? = nil,
        details: [String: JSONValue]? = nil
    ) {
        self.title = title
        self.message = message
        self.code = code
        self.provider = provider
        self.statusCode = statusCode
        self.details = details
    }
}

extension UserFacingError {
    var serverContractCode: ServerContractErrorCode {
        ServerContractErrorCode.resolve(code: code, statusCode: statusCode)
    }

    var normalizedCode: String {
        code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased() ?? ""
    }

    var requiresAuthentication: Bool {
        serverContractCode == .authRequired
    }

    var isForbiddenFeature: Bool {
        serverContractCode == .forbiddenFeature
    }

    var isRateLimited: Bool {
        serverContractCode == .rateLimited
    }

    var serverContractMapped: UserFacingError {
        switch serverContractCode {
        case .authRequired:
            return UserFacingError(
                title: "로그인이 필요해요",
                message: "이 기능은 로그인 후 사용할 수 있어요. Apple 또는 Google로 로그인해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .forbiddenFeature:
            return UserFacingError(
                title: "권한이 없어요",
                message: "이 기능에 대한 권한이 없습니다.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .socialTokenInvalid:
            return UserFacingError(
                title: "소셜 로그인 실패",
                message: "소셜 로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .accountExistsWithApple:
            return UserFacingError(
                title: "로그인 방법 안내",
                message: "이 계정은 Apple 로그인으로 이용할 수 있어요. Apple로 계속해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .accountExistsWithGoogle:
            return UserFacingError(
                title: "로그인 방법 안내",
                message: "이 계정은 Google 로그인으로 이용할 수 있어요. Google로 계속해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .authProviderMismatch:
            return UserFacingError(
                title: "로그인 방법 안내",
                message: "이 계정은 다른 로그인 방식으로 연결되어 있어요. 올바른 로그인 방식으로 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .invalidCredentials:
            return UserFacingError(
                title: "로그인 정보를 다시 확인해 주세요",
                message: "로그인에 실패했어요. 선택한 계정으로 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .emailAuthDisabled, .passwordAuthDisabled:
            return UserFacingError(
                title: "지원하지 않는 로그인 방식이에요",
                message: "이 앱에서는 Apple 또는 Google 로그인만 사용할 수 있어요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .rateLimited:
            return UserFacingError(
                title: "요청이 잠시 몰리고 있어요",
                message: "요청이 많아 잠시 후 다시 시도해 주세요.",
                code: self.code ?? "RATE_LIMITED",
                provider: provider,
                statusCode: statusCode ?? 429,
                details: details
            )
        case .unknown:
            return self
        }
    }

    static func authRequiredFallback(message: String = "세션이 만료되어 다시 로그인이 필요해요. Apple 또는 Google로 다시 로그인해 주세요.") -> UserFacingError {
        UserFacingError(
            title: "로그인이 필요해요",
            message: message,
            code: "AUTH_REQUIRED",
            statusCode: 401
        ).serverContractMapped
    }
}

struct AppleLoginAuthorization: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let userIdentifier: String
    let email: String?
    let givenName: String?
    let familyName: String?

    var nickname: String? {
        let fullName = [familyName, givenName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()

        if !fullName.isEmpty {
            return fullName
        }

        guard let email else { return nil }
        let emailPrefix = email.split(separator: "@").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return emailPrefix.isEmpty ? nil : emailPrefix
    }
}

struct GoogleLoginAuthorization: Equatable, Sendable {
    let idToken: String
    let accessToken: String?
    let email: String?
    let name: String?
}

enum Position: String, Codable, CaseIterable, Hashable {
    case top = "TOP"
    case jungle = "JUNGLE"
    case mid = "MID"
    case adc = "ADC"
    case support = "SUPPORT"
    case fill = "FILL"

    var shortLabel: String {
        switch self {
        case .top: return "TOP"
        case .jungle: return "JGL"
        case .mid: return "MID"
        case .adc: return "ADC"
        case .support: return "SUP"
        case .fill: return "FILL"
        }
    }

    static let duoLane: [Position] = [.adc, .support]
}

enum MatchStatus: String, Codable, Hashable {
    case draft = "DRAFT"
    case recruiting = "RECRUITING"
    case locked = "LOCKED"
    case balanced = "BALANCED"
    case inProgress = "IN_PROGRESS"
    case resultPending = "RESULT_PENDING"
    case confirmed = "CONFIRMED"
    case disputed = "DISPUTED"
    case closed = "CLOSED"
}

enum TeamSide: String, Codable, Hashable {
    case blue = "A"
    case red = "B"

    var title: String {
        switch self {
        case .blue: return "블루"
        case .red: return "레드"
        }
    }

    var opposite: TeamSide {
        switch self {
        case .blue: return .red
        case .red: return .blue
        }
    }
}

enum ResultStatus: String, Codable, Hashable {
    case partial = "PARTIAL"
    case confirmed = "CONFIRMED"
    case disputed = "DISPUTED"

    var title: String {
        switch self {
        case .partial: return "임시 기록"
        case .confirmed: return "확인됨"
        case .disputed: return "이의 제기"
        }
    }
}

enum InputMode: String, Codable, Hashable {
    case quick = "QUICK"
    case detailed = "DETAILED"
}

enum BalanceMode: String, Codable, CaseIterable, Hashable {
    case balanced = "BALANCED"
    case positionFirst = "POSITION_FIRST"
    case skillFirst = "SKILL_FIRST"

    var title: String {
        switch self {
        case .balanced: return "균형형"
        case .positionFirst: return "포지션 우선"
        case .skillFirst: return "실력 우선"
        }
    }

    var designBadgeTitle: String {
        switch self {
        case .balanced: return "균형형 추천"
        case .positionFirst: return "포지션 우선"
        case .skillFirst: return "실력 우선"
        }
    }
}

enum ParticipationStatus: String, Codable, Hashable {
    case invited = "INVITED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case lockedIn = "LOCKED_IN"
}

enum LaneResult: String, Codable, Hashable {
    case win = "WIN"
    case even = "EVEN"
    case lose = "LOSE"
    case unknown = "UNKNOWN"

    var displayTitle: String {
        switch self {
        case .win: return "승"
        case .even: return "비슷"
        case .lose: return "패"
        case .unknown: return "-"
        }
    }
}

enum ConfirmationAction: String, Codable, Hashable {
    case confirm = "CONFIRM"
    case suggestChange = "SUGGEST_CHANGE"
    case dispute = "DISPUTE"
}

enum GroupVisibility: String, Codable, Hashable {
    case `private` = "PRIVATE"
    case `public` = "PUBLIC"
}

enum JoinPolicy: String, Codable, Hashable, CaseIterable {
    case inviteOnly = "INVITE_ONLY"
    case approvalRequired = "APPROVAL_REQUIRED"
    case open = "OPEN"

    var title: String {
        switch self {
        case .inviteOnly: return "초대 전용"
        case .approvalRequired: return "승인 필요"
        case .open: return "공개"
        }
    }
}

enum GroupRole: String, Codable, Hashable {
    case owner = "OWNER"
    case admin = "ADMIN"
    case member = "MEMBER"
}

enum VerificationStatus: String, Codable, Hashable {
    case claimed = "CLAIMED"
    case groupVerified = "GROUP_VERIFIED"
    case adminVerified = "ADMIN_VERIFIED"

    var title: String {
        switch self {
        case .claimed: return "참고"
        case .groupVerified: return "그룹 검증"
        case .adminVerified: return "관리자 검증"
        }
    }
}

enum RecruitingPostType: String, Codable, Hashable, CaseIterable {
    case memberRecruit = "MEMBER_RECRUIT"
    case opponentRecruit = "OPPONENT_RECRUIT"

    var title: String {
        switch self {
        case .memberRecruit: return "팀원 모집"
        case .opponentRecruit: return "상대팀 모집"
        }
    }
}

enum RecruitingPostStatus: String, Codable, Hashable {
    case open = "OPEN"
    case closed = "CLOSED"
    case cancelled = "CANCELLED"
}

struct AuthUser: Codable, Hashable {
    let id: String
    let email: String
    let nickname: String
}

struct AuthTokens: Codable, Hashable {
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
}

struct UserSession: Equatable {
    let authTokens: AuthTokens
    var user: UserProfile
}

struct UserProfile: Codable, Hashable {
    let id: String
    let email: String
    var nickname: String
    var primaryPosition: Position?
    var secondaryPosition: Position?
    var isFillAvailable: Bool
    var styleTags: [String]
    let mannerScore: Double
    let noshowCount: Int
}

struct PowerProfile: Codable, Hashable {
    let userID: String
    let overallPower: Double
    let lanePower: [Position: Double]
    let stability: Double
    let carry: Double
    let teamContribution: Double
    let laneInfluence: Double
    let basePower: Double
    let formScore: Double
    let inhouseMMR: Double
    let inhouseConfidence: Double
    let version: String
    let calculatedAt: Date
}

struct RiotAccount: Codable, Hashable, Identifiable {
    let id: String
    let riotGameName: String
    let tagLine: String
    let region: String
    let puuid: String
    let isPrimary: Bool
    let verificationStatus: VerificationStatus
    let lastSyncedAt: Date?
}

struct GroupSummary: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let visibility: GroupVisibility
    let joinPolicy: JoinPolicy
    let tags: [String]
    let ownerUserID: String
    let memberCount: Int
    let recentMatches: Int
}

struct GroupMember: Codable, Hashable, Identifiable {
    let id: String
    let userID: String
    let nickname: String
    let role: GroupRole
}

struct MatchPlayer: Codable, Hashable, Identifiable {
    let id: String
    let userID: String
    let nickname: String
    let teamSide: TeamSide?
    let assignedRole: Position?
    let participationStatus: ParticipationStatus
    let isCaptain: Bool
}

struct Match: Codable, Hashable, Identifiable {
    let id: String
    let groupID: String
    let status: MatchStatus
    let scheduledAt: Date?
    let balanceMode: BalanceMode?
    let selectedCandidateNo: Int?
    let players: [MatchPlayer]
    let candidates: [MatchCandidate]

    var acceptedCount: Int {
        players.filter { $0.participationStatus == .accepted || $0.participationStatus == .lockedIn }.count
    }
}

struct CandidateMetrics: Codable, Hashable {
    let teamPowerGap: Double
    let laneMatchupGap: Double
    let offRolePenalty: Double
    let repeatTeamPenalty: Double
    let preferenceViolationPenalty: Double
    let volatilityClusterPenalty: Double
}

struct CandidatePlayer: Codable, Hashable, Identifiable {
    var id: String { userID + assignedRole.rawValue + teamSide.rawValue }

    let userID: String
    let nickname: String
    let teamSide: TeamSide
    let assignedRole: Position
    let rolePower: Double
    let isOffRole: Bool
}

struct MatchCandidate: Codable, Hashable, Identifiable {
    let candidateID: String
    let candidateNo: Int
    let type: BalanceMode
    let score: Double
    let metrics: CandidateMetrics
    let teamAPower: Double
    let teamBPower: Double
    let offRoleCount: Int
    let explanationTags: [String]
    let teamA: [CandidatePlayer]
    let teamB: [CandidatePlayer]

    var id: String { candidateID }
}

struct MatchStat: Codable, Hashable {
    let userID: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let laneResult: LaneResult
}

struct ResultConfirmation: Codable, Hashable, Identifiable {
    var id: String { userID + createdAt.description }

    let userID: String
    let action: ConfirmationAction
    let diff: [String: String]
    let comment: String?
    let createdAt: Date
}

struct MatchResult: Codable, Hashable {
    let id: String
    let winningTeam: TeamSide?
    let resultStatus: ResultStatus
    let inputMode: InputMode
    let players: [MatchStat]
    let confirmations: [ResultConfirmation]
}

struct ResultSubmissionStatus: Codable, Hashable {
    let resultID: String
    let status: ResultStatus
    let confirmationNeeded: Int
}

struct MatchHistoryItem: Codable, Hashable, Identifiable {
    var id: String { matchID }

    let matchID: String
    let scheduledAt: Date
    let role: Position
    let teamSide: TeamSide
    let result: String
    let kda: String
    let deltaMMR: Double
}

struct RecruitPost: Codable, Hashable, Identifiable {
    let id: String
    let groupID: String
    let postType: RecruitingPostType
    let title: String
    let status: RecruitingPostStatus
    let scheduledAt: Date?
    let body: String?
    let tags: [String]
    let requiredPositions: [String]
    let createdBy: String?
}

struct NotificationEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    let createdAt: Date
    let isUnread: Bool
    let systemImageName: String
}

struct CachedResultMetadata: Codable, Hashable {
    let winningTeam: TeamSide
    let mvpUserID: String
    let balanceRating: Int
    let updatedAt: Date
}

struct RecentMatchContext: Codable, Hashable, Identifiable {
    var id: String { matchID }

    let matchID: String
    let groupID: String
    let groupName: String
    let createdAt: Date
}

struct LocalMatchRecord: Codable, Hashable, Identifiable {
    var id: String { matchID }

    let matchID: String
    let groupID: String?
    let groupName: String
    let savedAt: Date
    let winningTeam: TeamSide
    let balanceRating: Int
    let mvpUserID: String
}

struct PreviewRosterPlayer: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var preferredPosition: Position
    var score: Int

    init(id: UUID = UUID(), name: String, preferredPosition: Position, score: Int) {
        self.id = id
        self.name = name
        self.preferredPosition = preferredPosition
        self.score = score
    }

    var sanitizedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "플레이어" : trimmed
    }

    var clampedScore: Int {
        min(max(score, 40), 100)
    }
}

struct TeamBalancePreviewDraft: Codable, Hashable {
    var players: [PreviewRosterPlayer]
    var selectedMode: BalanceMode

    static let defaultValue = TeamBalancePreviewDraft(
        players: [
            PreviewRosterPlayer(name: "민수", preferredPosition: .top, score: 82),
            PreviewRosterPlayer(name: "준호", preferredPosition: .top, score: 78),
            PreviewRosterPlayer(name: "서준", preferredPosition: .jungle, score: 80),
            PreviewRosterPlayer(name: "현우", preferredPosition: .jungle, score: 76),
            PreviewRosterPlayer(name: "지훈", preferredPosition: .mid, score: 84),
            PreviewRosterPlayer(name: "도윤", preferredPosition: .mid, score: 79),
            PreviewRosterPlayer(name: "우진", preferredPosition: .adc, score: 81),
            PreviewRosterPlayer(name: "시우", preferredPosition: .adc, score: 77),
            PreviewRosterPlayer(name: "예준", preferredPosition: .support, score: 75),
            PreviewRosterPlayer(name: "하준", preferredPosition: .support, score: 74),
        ],
        selectedMode: .balanced
    )

    var sanitizedPlayers: [PreviewRosterPlayer] {
        players.map {
            PreviewRosterPlayer(
                id: $0.id,
                name: $0.sanitizedName,
                preferredPosition: $0.preferredPosition,
                score: $0.clampedScore
            )
        }
    }

    var isReady: Bool {
        sanitizedPlayers.count >= 10
    }

    func makePreviewResult() -> TeamBalancePreviewResult? {
        let roster = Array(sanitizedPlayers.prefix(10))
        guard roster.count == 10 else { return nil }

        var bluePlayers: [PreviewRosterPlayer] = []
        var redPlayers: [PreviewRosterPlayer] = []
        var blueTotal = 0
        var redTotal = 0

        func assign(_ player: PreviewRosterPlayer, preferLowerTotal: Bool = true) {
            let shouldUseBlue: Bool
            if preferLowerTotal {
                shouldUseBlue = bluePlayers.count >= 5 ? false : (redPlayers.count >= 5 || blueTotal <= redTotal)
            } else {
                shouldUseBlue = bluePlayers.count <= redPlayers.count
            }

            if shouldUseBlue {
                bluePlayers.append(player)
                blueTotal += player.clampedScore
            } else {
                redPlayers.append(player)
                redTotal += player.clampedScore
            }
        }

        switch selectedMode {
        case .skillFirst:
            for player in roster.sorted(by: { $0.clampedScore > $1.clampedScore }) {
                assign(player)
            }
        case .positionFirst:
            let ordered = roster.sorted {
                if $0.preferredPosition == $1.preferredPosition {
                    return $0.clampedScore > $1.clampedScore
                }
                return Self.positionOrder($0.preferredPosition) < Self.positionOrder($1.preferredPosition)
            }
            for player in ordered {
                assign(player, preferLowerTotal: false)
            }
        case .balanced:
            let grouped = Dictionary(grouping: roster, by: \.preferredPosition)
            for position in Self.orderedPositions {
                let players = (grouped[position] ?? []).sorted { $0.clampedScore > $1.clampedScore }
                for player in players {
                    assign(player)
                }
            }
        }

        return TeamBalancePreviewResult(
            bluePlayers: bluePlayers,
            redPlayers: redPlayers,
            blueTotal: blueTotal,
            redTotal: redTotal,
            mode: selectedMode
        )
    }

    private static let orderedPositions: [Position] = [.top, .jungle, .mid, .adc, .support, .fill]

    private static func positionOrder(_ position: Position) -> Int {
        orderedPositions.firstIndex(of: position) ?? orderedPositions.count
    }
}

struct TeamBalancePreviewResult: Equatable {
    let bluePlayers: [PreviewRosterPlayer]
    let redPlayers: [PreviewRosterPlayer]
    let blueTotal: Int
    let redTotal: Int
    let mode: BalanceMode

    var headline: String {
        let gap = abs(blueTotal - redTotal)
        return gap <= 4 ? "접전 예상" : (blueTotal > redTotal ? "블루 우세" : "레드 우세")
    }
}

struct ResultPreviewValidation: Equatable {
    let isValid: Bool
    let message: String
}

struct ResultPreviewPlayer: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var teamSide: TeamSide
    var role: Position

    init(id: UUID = UUID(), name: String, teamSide: TeamSide, role: Position) {
        self.id = id
        self.name = name
        self.teamSide = teamSide
        self.role = role
    }
}

struct ResultPreviewDraft: Codable, Hashable {
    var players: [ResultPreviewPlayer]
    var winningTeam: TeamSide
    var balanceRating: Int
    var selectedMVPPlayerID: UUID?

    static func defaultValue(from balanceDraft: TeamBalancePreviewDraft = .defaultValue) -> ResultPreviewDraft {
        let preview = balanceDraft.makePreviewResult()
        let bluePlayers = preview?.bluePlayers ?? Array(balanceDraft.sanitizedPlayers.prefix(5))
        let redPlayers = preview?.redPlayers ?? Array(balanceDraft.sanitizedPlayers.dropFirst(5).prefix(5))
        return defaultValue(bluePlayers: bluePlayers, redPlayers: redPlayers)
    }

    static func defaultValue(from previewResult: TeamBalancePreviewResult) -> ResultPreviewDraft {
        defaultValue(bluePlayers: previewResult.bluePlayers, redPlayers: previewResult.redPlayers)
    }

    private static func defaultValue(bluePlayers: [PreviewRosterPlayer], redPlayers: [PreviewRosterPlayer]) -> ResultPreviewDraft {
        let players = bluePlayers.map {
            ResultPreviewPlayer(name: $0.sanitizedName, teamSide: .blue, role: $0.preferredPosition)
        } + redPlayers.map {
            ResultPreviewPlayer(name: $0.sanitizedName, teamSide: .red, role: $0.preferredPosition)
        }

        return ResultPreviewDraft(
            players: players,
            winningTeam: .blue,
            balanceRating: 5,
            selectedMVPPlayerID: players.first(where: { $0.teamSide == .blue })?.id
        )
    }

    var mvpCandidates: [ResultPreviewPlayer] {
        players.filter { $0.teamSide == winningTeam }
    }

    var sanitizedPlayers: [ResultPreviewPlayer] {
        players.map { player in
            let trimmedName = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResultPreviewPlayer(
                id: player.id,
                name: trimmedName.isEmpty ? "플레이어" : trimmedName,
                teamSide: player.teamSide,
                role: player.role
            )
        }
    }

    var selectedMVPName: String? {
        guard let selectedMVPPlayerID else { return nil }
        return sanitizedPlayers.first(where: { $0.id == selectedMVPPlayerID })?.name
    }
}

struct HomeSnapshot: Equatable {
    let profile: UserProfile
    let power: PowerProfile?
    let groups: [GroupSummary]
    let currentMatch: Match?
    let latestHistory: MatchHistoryItem?
    let recruitingPosts: [RecruitPost]
}

struct GuestHomeSnapshot: Equatable {
    let groups: [GroupSummary]
    let currentMatch: Match?
    let latestLocalResult: LocalMatchRecord?
    let recruitingPosts: [RecruitPost]
}

enum HomeContentState: Equatable {
    case guest(GuestHomeSnapshot)
    case authenticated(HomeSnapshot)
}

struct GroupDetailSnapshot: Equatable {
    let group: GroupSummary
    let members: [GroupMember]
    let latestMatch: MatchHistoryItem?
}

struct MatchLobbySnapshot: Equatable {
    let match: Match
    let group: GroupSummary
    let members: [GroupMember]
    let powerProfiles: [String: PowerProfile]
}

struct TeamBalanceSnapshot: Equatable {
    let match: Match
    let candidates: [MatchCandidate]
}

struct ManualAdjustDraft: Hashable {
    let blueRows: [ManualAdjustRow]
    let redRows: [ManualAdjustRow]
}

struct ManualAdjustRow: Hashable, Identifiable {
    let id: String
    let userID: String
    let role: Position
    let name: String
    let score: Int
    let isOffRole: Bool
}

struct ProfileSnapshot: Equatable {
    let profile: UserProfile
    let power: PowerProfile?
    let riotAccounts: [RiotAccount]
    let history: [MatchHistoryItem]
}

struct GuestProfileSnapshot: Equatable {
    let localResults: [LocalMatchRecord]
    let trackedGroupCount: Int
    let notificationCount: Int
}

enum ProfileContentState: Equatable {
    case guest(GuestProfileSnapshot)
    case authenticated(ProfileSnapshot)
}

struct MatchDetailSnapshot: Equatable {
    let match: Match
    let result: MatchResult?
    let cachedMetadata: CachedResultMetadata?
}

struct RiotAccountSnapshot: Equatable {
    let accounts: [RiotAccount]
    let syncInProgressIDs: Set<String>
}

struct RecruitBoardSnapshot: Equatable {
    let selectedType: RecruitingPostType
    let posts: [RecruitPost]
}

enum HistoryContentState: Equatable {
    case guest([LocalMatchRecord])
    case authenticated([MatchHistoryItem])
}
