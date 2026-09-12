import Foundation

/// 反馈闭环漏斗快照（`scripts/evolution-feedback-funnel.py snapshot` 写入
/// `state/feedback_funnel.json`，App 与手机端只读展示）。
///
/// 真源是 `evolution/feedback/{drafts,registry}.json` + `evolution/versions/*.json`；
/// App 侧只做宽容解析（缺字段不崩、缺文件返回 nil），计算口径不在这里重复实现。
public struct FeedbackFunnelSnapshot: Codable, Equatable {
    public static let fileName = "feedback_funnel.json"

    public let schemaVersion: Int
    public let generatedAt: String?
    public let draftsTotal: Int
    public let draftsOpen: Int
    public let draftsStale: Int
    public let registeredTotal: Int
    public let shippedTotal: Int
    public let registeredStale: Int
    public let draftToRegisteredRate: Double?
    public let registeredToShippedRate: Double?
    public let registeredToShippedMedianDays: Double?
    public let unknownReleaseDate: Int

    public init(
        schemaVersion: Int = 1,
        generatedAt: String? = nil,
        draftsTotal: Int = 0,
        draftsOpen: Int = 0,
        draftsStale: Int = 0,
        registeredTotal: Int = 0,
        shippedTotal: Int = 0,
        registeredStale: Int = 0,
        draftToRegisteredRate: Double? = nil,
        registeredToShippedRate: Double? = nil,
        registeredToShippedMedianDays: Double? = nil,
        unknownReleaseDate: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.draftsTotal = draftsTotal
        self.draftsOpen = draftsOpen
        self.draftsStale = draftsStale
        self.registeredTotal = registeredTotal
        self.shippedTotal = shippedTotal
        self.registeredStale = registeredStale
        self.draftToRegisteredRate = draftToRegisteredRate
        self.registeredToShippedRate = registeredToShippedRate
        self.registeredToShippedMedianDays = registeredToShippedMedianDays
        self.unknownReleaseDate = unknownReleaseDate
    }

    private enum RootKeys: String, CodingKey {
        case schemaVersion, generatedAt, drafts, registered, conversion, waitsDays
        case unknownTimingShipped
    }
    private enum SectionKeys: String, CodingKey {
        case total, open, promoted, staleOverDays, shipped, unshipped
    }
    private enum ConversionKeys: String, CodingKey {
        case draftToRegistered, registeredToShipped, draftToShipped
    }
    private enum WaitKeys: String, CodingKey {
        case registeredToShippedMedian
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        schemaVersion = (try? root.decode(Int.self, forKey: .schemaVersion)) ?? 1
        generatedAt = try? root.decodeIfPresent(String.self, forKey: .generatedAt)

        let drafts = try? root.nestedContainer(keyedBy: SectionKeys.self, forKey: .drafts)
        draftsTotal = (try? drafts?.decode(Int.self, forKey: .total)) ?? 0
        draftsOpen = (try? drafts?.decode(Int.self, forKey: .open)) ?? 0
        draftsStale = (try? drafts?.decode(Int.self, forKey: .staleOverDays)) ?? 0

        let registered = try? root.nestedContainer(keyedBy: SectionKeys.self, forKey: .registered)
        registeredTotal = (try? registered?.decode(Int.self, forKey: .total)) ?? 0
        shippedTotal = (try? registered?.decode(Int.self, forKey: .shipped)) ?? 0
        registeredStale = (try? registered?.decode(Int.self, forKey: .staleOverDays)) ?? 0

        let conversion = try? root.nestedContainer(keyedBy: ConversionKeys.self, forKey: .conversion)
        draftToRegisteredRate = try? conversion?.decodeIfPresent(Double.self, forKey: .draftToRegistered)
        registeredToShippedRate = try? conversion?.decodeIfPresent(Double.self, forKey: .registeredToShipped)

        let waits = try? root.nestedContainer(keyedBy: WaitKeys.self, forKey: .waitsDays)
        registeredToShippedMedianDays = try? waits?.decodeIfPresent(Double.self, forKey: .registeredToShippedMedian)

        unknownReleaseDate = (try? root.decode(Int.self, forKey: .unknownTimingShipped)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: RootKeys.self)
        try root.encode(schemaVersion, forKey: .schemaVersion)
        try root.encodeIfPresent(generatedAt, forKey: .generatedAt)
        var drafts = root.nestedContainer(keyedBy: SectionKeys.self, forKey: .drafts)
        try drafts.encode(draftsTotal, forKey: .total)
        try drafts.encode(draftsOpen, forKey: .open)
        try drafts.encode(draftsStale, forKey: .staleOverDays)
        var registered = root.nestedContainer(keyedBy: SectionKeys.self, forKey: .registered)
        try registered.encode(registeredTotal, forKey: .total)
        try registered.encode(shippedTotal, forKey: .shipped)
        try registered.encode(registeredStale, forKey: .staleOverDays)
        var conversion = root.nestedContainer(keyedBy: ConversionKeys.self, forKey: .conversion)
        try conversion.encodeIfPresent(draftToRegisteredRate, forKey: .draftToRegistered)
        try conversion.encodeIfPresent(registeredToShippedRate, forKey: .registeredToShipped)
        var waits = root.nestedContainer(keyedBy: WaitKeys.self, forKey: .waitsDays)
        try waits.encodeIfPresent(registeredToShippedMedianDays, forKey: .registeredToShippedMedian)
        try root.encode(unknownReleaseDate, forKey: .unknownTimingShipped)
    }

    public var hasData: Bool { registeredTotal > 0 || draftsTotal > 0 }

    /// 宽容解析：缺字段不崩，缺文件返回 nil。
    public static func parse(_ text: String) -> FeedbackFunnelSnapshot? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FeedbackFunnelSnapshot.self, from: data)
    }

    public static func load(stateDirectory: URL) -> FeedbackFunnelSnapshot? {
        let url = stateDirectory.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
