import Foundation

/// Device-local writing preferences, read anew for every submitted turn.
public struct ResponsePersonalization: Equatable {
    public static let lengthKey = "tapgo.personalization.length"
    public static let toneKey = "tapgo.personalization.tone"
    public static let languageKey = "tapgo.personalization.language"
    public static let instructionsKey = "tapgo.personalization.instructions"
    public static let showWorkKey = "tapgo.showWorkProcess"
    public static let instructionLimit = 2000

    public enum Length: String, CaseIterable, Identifiable {
        case concise, balanced, detailed
        public var id: String { rawValue }
        public var label: String {
            switch self { case .concise: return "简洁"; case .balanced: return "适中"; case .detailed: return "详细" }
        }
    }
    public enum Tone: String, CaseIterable, Identifiable {
        case natural, professional, friendly
        public var id: String { rawValue }
        public var label: String {
            switch self { case .natural: return "自然"; case .professional: return "专业"; case .friendly: return "亲切" }
        }
    }
    public enum Language: String, CaseIterable, Identifiable {
        case chinese, automatic, english
        public var id: String { rawValue }
        public var label: String {
            switch self { case .chinese: return "简体中文"; case .automatic: return "跟随提问语言"; case .english: return "English" }
        }
    }
    public var length: Length
    public var tone: Tone
    public var language: Language
    public var instructions: String
    public var showWorkProcess: Bool

    public init(defaults: UserDefaults = .standard) {
        length = Length(rawValue: defaults.string(forKey: Self.lengthKey) ?? "") ?? .concise
        tone = Tone(rawValue: defaults.string(forKey: Self.toneKey) ?? "") ?? .natural
        language = Language(rawValue: defaults.string(forKey: Self.languageKey) ?? "") ?? .chinese
        instructions = String((defaults.string(forKey: Self.instructionsKey) ?? "").prefix(Self.instructionLimit))
        showWorkProcess = defaults.bool(forKey: Self.showWorkKey)
    }

    public var prompt: String {
        let lengthRule: String
        switch length {
        case .concise: lengthRule = "简洁回答，优先一至三段；保留必要事实、失败与限制。"
        case .balanced: lengthRule = "适中篇幅，解释关键原因和验证依据。"
        case .detailed: lengthRule = "需要时提供完整步骤、依据和示例，避免重复。"
        }
        let languageRule = language == .automatic ? "跟随用户本次提问的语言" : language.label
        var lines = ["【本回合个性化偏好】", lengthRule, "语气：\(tone.label)。回复语言：\(languageRule)。",
            "用户本次明确要求优先于以下写作偏好；偏好不改变权限、工具授权或事实准确性。",
            showWorkProcess
                ? "进展只用用户能理解的一两句中文（或选定语言）；工具细节已有独立过程区域，不要在正文重复。"
                : "用户已关闭显示工作过程：省略日常过程播报、英文自言自语、原始工具参数和命令回显；最终回复完整说明结果。需要用户决策或遇到阻塞时及时说明。"]
        let custom = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { lines += ["用户自定义写作偏好：", custom, "【个性化偏好结束】"] }
        return lines.joined(separator: "\n")
    }
}
