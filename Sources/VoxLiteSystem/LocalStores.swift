import Foundation
import VoxLiteDomain

public final class FileHistoryStore: HistoryStore {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        self.fileURL = FileHistoryStore.makeFileURL(directory: directory, filename: "history.json")
    }

    public func loadHistory() -> [TranscriptHistoryItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? decoder.decode([TranscriptHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    public func saveHistory(_ items: [TranscriptHistoryItem]) {
        write(items)
    }

    private func write(_ items: [TranscriptHistoryItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func makeFileURL(directory: URL?, filename: String) -> URL {
        let base: URL
        if let directory {
            base = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            base = (appSupport ?? FileManager.default.homeDirectoryForCurrentUser)
                .appendingPathComponent("VoxLite", isDirectory: true)
        }
        return base.appendingPathComponent(filename)
    }
}

public final class FileSkillStore: SkillStore {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        self.fileURL = FileHistoryStore.makeFileURL(directory: directory, filename: "skills.json")
    }

    public func loadSkills() -> SkillConfigSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(SkillConfigSnapshot.self, from: data) else {
            return Self.defaultSnapshot
        }
        let migrated = Self.migrateSnapshot(snapshot)
        if migrated != snapshot {
            saveSkills(migrated)
        }
        return migrated
    }

    public func saveSkills(_ snapshot: SkillConfigSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public static let defaultSnapshot = SkillConfigSnapshot(
        profiles: [
            SkillProfile(
                id: "transcribe",
                name: "口语转录",
                type: .preinstalled,
                template: "作为专业的文字编辑，请润色用户的语音转录文本。要求：剔除所有无意义的语气词、口癖和停顿；修正明显的同音字错误；在绝对不改变原意且不增加额外信息的前提下，输出通顺、带正确标点的书面文本。原始文本：{{text}}",
                styleHint: "自动剔除口语废话，生成流畅书面文本。"
            ),
            SkillProfile(
                id: "prompt",
                name: "提示词",
                type: .preinstalled,
                template: "作为资深的 AI 提示词工程师，请将用户的口述指令转化为结构化的高质量 Prompt。要求：根据指令意图赋予合适的专家角色；清晰明确任务目标；补充必要的背景约束和输出格式要求（如 Markdown）。请直接输出最终的 Prompt 内容，无需任何废话。用户指令：{{text}}",
                styleHint: "语音指令秒变结构化的高质量提示词。"
            ),
            SkillProfile(
                id: "xiaohongshu",
                name: "小红书文案",
                type: .preinstalled,
                template: "作为小红书爆款文案专家，请将用户口述内容改写为小红书风格笔记。要求：1. 创作吸睛且带有情绪价值的标题；2. 正文分段清晰，采用真诚有代入感的语气；3. 丰富且精准地穿插 Emoji 增强视觉体验；4. 文末附上 3-5 个相关热门话题标签（#标签#）。原始内容：{{text}}",
                styleHint: "语音直出带标题和标签的网感爆款文案。"
            )
        ],
        matching: SkillMatchingConfig(
            bundleSkillMap: [
                "com.tencent.wechat": "transcribe",
                "com.alibaba.dingtalkmac": "transcribe",
                "com.apple.dt.Xcode": "prompt",
                "com.microsoft.VSCode": "prompt",
                "com.openai.chat": "prompt",
                "com.anthropic.claude": "prompt",
                "com.google.Gemini": "prompt",
                "com.apple.Notes": "transcribe",
                "notion.id": "transcribe",
                "md.obsidian": "transcribe",
                "com.bytedance.feishu": "transcribe",
                "com.larksuite.suite": "transcribe",
                "com.xingin.xhs": "xiaohongshu",
                "com.ruguoapp.jike": "xiaohongshu"
            ],
            bundleDisplayNameMap: [
                "com.tencent.wechat": "微信 (WeChat)",
                "com.alibaba.dingtalkmac": "钉钉 (DingTalk)",
                "com.apple.dt.Xcode": "Xcode",
                "com.microsoft.VSCode": "VS Code",
                "com.openai.chat": "ChatGPT",
                "com.anthropic.claude": "Claude",
                "com.google.Gemini": "Gemini",
                "notion.id": "Notion",
                "md.obsidian": "Obsidian",
                "com.bytedance.feishu": "飞书",
                "com.larksuite.suite": "飞书",
                "com.xingin.xhs": "小红书",
                "com.ruguoapp.jike": "即刻",
                "com.apple.Notes": "备忘录 (Apple Notes)"
            ],
            categorySkillMap: [
                .communication: "transcribe",
                .development: "prompt",
                .writing: "xiaohongshu",
                .general: "transcribe"
            ],
            defaultSkillId: "transcribe"
        )
    )

    private static func migrateSnapshot(_ snapshot: SkillConfigSnapshot) -> SkillConfigSnapshot {
        var migrated = snapshot
        let defaultProfilesById = Dictionary(uniqueKeysWithValues: defaultSnapshot.profiles.map { ($0.id, $0) })
        var customProfiles = migrated.profiles.filter { $0.type == .custom }
        let knownPreinstalledIds = Set(defaultProfilesById.keys).union(["article"])

        for profile in migrated.profiles where profile.type == .preinstalled {
            if profile.id == "article" {
                continue
            }
            if defaultProfilesById[profile.id] == nil {
                customProfiles.append(
                    SkillProfile(
                        id: profile.id,
                        name: profile.name,
                        type: .custom,
                        template: profile.template,
                        styleHint: profile.styleHint
                    )
                )
            }
        }

        var mergedProfiles = defaultSnapshot.profiles + customProfiles
        mergedProfiles = mergedProfiles.reduce(into: [SkillProfile]()) { result, profile in
            if result.contains(where: { $0.id == profile.id }) == false {
                result.append(profile)
            }
        }
        migrated.profiles = mergedProfiles

        migrated.matching.bundleSkillMap = migrated.matching.bundleSkillMap.mapValues { value in
            value == "article" ? "xiaohongshu" : value
        }
        for (bundleId, targetSkillId) in defaultSnapshot.matching.bundleSkillMap where migrated.matching.bundleSkillMap[bundleId] == nil {
            migrated.matching.bundleSkillMap[bundleId] = targetSkillId
        }
        migrated.matching.bundleSkillMap = migrated.matching.bundleSkillMap.filter { _, skillId in
            knownPreinstalledIds.contains(skillId) == false || migrated.profiles.contains(where: { $0.id == skillId })
        }

        var displayNameMap = migrated.matching.bundleDisplayNameMap
        for (bundleId, appName) in defaultSnapshot.matching.bundleDisplayNameMap where displayNameMap[bundleId] == nil {
            displayNameMap[bundleId] = appName
        }
        migrated.matching.bundleDisplayNameMap = displayNameMap

        migrated.matching.categorySkillMap = migrated.matching.categorySkillMap.mapValues { value in
            value == "article" ? "xiaohongshu" : value
        }
        migrated.matching.categorySkillMap[.writing] = migrated.matching.categorySkillMap[.writing] ?? "xiaohongshu"

        if migrated.profiles.contains(where: { $0.id == migrated.matching.defaultSkillId }) == false {
            migrated.matching.defaultSkillId = "transcribe"
        }
        return migrated
    }
}

public final class FileAppSettingsStore: AppSettingsStore {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        self.fileURL = FileHistoryStore.makeFileURL(directory: directory, filename: "settings.json")
    }

    public func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return Self.defaultSettings
        }
        return settings
    }

    public func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public static let defaultSettings = AppSettings(
        hotKeyDescription: "Fn",
        launchAtLoginEnabled: false,
        menuBarDisplayMode: .iconAndSummary,
        showRecentSummary: true,
        summaryMaxLength: 48,
        historyLimit: 100,
        speechModel: ModelSetting(localEnabled: true, remoteProvider: "", remoteEndpoint: ""),
        llmModel: ModelSetting(localEnabled: true, remoteProvider: "", remoteEndpoint: ""),
        onboardingCompleted: false
    )
}

public final class UserDefaultsLaunchAtLoginManager: LaunchAtLoginManaging {
    private let key = "voxlite.launchAtLogin"

    public init() {}

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}
