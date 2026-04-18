import Foundation
import Security
import SwiftData

enum AppEnvironment: String, Equatable {
    case dev
    case staging
    case production
}

struct AppConfiguration {
    let environment: AppEnvironment
    let baseURL: URL
    let googleClientID: String

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        fromInfoDictionary(bundle.infoDictionary ?? [:])
    }

    static func fromInfoDictionary(_ infoDictionary: [String: Any]) -> AppConfiguration {
        let environment = AppEnvironment(
            rawValue: stringValue(for: "APP_ENV", in: infoDictionary)?.lowercased() ?? ""
        ) ?? .dev

        let rawValue = stringValue(for: "API_BASE_URL", in: infoDictionary)
        let fallback = "http://127.0.0.1:3000"
        let url = URL(string: rawValue ?? fallback) ?? URL(string: fallback)!
        let rawGoogleClientID = stringValue(for: "GIDClientID", in: infoDictionary)
        let googleClientID = (rawGoogleClientID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? rawGoogleClientID!.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return AppConfiguration(
            environment: environment,
            baseURL: url,
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
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .product:
            return "InhouseMaker"
        case .support:
            return "문의하기"
        case .terms:
            return "이용약관"
        case .privacy:
            return "개인정보처리방침"
        }
    }

    var url: URL {
        switch self {
        case .product:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal")!
        case .support:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/support.html")!
        case .terms:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/community.html")!
        case .privacy:
            return URL(string: "https://hwangseokbeom.github.io/InhouseMaker-legal/privacy.html")!
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

private enum LocalStoreKey {
    static let groupIDs = "local.group.ids"
    static let recentMatches = "local.recent.matches"
    static let cachedResults = "local.cached.results"
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
        let groupIDs = persistenceStore.storedGroupIDs()
        return groupIDs.isEmpty ? (defaults.stringArray(forKey: LocalStoreKey.groupIDs) ?? []) : groupIDs
    }

    var recentMatches: [RecentMatchContext] {
        let recentMatches = persistenceStore.recentMatches()
        return recentMatches.isEmpty ? (decode([RecentMatchContext].self, forKey: LocalStoreKey.recentMatches) ?? []) : recentMatches
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

    func cacheResult(matchID: String, metadata: CachedResultMetadata) {
        persistenceStore.cacheResult(matchID: matchID, metadata: metadata)
        var current = cachedResults
        current[matchID] = metadata
        save(current, forKey: LocalStoreKey.cachedResults)
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

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder.app.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.app.decode(type, from: data)
    }

    private var legacyOnboardingStatus: OnboardingStatus? {
        guard let rawValue = defaults.string(forKey: LocalStoreKey.onboardingStatus) else { return nil }
        return OnboardingStatus(rawValue: rawValue)
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
            LocalStoreKey.manualAdjustDrafts,
            LocalStoreKey.notifications,
            LocalStoreKey.recentSearchKeywords,
            LocalStoreKey.recruitFilterType,
            LocalStoreKey.teamBalancePreviewDraft,
            LocalStoreKey.resultPreviewDraft,
        ].contains { defaults.object(forKey: $0) != nil }
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
            throw APIClientError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
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
                path: "/auth/refresh",
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
        path == "/auth/signup/email"
            || path == "/auth/login/email"
            || path == "/me"
            || path == "/groups"
            || path.hasPrefix("/groups/")
            || path == "/recruiting-posts"
            || path.hasPrefix("/recruiting-posts/")
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
    let nickname: String?
}

struct GoogleLoginRequestDTO: Encodable {
    let idToken: String
    let accessToken: String?
    let email: String?
    let name: String?
}

struct EmailSignUpRequestDTO: Encodable {
    let email: String
    let password: String
    let nickname: String
    let agreedToTerms: Bool
    let agreedToPrivacy: Bool
    let agreedToMarketing: Bool
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

struct UserProfileDTO: Codable {
    let id: String
    let email: String
    let nickname: String
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let isFillAvailable: Bool
    let styleTags: [String]
    let mannerScore: Double
    let noshowCount: Int

    func toDomain() -> UserProfile {
        UserProfile(
            id: id,
            email: email,
            nickname: nickname,
            primaryPosition: primaryPosition,
            secondaryPosition: secondaryPosition,
            isFillAvailable: isFillAvailable,
            styleTags: styleTags,
            mannerScore: mannerScore,
            noshowCount: noshowCount
        )
    }
}

struct UpdateProfileRequestDTO: Encodable {
    let primaryPosition: Position?
    let secondaryPosition: Position?
    let isFillAvailable: Bool
    let styleTags: [String]
    let nickname: String
}

struct PowerProfileDTO: Codable {
    struct StyleDTO: Codable {
        let stability: Double
        let carry: Double
        let teamContribution: Double
        let laneInfluence: Double
    }

    let userId: String
    let overallPower: Double
    let lanePower: [String: Double]
    let style: StyleDTO
    let basePower: Double
    let formScore: Double
    let inhouseMmr: Double
    let inhouseConfidence: Double
    let version: String
    let calculatedAt: Date

    func toDomain() -> PowerProfile {
        PowerProfile(
            userID: userId,
            overallPower: overallPower,
            lanePower: Dictionary(uniqueKeysWithValues: lanePower.compactMap { key, value in
                guard let position = Position(rawValue: key) else { return nil }
                return (position, value)
            }),
            stability: style.stability,
            carry: style.carry,
            teamContribution: style.teamContribution,
            laneInfluence: style.laneInfluence,
            basePower: basePower,
            formScore: formScore,
            inhouseMMR: inhouseMmr,
            inhouseConfidence: inhouseConfidence,
            version: version,
            calculatedAt: calculatedAt
        )
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
        ownerUserId: String,
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
        self.ownerUserId = ownerUserId
        self.memberCount = memberCount
        self.recentMatches = recentMatches
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
            memberCount: memberCount,
            recentMatches: recentMatches
        )
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
                path: "/auth/login/apple",
                method: .post,
                body: try apiClient.encodedBody(
                    AppleLoginRequestDTO(
                        identityToken: authorization.identityToken,
                        nickname: authorization.nickname
                    )
                ),
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
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: "/auth/login/google",
                method: .post,
                body: try apiClient.encodedBody(
                    GoogleLoginRequestDTO(
                        idToken: authorization.idToken,
                        accessToken: authorization.accessToken,
                        email: authorization.email,
                        name: authorization.name
                    )
                ),
                requiresAuth: false
            )
            let tokens = response.toDomain()
            await tokenStore.save(tokens: tokens)
            return tokens
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    func signUpWithEmail(
        email: String,
        password: String,
        nickname: String,
        agreedToTerms: Bool,
        agreedToPrivacy: Bool,
        agreedToMarketing: Bool
    ) async throws -> AuthTokens {
        do {
            let response: AuthTokensDTO = try await apiClient.send(
                path: "/auth/signup/email",
                method: .post,
                body: try apiClient.encodedBody(
                    EmailSignUpRequestDTO(
                        email: email,
                        password: password,
                        nickname: nickname,
                        agreedToTerms: agreedToTerms,
                        agreedToPrivacy: agreedToPrivacy,
                        agreedToMarketing: agreedToMarketing
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
                path: "/auth/login/email",
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
                path: "/auth/logout",
                method: .post,
                body: try? apiClient.encodedBody(LogoutRequestDTO(refreshToken: refreshToken)),
                requiresAuth: false
            )
            _ = response
        }
        await tokenStore.clear()
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
}

final class ProfileRepository {
    private let apiClient: APIClient

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
        return response.toDomain()
    }

    func powerProfile(userID: String) async throws -> PowerProfile {
        let response: PowerProfileDTO = try await apiClient.sendWithoutBody(path: "/users/\(userID)/power-profile")
        return response.toDomain()
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
                    subtitle: "멤버 \(group.memberCount)명 · 최근 내전 \(group.recentMatches)회",
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
}

// MARK: - Container

@MainActor
final class AppContainer {
    let configuration: AppConfiguration
    let modelContainer: ModelContainer
    let tokenStore: TokenStore
    let localStore: AppLocalStore
    let apiClient: APIClient
    let authRepository: AuthRepository
    let profileRepository: ProfileRepository
    let riotRepository: RiotRepository
    let groupRepository: GroupRepository
    let matchRepository: MatchRepository
    let recruitingRepository: RecruitingRepository
    let searchRepository: any SearchRepository
    let searchUseCase: SearchUseCase

    init(
        configuration: AppConfiguration = .load(),
        modelContainer: ModelContainer = AppModelContainerFactory.makeContainer(),
        tokenStore: TokenStore = TokenStore(),
        localStore: AppLocalStore? = nil,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.tokenStore = tokenStore
        self.localStore = localStore ?? AppLocalStore(defaults: .standard, modelContainer: modelContainer)
        self.apiClient = APIClient(configuration: configuration, tokenStore: tokenStore, session: urlSession)
        self.authRepository = AuthRepository(apiClient: apiClient, tokenStore: tokenStore)
        self.profileRepository = ProfileRepository(apiClient: apiClient)
        self.riotRepository = RiotRepository(apiClient: apiClient)
        self.groupRepository = GroupRepository(apiClient: apiClient)
        self.matchRepository = MatchRepository(apiClient: apiClient)
        self.recruitingRepository = RecruitingRepository(apiClient: apiClient)
        self.searchRepository = LiveSearchRepository(
            groupRepository: groupRepository,
            recruitingRepository: recruitingRepository
        )
        self.searchUseCase = SearchUseCase(repository: searchRepository)
    }
}
