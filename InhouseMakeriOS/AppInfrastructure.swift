import Combine
import Foundation
import Security
import SwiftData
import UIKit
import UserNotifications

enum AppEnvironment: String, Equatable, CaseIterable {
    case development
    case production

    var networkConfiguration: NetworkConfiguration {
        switch self {
        case .development:
            return NetworkConfiguration(
                environment: self,
                restBaseURL: "http://127.0.0.1:3000",
                publicWebSocketURL: "ws://127.0.0.1:3000/ws/market",
                privateWebSocketURL: "ws://127.0.0.1:3000/ws/trading"
            )
        case .production:
            return NetworkConfiguration(
                environment: self,
                restBaseURL: "https://inhousemaker.duckdns.org",
                publicWebSocketURL: "wss://inhousemaker.duckdns.org/ws/market",
                privateWebSocketURL: "wss://inhousemaker.duckdns.org/ws/trading"
            )
        }
    }
}

struct NetworkConfiguration: Equatable {
    let restBaseURL: URL
    let publicWebSocketURL: URL
    let privateWebSocketURL: URL

    init(
        environment: AppEnvironment,
        restBaseURL: String,
        publicWebSocketURL: String,
        privateWebSocketURL: String
    ) {
        self.restBaseURL = Self.validatedURL(
            restBaseURL,
            label: "REST base URL",
            environment: environment
        )
        self.publicWebSocketURL = Self.validatedURL(
            publicWebSocketURL,
            label: "Public WS URL",
            environment: environment
        )
        self.privateWebSocketURL = Self.validatedURL(
            privateWebSocketURL,
            label: "Private WS URL",
            environment: environment
        )
    }

    private static func validatedURL(
        _ rawValue: String,
        label: String,
        environment: AppEnvironment
    ) -> URL {
        guard let url = URL(string: rawValue) else {
            let message = "[NetworkConfiguration] Invalid \(label) for \(environment.rawValue): \(rawValue)"
            assertionFailure(message)
            fatalError(message)
        }
        return url
    }
}

enum AppConfigurationError: Error, Equatable {
    case missingEnvironment
    case invalidEnvironment(String)

    var debugDescription: String {
        switch self {
        case .missingEnvironment:
            let supportedValues = AppEnvironment.allCases.map(\.rawValue).joined(separator: ", ")
            return "APP_ENV is missing. Expected one of: \(supportedValues)"
        case let .invalidEnvironment(value):
            let supportedValues = AppEnvironment.allCases.map(\.rawValue).joined(separator: ", ")
            return "APP_ENV '\(value)' is invalid. Expected one of: \(supportedValues)"
        }
    }
}

struct AppConfiguration {
    let environment: AppEnvironment
    let networkConfiguration: NetworkConfiguration
    let googleClientID: String

    var baseURL: URL { networkConfiguration.restBaseURL }
    var publicWebSocketURL: URL { networkConfiguration.publicWebSocketURL }
    var privateWebSocketURL: URL { networkConfiguration.privateWebSocketURL }

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        do {
            return try fromInfoDictionary(bundle.infoDictionary ?? [:])
        } catch let error as AppConfigurationError {
            let message = "[AppConfiguration] \(error.debugDescription)"
            assertionFailure(message)
            fatalError(message)
        } catch {
            let message = "[AppConfiguration] Unexpected configuration error: \(error)"
            assertionFailure(message)
            fatalError(message)
        }
    }

    static func fromInfoDictionary(_ infoDictionary: [String: Any]) throws -> AppConfiguration {
        guard let rawEnvironment = stringValue(for: "APP_ENV", in: infoDictionary), !rawEnvironment.isEmpty else {
            throw AppConfigurationError.missingEnvironment
        }
        guard let environment = AppEnvironment(rawValue: rawEnvironment.lowercased()) else {
            throw AppConfigurationError.invalidEnvironment(rawEnvironment)
        }

        let rawGoogleClientID = stringValue(for: "GIDClientID", in: infoDictionary)
        let googleClientID = (rawGoogleClientID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? rawGoogleClientID!.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return AppConfiguration(
            environment: environment,
            networkConfiguration: environment.networkConfiguration,
            googleClientID: googleClientID
        )
    }

    private static func stringValue(for key: String, in infoDictionary: [String: Any]) -> String? {
        (infoDictionary[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AppExternalLink: String, CaseIterable, Identifiable {
    case product
    case support
    case serviceTerms
    case terms
    case privacy
    case openSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .product:
            return "InhouseMaker"
        case .support:
            return "문의하기"
        case .serviceTerms:
            return "서비스 이용약관"
        case .terms:
            return "이용약관"
        case .privacy:
            return "개인정보처리방침"
        case .openSource:
            return "오픈소스 라이선스"
        }
    }

    var url: URL {
        switch self {
        case .product:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal")!
        case .support:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/support.html")!
        case .serviceTerms:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/")!
        case .terms:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/community.html")!
        case .privacy:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/privacy.html")!
        case .openSource:
            // TODO: 실제 오픈소스 고지 문서 URL로 교체한다.
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/open-source.html")!
        }
    }
}

enum AppSupportContact {
    static let emailAddress = "tjrqja014@gmail.com"
}

struct AppInfoDescriptor {
    let appName: String
    let appVersion: String
    let buildNumber: String

    static func current(bundle: Bundle = .main) -> AppInfoDescriptor {
        let appName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ) ?? (
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ) ?? "InhouseMaker"
        let appVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let buildNumber = (bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String) ?? "1"
        return AppInfoDescriptor(appName: appName, appVersion: appVersion, buildNumber: buildNumber)
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum AuthAPI {
    enum Endpoint {
        static let signUp = "/auth/signup"
        static let loginEmail = "/auth/login/email"
        static let loginApple = "/auth/login/apple"
        static let loginGoogle = "/auth/login/google"
        static let logout = "/auth/logout"
        static let refresh = "/auth/refresh"
    }

    enum Availability {
        static let supportedLoginMethodsDescription = "이 앱에서는 이메일, Apple, Google 로그인을 사용할 수 있어요."
        static let authRequiredMessage = "이 기능은 로그인 후 사용할 수 있어요. 이메일, Apple 또는 Google로 로그인해 주세요."
        static let reauthenticationMessage = "세션이 만료되어 다시 로그인이 필요해요. 이메일, Apple 또는 Google로 다시 로그인해 주세요."
    }
}

private enum LocalStoreKey {
    static let groupIDs = "local.group.ids"
    static let recentMatches = "local.recent.matches"
    static let cachedResults = "local.cached.results"
    static let savedHistoryMatchIDs = "local.history.saved.match.ids"
    static let manualAdjustDrafts = "local.manual.adjust.drafts"
    static let notifications = "local.notifications"
    static let recentSearchKeywords = "local.recent.search.keywords"
    static let guestOnboardingCompleted = "local.guest.onboarding.completed"
    static let onboardingStatus = "local.onboarding.status"
    static let recruitFilterType = "local.recruit.filter.type"
    static let teamBalancePreviewDraft = "local.team.balance.preview.draft"
    static let resultPreviewDraft = "local.result.preview.draft"
    static let notificationsEnabled = "local.notifications.enabled"
    static let profilePublic = "local.profile.public"
    static let historyPublic = "local.history.public"
    static let profileImages = "local.profile.images"
    static let blockedUsers = "local.blocked.users"
}

private enum LocalPreferenceKey: String {
    case migrationVersion = "local.persistence.migration.version"
    case onboardingStatus = "local.onboarding.status"
    case recruitFilterType = "local.recruit.filter.type"
    case teamBalancePreviewDraft = "local.team.balance.preview.draft"
    case resultPreviewDraft = "local.result.preview.draft"
    case notificationsEnabled = "local.notifications.enabled"
    case profilePublic = "local.profile.public"
    case historyPublic = "local.history.public"
}

enum LocalStoreSnapshotSource: String {
    case swiftData
    case userDefaults
}

struct LocalStoreSnapshot<Value> {
    let value: Value
    let source: LocalStoreSnapshotSource
}

enum AppModelContainerFactory {
    private static let schema = Schema([
        LocalSearchKeywordEntity.self,
        LocalRecentGroupEntity.self,
        LocalMatchRecordEntity.self,
        LocalNotificationEntity.self,
        LocalAppPreferenceEntity.self,
    ])

    static func makeContainer(inMemoryOnly: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            #if DEBUG
            print("[SwiftData] persistent container initialization failed: \(error)")
            #endif

            do {
                let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: fallbackConfiguration)
            } catch {
                fatalError("SwiftData container initialization failed: \(error)")
            }
        }
    }
}

@Model
private final class LocalSearchKeywordEntity {
    @Attribute(.unique) var normalizedKeyword: String
    var keyword: String
    var lastSearchedAt: Date

    init(keyword: String, lastSearchedAt: Date) {
        self.normalizedKeyword = keyword.normalizedSearchKey
        self.keyword = keyword
        self.lastSearchedAt = lastSearchedAt
    }
}

@Model
private final class LocalRecentGroupEntity {
    @Attribute(.unique) var groupID: String
    var groupName: String?
    var lastViewedAt: Date

    init(groupID: String, groupName: String? = nil, lastViewedAt: Date) {
        self.groupID = groupID
        self.groupName = groupName
        self.lastViewedAt = lastViewedAt
    }
}

@Model
private final class LocalMatchRecordEntity {
    @Attribute(.unique) var matchID: String
    var groupID: String?
    var groupName: String
    var trackedAt: Date
    var savedAt: Date?
    var winningTeamRawValue: String?
    var balanceRating: Int?
    var mvpUserID: String?

    init(
        matchID: String,
        groupID: String?,
        groupName: String,
        trackedAt: Date,
        savedAt: Date? = nil,
        winningTeamRawValue: String? = nil,
        balanceRating: Int? = nil,
        mvpUserID: String? = nil
    ) {
        self.matchID = matchID
        self.groupID = groupID
        self.groupName = groupName
        self.trackedAt = trackedAt
        self.savedAt = savedAt
        self.winningTeamRawValue = winningTeamRawValue
        self.balanceRating = balanceRating
        self.mvpUserID = mvpUserID
    }
}

@Model
private final class LocalNotificationEntity {
    @Attribute(.unique) var notificationID: UUID
    var title: String
    var body: String
    var createdAt: Date
    var isUnread: Bool
    var systemImageName: String

    init(
        notificationID: UUID,
        title: String,
        body: String,
        createdAt: Date,
        isUnread: Bool,
        systemImageName: String
    ) {
        self.notificationID = notificationID
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isUnread = isUnread
        self.systemImageName = systemImageName
    }
}

@Model
private final class LocalAppPreferenceEntity {
    @Attribute(.unique) var key: String
    var stringValue: String?
    var dataValue: Data?
    var updatedAt: Date

    init(key: String, stringValue: String? = nil, dataValue: Data? = nil, updatedAt: Date) {
        self.key = key
        self.stringValue = stringValue
        self.dataValue = dataValue
        self.updatedAt = updatedAt
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension String {
    var normalizedSearchKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class LocalPersistenceStore {
    private let modelContainer: ModelContainer
    private let lock = NSLock()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func migrateLegacyData(from defaults: UserDefaults) {
        lock.withLock {
            let context = ModelContext(modelContainer)

            if preferenceString(for: .migrationVersion, in: context) == "1" {
                return
            }

            let now = Date()

            let legacyGroupIDs = defaults.stringArray(forKey: LocalStoreKey.groupIDs) ?? []
            for (index, groupID) in legacyGroupIDs.enumerated() {
                let groupEntity = recentGroupEntity(for: groupID, in: context)
                    ?? LocalRecentGroupEntity(
                        groupID: groupID,
                        lastViewedAt: now.addingTimeInterval(-Double(index))
                    )
                groupEntity.lastViewedAt = now.addingTimeInterval(-Double(index))
                if groupEntity.modelContext == nil {
                    context.insert(groupEntity)
                }
            }

            let recentMatches = decodeLegacy([RecentMatchContext].self, forKey: LocalStoreKey.recentMatches, defaults: defaults) ?? []
            for recentMatch in recentMatches {
                let entity = matchRecordEntity(for: recentMatch.matchID, in: context)
                    ?? LocalMatchRecordEntity(
                        matchID: recentMatch.matchID,
                        groupID: recentMatch.groupID,
                        groupName: recentMatch.groupName,
                        trackedAt: recentMatch.createdAt
                    )
                entity.groupID = recentMatch.groupID
                entity.groupName = recentMatch.groupName
                entity.trackedAt = recentMatch.createdAt
                if entity.modelContext == nil {
                    context.insert(entity)
                }
            }

            let cachedResults = decodeLegacy([String: CachedResultMetadata].self, forKey: LocalStoreKey.cachedResults, defaults: defaults) ?? [:]
            for (matchID, metadata) in cachedResults {
                let entity = matchRecordEntity(for: matchID, in: context)
                    ?? LocalMatchRecordEntity(
                        matchID: matchID,
                        groupID: nil,
                        groupName: "최근 내전",
                        trackedAt: metadata.updatedAt
                    )
                entity.savedAt = metadata.updatedAt
                entity.winningTeamRawValue = metadata.winningTeam.rawValue
                entity.balanceRating = metadata.balanceRating
                entity.mvpUserID = metadata.mvpUserID
                if entity.modelContext == nil {
                    context.insert(entity)
                }
            }

            let notifications = decodeLegacy([NotificationEntry].self, forKey: LocalStoreKey.notifications, defaults: defaults) ?? []
            for notification in notifications {
                let entity = notificationEntity(for: notification.id, in: context)
                    ?? LocalNotificationEntity(
                        notificationID: notification.id,
                        title: notification.title,
                        body: notification.body,
                        createdAt: notification.createdAt,
                        isUnread: notification.isUnread,
                        systemImageName: notification.systemImageName
                    )
                entity.title = notification.title
                entity.body = notification.body
                entity.createdAt = notification.createdAt
                entity.isUnread = notification.isUnread
                entity.systemImageName = notification.systemImageName
                if entity.modelContext == nil {
                    context.insert(entity)
                }
            }

            if let onboardingStatus = defaults.string(forKey: LocalStoreKey.onboardingStatus) {
                setPreferenceString(onboardingStatus, for: .onboardingStatus, in: context)
            } else if let legacyFlag = defaults.object(forKey: LocalStoreKey.guestOnboardingCompleted) as? Bool {
                setPreferenceString(legacyFlag ? OnboardingStatus.completed.rawValue : OnboardingStatus.pending.rawValue, for: .onboardingStatus, in: context)
            }

            if let recruitFilterType = decodeLegacy(RecruitingPostType.self, forKey: LocalStoreKey.recruitFilterType, defaults: defaults) {
                setPreferenceCodable(recruitFilterType, for: .recruitFilterType, in: context)
            }

            if let draft = decodeLegacy(TeamBalancePreviewDraft.self, forKey: LocalStoreKey.teamBalancePreviewDraft, defaults: defaults) {
                setPreferenceCodable(draft, for: .teamBalancePreviewDraft, in: context)
            }

            if let draft = decodeLegacy(ResultPreviewDraft.self, forKey: LocalStoreKey.resultPreviewDraft, defaults: defaults) {
                setPreferenceCodable(draft, for: .resultPreviewDraft, in: context)
            }

            setPreferenceString("1", for: .migrationVersion, in: context)
            pruneRecentGroups(in: context)
            pruneMatchRecords(in: context)
            pruneNotifications(in: context)
            save(context)
        }
    }

    func storedGroupIDs(limit: Int = 12) -> [String] {
        read { context in
            var descriptor = FetchDescriptor<LocalRecentGroupEntity>(
                sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return (try? context.fetch(descriptor).map(\.groupID)) ?? []
        }
    }

    func groupName(for groupID: String) -> String? {
        read { context in
            recentGroupEntity(for: groupID, in: context)?
                .groupName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func containsGroup(id: String) -> Bool {
        read { context in
            recentGroupEntity(for: id, in: context) != nil
        }
    }

    func trackGroup(id: String, name: String? = nil) {
        write { context in
            let entity = recentGroupEntity(for: id, in: context)
                ?? LocalRecentGroupEntity(groupID: id, groupName: name, lastViewedAt: Date())
            entity.lastViewedAt = Date()
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entity.groupName = name
            }
            if entity.modelContext == nil {
                context.insert(entity)
            }
            pruneRecentGroups(in: context)
        }
    }

    func deleteGroup(id: String) {
        write { context in
            if let entity = recentGroupEntity(for: id, in: context) {
                context.delete(entity)
            }

            let descriptor = FetchDescriptor<LocalMatchRecordEntity>(
                predicate: #Predicate { $0.groupID == id }
            )
            let relatedMatchRecords = (try? context.fetch(descriptor)) ?? []
            for entity in relatedMatchRecords {
                entity.groupID = nil
            }
        }
    }

    func recentMatches(limit: Int = 12) -> [RecentMatchContext] {
        read { context in
            var descriptor = FetchDescriptor<LocalMatchRecordEntity>(
                sortBy: [SortDescriptor(\.trackedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let entities = (try? context.fetch(descriptor)) ?? []
            return entities.compactMap { entity in
                guard let groupID = entity.groupID else { return nil }
                return RecentMatchContext(
                    matchID: entity.matchID,
                    groupID: groupID,
                    groupName: entity.groupName,
                    createdAt: entity.trackedAt
                )
            }
        }
    }

    func trackMatch(_ contextValue: RecentMatchContext) {
        write { context in
            let entity = matchRecordEntity(for: contextValue.matchID, in: context)
                ?? LocalMatchRecordEntity(
                    matchID: contextValue.matchID,
                    groupID: contextValue.groupID,
                    groupName: contextValue.groupName,
                    trackedAt: contextValue.createdAt
                )
            entity.groupID = contextValue.groupID
            entity.groupName = contextValue.groupName
            entity.trackedAt = contextValue.createdAt
            if entity.modelContext == nil {
                context.insert(entity)
            }
            pruneMatchRecords(in: context)
        }
    }

    func clearRecentMatchTracking(matchID: String) {
        write { context in
            guard let entity = matchRecordEntity(for: matchID, in: context) else { return }
            entity.groupID = nil
            if entity.savedAt == nil {
                context.delete(entity)
            }
        }
    }

    func cachedResults() -> [String: CachedResultMetadata] {
        read { context in
            let descriptor = FetchDescriptor<LocalMatchRecordEntity>()
            let entities = ((try? context.fetch(descriptor)) ?? []).sorted {
                ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast)
            }
            return Dictionary(
                uniqueKeysWithValues: entities.compactMap { entity in
                    guard
                        let savedAt = entity.savedAt,
                        let winningTeamRawValue = entity.winningTeamRawValue,
                        let winningTeam = TeamSide(rawValue: winningTeamRawValue),
                        let balanceRating = entity.balanceRating,
                        let mvpUserID = entity.mvpUserID
                    else {
                        return nil
                    }

                    return (
                        entity.matchID,
                        CachedResultMetadata(
                            winningTeam: winningTeam,
                            mvpUserID: mvpUserID,
                            balanceRating: balanceRating,
                            updatedAt: savedAt
                        )
                    )
                }
            )
        }
    }

    func cacheResult(matchID: String, metadata: CachedResultMetadata) {
        write { context in
            let entity = matchRecordEntity(for: matchID, in: context)
                ?? LocalMatchRecordEntity(
                    matchID: matchID,
                    groupID: nil,
                    groupName: "최근 내전",
                    trackedAt: metadata.updatedAt
                )
            entity.savedAt = metadata.updatedAt
            entity.winningTeamRawValue = metadata.winningTeam.rawValue
            entity.balanceRating = metadata.balanceRating
            entity.mvpUserID = metadata.mvpUserID
            if entity.modelContext == nil {
                context.insert(entity)
            }
            pruneMatchRecords(in: context)
        }
    }

    func localMatchRecords() -> [LocalMatchRecord] {
        read { context in
            let descriptor = FetchDescriptor<LocalMatchRecordEntity>()
            let entities = ((try? context.fetch(descriptor)) ?? []).sorted {
                ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast)
            }
            return entities.compactMap { entity in
                guard
                    let savedAt = entity.savedAt,
                    let winningTeamRawValue = entity.winningTeamRawValue,
                    let winningTeam = TeamSide(rawValue: winningTeamRawValue),
                    let balanceRating = entity.balanceRating,
                    let mvpUserID = entity.mvpUserID
                else {
                    return nil
                }

                return LocalMatchRecord(
                    matchID: entity.matchID,
                    groupID: entity.groupID,
                    groupName: entity.groupName,
                    savedAt: savedAt,
                    winningTeam: winningTeam,
                    balanceRating: balanceRating,
                    mvpUserID: mvpUserID
                )
            }
        }
    }

    func notifications() -> [NotificationEntry] {
        read { context in
            let descriptor = FetchDescriptor<LocalNotificationEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return ((try? context.fetch(descriptor)) ?? []).map {
                NotificationEntry(
                    id: $0.notificationID,
                    title: $0.title,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    isUnread: $0.isUnread,
                    systemImageName: $0.systemImageName
                )
            }
        }
    }

    func appendNotification(title: String, body: String, symbol: String, unread: Bool = true) {
        write { context in
            context.insert(
                LocalNotificationEntity(
                    notificationID: UUID(),
                    title: title,
                    body: body,
                    createdAt: Date(),
                    isUnread: unread,
                    systemImageName: symbol
                )
            )
            pruneNotifications(in: context)
        }
    }

    func recentSearchKeywords(limit: Int = 10) -> [RecentSearchKeyword] {
        read { context in
            var descriptor = FetchDescriptor<LocalSearchKeywordEntity>(
                sortBy: [SortDescriptor(\.lastSearchedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return ((try? context.fetch(descriptor)) ?? []).map {
                RecentSearchKeyword(id: $0.normalizedKeyword, keyword: $0.keyword, searchedAt: $0.lastSearchedAt)
            }
        }
    }

    func recordRecentSearchKeyword(_ keyword: String) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return }

        write { context in
            let normalizedKeyword = trimmedKeyword.normalizedSearchKey
            let entity = searchKeywordEntity(for: normalizedKeyword, in: context)
                ?? LocalSearchKeywordEntity(keyword: trimmedKeyword, lastSearchedAt: Date())
            entity.keyword = trimmedKeyword
            entity.normalizedKeyword = normalizedKeyword
            entity.lastSearchedAt = Date()
            if entity.modelContext == nil {
                context.insert(entity)
            }
            pruneRecentSearchKeywords(in: context)
        }
    }

    func deleteRecentSearchKeyword(id: String) {
        write { context in
            guard let entity = searchKeywordEntity(for: id, in: context) else { return }
            context.delete(entity)
        }
    }

    func deleteAllRecentSearchKeywords() {
        write { context in
            let descriptor = FetchDescriptor<LocalSearchKeywordEntity>()
            let entities = (try? context.fetch(descriptor)) ?? []
            for entity in entities {
                context.delete(entity)
            }
        }
    }

    func stringPreference(for key: LocalPreferenceKey) -> String? {
        read { context in
            preferenceString(for: key, in: context)
        }
    }

    func setStringPreference(_ value: String?, for key: LocalPreferenceKey) {
        write { context in
            setPreferenceString(value, for: key, in: context)
        }
    }

    func codablePreference<T: Decodable>(_ type: T.Type, for key: LocalPreferenceKey) -> T? {
        read { context in
            guard let data = preferenceEntity(for: key, in: context)?.dataValue else { return nil }
            return try? JSONDecoder.app.decode(type, from: data)
        }
    }

    func setCodablePreference<T: Encodable>(_ value: T, for key: LocalPreferenceKey) {
        write { context in
            setPreferenceCodable(value, for: key, in: context)
        }
    }

    func clearAccountScopedData() {
        write { context in
            for entity in (try? context.fetch(FetchDescriptor<LocalRecentGroupEntity>())) ?? [] {
                context.delete(entity)
            }
            for entity in (try? context.fetch(FetchDescriptor<LocalMatchRecordEntity>())) ?? [] {
                context.delete(entity)
            }
            for entity in (try? context.fetch(FetchDescriptor<LocalNotificationEntity>())) ?? [] {
                context.delete(entity)
            }
            for entity in (try? context.fetch(FetchDescriptor<LocalSearchKeywordEntity>())) ?? [] {
                context.delete(entity)
            }
        }
    }

    private func read<T>(_ body: (ModelContext) -> T) -> T {
        lock.withLock {
            body(ModelContext(modelContainer))
        }
    }

    private func write(_ body: (ModelContext) -> Void) {
        lock.withLock {
            let context = ModelContext(modelContainer)
            body(context)
            save(context)
        }
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[SwiftData] save failed: \(error)")
            #endif
        }
    }

    private func recentGroupEntity(for groupID: String, in context: ModelContext) -> LocalRecentGroupEntity? {
        let descriptor = FetchDescriptor<LocalRecentGroupEntity>(
            predicate: #Predicate { $0.groupID == groupID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func matchRecordEntity(for matchID: String, in context: ModelContext) -> LocalMatchRecordEntity? {
        let descriptor = FetchDescriptor<LocalMatchRecordEntity>(
            predicate: #Predicate { $0.matchID == matchID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func notificationEntity(for notificationID: UUID, in context: ModelContext) -> LocalNotificationEntity? {
        let descriptor = FetchDescriptor<LocalNotificationEntity>(
            predicate: #Predicate { $0.notificationID == notificationID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func searchKeywordEntity(for normalizedKeyword: String, in context: ModelContext) -> LocalSearchKeywordEntity? {
        let descriptor = FetchDescriptor<LocalSearchKeywordEntity>(
            predicate: #Predicate { $0.normalizedKeyword == normalizedKeyword }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func preferenceEntity(for key: LocalPreferenceKey, in context: ModelContext) -> LocalAppPreferenceEntity? {
        let rawKey = key.rawValue
        let descriptor = FetchDescriptor<LocalAppPreferenceEntity>(
            predicate: #Predicate { $0.key == rawKey }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func preferenceString(for key: LocalPreferenceKey, in context: ModelContext) -> String? {
        preferenceEntity(for: key, in: context)?.stringValue
    }

    private func setPreferenceString(_ value: String?, for key: LocalPreferenceKey, in context: ModelContext) {
        let entity = preferenceEntity(for: key, in: context)
            ?? LocalAppPreferenceEntity(key: key.rawValue, updatedAt: Date())
        entity.stringValue = value
        entity.updatedAt = Date()
        if entity.modelContext == nil {
            context.insert(entity)
        }
    }

    private func setPreferenceCodable<T: Encodable>(_ value: T, for key: LocalPreferenceKey, in context: ModelContext) {
        guard let data = try? JSONEncoder.app.encode(value) else { return }
        let entity = preferenceEntity(for: key, in: context)
            ?? LocalAppPreferenceEntity(key: key.rawValue, updatedAt: Date())
        entity.dataValue = data
        entity.updatedAt = Date()
        if entity.modelContext == nil {
            context.insert(entity)
        }
    }

    private func pruneRecentGroups(in context: ModelContext, limit: Int = 12) {
        let descriptor = FetchDescriptor<LocalRecentGroupEntity>(
            sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        guard entities.count > limit else { return }
        for entity in entities.dropFirst(limit) {
            context.delete(entity)
        }
    }

    private func pruneMatchRecords(in context: ModelContext, limit: Int = 50) {
        let descriptor = FetchDescriptor<LocalMatchRecordEntity>(
            sortBy: [SortDescriptor(\.trackedAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        guard entities.count > limit else { return }
        for entity in entities.dropFirst(limit) {
            context.delete(entity)
        }
    }

    private func pruneNotifications(in context: ModelContext, limit: Int = 50) {
        let descriptor = FetchDescriptor<LocalNotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        guard entities.count > limit else { return }
        for entity in entities.dropFirst(limit) {
            context.delete(entity)
        }
    }

    private func pruneRecentSearchKeywords(in context: ModelContext, limit: Int = 10) {
        let descriptor = FetchDescriptor<LocalSearchKeywordEntity>(
            sortBy: [SortDescriptor(\.lastSearchedAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        guard entities.count > limit else { return }
        for entity in entities.dropFirst(limit) {
            context.delete(entity)
        }
    }

    private func decodeLegacy<T: Decodable>(_ type: T.Type, forKey key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.app.decode(type, from: data)
    }
}

enum OnboardingStatus: String, Codable, Equatable {
    case pending
    case completed
}

enum OnboardingStatusNormalizationSource: String, Equatable {
    case normalized
    case legacyFlag
    case restoredAuthenticatedSession
    case legacyInstallFallback
    case freshInstallDefault
}

struct OnboardingStatusNormalizationResult: Equatable {
    let status: OnboardingStatus
    let source: OnboardingStatusNormalizationSource

    var didMigrate: Bool {
        source != .normalized
    }
}

private struct LocalProfileImageCacheEntry: Codable {
    let data: Data
    let updatedAt: Date
}

final class AppLocalStore {
    private let defaults: UserDefaults
    private let persistenceStore: LocalPersistenceStore

    convenience init(defaults: UserDefaults = .standard) {
        let usesStandardDefaults = defaults === UserDefaults.standard
        let modelContainer = AppModelContainerFactory.makeContainer(
            inMemoryOnly: !usesStandardDefaults
        )
        self.init(defaults: defaults, modelContainer: modelContainer)
    }

    init(defaults: UserDefaults, modelContainer: ModelContainer) {
        self.defaults = defaults
        self.persistenceStore = LocalPersistenceStore(modelContainer: modelContainer)
        persistenceStore.migrateLegacyData(from: defaults)
    }

    var userDefaults: UserDefaults {
        defaults
    }

    var storedGroupIDs: [String] {
        storedGroupIDsSnapshot().value
    }

    func storedGroupIDsSnapshot() -> LocalStoreSnapshot<[String]> {
        let persistedGroupIDs = persistenceStore.storedGroupIDs()
        if !persistedGroupIDs.isEmpty {
            return LocalStoreSnapshot(value: persistedGroupIDs, source: .swiftData)
        }

        if let fallbackGroupIDs = defaults.stringArray(forKey: LocalStoreKey.groupIDs) {
            return LocalStoreSnapshot(value: fallbackGroupIDs, source: .userDefaults)
        }

        return LocalStoreSnapshot(value: [], source: .swiftData)
    }

    var recentMatches: [RecentMatchContext] {
        recentMatchesSnapshot().value
    }

    func recentMatchesSnapshot() -> LocalStoreSnapshot<[RecentMatchContext]> {
        let persistedRecentMatches = persistenceStore.recentMatches()
        if !persistedRecentMatches.isEmpty {
            return LocalStoreSnapshot(value: persistedRecentMatches, source: .swiftData)
        }

        if let fallbackRecentMatches = decode([RecentMatchContext].self, forKey: LocalStoreKey.recentMatches) {
            return LocalStoreSnapshot(value: fallbackRecentMatches, source: .userDefaults)
        }

        return LocalStoreSnapshot(value: [], source: .swiftData)
    }

    var cachedResults: [String: CachedResultMetadata] {
        let cachedResults = persistenceStore.cachedResults()
        return cachedResults.isEmpty ? (decode([String: CachedResultMetadata].self, forKey: LocalStoreKey.cachedResults) ?? [:]) : cachedResults
    }

    var notifications: [NotificationEntry] {
        let notifications = persistenceStore.notifications()
        return notifications.isEmpty ? (decode([NotificationEntry].self, forKey: LocalStoreKey.notifications) ?? []) : notifications
    }

    var onboardingStatus: OnboardingStatus? {
        guard let rawValue = persistenceStore.stringPreference(for: .onboardingStatus) else { return nil }
        return OnboardingStatus(rawValue: rawValue) ?? legacyOnboardingStatus
    }

    var hasCompletedOnboarding: Bool {
        onboardingStatus == .completed
    }

    var hasCompletedGuestOnboarding: Bool {
        hasCompletedOnboarding
    }

    var recruitFilterType: RecruitingPostType {
        persistenceStore.codablePreference(RecruitingPostType.self, for: .recruitFilterType)
            ?? decode(RecruitingPostType.self, forKey: LocalStoreKey.recruitFilterType)
            ?? .memberRecruit
    }

    var teamBalancePreviewDraft: TeamBalancePreviewDraft {
        persistenceStore.codablePreference(TeamBalancePreviewDraft.self, for: .teamBalancePreviewDraft)
            ?? decode(TeamBalancePreviewDraft.self, forKey: LocalStoreKey.teamBalancePreviewDraft)
            ?? .defaultValue
    }

    var resultPreviewDraft: ResultPreviewDraft {
        persistenceStore.codablePreference(ResultPreviewDraft.self, for: .resultPreviewDraft)
            ?? decode(ResultPreviewDraft.self, forKey: LocalStoreKey.resultPreviewDraft)
            ?? .defaultValue(from: teamBalancePreviewDraft)
    }

    var localMatchRecords: [LocalMatchRecord] {
        let records = persistenceStore.localMatchRecords()
        guard !records.isEmpty else {
            let contexts = Dictionary(uniqueKeysWithValues: recentMatches.map { ($0.matchID, $0) })
            return cachedResults
                .map { matchID, metadata in
                    let context = contexts[matchID]
                    return LocalMatchRecord(
                        matchID: matchID,
                        groupID: context?.groupID,
                        groupName: context?.groupName ?? "최근 내전",
                        savedAt: metadata.updatedAt,
                        winningTeam: metadata.winningTeam,
                        balanceRating: metadata.balanceRating,
                        mvpUserID: metadata.mvpUserID
                    )
                }
                .sorted { $0.savedAt > $1.savedAt }
        }
        return records
    }

    var savedHistoryMatchIDs: Set<String> {
        if let encodedIDs = decode([String].self, forKey: LocalStoreKey.savedHistoryMatchIDs) {
            return Set(encodedIDs.map(Self.normalizedHistoryMatchID).filter { !$0.isEmpty })
        }

        return Set((defaults.stringArray(forKey: LocalStoreKey.savedHistoryMatchIDs) ?? []).map(Self.normalizedHistoryMatchID).filter { !$0.isEmpty })
    }

    var manualAdjustDrafts: [String: ManualAdjustDraft] {
        decode([String: ManualAdjustDraft].self, forKey: LocalStoreKey.manualAdjustDrafts) ?? [:]
    }

    var recentSearchKeywords: [RecentSearchKeyword] {
        let keywords = persistenceStore.recentSearchKeywords()
        return keywords.isEmpty ? (decode([RecentSearchKeyword].self, forKey: LocalStoreKey.recentSearchKeywords) ?? []) : keywords
    }

    var notificationsEnabled: Bool {
        boolPreference(
            preferenceKey: .notificationsEnabled,
            defaultsKey: LocalStoreKey.notificationsEnabled,
            defaultValue: true
        )
    }

    var isProfilePublic: Bool {
        boolPreference(
            preferenceKey: .profilePublic,
            defaultsKey: LocalStoreKey.profilePublic,
            defaultValue: true
        )
    }

    var isHistoryPublic: Bool {
        boolPreference(
            preferenceKey: .historyPublic,
            defaultsKey: LocalStoreKey.historyPublic,
            defaultValue: true
        )
    }

    var blockedUsers: [BlockedUser] {
        (decode([BlockedUser].self, forKey: LocalStoreKey.blockedUsers) ?? [])
            .sorted { $0.blockedAt > $1.blockedAt }
    }

    func setBlockedUsers(_ users: [BlockedUser]) {
        let sanitizedUsers = users.reduce(into: [String: BlockedUser]()) { partialResult, user in
            let normalizedUserID = user.userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedUserID.isEmpty else { return }
            partialResult[normalizedUserID] = BlockedUser(
                userID: normalizedUserID,
                nickname: user.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "사용자" : user.nickname,
                blockedAt: user.blockedAt
            )
        }
        save(
            sanitizedUsers.values.sorted { $0.blockedAt > $1.blockedAt },
            forKey: LocalStoreKey.blockedUsers
        )
    }

    @discardableResult
    func blockUser(_ target: BlockUserTarget) -> BlockedUser {
        let normalizedUserID = target.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else {
            return BlockedUser(userID: "", nickname: "사용자", blockedAt: Date())
        }
        let normalizedNickname = target.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let blockedUser = BlockedUser(
            userID: normalizedUserID,
            nickname: normalizedNickname.isEmpty ? "사용자" : normalizedNickname,
            blockedAt: Date()
        )
        var current = blockedUsers.filter { $0.userID != normalizedUserID }
        current.insert(blockedUser, at: 0)
        setBlockedUsers(current)
        return blockedUser
    }

    func unblockUser(userID: String) {
        guard let normalizedUserID = normalizedUserID(userID) else { return }
        setBlockedUsers(blockedUsers.filter { $0.userID != normalizedUserID })
    }

    func isUserBlocked(_ userID: String?) -> Bool {
        guard let normalizedUserID = normalizedUserID(userID) else { return false }
        return blockedUsers.contains { $0.userID == normalizedUserID }
    }

    func localProfileImageData(for userID: String) -> Data? {
        guard let normalizedUserID = normalizedUserID(userID) else { return nil }
        return localProfileImages[normalizedUserID]?.data
    }

    func saveLocalProfileImage(data: Data, for userID: String) {
        guard let normalizedUserID = normalizedUserID(userID) else { return }
        var current = localProfileImages
        current[normalizedUserID] = LocalProfileImageCacheEntry(data: data, updatedAt: Date())
        save(current, forKey: LocalStoreKey.profileImages)
    }

    func clearLocalProfileImage(for userID: String) {
        guard let normalizedUserID = normalizedUserID(userID) else { return }
        var current = localProfileImages
        current.removeValue(forKey: normalizedUserID)
        save(current, forKey: LocalStoreKey.profileImages)
    }

    func groupName(for groupID: String) -> String? {
        persistenceStore.groupName(for: groupID)
    }

    func containsGroup(id: String) -> Bool {
        persistenceStore.containsGroup(id: id)
            || storedGroupIDs.contains(id)
    }

    func trackGroup(id: String, name: String? = nil) {
        persistenceStore.trackGroup(id: id, name: name)
        var current = storedGroupIDs.filter { $0 != id }
        current.insert(id, at: 0)
        defaults.set(Array(current.prefix(12)), forKey: LocalStoreKey.groupIDs)
    }

    func removeGroup(id: String) {
        persistenceStore.deleteGroup(id: id)
        defaults.set(storedGroupIDs.filter { $0 != id }, forKey: LocalStoreKey.groupIDs)
        let filteredRecentMatches = recentMatches.filter { $0.groupID != id }
        save(filteredRecentMatches, forKey: LocalStoreKey.recentMatches)
    }

    func trackMatch(_ context: RecentMatchContext) {
        persistenceStore.trackMatch(context)
        var current = recentMatches.filter { $0.matchID != context.matchID }
        current.insert(context, at: 0)
        save(Array(current.prefix(12)), forKey: LocalStoreKey.recentMatches)
    }

    func clearRecentMatch(matchID: String) {
        persistenceStore.clearRecentMatchTracking(matchID: matchID)
        let filteredRecentMatches = recentMatches.filter { $0.matchID != matchID }
        save(filteredRecentMatches, forKey: LocalStoreKey.recentMatches)
        clearManualAdjustDraft(matchID: matchID)
    }

    func cacheResult(matchID: String, metadata: CachedResultMetadata) {
        persistenceStore.cacheResult(matchID: matchID, metadata: metadata)
        var current = cachedResults
        current[matchID] = metadata
        save(current, forKey: LocalStoreKey.cachedResults)
    }

    func isHistorySaved(matchID: String) -> Bool {
        savedHistoryMatchIDs.contains(Self.normalizedHistoryMatchID(matchID))
    }

    @discardableResult
    func setHistorySaved(matchID: String, isSaved: Bool) -> Set<String> {
        let normalizedMatchID = Self.normalizedHistoryMatchID(matchID)
        guard !normalizedMatchID.isEmpty else { return savedHistoryMatchIDs }

        var current = savedHistoryMatchIDs
        if isSaved {
            current.insert(normalizedMatchID)
        } else {
            current.remove(normalizedMatchID)
        }
        save(Array(current).sorted(), forKey: LocalStoreKey.savedHistoryMatchIDs)
        debugHistorySaved("action=toggle matchId=\(normalizedMatchID) saved=\(isSaved)")
        return current
    }

    @discardableResult
    func toggleHistorySaved(matchID: String) -> Set<String> {
        let normalizedMatchID = Self.normalizedHistoryMatchID(matchID)
        let nextValue = !savedHistoryMatchIDs.contains(normalizedMatchID)
        return setHistorySaved(matchID: normalizedMatchID, isSaved: nextValue)
    }

    func manualAdjustDraft(matchID: String) -> ManualAdjustDraft? {
        manualAdjustDrafts[matchID]
    }

    func saveManualAdjustDraft(matchID: String, draft: ManualAdjustDraft) {
        var current = manualAdjustDrafts
        current[matchID] = draft
        save(current, forKey: LocalStoreKey.manualAdjustDrafts)
    }

    func clearManualAdjustDraft(matchID: String) {
        var current = manualAdjustDrafts
        current.removeValue(forKey: matchID)
        save(current, forKey: LocalStoreKey.manualAdjustDrafts)
    }

    func appendNotification(title: String, body: String, symbol: String, unread: Bool = true) {
        persistenceStore.appendNotification(title: title, body: body, symbol: symbol, unread: unread)
        var current = decode([NotificationEntry].self, forKey: LocalStoreKey.notifications) ?? []
        current.insert(
            NotificationEntry(
                id: UUID(),
                title: title,
                body: body,
                createdAt: Date(),
                isUnread: unread,
                systemImageName: symbol
            ),
            at: 0
        )
        save(Array(current.prefix(50)), forKey: LocalStoreKey.notifications)
    }

    func resolveOnboardingStatus(
        hasAuthenticatedSession: Bool
    ) -> OnboardingStatusNormalizationResult {
        if hasAuthenticatedSession {
            if onboardingStatus == .completed {
                return OnboardingStatusNormalizationResult(status: .completed, source: .normalized)
            }

            setOnboardingStatus(.completed)
            return OnboardingStatusNormalizationResult(
                status: .completed,
                source: .restoredAuthenticatedSession
            )
        }

        if let onboardingStatus {
            return OnboardingStatusNormalizationResult(status: onboardingStatus, source: .normalized)
        }

        if let legacyFlag = defaults.object(forKey: LocalStoreKey.guestOnboardingCompleted) as? Bool {
            let normalizedStatus: OnboardingStatus = legacyFlag ? .completed : .pending
            setOnboardingStatus(normalizedStatus)
            return OnboardingStatusNormalizationResult(status: normalizedStatus, source: .legacyFlag)
        }

        let normalizedStatus: OnboardingStatus
        let source: OnboardingStatusNormalizationSource

        if hasAuthenticatedSession {
            normalizedStatus = .completed
            source = .restoredAuthenticatedSession
        } else if hasLegacyUsageData {
            normalizedStatus = .completed
            source = .legacyInstallFallback
        } else {
            normalizedStatus = .pending
            source = .freshInstallDefault
        }

        setOnboardingStatus(normalizedStatus)
        return OnboardingStatusNormalizationResult(status: normalizedStatus, source: source)
    }

    func setOnboardingStatus(_ status: OnboardingStatus) {
        persistenceStore.setStringPreference(status.rawValue, for: .onboardingStatus)
        defaults.set(status.rawValue, forKey: LocalStoreKey.onboardingStatus)
        defaults.set(status == .completed, forKey: LocalStoreKey.guestOnboardingCompleted)
    }

    func setGuestOnboardingCompleted(_ completed: Bool) {
        setOnboardingStatus(completed ? .completed : .pending)
    }

    func setRecruitFilterType(_ type: RecruitingPostType) {
        persistenceStore.setCodablePreference(type, for: .recruitFilterType)
        save(type, forKey: LocalStoreKey.recruitFilterType)
    }

    func setTeamBalancePreviewDraft(_ draft: TeamBalancePreviewDraft) {
        persistenceStore.setCodablePreference(draft, for: .teamBalancePreviewDraft)
        save(draft, forKey: LocalStoreKey.teamBalancePreviewDraft)
    }

    func setResultPreviewDraft(_ draft: ResultPreviewDraft) {
        persistenceStore.setCodablePreference(draft, for: .resultPreviewDraft)
        save(draft, forKey: LocalStoreKey.resultPreviewDraft)
    }

    func recordRecentSearchKeyword(_ keyword: String) {
        persistenceStore.recordRecentSearchKeyword(keyword)
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return }
        var current = recentSearchKeywords.filter { $0.id != trimmedKeyword.normalizedSearchKey }
        current.insert(
            RecentSearchKeyword(
                id: trimmedKeyword.normalizedSearchKey,
                keyword: trimmedKeyword,
                searchedAt: Date()
            ),
            at: 0
        )
        save(Array(current.prefix(10)), forKey: LocalStoreKey.recentSearchKeywords)
    }

    func deleteRecentSearchKeyword(id: String) {
        persistenceStore.deleteRecentSearchKeyword(id: id)
        let nextValue = recentSearchKeywords.filter { $0.id != id }
        save(nextValue, forKey: LocalStoreKey.recentSearchKeywords)
    }

    func clearRecentSearchKeywords() {
        persistenceStore.deleteAllRecentSearchKeywords()
        defaults.removeObject(forKey: LocalStoreKey.recentSearchKeywords)
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        persistenceStore.setStringPreference(isEnabled ? "true" : "false", for: .notificationsEnabled)
        defaults.set(isEnabled, forKey: LocalStoreKey.notificationsEnabled)
    }

    func setProfilePublic(_ isEnabled: Bool) {
        persistenceStore.setStringPreference(isEnabled ? "true" : "false", for: .profilePublic)
        defaults.set(isEnabled, forKey: LocalStoreKey.profilePublic)
    }

    func setHistoryPublic(_ isEnabled: Bool) {
        persistenceStore.setStringPreference(isEnabled ? "true" : "false", for: .historyPublic)
        defaults.set(isEnabled, forKey: LocalStoreKey.historyPublic)
    }

    func clearAccountScopedData() {
        persistenceStore.clearAccountScopedData()
        [
            LocalStoreKey.groupIDs,
            LocalStoreKey.recentMatches,
            LocalStoreKey.cachedResults,
            LocalStoreKey.savedHistoryMatchIDs,
            LocalStoreKey.manualAdjustDrafts,
            LocalStoreKey.notifications,
            LocalStoreKey.recentSearchKeywords,
            LocalStoreKey.recruitFilterType,
            LocalStoreKey.teamBalancePreviewDraft,
            LocalStoreKey.resultPreviewDraft,
            LocalStoreKey.profileImages,
            LocalStoreKey.blockedUsers,
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder.app.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.app.decode(type, from: data)
    }

    private var localProfileImages: [String: LocalProfileImageCacheEntry] {
        decode([String: LocalProfileImageCacheEntry].self, forKey: LocalStoreKey.profileImages) ?? [:]
    }

    private var legacyOnboardingStatus: OnboardingStatus? {
        guard let rawValue = defaults.string(forKey: LocalStoreKey.onboardingStatus) else { return nil }
        return OnboardingStatus(rawValue: rawValue)
    }

    private func normalizedUserID(_ value: String?) -> String? {
        guard let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedValue.isEmpty else {
            return nil
        }
        return normalizedValue
    }

    private func boolPreference(
        preferenceKey: LocalPreferenceKey,
        defaultsKey: String,
        defaultValue: Bool
    ) -> Bool {
        guard let rawValue = persistenceStore.stringPreference(for: preferenceKey) else {
            if defaults.object(forKey: defaultsKey) != nil {
                return defaults.bool(forKey: defaultsKey)
            }
            return defaultValue
        }
        switch rawValue.lowercased() {
        case "true": return true
        case "false": return false
        default: return defaultValue
        }
    }

    private var hasLegacyUsageData: Bool {
        [
            LocalStoreKey.groupIDs,
            LocalStoreKey.recentMatches,
            LocalStoreKey.cachedResults,
            LocalStoreKey.savedHistoryMatchIDs,
            LocalStoreKey.manualAdjustDrafts,
            LocalStoreKey.notifications,
            LocalStoreKey.recentSearchKeywords,
            LocalStoreKey.recruitFilterType,
            LocalStoreKey.teamBalancePreviewDraft,
            LocalStoreKey.resultPreviewDraft,
        ].contains { defaults.object(forKey: $0) != nil }
    }

    private static func normalizedHistoryMatchID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func debugHistorySaved(_ message: String) {
        #if DEBUG
        print("[HistorySavedDebug] \(message)")
        #endif
    }
}

actor TokenStore {
    private let service: String
    private let account: String
    private var cachedTokens: AuthTokens?

    init(service: String = "com.hwb.InhouseIOS.token", account: String = "session") {
        self.service = service
        self.account = account
    }

    func loadTokens() -> AuthTokens? {
        if let cachedTokens {
            return cachedTokens
        }

        guard let data = readKeychain() else { return nil }
        let tokens = try? JSONDecoder.app.decode(AuthTokens.self, from: data)
        cachedTokens = tokens
        return tokens
    }

    func save(tokens: AuthTokens) {
        cachedTokens = tokens
        guard let data = try? JSONEncoder.app.encode(tokens) else { return }
        writeKeychain(data: data)
    }

    func clear() {
        cachedTokens = nil
        deleteKeychain()
    }

    private func readKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeKeychain(data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
        ]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var item = query
            item[kSecValueData] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func deleteKeychain() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum APIClientError: Error {
    case invalidResponse
    case unauthorized
    case emptyBody
    case invalidURL
}

struct ServerErrorResponse: Decodable {
    let statusCode: Int
    let code: String?
    let provider: String?
    let message: MessageContainer
    let timestamp: String
    let path: String
    let details: [String: JSONValue]?

    struct MessageContainer: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let list = try? container.decode([String].self) {
                value = list.joined(separator: "\n")
            } else {
                value = "알 수 없는 오류가 발생했습니다."
            }
        }
    }
}

final class APIClient {
    private let configuration: AppConfiguration
    private let session: URLSession
    private let tokenStore: TokenStore
    private let inFlightGetRequests = InFlightGETRequestStore()

    init(
        configuration: AppConfiguration,
        tokenStore: TokenStore,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
    }

    func send<Response: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresAuth: Bool = true,
        retryOnUnauthorized: Bool = true
    ) async throws -> Response {
        let request = try await makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            headers: headers,
            requiresAuth: requiresAuth
        )
        debugLogRequest(request)
        let (data, response) = try await dataForRequest(request, path: path, method: method)
        return try await decode(
            data: data,
            response: response,
            originalRequest: (path, method, queryItems, body, headers, requiresAuth),
            retryOnUnauthorized: retryOnUnauthorized
        )
    }

    func sendWithoutBody<Response: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: nil,
            requiresAuth: requiresAuth
        )
    }

    func encodedBody<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder.app.encode(value)
    }

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        body: Data?,
        headers: [String: String],
        requiresAuth: Bool
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL.appending(path: path), resolvingAgainstBaseURL: true) else {
            assertionFailure(
                "[APIClient] Failed to resolve request URL. baseURL=\(configuration.baseURL.absoluteString) path=\(path)"
            )
            throw APIClientError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            assertionFailure(
                "[APIClient] Failed to build request URL. baseURL=\(configuration.baseURL.absoluteString) path=\(path)"
            )
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.timeoutInterval = 30
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if requiresAuth, let accessToken = await tokenStore.loadTokens()?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func dataForRequest(
        _ request: URLRequest,
        path: String,
        method: HTTPMethod
    ) async throws -> (Data, URLResponse) {
        guard method == .get, let dedupKey = dedupKey(for: request) else {
            return try await session.data(for: request)
        }

        if let existingTask = await inFlightGetRequests.task(for: dedupKey) {
            debugLogDedupBlocked(endpoint: debugEndpoint(for: request.url, fallbackPath: path))
            return try await existingTask.value
        }

        let task = Task { try await session.data(for: request) }
        await inFlightGetRequests.store(task: task, for: dedupKey)
        do {
            let result = try await task.value
            await inFlightGetRequests.removeTask(for: dedupKey)
            return result
        } catch {
            await inFlightGetRequests.removeTask(for: dedupKey)
            throw error
        }
    }

    private func decode<Response: Decodable>(
        data: Data,
        response: URLResponse,
        originalRequest: (path: String, method: HTTPMethod, queryItems: [URLQueryItem], body: Data?, headers: [String: String], requiresAuth: Bool),
        retryOnUnauthorized: Bool
    ) async throws -> Response {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        debugLogResponse(path: originalRequest.path, statusCode: httpResponse.statusCode, data: data)

        switch httpResponse.statusCode {
        case 200 ... 299:
            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }
            do {
                let decoded = try JSONDecoder.app.decode(Response.self, from: data)
                debugLogDecodeSuccess(path: originalRequest.path, responseType: Response.self)
                return decoded
            } catch {
                debugLogDecodeFailure(path: originalRequest.path, data: data, error: error)
                throw error
            }
        case 401 where retryOnUnauthorized && originalRequest.requiresAuth:
            try await refreshTokens()
            return try await send(
                path: originalRequest.path,
                method: originalRequest.method,
                queryItems: originalRequest.queryItems,
                body: originalRequest.body,
                headers: originalRequest.headers,
                requiresAuth: originalRequest.requiresAuth,
                retryOnUnauthorized: false
            )
        default:
            throw mapError(
                data: data,
                statusCode: httpResponse.statusCode,
                path: originalRequest.path,
                method: originalRequest.method
            )
        }
    }

    private func refreshTokens() async throws {
        guard let refreshToken = await tokenStore.loadTokens()?.refreshToken else {
            await tokenStore.clear()
            throw UserFacingError.authRequiredFallback()
        }
        do {
            let response: AuthTokensDTO = try await send(
                path: AuthAPI.Endpoint.refresh,
                method: .post,
                body: try encodedBody(RefreshTokenRequestDTO(refreshToken: refreshToken)),
                requiresAuth: false,
                retryOnUnauthorized: false
            )
            await tokenStore.save(tokens: response.toDomain())
        } catch let error as UserFacingError {
            if error.statusCode == 401 || error.requiresAuthentication || error.serverContractCode == .invalidCredentials {
                await tokenStore.clear()
                throw UserFacingError.authRequiredFallback()
            }
            throw error
        } catch APIClientError.unauthorized {
            await tokenStore.clear()
            throw UserFacingError.authRequiredFallback()
        } catch {
            throw error
        }
    }

    private func mapError(data: Data, statusCode: Int, path: String, method: HTTPMethod) -> UserFacingError {
        if let serverError = try? JSONDecoder.app.decode(ServerErrorResponse.self, from: data) {
            let mappedError = UserFacingError(
                title: statusCode == 401 ? "인증 오류" : "서버 오류",
                message: serverError.message.value,
                code: serverError.code,
                provider: serverError.provider,
                statusCode: serverError.statusCode,
                details: serverError.details,
                endpoint: path,
                requestMethod: method.rawValue
            ).serverContractMapped
            debugLogMappedError(
                path: path,
                method: method,
                rawCode: serverError.code,
                rawMessage: serverError.message.value,
                error: mappedError
            )
            return mappedError
        }
        let mappedError = UserFacingError(
            title: statusCode == 401 ? "인증 오류" : "네트워크 오류",
            message: "요청 처리 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.",
            code: statusCode == 429 ? "RATE_LIMITED" : nil,
            statusCode: statusCode,
            endpoint: path,
            requestMethod: method.rawValue
        ).serverContractMapped
        debugLogMappedError(path: path, method: method, error: mappedError)
        return mappedError
    }

    private func debugLogRequest(_ request: URLRequest) {
#if DEBUG
        guard let url = request.url, shouldDebugLog(path: url.path) else { return }
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        print("[APIClient] request \(request.httpMethod ?? "GET") \(url.absoluteString)")
        print("[APIClient] requestBody \(body)")
#endif
    }

    private func debugLogResponse(path: String, statusCode: Int, data: Data) {
#if DEBUG
        guard shouldDebugLog(path: path) else { return }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        print("[APIClient] response \(path) status=\(statusCode)")
        print("[APIClient] responseBody \(body)")
#endif
    }

    private func debugLogDecodeSuccess<Response: Decodable>(path: String, responseType: Response.Type) {
#if DEBUG
        guard shouldDebugLog(path: path) else { return }
        print("[APIClient] decodeSuccess \(path) type=\(String(describing: responseType))")
#endif
    }

    private func debugLogDecodeFailure(path: String, data: Data, error: Error) {
#if DEBUG
        guard shouldDebugLog(path: path) else { return }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        print("[APIClient] decodeError \(path) error=\(error)")
        if let summary = decodingErrorSummary(error) {
            print("[APIClient] decodeErrorField \(path) \(summary)")
        }
        print("[APIClient] decodeErrorBody \(body)")
#endif
    }

    private func debugLogDedupBlocked(endpoint: String) {
#if DEBUG
        print("[APIClient] dedup blocked endpoint=\(endpoint)")
#endif
    }

    private func debugLogMappedError(
        path: String,
        method: HTTPMethod,
        rawCode: String? = nil,
        rawMessage: String? = nil,
        error: UserFacingError
    ) {
#if DEBUG
        guard shouldDebugLog(path: path) else { return }
        print(
            "[ErrorMapper] endpoint=\(path) method=\(method.rawValue) rawCode=\(rawCode ?? error.code ?? "nil") rawMessage=\(rawMessage ?? "nil") mappedMessage=\(error.message)"
        )
        print(
            "[APIClient] mappedError \(path) title=\(error.title) code=\(error.code ?? "nil") status=\(error.statusCode.map(String.init) ?? "nil") message=\(error.message)"
        )
#endif
    }

    private func shouldDebugLog(path: String) -> Bool {
        path == AuthAPI.Endpoint.signUp
            || path == AuthAPI.Endpoint.loginEmail
            || path == AuthAPI.Endpoint.loginApple
            || path == AuthAPI.Endpoint.loginGoogle
            || path == "/me"
            || path == "/me/profile-image"
            || path == "/users"
            || path == "/users/search"
            || path.hasPrefix("/users/")
            || path == "/groups"
            || path.hasPrefix("/groups/")
            || path.hasPrefix("/matches/")
            || path == "/recruiting-posts"
            || path.hasPrefix("/recruiting-posts/")
            || path == "/reports"
            || path == "/blocks"
            || path.hasPrefix("/blocks/")
            || path.hasSuffix("/power-profile")
            || path.hasSuffix("/inhouse-history")
            || path.hasPrefix("/riot-accounts")
    }

    private func dedupKey(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        return "\(request.httpMethod ?? HTTPMethod.get.rawValue) \(url.absoluteString) auth=\(authorization)"
    }

    private func debugEndpoint(for url: URL?, fallbackPath: String) -> String {
        guard let url else { return fallbackPath }
        if let query = url.query, !query.isEmpty {
            return "\(url.path)?\(query)"
        }
        return url.path
    }

    private func decodingErrorSummary(_ error: Error) -> String? {
        guard let decodingError = error as? DecodingError else { return nil }
        switch decodingError {
        case let .typeMismatch(type, context):
            return "kind=typeMismatch type=\(type) path=\(formatCodingPath(context.codingPath)) description=\(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "kind=valueNotFound type=\(type) path=\(formatCodingPath(context.codingPath)) description=\(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "kind=keyNotFound key=\(key.stringValue) path=\(formatCodingPath(context.codingPath)) description=\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "kind=dataCorrupted path=\(formatCodingPath(context.codingPath)) description=\(context.debugDescription)"
        @unknown default:
            return "kind=unknown"
        }
    }

    private func formatCodingPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath.map { key in
            if let intValue = key.intValue {
                return "[\(intValue)]"
            }
            return key.stringValue
        }
        .joined(separator: ".")
    }
}

private actor InFlightGETRequestStore {
    private var tasks: [String: Task<(Data, URLResponse), Error>] = [:]

    func task(for key: String) -> Task<(Data, URLResponse), Error>? {
        tasks[key]
    }

    func store(task: Task<(Data, URLResponse), Error>, for key: String) {
        tasks[key] = task
    }

    func removeTask(for key: String) {
        tasks.removeValue(forKey: key)
    }
}

struct EmptyResponse: Decodable {}

extension JSONEncoder {
    static let app: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let app: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.full.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter.simple.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return decoder
    }()
}

extension ISO8601DateFormatter {
    static let full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let simple: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case let .object(value): return value.map { "\($0.key): \($0.value.stringValue)" }.joined(separator: ", ")
        case let .array(value): return value.map(\.stringValue).joined(separator: ", ")
        case .null: return ""
        }
    }
}

// MARK: - DTOs

struct AuthUserDTO: Codable {
    let id: String
    let email: String
    let nickname: String
    let provider: String
    let status: AuthenticatedUserStatus
}

struct AuthTokensDTO: Codable {
    let user: AuthUserDTO
    let accessToken: String
    let refreshToken: String

    func toDomain() -> AuthTokens {
        AuthTokens(
            user: AuthUser(
                id: user.id,
                email: user.email,
                nickname: user.nickname,
                provider: AuthProvider(serverValue: user.provider),
                status: user.status
            ),
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
}

struct AppleLoginRequestDTO: Encodable {
    let identityToken: String
}

struct GoogleLoginRequestDTO: Encodable {
    let identityToken: String
}

struct EmailSignUpRequestDTO: Encodable {
    let email: String
    let password: String
    let nickname: String
}

struct EmailLoginRequestDTO: Encodable {
    let email: String
    let password: String
}

struct LogoutRequestDTO: Encodable {
    let refreshToken: String?
}

struct RefreshTokenRequestDTO: Encodable {
    let refreshToken: String
}

private struct LossyDecodableList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []

        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                values.append(value)
            } else {
                _ = try? container.decode(JSONValue.self)
            }
        }

        elements = values
    }
}

struct ProfileTopChampionDTO: Codable {
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

    private enum CodingKeys: String, CodingKey {
        case championId
        case championID
        case championIdSnake = "champion_id"
        case championKey
        case key
        case championKeySnake = "champion_key"
        case championName
        case name
        case championNameSnake = "champion_name"
        case games
        case gamesPlayed
        case matchCount
        case wins
        case losses
        case winRate
        case winRateSnake = "win_rate"
        case kills
        case deaths
        case assists
        case kda
        case lastPlayedAtSnake = "last_played_at"
        case lastPlayedAt
    }

    init(
        championId: Int? = nil,
        championKey: String,
        championName: String,
        games: Int,
        wins: Int,
        losses: Int,
        winRate: Double,
        kills: Double,
        deaths: Double,
        assists: Double,
        kda: Double? = nil,
        lastPlayedAt: Date? = nil
    ) {
        self.championId = championId
        self.championKey = championKey
        self.championName = championName
        self.games = games
        self.wins = wins
        self.losses = losses
        self.winRate = winRate
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.kda = kda
        self.lastPlayedAt = lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        championId = Self.decodeLossyInt(from: container, forKeys: [.championId, .championID, .championIdSnake])
        championKey = Self.decodeLossyString(from: container, forKeys: [.championKey, .championKeySnake, .key]) ?? ""
        championName = Self.decodeLossyString(from: container, forKeys: [.championName, .championNameSnake, .name]) ?? ""
        games = max(Self.decodeLossyInt(from: container, forKeys: [.games, .gamesPlayed, .matchCount]) ?? 0, 0)
        wins = max(Self.decodeLossyInt(from: container, forKeys: [.wins]) ?? 0, 0)
        losses = max(Self.decodeLossyInt(from: container, forKeys: [.losses]) ?? 0, 0)
        winRate = Self.decodeLossyDouble(from: container, forKeys: [.winRate, .winRateSnake]) ?? 0
        kills = Self.decodeLossyDouble(from: container, forKeys: [.kills]) ?? 0
        deaths = Self.decodeLossyDouble(from: container, forKeys: [.deaths]) ?? 0
        assists = Self.decodeLossyDouble(from: container, forKeys: [.assists]) ?? 0
        kda = Self.decodeLossyDouble(from: container, forKeys: [.kda])
        lastPlayedAt = Self.decodeLossyDate(from: container, forKeys: [.lastPlayedAt, .lastPlayedAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(championId, forKey: .championId)
        try container.encode(championKey, forKey: .championKey)
        try container.encode(championName, forKey: .championName)
        try container.encode(games, forKey: .games)
        try container.encode(wins, forKey: .wins)
        try container.encode(losses, forKey: .losses)
        try container.encode(winRate, forKey: .winRate)
        try container.encode(kills, forKey: .kills)
        try container.encode(deaths, forKey: .deaths)
        try container.encode(assists, forKey: .assists)
        try container.encodeIfPresent(kda, forKey: .kda)
        try container.encodeIfPresent(lastPlayedAt, forKey: .lastPlayedAt)
    }

    func toDomain() -> ProfileTopChampion? {
        let normalizedKey = championKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = championName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty || !normalizedName.isEmpty else { return nil }

        return ProfileTopChampion(
            championId: championId,
            championKey: normalizedKey,
            championName: normalizedName,
            games: games,
            wins: wins,
            losses: losses,
            winRate: winRate,
            kills: kills,
            deaths: deaths,
            assists: assists,
            kda: kda,
            lastPlayedAt: lastPlayedAt
        )
    }

    private static func decodeLossyInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return Int(value.rounded())
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func decodeLossyDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func decodeLossyString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
        }
        return nil
    }

    private static func decodeLossyDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Date? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Date.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

struct ProfileTopChampionAggregationDTO: Codable {
    let status: ChampionAggregationStatus?
    let reason: String?
    let message: String?
    let syncCoverageSummary: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case reason
        case message
        case serverMessage
        case syncCoverageSummary
        case coverageSummary
        case syncStatusSummary
    }

    init(
        status: ChampionAggregationStatus? = nil,
        reason: String? = nil,
        message: String? = nil,
        syncCoverageSummary: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.message = message
        self.syncCoverageSummary = syncCoverageSummary
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let value = try? container.decode(String.self) {
                self.init(status: ChampionAggregationStatus(serverValue: value))
                return
            }
            if let value = try? container.decode(Bool.self) {
                self.init(status: value ? .ready : .connectedEmpty)
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: Self.decodeLossyStatus(from: container, forKeys: [.status]),
            reason: Self.decodeLossyString(from: container, forKeys: [.reason]),
            message: Self.decodeLossyString(from: container, forKeys: [.message, .serverMessage]),
            syncCoverageSummary: Self.decodeLossyString(
                from: container,
                forKeys: [.syncCoverageSummary, .coverageSummary, .syncStatusSummary]
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        if hasSupplementaryMetadata {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(reason, forKey: .reason)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encodeIfPresent(syncCoverageSummary, forKey: .syncCoverageSummary)
            return
        }

        var container = encoder.singleValueContainer()
        try container.encode(status?.debugValue)
    }

    var hasSupplementaryMetadata: Bool {
        reason != nil || message != nil || syncCoverageSummary != nil
    }

    func toDomain() -> ProfileTopChampionAggregation {
        ProfileTopChampionAggregation(
            status: status,
            reason: reason,
            message: message,
            syncCoverageSummary: syncCoverageSummary
        )
    }

    private static func decodeLossyStatus(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> ChampionAggregationStatus? {
        for key in keys {
            if let value = try? container.decodeIfPresent(ChampionAggregationStatus.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return ChampionAggregationStatus(serverValue: value)
            }
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value ? .ready : .connectedEmpty
            }
        }
        return nil
    }

    private static func decodeLossyString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }
        return nil
    }
}

struct UserProfileDTO: Codable {
    let id: String
    let email: String
    let nickname: String
    let profileImageURL: URL?
    let profileImageUpdatedAt: Date?
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let isFillAvailable: Bool
    let styleTags: [String]
    let mannerScore: Double
    let noshowCount: Int
    let topChampions: [ProfileTopChampionDTO]?
    let topChampionAggregation: ProfileTopChampionAggregationDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case nickname
        case profileImageUrl
        case profileImageURL
        case avatarUrl
        case imageUrl
        case updatedAt
        case profileUpdatedAt
        case profileImageUpdatedAt
        case primaryPosition
        case mainPosition
        case secondaryPosition
        case isFillAvailable
        case styleTags
        case mannerScore
        case noshowCount
        case topChampions
        case championAggregationStatus
        case topChampionsStatus
        case topChampionAggregationStatus
        case championStatsStatus
    }

    var championAggregationStatus: ChampionAggregationStatus? {
        topChampionAggregation?.status
    }

    init(
        id: String,
        email: String,
        nickname: String,
        profileImageURL: URL? = nil,
        profileImageUpdatedAt: Date? = nil,
        primaryPosition: Position?,
        secondaryPosition: Position?,
        isFillAvailable: Bool,
        styleTags: [String],
        mannerScore: Double,
        noshowCount: Int,
        topChampions: [ProfileTopChampionDTO]? = nil,
        championAggregationStatus: ChampionAggregationStatus? = nil,
        topChampionAggregation: ProfileTopChampionAggregationDTO? = nil
    ) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.profileImageURL = profileImageURL
        self.profileImageUpdatedAt = profileImageUpdatedAt
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.isFillAvailable = isFillAvailable
        self.styleTags = styleTags
        self.mannerScore = mannerScore
        self.noshowCount = noshowCount
        self.topChampions = topChampions
        self.topChampionAggregation = topChampionAggregation ?? ProfileTopChampionAggregationDTO(status: championAggregationStatus)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        nickname = try container.decode(String.self, forKey: .nickname)
        profileImageURL = Self.decodeLossyURL(from: container, forKeys: [.profileImageUrl, .profileImageURL, .avatarUrl, .imageUrl])
        profileImageUpdatedAt = Self.decodeLossyDate(
            from: container,
            forKeys: [.profileImageUpdatedAt, .updatedAt, .profileUpdatedAt]
        )
        primaryPosition = Self.decodeLossyPosition(from: container, forKeys: [.primaryPosition, .mainPosition])
        secondaryPosition = Self.decodeLossyPosition(from: container, forKeys: [.secondaryPosition])
        isFillAvailable = (try? container.decode(Bool.self, forKey: .isFillAvailable)) ?? false
        styleTags = (try? container.decode([String].self, forKey: .styleTags)) ?? []
        mannerScore = (try? container.decode(Double.self, forKey: .mannerScore))
            ?? (try? container.decode(Int.self, forKey: .mannerScore)).map(Double.init)
            ?? 0
        noshowCount = (try? container.decode(Int.self, forKey: .noshowCount))
            ?? (try? container.decode(Double.self, forKey: .noshowCount)).map { Int($0.rounded()) }
            ?? 0
        topChampions = Self.decodeLossyTopChampions(from: container)
        topChampionAggregation = Self.decodeTopChampionAggregation(from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(profileImageURL?.absoluteString, forKey: .profileImageUrl)
        try container.encodeIfPresent(profileImageUpdatedAt, forKey: .profileImageUpdatedAt)
        try container.encodeIfPresent(primaryPosition, forKey: .primaryPosition)
        try container.encodeIfPresent(secondaryPosition, forKey: .secondaryPosition)
        try container.encode(isFillAvailable, forKey: .isFillAvailable)
        try container.encode(styleTags, forKey: .styleTags)
        try container.encode(mannerScore, forKey: .mannerScore)
        try container.encode(noshowCount, forKey: .noshowCount)
        try container.encodeIfPresent(topChampions, forKey: .topChampions)
        if let topChampionAggregation {
            try container.encodeIfPresent(topChampionAggregation.status, forKey: .championAggregationStatus)
            if topChampionAggregation.hasSupplementaryMetadata {
                try container.encode(topChampionAggregation, forKey: .topChampionAggregationStatus)
            }
        }
    }

    func toDomain() -> UserProfile {
        UserProfile(
            id: id,
            email: email,
            nickname: nickname,
            profileImageURL: profileImageURL,
            profileImageUpdatedAt: profileImageUpdatedAt,
            profileImageCacheKey: profileImageUpdatedAt.map { String(Int($0.timeIntervalSince1970)) },
            primaryPosition: primaryPosition,
            secondaryPosition: secondaryPosition,
            isFillAvailable: isFillAvailable,
            styleTags: styleTags,
            mannerScore: mannerScore,
            noshowCount: noshowCount,
            topChampions: (topChampions ?? []).compactMap { $0.toDomain() },
            topChampionAggregation: topChampionAggregation?.toDomain()
        )
    }

    private static func decodeLossyPosition(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Position? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Position.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let normalized = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: " ", with: "_")
                    .uppercased()
                if let position = Position(rawValue: normalized) {
                    return position
                }
            }
        }
        return nil
    }

    private static func decodeLossyURL(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> URL? {
        for key in keys {
            if let value = try? container.decodeIfPresent(URL.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: normalized), !normalized.isEmpty {
                    return url
                }
            }
        }
        return nil
    }

    private static func decodeLossyDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Date? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Date.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    private static func decodeLossyTopChampions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [ProfileTopChampionDTO]? {
        if let list = try? container.decodeIfPresent(LossyDecodableList<ProfileTopChampionDTO>.self, forKey: .topChampions) {
            return list.elements
        }
        return nil
    }

    private static func decodeTopChampionAggregation(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ProfileTopChampionAggregationDTO? {
        for key in [
            CodingKeys.topChampionAggregationStatus,
            CodingKeys.championAggregationStatus,
            CodingKeys.topChampionsStatus,
            CodingKeys.championStatsStatus,
        ] {
            if let aggregation = try? container.decodeIfPresent(ProfileTopChampionAggregationDTO.self, forKey: key) {
                return aggregation
            }
        }
        return nil
    }
}

struct GroupMemberInviteUserDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case nickname
        case primaryPosition
        case mainPosition
        case secondaryPosition
        case recentPower
        case riotGameName
        case tagLine
        case riotDisplayName
        case displayName
        case profileImageUrl
        case avatarUrl
        case imageUrl
    }

    let id: String
    let nickname: String
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let recentPower: Double?
    let riotDisplayName: String?
    let profileImageURL: URL?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decode(String.self, forKey: .id)
        nickname = try container.decode(String.self, forKey: .nickname)
        primaryPosition = try container.decodeIfPresent(Position.self, forKey: .primaryPosition)
            ?? container.decodeIfPresent(Position.self, forKey: .mainPosition)
        secondaryPosition = try container.decodeIfPresent(Position.self, forKey: .secondaryPosition)
        recentPower = try container.decodeIfPresent(Double.self, forKey: .recentPower)

        let explicitRiotDisplay = try container.decodeIfPresent(String.self, forKey: .riotDisplayName)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
        let riotGameName = try container.decodeIfPresent(String.self, forKey: .riotGameName)
        let tagLine = try container.decodeIfPresent(String.self, forKey: .tagLine)
        if let explicitRiotDisplay, !explicitRiotDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            riotDisplayName = explicitRiotDisplay
        } else if let riotGameName, !riotGameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedTagLine = tagLine?.trimmingCharacters(in: .whitespacesAndNewlines)
            riotDisplayName = normalizedTagLine.map { "\(riotGameName)#\($0)" } ?? riotGameName
        } else {
            riotDisplayName = nil
        }

        let profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
            ?? container.decodeIfPresent(String.self, forKey: .avatarUrl)
            ?? container.decodeIfPresent(String.self, forKey: .imageUrl)
        profileImageURL = profileImagePath.flatMap(URL.init(string:))
    }

    func toDomain() -> GroupMemberInviteUser {
        GroupMemberInviteUser(
            id: id,
            nickname: nickname,
            primaryPosition: primaryPosition,
            secondaryPosition: secondaryPosition,
            recentPower: recentPower,
            riotDisplayName: riotDisplayName,
            profileImageURL: profileImageURL
        )
    }
}

struct GroupMemberInviteSearchResponseDTO: Decodable {
    let items: [GroupMemberInviteUserDTO]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let items = try? container.decode([GroupMemberInviteUserDTO].self, forKey: .items) {
            self.items = items
            return
        }

        let singleValueContainer = try decoder.singleValueContainer()
        items = try singleValueContainer.decode([GroupMemberInviteUserDTO].self)
    }
}

struct UpdateProfileRequestDTO: Encodable {
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let isFillAvailable: Bool
    let styleTags: [String]
    let nickname: String
}

struct ReportRequestDTO: Encodable {
    let targetType: ReportTargetType
    let targetId: String
    let reason: ReportReason
    let detail: String?

    init(target: ReportTarget, reason: ReportReason, detail: String?) {
        targetType = target.type
        targetId = target.targetID
        self.reason = reason
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct BlockUserRequestDTO: Encodable {
    let userId: String
}

struct BlockedUserDTO: Decodable {
    let userID: String
    let nickname: String
    let blockedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case userID
        case blockedUserId
        case nickname
        case displayName
        case name
        case blockedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decodeIfPresent(String.self, forKey: .userID)
            ?? container.decodeIfPresent(String.self, forKey: .blockedUserId)
            ?? container.decode(String.self, forKey: .id)
        let decodedNickname = try container.decodeIfPresent(String.self, forKey: .nickname)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        nickname = decodedNickname?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "사용자"
        blockedAt = (try? container.decodeIfPresent(Date.self, forKey: .blockedAt))
            ?? (try? container.decodeIfPresent(Date.self, forKey: .createdAt))
            ?? (try? container.decodeIfPresent(Date.self, forKey: .updatedAt))
            ?? Date()
    }

    func toDomain() -> BlockedUser {
        BlockedUser(
            userID: userID.trimmingCharacters(in: .whitespacesAndNewlines),
            nickname: nickname,
            blockedAt: blockedAt
        )
    }
}

struct BlockedUserListDTO: Decodable {
    let items: [BlockedUserDTO]

    private enum CodingKeys: String, CodingKey {
        case items
        case users
        case blockedUsers
        case data
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            for key in [CodingKeys.items, .users, .blockedUsers, .data] {
                if let items = try? container.decodeIfPresent([BlockedUserDTO].self, forKey: key) {
                    self.items = items
                    return
                }
            }
        }
        let singleValueContainer = try decoder.singleValueContainer()
        items = try singleValueContainer.decode([BlockedUserDTO].self)
    }
}

struct PowerProfileDTO: Codable {
    struct StyleDTO: Codable {
        let stability: Double?
        let carry: Double?
        let teamContribution: Double?
        let laneInfluence: Double?

        private enum CodingKeys: String, CodingKey {
            case stability
            case carry
            case teamContribution
            case laneInfluence
        }

        init(
            stability: Double? = nil,
            carry: Double? = nil,
            teamContribution: Double? = nil,
            laneInfluence: Double? = nil
        ) {
            self.stability = stability
            self.carry = carry
            self.teamContribution = teamContribution
            self.laneInfluence = laneInfluence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stability = PowerProfileDTO.decodeLossyDouble(from: container, forKey: .stability)
            carry = PowerProfileDTO.decodeLossyDouble(from: container, forKey: .carry)
            teamContribution = PowerProfileDTO.decodeLossyDouble(from: container, forKey: .teamContribution)
            laneInfluence = PowerProfileDTO.decodeLossyDouble(from: container, forKey: .laneInfluence)
        }
    }

    let userId: String
    let overallPower: Double
    let lanePower: [String: Double]
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let style: StyleDTO?
    let basePower: Double?
    let formScore: Double?
    let inhouseMmr: Double?
    let inhouseConfidence: Double?
    let version: String?
    let calculatedAt: Date?
    let laneScoreBreakdown: [String: Double]?
    let autoAssignmentBasis: String?
    let historicalContributionSummary: String?
    let topChampions: [ProfileTopChampionDTO]?
    let topChampionAggregation: ProfileTopChampionAggregationDTO?

    private enum CodingKeys: String, CodingKey {
        case userId
        case userID
        case overallPower
        case lanePower
        case topChampions
        case championAggregationStatus
        case topChampionAggregationStatus
        case topChampionsStatus
        case championStatsStatus
        case primaryPosition
        case mainPosition
        case secondaryPosition
        case style
        case basePower
        case formScore
        case inhouseMmr
        case inhouseMMR
        case inhouseConfidence
        case version
        case calculatedAt
        case laneScoreBreakdown
        case laneScores
        case autoAssignmentBasis
        case laneAutoAssignmentBasis
        case positionAssignmentBasis
        case assignmentBasis
        case historicalContributionSummary
        case historicalContributionText
        case historicalContribution
        case previousSeasonContribution
    }

    init(
        userId: String,
        overallPower: Double,
        lanePower: [String: Double],
        primaryPosition: Position? = nil,
        secondaryPosition: Position? = nil,
        style: StyleDTO? = nil,
        basePower: Double? = nil,
        formScore: Double? = nil,
        inhouseMmr: Double? = nil,
        inhouseConfidence: Double? = nil,
        version: String? = nil,
        calculatedAt: Date? = nil,
        laneScoreBreakdown: [String: Double]? = nil,
        autoAssignmentBasis: String? = nil,
        historicalContributionSummary: String? = nil,
        topChampions: [ProfileTopChampionDTO]? = nil,
        topChampionAggregation: ProfileTopChampionAggregationDTO? = nil
    ) {
        self.userId = userId
        self.overallPower = overallPower
        self.lanePower = lanePower
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.style = style
        self.basePower = basePower
        self.formScore = formScore
        self.inhouseMmr = inhouseMmr
        self.inhouseConfidence = inhouseConfidence
        self.version = version
        self.calculatedAt = calculatedAt
        self.laneScoreBreakdown = laneScoreBreakdown
        self.autoAssignmentBasis = autoAssignmentBasis
        self.historicalContributionSummary = historicalContributionSummary
        self.topChampions = topChampions
        self.topChampionAggregation = topChampionAggregation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLanePower = Self.decodeLossyDoubleDictionary(from: container, forKey: .lanePower) ?? [:]
        let decodedLaneScoreBreakdown = Self.decodeLossyDoubleDictionary(from: container, forKey: .laneScoreBreakdown)
            ?? Self.decodeLossyDoubleDictionary(from: container, forKey: .laneScores)
        let resolvedOverallPower = Self.decodeLossyDouble(from: container, forKey: .overallPower)
            ?? decodedLanePower.values.max()
            ?? decodedLaneScoreBreakdown?.values.max()
            ?? 0

        userId = Self.decodeLossyString(from: container, forKeys: [.userId, .userID]) ?? ""
        overallPower = resolvedOverallPower
        lanePower = decodedLanePower.isEmpty ? (decodedLaneScoreBreakdown ?? [:]) : decodedLanePower
        primaryPosition = Self.decodeLossyPosition(from: container, forKeys: [.primaryPosition, .mainPosition])
        secondaryPosition = Self.decodeLossyPosition(from: container, forKeys: [.secondaryPosition])
        style = try? container.decodeIfPresent(StyleDTO.self, forKey: .style)
        basePower = Self.decodeLossyDouble(from: container, forKey: .basePower)
        formScore = Self.decodeLossyDouble(from: container, forKey: .formScore)
        inhouseMmr = Self.decodeLossyDouble(from: container, forKey: .inhouseMmr)
            ?? Self.decodeLossyDouble(from: container, forKey: .inhouseMMR)
        inhouseConfidence = Self.decodeLossyDouble(from: container, forKey: .inhouseConfidence)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        calculatedAt = try? container.decodeIfPresent(Date.self, forKey: .calculatedAt)
        laneScoreBreakdown = decodedLaneScoreBreakdown
        topChampions = Self.decodeLossyTopChampions(from: container)
        topChampionAggregation = Self.decodeTopChampionAggregation(from: container)
        autoAssignmentBasis = Self.decodeLossyString(from: container, forKeys: [
            .autoAssignmentBasis,
            .laneAutoAssignmentBasis,
            .positionAssignmentBasis,
            .assignmentBasis,
        ])
        historicalContributionSummary = Self.decodeHistoricalContributionSummary(from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(overallPower, forKey: .overallPower)
        try container.encode(lanePower, forKey: .lanePower)
        try container.encodeIfPresent(primaryPosition, forKey: .primaryPosition)
        try container.encodeIfPresent(secondaryPosition, forKey: .secondaryPosition)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(basePower, forKey: .basePower)
        try container.encodeIfPresent(formScore, forKey: .formScore)
        try container.encodeIfPresent(inhouseMmr, forKey: .inhouseMmr)
        try container.encodeIfPresent(inhouseConfidence, forKey: .inhouseConfidence)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(calculatedAt, forKey: .calculatedAt)
        try container.encodeIfPresent(laneScoreBreakdown, forKey: .laneScoreBreakdown)
        try container.encodeIfPresent(autoAssignmentBasis, forKey: .autoAssignmentBasis)
        try container.encodeIfPresent(historicalContributionSummary, forKey: .historicalContributionSummary)
        try container.encodeIfPresent(topChampions, forKey: .topChampions)
        if let topChampionAggregation {
            try container.encodeIfPresent(topChampionAggregation.status, forKey: .championAggregationStatus)
            if topChampionAggregation.hasSupplementaryMetadata {
                try container.encode(topChampionAggregation, forKey: .topChampionAggregationStatus)
            }
        }
    }

    var missingFieldPaths: [String] {
        var fields: [String] = []
        if style?.stability == nil { fields.append("style.stability") }
        if style?.carry == nil { fields.append("style.carry") }
        if style?.teamContribution == nil { fields.append("style.teamContribution") }
        if style?.laneInfluence == nil { fields.append("style.laneInfluence") }
        if basePower == nil { fields.append("basePower") }
        if formScore == nil { fields.append("formScore") }
        if inhouseMmr == nil { fields.append("inhouseMmr") }
        if inhouseConfidence == nil { fields.append("inhouseConfidence") }
        if version == nil { fields.append("version") }
        if calculatedAt == nil { fields.append("calculatedAt") }
        return fields
    }

    var resolvedPreferredPositions: [Position] {
        var ordered: [Position] = []

        func appendIfNeeded(_ position: Position?) {
            guard let position, !ordered.contains(position) else { return }
            ordered.append(position)
        }

        appendIfNeeded(primaryPosition)
        appendIfNeeded(secondaryPosition)

        let laneOrdered = lanePower
            .compactMap { key, value -> (Position, Double)? in
                guard let position = Position(rawValue: key) else { return nil }
                return (position, value)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.rawValue < rhs.0.rawValue
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)

        laneOrdered.forEach { appendIfNeeded($0) }
        return ordered
    }

    var usesFallbackMapping: Bool {
        !missingFieldPaths.isEmpty || primaryPosition == nil || secondaryPosition == nil
    }

    func toDomain(requestedUserID: String? = nil) -> PowerProfile {
        let resolvedStyleFallback = overallPower > 0 ? overallPower : (lanePower.values.max() ?? 0)

        return PowerProfile(
            userID: userId.isEmpty ? (requestedUserID ?? "") : userId,
            overallPower: overallPower,
            lanePower: Dictionary(uniqueKeysWithValues: lanePower.compactMap { key, value in
                guard let position = Position(rawValue: key) else { return nil }
                return (position, value)
            }),
            primaryPosition: primaryPosition,
            secondaryPosition: secondaryPosition,
            stability: style?.stability ?? resolvedStyleFallback,
            carry: style?.carry ?? resolvedStyleFallback,
            teamContribution: style?.teamContribution ?? resolvedStyleFallback,
            laneInfluence: style?.laneInfluence ?? resolvedStyleFallback,
            basePower: basePower ?? overallPower,
            formScore: formScore ?? overallPower,
            inhouseMMR: inhouseMmr ?? overallPower,
            inhouseConfidence: inhouseConfidence ?? 0,
            version: version ?? "seeded-fallback",
            calculatedAt: calculatedAt ?? .distantPast,
            laneScoreBreakdown: Self.mapLaneScores(laneScoreBreakdown),
            autoAssignmentBasis: autoAssignmentBasis,
            historicalContributionSummary: historicalContributionSummary,
            topChampions: topChampions?.compactMap { $0.toDomain() },
            topChampionAggregation: topChampionAggregation?.toDomain()
        )
    }

    private static func decodeLossyDouble<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    private static func decodeLossyString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty { return normalized }
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return String(value)
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
        }
        return nil
    }

    private static func decodeLossyPosition(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Position? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Position.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let normalized = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: " ", with: "_")
                    .uppercased()
                if let position = Position(rawValue: normalized) {
                    return position
                }
            }
        }
        return nil
    }

    private static func decodeLossyTopChampions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [ProfileTopChampionDTO]? {
        if let list = try? container.decodeIfPresent(LossyDecodableList<ProfileTopChampionDTO>.self, forKey: .topChampions) {
            return list.elements
        }
        return nil
    }

    private static func decodeTopChampionAggregation(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ProfileTopChampionAggregationDTO? {
        for key in [
            CodingKeys.topChampionAggregationStatus,
            CodingKeys.championAggregationStatus,
            CodingKeys.topChampionsStatus,
            CodingKeys.championStatsStatus,
        ] {
            if let aggregation = try? container.decodeIfPresent(ProfileTopChampionAggregationDTO.self, forKey: key) {
                return aggregation
            }
        }
        return nil
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private static func decodeLossyDoubleDictionary(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String: Double]? {
        guard let nestedContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key) else {
            return nil
        }

        var values: [String: Double] = [:]
        for dynamicKey in nestedContainer.allKeys {
            if let value = decodeLossyDouble(from: nestedContainer, forKey: dynamicKey) {
                values[dynamicKey.stringValue] = value
            }
        }
        return values
    }

    private static func decodeHistoricalContributionSummary(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String? {
        if let text = decodeLossyString(from: container, forKeys: [.historicalContributionSummary, .historicalContributionText]) {
            return text
        }

        let historicalContribution = decodeLossyDouble(from: container, forKey: .historicalContribution)
        let previousSeasonContribution = decodeLossyDouble(from: container, forKey: .previousSeasonContribution)
        let contribution = historicalContribution ?? previousSeasonContribution
        guard let contribution, contribution.isFinite else { return nil }
        return "이전 시즌 기여 \(Int(contribution.rounded())) 반영"
    }

    private static func mapLaneScores(_ scores: [String: Double]?) -> [Position: Double]? {
        guard let scores else { return nil }
        let pairs: [(Position, Double)] = scores.compactMap { key, value in
            let normalized = key
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
                .uppercased()
            guard let position = Position(rawValue: normalized) else { return nil }
            return (position, value)
        }
        let mapped = Dictionary(uniqueKeysWithValues: pairs)
        return mapped.isEmpty ? nil : mapped
    }
}

struct RiotAccountDTO: Codable {
    let id: String
    let riotGameName: String
    let tagLine: String
    let region: String
    let puuid: String
    let isPrimary: Bool
    let verificationStatus: VerificationStatus
    let syncStatus: RiotSyncStatus?
    let lastSyncRequestedAt: Date?
    let lastSyncSucceededAt: Date?
    let lastSyncFailedAt: Date?
    let lastSyncErrorCode: String?
    let lastSyncErrorMessage: String?
    let lastSyncedAt: Date?

    func toDomain() -> RiotAccount {
        RiotAccount(
            id: id,
            riotGameName: riotGameName,
            tagLine: tagLine,
            region: region,
            puuid: puuid,
            isPrimary: isPrimary,
            verificationStatus: verificationStatus,
            syncStatus: syncStatus ?? .idle,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage,
            lastSyncedAt: lastSyncedAt
        )
    }
}

struct RiotAccountListDTO: Codable {
    let items: [RiotAccountDTO]
}

struct CreateRiotAccountRequestDTO: Encodable {
    let riotGameName: String
    let tagLine: String
    let region: String
    let isPrimary: Bool
}

struct RiotAccountSyncAcceptedDTO: Codable {
    let riotAccountId: String
    let queued: Bool
    let syncStatus: RiotSyncStatus

    func toDomain() -> RiotAccountSyncAccepted {
        RiotAccountSyncAccepted(
            riotAccountId: riotAccountId,
            queued: queued,
            syncStatus: syncStatus
        )
    }
}

struct RiotAccountSyncStatusDTO: Codable {
    let riotAccountId: String
    let syncStatus: RiotSyncStatus
    let lastSyncRequestedAt: Date?
    let lastSyncSucceededAt: Date?
    let lastSyncFailedAt: Date?
    let lastSyncErrorCode: String?
    let lastSyncErrorMessage: String?

    func toDomain() -> RiotAccountSyncState {
        RiotAccountSyncState(
            riotAccountId: riotAccountId,
            syncStatus: syncStatus,
            lastSyncRequestedAt: lastSyncRequestedAt,
            lastSyncSucceededAt: lastSyncSucceededAt,
            lastSyncFailedAt: lastSyncFailedAt,
            lastSyncErrorCode: lastSyncErrorCode,
            lastSyncErrorMessage: lastSyncErrorMessage
        )
    }
}

struct GroupSummaryDTO: Codable {
    let id: String
    let name: String
    let description: String?
    let visibility: GroupVisibility
    let isMember: Bool?
    let joinPolicy: JoinPolicy
    let tags: [String]
    let ownerUserId: String
    let canInviteMembers: Bool?
    let inviteMembersBlockedReason: String?
    let memberCount: Int
    let recentMatches: Int
    let recentMatchCountSource: GroupMatchCountSource

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case visibility
        case isMember
        case joinPolicy
        case tags
        case ownerUserId
        case ownerUserID
        case canInviteMembers
        case inviteMembersBlockedReason
        case memberCount
        case recentMatches
        case matchCount
        case inhouseCount
        case recordCount
        case latestMatchCount
        case recentInhouseCount
        case scrimCount
        case completedMatchCount
        case confirmedMatchCount
        case closedMatchCount
        case pastMatchCount
        case completedInhouseCount
        case pastInhouseCount
        case lobbyCount
        case activeLobbyCount
        case pendingLobbyCount
    }

    init(
        id: String,
        name: String,
        description: String?,
        visibility: GroupVisibility,
        isMember: Bool? = nil,
        joinPolicy: JoinPolicy,
        tags: [String],
        ownerUserId: String,
        canInviteMembers: Bool? = nil,
        inviteMembersBlockedReason: String? = nil,
        memberCount: Int,
        recentMatches: Int,
        recentMatchCountSource: GroupMatchCountSource = .completedHistory
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.visibility = visibility
        self.isMember = isMember
        self.joinPolicy = joinPolicy
        self.tags = tags
        self.ownerUserId = ownerUserId
        self.canInviteMembers = canInviteMembers
        self.inviteMembersBlockedReason = inviteMembersBlockedReason
        self.memberCount = memberCount
        self.recentMatches = recentMatches
        self.recentMatchCountSource = recentMatchCountSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = Self.decodeLossyString(from: container, forKeys: [.id]) ?? ""
        name = Self.decodeLossyString(from: container, forKeys: [.name]) ?? ""
        description = Self.decodeLossyString(from: container, forKeys: [.description])
        visibility = try container.decode(GroupVisibility.self, forKey: .visibility)
        isMember = try? container.decodeIfPresent(Bool.self, forKey: .isMember)
        joinPolicy = try container.decode(JoinPolicy.self, forKey: .joinPolicy)
        tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        ownerUserId = Self.decodeLossyString(from: container, forKeys: [.ownerUserId, .ownerUserID]) ?? ""
        canInviteMembers = try? container.decodeIfPresent(Bool.self, forKey: .canInviteMembers)
        inviteMembersBlockedReason = Self.decodeLossyString(from: container, forKeys: [.inviteMembersBlockedReason])
        memberCount = max(Self.decodeLossyInt(from: container, forKeys: [.memberCount]) ?? 0, 0)

        let resolvedCount = Self.resolveRecentMatchCount(from: container)
        recentMatches = resolvedCount.count
        recentMatchCountSource = resolvedCount.source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(visibility, forKey: .visibility)
        try container.encodeIfPresent(isMember, forKey: .isMember)
        try container.encode(joinPolicy, forKey: .joinPolicy)
        try container.encode(tags, forKey: .tags)
        try container.encode(ownerUserId, forKey: .ownerUserId)
        try container.encodeIfPresent(canInviteMembers, forKey: .canInviteMembers)
        try container.encodeIfPresent(inviteMembersBlockedReason, forKey: .inviteMembersBlockedReason)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(recentMatches, forKey: .recentMatches)
    }

    func toDomain() -> GroupSummary {
        GroupSummary(
            id: id,
            name: name,
            description: description,
            visibility: visibility,
            isMember: isMember,
            joinPolicy: joinPolicy,
            tags: tags,
            ownerUserID: ownerUserId,
            canInviteMembers: canInviteMembers,
            inviteMembersBlockedReason: inviteMembersBlockedReason,
            memberCount: memberCount,
            recentMatches: recentMatches,
            recentMatchCountSource: recentMatchCountSource
        )
    }

    private static func resolveRecentMatchCount(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> (count: Int, source: GroupMatchCountSource) {
        let authoritativeKeys: [CodingKeys] = [
            .completedMatchCount,
            .confirmedMatchCount,
            .closedMatchCount,
            .pastMatchCount,
            .completedInhouseCount,
            .pastInhouseCount,
        ]
        if let count = decodeLossyInt(from: container, forKeys: authoritativeKeys) {
            return (max(count, 0), .completedHistory)
        }

        // TODO: Remove the legacy fallback once the server contract is finalized around a
        // completed-history field. These keys are kept for backward compatibility only.
        let legacyKeys: [CodingKeys] = [
            .recentMatches,
            .matchCount,
            .inhouseCount,
            .recordCount,
            .latestMatchCount,
            .recentInhouseCount,
            .scrimCount,
        ]
        let legacyCount = max(decodeLossyInt(from: container, forKeys: legacyKeys) ?? 0, 0)
        let lobbyCountKeys: [CodingKeys] = [.activeLobbyCount, .pendingLobbyCount, .lobbyCount]
        let lobbyCount = max(decodeLossyInt(from: container, forKeys: lobbyCountKeys) ?? 0, 0)
        if lobbyCount > 0 {
            return (max(legacyCount - lobbyCount, 0), .legacyAdjustedByLobbyCount)
        }
        return (legacyCount, legacyCount > 0 ? .legacyRecentMatches : .completedHistory)
    }

    private static func decodeLossyInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return Int(value.rounded())
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func decodeLossyString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
        }
        return nil
    }
}

struct GroupSummaryListDTO: Codable {
    let items: [GroupSummaryDTO]
}

struct CreateGroupRequestDTO: Encodable {
    let name: String
    let description: String?
    let visibility: GroupVisibility
    let joinPolicy: JoinPolicy
    let tags: [String]
}

struct UpdateGroupRequestDTO: Encodable {
    let name: String
    let description: String?
    let visibility: GroupVisibility
    let joinPolicy: JoinPolicy
    let tags: [String]
}

struct GroupMemberDTO: Codable {
    let id: String
    let userId: String
    let nickname: String
    let role: GroupRole

    func toDomain() -> GroupMember {
        GroupMember(id: id, userID: userId, nickname: nickname, role: role)
    }
}

struct GroupMemberListDTO: Codable {
    let items: [GroupMemberDTO]

    private enum CodingKeys: String, CodingKey {
        case items
        case members
    }

    init(items: [GroupMemberDTO]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let items = try? container.decode([GroupMemberDTO].self, forKey: .items) {
                self.items = items
                return
            }
            if let members = try? container.decode([GroupMemberDTO].self, forKey: .members) {
                items = members
                return
            }
        }

        let singleValueContainer = try decoder.singleValueContainer()
        items = try singleValueContainer.decode([GroupMemberDTO].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

struct AddGroupMemberRequestDTO: Encodable {
    let userId: String
    let role: GroupRole
}

struct MatchPlayerDTO: Codable {
    let id: String
    let userId: String
    let nickname: String
    let teamSide: TeamSide?
    let assignedRole: Position?
    let participationStatus: ParticipationStatus
    let isCaptain: Bool

    func toDomain() -> MatchPlayer {
        MatchPlayer(
            id: id,
            userID: userId,
            nickname: nickname,
            teamSide: teamSide,
            assignedRole: assignedRole,
            participationStatus: participationStatus,
            isCaptain: isCaptain
        )
    }
}

struct MatchResponseDTO: Codable {
    let id: String
    let groupId: String
    let status: MatchStatus
    let scheduledAt: Date?
    let balanceMode: BalanceMode?
    let selectedCandidateNo: Int?
    let players: [MatchPlayerDTO]
    let candidates: [MatchCandidateDTO]?

    func toDomain() -> Match {
        Match(
            id: id,
            groupID: groupId,
            status: status,
            scheduledAt: scheduledAt,
            balanceMode: balanceMode,
            selectedCandidateNo: selectedCandidateNo,
            players: players.map { $0.toDomain() },
            candidates: (candidates ?? []).map { $0.toDomain() }
        )
    }
}

struct CreateMatchRequestDTO: Encodable {
    let scheduledAt: String?
    let title: String?
    let notes: String?
}

struct MatchPlayerInputDTO: Encodable {
    let userId: String
    let riotAccountId: String?
    let participationStatus: ParticipationStatus
    let sameTeamPreferenceUserIds: [String]
    let avoidTeamPreferenceUserIds: [String]
    let isCaptain: Bool
}

struct AddPlayersRequestDTO: Encodable {
    let players: [MatchPlayerInputDTO]
}

struct CandidateMetricsDTO: Codable {
    let teamPowerGap: Double
    let laneMatchupGap: Double
    let offRolePenalty: Double
    let repeatTeamPenalty: Double
    let preferenceViolationPenalty: Double
    let volatilityClusterPenalty: Double

    func toDomain() -> CandidateMetrics {
        CandidateMetrics(
            teamPowerGap: teamPowerGap,
            laneMatchupGap: laneMatchupGap,
            offRolePenalty: offRolePenalty,
            repeatTeamPenalty: repeatTeamPenalty,
            preferenceViolationPenalty: preferenceViolationPenalty,
            volatilityClusterPenalty: volatilityClusterPenalty
        )
    }
}

struct CandidatePlayerDTO: Codable {
    let userId: String
    let nickname: String
    let teamSide: TeamSide
    let assignedRole: Position
    let rolePower: Double

    func toDomain(primaryPosition: Position?, secondaryPosition: Position?) -> CandidatePlayer {
        let allowedPositions = [primaryPosition, secondaryPosition].compactMap { $0 }
        let isOffRole = !allowedPositions.contains(assignedRole)
        return CandidatePlayer(
            userID: userId,
            nickname: nickname,
            teamSide: teamSide,
            assignedRole: assignedRole,
            rolePower: rolePower,
            isOffRole: isOffRole
        )
    }
}

struct MatchCandidateDTO: Codable {
    let candidateId: String
    let candidateNo: Int
    let type: BalanceMode
    let score: Double
    let metrics: CandidateMetricsDTO
    let teamAPower: Double
    let teamBPower: Double
    let offRoleCount: Int
    let explanationTags: [String]
    let teamA: [CandidatePlayerDTO]
    let teamB: [CandidatePlayerDTO]

    func toDomain() -> MatchCandidate {
        MatchCandidate(
            candidateID: candidateId,
            candidateNo: candidateNo,
            type: type,
            score: score,
            metrics: metrics.toDomain(),
            teamAPower: teamAPower,
            teamBPower: teamBPower,
            offRoleCount: offRoleCount,
            explanationTags: explanationTags,
            teamA: teamA.map { $0.toDomain(primaryPosition: nil, secondaryPosition: nil) },
            teamB: teamB.map { $0.toDomain(primaryPosition: nil, secondaryPosition: nil) }
        )
    }
}

struct MatchmakingCandidatesDTO: Codable {
    let candidates: [MatchCandidateDTO]
}

struct AutoBalanceRequestDTO: Encodable {
    let mode: BalanceMode?
    let lockedPlayerIds: [String]
}

struct RerollRequestDTO: Encodable {
    let mode: BalanceMode?
    let lockedPlayerIds: [String]
    let excludeCandidateIds: [String]
}

struct SelectCandidateRequestDTO: Encodable {
    let candidateNo: Int
}

struct PreviewRosterPlayerInputDTO: Codable, Hashable {
    let nickname: String
    let preferredPosition: Position
    let score: Int

    func toDomain() -> PreviewRosterPlayer {
        PreviewRosterPlayer(name: nickname, preferredPosition: preferredPosition, score: score)
    }
}

struct BalancePreviewRequestDTO: Encodable {
    let mode: BalanceMode
    let players: [PreviewRosterPlayerInputDTO]
}

struct BalancePreviewResponseDTO: Codable {
    let bluePlayers: [PreviewRosterPlayerInputDTO]
    let redPlayers: [PreviewRosterPlayerInputDTO]
    let blueTotal: Int
    let redTotal: Int
    let mode: BalanceMode?

    func toDomain(fallbackMode: BalanceMode) -> TeamBalancePreviewResult {
        TeamBalancePreviewResult(
            bluePlayers: bluePlayers.map { $0.toDomain() },
            redPlayers: redPlayers.map { $0.toDomain() },
            blueTotal: blueTotal,
            redTotal: redTotal,
            mode: mode ?? fallbackMode
        )
    }
}

struct ResultPreviewPlayerInputDTO: Encodable {
    let nickname: String
    let teamSide: TeamSide
    let role: Position
}

struct ResultPreviewRequestDTO: Encodable {
    let winningTeam: TeamSide
    let balanceRating: Int
    let mvpNickname: String?
    let players: [ResultPreviewPlayerInputDTO]
}

struct ResultPreviewResponseDTO: Codable {
    let isValid: Bool?
    let message: String?

    func toDomain() -> ResultPreviewValidation {
        ResultPreviewValidation(
            isValid: isValid ?? true,
            message: message ?? ((isValid ?? true) ? "결과 프리뷰를 확인했어요." : "프리뷰 입력값을 다시 확인해 주세요.")
        )
    }
}

struct MatchStatDTO: Codable {
    let userId: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let laneResult: LaneResult

    func toDomain() -> MatchStat {
        MatchStat(userID: userId, kills: kills, deaths: deaths, assists: assists, laneResult: laneResult)
    }
}

struct ResultConfirmationDTO: Codable {
    let userId: String
    let action: ConfirmationAction
    let diff: [String: JSONValue]?
    let comment: String?
    let createdAt: Date

    func toDomain() -> ResultConfirmation {
        ResultConfirmation(
            userID: userId,
            action: action,
            diff: (diff ?? [:]).mapValues { $0.stringValue },
            comment: comment,
            createdAt: createdAt
        )
    }
}

struct MatchResultDTO: Codable {
    let id: String
    let winningTeam: TeamSide?
    let resultStatus: ResultStatus
    let inputMode: InputMode
    let players: [MatchStatDTO]
    let confirmations: [ResultConfirmationDTO]

    func toDomain() -> MatchResult {
        MatchResult(
            id: id,
            winningTeam: winningTeam,
            resultStatus: resultStatus,
            inputMode: inputMode,
            players: players.map { $0.toDomain() },
            confirmations: confirmations.map { $0.toDomain() }
        )
    }
}

struct QuickResultPlayerDTO: Encodable {
    let userId: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let laneResult: LaneResult
    let contributionRating: Int?
}

struct QuickResultRequestDTO: Encodable {
    let winningTeam: TeamSide
    let mvpUserId: String
    let balanceRating: Int
    let players: [QuickResultPlayerDTO]
}

struct ConfirmResultRequestDTO: Encodable {
    let action: ConfirmationAction
    let diff: [String: String]?
    let comment: String?
}

struct ResultSubmissionDTO: Codable {
    let resultId: String
    let status: ResultStatus
    let confirmationNeeded: Int

    func toDomain() -> ResultSubmissionStatus {
        ResultSubmissionStatus(resultID: resultId, status: status, confirmationNeeded: confirmationNeeded)
    }
}

struct HistoryItemDTO: Codable {
    let matchId: String
    let scheduledAt: Date
    let role: Position
    let teamSide: TeamSide
    let result: String
    let kda: String
    let deltaMmr: Double

    func toDomain() -> MatchHistoryItem {
        MatchHistoryItem(
            matchID: matchId,
            scheduledAt: scheduledAt,
            role: role,
            teamSide: teamSide,
            result: result,
            kda: kda,
            deltaMMR: deltaMmr
        )
    }
}

struct HistoryResponseDTO: Codable {
    let items: [HistoryItemDTO]
}

struct RecruitPostDTO: Codable {
    let id: String
    let groupId: String
    let postType: RecruitingPostType
    let title: String
    let status: RecruitingPostStatus
    let scheduledAt: Date?
    let body: String?
    let tags: [String]?
    let requiredPositions: [String]?
    let createdBy: String?

    func toDomain() -> RecruitPost {
        RecruitPost(
            id: id,
            groupID: groupId,
            postType: postType,
            title: title,
            status: status,
            scheduledAt: scheduledAt,
            body: body,
            tags: tags ?? [],
            requiredPositions: requiredPositions ?? [],
            createdBy: createdBy
        )
    }
}

struct RecruitPostListDTO: Codable {
    let items: [RecruitPostDTO]
}

struct CreateRecruitPostRequestDTO: Encodable {
    let groupId: String
    let postType: RecruitingPostType
    let title: String
    let body: String?
    let tags: [String]
    let scheduledAt: String?
    let requiredPositions: [String]
}

struct UpdateRecruitPostRequestDTO: Encodable {
    let postType: RecruitingPostType
    let title: String
    let body: String?
    let tags: [String]
    let scheduledAt: String?
    let requiredPositions: [String]
}

// MARK: - Repositories

final class AuthRepository {
    private let apiClient: APIClient
    private let tokenStore: TokenStore

    init(apiClient: APIClient, tokenStore: TokenStore) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    func loadPersistedTokens() async -> AuthTokens? {
        await tokenStore.loadTokens()
    }

    func loginWithApple(authorization: AppleLoginAuthorization) async throws -> AuthTokens {
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: AuthAPI.Endpoint.loginApple,
                method: .post,
                body: try apiClient.encodedBody(AppleLoginRequestDTO(identityToken: authorization.identityToken)),
                requiresAuth: false
            )
            let tokens = response.toDomain()
            await tokenStore.save(tokens: tokens)
            return tokens
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    func loginWithGoogle(authorization: GoogleLoginAuthorization) async throws -> AuthTokens {
        debugLogGoogleBackendLoginStarted(endpoint: AuthAPI.Endpoint.loginGoogle)
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: AuthAPI.Endpoint.loginGoogle,
                method: .post,
                body: try apiClient.encodedBody(GoogleLoginRequestDTO(identityToken: authorization.idToken)),
                requiresAuth: false
            )
            let tokens = response.toDomain()
            await tokenStore.save(tokens: tokens)
            debugLogGoogleBackendLoginSucceeded(tokens)
            return tokens
        } catch {
            let mappedError = AuthErrorMapper.map(error)
            debugLogGoogleBackendLoginFailed(mappedError)
            throw mappedError
        }
    }

    func signUpWithEmail(
        email: String,
        password: String,
        nickname: String
    ) async throws -> AuthTokens {
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: AuthAPI.Endpoint.signUp,
                method: .post,
                body: try apiClient.encodedBody(
                    EmailSignUpRequestDTO(
                        email: email,
                        password: password,
                        nickname: nickname
                    )
                ),
                requiresAuth: false
            )
            let tokens = response.toDomain()
            await tokenStore.save(tokens: tokens)
            debugLogEmailSignUpSuccess(tokens)
            return tokens
        } catch {
            let mappedError = AuthErrorMapper.map(error)
            debugLogEmailSignUpFailure(mappedError)
            throw mappedError
        }
    }

    func loginWithEmail(email: String, password: String) async throws -> AuthTokens {
        debugLogEmailLoginRequest(email: email, password: password)
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: AuthAPI.Endpoint.loginEmail,
                method: .post,
                body: try apiClient.encodedBody(
                    EmailLoginRequestDTO(
                        email: email,
                        password: password
                    )
                ),
                requiresAuth: false
            )
            let tokens = response.toDomain()
            await tokenStore.save(tokens: tokens)
            debugLogEmailLoginSuccess(tokens)
            return tokens
        } catch {
            let mappedError = AuthErrorMapper.map(error)
            debugLogEmailLoginFailure(mappedError)
            throw mappedError
        }
    }

    func signOut() async {
        if let refreshToken = await tokenStore.loadTokens()?.refreshToken {
            let response: EmptyResponse? = try? await apiClient.send(
                path: AuthAPI.Endpoint.logout,
                method: .post,
                body: try? apiClient.encodedBody(LogoutRequestDTO(refreshToken: refreshToken)),
                requiresAuth: false
            )
            _ = response
        }
        await tokenStore.clear()
    }

    func deleteAccount() async throws {
        var lastCapabilityError: UserFacingError?

        // TODO: 서버 확정 스펙에 맞춰 계정 탈퇴 endpoint를 단일화한다.
        for path in ["/me", "/auth/account"] {
            do {
                let response: EmptyResponse = try await apiClient.sendWithoutBody(
                    path: path,
                    method: .delete
                )
                _ = response
                await tokenStore.clear()
                return
            } catch let error as UserFacingError {
                if [404, 405, 501].contains(error.statusCode ?? -1) {
                    lastCapabilityError = error
                    continue
                }
                throw error
            }
        }

        throw lastCapabilityError
            ?? UserFacingError(
                title: "회원 탈퇴 실패",
                message: "회원 탈퇴 기능이 아직 서버와 연결되지 않았어요. 잠시 후 다시 시도해주세요.",
                endpoint: "/me",
                requestMethod: HTTPMethod.delete.rawValue
            ).serverContractMapped
    }

    private func debugLogEmailSignUpSuccess(_ tokens: AuthTokens) {
#if DEBUG
        print(
            "[AuthRepository] signUpWithEmail success userId=\(tokens.user.id) provider=\(tokens.user.provider?.rawValue ?? "nil") status=\(tokens.user.status?.rawValue ?? "nil")"
        )
#endif
    }

    private func debugLogEmailSignUpFailure(_ error: AuthError) {
#if DEBUG
        print("[AuthRepository] signUpWithEmail mappedError=\(String(describing: error))")
#endif
    }

    private func debugLogEmailLoginRequest(email: String, password: String) {
#if DEBUG
        print("[AuthRepository] loginWithEmail requestBody email=\(email) password=\(password)")
#endif
    }

    private func debugLogEmailLoginSuccess(_ tokens: AuthTokens) {
#if DEBUG
        print(
            "[AuthRepository] loginWithEmail success userId=\(tokens.user.id) provider=\(tokens.user.provider?.rawValue ?? "nil") status=\(tokens.user.status?.rawValue ?? "nil")"
        )
#endif
    }

    private func debugLogEmailLoginFailure(_ error: AuthError) {
#if DEBUG
        print("[AuthRepository] loginWithEmail mappedError=\(String(describing: error))")
#endif
    }

    private func debugLogGoogleBackendLoginStarted(endpoint: String) {
#if DEBUG
        print("[GoogleAuth] backendLoginStarted endpoint=\(endpoint)")
#endif
    }

    private func debugLogGoogleBackendLoginSucceeded(_ tokens: AuthTokens) {
#if DEBUG
        print(
            "[GoogleAuth] backendLoginSucceeded userId=\(tokens.user.id) provider=\(tokens.user.provider?.rawValue ?? "nil") status=\(tokens.user.status?.rawValue ?? "nil")"
        )
#endif
    }

    private func debugLogGoogleBackendLoginFailed(_ error: AuthError) {
#if DEBUG
        print("[GoogleAuth] backendLoginFailed mappedError=\(String(describing: error))")
#endif
    }
}

final class ProfileRepository {
    private struct CachedPowerProfile {
        let profile: PowerProfile
        let fetchedAt: Date
    }

    private let apiClient: APIClient
    private let inviteSearchEndpointCandidates = ["/users/search", "/users"]
    private let powerProfileCacheTTL: TimeInterval = 10
    private let powerProfileLock = NSLock()
    private var cachedPowerProfiles: [String: CachedPowerProfile] = [:]
    private var inFlightPowerProfileRequests: [String: Task<PowerProfile, Error>] = [:]

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func me() async throws -> UserProfile {
        let response: UserProfileDTO = try await apiClient.sendWithoutBody(path: "/me")
        return response.toDomain()
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let response: UserProfileDTO = try await apiClient.send(
            path: "/me/profile",
            method: .patch,
            body: try apiClient.encodedBody(
                UpdateProfileRequestDTO(
                    primaryPosition: profile.primaryPosition,
                    secondaryPosition: profile.secondaryPosition,
                    isFillAvailable: profile.isFillAvailable,
                    styleTags: profile.styleTags,
                    nickname: profile.nickname
                )
            )
        )
        let updatedProfile = response.toDomain()
        clearCachedPowerProfile(for: updatedProfile.id)
        return updatedProfile
    }

    func updateProfileImage(imageData: Data, mimeType: String, fileName: String) async throws -> UserProfile {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = multipartFormBody(
            data: imageData,
            fieldName: "image",
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )
        // TODO: 서버 업로드 스펙 확정 시 endpoint 및 multipart field name을 맞춘다.
        let response: UserProfileDTO = try await apiClient.send(
            path: "/me/profile-image",
            method: .post,
            body: body,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
        var updatedProfile = response.toDomain()
        updatedProfile.profileImageCacheKey = UUID().uuidString
        clearCachedPowerProfile(for: updatedProfile.id)
        return updatedProfile
    }

    func isProfileImageUploadCapabilityUnavailable(_ error: UserFacingError) -> Bool {
        switch error.statusCode {
        case 404, 405, 501:
            return true
        default:
            return false
        }
    }

    func powerProfile(userID: String) async throws -> PowerProfile {
        if let cachedProfile = cachedPowerProfile(for: userID) {
            debugPowerProfile("userId=\(userID) action=cache_hit reason=recent_success")
            return cachedProfile
        }

        if let inFlightRequest = inFlightPowerProfileRequest(for: userID) {
            debugPowerProfile("userId=\(userID) action=deduplicated reason=in_flight")
            return try await inFlightRequest.value
        }

        debugPowerProfile("userId=\(userID) action=fetch_start source=live")
        let task = Task { try await self.fetchPowerProfile(userID: userID) }
        storeInFlightPowerProfileRequest(task, for: userID)

        do {
            let profile = try await task.value
            clearInFlightPowerProfileRequest(for: userID)
            storeCachedPowerProfile(profile, for: userID)
            debugPowerProfile("userId=\(userID) action=fetch_success source=live")
            return profile
        } catch {
            clearInFlightPowerProfileRequest(for: userID)
            throw error
        }
    }

    func history(userID: String, groupID: String? = nil, limit: Int = 20) async throws -> [MatchHistoryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let groupID {
            items.append(URLQueryItem(name: "groupId", value: groupID))
        }
        let response: HistoryResponseDTO = try await apiClient.sendWithoutBody(
            path: "/users/\(userID)/inhouse-history",
            queryItems: items
        )
        return response.items.map { $0.toDomain() }
    }

    func searchInviteUsers(query: String, limit: Int = 20) async throws -> [GroupMemberInviteUser] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        var lastCapabilityError: UserFacingError?

        for path in inviteSearchEndpointCandidates {
            do {
                let response: GroupMemberInviteSearchResponseDTO = try await apiClient.sendWithoutBody(
                    path: path,
                    queryItems: queryItems
                )
                return sanitizeInviteUsers(response.items.map { $0.toDomain() })
            } catch let error as UserFacingError {
                if isInviteSearchEndpointUnavailable(error) {
                    lastCapabilityError = error
                    continue
                }
                throw error
            }
        }

        throw lastCapabilityError
            ?? UserFacingError(
                title: "사용자 검색 실패",
                message: "사용자 검색을 진행할 수 없어요.",
                endpoint: inviteSearchEndpointCandidates.first,
                requestMethod: HTTPMethod.get.rawValue
            ).serverContractMapped
    }

    private func isInviteSearchEndpointUnavailable(_ error: UserFacingError) -> Bool {
        switch error.statusCode {
        case 404, 405, 501:
            return true
        default:
            return false
        }
    }

    private func sanitizeInviteUsers(_ items: [GroupMemberInviteUser]) -> [GroupMemberInviteUser] {
        var seenUserIDs = Set<String>()
        return items.compactMap { item in
            let normalizedUserID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNickname = item.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedUserID.isEmpty, !normalizedNickname.isEmpty else { return nil }
            guard seenUserIDs.insert(normalizedUserID).inserted else { return nil }
            return GroupMemberInviteUser(
                id: normalizedUserID,
                nickname: normalizedNickname,
                primaryPosition: item.primaryPosition,
                secondaryPosition: item.secondaryPosition,
                recentPower: item.recentPower,
                riotDisplayName: item.riotDisplayName,
                profileImageURL: item.profileImageURL
            )
        }
    }

    private func multipartFormBody(
        data: Data,
        fieldName: String,
        fileName: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func fetchPowerProfile(userID: String) async throws -> PowerProfile {
        do {
            let response: PowerProfileDTO = try await apiClient.sendWithoutBody(path: "/users/\(userID)/power-profile")
            let profile = response.toDomain(requestedUserID: userID)
#if DEBUG
            if !response.missingFieldPaths.isEmpty {
                print(
                    "[ProfileRepository] power profile partial userID=\(userID) missingFields=\(response.missingFieldPaths.joined(separator: ",")) primary=\(profile.primaryPosition?.rawValue ?? "nil") secondary=\(profile.secondaryPosition?.rawValue ?? "nil") power=\(Int(profile.overallPower.rounded()))"
                )
            }
#endif
            return profile
        } catch let error as UserFacingError {
#if DEBUG
            print(
                "[ProfileRepository] power profile request failed userID=\(userID) status=\(error.statusCode.map(String.init) ?? "nil") code=\(error.code ?? "nil") message=\(error.message)"
            )
#endif
            throw error
        } catch {
#if DEBUG
            print("[ProfileRepository] power profile decode failed userID=\(userID) error=\(error)")
#endif
            throw error
        }
    }

    private func cachedPowerProfile(for userID: String) -> PowerProfile? {
        powerProfileLock.lock()
        defer { powerProfileLock.unlock() }

        guard let cached = cachedPowerProfiles[userID] else { return nil }
        guard Date().timeIntervalSince(cached.fetchedAt) <= powerProfileCacheTTL else {
            cachedPowerProfiles[userID] = nil
            return nil
        }
        return cached.profile
    }

    private func inFlightPowerProfileRequest(for userID: String) -> Task<PowerProfile, Error>? {
        powerProfileLock.lock()
        defer { powerProfileLock.unlock() }
        return inFlightPowerProfileRequests[userID]
    }

    private func storeInFlightPowerProfileRequest(_ task: Task<PowerProfile, Error>, for userID: String) {
        powerProfileLock.lock()
        inFlightPowerProfileRequests[userID] = task
        powerProfileLock.unlock()
    }

    private func clearInFlightPowerProfileRequest(for userID: String) {
        powerProfileLock.lock()
        inFlightPowerProfileRequests[userID] = nil
        powerProfileLock.unlock()
    }

    private func storeCachedPowerProfile(_ profile: PowerProfile, for userID: String) {
        powerProfileLock.lock()
        cachedPowerProfiles[userID] = CachedPowerProfile(profile: profile, fetchedAt: Date())
        powerProfileLock.unlock()
    }

    private func clearCachedPowerProfile(for userID: String) {
        powerProfileLock.lock()
        cachedPowerProfiles[userID] = nil
        powerProfileLock.unlock()
    }

    private func debugPowerProfile(_ message: String) {
#if DEBUG
        print("[ProfileDebug] \(message)")
#endif
    }
}

final class SafetyRepository {
    private let apiClient: APIClient
    private let blockedUsersEndpointCandidates = ["/blocks", "/me/blocks"]

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func submitReport(target: ReportTarget, reason: ReportReason, detail: String?) async throws {
        // TODO: 서버 신고 스펙 확정 시 endpoint 및 targetType 값을 검증한다.
        let response: EmptyResponse = try await apiClient.send(
            path: "/reports",
            method: .post,
            body: try apiClient.encodedBody(
                ReportRequestDTO(target: target, reason: reason, detail: detail)
            )
        )
        _ = response
    }

    func blockedUsers() async throws -> [BlockedUser] {
        var lastCapabilityError: UserFacingError?
        for path in blockedUsersEndpointCandidates {
            do {
                let response: BlockedUserListDTO = try await apiClient.sendWithoutBody(path: path)
                return response.items
                    .map { $0.toDomain() }
                    .filter { !$0.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            } catch let error as UserFacingError {
                if isCapabilityUnavailable(error) {
                    lastCapabilityError = error
                    continue
                }
                throw error
            }
        }
        throw lastCapabilityError
            ?? UserFacingError(
                title: "차단 목록 조회 실패",
                message: "차단 목록을 불러올 수 없어요.",
                endpoint: blockedUsersEndpointCandidates.first,
                requestMethod: HTTPMethod.get.rawValue
            ).serverContractMapped
    }

    func blockUser(_ target: BlockUserTarget) async throws {
        let response: EmptyResponse = try await apiClient.send(
            path: "/blocks",
            method: .post,
            body: try apiClient.encodedBody(BlockUserRequestDTO(userId: target.userID))
        )
        _ = response
    }

    func unblockUser(userID: String) async throws {
        var lastCapabilityError: UserFacingError?
        for path in ["/blocks/\(userID)", "/users/\(userID)/block"] {
            do {
                let response: EmptyResponse = try await apiClient.sendWithoutBody(
                    path: path,
                    method: .delete
                )
                _ = response
                return
            } catch let error as UserFacingError {
                if isCapabilityUnavailable(error) {
                    lastCapabilityError = error
                    continue
                }
                throw error
            }
        }
        throw lastCapabilityError
            ?? UserFacingError(
                title: "차단 해제 실패",
                message: "차단 해제를 완료할 수 없어요.",
                endpoint: "/blocks/\(userID)",
                requestMethod: HTTPMethod.delete.rawValue
            ).serverContractMapped
    }

    func isCapabilityUnavailable(_ error: UserFacingError) -> Bool {
        switch error.statusCode {
        case 404, 405, 501:
            return true
        default:
            return false
        }
    }
}

final class RiotRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func list() async throws -> [RiotAccount] {
        let response: RiotAccountListDTO = try await apiClient.sendWithoutBody(path: "/riot-accounts")
        return response.items.map { $0.toDomain() }
    }

    func connect(gameName: String, tagLine: String, region: String, isPrimary: Bool) async throws -> RiotAccount {
        let response: RiotAccountDTO = try await apiClient.send(
            path: "/riot-accounts",
            method: .post,
            body: try apiClient.encodedBody(
                CreateRiotAccountRequestDTO(
                    riotGameName: gameName,
                    tagLine: tagLine,
                    region: region,
                    isPrimary: isPrimary
                )
            )
        )
        return response.toDomain()
    }

    func sync(accountID: String) async throws -> RiotAccountSyncAccepted {
        let response: RiotAccountSyncAcceptedDTO = try await apiClient.send(
            path: "/riot-accounts/\(accountID)/sync",
            method: .post
        )
        return response.toDomain()
    }

    func syncStatus(accountID: String) async throws -> RiotAccountSyncState {
        let response: RiotAccountSyncStatusDTO = try await apiClient.sendWithoutBody(
            path: "/riot-accounts/\(accountID)/sync-status"
        )
        return response.toDomain()
    }

    func unlink(accountID: String) async throws {
        let _: EmptyResponse = try await apiClient.send(
            path: "/riot-accounts/\(accountID)",
            method: .delete
        )
    }
}

final class GroupRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func list() async throws -> [GroupSummary] {
        let response: GroupSummaryListDTO = try await apiClient.sendWithoutBody(path: "/groups")
        return response.items.map { $0.toDomain() }
    }

    func listPublic() async throws -> [GroupSummary] {
        let response: GroupSummaryListDTO = try await apiClient.sendWithoutBody(
            path: "/groups/public",
            requiresAuth: false
        )
        return response.items
            .map { $0.toDomain() }
            .filterPubliclyVisible()
    }

    func create(name: String, description: String?, visibility: GroupVisibility, joinPolicy: JoinPolicy, tags: [String]) async throws -> GroupSummary {
        let response: GroupSummaryDTO = try await apiClient.send(
            path: "/groups",
            method: .post,
            body: try apiClient.encodedBody(
                CreateGroupRequestDTO(
                    name: name,
                    description: description,
                    visibility: visibility,
                    joinPolicy: joinPolicy,
                    tags: tags
                )
            )
        )
        return response.toDomain()
    }

    func update(groupID: String, name: String, description: String?, visibility: GroupVisibility, joinPolicy: JoinPolicy, tags: [String]) async throws -> GroupSummary {
        let response: GroupSummaryDTO = try await apiClient.send(
            path: "/groups/\(groupID)",
            method: .patch,
            body: try apiClient.encodedBody(
                UpdateGroupRequestDTO(
                    name: name,
                    description: description,
                    visibility: visibility,
                    joinPolicy: joinPolicy,
                    tags: tags
                )
            )
        )
        return response.toDomain()
    }

    func detail(groupID: String) async throws -> GroupSummary {
        let response: GroupSummaryDTO = try await apiClient.sendWithoutBody(path: "/groups/\(groupID)")
        return response.toDomain()
    }

    func details(groupIDs: [String]) async throws -> [GroupSummary] {
        try await withThrowingTaskGroup(of: GroupSummary.self) { group in
            for id in groupIDs {
                group.addTask { try await self.detail(groupID: id) }
            }
            var items: [GroupSummary] = []
            for try await item in group {
                items.append(item)
            }
            return groupIDs.compactMap { id in items.first(where: { $0.id == id }) }
        }
    }

    func members(groupID: String) async throws -> [GroupMember] {
        let response: GroupMemberListDTO = try await apiClient.sendWithoutBody(path: "/groups/\(groupID)/members")
        return response.items.map { $0.toDomain() }
    }

    func addMember(groupID: String, userID: String, role: GroupRole = .member) async throws -> [GroupMember] {
        let response: GroupMemberListDTO = try await apiClient.send(
            path: "/groups/\(groupID)/members",
            method: .post,
            body: try apiClient.encodedBody(AddGroupMemberRequestDTO(userId: userID, role: role))
        )
        return response.items.map { $0.toDomain() }
    }

    func delete(groupID: String) async throws {
        let _: EmptyResponse = try await apiClient.send(
            path: "/groups/\(groupID)",
            method: .delete
        )
    }
}

final class MatchRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func create(groupID: String, title: String? = nil, notes: String? = nil, scheduledAt: Date? = nil) async throws -> Match {
        let response: MatchResponseDTO = try await apiClient.send(
            path: "/groups/\(groupID)/matches",
            method: .post,
            body: try apiClient.encodedBody(
                CreateMatchRequestDTO(
                    scheduledAt: scheduledAt.map { ISO8601DateFormatter.simple.string(from: $0) },
                    title: title,
                    notes: notes
                )
            )
        )
        return response.toDomain()
    }

    func detail(matchID: String) async throws -> Match {
        let response: MatchResponseDTO = try await apiClient.sendWithoutBody(path: "/matches/\(matchID)")
        return response.toDomain()
    }

    func addPlayers(matchID: String, players: [MatchPlayerInputDTO]) async throws -> Match {
        let response: MatchResponseDTO = try await apiClient.send(
            path: "/matches/\(matchID)/players",
            method: .post,
            body: try apiClient.encodedBody(AddPlayersRequestDTO(players: players))
        )
        return response.toDomain()
    }

    func lock(matchID: String) async throws -> Match {
        let response: MatchResponseDTO = try await apiClient.send(path: "/matches/\(matchID)/lock", method: .post)
        return response.toDomain()
    }

    func autoBalance(matchID: String, mode: BalanceMode? = .balanced, lockedPlayerIDs: [String] = []) async throws -> [MatchCandidate] {
        let response: MatchmakingCandidatesDTO = try await apiClient.send(
            path: "/matches/\(matchID)/auto-balance",
            method: .post,
            body: try apiClient.encodedBody(AutoBalanceRequestDTO(mode: mode, lockedPlayerIds: lockedPlayerIDs))
        )
        return response.candidates.map { $0.toDomain() }
    }

    func reroll(matchID: String, mode: BalanceMode?, lockedPlayerIDs: [String] = [], excludeCandidateIDs: [String]) async throws -> [MatchCandidate] {
        let response: MatchmakingCandidatesDTO = try await apiClient.send(
            path: "/matches/\(matchID)/reroll",
            method: .post,
            body: try apiClient.encodedBody(
                RerollRequestDTO(
                    mode: mode,
                    lockedPlayerIds: lockedPlayerIDs,
                    excludeCandidateIds: excludeCandidateIDs
                )
            )
        )
        return response.candidates.map { $0.toDomain() }
    }

    func previewBalance(draft: TeamBalancePreviewDraft) async throws -> TeamBalancePreviewResult {
        let response: BalancePreviewResponseDTO = try await apiClient.send(
            path: "/matches/balance/preview",
            method: .post,
            body: try apiClient.encodedBody(
                BalancePreviewRequestDTO(
                    mode: draft.selectedMode,
                    players: Array(draft.sanitizedPlayers.prefix(10)).map {
                        PreviewRosterPlayerInputDTO(
                            nickname: $0.sanitizedName,
                            preferredPosition: $0.preferredPosition,
                            score: $0.clampedScore
                        )
                    }
                )
            ),
            requiresAuth: false
        )
        return response.toDomain(fallbackMode: draft.selectedMode)
    }

    func previewResult(draft: ResultPreviewDraft) async throws -> ResultPreviewValidation {
        let response: ResultPreviewResponseDTO = try await apiClient.send(
            path: "/matches/result/preview",
            method: .post,
            body: try apiClient.encodedBody(
                ResultPreviewRequestDTO(
                    winningTeam: draft.winningTeam,
                    balanceRating: draft.balanceRating,
                    mvpNickname: draft.selectedMVPName,
                    players: draft.sanitizedPlayers.map {
                        ResultPreviewPlayerInputDTO(
                            nickname: $0.name,
                            teamSide: $0.teamSide,
                            role: $0.role
                        )
                    }
                )
            ),
            requiresAuth: false
        )
        return response.toDomain()
    }

    func selectCandidate(matchID: String, candidateNo: Int) async throws -> Match {
        let response: MatchResponseDTO = try await apiClient.send(
            path: "/matches/\(matchID)/select-candidate",
            method: .post,
            body: try apiClient.encodedBody(SelectCandidateRequestDTO(candidateNo: candidateNo))
        )
        return response.toDomain()
    }

    func result(matchID: String) async throws -> MatchResult {
        let response: MatchResultDTO = try await apiClient.sendWithoutBody(path: "/matches/\(matchID)/results")
        return response.toDomain()
    }

    func submitQuickResult(matchID: String, payload: QuickResultRequestDTO) async throws -> ResultSubmissionStatus {
        let response: ResultSubmissionDTO = try await apiClient.send(
            path: "/matches/\(matchID)/results/quick",
            method: .post,
            body: try apiClient.encodedBody(payload),
            headers: ["idempotency-key": UUID().uuidString]
        )
        return response.toDomain()
    }

    func confirmResult(matchID: String, resultID: String, action: ConfirmationAction, diff: [String: String]? = nil, comment: String? = nil) async throws -> ResultSubmissionStatus {
        let response: ResultSubmissionDTO = try await apiClient.send(
            path: "/matches/\(matchID)/results/\(resultID)/confirm",
            method: .post,
            body: try apiClient.encodedBody(ConfirmResultRequestDTO(action: action, diff: diff, comment: comment))
        )
        return response.toDomain()
    }
}

final class RecruitingRepository {
    private let apiClient: APIClient
    private let applyEndpointPatterns = [
        "/recruiting-posts/%@/apply",
        "/recruiting-posts/%@/participants",
        "/recruiting-posts/%@/join",
    ]

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func list(type: RecruitingPostType? = nil, groupID: String? = nil, status: RecruitingPostStatus? = .open) async throws -> [RecruitPost] {
        try await list(
            query: RecruitPostListQuery(
                postType: type,
                groupID: groupID,
                status: status
            )
        )
    }

    func list(query: RecruitPostListQuery) async throws -> [RecruitPost] {
        let queryItems = buildListQueryItems(from: query)
        debugRecruitListRequest(path: "/recruiting-posts", queryItems: queryItems, includeUnscheduledSent: false)
        let response: RecruitPostListDTO = try await apiClient.sendWithoutBody(
            path: "/recruiting-posts",
            queryItems: queryItems
        )
        return response.items.map { $0.toDomain() }
    }

    func listPublic(type: RecruitingPostType? = nil, status: RecruitingPostStatus? = .open) async throws -> [RecruitPost] {
        try await listPublic(
            query: RecruitPostListQuery(
                postType: type,
                status: status
            )
        )
    }

    func listPublic(query: RecruitPostListQuery) async throws -> [RecruitPost] {
        let queryItems = buildListQueryItems(from: query, allowsGroupID: false)
        debugRecruitListRequest(path: "/recruiting-posts/public", queryItems: queryItems, includeUnscheduledSent: false)
        let response: RecruitPostListDTO = try await apiClient.sendWithoutBody(
            path: "/recruiting-posts/public",
            queryItems: queryItems,
            requiresAuth: false
        )
        return response.items.map { $0.toDomain() }
    }

    private func buildListQueryItems(from query: RecruitPostListQuery, allowsGroupID: Bool = true) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = []
        if let type = query.postType {
            queryItems.append(URLQueryItem(name: "postType", value: type.rawValue))
        }
        if allowsGroupID,
           let groupID = query.groupID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !groupID.isEmpty
        {
            queryItems.append(URLQueryItem(name: "groupId", value: groupID))
        }
        if let status = query.status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let scheduledFrom = query.scheduledFrom {
            queryItems.append(URLQueryItem(name: "scheduledFrom", value: ISO8601DateFormatter.simple.string(from: scheduledFrom)))
        }
        if let scheduledTo = query.scheduledTo {
            queryItems.append(URLQueryItem(name: "scheduledTo", value: ISO8601DateFormatter.simple.string(from: scheduledTo)))
        }
        let requiredPositions = sanitizedQueryValues(query.requiredPositions)
        if !requiredPositions.isEmpty {
            queryItems.append(contentsOf: requiredPositions.map { URLQueryItem(name: "requiredPositions", value: $0) })
        }
        let regions = sanitizedQueryValues(query.regions)
        if !regions.isEmpty {
            queryItems.append(contentsOf: regions.map { URLQueryItem(name: "region", value: $0) })
        }
        let tags = sanitizedQueryValues(query.tags)
        if !tags.isEmpty {
            queryItems.append(contentsOf: tags.map { URLQueryItem(name: "tags", value: $0) })
        }
        return queryItems
    }

    private func sanitizedQueryValues(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func debugRecruitListRequest(path: String, queryItems: [URLQueryItem], includeUnscheduledSent: Bool) {
#if DEBUG
        let queryDescription = queryItems.isEmpty
            ? "<none>"
            : queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        print("[RecruitListRequest] endpoint=\(path) query=\(queryDescription)")
        print("[RecruitListRequest] includeUnscheduled sent=\(includeUnscheduledSent)")
#endif
    }

    func detail(postID: String) async throws -> RecruitPost {
        let response: RecruitPostDTO = try await apiClient.sendWithoutBody(path: "/recruiting-posts/\(postID)")
        return response.toDomain()
    }

    func apply(postID: String) async throws -> RecruitPost {
        var lastCapabilityError: UserFacingError?

        for pathPattern in applyEndpointPatterns {
            let path = String(format: pathPattern, postID)
            do {
                let _: EmptyResponse = try await apiClient.send(path: path, method: .post)
                return try await detail(postID: postID)
            } catch let error as UserFacingError {
                if error.requiresAuthentication {
                    throw error
                }
                if isCapabilityUnavailable(error) {
                    lastCapabilityError = error
                    continue
                }
                throw error
            }
        }

        throw lastCapabilityError
            ?? UserFacingError(
                title: "참가 신청 실패",
                message: "참가 신청 기능을 확인하지 못했습니다.",
                endpoint: "/recruiting-posts/\(postID)",
                requestMethod: HTTPMethod.post.rawValue
            )
    }

    func isCapabilityUnavailable(_ error: UserFacingError) -> Bool {
        switch error.statusCode {
        case 404, 405, 501:
            return true
        default:
            return false
        }
    }

    func delete(postID: String) async throws {
        let _: EmptyResponse = try await apiClient.send(
            path: "/recruiting-posts/\(postID)",
            method: .delete
        )
    }

    func update(postID: String, type: RecruitingPostType, title: String, body: String?, tags: [String], scheduledAt: Date?, requiredPositions: [String]) async throws -> RecruitPost {
        let response: RecruitPostDTO = try await apiClient.send(
            path: "/recruiting-posts/\(postID)",
            method: .patch,
            body: try apiClient.encodedBody(
                UpdateRecruitPostRequestDTO(
                    postType: type,
                    title: title,
                    body: body,
                    tags: tags,
                    scheduledAt: scheduledAt.map { ISO8601DateFormatter.simple.string(from: $0) },
                    requiredPositions: requiredPositions
                )
            )
        )
        return response.toDomain()
    }

    func create(groupID: String, type: RecruitingPostType, title: String, body: String?, tags: [String], scheduledAt: Date?, requiredPositions: [String]) async throws -> RecruitPost {
        let response: RecruitPostDTO = try await apiClient.send(
            path: "/recruiting-posts",
            method: .post,
            body: try apiClient.encodedBody(
                CreateRecruitPostRequestDTO(
                    groupId: groupID,
                    postType: type,
                    title: title,
                    body: body,
                    tags: tags,
                    scheduledAt: scheduledAt.map { ISO8601DateFormatter.simple.string(from: $0) },
                    requiredPositions: requiredPositions
                )
            )
        )
        return response.toDomain()
    }
}

struct SearchRepositoryPayload {
    let groups: [GroupSummary]
    let recruitingPosts: [RecruitPost]
}

protocol SearchRepository {
    func loadSearchableResources(forceRefresh: Bool) async -> SearchRepositoryPayload
}

final class LiveSearchRepository: SearchRepository {
    private let groupRepository: GroupRepository
    private let recruitingRepository: RecruitingRepository
    private var cachedPayload: SearchRepositoryPayload?
    private var cacheDate: Date?

    init(groupRepository: GroupRepository, recruitingRepository: RecruitingRepository) {
        self.groupRepository = groupRepository
        self.recruitingRepository = recruitingRepository
    }

    func loadSearchableResources(forceRefresh: Bool = false) async -> SearchRepositoryPayload {
        if
            !forceRefresh,
            let cachedPayload,
            let cacheDate,
            Date().timeIntervalSince(cacheDate) < 60
        {
            return cachedPayload
        }

        async let groupsTask: [GroupSummary]? = try? await groupRepository.listPublic()
        async let recruitingPostsTask: [RecruitPost]? = try? await recruitingRepository.listPublic(status: .open)

        let payload = SearchRepositoryPayload(
            groups: await groupsTask ?? [],
            recruitingPosts: await recruitingPostsTask ?? []
        )

        cachedPayload = payload
        cacheDate = Date()
        return payload
    }
}

final class SearchUseCase {
    private let repository: any SearchRepository

    init(repository: any SearchRepository) {
        self.repository = repository
    }

    func execute(
        query: String,
        linkedRiotAccounts: [RiotAccount],
        forceRefresh: Bool = false
    ) async -> SearchResponse {
        let tokens = query.searchTokens
        guard !tokens.isEmpty else {
            return SearchResponse(sections: [])
        }

        let payload = await repository.loadSearchableResources(forceRefresh: forceRefresh)

        let riotItems = linkedRiotAccounts
            .filter { account in
                searchMatches(tokens: tokens, fields: [
                    account.riotGameName,
                    account.tagLine,
                    account.displayName,
                    account.region,
                    account.syncStatusSummary,
                ])
            }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary {
                    return lhs.isPrimary && !rhs.isPrimary
                }
                return lhs.displayName < rhs.displayName
            }
            .map {
                SearchResultItem(
                    id: "riot-\($0.id)",
                    kind: .riotAccount,
                    title: $0.displayName,
                    subtitle: "\($0.region.uppercased()) · \($0.verificationStatus.title)",
                    tags: [$0.isPrimary ? "기준 Riot ID" : "참고 Riot ID", $0.syncUIState.title],
                    supportingText: $0.syncStatusSummary,
                    destination: .riotAccounts
                )
            }

        let groupItems = payload.groups
            .filterPubliclyVisible()
            .filter { group in
                searchMatches(tokens: tokens, fields: [
                    group.name,
                    group.description ?? "",
                    group.tags.joined(separator: " "),
                ])
            }
            .sorted { lhs, rhs in
                if lhs.recentMatches != rhs.recentMatches {
                    return lhs.recentMatches > rhs.recentMatches
                }
                return lhs.name < rhs.name
            }
            .map { group in
                SearchResultItem(
                    id: "group-\(group.id)",
                    kind: .group,
                    title: group.name,
                    subtitle: "멤버 \(group.memberCount)명 · \(group.completedInhouseDisplay.summaryText)",
                    tags: Array(group.tags.prefix(3)),
                    supportingText: group.description,
                    destination: .groupDetail(groupID: group.id, isAccessible: group.isAccessible())
                )
            }

        let postItems = payload.recruitingPosts
            .filter { post in
                searchMatches(tokens: tokens, fields: [
                    post.title,
                    post.body ?? "",
                    post.groupID,
                    post.tags.joined(separator: " "),
                    post.requiredPositions.joined(separator: " "),
                ])
            }
            .sorted { lhs, rhs in
                switch (lhs.scheduledAt, rhs.scheduledAt) {
                case let (left?, right?):
                    if left == right {
                        return lhs.title < rhs.title
                    }
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title < rhs.title
                }
            }
            .map { post in
                SearchResultItem(
                    id: "recruit-\(post.id)",
                    kind: .recruitPost,
                    title: post.title,
                    subtitle: [post.groupID, post.scheduledAt?.shortDateText].compactMap { $0 }.joined(separator: " · "),
                    tags: Array((post.requiredPositions + post.tags).filter { !$0.isEmpty }.prefix(4)),
                    supportingText: post.body,
                    destination: .recruitDetail(postID: post.id)
                )
            }

        let allSections = [
            SearchResultSection(kind: .riotAccount, items: riotItems),
            SearchResultSection(kind: .group, items: groupItems),
            SearchResultSection(kind: .recruitPost, items: postItems),
        ]
        .filter { !$0.items.isEmpty }

        return SearchResponse(sections: allSections)
    }

    private func searchMatches(tokens: [String], fields: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let haystack = fields.joined(separator: " ").searchableText
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

private extension String {
    var searchableText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var searchTokens: [String] {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(\.searchableText)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Container

enum NotificationAuthorizationState: String, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .provisional, .ephemeral:
            self = .provisional
        case .denied:
            self = .denied
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }

    var canRegisterRemoteNotifications: Bool {
        switch self {
        case .authorized, .provisional:
            return true
        case .notDetermined, .denied:
            return false
        }
    }
}

enum NotificationPermissionPrimaryAction: Equatable {
    case showPrePrompt
    case openSettings
    case none
}

@MainActor
protocol NotificationAuthorizationProviding {
    func authorizationStatus() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
}

@MainActor
protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications()
}

@MainActor
protocol ApplicationSettingsOpening {
    func openNotificationSettings()
}

@MainActor
protocol PushTokenSynchronizing {
    func syncPushToken(_ deviceToken: String, notificationsEnabled: Bool) async
}

@MainActor
struct NoopPushTokenSynchronizer: PushTokenSynchronizing {
    func syncPushToken(_: String, notificationsEnabled _: Bool) async {}
}

@MainActor
final class UserNotificationCenterAuthorizationProvider: NotificationAuthorizationProviding {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationState {
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
        return NotificationAuthorizationState(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }
}

@MainActor
struct UIApplicationRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

@MainActor
struct UIApplicationSettingsOpener: ApplicationSettingsOpening {
    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

@MainActor
final class NotificationPermissionManager: ObservableObject {
    @Published private(set) var authorizationState: NotificationAuthorizationState
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var lastRegistrationErrorDescription: String?
    @Published private(set) var lastRegisteredDeviceToken: String?

    private let authorizationProvider: NotificationAuthorizationProviding
    private let remoteNotificationRegistrar: RemoteNotificationRegistering
    private let settingsOpener: ApplicationSettingsOpening
    private let pushTokenSynchronizer: PushTokenSynchronizing
    private var hasAttemptedRemoteRegistrationThisLaunch = false
    private var lastSyncedTokenState: (token: String, isEnabled: Bool)?

    init(
        authorizationProvider: NotificationAuthorizationProviding? = nil,
        remoteNotificationRegistrar: RemoteNotificationRegistering? = nil,
        settingsOpener: ApplicationSettingsOpening? = nil,
        pushTokenSynchronizer: PushTokenSynchronizing? = nil,
        initialAuthorizationState: NotificationAuthorizationState = .notDetermined
    ) {
        self.authorizationProvider = authorizationProvider ?? UserNotificationCenterAuthorizationProvider()
        self.remoteNotificationRegistrar = remoteNotificationRegistrar ?? UIApplicationRemoteNotificationRegistrar()
        self.settingsOpener = settingsOpener ?? UIApplicationSettingsOpener()
        self.pushTokenSynchronizer = pushTokenSynchronizer ?? NoopPushTokenSynchronizer()
        self.authorizationState = initialAuthorizationState
    }

    var canUseNotifications: Bool {
        authorizationState.canRegisterRemoteNotifications
    }

    func refreshAuthorizationStatus(registerIfNeeded: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let resolvedState = await authorizationProvider.authorizationStatus()
        authorizationState = resolvedState
        isRefreshing = false

        if resolvedState.canRegisterRemoteNotifications {
            lastRegistrationErrorDescription = nil
            if registerIfNeeded {
                registerForRemoteNotificationsIfNeeded()
            }
            return
        }

        hasAttemptedRemoteRegistrationThisLaunch = false
        await syncStoredTokenIfNeeded(isEnabled: false)
    }

    func resolvePrimaryAction() async -> NotificationPermissionPrimaryAction {
        await refreshAuthorizationStatus(registerIfNeeded: false)

        switch authorizationState {
        case .notDetermined:
            return .showPrePrompt
        case .denied:
            return .openSettings
        case .authorized, .provisional:
            registerForRemoteNotificationsIfNeeded()
            return .none
        }
    }

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorizationState {
        guard !isRequestingAuthorization else { return authorizationState }

        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        do {
            _ = try await authorizationProvider.requestAuthorization()
            lastRegistrationErrorDescription = nil
        } catch {
            lastRegistrationErrorDescription = error.localizedDescription
        }

        await refreshAuthorizationStatus(registerIfNeeded: true)
        return authorizationState
    }

    func openSystemSettings() {
        settingsOpener.openNotificationSettings()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        lastRegisteredDeviceToken = token
        lastRegistrationErrorDescription = nil
        guard authorizationState.canRegisterRemoteNotifications else { return }
        await syncStoredTokenIfNeeded(isEnabled: true)
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        hasAttemptedRemoteRegistrationThisLaunch = false
        lastRegistrationErrorDescription = error.localizedDescription
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard authorizationState.canRegisterRemoteNotifications else { return }
        guard !hasAttemptedRemoteRegistrationThisLaunch else { return }
        hasAttemptedRemoteRegistrationThisLaunch = true
        remoteNotificationRegistrar.registerForRemoteNotifications()
    }

    private func syncStoredTokenIfNeeded(isEnabled: Bool) async {
        guard let token = lastRegisteredDeviceToken else { return }
        if !isEnabled && lastSyncedTokenState == nil {
            return
        }
        if let lastSyncedTokenState,
           lastSyncedTokenState.token == token,
           lastSyncedTokenState.isEnabled == isEnabled {
            return
        }
        await pushTokenSynchronizer.syncPushToken(token, notificationsEnabled: isEnabled)
        lastSyncedTokenState = (token, isEnabled)
    }
}

@MainActor
final class NotificationApplicationDelegate: NSObject, UIApplicationDelegate {
    var notificationPermissionManager: NotificationPermissionManager?

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await notificationPermissionManager?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        notificationPermissionManager?.didFailToRegisterForRemoteNotifications(error: error)
    }
}

@MainActor
final class AppContainer {
    let configuration: AppConfiguration
    let modelContainer: ModelContainer
    let tokenStore: TokenStore
    let localStore: AppLocalStore
    let apiClient: APIClient
    let authRepository: AuthRepository
    let profileRepository: ProfileRepository
    let safetyRepository: SafetyRepository
    let riotRepository: RiotRepository
    let groupRepository: GroupRepository
    let matchRepository: MatchRepository
    let recruitingRepository: RecruitingRepository
    let searchRepository: any SearchRepository
    let searchUseCase: SearchUseCase
    let notificationPermissionManager: NotificationPermissionManager

    init(
        configuration: AppConfiguration = .load(),
        modelContainer: ModelContainer = AppModelContainerFactory.makeContainer(),
        tokenStore: TokenStore = TokenStore(),
        localStore: AppLocalStore? = nil,
        notificationPermissionManager: NotificationPermissionManager? = nil,
        urlSession: URLSession = .shared
    ) {
        let resolvedLocalStore = localStore ?? AppLocalStore(defaults: .standard, modelContainer: modelContainer)
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.tokenStore = tokenStore
        self.localStore = resolvedLocalStore
        self.apiClient = APIClient(configuration: configuration, tokenStore: tokenStore, session: urlSession)
        self.authRepository = AuthRepository(apiClient: apiClient, tokenStore: tokenStore)
        self.profileRepository = ProfileRepository(apiClient: apiClient)
        self.safetyRepository = SafetyRepository(apiClient: apiClient)
        self.riotRepository = RiotRepository(apiClient: apiClient)
        self.groupRepository = GroupRepository(apiClient: apiClient)
        self.matchRepository = MatchRepository(apiClient: apiClient)
        self.recruitingRepository = RecruitingRepository(apiClient: apiClient)
        self.notificationPermissionManager = notificationPermissionManager ?? NotificationPermissionManager()
        self.searchRepository = LiveSearchRepository(
            groupRepository: groupRepository,
            recruitingRepository: recruitingRepository
        )
        self.searchUseCase = SearchUseCase(repository: searchRepository)
        Self.logConfiguration(configuration)
    }

    private static func logConfiguration(_ configuration: AppConfiguration) {
        print("[AppContainer] Environment -> \(configuration.environment.rawValue)")
        print("[AppContainer] REST base URL -> \(configuration.baseURL.absoluteString)")
        print("[AppContainer] Public WS URL -> \(configuration.publicWebSocketURL.absoluteString)")
        print("[AppContainer] Private WS URL -> \(configuration.privateWebSocketURL.absoluteString)")
    }
}
