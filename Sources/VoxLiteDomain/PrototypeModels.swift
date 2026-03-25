import Foundation

public enum MainModule: String, Codable, CaseIterable, Sendable {
    case welcome
    case home
    case skills
    case settings
}

public enum SkillType: String, Codable, Sendable {
    case preinstalled
    case custom
}

public struct SkillProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var type: SkillType
    public var template: String
    public var styleHint: String

    public init(id: String, name: String, type: SkillType, template: String, styleHint: String) {
        self.id = id
        self.name = name
        self.type = type
        self.template = template
        self.styleHint = styleHint
    }
}

public struct SkillMatchingConfig: Codable, Equatable, Sendable {
    public var bundleSkillMap: [String: String]
    public var bundleDisplayNameMap: [String: String]
    public var categorySkillMap: [AppCategory: String]
    public var defaultSkillId: String

    public init(
        bundleSkillMap: [String: String],
        bundleDisplayNameMap: [String: String] = [:],
        categorySkillMap: [AppCategory: String],
        defaultSkillId: String
    ) {
        self.bundleSkillMap = bundleSkillMap
        self.bundleDisplayNameMap = bundleDisplayNameMap
        self.categorySkillMap = categorySkillMap
        self.defaultSkillId = defaultSkillId
    }

    enum CodingKeys: String, CodingKey {
        case bundleSkillMap
        case bundleDisplayNameMap
        case categorySkillMap
        case defaultSkillId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleSkillMap = try container.decode([String: String].self, forKey: .bundleSkillMap)
        bundleDisplayNameMap = try container.decodeIfPresent([String: String].self, forKey: .bundleDisplayNameMap) ?? [:]
        categorySkillMap = try container.decode([AppCategory: String].self, forKey: .categorySkillMap)
        defaultSkillId = try container.decode(String.self, forKey: .defaultSkillId)
    }
}

public struct AppBinding: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { bundleId }
    public let bundleId: String
    public let appName: String

    public init(bundleId: String, appName: String) {
        self.bundleId = bundleId
        self.appName = appName
    }
}

public struct SkillConfigSnapshot: Codable, Equatable, Sendable {
    public var profiles: [SkillProfile]
    public var matching: SkillMatchingConfig

    public init(profiles: [SkillProfile], matching: SkillMatchingConfig) {
        self.profiles = profiles
        self.matching = matching
    }
}

public struct TranscriptHistoryItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let appName: String
    public let bundleId: String
    public let skillId: String
    public let skillName: String
    public let sourceText: String
    public let outputText: String
    public let succeeded: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        appName: String,
        bundleId: String,
        skillId: String,
        skillName: String,
        sourceText: String,
        outputText: String,
        succeeded: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.appName = appName
        self.bundleId = bundleId
        self.skillId = skillId
        self.skillName = skillName
        self.sourceText = sourceText
        self.outputText = outputText
        self.succeeded = succeeded
    }
}

public enum MenuBarDisplayMode: String, Codable, Sendable {
    case iconOnly
    case iconAndSummary
}

public struct ModelSetting: Codable, Equatable, Sendable {
    public var localEnabled: Bool
    public var remoteProvider: String
    public var remoteEndpoint: String

    public init(localEnabled: Bool, remoteProvider: String, remoteEndpoint: String) {
        self.localEnabled = localEnabled
        self.remoteProvider = remoteProvider
        self.remoteEndpoint = remoteEndpoint
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotKeyDescription: String
    public var launchAtLoginEnabled: Bool
    public var menuBarDisplayMode: MenuBarDisplayMode
    public var showRecentSummary: Bool
    public var summaryMaxLength: Int
    public var historyLimit: Int
    public var speechModel: ModelSetting
    public var llmModel: ModelSetting
    public var onboardingCompleted: Bool

    public init(
        hotKeyDescription: String,
        launchAtLoginEnabled: Bool,
        menuBarDisplayMode: MenuBarDisplayMode,
        showRecentSummary: Bool,
        summaryMaxLength: Int,
        historyLimit: Int,
        speechModel: ModelSetting,
        llmModel: ModelSetting,
        onboardingCompleted: Bool = false
    ) {
        self.hotKeyDescription = hotKeyDescription
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.menuBarDisplayMode = menuBarDisplayMode
        self.showRecentSummary = showRecentSummary
        self.summaryMaxLength = summaryMaxLength
        self.historyLimit = historyLimit
        self.speechModel = speechModel
        self.llmModel = llmModel
        self.onboardingCompleted = onboardingCompleted
    }
}
