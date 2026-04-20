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
    case search
    case notifications
    case riotAccounts
    case settings
    case homeUpcomingMatches
    case homeGroups
    case powerDetail
    case memberProfile(userID: String, nickname: String)
    case homeRecentMatches
    case groupDetail(String)
    case matchLobby(groupID: String, matchID: String)
    case teamBalance(groupID: String, matchID: String)
    case manualAdjust(matchID: String, draft: ManualAdjustDraft)
    case matchResult(matchID: String)
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
    case userNotFound
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
    case groupAccessForbidden
    case groupMemberAlreadyExists
    case recruitingClosed
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
        case contains("ACCOUNT_NOT_FOUND"), contains("EMAIL_NOT_FOUND"):
            return .accountNotFound
        case contains("USER_NOT_FOUND"):
            return .userNotFound
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
        case contains("GROUP_ACCESS_FORBIDDEN"):
            return .groupAccessForbidden
        case contains("GROUP_MEMBER_ALREADY_EXISTS"):
            return .groupMemberAlreadyExists
        case contains("RECRUITING_CLOSED"):
            return .recruitingClosed
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
    var endpoint: String?
    var requestMethod: String?

    init(
        title: String,
        message: String,
        code: String? = nil,
        provider: String? = nil,
        statusCode: Int? = nil,
        details: [String: JSONValue]? = nil,
        endpoint: String? = nil,
        requestMethod: String? = nil
    ) {
        self.title = title
        self.message = message
        self.code = code
        self.provider = provider
        self.statusCode = statusCode
        self.details = details
        self.endpoint = endpoint
        self.requestMethod = requestMethod
    }
}

extension UserFacingError {
    fileprivate static func normalizeErrorToken(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased() ?? ""
    }

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

    var normalizedMessage: String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
    }

    fileprivate var normalizedDetailTokens: [String] {
        guard let details else { return [] }
        return details.values
            .map { Self.normalizeErrorToken($0.stringValue) }
            .filter { !$0.isEmpty }
    }

    fileprivate func containsNormalizedErrorToken(_ token: String) -> Bool {
        let normalizedToken = Self.normalizeErrorToken(token)
        guard !normalizedToken.isEmpty else { return false }
        return ([normalizedCode, normalizedMessage] + normalizedDetailTokens)
            .contains { $0.contains(normalizedToken) }
    }

    var requiresAuthentication: Bool {
        serverContractCode == .authRequired
    }

    var isForbiddenFeature: Bool {
        serverContractCode == .forbiddenFeature
    }

    var isGroupAccessForbidden: Bool {
        normalizedCode == "GROUP_ACCESS_FORBIDDEN" || serverContractCode == .groupAccessForbidden
    }

    var isGroupMemberAlreadyExists: Bool {
        serverContractCode == .groupMemberAlreadyExists
    }

    var isUserNotFound: Bool {
        serverContractCode == .userNotFound
    }

    var isRecruitingClosed: Bool {
        serverContractCode == .recruitingClosed
    }

    var isRecruitingApplyEndpoint: Bool {
        normalizedRequestMethod == "POST"
            && (normalizedEndpoint.hasSuffix("/apply") || normalizedEndpoint.contains("/participants"))
    }

    var isRecruitingCapacityFull: Bool {
        guard isRecruitingApplyEndpoint else { return false }
        if containsNormalizedErrorToken("CAPACITY_FULL")
            || containsNormalizedErrorToken("RECRUITING_FULL")
            || containsNormalizedErrorToken("ALREADY_FULL") {
            return true
        }

        let lowercasedMessage = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return (lowercasedMessage.contains("capacity") && lowercasedMessage.contains("full"))
            || lowercasedMessage.contains("already full")
            || lowercasedMessage.contains("is full")
    }

    var isRecruitingApplyClosedOrFull: Bool {
        guard isRecruitingApplyEndpoint else { return false }
        let lowercasedMessage = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return isRecruitingClosed || isRecruitingCapacityFull || lowercasedMessage.contains("closed")
    }

    var isRateLimited: Bool {
        serverContractCode == .rateLimited
    }

    var serverContractMapped: UserFacingError {
        ErrorMapper.map(self)
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

private enum ErrorMappingContext {
    case authSignup
    case authLogin
    case recruitingList
    case genericForm
    case generic
}

extension UserFacingError {
    fileprivate var normalizedEndpoint: String {
        let trimmed = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        return trimmed.components(separatedBy: "?").first ?? trimmed
    }

    fileprivate var normalizedRequestMethod: String {
        requestMethod?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
    }

    var isGroupNotFoundResource: Bool {
        guard statusCode == 404 else { return false }
        guard normalizedCode == "RESOURCE_NOT_FOUND" else { return false }

        if normalizedEndpoint.hasPrefix("/groups/") {
            return true
        }
        return normalizedEndpoint == "/recruiting-posts"
            && normalizedRequestMethod == "POST"
    }

    var isMatchNotFoundResource: Bool {
        guard statusCode == 404 else { return false }
        if normalizedEndpoint.hasPrefix("/matches/") {
            return true
        }
        return normalizedCode == "MATCH_NOT_FOUND"
    }

    fileprivate var groupNotFoundPresentationMessage: String {
        if normalizedEndpoint == "/recruiting-posts", normalizedRequestMethod == "POST" {
            return "삭제되었거나 존재하지 않는 그룹입니다."
        }
        return "더 이상 접근할 수 없는 그룹입니다."
    }

    fileprivate var errorMappingContext: ErrorMappingContext {
        switch (normalizedRequestMethod, normalizedEndpoint) {
        case ("POST", "/auth/signup/email"):
            return .authSignup
        case ("POST", "/auth/login/email"):
            return .authLogin
        case ("GET", "/recruiting-posts"), ("GET", "/recruiting-posts/public"):
            return .recruitingList
        default:
            if statusCode == 400 {
                return .genericForm
            }
            return .generic
        }
    }

    fileprivate func withPresentation(title: String, message: String) -> UserFacingError {
        UserFacingError(
            title: title,
            message: message,
            code: code,
            provider: provider,
            statusCode: statusCode,
            details: details,
            endpoint: endpoint,
            requestMethod: requestMethod
        )
    }
}

enum ErrorMapper {
    static func map(_ error: UserFacingError) -> UserFacingError {
        if error.isGroupNotFoundResource {
            #if DEBUG
            print("[ErrorMapper] mapped group not found -> deleted or inaccessible group")
            #endif
            return error.withPresentation(
                title: "접근할 수 없는 그룹이에요",
                message: error.groupNotFoundPresentationMessage
            )
        }

        if let mappedError = mapPermissionOrResourceError(error) {
            return mappedError
        }

        if error.isRecruitingApplyClosedOrFull {
            return error.withPresentation(
                title: "모집이 마감되었어요",
                message: "모집이 마감되어 참가 신청할 수 없어요."
            )
        }

        if error.statusCode == 400, case .unknown = error.serverContractCode {
            return mapInvalidPayload(error)
        }

        switch error.serverContractCode {
        case .riotAccountAlreadyAddedByThisUser:
            return error.withPresentation(
                title: "이미 추가한 Riot ID예요",
                message: "같은 Riot ID를 내 목록에 두 번 추가할 수는 없어요."
            )
        case .riotAccountAddUnavailable:
            return error.withPresentation(
                title: "Riot ID를 추가하지 못했어요",
                message: "요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요."
            )
        case .authRequired:
            return error.withPresentation(
                title: "로그인이 필요해요",
                message: "이 기능은 로그인 후 사용할 수 있어요. 이메일, Apple 또는 Google로 로그인해 주세요."
            )
        case .forbiddenFeature:
            return error.withPresentation(
                title: "권한이 없어요",
                message: "이 기능에 대한 권한이 없습니다."
            )
        case .groupAccessForbidden:
            return error.withPresentation(
                title: "권한이 없어요",
                message: "이 작업을 진행할 권한이 없어요."
            )
        case .groupMemberAlreadyExists:
            return error.withPresentation(
                title: "이미 참여 중이에요",
                message: "이미 그룹에 참여 중인 사용자예요."
            )
        case .socialTokenInvalid:
            return error.withPresentation(
                title: "소셜 로그인 실패",
                message: "소셜 로그인 정보를 확인하지 못했어요. 다시 시도해 주세요."
            )
        case .accountExistsWithApple:
            return error.withPresentation(
                title: "로그인 방법 안내",
                message: "이 계정은 Apple 로그인으로 이용할 수 있어요. Apple로 계속해 주세요."
            )
        case .accountExistsWithGoogle:
            return error.withPresentation(
                title: "로그인 방법 안내",
                message: "이 계정은 Google 로그인으로 이용할 수 있어요. Google로 계속해 주세요."
            )
        case .authProviderMismatch:
            return error.withPresentation(
                title: "로그인 방법 안내",
                message: "이 계정은 다른 로그인 방식으로 연결되어 있어요. 올바른 로그인 방식으로 다시 시도해 주세요."
            )
        case .accountNotFound:
            return error.withPresentation(
                title: "존재하지 않는 계정이에요",
                message: "가입한 이메일인지 다시 확인해 주세요."
            )
        case .userNotFound:
            return error.withPresentation(
                title: "사용자를 찾을 수 없어요",
                message: "추가할 사용자를 찾을 수 없어요."
            )
        case .unsupportedProvider:
            return error.withPresentation(
                title: "지원하지 않는 로그인 방식이에요",
                message: "이 앱에서는 이메일, Apple, Google 로그인을 사용할 수 있어요."
            )
        case .emailAlreadyExists:
            return error.withPresentation(
                title: "이미 가입된 이메일이에요",
                message: "다른 이메일을 사용하거나 로그인으로 계속해 주세요."
            )
        case .nicknameAlreadyExists:
            return error.withPresentation(
                title: "이미 사용 중인 닉네임이에요",
                message: "다른 닉네임으로 다시 시도해 주세요."
            )
        case .invalidEmailFormat:
            return error.withPresentation(
                title: "이메일 형식을 확인해 주세요",
                message: "올바른 이메일 형식으로 다시 입력해 주세요."
            )
        case .weakPassword:
            return error.withPresentation(
                title: "비밀번호를 다시 확인해 주세요",
                message: "비밀번호 조건을 만족하도록 다시 입력해 주세요."
            )
        case .requiredTermsNotAgreed:
            return error.withPresentation(
                title: "필수 약관 동의가 필요해요",
                message: "서비스 이용약관과 개인정보 처리방침에 동의해 주세요."
            )
        case .invalidPayload:
            return mapInvalidPayload(error)
        case .internalServerError:
            return error.withPresentation(
                title: "서버에 잠시 문제가 있어요",
                message: "잠시 후 다시 시도해 주세요."
            )
        case .invalidCredentials:
            return error.withPresentation(
                title: "로그인 정보를 다시 확인해 주세요",
                message: "로그인에 실패했어요. 선택한 계정으로 다시 시도해 주세요."
            )
        case .emailAuthDisabled:
            return error.withPresentation(
                title: "이메일 회원가입을 사용할 수 없어요",
                message: "현재 이메일 회원가입이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요."
            )
        case .passwordAuthDisabled:
            return error.withPresentation(
                title: "이메일 로그인을 사용할 수 없어요",
                message: "현재 이메일 로그인이 비활성화되어 있어요. 잠시 후 다시 시도해 주세요."
            )
        case .recruitingClosed:
            return error.withPresentation(
                title: "모집이 마감되었어요",
                message: "모집이 종료되어 더 이상 진행할 수 없어요."
            )
        case .rateLimited:
            var rateLimitedError = error.withPresentation(
                title: "요청이 잠시 몰리고 있어요",
                message: "요청이 많아 잠시 후 다시 시도해 주세요."
            )
            rateLimitedError.code = rateLimitedError.code ?? "RATE_LIMITED"
            rateLimitedError.statusCode = rateLimitedError.statusCode ?? 429
            return rateLimitedError
        case .unknown:
            return error
        }
    }

    private static func mapPermissionOrResourceError(_ error: UserFacingError) -> UserFacingError? {
        let rawMessage = error.message.lowercased()

        if error.statusCode == 403 {
            if rawMessage.contains("share the same inhouse group") {
                return error.withPresentation(
                    title: "같은 그룹 멤버만 볼 수 있어요",
                    message: "같은 인하우스 그룹에 속한 사용자 기록만 확인할 수 있어요."
                )
            }

            if error.normalizedEndpoint.contains("/profiles/") || error.normalizedEndpoint.contains("/history") {
                return error.withPresentation(
                    title: "기록을 볼 수 없어요",
                    message: "같은 그룹 멤버이거나 공개된 기록만 확인할 수 있어요."
                )
            }

            if error.normalizedEndpoint.hasPrefix("/groups/") {
                return error.withPresentation(
                    title: "그룹에 접근할 수 없어요",
                    message: "참여 중인 그룹만 확인할 수 있어요."
                )
            }

            return error.withPresentation(
                title: "권한이 없어요",
                message: "이 정보에 접근할 수 없습니다."
            )
        }

        if error.statusCode == 404 {
            if error.normalizedEndpoint.contains("/matches/") {
                return error.withPresentation(
                    title: "경기를 찾을 수 없어요",
                    message: "삭제되었거나 더 이상 볼 수 없는 경기입니다."
                )
            }

            if error.normalizedEndpoint.contains("/profiles/") || rawMessage.contains("user") {
                return error.withPresentation(
                    title: "사용자를 찾을 수 없어요",
                    message: "삭제되었거나 확인할 수 없는 사용자입니다."
                )
            }
        }

        if error.statusCode == 400,
           rawMessage.contains("validation") || rawMessage.contains("invalid") {
            return mapInvalidPayload(error)
        }

        return nil
    }

    private static func mapInvalidPayload(_ error: UserFacingError) -> UserFacingError {
        switch error.errorMappingContext {
        case .authSignup:
            return error.withPresentation(
                title: "입력값을 다시 확인해 주세요",
                message: "입력한 회원가입 정보를 다시 확인한 뒤 시도해 주세요."
            )
        case .authLogin:
            return error.withPresentation(
                title: "로그인 정보를 다시 확인해 주세요",
                message: "입력한 로그인 정보를 다시 확인한 뒤 다시 시도해 주세요."
            )
        case .recruitingList:
            return error.withPresentation(
                title: "필터 조건을 다시 확인해 주세요",
                message: "목록을 불러오는 조건이 올바르지 않습니다."
            )
        case .genericForm, .generic:
            return error.withPresentation(
                title: "입력값을 다시 확인해 주세요",
                message: "입력한 내용을 다시 확인한 뒤 시도해 주세요."
            )
        }
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
    static let standardLanes: [Position] = [.top, .jungle, .mid, .adc, .support]
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

    var title: String {
        switch self {
        case .private: return "비공개"
        case .public: return "공개"
        }
    }
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

enum RecruitDateFilterPreset: String, Codable, Hashable, CaseIterable {
    case all
    case today
    case thisWeek
    case specificDate
}

struct RecruitDateFilter: Codable, Hashable {
    var preset: RecruitDateFilterPreset = .all
    var selectedDate: Date = Date()
    var includesUnscheduledPosts = true

    var isDefault: Bool {
        preset == .all && includesUnscheduledPosts
    }
}

struct RecruitBoardFilterState: Codable, Hashable {
    var selectedDateFilter = RecruitDateFilter()
    var selectedPositions: Set<String> = []
    var selectedRegions: Set<String> = []
    var selectedTags: Set<String> = []

    static let defaultValue = RecruitBoardFilterState()

    var isDefault: Bool {
        selectedDateFilter.isDefault
            && selectedPositions.isEmpty
            && selectedRegions.isEmpty
            && selectedTags.isEmpty
    }
}

struct RecruitPostListQuery: Hashable {
    var postType: RecruitingPostType?
    var groupID: String?
    var status: RecruitingPostStatus? = .open
    var scheduledFrom: Date?
    var scheduledTo: Date?
    var requiredPositions: [String] = []
    var regions: [String] = []
    var tags: [String] = []
    var includeUnscheduledPosts = true
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

enum ChampionAggregationStatus: Codable, Hashable {
    case disconnected
    case syncing
    case partial
    case insufficientSample
    case connectedEmpty
    case ready
    case unknown(String)

    init(serverValue: String) {
        let normalized = serverValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()

        switch normalized {
        case "DISCONNECTED", "RIOT_DISCONNECTED", "RIOT_UNLINKED", "UNLINKED", "NO_RIOT_ACCOUNT", "NOT_CONNECTED":
            self = .disconnected
        case "SYNCING", "SYNC_PENDING", "PENDING", "QUEUED", "RUNNING", "NOT_SYNCED", "NEEDS_SYNC", "INSUFFICIENT_SYNC":
            self = .syncing
        case "PARTIAL", "PARTIALLY_READY", "PARTIALLY_COMPLETE", "INCOMPLETE":
            self = .partial
        case "INSUFFICIENT_SAMPLE", "NOT_ENOUGH_MATCHES", "NOT_ENOUGH_RANKED_MATCHES", "LOW_SAMPLE", "NO_RANKED_MATCHES":
            self = .insufficientSample
        case "CONNECTED_EMPTY", "EMPTY", "NO_DATA", "NO_CHAMPION_DATA":
            self = .connectedEmpty
        case "READY", "SUCCEEDED", "SUCCESS", "COMPLETED":
            self = .ready
        default:
            self = .unknown(normalized)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = ChampionAggregationStatus(serverValue: stringValue)
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self = boolValue ? .ready : .connectedEmpty
            return
        }
        self = .unknown("UNSUPPORTED")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(debugValue)
    }

    var debugValue: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .syncing:
            return "syncing"
        case .partial:
            return "partial"
        case .insufficientSample:
            return "insufficient_sample"
        case .connectedEmpty:
            return "connected_empty"
        case .ready:
            return "ready"
        case let .unknown(value):
            return value.lowercased()
        }
    }
}

struct ProfileTopChampionAggregation: Codable, Hashable {
    let status: ChampionAggregationStatus?
    let reason: String?
    let message: String?
    let syncCoverageSummary: String?

    init(
        status: ChampionAggregationStatus? = nil,
        reason: String? = nil,
        message: String? = nil,
        syncCoverageSummary: String? = nil
    ) {
        self.status = status
        self.reason = Self.trimmed(reason)
        self.message = Self.trimmed(message)
        self.syncCoverageSummary = Self.trimmed(syncCoverageSummary)
    }

    var normalizedReason: String? {
        Self.normalizedToken(reason)
    }

    var preferredSubtitle: String? {
        message ?? syncCoverageSummary
    }

    var isInsufficientBackfill: Bool {
        guard let normalizedReason else { return false }
        return normalizedReason.contains("INSUFFICIENT_BACKFILL")
            || normalizedReason.contains("BACKFILL_PENDING")
            || normalizedReason.contains("BACKFILL")
    }

    var isInsufficientSample: Bool {
        if status == .insufficientSample {
            return true
        }

        guard let normalizedReason else { return false }
        return normalizedReason.contains("INSUFFICIENT_SAMPLE")
            || normalizedReason.contains("NOT_ENOUGH_MATCHES")
            || normalizedReason.contains("NOT_ENOUGH_RANKED_MATCHES")
            || normalizedReason.contains("LOW_SAMPLE")
            || normalizedReason.contains("NO_RANKED_MATCHES")
    }

    private static func trimmed(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func normalizedToken(_ value: String?) -> String? {
        let normalized = trimmed(value)?
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

struct ProfileTopChampion: Codable, Hashable {
    let championId: Int?
    let championKey: String
    let championName: String
    let games: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let kills: Double
    let deaths: Double
    let assists: Double
    let kda: Double?
    let lastPlayedAt: Date?
}

struct ProfileTopChampionViewState: Equatable, Identifiable {
    let id: String
    let rank: Int
    let championKey: String
    let championName: String
    let gamesText: String
    let winRateText: String
    let kdaText: String?
    let lastPlayedText: String?
    let championIconURL: URL?

    var isTopRanked: Bool {
        rank == 1
    }
}

enum ProfileTopChampionsDisplayState: String, Equatable {
    case content
    case syncing
    case backfillPending = "backfill_pending"
    case insufficientSample = "insufficient_sample"
    case disconnected
    case genericEmpty = "generic_empty"
}

enum ProfileTopChampionsSectionState: Equatable {
    case hidden
    case empty(state: ProfileTopChampionsDisplayState, title: String, message: String, subtitle: String?)
    case content([ProfileTopChampionViewState], subtitle: String?)

    static func build(
        champions: [ProfileTopChampion],
        aggregation: ProfileTopChampionAggregation?,
        riotAccountsViewState: RiotLinkedAccountsViewState
    ) -> ProfileTopChampionsSectionState {
        let rows = championRows(from: champions)
        let displayState = resolvedDisplayState(
            champions: champions,
            aggregation: aggregation,
            riotAccountsViewState: riotAccountsViewState
        )
        let subtitle = aggregation?.preferredSubtitle

        if displayState == .content {
            return .content(rows, subtitle: subtitle)
        }

        let copy = emptyCopy(for: displayState)
        return .empty(state: displayState, title: copy.title, message: copy.message, subtitle: subtitle)
    }

    static func build(
        champions: [ProfileTopChampion],
        aggregationStatus: ChampionAggregationStatus?,
        riotAccountsViewState: RiotLinkedAccountsViewState
    ) -> ProfileTopChampionsSectionState {
        build(
            champions: champions,
            aggregation: ProfileTopChampionAggregation(status: aggregationStatus),
            riotAccountsViewState: riotAccountsViewState
        )
    }

    static func build(
        champions: [ProfileTopChampion],
        hasLinkedRiotAccount: Bool
    ) -> ProfileTopChampionsSectionState {
        build(
            champions: champions,
            aggregation: hasLinkedRiotAccount ? nil : ProfileTopChampionAggregation(status: .disconnected),
            riotAccountsViewState: hasLinkedRiotAccount ? .loading : .noLinkedAccounts
        )
    }

    var debugState: ProfileTopChampionsDisplayState {
        switch self {
        case .hidden:
            return .genericEmpty
        case let .empty(state, _, _, _):
            return state
        case .content:
            return .content
        }
    }

    var renderedChampions: [ProfileTopChampionViewState] {
        switch self {
        case let .content(items, _):
            return items
        case .hidden, .empty:
            return []
        }
    }

    var headerSubtitle: String {
        switch self {
        case .hidden:
            return Self.defaultHeaderSubtitle
        case let .empty(_, _, _, subtitle), let .content(_, subtitle):
            return subtitle ?? Self.defaultHeaderSubtitle
        }
    }

    private static let defaultHeaderSubtitle = "서버 집계 기준 가장 많이 플레이한 챔피언"

    private static func championRows(from champions: [ProfileTopChampion]) -> [ProfileTopChampionViewState] {
        champions
            .sorted { lhs, rhs in
                if lhs.games == rhs.games {
                    if lhs.winRate == rhs.winRate {
                        return resolvedChampionName(lhs).localizedCaseInsensitiveCompare(resolvedChampionName(rhs)) == .orderedAscending
                    }
                    return normalizedWinRate(for: lhs) > normalizedWinRate(for: rhs)
                }
                return lhs.games > rhs.games
            }
            .prefix(3)
            .enumerated()
            .map { index, champion in
                ProfileTopChampionViewState(
                    id: championIdentity(champion, rank: index + 1),
                    rank: index + 1,
                    championKey: champion.championKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    championName: resolvedChampionName(champion),
                    gamesText: "\(champion.games)판",
                    winRateText: "승률 \(formatPercentage(normalizedWinRate(for: champion)))",
                    kdaText: formattedKDA(champion.kda),
                    lastPlayedText: formattedLastPlayed(champion.lastPlayedAt),
                    championIconURL: championIconURL(for: champion)
                )
            }
    }

    private static func resolvedDisplayState(
        champions: [ProfileTopChampion],
        aggregation: ProfileTopChampionAggregation?,
        riotAccountsViewState: RiotLinkedAccountsViewState
    ) -> ProfileTopChampionsDisplayState {
        if !champions.isEmpty {
            return .content
        }

        if isSyncing(aggregation: aggregation, riotAccountsViewState: riotAccountsViewState) {
            return .syncing
        }

        if aggregation?.status == .partial, aggregation?.isInsufficientBackfill == true {
            return .backfillPending
        }

        if aggregation?.isInsufficientSample == true {
            return .insufficientSample
        }

        if let status = aggregation?.status {
            switch status {
            case .disconnected:
                return .disconnected
            case .connectedEmpty, .ready, .partial, .syncing, .insufficientSample, .unknown:
                break
            }
        }

        if case .noLinkedAccounts = riotAccountsViewState {
            return .disconnected
        }

        return .genericEmpty
    }

    private static func isSyncing(
        aggregation: ProfileTopChampionAggregation?,
        riotAccountsViewState: RiotLinkedAccountsViewState
    ) -> Bool {
        if aggregation?.status == .syncing {
            return true
        }

        switch riotAccountsViewState {
        case .loading:
            return true
        case .noLinkedAccounts, .error:
            return false
        case let .loaded(accounts):
            guard !accounts.isEmpty else { return false }
            if accounts.contains(where: { $0.syncStatus.isInFlight || $0.syncStatus == .idle }) {
                return true
            }
            return false
        }
    }

    private static func emptyCopy(for state: ProfileTopChampionsDisplayState) -> (title: String, message: String) {
        switch state {
        case .content:
            return (
                "주 챔피언을 불러왔어요",
                "상위 챔피언을 표시합니다."
            )
        case .syncing:
            return (
                "최근 전적을 분석 중이에요",
                "동기화가 끝나면 주 챔피언이 자동으로 채워집니다."
            )
        case .backfillPending:
            return (
                "전적 동기화가 더 필요해요",
                "이전 랭크 전적이 더 반영되면 주 챔피언을 보여드릴게요."
            )
        case .insufficientSample:
            return (
                "랭크 기록이 더 필요해요",
                "집계 가능한 랭크 기록이 더 쌓이면 주 챔피언을 보여드릴게요."
            )
        case .disconnected:
            return (
                "Riot 계정 연결이 필요해요",
                "Riot ID를 연결하면 주 챔피언을 분석해 보여드릴게요."
            )
        case .genericEmpty:
            return (
                "아직 표시할 챔피언이 없어요",
                "서버 집계가 완료되면 상위 챔피언을 보여드릴게요."
            )
        }
    }

    private static func resolvedChampionName(_ champion: ProfileTopChampion) -> String {
        let normalizedName = champion.championName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedName.isEmpty {
            return normalizedName
        }

        let normalizedKey = champion.championKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedKey.isEmpty ? "알 수 없는 챔피언" : normalizedKey
    }

    private static func championIdentity(_ champion: ProfileTopChampion, rank: Int) -> String {
        let normalizedKey = champion.championKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedKey.isEmpty {
            return "\(normalizedKey)-\(rank)"
        }
        return "\(resolvedChampionName(champion))-\(rank)"
    }

    private static func normalizedWinRate(for champion: ProfileTopChampion) -> Double {
        let rawValue = champion.winRate
        let normalized: Double
        if rawValue > 0 {
            normalized = rawValue <= 1 ? rawValue * 100 : rawValue
        } else if champion.games > 0 {
            normalized = Double(champion.wins) / Double(champion.games) * 100
        } else {
            normalized = 0
        }

        return min(max(normalized, 0), 100)
    }

    private static func formatPercentage(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    private static func formattedKDA(_ value: Double?) -> String? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let rounded = (value * 10).rounded() / 10
        let text: String
        if rounded.rounded() == rounded {
            text = "\(Int(rounded))"
        } else {
            text = String(format: "%.1f", rounded)
        }
        return "KDA \(text)"
    }

    private static func formattedLastPlayed(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d"
        return "최근 \(formatter.string(from: date))"
    }

    private static func championIconURL(for champion: ProfileTopChampion) -> URL? {
        let normalizedKey = champion.championKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        if !normalizedKey.isEmpty {
            return URL(string: "https://ddragon.leagueoflegends.com/cdn/16.8.1/img/champion/\(normalizedKey).png")
        }

        guard let championId = champion.championId else { return nil }
        return URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/\(championId).png")
    }
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
    var topChampions: [ProfileTopChampion] = []
    var topChampionAggregation: ProfileTopChampionAggregation? = nil

    init(
        id: String,
        email: String,
        nickname: String,
        primaryPosition: Position?,
        secondaryPosition: Position?,
        isFillAvailable: Bool,
        styleTags: [String],
        mannerScore: Double,
        noshowCount: Int,
        topChampions: [ProfileTopChampion] = [],
        championAggregationStatus: ChampionAggregationStatus? = nil,
        topChampionAggregation: ProfileTopChampionAggregation? = nil
    ) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.isFillAvailable = isFillAvailable
        self.styleTags = styleTags
        self.mannerScore = mannerScore
        self.noshowCount = noshowCount
        self.topChampions = topChampions
        self.topChampionAggregation = topChampionAggregation ?? ProfileTopChampionAggregation(status: championAggregationStatus)
    }

    var championAggregationStatus: ChampionAggregationStatus? {
        topChampionAggregation?.status
    }
}

enum ProfilePositionAssignmentSource: String, Codable, Equatable {
    case server
    case fallback
}

struct ProfilePositionSummaryViewState: Equatable {
    let primary: Position?
    let secondary: Position?
    let source: ProfilePositionAssignmentSource
    let primaryPowerText: String?
    let secondaryPowerText: String?
    let captionText: String

    static func build(profile: UserProfile, power: PowerProfile?) -> ProfilePositionSummaryViewState {
        var resolvedPositions: [Position] = []

        func appendIfNeeded(_ position: Position?) {
            guard let position, !resolvedPositions.contains(position) else { return }
            resolvedPositions.append(position)
        }

        appendIfNeeded(power?.primaryPosition)
        appendIfNeeded(power?.secondaryPosition)
        appendIfNeeded(profile.primaryPosition)
        appendIfNeeded(profile.secondaryPosition)

        let source: ProfilePositionAssignmentSource
        if resolvedPositions.isEmpty {
            source = .fallback
        } else {
            source = .server
        }

        fallbackPositions(from: power?.lanePower ?? [:]).forEach { appendIfNeeded($0) }

        return ProfilePositionSummaryViewState(
            primary: resolvedPositions.first,
            secondary: resolvedPositions.dropFirst().first,
            source: source,
            primaryPowerText: scoreText(for: resolvedPositions.first, lanePower: power?.lanePower ?? [:]),
            secondaryPowerText: scoreText(for: resolvedPositions.dropFirst().first, lanePower: power?.lanePower ?? [:]),
            captionText: source == .server ? "서버 산정 라인 적용" : "라인 파워 기준 임시 산정"
        )
    }

    private static func fallbackPositions(from lanePower: [Position: Double]) -> [Position] {
        Position.standardLanes
            .compactMap { position -> (Position, Double)? in
                guard let value = lanePower[position] else { return nil }
                return (position, value)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return laneOrder(lhs.0) < laneOrder(rhs.0)
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private static func laneOrder(_ position: Position) -> Int {
        Position.standardLanes.firstIndex(of: position) ?? Int.max
    }

    private static func scoreText(for position: Position?, lanePower: [Position: Double]) -> String? {
        guard let position, let value = lanePower[position], value.isFinite else { return nil }
        return "\(Int(value.rounded()))"
    }
}

struct ProfilePowerStatViewState: Equatable, Identifiable {
    let id: String
    let label: String
    let valueText: String
    let emphasis: ProfilePowerStatEmphasis
}

enum ProfilePowerStatEmphasis: Equatable {
    case primary
    case secondary
    case gold
}

struct ProfileLanePowerRowViewState: Equatable, Identifiable {
    let id: String
    let position: Position
    let powerText: String
    let progressValue: Double
    let isPrimary: Bool
    let isSecondary: Bool
    let roleBadgeText: String?
    let differenceText: String?
}

struct ProfilePowerSectionViewState: Equatable {
    let overallText: String
    let positionSummary: ProfilePositionSummaryViewState
    let stats: [ProfilePowerStatViewState]
    let laneRows: [ProfileLanePowerRowViewState]
    let calculationHintText: String?

    static func build(power: PowerProfile, positionSummary: ProfilePositionSummaryViewState) -> ProfilePowerSectionViewState {
        let referencePower = positionSummary.primary.flatMap { power.lanePower[$0] } ?? power.lanePower.values.max()
        let laneRows = Position.standardLanes.map { position in
            let lanePower = power.lanePower[position]
            return ProfileLanePowerRowViewState(
                id: position.rawValue,
                position: position,
                powerText: lanePower.map { "\(Int($0.rounded()))" } ?? "--",
                progressValue: min(max(lanePower ?? 0, 0), 100),
                isPrimary: position == positionSummary.primary,
                isSecondary: position == positionSummary.secondary,
                roleBadgeText: position == positionSummary.primary ? "주" : (position == positionSummary.secondary ? "부" : nil),
                differenceText: differenceText(
                    currentPower: lanePower,
                    referencePower: referencePower,
                    isPrimary: position == positionSummary.primary
                )
            )
        }

        return ProfilePowerSectionViewState(
            overallText: "\(Int(power.overallPower.rounded()))",
            positionSummary: positionSummary,
            stats: [
                ProfilePowerStatViewState(id: "form", label: "최근 폼", valueText: "\(Int(power.formScore.rounded()))", emphasis: .primary),
                ProfilePowerStatViewState(id: "stability", label: "안정성", valueText: "\(Int(power.stability.rounded()))", emphasis: .secondary),
                ProfilePowerStatViewState(id: "carry", label: "캐리 기여", valueText: "\(Int(power.carry.rounded()))", emphasis: .secondary),
                ProfilePowerStatViewState(id: "team", label: "팀 기여도", valueText: "\(Int(power.teamContribution.rounded()))", emphasis: .secondary),
                ProfilePowerStatViewState(id: "mmr", label: "내전 MMR", valueText: "\(Int(power.inhouseMMR.rounded()))", emphasis: .gold),
            ],
            laneRows: laneRows,
            calculationHintText: calculationHint(for: power, source: positionSummary.source)
        )
    }

    private static func calculationHint(for power: PowerProfile, source: ProfilePositionAssignmentSource) -> String? {
        if let autoAssignmentBasis = power.autoAssignmentBasis?.trimmingCharacters(in: .whitespacesAndNewlines),
           !autoAssignmentBasis.isEmpty {
            return autoAssignmentBasis
        }
        if let historicalContributionSummary = power.historicalContributionSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !historicalContributionSummary.isEmpty {
            return historicalContributionSummary
        }
        return source == .fallback ? "서버 라인 값이 비어 있어 라인 파워 순서로 표시합니다." : "라인 파워와 최근/이전 시즌 지표가 함께 반영됩니다."
    }

    private static func differenceText(
        currentPower: Double?,
        referencePower: Double?,
        isPrimary: Bool
    ) -> String? {
        guard let currentPower, currentPower.isFinite else { return nil }
        if isPrimary {
            return "기준"
        }
        guard let referencePower, referencePower.isFinite else { return nil }
        let difference = Int((currentPower - referencePower).rounded())
        if difference == 0 {
            return "동일"
        }
        return difference > 0 ? "+\(difference)" : "\(difference)"
    }
}

struct PowerProfile: Codable, Hashable {
    let userID: String
    let overallPower: Double
    let lanePower: [Position: Double]
    let primaryPosition: Position?
    let secondaryPosition: Position?
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
    let laneScoreBreakdown: [Position: Double]?
    let autoAssignmentBasis: String?
    let historicalContributionSummary: String?
    let topChampions: [ProfileTopChampion]?
    let topChampionAggregation: ProfileTopChampionAggregation?

    init(
        userID: String,
        overallPower: Double,
        lanePower: [Position: Double],
        primaryPosition: Position?,
        secondaryPosition: Position?,
        stability: Double,
        carry: Double,
        teamContribution: Double,
        laneInfluence: Double,
        basePower: Double,
        formScore: Double,
        inhouseMMR: Double,
        inhouseConfidence: Double,
        version: String,
        calculatedAt: Date,
        laneScoreBreakdown: [Position: Double]? = nil,
        autoAssignmentBasis: String? = nil,
        historicalContributionSummary: String? = nil,
        topChampions: [ProfileTopChampion]? = nil,
        topChampionAggregation: ProfileTopChampionAggregation? = nil
    ) {
        self.userID = userID
        self.overallPower = overallPower
        self.lanePower = lanePower
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.stability = stability
        self.carry = carry
        self.teamContribution = teamContribution
        self.laneInfluence = laneInfluence
        self.basePower = basePower
        self.formScore = formScore
        self.inhouseMMR = inhouseMMR
        self.inhouseConfidence = inhouseConfidence
        self.version = version
        self.calculatedAt = calculatedAt
        self.laneScoreBreakdown = laneScoreBreakdown
        self.autoAssignmentBasis = autoAssignmentBasis
        self.historicalContributionSummary = historicalContributionSummary
        self.topChampions = topChampions
        self.topChampionAggregation = topChampionAggregation
    }

    var championAggregationStatus: ChampionAggregationStatus? {
        topChampionAggregation?.status
    }

    var preferredPositions: [Position] {
        var ordered: [Position] = []

        func appendIfNeeded(_ position: Position?) {
            guard let position, !ordered.contains(position) else { return }
            ordered.append(position)
        }

        appendIfNeeded(primaryPosition)
        appendIfNeeded(secondaryPosition)

        let laneOrdered = lanePower
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return Self.laneOrder(lhs.key) < Self.laneOrder(rhs.key)
                }
                return lhs.value > rhs.value
            }
            .map(\.key)

        laneOrdered.forEach { appendIfNeeded($0) }
        return ordered
    }

    var resolvedPrimaryPosition: Position? {
        preferredPositions.first
    }

    var resolvedSecondaryPosition: Position? {
        preferredPositions.dropFirst().first
    }

    private static func laneOrder(_ position: Position) -> Int {
        Position.standardLanes.firstIndex(of: position) ?? Int.max
    }
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
        if syncUIState == .syncing,
           let lastSyncRequestedAt,
           Date().timeIntervalSince(lastSyncRequestedAt) >= 12
        {
            return "최근 전적을 불러오는 중이에요. 서버 응답에 따라 조금 더 걸릴 수 있어요."
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
    let isMember: Bool?
    let joinPolicy: JoinPolicy
    let tags: [String]
    let ownerUserID: String
    let canInviteMembers: Bool?
    let inviteMembersBlockedReason: String?
    let memberCount: Int
    let recentMatches: Int

    init(
        id: String,
        name: String,
        description: String?,
        visibility: GroupVisibility,
        isMember: Bool? = nil,
        joinPolicy: JoinPolicy,
        tags: [String],
        ownerUserID: String,
        canInviteMembers: Bool? = nil,
        inviteMembersBlockedReason: String? = nil,
        memberCount: Int,
        recentMatches: Int
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.visibility = visibility
        self.isMember = isMember
        self.joinPolicy = joinPolicy
        self.tags = tags
        self.ownerUserID = ownerUserID
        self.canInviteMembers = canInviteMembers
        self.inviteMembersBlockedReason = inviteMembersBlockedReason
        self.memberCount = memberCount
        self.recentMatches = recentMatches
    }

    var isPubliclyVisible: Bool {
        visibility == .public
    }

    func isAccessible(knownMember: Bool = false) -> Bool {
        isPubliclyVisible || isMember == true || knownMember
    }
}

extension Sequence where Element == GroupSummary {
    func filterPubliclyVisible() -> [GroupSummary] {
        filter(\.isPubliclyVisible)
    }

    func filterAccessible(knownMemberGroupIDs: Set<String> = []) -> [GroupSummary] {
        filter { group in
            group.isAccessible(knownMember: knownMemberGroupIDs.contains(group.id))
        }
    }
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

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case recent
    case local
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "전체"
        case .recent: return "최근"
        case .local: return "로컬"
        case .saved: return "저장"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "아직 기록된 내전이 없습니다."
        case .recent:
            return "최근 기록이 없습니다."
        case .local:
            return "로컬에 저장된 기록이 없습니다."
        case .saved:
            return "저장한 기록이 없습니다."
        }
    }

    var debugName: String { rawValue }
}

enum HistoryItemSource: String, Hashable {
    case remote
    case local
}

struct HistoryListItem: Hashable, Identifiable {
    var id: String { matchID }

    let matchID: String
    let source: HistoryItemSource
    let remoteItem: MatchHistoryItem?
    let localItem: LocalMatchRecord?
    let isSaved: Bool

    init(remoteItem: MatchHistoryItem, isSaved: Bool) {
        self.matchID = remoteItem.matchID
        self.source = .remote
        self.remoteItem = remoteItem
        self.localItem = nil
        self.isSaved = isSaved
    }

    init(localItem: LocalMatchRecord, isSaved: Bool) {
        self.matchID = localItem.matchID
        self.source = .local
        self.remoteItem = nil
        self.localItem = localItem
        self.isSaved = isSaved
    }

    var sortDate: Date {
        remoteItem?.scheduledAt ?? localItem?.savedAt ?? .distantPast
    }
}

struct HistoryViewState: Equatable {
    let selectedFilter: HistoryFilter
    let allItems: [HistoryListItem]
    let displayedItems: [HistoryListItem]

    var emptyMessage: String {
        selectedFilter.emptyMessage
    }
}

struct RecentSearchKeyword: Codable, Hashable, Identifiable {
    let id: String
    let keyword: String
    let searchedAt: Date
}

struct GroupMemberInviteUser: Codable, Hashable, Identifiable {
    let id: String
    let nickname: String
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let recentPower: Double?
    let riotDisplayName: String?
    let profileImageURL: URL?
}

enum SearchResultKind: String, Hashable, Identifiable {
    case riotAccount
    case group
    case recruitPost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .riotAccount:
            return "Riot ID"
        case .group:
            return "공개 그룹"
        case .recruitPost:
            return "모집글"
        }
    }

    var emptyDescription: String {
        switch self {
        case .riotAccount:
            return "연결된 Riot ID와 일치하는 항목이 없습니다."
        case .group:
            return "일치하는 공개 그룹이 없습니다."
        case .recruitPost:
            return "일치하는 모집글이 없습니다."
        }
    }
}

enum SearchResultDestination: Hashable {
    case riotAccounts
    case groupDetail(groupID: String, isAccessible: Bool)
    case recruitDetail(postID: String)

    var route: AppRoute {
        switch self {
        case .riotAccounts:
            return .riotAccounts
        case let .groupDetail(groupID, _):
            return .groupDetail(groupID)
        case let .recruitDetail(postID):
            return .recruitDetail(postID: postID)
        }
    }

    var authRequirement: AuthRequirement {
        switch self {
        case .riotAccounts:
            return .riotAccount
        case .groupDetail:
            return .groupManagement
        case .recruitDetail:
            return .recruitingWrite
        }
    }

    var isAccessible: Bool {
        switch self {
        case .riotAccounts, .recruitDetail:
            return true
        case let .groupDetail(_, isAccessible):
            return isAccessible
        }
    }
}

struct SearchResultItem: Hashable, Identifiable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let tags: [String]
    let supportingText: String?
    let destination: SearchResultDestination
}

struct SearchResultSection: Hashable, Identifiable {
    let kind: SearchResultKind
    let items: [SearchResultItem]

    var id: String { kind.rawValue }
    var title: String { kind.title }
}

struct SearchResponse: Hashable {
    let sections: [SearchResultSection]

    var isEmpty: Bool {
        sections.allSatisfy { $0.items.isEmpty }
    }
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
    let homeSummaryState: HomeSummaryLoadState
    let trackedGroupsState: HomeTrackedGroupsLoadState
    let currentMatchState: HomeCurrentMatchLoadState
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

enum HomeSummaryLoadState: Equatable {
    case loaded
}

enum HomeTrackedGroupsLoadState: Equatable {
    case loaded
    case partial
    case missing
}

enum HomeCurrentMatchLoadState: Equatable {
    case loaded
    case partial
    case missing
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

struct ManualAdjustDraft: Codable, Hashable {
    let mode: BalanceMode
    let blueRows: [ManualAdjustRow]
    let redRows: [ManualAdjustRow]
}

struct ManualAdjustRow: Codable, Hashable, Identifiable {
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
    let positionSummary: ProfilePositionSummaryViewState
    let powerSection: ProfilePowerSectionViewState?
    let history: [MatchHistoryItem]
    let topChampionsSection: ProfileTopChampionsSectionState
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
}

struct RecruitBoardSnapshot: Equatable {
    let selectedType: RecruitingPostType
    let filterState: RecruitBoardFilterState
    let posts: [RecruitPost]
    let groupNamesByID: [String: String]
    let groupRegionsByID: [String: String]
}

enum HistoryContentState: Equatable {
    case guest(HistoryViewState)
    case authenticated(HistoryViewState)
}
