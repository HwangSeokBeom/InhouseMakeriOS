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
    case homeUpcomingMatches
    case homeGroups
    case powerDetail
    case homeRecentMatches
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

enum RiotSyncStatus: String, Codable, Hashable {
    case idle = "IDLE"
    case queued = "QUEUED"
    case running = "RUNNING"
    case partial = "PARTIAL"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case retryScheduled = "RETRY_SCHEDULED"

    var isInFlight: Bool {
        switch self {
        case .queued, .running, .retryScheduled:
            return true
        case .idle, .partial, .succeeded, .failed:
            return false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawStatus = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch rawStatus {
        case Self.idle.rawValue:
            self = .idle
        case Self.queued.rawValue:
            self = .queued
        case Self.running.rawValue, "SYNCING":
            self = .running
        case Self.partial.rawValue:
            self = .partial
        case Self.succeeded.rawValue:
            self = .succeeded
        case Self.failed.rawValue:
            self = .failed
        case Self.retryScheduled.rawValue:
            self = .retryScheduled
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported RiotSyncStatus value: \(rawStatus)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RiotSyncUIState: Equatable {
    case pending
    case syncing
    case success
    case accountNotFound
    case invalidInput
    case serverConfiguration
    case failure

    var title: String {
        switch self {
        case .pending:
            return "동기화 대기"
        case .syncing:
            return "동기화 중"
        case .success:
            return "동기화 성공"
        case .accountNotFound:
            return "계정을 찾을 수 없음"
        case .invalidInput:
            return "입력 형식 오류"
        case .serverConfiguration:
            return "서버 설정 문제"
        case .failure:
            return "동기화 실패"
        }
    }

    var summary: String {
        switch self {
        case .pending:
            return "Sync 버튼을 누르면 Riot 전적 동기화 요청을 보낼 수 있습니다."
        case .syncing:
            return "Riot API에서 최신 전적을 확인하고 있습니다."
        case .success:
            return "가장 최근 동기화가 정상적으로 완료되었습니다."
        case .accountNotFound:
            return "게임 이름과 태그라인이 현재 Riot ID와 일치하는지 확인해 주세요."
        case .invalidInput:
            return "Riot ID 형식이 잘못되었거나 요청 값이 유효하지 않습니다."
        case .serverConfiguration:
            return "Riot API 인증 또는 서버 설정을 확인해야 합니다."
        case .failure:
            return "동기화 처리 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    var isFailure: Bool {
        switch self {
        case .accountNotFound, .invalidInput, .serverConfiguration, .failure:
            return true
        case .pending, .syncing, .success:
            return false
        }
    }
}

enum ServerContractErrorCode: Equatable {
    case riotAccountAlreadyAddedByThisUser
    case riotAccountAddUnavailable
    case socialTokenInvalid
    case accountExistsWithApple
    case accountExistsWithGoogle
    case authProviderMismatch
    case accountNotFound
    case unsupportedProvider
    case emailAlreadyExists
    case nicknameAlreadyExists
    case invalidEmailFormat
    case weakPassword
    case requiredTermsNotAgreed
    case invalidPayload
    case internalServerError
    case invalidCredentials
    case emailAuthDisabled
    case passwordAuthDisabled
    case authRequired
    case forbiddenFeature
    case rateLimited
    case unknown(String?)

    private static func normalizedToken(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased() ?? ""
    }

    static func resolve(code: String?, details: [String: JSONValue]?, statusCode: Int?) -> Self {
        let normalizedTokens = [
            normalizedToken(code),
            normalizedToken(details?["reason"]?.stringValue),
        ].filter { !$0.isEmpty }

        func contains(_ token: String) -> Bool {
            normalizedTokens.contains { $0.contains(token) }
        }

        switch true {
        case contains("ALREADY_ADDED_BY_THIS_USER"), contains("ALREADY_LINKED_TO_THIS_USER"):
            return .riotAccountAlreadyAddedByThisUser
        case contains("ALREADY_LINKED_TO_ANOTHER_USER"), contains("ALREADY_ADDED_BY_ANOTHER_USER"):
            return .riotAccountAddUnavailable
        case contains("SOCIAL_TOKEN_INVALID"):
            return .socialTokenInvalid
        case contains("ACCOUNT_EXISTS_WITH_APPLE"):
            return .accountExistsWithApple
        case contains("ACCOUNT_EXISTS_WITH_GOOGLE"):
            return .accountExistsWithGoogle
        case contains("AUTH_PROVIDER_MISMATCH"):
            return .authProviderMismatch
        case contains("ACCOUNT_NOT_FOUND"), contains("USER_NOT_FOUND"), contains("EMAIL_NOT_FOUND"):
            return .accountNotFound
        case contains("UNSUPPORTED_PROVIDER"), contains("UNSUPPORTED_AUTH_PROVIDER"), contains("UNSUPPORTED_LOGIN_METHOD"):
            return .unsupportedProvider
        case contains("EMAIL_ALREADY_IN_USE"), contains("EMAIL_ALREADY_EXISTS"), contains("EMAIL_DUPLICATE"), contains("DUPLICATE_EMAIL"), contains("ACCOUNT_EXISTS_WITH_EMAIL"):
            return .emailAlreadyExists
        case contains("NICKNAME_ALREADY_IN_USE"), contains("NICKNAME_ALREADY_EXISTS"), contains("NICKNAME_DUPLICATE"), contains("DUPLICATE_NICKNAME"), contains("NICKNAME_TAKEN"):
            return .nicknameAlreadyExists
        case contains("INVALID_EMAIL_FORMAT"):
            return .invalidEmailFormat
        case contains("WEAK_PASSWORD"):
            return .weakPassword
        case contains("REQUIRED_TERMS_NOT_AGREED"):
            return .requiredTermsNotAgreed
        case contains("INVALID_PAYLOAD"):
            return .invalidPayload
        case contains("INTERNAL_SERVER_ERROR"):
            return .internalServerError
        case contains("INVALID_CREDENTIALS"):
            return .invalidCredentials
        case contains("EMAIL_AUTH_DISABLED"):
            return .emailAuthDisabled
        case contains("PASSWORD_AUTH_DISABLED"):
            return .passwordAuthDisabled
        case contains("AUTH_REQUIRED"):
            return .authRequired
        case contains("FORBIDDEN_FEATURE"):
            return .forbiddenFeature
        case contains("RATE_LIMITED"):
            return .rateLimited
        default:
            if statusCode == 429 {
                return .rateLimited
            }
            return .unknown(code ?? details?["reason"]?.stringValue)
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
        ServerContractErrorCode.resolve(code: code, details: details, statusCode: statusCode)
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
        case .riotAccountAlreadyAddedByThisUser:
            return UserFacingError(
                title: "이미 추가한 Riot ID예요",
                message: "같은 Riot ID를 내 목록에 두 번 추가할 수는 없어요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .riotAccountAddUnavailable:
            return UserFacingError(
                title: "Riot ID를 추가하지 못했어요",
                message: "요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .authRequired:
            return UserFacingError(
                title: "로그인이 필요해요",
                message: "이 기능은 로그인 후 사용할 수 있어요. 이메일, Apple 또는 Google로 로그인해 주세요.",
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
        case .accountNotFound:
            return UserFacingError(
                title: "존재하지 않는 계정이에요",
                message: "가입한 이메일인지 다시 확인해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .unsupportedProvider:
            return UserFacingError(
                title: "지원하지 않는 로그인 방식이에요",
                message: "이 앱에서는 이메일, Apple, Google 로그인을 사용할 수 있어요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .emailAlreadyExists:
            return UserFacingError(
                title: "이미 가입된 이메일이에요",
                message: "다른 이메일을 사용하거나 로그인으로 계속해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .nicknameAlreadyExists:
            return UserFacingError(
                title: "이미 사용 중인 닉네임이에요",
                message: "다른 닉네임으로 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .invalidEmailFormat:
            return UserFacingError(
                title: "이메일 형식을 확인해 주세요",
                message: "올바른 이메일 형식으로 다시 입력해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .weakPassword:
            return UserFacingError(
                title: "비밀번호를 다시 확인해 주세요",
                message: "비밀번호 조건을 만족하도록 다시 입력해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .requiredTermsNotAgreed:
            return UserFacingError(
                title: "필수 약관 동의가 필요해요",
                message: "서비스 이용약관과 개인정보 처리방침에 동의해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .invalidPayload:
            return UserFacingError(
                title: "입력값을 다시 확인해 주세요",
                message: "입력한 회원가입 정보를 다시 확인한 뒤 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .internalServerError:
            return UserFacingError(
                title: "서버에 잠시 문제가 있어요",
                message: "잠시 후 다시 시도해 주세요.",
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
        case .emailAuthDisabled:
            return UserFacingError(
                title: "이메일 회원가입을 사용할 수 없어요",
                message: "현재 이메일 회원가입이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요.",
                code: self.code,
                provider: provider,
                statusCode: statusCode,
                details: details
            )
        case .passwordAuthDisabled:
            return UserFacingError(
                title: "이메일 로그인을 사용할 수 없어요",
                message: "현재 이메일 로그인이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요.",
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

    static func authRequiredFallback(message: String = "세션이 만료되어 다시 로그인이 필요해요. 이메일, Apple 또는 Google로 다시 로그인해 주세요.") -> UserFacingError {
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
    let provider: AuthProvider?
    let status: AuthenticatedUserStatus?

    init(
        id: String,
        email: String,
        nickname: String,
        provider: AuthProvider? = nil,
        status: AuthenticatedUserStatus? = nil
    ) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.provider = provider
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case nickname
        case provider
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        nickname = try container.decode(String.self, forKey: .nickname)
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider)
        status = try container.decodeIfPresent(AuthenticatedUserStatus.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

struct AuthTokens: Codable, Hashable {
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
}

enum AuthenticatedUserStatus: String, Codable, Hashable {
    case active = "ACTIVE"
    case suspended = "SUSPENDED"
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
    let syncStatus: RiotSyncStatus
    let lastSyncRequestedAt: Date?
    let lastSyncSucceededAt: Date?
    let lastSyncFailedAt: Date?
    let lastSyncErrorCode: String?
    let lastSyncErrorMessage: String?
    let lastSyncedAt: Date?

    var displayName: String {
        "\(riotGameName)#\(tagLine)"
    }

    var syncUIState: RiotSyncUIState {
        switch syncStatus {
        case .idle, .queued, .retryScheduled:
            return .pending
        case .running:
            return .syncing
        case .partial, .succeeded:
            return .success
        case .failed:
            switch normalizedSyncErrorCode {
            case "RIOT_RESOURCE_NOT_FOUND":
                return .accountNotFound
            case "RIOT_CLIENT_ERROR", "INVALID_PAYLOAD":
                return .invalidInput
            case "RIOT_AUTH_FAILED":
                return .serverConfiguration
            default:
                return .failure
            }
        }
    }

    var syncStatusSummary: String {
        if syncUIState.isFailure, let lastSyncErrorMessage, !lastSyncErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lastSyncErrorMessage
        }
        return syncUIState.summary
    }

    var syncStatusTimestamp: Date? {
        switch syncUIState {
        case .success:
            return lastSyncSucceededAt ?? lastSyncedAt
        case .accountNotFound, .invalidInput, .serverConfiguration, .failure:
            return lastSyncFailedAt
        case .syncing:
            return lastSyncRequestedAt
        case .pending:
            return lastSyncRequestedAt ?? lastSyncedAt
        }
    }

    var normalizedSyncErrorCode: String {
        lastSyncErrorCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased() ?? ""
    }

    func withPrimary(_ isPrimary: Bool) -> RiotAccount {
        RiotAccount(
            id: id,
            riotGameName: riotGameName,
            tagLine: tagLine,
            region: region,
            puuid: puuid,
            isPrimary: isPrimary,
            verificationStatus: verificationStatus,
            syncStatus: syncStatus,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage,
            lastSyncedAt: lastSyncedAt
        )
    }

    func withSyncAccepted(_ accepted: RiotAccountSyncAccepted, requestedAt: Date) -> RiotAccount {
        RiotAccount(
            id: id,
            riotGameName: riotGameName,
            tagLine: tagLine,
            region: region,
            puuid: puuid,
            isPrimary: isPrimary,
            verificationStatus: verificationStatus,
            syncStatus: accepted.syncStatus,
            lastSyncRequestedAt: requestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: accepted.syncStatus == .failed ? lastSyncErrorCode : nil,
            lastSyncErrorMessage: accepted.syncStatus == .failed ? lastSyncErrorMessage : nil,
            lastSyncedAt: lastSyncedAt
        )
    }

    func withSyncStatus(_ status: RiotAccountSyncState) -> RiotAccount {
        RiotAccount(
            id: id,
            riotGameName: riotGameName,
            tagLine: tagLine,
            region: region,
            puuid: puuid,
            isPrimary: isPrimary,
            verificationStatus: verificationStatus,
            syncStatus: status.syncStatus,
            lastSyncRequestedAt: status.lastSyncRequestedAt,
            lastSyncSucceededAt: status.lastSyncSucceededAt,
            lastSyncFailedAt: status.lastSyncFailedAt,
            lastSyncErrorCode: status.lastSyncErrorCode,
            lastSyncErrorMessage: status.lastSyncErrorMessage,
            lastSyncedAt: status.lastSyncSucceededAt ?? lastSyncedAt
        )
    }
}

enum RiotLinkedAccountsViewState: Equatable {
    case loading
    case noLinkedAccounts
    case loaded([RiotAccount])
    case error(UserFacingError)

    init(accounts: [RiotAccount]) {
        self = accounts.isEmpty ? .noLinkedAccounts : .loaded(accounts)
    }

    var accounts: [RiotAccount] {
        switch self {
        case let .loaded(accounts):
            return accounts
        case .loading, .noLinkedAccounts, .error:
            return []
        }
    }

    var hasLinkedAccounts: Bool {
        switch self {
        case let .loaded(accounts):
            return accounts.isEmpty == false
        case .loading, .noLinkedAccounts, .error:
            return false
        }
    }

    var primaryAccount: RiotAccount? {
        let accounts = accounts
        return accounts.first(where: \.isPrimary) ?? accounts.first
    }
}

struct RiotAccountSyncAccepted: Codable, Hashable {
    let riotAccountId: String
    let queued: Bool
    let syncStatus: RiotSyncStatus
}

struct RiotAccountSyncState: Codable, Hashable {
    let riotAccountId: String
    let syncStatus: RiotSyncStatus
    let lastSyncRequestedAt: Date?
    let lastSyncSucceededAt: Date?
    let lastSyncFailedAt: Date?
    let lastSyncErrorCode: String?
    let lastSyncErrorMessage: String?
}

enum RiotAccountInputValidator {
    static let region = "kr"
    static let gameNameMaxLength = 32
    static let tagLineMinLength = 2
    static let tagLineMaxLength = 8

    static func normalizedGameName(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTagLine(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }

    static func validateGameName(_ rawValue: String) -> FieldValidationState {
        let normalizedValue = normalizedGameName(rawValue)
        guard !normalizedValue.isEmpty else {
            return .invalid("게임 이름을 입력해 주세요")
        }
        guard !normalizedValue.contains("#") else {
            return .invalid("게임 이름과 태그라인을 나눠 입력해 주세요")
        }
        guard normalizedValue.count <= gameNameMaxLength else {
            return .invalid("게임 이름은 32자 이하로 입력해 주세요")
        }
        return .valid("예: Hide on bush")
    }

    static func validateTagLine(_ rawValue: String) -> FieldValidationState {
        let normalizedValue = normalizedTagLine(rawValue)
        guard !normalizedValue.isEmpty else {
            return .invalid("태그라인을 입력해 주세요")
        }
        guard !rawValue.contains("#") else {
            return .invalid("# 없이 KR1만 입력해 주세요")
        }
        guard normalizedValue.count >= tagLineMinLength && normalizedValue.count <= tagLineMaxLength else {
            return .invalid("태그라인은 2자 이상 8자 이하로 입력해 주세요")
        }
        return .valid("예: KR1, KOR")
    }
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
    let riotAccountsViewState: RiotLinkedAccountsViewState
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
    let powerProfiles: [String: PowerProfile]
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
    let riotAccountsViewState: RiotLinkedAccountsViewState
    let power: PowerProfile?
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
