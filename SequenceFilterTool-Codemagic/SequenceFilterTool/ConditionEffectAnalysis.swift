import SwiftUI
import Charts
import CryptoKit

struct ConditionEffectGroup: Codable, Sendable {
    let year: Int
    let issue: String
    let start: Int
    let logic: String
    let outcomes: [Int]
    let odds: [[Double]]
    var matchNumbers: [Int]? = nil
}

struct ConditionEffectDataset: Codable, Sendable {
    let version: Int
    let source: String
    let groups: [ConditionEffectGroup]
}

struct ConditionEffectRule: Identifiable, Sendable {
    let id: String
    let title: String
    let enabled: Bool
}

struct ConditionEffectCounts: Sendable {
    var groups = 0
    var hits = 0
    var retainedBets = 0
    var hitRate: Double { groups == 0 ? 0 : Double(hits) / Double(groups) }
    var filteredRate: Double { groups == 0 ? 0 : 1 - Double(retainedBets) / Double(groups * 729) }
    var efficiency: Double { filteredRate - (1 - hitRate) }
}

struct ConditionPassRateYear: Codable, Equatable, Sendable {
    var groups = 0
    var hits = 0
    var rate: Double { groups == 0 ? 0 : Double(hits) / Double(groups) }
}

/// Frozen descriptive comparison from Analysis/research_svvvp11_20261104.json.
/// The current-condition card remains separate, so editing a switch cannot
/// present the preset's numbers as a fresh backtest of the edited conditions.
struct SVVVP11HistoricalComparisonView: View {
    private func row(_ title: String, _ hits: Int, _ groups: Int, _ bets: Int, _ meanPrize: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.2f%% · 平均%.2f注", 100 * Double(hits) / Double(groups), Double(bets) / Double(groups)))
                    .monospacedDigit()
            }
            Text("过关\(hits)／有效\(groups)组 · 命中组均奖¥\(String(format: "%.2f", meanPrize))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    var body: some View {
        Group {
            row("2025", 1003, 2439, 556373, 880.331446493218)
            row("2026", 759, 1884, 431362, 948.7895102039644)
            row("两年合计", 1762, 4323, 987735, 909.9887925870859)
            Text("连续六场，任一场31/30/10自动双选。评分0–6.7、赔率乘积≥350、最长连续不平2–6；历史每组125–389注，平均228.48注，不是每组上限。")
                .font(.caption)
            LabeledContent("命中奖金中位数", value: "¥804.35")
            LabeledContent("每组平均成本／奖金", value: "¥456.99／¥371.29")
            Text("总奖金／总成本81.25%，历史平均每组净亏¥85.70。成本和奖金使用相同4,294组完整且无SP=1歧义的开奖SP样本。")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("180注目标与选择依据") {
                Text("已比较21,280种范围组合，未找到平均≤180注、两年各过关>40%、命中均奖≥873.59元同时满足的方案。采用你选定的保40%和奖金方案，不设固定注数或补齐。")
                Text("相同4,323组中，调整前为47.79%、平均261.92注、命中均奖¥873.31；调整后40.76%、228.48注、¥909.99。平均减少33.44注，过关率下降7.03个百分点，命中均奖增加¥36.68。")
            }.font(.caption)
            DisclosureGroup("统计口径与数据范围") {
                Text("2025年2,439组，2026年1,884组；六场赛果须在最终TXT内才算过关。不含手动第7场、倍数和整体赔率门禁500。平均奖金仅统计有完整开奖SP的命中组：2025年993组、2026年759组。29组因缺SP或SP=1的取消及异常结算歧义排除于奖金和成本统计，仍纳入过关率。")
                Text("六场1倍奖金沿用App口径：对应开奖SP连乘×1.3；每注成本2元，未命中返回0。开奖SP来自项目归档和补充查询，不用自定义赔率冒充开奖SP；不含第7场及税费。")
                Text("历史赔率采集时点未经验证，资金与走势缺少历史快照，双选按赔率基线回放。两年均参与参数比较，属于历史探索和跨年检查，不是独立样本外验证；历史超过40%不代表未来能维持，平均奖金也不代表盈利。")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("svvvp11HistoricalComparison")
    }
}

struct ConditionPassRateSummary: Sendable {
    let input: String
    let years: [Int: ConditionPassRateYear]
    let enabledRuleCount: Int
    var twoDoubleYears: [Int: ConditionPassRateYear] = [:]
    var usesAutomaticPairs = false
    var omittedJudgmentCount = 0
    var candidateCountRange: ClosedRange<Int>? = nil
    var twoDoubleCombined: ConditionPassRateYear {
        twoDoubleYears.values.reduce(into: ConditionPassRateYear()) {
            $0.groups += $1.groups; $0.hits += $1.hits
        }
    }
    var combined: ConditionPassRateYear {
        years.values.reduce(into: ConditionPassRateYear()) {
            $0.groups += $1.groups
            $0.hits += $1.hits
        }
    }
}

private actor ConditionPassRateCache {
    static let shared = ConditionPassRateCache()
    private var summaries: [String: ConditionPassRateSummary] = [:]
    func summary(for key: String) -> ConditionPassRateSummary? { summaries[key] }
    func store(_ summary: ConditionPassRateSummary) {
        if summaries.count >= 8 { summaries.removeAll() }
        summaries[summary.input] = summary
    }
}

struct ConditionSuggestionYear: Sendable {
    let standalone: ConditionEffectCounts
    let base: ConditionEffectCounts
    let combined: ConditionEffectCounts
    var additionalFilteredRate: Double {
        base.retainedBets == 0 ? 0 : 1 - Double(combined.retainedBets) / Double(base.retainedBets)
    }
    var hitRetention: Double { base.hits == 0 ? 0 : Double(combined.hits) / Double(base.hits) }
    var efficiency: Double { additionalFilteredRate - (1 - hitRetention) }
}

struct ConditionEffectSuggestion: Identifiable, Sendable {
    let condition: OutcomeCondition
    let range: ClosedRange<Int>
    let years: [Int: ConditionSuggestionYear]
    var id: String { "generated.\(condition.rawValue).\(range.lowerBound)-\(range.upperBound)" }
    var editorID: String { "OC_" + condition.rawValue }
    var title: String { "\(condition.title) \(range.lowerBound)–\(range.upperBound)" }
    var score: Double { [2025, 2026].map { years[$0]?.efficiency ?? -1 }.min()! }
}

/// Histograms retain exact integer counts; a new range can be searched without
/// replaying millions of combinations or approximating the marginal effect.
struct ConditionSuggestionHistogram {
    var actual: [Int: [OutcomeCondition: [Int]]] = [:]
    var baseActual: [Int: [OutcomeCondition: [Int]]] = [:]
    var baseBets: [Int: [OutcomeCondition: [Int]]] = [:]
    var base: [Int: ConditionEffectCounts] = [:]
}

struct ConditionEffectReport: Sendable {
    let rules: [ConditionEffectRule]
    let counts: [Int: [String: ConditionEffectCounts]]
    let issueRanges: [Int: String]
    let notices: [String]
    var suggestions: [ConditionEffectSuggestion] = []

    func nextSuggestion(excluding editorIDs: Set<String>) -> ConditionEffectSuggestion? {
        suggestions.first { !editorIDs.contains($0.editorID) }
    }

    var recommendedRules: [ConditionEffectRule] {
        rules.filter { rule in
            [2025, 2026].allSatisfy { (counts[$0]?[rule.id]?.efficiency ?? -1) > 0 }
        }.sorted { left, right in
            let lhs = [2025, 2026].map { counts[$0]?[left.id]?.efficiency ?? -1 }.min()!
            let rhs = [2025, 2026].map { counts[$0]?[right.id]?.efficiency ?? -1 }.min()!
            return abs(lhs - rhs) > 1e-12 ? lhs > rhs : left.id < right.id
        }.prefix(3).map { $0 }
    }
}

private actor ConditionEffectReportCache {
    static let shared = ConditionEffectReportCache()
    private var reports: [String: ConditionEffectReport] = [:]
    func report(for key: String) -> ConditionEffectReport? { reports[key] }
    func store(_ report: ConditionEffectReport, for key: String) {
        if reports.count >= 4 { reports.removeAll() }
        reports[key] = report
    }
}

enum ConditionEffectAnalysis {
    enum AnalysisError: LocalizedError {
        case invalidInput, unsupported, missingData, invalidData
        var errorDescription: String? {
            switch self {
            case .invalidInput: return "条件范围无效，请返回条件页检查后重试。"
            case .unsupported: return "当前提供SVIP10的逐项统计，请在条件页选择SVIP10后打开。"
            case .missingData: return "缺少两年历史数据，无法计算。"
            case .invalidData: return "历史数据不完整，已停止统计，不使用部分样本生成建议。"
            }
        }
    }

    /// Current ranges and switches only; current fixture numbers and ABCD are
    /// replaced by every historical group's own inputs before evaluation.
    static func template(_ input: String) throws -> FilterConfig {
        var fields = input.components(separatedBy: "|")
        guard fields.count >= 9 else { throw AnalysisError.invalidInput }
        fields[0] = "1,2,3,4,5,6"
        fields[1] = "AAAAAA" // Parsing placeholder; never used as historical ABCD.
        fields.removeAll { $0.contains(":") || $0.uppercased().hasPrefix("MERGE") || $0.hasPrefix("S10MARKET=") }
        fields.append(contentsOf: ["7:3", "MERGE3"])
        guard let config = try? FilterConfig.parse(fields.joined(separator: "|")) else { throw AnalysisError.invalidInput }
        guard config.svip10Frozen160Enabled else { throw AnalysisError.unsupported }
        return config
    }

    static func rules(for config: FilterConfig) -> [ConditionEffectRule] {
        let active = config.conditionPackageEnabled
        func core(_ index: Int, _ title: String, _ basic: BasicCondition) -> ConditionEffectRule {
            ConditionEffectRule(id: "core.\(index)", title: title, enabled: active && config.isEnabled(basic))
        }
        let a = config.svip10AdditionalFilters
        var rows = [
            core(0, "六场S \(config.six250SumRange.lowerBound)–\(config.six250SumRange.upperBound)", .sum),
            core(1, "六场实际M \(config.six250MRange.lowerBound)–\(config.six250MRange.upperBound)", .displacement),
            core(2, "六场R \(config.six250RRange.lowerBound)–\(config.six250RRange.upperBound)", .roughness),
            core(3, "判定值3最多\(config.valueThreeMaximum)个", .valueThree),
            core(6, "判定值2最多\(config.valueTwoMaximum)个", .valueTwo),
            core(4, "自定义评分 \(config.six250ScoreLower)–\(config.six250ScoreUpper)", .score),
        ]
        let additions: [(Int, String, Bool)] = [
            (0, "第三选\(a.coldCountRange.lowerBound)–\(a.coldCountRange.upperBound)个", a.coldCountEnabled),
            (1, "平局\(a.drawCountRange.lowerBound)–\(a.drawCountRange.upperBound)个", a.drawCountEnabled),
            (2, "前5场胜负切换0–2次", a.winLossSwitchEnabled),
            (4, "前5场实际M \(a.fiveMatchMRange.lowerBound)–\(a.fiveMatchMRange.upperBound)", a.fiveMatchMEnabled),
            (5, "前5场同彩果连续≤2", a.frontFiveSameOutcomeRunMaximum2Enabled),
            (6, "前5场隔场回返≤2", a.frontFiveReturnMaximum2Enabled),
            (7, "前5场不连续平局", a.frontFiveNoConsecutiveDrawEnabled),
            (8, "前5场判定值3≤2个", a.frontFiveValueThreeMaximum2Enabled),
            (15, "六场第一选1–4个", a.sixMatchFavoriteCount1To4Enabled),
            (10, "六场自定义赔率乘积≥\(a.sixMatchMinimumOddsProduct)", a.sixMatchMinimumOddsProductEnabled),
            (12, "六场彩果断点B=\(a.sixMatchBreakpointRange.lowerBound)–\(a.sixMatchBreakpointRange.upperBound)", a.sixMatchBreakpoint3To5Enabled),
            (13, !a.adDoublesWithinSixEnabled && a.automaticDoublePairEnabled && a.automaticDoubleCount == 1 ? "一场31/30/10自动双选" : "第一处自动双选", a.firstDoubleActive),
            (14, "第二处自动双选", a.secondDoubleActive),
        ]
        rows += additions.filter { ![13, 14].contains($0.0) || a.firstDoubleActive || a.secondDoubleActive }
            .map { ConditionEffectRule(id: "extra.\($0.0)", title: $0.1, enabled: active && $0.2) }
        for condition in OutcomeCondition.activeCases {
            if let range = config.outcomeConditions[condition] {
                rows.append(ConditionEffectRule(id: "outcome.\(condition.rawValue)",
                    title: "\(condition.title) \(range.lowerBound)–\(range.upperBound)",
                    enabled: condition.isHighPass98Fifty ? (config.highPass98FiftyGroupEnabled ?? active)
                        : (condition.isHighPass98 ? (config.highPass98GroupEnabled ?? active)
                        : (condition.isHighPass93 ? (config.highPass93GroupEnabled ?? active) : active))))
            }
        }
        rows.append(ConditionEffectRule(id: "independent.double50", title: "某一场自动双选（六场中概率前两项之和最高）",
            enabled: config.highPass50DoubleActive))
        return rows
    }

    static func preparedConfig(template: FilterConfig, group: ConditionEffectGroup) throws -> FilterConfig {
        var fields = template.normalizedInput.components(separatedBy: "|")
        fields[0] = (group.matchNumbers ?? Array(group.start..<(group.start + 6))).map(String.init).joined(separator: ",")
        fields[1] = group.logic
        // The historical fixed seventh leg is excluded from both denominators.
        fields = fields.map { $0 == "7:3" ? "1:3" : $0 }
        guard var config = try? FilterConfig.parse(fields.joined(separator: "|")) else { throw AnalysisError.invalidData }
        config.conditionPackageEnabled = true
        config.disabledBasicConditions = []
        var a = config.svip10AdditionalFilters
        // The dataset has no time-verified funds/Asian/European snapshots.
        // Never silently evaluate a partial multi-factor model as its hit rate.
        a.doubleJudgmentFactors = []; a.doubleMarketEvidence = []
        a.coldCountEnabled = true; a.drawCountEnabled = true; a.winLossSwitchEnabled = true
        a.fiveMatchMEnabled = true; a.frontFiveSameOutcomeRunMaximum2Enabled = true
        a.frontFiveReturnMaximum2Enabled = true; a.frontFiveNoConsecutiveDrawEnabled = true
        a.frontFiveValueThreeMaximum2Enabled = true; a.sixMatchFavoriteCount1To4Enabled = true
        a.sixMatchMinimumOddsProductEnabled = true; a.sixMatchBreakpoint3To5Enabled = true
        a.highestDoubleProbabilityTopTwoEnabled = true; a.secondDoubleLowestProbabilityEnabled = true
        config.svip10AdditionalFilters = a
        if let selection = SequenceFilterEngine.svip10SecondDoubleSelection(
            config: config, currentOutcomeProbabilities: nil, customOdds: group.odds) {
            config.resolvedSecondDoublePosition = selection.position
            config.resolvedSecondDoubleRemovedOutcome = selection.removedOutcome
            config.resolvedSecondDoubleProbability = selection.doubleProbability
        }
        return config
    }

    static func failures(outcomes: [Int], config: FilterConfig, odds: [[Double]]) -> Set<String> {
        var failures = Set<String>()
        _ = SequenceFilterEngine.six250FailureReasons(outcomes: outcomes, config: config, customOdds: odds,
            collectMessages: false, onFailure: { failures.insert("core.\($0)") })
        _ = SequenceFilterEngine.svip10AdditionalFailureReasons(outcomes: outcomes, config: config, customOdds: odds,
            collectMessages: false, onFailure: { failures.insert("extra.\($0)") })
        for (condition, range) in config.outcomeConditions where !range.contains(condition.value(in: outcomes)) {
            failures.insert("outcome.\(condition.rawValue)")
        }
        if let selection = config.highPass50DoubleSelection(in: odds), outcomes.count >= 6 {
            if !selection.outcomes.contains(outcomes[selection.position - 1]) { failures.insert("independent.double50") }
        } else { failures.insert("independent.double50") }
        return failures
    }

    /// Fixed quality criteria for historical recommendations, not engine gates.
    /// Each supported metric contributes at most one range. Both years must pass
    /// independently; searching both years is retrospective, not a holdout test.
    static func suggestions(template: FilterConfig, histogram: ConditionSuggestionHistogram,
                            patternValues: [[Int]]) -> [ConditionEffectSuggestion] {
        let metrics = OutcomeCondition.activeCases
        var best: [ConditionEffectSuggestion] = []
        for (index, condition) in metrics.enumerated() {
            guard !condition.isRelativePositionCondition, template.outcomeConditions[condition] == nil,
                  !(condition == .draws && template.svip10AdditionalFilters.drawCountEnabled) else { continue }
            var choices: [ConditionEffectSuggestion] = []
            let maximum = condition.maximum(matchCount: 6)
            for lower in 0...maximum {
                for upper in lower...maximum {
                    let range = lower...upper
                    let retainedPerGroup = patternValues.filter { range.contains($0[index]) }.count
                    var years: [Int: ConditionSuggestionYear] = [:]
                    for year in [2025, 2026] {
                        guard let base = histogram.base[year], base.groups > 0, base.hits > 0, base.retainedBets > 0,
                              let actual = histogram.actual[year]?[condition],
                              let baseActual = histogram.baseActual[year]?[condition],
                              let bets = histogram.baseBets[year]?[condition] else { continue }
                        let standalone = ConditionEffectCounts(groups: base.groups,
                            hits: range.reduce(0) { $0 + actual[$1] }, retainedBets: retainedPerGroup * base.groups)
                        let combined = ConditionEffectCounts(groups: base.groups,
                            hits: range.reduce(0) { $0 + baseActual[$1] }, retainedBets: range.reduce(0) { $0 + bets[$1] })
                        let counts = ConditionSuggestionYear(standalone: standalone, base: base, combined: combined)
                        guard standalone.hitRate >= 0.90, standalone.filteredRate >= 0.05,
                              counts.additionalFilteredRate >= 0.02, counts.hitRetention >= 0.95,
                              counts.efficiency > 0 else { continue }
                        years[year] = counts
                    }
                    if years.count == 2 { choices.append(ConditionEffectSuggestion(condition: condition, range: range, years: years)) }
                }
            }
            if let winner = choices.sorted(by: suggestionPrecedes).first { best.append(winner) }
        }
        return best.sorted(by: suggestionPrecedes)
    }

    private static func suggestionPrecedes(_ left: ConditionEffectSuggestion, _ right: ConditionEffectSuggestion) -> Bool {
        if abs(left.score - right.score) > 1e-12 { return left.score > right.score }
        let lhs = left.years.values.map { $0.standalone.hitRate }.min() ?? 0
        let rhs = right.years.values.map { $0.standalone.hitRate }.min() ?? 0
        return abs(lhs - rhs) > 1e-12 ? lhs > rhs : left.id < right.id
    }

    fileprivate static func validate(_ dataset: ConditionEffectDataset, requireBothYears: Bool = true) throws {
        guard dataset.version == 1, !dataset.groups.isEmpty else { throw AnalysisError.invalidData }
        var seen = Set<String>()
        for group in dataset.groups {
            guard [2025, 2026].contains(group.year), group.start % 6 == 2,
                  group.issue.hasPrefix(group.year == 2025 ? "25" : "26"),
                  group.logic.count == 6, group.logic.allSatisfy({ "ABCD".contains($0) }),
                  group.outcomes.count == 6, group.outcomes.allSatisfy({ [3, 1, 0].contains($0) }),
                  group.odds.count == 6, group.odds.allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0.isFinite && $0 > 0 }) }),
                  seen.insert("\(group.issue):\(group.start)").inserted else { throw AnalysisError.invalidData }
        }
        if requireBothYears && ![2025, 2026].allSatisfy({ year in dataset.groups.contains { $0.year == year } }) {
            throw AnalysisError.invalidData
        }
    }

    static func usesAutomaticPairs(_ config: FilterConfig) -> Bool {
        config.conditionPackageEnabled && config.svip10AdditionalFilters.automaticDoublePairEnabled
            && config.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled
            && (config.svip10AdditionalFilters.automaticDoubleCount == 1 || config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled)
    }

    /// Keep every historical six-match group intact. Pair selection may
    /// change the two retained outcomes, never the group's match numbers.
    static func evaluatedGroups(template: FilterConfig, dataset: ConditionEffectDataset) throws
        -> (groups: [ConditionEffectGroup], candidateCounts: [Int]) {
        try Task.checkCancellation()
        return (dataset.groups, usesAutomaticPairs(template) ? Array(repeating: 6, count: dataset.groups.count) : [])
    }

    /// Replay the actual result once per group. Do not multiply standalone rates
    /// or enumerate all 729 candidates just to refresh the home screen.
    static func passRate(input: String, dataset: ConditionEffectDataset) async throws -> ConditionPassRateSummary {
        try Task.checkCancellation()
        let template = try template(input)
        try validate(dataset)
        let activeIDs = Set(rules(for: template).filter(\.enabled).map(\.id))
        var years: [Int: ConditionPassRateYear] = [:]
        var jointYears: [Int: ConditionPassRateYear] = [:]
        let evaluated = try evaluatedGroups(template: template, dataset: dataset)
        let jointEnabled = template.conditionPackageEnabled && template.svip10AdditionalFilters.firstDoubleActive
            && (template.svip10AdditionalFilters.adDoublesWithinSixEnabled && template.svip10AdditionalFilters.adDoubleCountWithinSix == 1
                || !template.svip10AdditionalFilters.adDoublesWithinSixEnabled && template.svip10AdditionalFilters.automaticDoublePairEnabled && template.svip10AdditionalFilters.automaticDoubleCount == 1
                || template.svip10AdditionalFilters.secondDoubleActive)
        for group in evaluated.groups {
            try Task.checkCancellation()
            let config = try preparedConfig(template: template, group: group)
            let failed = failures(outcomes: group.outcomes, config: config, odds: group.odds)
            years[group.year, default: ConditionPassRateYear()].groups += 1
            if failed.isDisjoint(with: activeIDs) { years[group.year]!.hits += 1 }
            if jointEnabled {
                jointYears[group.year, default: ConditionPassRateYear()].groups += 1
                if !failed.contains("extra.13") && !failed.contains("extra.14") { jointYears[group.year]!.hits += 1 }
            }
        }
        let counts = evaluated.candidateCounts
        return ConditionPassRateSummary(input: template.normalizedInput, years: years,
            enabledRuleCount: activeIDs.count, twoDoubleYears: jointYears, usesAutomaticPairs: usesAutomaticPairs(template),
            omittedJudgmentCount: template.conditionPackageEnabled && template.svip10AdditionalFilters.automaticDoublePairEnabled && (template.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled || template.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled) ? template.svip10AdditionalFilters.doubleJudgmentFactors.count : 0,
            candidateCountRange: counts.min().flatMap { lower in counts.max().map { lower...$0 } })
    }

    static func analyze(input: String, dataset: ConditionEffectDataset,
                        progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> ConditionEffectReport {
        let template = try template(input)
        let rules = rules(for: template)
        try validate(dataset)
        let evaluated = try evaluatedGroups(template: template, dataset: dataset)
        let candidates = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3, 1, 0].map { row + [$0] } } }
        let metrics = OutcomeCondition.activeCases
        let patternValues = candidates.map { outcomes in metrics.map { $0.value(in: outcomes) } }
        let activeIDs = Set(rules.filter(\.enabled).map(\.id))
        var histogram = ConditionSuggestionHistogram()
        for year in [2025, 2026] {
            let bins = Dictionary(uniqueKeysWithValues: metrics.map { ($0, Array(repeating: 0, count: $0.maximum(matchCount: 6) + 1)) })
            histogram.actual[year] = bins; histogram.baseActual[year] = bins; histogram.baseBets[year] = bins
        }
        var counts: [Int: [String: ConditionEffectCounts]] = [:]
        for (index, group) in evaluated.groups.enumerated() {
            try Task.checkCancellation()
            let config = try preparedConfig(template: template, group: group)
            let actualFailures = failures(outcomes: group.outcomes, config: config, odds: group.odds)
            let baseHit = actualFailures.isDisjoint(with: activeIDs)
            histogram.base[group.year, default: ConditionEffectCounts()].groups += 1
            if baseHit { histogram.base[group.year]!.hits += 1 }
            for metric in metrics {
                let value = metric.value(in: group.outcomes)
                histogram.actual[group.year]![metric]![value] += 1
                if baseHit { histogram.baseActual[group.year]![metric]![value] += 1 }
            }
            var rejected: [String: Int] = [:]
            for (patternIndex, outcomes) in candidates.enumerated() {
                let failed = failures(outcomes: outcomes, config: config, odds: group.odds)
                for id in failed { rejected[id, default: 0] += 1 }
                if failed.isDisjoint(with: activeIDs) {
                    histogram.base[group.year]!.retainedBets += 1
                    for (metricIndex, metric) in metrics.enumerated() {
                        histogram.baseBets[group.year]![metric]![patternValues[patternIndex][metricIndex]] += 1
                    }
                }
            }
            for rule in rules {
                var count = counts[group.year]?[rule.id] ?? ConditionEffectCounts()
                count.groups += 1
                if !actualFailures.contains(rule.id) { count.hits += 1 }
                count.retainedBets += 729 - (rejected[rule.id] ?? 0)
                counts[group.year, default: [:]][rule.id] = count
            }
            if index % 16 == 0 || index + 1 == dataset.groups.count { await progress(index + 1, dataset.groups.count) }
        }
        var issueRanges: [Int: String] = [:]
        for year in [2025, 2026] {
            let issues = dataset.groups.filter { $0.year == year }.map(\.issue).sorted()
            issueRanges[year] = "\(issues.first!)–\(issues.last!)"
        }
        var notices = [usesAutomaticPairs(template)
            ? "从第2场起每6场一组，固定该连续6场，在组内自动比较31、30、10选择双选；不跨组或更换比赛。"
            : "固定从第2场起每6场一组，分母包含全部现有有效组；不是完整日历年。",
            "命中率＝真实前六场赛果单独通过该条件的组数／全部组数；过滤比例＝从每组729种组合中单独剔除的比例。",
            "关闭项显示按当前范围单独开启的模拟效果。各项独立计算，不能相乘或相加当作整单命中率；全局容错不参与单项评估。",
            "第7场不参与；本页未合并TXT，行数未计算。历史赔率采集时点未验证，回放和建议不保证未来。",
            "本页列出可逐注复算的SVIP10硬条件；整体赔率门禁等投注前检查需整单回放，不包含在单项结果里。",
            "概率校正是选择方式，效果体现在两处双选中；自动比较开关开启时，两处统一使用自定义赔率概率；关闭自动比较且未校正时，历史第二处按自定义赔率回退口径评估。"]
        if !template.svip10AdditionalFilters.doubleJudgmentFactors.isEmpty {
            notices.insert("缺少两年完整且可核验的赛前资金/欧赔/亚盘快照；下面只回放关闭新增试验判断后的赔率基线与当前过滤条件，不是多因素方案过关率。", at: 0)
        }
        if template.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled || template.svip10AdditionalFilters.probabilityMass60Enabled || template.svip10AdditionalFilters.statisticalLineBudgetEnabled {
            notices.append("补回100注、概率优先60行和统计优选50行依赖组合结果，不作为单项硬条件；它们的实际效果需要整单回放。")
        }
        let generated = suggestions(template: template, histogram: histogram, patternValues: patternValues)
        return ConditionEffectReport(rules: rules, counts: counts, issueRanges: issueRanges, notices: notices, suggestions: generated)
    }
}

/// Stable source-order batches; the archive itself is never trimmed or shuffled.
struct CompleteConditionSamplePlan: Codable, Equatable, Sendable {
    static let batchCount = 14
    static let batchSize = 300
    static let eligibleCount = batchCount * batchSize
    let totalGroupCount: Int
    let batchIndex: Int
    var batchNumber: Int { batchIndex + 1 }
    var range: Range<Int> { (batchIndex * Self.batchSize)..<((batchIndex + 1) * Self.batchSize) }
    var tailCount: Int { totalGroupCount - Self.eligibleCount }

    init(totalGroupCount: Int, batchIndex: Int) throws {
        guard totalGroupCount >= Self.eligibleCount, (0..<Self.batchCount).contains(batchIndex) else {
            throw ConditionEffectAnalysis.AnalysisError.invalidData
        }
        self.totalGroupCount = totalGroupCount
        self.batchIndex = batchIndex
    }

    static func draw<R: RandomNumberGenerator>(totalGroupCount: Int, using generator: inout R) throws -> Self {
        try Self(totalGroupCount: totalGroupCount, batchIndex: Int.random(in: 0..<batchCount, using: &generator))
    }

    func dataset(from archive: ConditionEffectDataset) throws -> ConditionEffectDataset {
        // Revalidate decoded plans too; malformed metadata must not subscript the archive.
        _ = try Self(totalGroupCount: totalGroupCount, batchIndex: batchIndex)
        guard archive.groups.count == totalGroupCount else { throw ConditionEffectAnalysis.AnalysisError.invalidData }
        return ConditionEffectDataset(version: archive.version, source: archive.source, groups: Array(archive.groups[range]))
    }
}

struct CompleteConditionBacktestRequest: Equatable, Sendable {
    let input: String
    let sampled: Bool
    let redraw: Int
}

/// One draw per logical request, including pause/resume. A new run invalidates
/// every publication from its predecessor, even if that worker ignores cancellation.
struct CompleteConditionBacktestSession: Sendable {
    private(set) var request: CompleteConditionBacktestRequest?
    private(set) var sample: CompleteConditionSamplePlan?
    private var runID: UUID?

    mutating func begin(_ request: CompleteConditionBacktestRequest) -> UUID {
        if self.request != request { sample = nil }
        self.request = request
        let id = UUID()
        runID = id
        return id
    }

    func accepts(_ id: UUID, request: CompleteConditionBacktestRequest) -> Bool {
        self.request == request && runID == id
    }

    mutating func freezeSample<R: RandomNumberGenerator>(totalGroupCount: Int, using generator: inout R,
        runID: UUID, request: CompleteConditionBacktestRequest) throws -> CompleteConditionSamplePlan {
        guard accepts(runID, request: request) else { throw CancellationError() }
        if let sample { return sample }
        let value = try CompleteConditionSamplePlan.draw(totalGroupCount: totalGroupCount, using: &generator)
        sample = value
        return value
    }
}

struct CompleteConditionBacktestSummary: Codable, Sendable {
    let input: String
    let years: [Int: ConditionPassRateYear]
    let excluded: [Int: Int]
    let usesOddsBaseline: Bool
    var sample: CompleteConditionSamplePlan? = nil
    var combined: ConditionPassRateYear {
        years.values.reduce(into: ConditionPassRateYear()) { $0.groups += $1.groups; $0.hits += $1.hits }
    }
}

enum CompleteConditionBacktest {
    struct Fixture: Equatable {
        let number: Int
        let logic: LogicMapping
        let outcome: Int
        let odds: [Double]
        var selection: VIP6MatchRecommender.ADSelectionFixture { .init(number: number, logic: logic) }
    }

    static func run(input: String, dataset: ConditionEffectDataset,
                    progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> CompleteConditionBacktestSummary {
        try await run(input: input, dataset: dataset, sample: nil, progress: progress)
    }

    static func runSample(input: String, archive: ConditionEffectDataset, plan: CompleteConditionSamplePlan,
                          progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> CompleteConditionBacktestSummary {
        // Slice before fixture preparation or any calls to the full generation engine.
        try await run(input: input, dataset: plan.dataset(from: archive), sample: plan, progress: progress)
    }

    private static func run(input: String, dataset: ConditionEffectDataset, sample: CompleteConditionSamplePlan?,
                            progress: @Sendable (Int, Int) async -> Void) async throws -> CompleteConditionBacktestSummary {
        try Task.checkCancellation()
        let template = try ConditionEffectAnalysis.template(input)
        try ConditionEffectAnalysis.validate(dataset, requireBothYears: sample == nil)
        guard !template.requiresStrictProbabilityData else { throw BacktestError.missingProbabilities }
        var fixtures: [String: [Int: Fixture]] = [:]
        for group in dataset.groups {
            try Task.checkCancellation()
            let numbers = group.matchNumbers ?? Array(group.start..<(group.start + 6))
            guard numbers.count == 6, Set(numbers).count == 6, numbers == numbers.sorted(),
                  numbers.allSatisfy({ $0 > 0 && $0 < Int.max - 6 }) else { throw ConditionEffectAnalysis.AnalysisError.invalidData }
            for (index, letter) in group.logic.enumerated() {
                guard let logic = LogicMapping(rawValue: String(letter).lowercased()) else { throw ConditionEffectAnalysis.AnalysisError.invalidData }
                let row = Fixture(number: numbers[index], logic: logic, outcome: group.outcomes[index], odds: group.odds[index])
                if let old = fixtures[group.issue]?[row.number], old != row { throw ConditionEffectAnalysis.AnalysisError.invalidData }
                fixtures[group.issue, default: [:]][row.number] = row
            }
        }
        let ordered = fixtures.mapValues { $0.values.sorted { $0.number < $1.number } }
        var years: [Int: ConditionPassRateYear] = [:], excluded: [Int: Int] = [:]
        for (index, group) in dataset.groups.enumerated() {
            try Task.checkCancellation()
            if index % 512 == 0 { NSLog("COMPLETE-BACKTEST progress=%ld/%ld", index, dataset.groups.count) }
            let pool = fixtures[group.issue]!
            let initial = group.matchNumbers ?? Array(group.start..<(group.start + 6))
            var numbers = initial
            if template.conditionPackageEnabled && template.svip10AdditionalFilters.adDoublesWithinSixEnabled {
                do {
                    numbers = try VIP6MatchRecommender.fillingADMatchNumbers(
                        initial: initial.map { pool[$0]!.selection },
                        later: ordered[group.issue]!.lazy.filter { $0.number > initial.last! }.map(\.selection),
                        requiredCount: template.svip10AdditionalFilters.adDoubleCountWithinSix)
                } catch is VIP6MatchRecommender.ABCDSelectionError {
                    excluded[group.year, default: 0] += 1
                    await progress(index + 1, dataset.groups.count)
                    continue
                }
                // A missing historical block could contain an earlier A/D.
                // Exclude it rather than inventing what live selection would do.
                if numbers != initial && !(initial.first!...numbers.last!).allSatisfy({ pool[$0] != nil }) {
                    excluded[group.year, default: 0] += 1
                    await progress(index + 1, dataset.groups.count)
                    continue
                }
            }
            let selected = numbers.map { pool[$0]! }
            var fields = template.normalizedInput.components(separatedBy: "|")
            fields.removeAll { $0.hasPrefix("RESULTBEFORE=") }
            if !template.historicalOutcomeWindows.isEmpty { fields.append("RESULTBEFORE=" + group.issue) }
            fields[0] = numbers.map(String.init).joined(separator: ",")
            fields[1] = selected.map { $0.logic.displayName }.joined()
            fields.removeAll { $0.contains(":") || $0.uppercased().hasPrefix("MERGE") }
            var extra = 1
            while numbers.contains(extra) { extra += 1 }
            fields.append(contentsOf: ["\(extra):3", "MERGE3"])
            let config: FilterConfig
            do { config = try FilterConfig.parse(fields.joined(separator: "|")) }
            catch {
                NSLog("COMPLETE-BACKTEST invalid sample numbers=%@ logic=%@ error=%@", fields[0], fields[1], String(describing: error))
                throw error
            }
            let generated = SequenceFilterEngine.calculate(config, previousContext: nil,
                currentOutcomeSPs: selected.map(\.odds), applyPoissonRelationshipCondition: false)
            try Task.checkCancellation()
            let target = selected.map(\.outcome)
            let hit = generated.exportCompressedRecords.contains { record in
                record.options.count >= 6 && zip(record.options.prefix(6), target).allSatisfy { $0.contains($1) }
            }
            years[group.year, default: ConditionPassRateYear()].groups += 1
            if hit { years[group.year]!.hits += 1 }
            if index % 16 == 0 || index + 1 == dataset.groups.count { await progress(index + 1, dataset.groups.count) }
        }
        return CompleteConditionBacktestSummary(input: template.normalizedInput, years: years, excluded: excluded,
            usesOddsBaseline: template.conditionPackageEnabled && !template.svip10AdditionalFilters.doubleJudgmentFactors.isEmpty,
            sample: sample)
    }

    enum BacktestError: LocalizedError {
        case missingProbabilities
        var errorDescription: String? { "当前概率条件缺少历史模型概率，暂时无法完整回测。" }
    }
}

private actor CompleteConditionBacktestCache {
    static let shared = CompleteConditionBacktestCache()
    private var dataset: (ConditionEffectDataset, String)?
    private var summaries: [String: CompleteConditionBacktestSummary] = [:]
    private var loaded = false
    static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SequenceFilterCompleteBacktest-v1.json")
    }
    func history() throws -> (ConditionEffectDataset, String) {
        if let dataset { return dataset }
        guard let url = Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json") else {
            throw ConditionEffectAnalysis.AnalysisError.missingData
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ConditionEffectDataset.self, from: data)
        try ConditionEffectAnalysis.validate(decoded)
        let value = (decoded, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        dataset = value
        return value
    }
    func summary(for key: String) -> CompleteConditionBacktestSummary? {
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: Self.fileURL),
               let saved = try? JSONDecoder().decode([String: CompleteConditionBacktestSummary].self, from: data) { summaries = saved }
        }
        return summaries[key]
    }
    func store(_ summary: CompleteConditionBacktestSummary, key: String) {
        if summaries.count >= 4 { summaries.removeAll() }
        summaries[key] = summary
        if let data = try? JSONEncoder().encode(summaries) {
            try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

struct CompleteConditionPassRateCard: View {
    let input: String?
    var paused = false
    var sampled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary: CompleteConditionBacktestSummary?
    @State private var progress = "正在准备历史回测…"
    @State private var error: String?
    @State private var redraw = 0
    @State private var session = CompleteConditionBacktestSession()
    private var configurationKey: String { input.flatMap { try? ConditionEffectAnalysis.template($0).normalizedInput } ?? "" }
    private var request: CompleteConditionBacktestRequest {
        .init(input: configurationKey, sampled: sampled, redraw: redraw)
    }
    private var currentSummary: CompleteConditionBacktestSummary? {
        session.request == request && summary?.input == configurationKey ? summary : nil
    }
    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("当前全部条件过关率").font(.subheadline.bold())
                Spacer(minLength: 4)
                if let summary = currentSummary, summary.combined.groups > 0 {
                    Text(percent(summary.combined.rate)).font(.headline).monospacedDigit()
                }
            }
            if sampled {
                if session.request == request, let plan = session.sample {
                    Text("随机第\(plan.batchNumber)/14批 · 本次300组 · 可抽样4,200/\(plan.totalGroupCount)组")
                        .font(.caption).monospacedDigit()
                    Text("按归档原顺序固定分为14批，每批300组；末尾\(plan.tailCount)组保留在归档，不参与这14批。每次等概率抽一批，同次计算不换批；结果为抽样参考。")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("从14个固定的300组批次中等概率抽一批回测")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button("重新抽取300组计算") { redraw += 1 }
                    .font(.caption)
                    .disabled(configurationKey.isEmpty || paused)
                    .accessibilityIdentifier("input.redrawConditionSample")
            }
            if let summary = currentSummary {
                if summary.usesOddsBaseline {
                    Text("2025/2026历史回测 · 赔率基线参考").font(.caption2).foregroundStyle(.secondary)
                }
                if summary.combined.groups == 0 { Text("历史有效选场样本不足").font(.caption) }
                HStack {
                    ForEach([2025, 2026], id: \.self) { year in
                        let count = summary.years[year] ?? ConditionPassRateYear()
                        Text("\(String(year))：\(count.groups == 0 ? "—" : percent(count.rate))（\(count.hits)/\(count.groups)）")
                            .font(.caption).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                let excluded = summary.excluded.values.reduce(0, +)
                Text("过关\(summary.combined.hits)／有效\(summary.combined.groups)组 · 选场排除\(excluded)组\(sampled ? " · 抽取300组" : "")")
                    .font(.caption).monospacedDigit()
                DisclosureGroup("回测口径") {
                    Text("每期第2场起每6场为初始组，按当前全部开关与范围完整生成，六场赛果在最终TXT中才算过关。\(summary.input.contains("S10ADWITHIN6=1") ? "旧A/D协议沿用顺延补齐，无法选场或补齐路径缺数据的组排除于分母。" : "使用原连续六场，不要求包含A/D，不顺延补A/D。")不含手动第7场。")
                    if sampled { Text("本次只完整计算抽中的300组；有效分母为300减选场排除组数。批次可能只包含某一年，分年栏的0组表示本次未抽中该年。") }
                    Text(summary.usesOddsBaseline ? "历史缺少可核验的赛前资金与走势快照，双选按赔率基线回放；此处为历史参考。" : "历史赔率采集时点未验证，回测结果仅供历史参考。")
                }.font(.caption2).foregroundStyle(.secondary)
            } else if session.request == request, let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if input != nil && configurationKey.isEmpty {
                Text("条件范围无效，修正后自动回测").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(paused ? "生成完成后继续回测" : (session.request == request ? progress : "正在准备历史回测…")).font(.caption)
            }
        }
        .accessibilityIdentifier("input.completeConditionPassRate")
        .task(id: configurationKey + "|\(sampled)|\(redraw)|\(scenePhase == .active)|\(paused)") {
            let request = self.request
            if session.request != request {
                summary = nil
                error = nil
                progress = "正在准备历史回测…"
            }
            let runID = session.begin(request)
            guard let input, !request.input.isEmpty, scenePhase == .active, !paused, summary == nil else { return }
            error = nil
            let work = Task.detached(priority: .utility) {
                try await Task.sleep(nanoseconds: 350_000_000)
                let (dataset, signature) = try await CompleteConditionBacktestCache.shared.history()
                try Task.checkCancellation()
                let plan: CompleteConditionSamplePlan? = try await MainActor.run {
                    guard session.accepts(runID, request: request) else { throw CancellationError() }
                    guard request.sampled else { return nil }
                    var generator = SystemRandomNumberGenerator()
                    return try session.freezeSample(totalGroupCount: dataset.groups.count, using: &generator,
                        runID: runID, request: request)
                }
                let report: @Sendable (Int, Int) async -> Void = { done, total in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard session.accepts(runID, request: request) else { return }
                        progress = "回测当前全部条件：\(done)/\(total)组"
                    }
                }
                if let plan {
                    return try await CompleteConditionBacktest.runSample(input: input, archive: dataset, plan: plan, progress: report)
                }
                let cacheKey = "complete-ad-count-v2|" + signature + "|" + request.input
                if let cached = await CompleteConditionBacktestCache.shared.summary(for: cacheKey) { return cached }
                let value = try await CompleteConditionBacktest.run(input: input, dataset: dataset, progress: report)
                try Task.checkCancellation()
                await CompleteConditionBacktestCache.shared.store(value, key: cacheKey)
                return value
            }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                guard session.accepts(runID, request: request) else { return }
                summary = value
                NSLog("COMPLETE-BACKTEST finished groups=%ld hits=%ld rate=%.4f", value.combined.groups, value.combined.hits, value.combined.rate)
            } catch is CancellationError { } catch {
                guard !Task.isCancelled, session.accepts(runID, request: request) else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

/// The task restarts on re-entry, foregrounding, and condition changes. A result
/// is only displayed for its exact current configuration, including cache hits.
struct ConditionPassRateCard: View {
    let input: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary: ConditionPassRateSummary?
    @State private var error: String?

    private var isSingleAD: Bool { input?.contains("S10ADWITHIN6=1") == true && input?.contains("S10ADCOUNT=1") == true }
    private var isSingleAny: Bool { input?.contains("S10ADWITHIN6=1") != true && input?.contains("S10DBLCOUNT=1") == true && input?.contains("S10AUTOPAIR=1") == true }
    private var isSingleDouble: Bool { isSingleAD || isSingleAny }
    private var hasDoubleRestriction: Bool {
        guard let input, let config = try? ConditionEffectAnalysis.template(input) else { return false }
        return config.svip10AdditionalFilters.firstDoubleActive || config.svip10AdditionalFilters.secondDoubleActive || config.highPass50DoubleActive
    }

    private var showsFixedFrontTwoReference: Bool { input?.contains("S10FRONTDBL=1") == true }

    private var showsMaximum105Reference: Bool { input?.contains("S10MAX105=1") == true }

    private var configurationKey: String {
        input.flatMap { try? ConditionEffectAnalysis.template($0).normalizedInput } ?? input ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showsMaximum105Reference {
                Text("以下为最多105注优选前的硬条件历史参考，未包含最终105注截取；不能当作当前最终TXT过关率。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if showsFixedFrontTwoReference {
                Text("以下为固定历史组六场参考，不是按胜负倾向选前两场、后四场连续的新选场过关率；新方案以独立赛前登记实测为准。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if input?.contains("S10FRONTAD=1") == true {
                Text("以下为固定连续六场的历史参考，不是前两场A/D选场后的过关率；新选场效果以赛前登记实测为准。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if input?.contains("S10ABCDSELECT=1") == true {
                Text("以下为固定连续六场的历史参考，不是补齐ABCD非连续选场后的过关率；新选场效果以赛前登记实测为准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let summary, summary.input == configurationKey, summary.twoDoubleCombined.groups > 0 {
                HStack {
                    Text(isSingleAny ? "一场自动双选过关率" : isSingleAD ? "一场A/D双选过关率（固定组六场参考）" : summary.omittedJudgmentCount > 0 ? "双选赔率基线过关率" : "两个双选一起过关率").font(.subheadline.bold())
                    Spacer(minLength: 4)
                    Text(percent(summary.twoDoubleCombined.rate)).font(.headline).monospacedDigit()
                }
                Text("\(isSingleDouble ? "一场双选命中" : "两场同时命中") \(summary.twoDoubleCombined.hits)／\(summary.twoDoubleCombined.groups)组 · \(showsFixedFrontTwoReference ? "历史组六场的前两场固定31/10" : (summary.usesAutomaticPairs ? "连续6场内自动比较31/30/10" : "原六场内选择"))")
                    .font(.caption).monospacedDigit()
                HStack {
                    ForEach([2025, 2026], id: \.self) { year in
                        if let count = summary.twoDoubleYears[year] {
                            Text("\(String(year))：\(percent(count.rate))（\(count.hits)/\(count.groups)）")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.font(.caption2).monospacedDigit()
                if summary.omittedJudgmentCount > 0 {
                    Text("多因素完整历史过关率暂不可核验：缺少两年赛前资金/走势快照。此处为关闭\(summary.omittedJudgmentCount)项新增判断后的赔率基线。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
            } else if hasDoubleRestriction, let summary, summary.input == configurationKey {
                Text(isSingleAny ? "一场自动双选：暂无参考样本" : isSingleAD ? "一场A/D双选：暂无参考样本" : "两个双选一起过关率：请开启两处双选条件").font(.caption)
            }
            if !hasDoubleRestriction {
                Text("六场初始全选310，未启用双选限制；只统计其余当前条件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(showsMaximum105Reference ? "六场硬条件参考（105优选前）" : ((summary?.omittedJudgmentCount ?? 0) > 0 ? "六场总过关率（赔率基线）" : "六场总过关率")).font(.subheadline.bold())
                Spacer(minLength: 4)
                if let summary, summary.input == configurationKey {
                    Text(percent(summary.combined.rate)).font(.headline).monospacedDigit()
                }
            }
            if let summary, summary.input == configurationKey {
                Text("六场全中\(summary.combined.hits)／\(summary.combined.groups)组 · \(summary.enabledRuleCount)项已开硬条件共同通过")
                    .font(.caption).monospacedDigit()
                Text("2–7、8–13、14–19……每6场一组")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach([2025, 2026], id: \.self) { year in
                        if let count = summary.years[year] {
                            Text("\(String(year))：\(percent(count.rate))（\(count.hits)/\(count.groups)）")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.font(.caption2).monospacedDigit()
                Text("每组6场全部命中才计为通过。历史回放，不代表未来；不含第7场、容错补回及行数优选。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("正在统计当前已开启条件…").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("currentConditionPassRate")
        .task(id: configurationKey + "|active=\(scenePhase == .active)") {
            guard let input, scenePhase == .active else { return }
            error = nil
            let work = Task.detached(priority: .userInitiated) {
                // Debounce range typing; a superseded snapshot never reaches UI.
                try await Task.sleep(nanoseconds: 150_000_000)
                let key = try ConditionEffectAnalysis.template(input).normalizedInput
                if let cached = await ConditionPassRateCache.shared.summary(for: key) { return cached }
                guard let url = Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json") else {
                    throw ConditionEffectAnalysis.AnalysisError.missingData
                }
                let dataset = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
                let result = try await ConditionEffectAnalysis.passRate(input: input, dataset: dataset)
                try Task.checkCancellation()
                await ConditionPassRateCache.shared.store(result)
                return result
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                summary = result
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
}

struct ConditionEffectAnalysisPage: View {
    let input: String
    let existingEditorIDs: Set<String>
    let onAdd: (Set<String>, ConditionEffectSuggestion?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<String>()
    @State private var previewRules: [ConditionEffectRule] = []
    @State private var year = 2026
    @State private var report: ConditionEffectReport?
    @State private var progress = 0
    @State private var total = 0
    @State private var error: String?
    @State private var attempt = 0
    @State private var requestedSuggestion = false
    @State private var suggestion: ConditionEffectSuggestion?
    @State private var suggestionSelected = false
    @State private var seenSuggestionIDs = Set<String>()
    @State private var suggestionMessage: String?

    private var selectionCount: Int { selectedIDs.count + (suggestionSelected && suggestion != nil ? 1 : 0) }

    var body: some View {
        List {
            Section("SVIP10 · 单项条件分析") {
                Text("按打开本页时的条件范围计算；返回修改条件后重新进入即可更新。")
                Picker("年份", selection: $year) { Text("2025").tag(2025); Text("2026").tag(2026) }
                    .pickerStyle(.segmented)
                if let report { Text("现有有效期次：\(report.issueRanges[year] ?? "")") }
            }
            suggestionSection
            if let report {
                Section("建议优先比较") {
                    if report.recommendedRules.isEmpty { Text("现有样本未显示两年一致的筛选效率优势，暂不推荐新增条件。") }
                    ForEach(report.recommendedRules) { rule in
                        HStack {
                            selectionButton(rule)
                            Label(rule.title + (rule.enabled ? "（已开启）" : "（当前关闭）"), systemImage: "chart.bar.xaxis")
                        }
                    }
                    Text("按两年中较低的筛选效率排序：效率＝过滤比例－误杀比例。正值表示删去组合的比例高于删去真实赛果的比例；只是历史对照建议，不自动更改开关，也不代表最佳条件组合。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("每个条件单独计算") {
                    ForEach(report.rules) { rule in
                        if let count = report.counts[year]?[rule.id] {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    selectionButton(rule)
                                    Text(rule.title).fontWeight(.semibold)
                                    Spacer()
                                    Text(rule.enabled ? "已开" : "关闭·模拟").font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Label("命中 \(percent(count.hitRate))", systemImage: "checkmark.circle")
                                    Spacer()
                                    Text("过滤 \(percent(count.filteredRate))")
                                }.monospacedDigit()
                                Text("通过\(count.hits)／\(count.groups)组 · 误杀\(count.groups - count.hits)组")
                                Text("累计保留\(count.retainedBets)注 · 平均\(String(format: "%.2f", Double(count.retainedBets) / Double(max(1, count.groups))))注／组")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                Section("统计口径与限制") { ForEach(report.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } }
            } else if let error {
                Section { Text(error); Button("重新计算") { attempt += 1 } }
            } else {
                Section {
                    ProgressView(total == 0 ? "正在读取历史数据…" : "已统计\(progress)／\(total)组", value: Double(progress), total: Double(max(1, total)))
                    Text("在后台逐项计算，离开本页会取消。首次统计可能需要一些时间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if report == nil && error == nil && !previewRules.isEmpty {
                Section("可勾选条件 · 统计完成后显示效果") {
                    ForEach(previewRules) { rule in
                        HStack {
                            selectionButton(rule)
                            Text(rule.title)
                            Spacer()
                            Text(rule.enabled ? "已开" : "关闭").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd(selectedIDs, suggestionSelected ? suggestion : nil)
                dismiss()
            } label: {
                Text("添加到条件列表（\(selectionCount)项）")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectionCount == 0)
            .accessibilityIdentifier("addSelectedAnalyzedConditions")
            .padding(.horizontal).padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .navigationTitle("条件效果分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: attempt) {
            report = nil; error = nil; progress = 0; total = 0
            let snapshot = input
            if let config = try? ConditionEffectAnalysis.template(snapshot) {
                previewRules = ConditionEffectAnalysis.rules(for: config)
            }
            let work = Task.detached(priority: .userInitiated) {
                let key = try ConditionEffectAnalysis.template(snapshot).normalizedInput
                if let cached = await ConditionEffectReportCache.shared.report(for: key) { return cached }
                guard let url = Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json") else { throw ConditionEffectAnalysis.AnalysisError.missingData }
                let data = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
                let report = try await ConditionEffectAnalysis.analyze(input: snapshot, dataset: data) { done, count in
                    await MainActor.run { progress = done; total = count }
                }
                try Task.checkCancellation()
                await ConditionEffectReportCache.shared.store(report, for: key)
                return report
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                report = result
                if requestedSuggestion { produceSuggestion(from: result) }
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription; requestedSuggestion = false }
        }
    }

    private var suggestionSection: some View {
        Section("计算一个可增加的条件") {
            Button {
                suggestionMessage = nil
                if let report { produceSuggestion(from: report) }
                else { requestedSuggestion = true }
            } label: {
                Label(suggestion == nil ? "计算新增条件" : "再计算一个条件", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(requestedSuggestion || error != nil)
            .accessibilityIdentifier("calculateAdditionalCondition")
            if requestedSuggestion {
                ProgressView(total == 0 ? "正在准备两年回放…" : "正在搜索条件 \(progress)／\(total)组")
            }
            if let suggestion {
                HStack {
                    Button {
                        suggestionSelected.toggle()
                        if suggestionSelected && suggestion.condition == .draws { selectedIDs.remove("extra.1") }
                    } label: {
                        Image(systemName: suggestionSelected ? "checkmark.square.fill" : "square")
                            .font(.title3).frame(width: 32, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("勾选新增条件\(suggestion.title)")
                    .accessibilityValue(suggestionSelected ? "已勾选" : "未勾选")
                    .accessibilityIdentifier("selectGeneratedCondition")
                    Text(suggestion.title).fontWeight(.semibold)
                }
                ForEach([2025, 2026], id: \.self) { candidateYear in
                    if let c = suggestion.years[candidateYear] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(String(candidateYear))年 · 单项命中 \(percent(c.standalone.hitRate)) · 过滤 \(percent(c.standalone.filteredRate))")
                                .font(.subheadline).monospacedDigit()
                            Text("单项通过\(c.standalone.hits)／\(c.standalone.groups)组；当前条件再过滤\(percent(c.additionalFilteredRate))，新增误杀\(c.base.hits - c.combined.hits)组。")
                            Text("相交通过\(c.base.hits)→\(c.combined.hits)／\(c.base.groups)组；保留\(c.base.retainedBets)→\(c.combined.retainedBets)注。")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("已勾选时，点击底部按钮即可加入条件列表，随后可单独开关。再次计算会替换本次候选。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let suggestionMessage { Text(suggestionMessage).font(.caption) }
            Text("搜索六场彩果数量、连续段、种类、和值与回返范围。两年均需单项命中≥90%、单项过滤≥5%、新增过滤≥2%，并保留当前命中组的≥95%；按两年较低的新增筛选效率择优。")
                .font(.caption).foregroundStyle(.secondary)
            Text("新增效果按本页已开启条件严格相交计算，不含容错、补回和行数优选；不是整单命中率。使用两年历史搜索，不是独立验证，不保证未来。第7场不计，TXT行数未计算。没有达标项会如实提示。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func produceSuggestion(from report: ConditionEffectReport) {
        requestedSuggestion = false
        let selectedOutcomeIDs = Set(selectedIDs.compactMap { id -> String? in
            if id.hasPrefix("outcome.") { return "OC_" + id.dropFirst(8) }
            return id == "extra.1" ? "OC_DRAWS" : nil
        })
        let excluded = existingEditorIDs.union(seenSuggestionIDs).union(selectedOutcomeIDs)
        if let next = report.nextSuggestion(excluding: excluded) {
            suggestion = next; suggestionSelected = true
            seenSuggestionIDs.insert(next.editorID)
        } else {
            suggestionMessage = suggestion == nil
                ? "没有找到两年都达标、且能在当前条件上继续过滤的新增项。可以调整现有条件后重新计算。"
                : "其余可增加的条件未达到标准，保留上一项供选择。添加后可返回本页，按新条件重新计算。"
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }

    private func selectionButton(_ rule: ConditionEffectRule) -> some View {
        Button {
            if selectedIDs.contains(rule.id) { selectedIDs.remove(rule.id) }
            else {
                selectedIDs.insert(rule.id)
                if rule.id == "extra.1" && suggestion?.condition == .draws { suggestionSelected = false }
            }
        } label: {
            Image(systemName: selectedIDs.contains(rule.id) ? "checkmark.square.fill" : "square")
                .font(.title3).frame(width: 32, height: 36)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("勾选\(rule.title)")
        .accessibilityValue(selectedIDs.contains(rule.id) ? "已勾选" : "未勾选")
        .accessibilityIdentifier("selectCondition_" + rule.id)
    }
}


struct DoubleForwardValidationPanel: View {
    let calibrated: Bool
    let factors: Set<DoubleJudgmentFactor>
    let revision: Int
    var compact = false
    var modelVersion = DoubleForwardForecast.modelVersion
    @State private var summary: DoubleForwardSummary?
    @State private var refreshing = false
    @State private var message: String?
    private var cohort: String {
        DoubleForwardForecast.cohort(calibrated: calibrated, factors: DoubleJudgmentFactor.text(factors), version: modelVersion)
    }
    private func rate(_ hits: Int, _ count: Int) -> String {
        count > 0 ? String(format: "%.2f%%（%d/%d）", Double(hits)*100/Double(count), hits, count) : "暂无已完赛样本"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("走势方案目标≥75% · 尚未验证").font(.headline)
            if let summary {
                LabeledContent("所选双选全部过关", value: rate(summary.selectedHits, summary.settled))
                LabeledContent("同组纯赔率方案", value: rate(summary.baselineHits, summary.settled))
                Text("当前设置已登记\(summary.registered)组，已核对\(summary.settled)组，待完赛或待核对\(summary.pending)组。")
                    .font(.caption)
                if let interval = summary.confidenceInterval {
                    Text(String(format: "独立样本假设下95%%参考区间：%.1f%%–%.1f%%；多因素独中过关%d组，纯赔率独中过关%d组。",
                        interval.lowerBound*100, interval.upperBound*100, summary.improved, summary.worsened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if summary.hasOverlappingFixtures {
                    Text("已完赛组有重叠场次，不按独立样本计算区间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !compact && !summary.rows.isEmpty {
                    DisclosureGroup("最近登记与核对记录") {
                        ForEach(Array(summary.rows.prefix(12))) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第\(row.forecast.issue)期 · " + row.forecast.fixtures.map { String($0.number) }.joined(separator: ",") + "场")
                                    .font(.subheadline.bold())
                                Text(row.forecast.selected.map { "\($0.number)场选\($0.mappedPair.map(String.init).joined())" }.joined(separator: "；"))
                                Text("多因素：\(outcome(row.selectedHit)) · 纯赔率：\(outcome(row.baselineHit))")
                                Text("赛前登记：" + row.forecast.recordedAt.formatted(date: .abbreviated, time: .standard))
                                    .foregroundStyle(.secondary)
                            }.font(.caption).padding(.vertical, 4)
                        }
                    }
                }
            }
            if !compact {
                Button(refreshing ? "正在核对完赛结果…" : "刷新实测过关率") {
                    Task { await refresh(settle: true) }
                }.disabled(refreshing)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if !compact {
            Text("走势范围为初盘至首场赛前2小时；若源时间是提前停售时间，按其提前2小时保守截止。只统计本机在窗口内登记的所选6场，每组取锁定点前最后一次已显示推荐。错过窗口仍给参考双选，不补录为实测。对照使用相同赔率和校正设置，关闭新增因素；不含其他过滤条件。")
                .font(.caption).foregroundStyle(.secondary)
            Text("按选场方案、当前因素开关与校正设置分别统计；切换设置不会保留同一组的旧推荐重复计数。小样本及重叠场次不代表长期独立命中率。")
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("初盘至首场赛前2小时 · 下方为旧赔率历史基线")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: cohort) { await refresh(settle: true) }
        .onChange(of: revision) { _ in Task { await refresh(settle: false) } }
    }
    private func outcome(_ hit: Bool?) -> String {
        hit.map { $0 ? "所选双选均中" : "未全部命中" } ?? "待核对"
    }
    @MainActor private func refresh(settle: Bool) async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        let requestedCohort = cohort
        do {
            summary = try await DoubleForwardValidationStore.shared.summary(cohort: requestedCohort)
            if settle {
                let issues = try await DoubleForwardValidationStore.shared.issuesDue()
                var failed = 0
                for issue in issues {
                    try Task.checkCancellation()
                    do {
                        let matches = try await FiveHundredBeijingSingleClient.fetchIssueScoreboard(issue: issue, requiringExplicitStatus: true)
                        try Task.checkCancellation()
                        try await DoubleForwardValidationStore.shared.reconcile(matches: matches)
                    } catch is CancellationError { throw CancellationError() }
                    catch { failed += 1 }
                }
                message = failed > 0 ? "有\(failed)期结果暂未取得，继续列为待核对，不按未中处理。" : nil
            }
            guard requestedCohort == cohort else { return }
            summary = try await DoubleForwardValidationStore.shared.summary(cohort: requestedCohort)
        } catch is CancellationError { return }
        catch { message = "实测记录读取失败：\(error.localizedDescription)；未改动已有记录。" }
    }
}

struct DoubleMarketTrendsPanel: View {
    let numbers: [Int]
    let evidence: [DoubleMarketEvidence]
    let notes: [Int: String]
    var body: some View {
        ForEach(Array(numbers.prefix(6)), id: \.self) { number in
            let value = evidence.first { $0.number == number && $0.isValid }
            DisclosureGroup {
                DoubleMarketTrendView(evidence: value, note: notes[number])
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("第\(number)场 · 欧赔与亚盘走势")
                    Text(availability(value)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Text("每场均采集，包括四场全选。行情图展示最近采样；已生成TXT继续使用生成时的快照。")
            .font(.caption).foregroundStyle(.secondary)
    }
    private func availability(_ evidence: DoubleMarketEvidence?) -> String {
        guard let evidence else { return "欧赔：暂无赛前记录 · 亚盘：暂无赛前记录" }
        return "欧赔：\(evidence.books.isEmpty ? "缺失" : "已采集") · 亚盘：\(evidence.books.contains { $0.currentAsian != nil } ? "已采集" : "缺失") · \(evidence.observations?.count ?? 1)次采样"
    }
}

private struct DoubleMarketTrendView: View {
    let evidence: DoubleMarketEvidence?
    let note: String?
    @State private var selectedCompany = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let evidence, let first = evidence.books.first {
                let company = evidence.books.contains { $0.companyID == selectedCompany } ? selectedCompany : first.companyID
                if evidence.books.count > 1 {
                    Picker("行情来源机构", selection: Binding(get: { company }, set: { selectedCompany = $0 })) {
                        ForEach(evidence.books, id: \.companyID) { book in
                            Text("机构\(book.companyID)").tag(book.companyID)
                        }
                    }.pickerStyle(.segmented)
                }
                Text("来源：\(evidence.source) · 机构\(company)").font(.caption).foregroundStyle(.secondary)
                Text("最后采样：" + evidence.capturedAt.formatted(date: .numeric, time: .standard))
                    .font(.caption).monospacedDigit()
                if let data = DoubleMarketTrendData(evidence: evidence, companyID: company) {
                    Text("普通欧赔走势 · 主胜／平局／客胜").font(.subheadline.bold())
                    Text("初盘 " + odds(data.openingEuropean) + " → 当前 " + odds(data.currentEuropean))
                        .font(.caption).monospacedDigit()
                    DoubleMarketTrendChart(points: data.european)
                    Text("亚盘让球走势 · 负数为主让，正数为主受让").font(.subheadline.bold())
                    if let opening = data.openingAsian, let current = data.currentAsian {
                        Text(String(format: "初盘 %+.2f → 当前 %+.2f", opening.line, current.line))
                            .font(.caption).monospacedDigit()
                    }
                    if data.asianLine.isEmpty { Text("该机构未取得可核验亚盘，暂无走势。").font(.caption) }
                    else { DoubleMarketTrendChart(points: data.asianLine) }
                    Text("亚盘主客水位走势").font(.subheadline.bold())
                    if let opening = data.openingAsian, let current = data.currentAsian {
                        Text(String(format: "主水 %.3f→%.3f · 客水 %.3f→%.3f", opening.homeWater, current.homeWater, opening.awayWater, current.awayWater))
                            .font(.caption).monospacedDigit()
                    }
                    if data.asianWater.isEmpty { Text("水位数据缺失，暂无走势。").font(.caption) }
                    else { DoubleMarketTrendChart(points: data.asianWater) }
                    Text("初盘发布时间未公开，图中只画本机实际采样时间；连线仅连接采样点。升降盘前后的水位不可直接比较强弱。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("欧赔走势：暂无可核验赛前数据").font(.subheadline.bold())
                Text("亚盘走势：暂无可核验赛前数据").font(.subheadline.bold())
                Text("未开赛时点击刷新开始记录；首场已开赛且此前未采集时，无法补造赛前走势。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func odds(_ values: [Double]) -> String { values.map { String(format: "%.2f", $0) }.joined(separator: "／") }
}

private struct DoubleMarketTrendChart: View {
    let points: [DoubleMarketTrendPoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("本机采样时间", point.capturedAt), y: .value("数值", point.value))
                .foregroundStyle(by: .value("方向", point.direction))
                .interpolationMethod(.linear)
            PointMark(x: .value("本机采样时间", point.capturedAt), y: .value("数值", point.value))
                .foregroundStyle(by: .value("方向", point.direction))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartLegend(position: .bottom)
        .frame(height: 145)
        .accessibilityLabel("赛前行情采样走势")
        if Set(points.map(\.capturedAt)).count < 2 {
            Text("当前仅1次真实采样，暂不构成连续走势；下一次采样后连线。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct DoubleJudgmentEvidencePanel: View {
    let selection: AutomaticDoubleSelection?
    let factors: Set<DoubleJudgmentFactor>
    let calibrated: Bool
    let notes: [Int: String]
    var body: some View {
        DisclosureGroup("所选六场 · \(selection?.choices.count ?? 1)处双选 · \(factors.count)项判断") {
            Text("新增判断使用人工设定且有上限的试验权重，尚未证实提高命中率；资金未公开时不计，心理仅用可观察的拥挤/背离指标表示。")
                .font(.caption).foregroundStyle(.secondary)
            if let selection {
                Text("所选双选赔率基础估算：\(String(format: "%.2f%%", selection.estimatedJointCoverage * 100))（不是多因素实测命中率）")
                    .font(.caption).monospacedDigit()
                ForEach(selection.matches, id: \.number) { match in
                    DisclosureGroup {
                        Text(notes[match.number] ?? "未取得额外赛前市场数据")
                            .font(.caption).foregroundStyle(.secondary)
                        if let evidence = match.evidence {
                            Text("本机赛前采样：" + evidence.capturedAt.formatted(date: .numeric, time: .standard)
                                 + " · \(evidence.observations?.count ?? 1)次")
                                .font(.caption).monospacedDigit()
                            if let observations = evidence.observations, !observations.isEmpty {
                                DisclosureGroup("查看欧赔／亚盘连续采样") {
                                    ForEach(Array(observations.enumerated()), id: \.offset) { _, point in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(point.capturedAt.formatted(date: .omitted, time: .standard)).font(.caption.bold())
                                            ForEach(point.books, id: \.companyID) { quote in
                                                Text("机构\(quote.companyID) 欧赔 " + quote.european.map { String(format: "%.2f", $0) }.joined(separator: "/"))
                                                    .font(.caption2).monospacedDigit()
                                                if let asian = quote.asian {
                                                    Text(String(format: "亚盘 %+.2f · 主水 %.3f · 客水 %.3f", asian.line, asian.homeWater, asian.awayWater))
                                                        .font(.caption2).monospacedDigit()
                                                }
                                            }
                                        }
                                    }
                                    Text("时间为本机抓取时间，非机构发布或完整市场逐笔历史。")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("实际投注金额：\(match.evidence?.bettingAmounts == nil ? "未公开" : "已采集")")
                            .font(.caption)
                        ForEach(DoubleJudgmentScorer.assessments(match, calibrated: calibrated, factors: factors)) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.factor.title + (row.available ? " · 已计入参考" : " · 未计入"))
                                    .font(.caption.bold())
                                Text(row.note).font(.caption2).foregroundStyle(.secondary)
                                if row.available {
                                    Text("辅助分（非概率）：" + zip(["3", "1", "0"], row.adjustment).map {
                                        "\($0.0) " + String(format: "%+.2f", $0.1 * 100)
                                    }.joined(separator: " · ")).font(.caption2).monospacedDigit()
                                }
                            }
                        }
                    } label: {
                        if let choice = selection.choices.first(where: { $0.number == match.number }) {
                            Text("第\(match.number)场：双选\(choice.mappedPair.map(String.init).joined()) · 彩果\(choice.retainedOutcomes.map(String.init).joined(separator: "/"))")
                        } else { Text("第\(match.number)场：全选") }
                    }
                }
            } else { Text("自动选择完成后，展开查看六场逐项依据及缺失数据。").font(.caption) }
        }
    }
}
