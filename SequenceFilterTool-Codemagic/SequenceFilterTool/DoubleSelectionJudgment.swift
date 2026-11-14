import Foundation
import CoreFoundation

/// Soft evidence for choosing two doubles, never a gate that drops a group.
enum DoubleJudgmentFactor: String, CaseIterable, Codable, Sendable {
    case euro, asianLine, asianWater, books, funds, reverse, crowd, drawGap
    var title: String {
        switch self {
        case .euro: return "欧赔初盘至即时走势"
        case .asianLine: return "亚盘升降盘走势"
        case .asianWater: return "亚盘水位变化"
        case .books: return "多机构分歧与一致性"
        case .funds: return "市场投注资金偏向"
        case .reverse: return "资金与赔率反向变化"
        case .crowd: return "热门拥挤心理风险"
        case .drawGap: return "平局风险与概率差距"
        }
    }
    var help: String {
        switch self {
        case .euro: return "比较同机构初盘与即时欧赔，经实际让球和项目对照表换算后给双选排序提供弱参考。"
        case .asianLine: return "比较初盘与即时让球深浅；只使用有来源且赛前采集的盘口，不把升盘等同于必胜。"
        case .asianWater: return "比较同机构主客水位变化；只作有上限的辅助排序。"
        case .books: return "比较3家机构换算后的自定义赔率，观察共同方向与分歧；缺少2家时不计。"
        case .funds: return "仅使用公开投注金额或投注占比。金额未公开时注明仅有占比，不从赔率或你的投注倍数伪造资金。"
        case .reverse: return "观察投注偏热而对应欧赔概率走弱的背离；资金或走势缺失时不计。"
        case .crowd: return "用公开投注占比相对赔率的拥挤程度表示心理代理；不能读取或断言真实心理。"
        case .drawGap: return "概率接近且平局有一定基础时，给保留平局小幅辅助参考；不改变连续6场。"
        }
    }
    var aliases: [String] {
        switch self {
        case .euro: return ["欧赔走势", "欧赔变化"]
        case .asianLine: return ["亚盘走势", "亚盘升降", "升降盘"]
        case .asianWater: return ["水位走势", "亚盘水位"]
        case .books: return ["机构分歧", "多机构一致性"]
        case .funds: return ["投注资金", "市场投注金额", "投注偏向", "资金偏向"]
        case .reverse: return ["资金赔率背离", "反向变盘"]
        case .crowd: return ["热门拥挤", "心理风险", "投注心理"]
        case .drawGap: return ["平局风险", "概率差距"]
        }
    }
    static func text(_ factors: Set<Self>) -> String { allCases.filter(factors.contains).map(\.rawValue).joined(separator: ",") }
    static func parse(_ text: String) -> Set<Self>? {
        if text.isEmpty { return [] }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let values = parts.compactMap(Self.init(rawValue:))
        return values.count == parts.count && Set(values).count == parts.count ? Set(values) : nil
    }
}

struct DoubleAsianPoint: Codable, Hashable, Sendable {
    let homeWater: Double
    let line: Double // home handicap: negative gives goals, positive receives
    let awayWater: Double
}
struct DoubleBookQuote: Codable, Hashable, Sendable {
    let companyID: Int
    let openingEuropean: [Double]
    let currentEuropean: [Double]
    let openingAsian: DoubleAsianPoint?
    let currentAsian: DoubleAsianPoint?
}
struct DoubleObservedQuote: Codable, Hashable, Sendable {
    let companyID: Int
    let european: [Double]
    let asian: DoubleAsianPoint?
    init(_ quote: DoubleBookQuote) {
        companyID = quote.companyID; european = quote.currentEuropean; asian = quote.currentAsian
    }
}
struct DoubleMarketObservation: Codable, Hashable, Sendable {
    let capturedAt: Date
    let books: [DoubleObservedQuote]
    let bettingShares: [Double]
}
struct DoubleMarketTrendPoint: Identifiable, Equatable, Sendable {
    let capturedAt: Date
    let direction: String
    let value: Double
    var id: String { "\(capturedAt.timeIntervalSince1970):\(direction)" }
}
struct DoubleMarketTrendData: Sendable {
    let companyID: Int
    let openingEuropean: [Double]
    let currentEuropean: [Double]
    let openingAsian: DoubleAsianPoint?
    let currentAsian: DoubleAsianPoint?
    let european: [DoubleMarketTrendPoint]
    let asianLine: [DoubleMarketTrendPoint]
    let asianWater: [DoubleMarketTrendPoint]
    init?(evidence: DoubleMarketEvidence, companyID: Int) {
        guard evidence.isValid, let book = evidence.books.first(where: { $0.companyID == companyID }) else { return nil }
        self.companyID = companyID
        openingEuropean = book.openingEuropean; currentEuropean = book.currentEuropean
        openingAsian = book.openingAsian; currentAsian = book.currentAsian
        var european: [DoubleMarketTrendPoint] = [], line: [DoubleMarketTrendPoint] = [], water: [DoubleMarketTrendPoint] = []
        for sample in evidence.observations ?? [evidence.observation] {
            guard let quote = sample.books.first(where: { $0.companyID == companyID }) else { continue }
            for (index, label) in ["主胜", "平局", "客胜"].enumerated() {
                european.append(DoubleMarketTrendPoint(capturedAt: sample.capturedAt, direction: label, value: quote.european[index]))
            }
            if let asian = quote.asian {
                line.append(DoubleMarketTrendPoint(capturedAt: sample.capturedAt, direction: "主队让球", value: asian.line))
                water.append(DoubleMarketTrendPoint(capturedAt: sample.capturedAt, direction: "主队水位", value: asian.homeWater))
                water.append(DoubleMarketTrendPoint(capturedAt: sample.capturedAt, direction: "客队水位", value: asian.awayWater))
            }
        }
        self.european = european; asianLine = line; asianWater = water
    }
}
struct DoubleMarketEvidence: Codable, Hashable, Sendable {
    let issue: String
    let number: Int
    let fixtureID: String
    let handicap: Int
    let capturedAt: Date
    let kickoff: Date
    let books: [DoubleBookQuote]
    let bettingShares: [Double]
    var bettingAmounts: [Double]? = nil
    var source = "500公开赔率及北单投注比例"
    // Optional so existing TXT snapshots keep their original meaning.
    var observations: [DoubleMarketObservation]? = nil

    var isValid: Bool {
        issue.count == 5 && issue.allSatisfy(\.isNumber) && number > 0 && !fixtureID.isEmpty
            && capturedAt < kickoff && capturedAt <= Date().addingTimeInterval(60) && capturedAt.timeIntervalSince1970 > 946684800
            && books.count <= 3 && Set(books.map(\.companyID)).count == books.count
            && books.allSatisfy { quote in
                quote.companyID > 0 && DoubleJudgmentScorer.validOdds(quote.openingEuropean)
                    && DoubleJudgmentScorer.validOdds(quote.currentEuropean)
                    && [quote.openingAsian, quote.currentAsian].compactMap { $0 }.allSatisfy(Self.validAsian)
            } && (bettingShares.isEmpty || (DoubleJudgmentScorer.normalizedShares(bettingShares) != nil && abs(bettingShares.reduce(0,+)-1)<0.02))
            && (bettingAmounts == nil || DoubleJudgmentScorer.normalizedShares(bettingAmounts!) != nil)
            && validObservations
    }
    static func validAsian(_ point: DoubleAsianPoint) -> Bool {
        point.homeWater.isFinite && point.homeWater > 0 && point.awayWater.isFinite && point.awayWater > 0
            && point.line.isFinite && abs(point.line) <= 10
    }
    private var validObservations: Bool {
        guard let observations else { return true }
        guard observations.count <= 12 else { return false }
        var previous = Date(timeIntervalSince1970: 946684800)
        for point in observations {
            guard point.capturedAt > previous, point.capturedAt <= capturedAt, point.capturedAt < kickoff,
                  point.books.count <= 3, Set(point.books.map(\.companyID)).count == point.books.count,
                  point.books.allSatisfy({ $0.companyID > 0 && DoubleJudgmentScorer.validOdds($0.european)
                      && ($0.asian.map(Self.validAsian) ?? true) }),
                  point.bettingShares.isEmpty || (DoubleJudgmentScorer.normalizedShares(point.bettingShares) != nil
                      && abs(point.bettingShares.reduce(0,+)-1) < 0.02) else { return false }
            previous = point.capturedAt
        }
        // The final observation must describe this exact snapshot, not a future or unrelated quote.
        return observations.last.map { $0 == observation } ?? true
    }
    var observation: DoubleMarketObservation {
        DoubleMarketObservation(capturedAt: capturedAt, books: books.map(DoubleObservedQuote.init),
                                bettingShares: publishedShares ?? [])
    }
    func recording(previous: Self?) -> Self {
        guard isValid else { return self }
        let compatible = previous.flatMap {
            $0.isValid && $0.issue == issue && $0.number == number && $0.fixtureID == fixtureID
                && $0.handicap == handicap && $0.kickoff == kickoff && $0.capturedAt < capturedAt ? $0 : nil
        }
        var points = compatible.map { $0.observations ?? [$0.observation] } ?? []
        // Manual refreshes in quick succession do not crowd out the minute samples.
        if let last = points.last, capturedAt.timeIntervalSince(last.capturedAt) < 45 { points.removeLast() }
        points.append(observation)
        var result = self; result.observations = Array(points.suffix(12))
        return result
    }
    var recentPrimaryObservations: [(Date, DoubleObservedQuote)] {
        guard isValid, let company = (books.first { $0.companyID == 3 } ?? books.first)?.companyID else { return [] }
        let points = (observations ?? [observation]).compactMap { point -> (Date, DoubleObservedQuote)? in
            guard capturedAt.timeIntervalSince(point.capturedAt) <= 30*60,
                  let quote = point.books.first(where: { $0.companyID == company }) else { return nil }
            return (point.capturedAt, quote)
        }
        guard points.count >= 2, let first = points.first, let last = points.last,
              last.0.timeIntervalSince(first.0) >= 45 else { return [] }
        return points
    }
    var publishedShares: [Double]? {
        bettingAmounts.flatMap(DoubleJudgmentScorer.normalizedShares) ?? DoubleJudgmentScorer.normalizedShares(bettingShares)
    }
    static func encoded(_ evidence: [Self]) -> String {
        guard !evidence.isEmpty else { return "" }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(evidence).base64EncodedString()) ?? ""
    }
    static func decoded(_ text: String) -> [Self]? {
        if text.isEmpty { return [] }
        guard text.utf8.count <= 100_000, let data = Data(base64Encoded: text),
              let rows = try? JSONDecoder().decode([Self].self, from: data), rows.count <= 6,
              rows.allSatisfy(\.isValid), Set(rows.map(\.number)).count == rows.count,
              Set(rows.map(\.issue)).count <= 1 else { return nil }
        return rows
    }
}
struct DoubleFactorAssessment: Identifiable, Sendable {
    let factor: DoubleJudgmentFactor
    let adjustment: [Double]
    let note: String
    let available: Bool
    var id: String { factor.rawValue }
}

/// The same six snapshots are assessed for hundreds of generated combinations
/// and by SwiftUI. Keep immutable, fully keyed results behind a bounded lock.
private final class DoubleFactorAssessmentCache: @unchecked Sendable {
    struct Key: Hashable {
        let number: Int
        let logic: String
        let odds: [Double]
        let calibrated: Bool
        let factors: Set<DoubleJudgmentFactor>
        let evidence: DoubleMarketEvidence?
    }
    static let shared = DoubleFactorAssessmentCache()
    private let lock = NSLock()
    private var values: [Key:[DoubleFactorAssessment]] = [:]
    func value(for key: Key) -> [DoubleFactorAssessment]? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    func store(_ value: [DoubleFactorAssessment], for key: Key) {
        lock.lock(); defer { lock.unlock() }
        if values.count >= 128 { values.removeAll(keepingCapacity:true) }
        values[key] = value
    }
}

/// Bounded, experimental ranking signals. They are not calibrated probabilities
/// and have not demonstrated a historical improvement. Missing data adds zero.
enum DoubleJudgmentScorer {
    static func validOdds(_ row: [Double]) -> Bool { row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 1 } }
    static func normalizedShares(_ row: [Double]) -> [Double]? {
        guard row.count == 3, row.allSatisfy({ $0.isFinite && $0 >= 0 }), row.reduce(0,+).isFinite,
              row.reduce(0,+) > 0 else { return nil }
        return row.map { $0 / row.reduce(0,+) }
    }
    static func clamp(_ x: Double, _ limit: Double) -> Double { max(-limit, min(limit, x)) }
    static func assessments(_ match: AutomaticDoubleCandidate, calibrated: Bool,
                            factors: Set<DoubleJudgmentFactor>) -> [DoubleFactorAssessment] {
        guard !factors.isEmpty, AutomaticDoubleSelector.probabilities(odds:match.odds,calibrated:calibrated) != nil else { return [] }
        var sanitized = match
        sanitized.evidence = match.evidence.flatMap { $0.isValid && $0.number == match.number ? $0 : nil }
        let key = DoubleFactorAssessmentCache.Key(number:match.number,logic:match.logic.rawValue,odds:match.odds,
            calibrated:calibrated,factors:factors,evidence:sanitized.evidence)
        if let cached = DoubleFactorAssessmentCache.shared.value(for:key) { return cached }
        let rows = uncachedAssessments(sanitized,calibrated:calibrated,factors:factors)
        DoubleFactorAssessmentCache.shared.store(rows,for:key)
        return rows
    }
    private static func uncachedAssessments(_ match: AutomaticDoubleCandidate, calibrated: Bool,
                                           factors: Set<DoubleJudgmentFactor>) -> [DoubleFactorAssessment] {
        guard let base = AutomaticDoubleSelector.probabilities(odds: match.odds, calibrated: calibrated) else { return [] }
        let evidence = match.evidence.flatMap { $0.isValid && $0.number == match.number ? $0 : nil }
        let zero = [0.0,0,0]
        func converted(_ ordinary: [Double]) -> [Double]? {
            guard let evidence, let odds = HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: ordinary, handicap: evidence.handicap) else { return nil }
            return AutomaticDoubleSelector.probabilities(odds: odds, calibrated: calibrated)
        }
        let books = evidence?.books ?? []
        let primary = books.first { $0.companyID == 3 } ?? books.first
        let opening = primary.flatMap { converted($0.openingEuropean) }
        let current = primary.flatMap { converted($0.currentEuropean) }
        let trend = zip(current ?? [], opening ?? []).map(-)
        let recent = evidence?.recentPrimaryObservations ?? []
        let recentOpening = recent.first.flatMap { converted($0.1.european) }
        let recentTrend = zip(current ?? [], recentOpening ?? []).map(-)
        let samplingNote = recent.count >= 2 ? "；本机连续采样\(recent.count)次，跨度\(Int(recent.last!.0.timeIntervalSince(recent.first!.0)/60))分钟" : "；连续采样尚不足，仅比较初盘与当前盘"
        let shares = evidence?.publishedShares
        return DoubleJudgmentFactor.allCases.filter(factors.contains).map { factor in
            var adjustment = zero, note = "缺少赛前数据，本项未计入", available = false
            switch factor {
            case .euro:
                if trend.count == 3 {
                    adjustment = (0..<3).map { index in
                        clamp(recentTrend.count == 3 ? trend[index]*0.15 + recentTrend[index]*0.10 : trend[index]*0.20, 0.025)
                    }; available = true
                    note = "机构\(primary!.companyID)普通欧赔：\(primary!.openingEuropean.map { String(format: "%.2f", $0) }.joined(separator: "/")) → \(primary!.currentEuropean.map { String(format: "%.2f", $0) }.joined(separator: "/"))；评分经实际让球换算" + samplingNote
                    if recentTrend.count == 3, (0..<3).contains(where: { trend[$0]*recentTrend[$0] < 0 && abs(recentTrend[$0]) > 0.005 }) {
                        note += "；最近方向与初盘方向有背离，不能将长期降赔视作持续支持"
                    }
                }
            case .asianLine:
                if let a = primary?.openingAsian, let b = primary?.currentAsian {
                    let recentLine = recent.first?.1.asian?.line
                    let delta = clamp(recentLine.map { -(b.line-a.line)*0.025 - (b.line-$0)*0.015 } ?? (-(b.line-a.line)*0.03), 0.02)
                    adjustment = [delta,0,-delta]; available = true
                    note = String(format: "主队让球 %.2f → %.2f", a.line,b.line) + samplingNote
                }
            case .asianWater:
                if let b = primary?.currentAsian {
                    // Water on different handicap lines prices different events.
                    // Only compare a continuous segment with the same line.
                    let sameLine = recent.reversed().prefix { point in
                        point.1.asian.map { abs($0.line-b.line) < 0.0001 } ?? false
                    }
                    let sampled = sameLine.last.flatMap { point in
                        evidence!.capturedAt.timeIntervalSince(point.0) >= 45 ? point.1.asian : nil
                    }
                    let initial = primary?.openingAsian.flatMap { abs($0.line-b.line) < 0.0001 ? $0 : nil }
                    func home(_ p: DoubleAsianPoint) -> Double {
                        let h = 1/(1+p.homeWater), v = 1/(1+p.awayWater); return h/(h+v)
                    }
                    if let a = sampled ?? initial {
                        let delta = clamp((home(b)-home(a)) * 0.20,0.01)
                        adjustment = [delta,0,-delta]; available = true
                        note = String(format: "同盘口 %.2f：主水 %.3f→%.3f；客水 %.3f→%.3f",b.line,a.homeWater,b.homeWater,a.awayWater,b.awayWater)
                    } else { note = "初盘与当前盘口不同，水位不可直接比较；等待同盘口连续采样" }
                }
            case .books:
                let rows = books.compactMap { converted($0.currentEuropean) }
                if rows.count >= 2 {
                    for i in 0..<3 {
                        let mean = rows.map { $0[i] }.reduce(0,+)/Double(rows.count)
                        let deviation = sqrt(rows.map { pow($0[i]-mean,2) }.reduce(0,+)/Double(rows.count))
                        adjustment[i] = clamp(0.15*(mean-base[i])-0.05*deviation,0.015)
                    }
                    available = true; note = "已比较\(rows.count)家机构；同一实际让球换算口径"
                }
            case .funds:
                if let shares {
                    adjustment = zip(shares,base).map { clamp(($0-$1)*0.025,0.01) }; available = true
                    note = evidence?.bettingAmounts != nil ? "采用来源公开金额的方向占比" : "采用公开投注占比；实际金额未公开"
                } else { note = "实际金额及投注占比未公开，未计入；没有用赔率代替资金" }
            case .reverse:
                if let shares, trend.count == 3 {
                    adjustment = (0..<3).map { i in
                        shares[i]-base[i] > 0.10 && trend[i] < 0 ? -min(0.015,(shares[i]-base[i])*abs(trend[i])*0.5) : 0
                    }
                    available = true; note = "检查资金偏热且赔率支持走弱的反向变化"
                }
            case .crowd:
                if let shares {
                    adjustment = (0..<3).map { -min(0.015,max(0,shares[$0]-base[$0]-0.10)*0.05) }
                    available = true; note = "投注拥挤是心理代理，非真实心理结论"
                }
            case .drawGap:
                let sorted = base.sorted(by: >)
                if sorted[0]-sorted[1] < 0.08 && base[1] >= 0.25 {
                    adjustment[1] = min(0.006,(0.08-(sorted[0]-sorted[1]))*0.075)
                }
                available = true; note = "概率接近时小幅保护平局；实验性排序依据"
            }
            return DoubleFactorAssessment(factor: factor, adjustment: adjustment, note: note, available: available)
        }
    }
    static func scores(_ match: AutomaticDoubleCandidate, calibrated: Bool, factors: Set<DoubleJudgmentFactor>) -> [Double]? {
        guard let base = AutomaticDoubleSelector.probabilities(odds: match.odds, calibrated: calibrated) else { return nil }
        guard !factors.isEmpty else { return base }
        let signals = assessments(match, calibrated: calibrated, factors: factors)
        let combined = (0..<3).map { index in
            max(0.001, base[index] + clamp(signals.reduce(0) { $0 + $1.adjustment[index] },0.04))
        }
        let total = combined.reduce(0,+)
        return combined.map { $0/total }
    }
    static func asianLine(_ raw: String) -> Double? {
        let text = raw.replacingOccurrences(of: " ",with: "").replacingOccurrences(of:"／",with:"/")
        let receives = text.hasPrefix("受")
        let clean = receives ? String(text.dropFirst()) : text
        let names: [String:Double] = ["平手":0,"平":0,"半球":0.5,"半":0.5,"一球":1,"一":1,"球半":1.5,"一球半":1.5,"两球":2,"二球":2,"两":2,"两球半":2.5,"三球":3,"三球半":3.5,"四球":4,"四球半":4.5,"五球":5,"五球半":5.5,"六球":6]
        let parts = clean.split(separator:"/").map(String.init)
        let values = parts.compactMap { names[$0] ?? Double($0) }
        guard !parts.isEmpty, parts.count <= 2, values.count == parts.count, values.allSatisfy({ $0.isFinite && abs($0)<=10 }) else { return nil }
        let magnitude = values.reduce(0,+)/Double(values.count)
        if clean.first == "+" || clean.first == "-" { return magnitude }
        return receives ? abs(magnitude) : -abs(magnitude)
    }
}

actor DoubleMarketSnapshotStore {
    static let shared = DoubleMarketSnapshotStore()
    private let key = "sequenceFilter.doubleMarketEvidence.v1"
    private let directory: URL
    private let defaults: UserDefaults
    private var legacy: [String:DoubleMarketEvidence]?
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("DoubleMarketEvidence",isDirectory:true)
        self.defaults = defaults
    }
    private func file(issue: String, number: Int, fixtureID: String) -> URL? {
        guard issue.count == 5, issue.allSatisfy(\.isNumber), number > 0,
              !fixtureID.isEmpty, fixtureID.allSatisfy(\.isNumber) else { return nil }
        return directory.appendingPathComponent("\(issue)-\(number)-\(fixtureID).json")
    }
    func evidence(issue: String, number: Int, fixtureID: String, before cutoff: Date? = nil) -> DoubleMarketEvidence? {
        guard let url = file(issue:issue,number:number,fixtureID:fixtureID) else { return nil }
        if let data = try? Data(contentsOf:url), let value = try? JSONDecoder().decode(DoubleMarketEvidence.self,from:data),
           value.isValid, value.issue == issue, value.number == number, value.fixtureID == fixtureID,
           cutoff.map({ value.capturedAt < $0 }) ?? true { return value }
        if let cutoff, let log = try? Data(contentsOf:url.deletingPathExtension().appendingPathExtension("jsonl")) {
            let samples = log.split(separator:0x0A).compactMap { try? JSONDecoder().decode(DoubleMarketEvidence.self,from:Data($0)) }
                .filter { $0.isValid && $0.issue == issue && $0.number == number && $0.fixtureID == fixtureID && $0.capturedAt < cutoff }
                .sorted { $0.capturedAt < $1.capturedAt }
            if !samples.isEmpty { return samples.reduce(nil as DoubleMarketEvidence?) { $1.recording(previous:$0) } }
        }
        if legacy == nil {
            legacy = defaults.data(forKey:key).flatMap { try? JSONDecoder().decode([String:DoubleMarketEvidence].self,from:$0) } ?? [:]
        }
        return legacy?["\(issue):\(number):\(fixtureID)"].flatMap { value in
            value.isValid && (cutoff.map { value.capturedAt < $0 } ?? true) ? value : nil
        }
    }
    @discardableResult func store(_ value: DoubleMarketEvidence) -> DoubleMarketEvidence {
        guard value.isValid, let url = file(issue:value.issue,number:value.number,fixtureID:value.fixtureID) else { return value }
        let previous = evidence(issue:value.issue,number:value.number,fixtureID:value.fixtureID)
        if let previous, previous.handicap == value.handicap, previous.kickoff == value.kickoff,
           previous.capturedAt >= value.capturedAt { return previous }
        let recorded = value.recording(previous:previous)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONEncoder().encode(recorded).write(to:url,options:.atomic)
            if previous == nil || recorded.capturedAt.timeIntervalSince(previous!.capturedAt) >= 45 {
                // Keep immutable raw samples for future chronological validation;
                // only the latest twelve travel with an individual TXT snapshot.
                let history = url.deletingPathExtension().appendingPathExtension("jsonl")
                if !FileManager.default.fileExists(atPath:history.path) {
                    FileManager.default.createFile(atPath:history.path,contents:nil)
                }
                let handle = try FileHandle(forWritingTo:history)
                defer { try? handle.close() }
                var sample = value; sample.observations = nil
                var data = try JSONEncoder().encode(sample); data.append(0x0A)
                try handle.seekToEnd(); try handle.write(contentsOf:data)
            }
        } catch {
            NSLog("Double-market snapshot persistence failed: %@",error.localizedDescription)
        }
        return recorded
    }
}
struct DoubleMarketFetchResult: Sendable {
    let evidence: [DoubleMarketEvidence]
    let notes: [Int:String]
    var trendEvidence: [DoubleMarketEvidence]? = nil
    var displayEvidence: [DoubleMarketEvidence] { trendEvidence ?? evidence }
}

enum DoubleMarketDataClient {
    static let decisionLeadTime: TimeInterval = 2 * 3600
    static func verifiedEvidence(_ evidence: [DoubleMarketEvidence], matches: [BeijingSingleMatch], firstMatchNumber: Int,
                                 leadTime: TimeInterval = 0) -> [DoubleMarketEvidence] {
        guard firstMatchNumber > 0, firstMatchNumber <= Int.max - 6 else { return [] }
        return verifiedEvidence(evidence, matches: matches,
            matchNumbers: Array(firstMatchNumber..<(firstMatchNumber + 6)), leadTime: leadTime)
    }
    static func verifiedEvidence(_ evidence: [DoubleMarketEvidence], matches: [BeijingSingleMatch], matchNumbers: [Int],
                                 leadTime: TimeInterval = 0) -> [DoubleMarketEvidence] {
        let numbers = Set(matchNumbers)
        guard matchNumbers.count == 6, numbers.count == 6 else { return [] }
        let six = matches.filter { Int($0.matchNumber).map(numbers.contains) == true }
        let kickoffs = six.compactMap { kickoff(issue:$0.issue,matchTime:$0.matchTime) }
        guard six.count == 6, Set(six.map(\.matchNumber)).count == 6, kickoffs.count == 6,
              let firstTime = kickoffs.min(), leadTime.isFinite, leadTime >= 0 else { return [] }
        let cutoff = firstTime.addingTimeInterval(-leadTime)
        return evidence.filter { value in
            value.isValid && value.capturedAt < cutoff && six.contains { match in
                match.issue == value.issue && Int(match.matchNumber) == value.number && match.fixtureID == value.fixtureID
                    && match.handicap == value.handicap && kickoff(issue:match.issue,matchTime:match.matchTime) == value.kickoff
            }
        }
    }
    static func applyingVerifiedQuotes(_ evidence: [DoubleMarketEvidence], to matches: [BeijingSingleMatch]) -> [BeijingSingleMatch] {
        matches.map { match in
            guard let value = evidence.first(where: { $0.isValid && $0.issue == match.issue && $0.number == Int(match.matchNumber)
                && $0.fixtureID == match.fixtureID && $0.handicap == match.handicap
                && $0.kickoff == kickoff(issue:match.issue,matchTime:match.matchTime) }),
                let quote = value.books.first(where: { $0.companyID == 3 }) ?? value.books.first else { return match }
            return match.replacingMarketOdds(quote.currentEuropean)
        }
    }
    static func kickoff(issue: String, matchTime: String) -> Date? {
        let text = matchTime.trimmingCharacters(in:.whitespacesAndNewlines)
        guard issue.count == 5, issue.allSatisfy(\.isNumber), let year = Int(issue.prefix(2)),
              let issueMonth = Int(issue.dropFirst(2).prefix(2)), (1...12).contains(issueMonth),
              text.range(of:#"^\d{2}-\d{2} \d{2}:\d{2}$"#,options:.regularExpression) != nil,
              let fixtureMonth = Int(text.prefix(2)) else { return nil }
        let yearOffset = issueMonth == 12 && fixtureMonth == 1 ? 1 : (issueMonth == 1 && fixtureMonth == 12 ? -1 : 0)
        let formatter = DateFormatter();formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT:8*3600);formatter.dateFormat = "yyyy-MM-dd HH:mm";formatter.isLenient = false
        return formatter.date(from:"\(2000+year+yearOffset)-\(text)")
    }
    static func parseQuote(data: Data, companyID: Int) throws -> DoubleBookQuote {
        guard let root = try JSONSerialization.jsonObject(with:data) as? [Any], root.count >= 2,
              let euro = root[1] as? [[Any]], euro.count >= 2 else { throw GoalModelError.invalidResponse }
        func triplet(_ row: [Any]) -> [Double]? {
            let values = row.compactMap { item -> Double? in
                if let text = item as? String { return Double(text) }
                if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.doubleValue }
                return nil
            }
            return DoubleJudgmentScorer.validOdds(values) && row.count == 3 ? values : nil
        }
        guard let opening = triplet(euro[0]), let current = triplet(euro[1]) else { throw GoalModelError.invalidResponse }
        var openingAsian:DoubleAsianPoint?, currentAsian:DoubleAsianPoint?
        if let asian = try? FiveHundredBeijingSingleClient.parseAsianHandicapQuote(data:data),
           let line = DoubleJudgmentScorer.asianLine(asian.current.handicap) {
            currentAsian = DoubleAsianPoint(homeWater:asian.current.homeWater,line:line,awayWater:asian.current.awayWater)
            if let point = asian.initial, let line = DoubleJudgmentScorer.asianLine(point.handicap) {
                openingAsian = DoubleAsianPoint(homeWater:point.homeWater,line:line,awayWater:point.awayWater)
            }
        }
        return DoubleBookQuote(companyID:companyID,openingEuropean:opening,currentEuropean:current,
            openingAsian:openingAsian,currentAsian:currentAsian)
    }
    private static func quote(fixtureID: String, companyID: Int) async throws -> DoubleBookQuote {
        guard !fixtureID.isEmpty,fixtureID.allSatisfy(\.isNumber) else { throw GoalModelError.invalidResponse }
        var components = URLComponents(string:"https://live.500.com/json/odds.php")!
        components.queryItems = [URLQueryItem(name:"fid",value:fixtureID),URLQueryItem(name:"cid",value:String(companyID))]
        var request = URLRequest(url:components.url!);request.timeoutInterval = 8;request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36",forHTTPHeaderField:"User-Agent")
        request.setValue("https://live.500.com/",forHTTPHeaderField:"Referer")
        let (data,response) = try await URLSession.shared.data(for:request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,(200...299).contains(http.statusCode) else { throw GoalModelError.invalidResponse }
        return try parseQuote(data:data,companyID:companyID)
    }
    static func fetch(matches: [BeijingSingleMatch], factors: Set<DoubleJudgmentFactor>, now:Date = Date(),
                      includeTrends: Bool = false,
                      leadTime: TimeInterval = 0,
                      store: DoubleMarketSnapshotStore = .shared,
                      quoteLoader: @escaping @Sendable (String,Int) async throws -> DoubleBookQuote = { try await quote(fixtureID:$0,companyID:$1) }) async -> DoubleMarketFetchResult {
        guard !factors.isEmpty || includeTrends else { return DoubleMarketFetchResult(evidence:[],notes:[:]) }
        let kickoffs = matches.compactMap { kickoff(issue:$0.issue,matchTime:$0.matchTime) }
        guard kickoffs.count == matches.count, let firstTime = kickoffs.min(), leadTime.isFinite, leadTime >= 0 else {
            return DoubleMarketFetchResult(evidence:[],notes:Dictionary(matches.map {
                (Int($0.matchNumber) ?? 0,"缺少完整六场开赛时间，无法核验整组赛前时点，未采用临时走势")
            },uniquingKeysWith:{ first,_ in first }))
        }
        let groupCutoff = firstTime.addingTimeInterval(-leadTime)
        let lockedMessage = leadTime > 0 ? "已到首场赛前2小时锁定点" : "本组首场已开赛"
        return await withTaskGroup(of:(Int,DoubleMarketEvidence?,String).self) { group in
            for match in matches {
                group.addTask {
                    guard let number = Int(match.matchNumber),let handicap = match.handicap,
                          let kickoff = kickoff(issue:match.issue,matchTime:match.matchTime) else { return (Int(match.matchNumber) ?? 0,nil,"缺少可核验开赛时间，未采用临时走势") }
                    let cached = await store.evidence(issue:match.issue,number:number,fixtureID:match.fixtureID,before:groupCutoff).flatMap {
                        $0.isValid && $0.handicap == handicap && $0.kickoff == kickoff ? $0 : nil
                    }
                    if let cached, now >= groupCutoff { return (number,cached,"\(lockedMessage)，使用锁定点之前归档，已停止后续采集") }
                    guard now < groupCutoff else { return (number,nil,leadTime > 0
                        ? "\(lockedMessage)且没有窗口内快照；仍给赔率参考双选，不计入走势窗口实测"
                        : "本组首场已开赛且没有赛前快照；未采用事后走势或资金") }
                    var books:[DoubleBookQuote] = []
                    let needsQuotes = includeTrends || !factors.isDisjoint(with:[.euro,.asianLine,.asianWater,.books,.reverse])
                    if needsQuotes {
                        for company in (factors.contains(.books) ? [3,5,280] : [3]) {
                            if Task.isCancelled { return (number,nil,"已取消") }
                            if let result = try? await quoteLoader(match.fixtureID,company) { books.append(result) }
                        }
                    }
                    guard !Task.isCancelled,Date() < groupCutoff else { return (number,nil,"采集时已到本组锁定点，未采用") }
                    if needsQuotes && books.isEmpty, let cached {
                        if Date().timeIntervalSince(cached.capturedAt) > 180 {
                            return (number,nil,"欧赔/亚盘获取失败，原快照已超过3分钟；本次未采用过期额外行情")
                        }
                        return (number,cached,"本次欧赔/亚盘获取失败，保留原采集时间的赛前快照；行情未更新")
                    }
                    var evidence = DoubleMarketEvidence(issue:match.issue,number:number,fixtureID:match.fixtureID,handicap:handicap,
                        capturedAt:Date(),kickoff:kickoff,books:books,bettingShares:match.marketBettingShares)
                    guard !books.isEmpty || evidence.publishedShares != nil else {
                        return (number,nil,"未取得可用欧赔、亚盘或公开资金数据；本次未采用额外行情")
                    }
                    evidence = await store.store(evidence)
                    return (number,evidence,"已采集\(books.count)家机构，本机赛前采样\(evidence.observations?.count ?? 1)次；实际投注金额未公开")
                }
            }
            var rows:[DoubleMarketEvidence] = [],notes:[Int:String] = [:]
            for await (number,evidence,note) in group { if let evidence { rows.append(evidence) };notes[number] = note }
            var display = rows
            for match in matches {
                guard let number = Int(match.matchNumber), !display.contains(where: { $0.number == number }),
                      let cached = await store.evidence(issue:match.issue,number:number,fixtureID:match.fixtureID,before:groupCutoff),
                      cached.handicap == match.handicap, cached.kickoff == kickoff(issue:match.issue,matchTime:match.matchTime) else { continue }
                display.append(cached)
            }
            return DoubleMarketFetchResult(evidence:rows.sorted { $0.number<$1.number },notes:notes,
                trendEvidence:display.sorted { $0.number<$1.number })
        }
    }
}
