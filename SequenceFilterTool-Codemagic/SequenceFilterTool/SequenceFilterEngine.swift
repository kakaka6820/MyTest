import Foundation

struct SequenceRecord: Hashable, Sendable {
    let outcomes: [Int]
    let values: [Int]
    let sum: Int
    let displacement: Int
    let variance: Double
    let transitionProbability: Double
    var realOddsSum: Double? = nil

    var compactOutcomes: String { outcomes.map(String.init).joined() }
    var compactValues: String { values.map(String.init).joined() }
}

struct PreviousResultContext: Equatable, Sendable {
    let logic: [LogicMapping]
    let outcomes: [Int]
    let hitFlag: Int

    var displayText: String {
        "\(logic.map(\.displayName).joined()) / \(outcomes.map(String.init).joined())"
    }
}

/// VIP3的六场通用输入。赔率行必须来自项目的
/// “普通欧赔＋实际让球＋对照表”链路，不允许传入开奖SP。
struct VIP3MatchContext: Equatable, Sendable {
    let comparisonTableOdds: [[Double]]
    let handicaps: [Int]
    let leagues: [String]
    let logic: [LogicMapping]
}

struct RecommendedFilterConditions: Equatable, Sendable {
    let sumRange: ClosedRange<Int>
    let displacementRange: ClosedRange<Int>
    let varianceMaximum: Double
    let valueTwoMaximum: Int
    let transitionMinimumPercent: Double
}

struct ConsecutiveRunPresetAssessment: Equatable, Sendable, Identifiable {
    let minimum: Int
    let tolerance: ClosedRange<Int>
    let currentEstimatedCoverage: Double
    let historicalSPCoverage: Double
    let combinedCoverage: Double
    let theoreticalKeptCount: Int

    var id: Int { minimum }
    var rangeText: String { "\(minimum)–7" }
    var toleranceText: String { "\(tolerance.lowerBound)–\(tolerance.upperBound)" }
    var theoreticalFilteredCount: Int { 729 - theoreticalKeptCount }
}

struct ConsecutiveRunRangeRecommendation: Equatable, Sendable {
    let recommendedMinimum: Int
    let source: String
    let marketEntropy: Double?
    let historicalSampleCount: Int
    let assessments: [ConsecutiveRunPresetAssessment]

    var recommendedAssessment: ConsecutiveRunPresetAssessment? {
        assessments.first { $0.minimum == recommendedMinimum }
    }
}

/// 用当前SP的隐含概率估计3/4/5三档的覆盖率，再用历史SP的
/// 市场不确定度分层校准。只使用汇总统计，不保存或匹配期号、场次号。
enum ConsecutiveRunRangeAdvisor {
    private struct Preset {
        let minimum: Int
        let tolerance: ClosedRange<Int>
        let theoreticalKeptCount: Int
    }

    private struct HistoricalSPBand {
        let range: Range<Double>
        let sampleCount: Int
        /// 顺序为3–7＋0–1、4–7＋0–2、5–7＋2–3。
        let passCounts: [Int]
    }

    private static let presets = [
        Preset(minimum: 3, tolerance: 0...1, theoreticalKeptCount: 585),
        Preset(minimum: 4, tolerance: 0...2, theoreticalKeptCount: 649),
        Preset(minimum: 5, tolerance: 2...3, theoreticalKeptCount: 688)
    ]

    /// 33条去重历史单的赛前页面完整欧赔/SP熵分层（低/中/高不确定度）。
    /// 各层只留样本数与三档通过数，避免对某一期或某一场特判。
    private static let historicalSPBands = [
        HistoricalSPBand(range: 0..<0.8, sampleCount: 6, passCounts: [5, 6, 5]),
        HistoricalSPBand(range: 0.8..<0.9, sampleCount: 9, passCounts: [6, 6, 9]),
        HistoricalSPBand(range: 0.9..<Double.greatestFiniteMagnitude, sampleCount: 18, passCounts: [16, 14, 18])
    ]
    private static let overallHistoricalPassCounts = [27, 26, 32]
    private static let overallHistoricalSampleCount = 33

    static func recommend(
        spRows: [[Double]]?,
        logic: [LogicMapping],
        seventhOutcome: Int
    ) -> ConsecutiveRunRangeRecommendation? {
        guard [3, 1, 0].contains(seventhOutcome), logic.count == 5 else { return nil }

        let validSPRows = spRows.flatMap { rows -> [[Double]]? in
            guard rows.count == 5,
                  rows.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else {
                return nil
            }
            return rows
        }
        let currentProbabilities: [[Double]]
        let entropy: Double?
        let historicalCounts: [Int]
        let historicalSampleCount: Int
        let source: String
        let currentWeight: Double

        if let validSPRows {
            currentProbabilities = validSPRows.map(normalizedImpliedProbabilities)
            let value = validSPRows.map(normalizedEntropy).reduce(0, +) / Double(validSPRows.count)
            entropy = value
            let band = historicalSPBands.first { $0.range.contains(value) }
            historicalCounts = band?.passCounts ?? overallHistoricalPassCounts
            historicalSampleCount = band?.sampleCount ?? overallHistoricalSampleCount
            source = "当前实时SP＋历史SP分层"
            currentWeight = 0.70
        } else {
            currentProbabilities = logic.map { mapping in
                mapping.values.map { value in
                    switch value {
                    case 2: return 0.52
                    case 3: return 0.30
                    default: return 0.18
                    }
                }
            }
            entropy = nil
            historicalCounts = overallHistoricalPassCounts
            historicalSampleCount = overallHistoricalSampleCount
            source = "ABCD排序＋历史总样本（SP不完整）"
            currentWeight = 0.55
        }

        let assessments = presets.enumerated().map { index, preset in
            let currentCoverage = estimatedCoverage(
                probabilities: currentProbabilities,
                seventhOutcome: seventhOutcome,
                preset: preset
            )
            let historicalCoverage = Double(historicalCounts[index]) / Double(historicalSampleCount)
            return ConsecutiveRunPresetAssessment(
                minimum: preset.minimum,
                tolerance: preset.tolerance,
                currentEstimatedCoverage: currentCoverage,
                historicalSPCoverage: historicalCoverage,
                combinedCoverage: currentCoverage * currentWeight + historicalCoverage * (1 - currentWeight),
                theoreticalKeptCount: preset.theoreticalKeptCount
            )
        }

        // 按压缩强度3 > 4 > 5递减选择：优先用综合覆盖估计不低于80%的最强档。
        let recommended = assessments.first { $0.combinedCoverage >= 0.80 }
            ?? assessments.max { $0.combinedCoverage < $1.combinedCoverage }
        guard let recommended else { return nil }
        return ConsecutiveRunRangeRecommendation(
            recommendedMinimum: recommended.minimum,
            source: source,
            marketEntropy: entropy,
            historicalSampleCount: historicalSampleCount,
            assessments: assessments
        )
    }

    private static func normalizedImpliedProbabilities(_ odds: [Double]) -> [Double] {
        let inverses = odds.map { 1 / $0 }
        let total = inverses.reduce(0, +)
        return inverses.map { $0 / total }
    }

    private static func normalizedEntropy(_ odds: [Double]) -> Double {
        -normalizedImpliedProbabilities(odds)
            .reduce(0) { $0 + $1 * log($1) } / log(3)
    }

    private static func estimatedCoverage(
        probabilities: [[Double]],
        seventhOutcome: Int,
        preset: Preset
    ) -> Double {
        let outcomes = [3, 1, 0]
        let rows = probabilities + [[1.0 / 3, 1.0 / 3, 1.0 / 3]]
        var covered = 0.0
        for encoded in 0..<729 {
            var value = encoded
            var sequence: [Int] = []
            var probability = 1.0
            for row in rows {
                let index = value % 3
                value /= 3
                sequence.append(outcomes[index])
                probability *= row[index]
            }
            sequence.append(seventhOutcome)
            let failures = [
                ConsecutiveRunCondition.nonLoss,
                ConsecutiveRunCondition.nonDraw,
                ConsecutiveRunCondition.nonWin
            ].filter { $0.longestRun(in: sequence) < preset.minimum }.count
            if preset.tolerance.contains(failures) { covered += probability }
        }
        return covered
    }
}

struct ProductQFilterAssessment: Equatable, Sendable {
    let passes: Bool?
    let product: Int?
    /// 按Q从低到高排列的5场主彩果名次，从1开始。
    let mainOutcomeRank: Int?
    let mainOutcomeCount: Int
    /// 该5场主彩果展开后，被Q阶段删除的具体注数。
    let removedExpandedBetCount: Int
    let expansionFactor: Int
}

enum ComprehensiveAnalysisMetric: String, Codable, CaseIterable, Sendable {
    case winCount, drawCount, lossCount, diversity, outcomeSum, returns, winLossSwitches
    case nonLoss, nonDraw, nonWin, winRun, drawRun, lossRun
    case productQ, sum, displacement, variance, valueTwoCount, valueFourCount
    case transitionPercent, roughness, breakpoints, spSum, spProduct, estimatedPrize
    case maximumSingleSP, highSPCount, minimumProbabilityPercent, jointProbabilityPercent
    case frontOutcomeSum, backOutcomeSum, frontSPProduct, backSPProduct

    var title: String {
        switch self {
        case .winCount: return "胜总数"
        case .drawCount: return "平总数"
        case .lossCount: return "负总数"
        case .diversity: return "彩果种类"
        case .outcomeSum: return "彩果和值"
        case .returns: return "隔场回返"
        case .winLossSwitches: return "胜负切换"
        case .nonLoss: return "连续不败"
        case .nonDraw: return "连续不平"
        case .nonWin: return "连续不胜"
        case .winRun: return "连续胜"
        case .drawRun: return "连续平"
        case .lossRun: return "连续负"
        case .productQ: return "乘积Q"
        case .sum: return "判定总和S"
        case .displacement: return "位移M"
        case .variance: return "稳定性σ²"
        case .valueTwoCount: return "判定值2次数"
        case .valueFourCount: return "判定值4次数"
        case .transitionPercent: return "P_tr%"
        case .roughness: return "二阶波动R"
        case .breakpoints: return "彩果断点B"
        case .spSum: return "SP和值"
        case .spProduct: return "SP乘积"
        case .estimatedPrize: return "预计奖金"
        case .maximumSingleSP: return "最大单场SP"
        case .highSPCount: return "SP>4场次"
        case .minimumProbabilityPercent: return "最低单场概率%"
        case .jointProbabilityPercent: return "整串全中概率%"
        case .frontOutcomeSum: return "前3场和值"
        case .backOutcomeSum: return "后2场和值"
        case .frontSPProduct: return "前3场SP乘积"
        case .backSPProduct: return "后2场SP乘积"
        }
    }

    var needsSP: Bool {
        [.spSum, .spProduct, .estimatedPrize, .maximumSingleSP, .highSPCount,
         .frontSPProduct, .backSPProduct].contains(self)
    }

    var needsProbability: Bool {
        [.minimumProbabilityPercent, .jointProbabilityPercent].contains(self)
    }
}

struct ComprehensiveAnalysisRule: Codable, Equatable, Sendable, Identifiable {
    let metric: ComprehensiveAnalysisMetric
    let lowerBound: Double
    let upperBound: Double
    let sampleCount: Int
    let score: Double

    var id: ComprehensiveAnalysisMetric { metric }
    func contains(_ value: Double) -> Bool {
        value + 1e-10 >= lowerBound && value <= upperBound + 1e-10
    }
}

struct ComprehensiveAnalysisProfile: Codable, Equatable, Sendable {
    let generatedAt: Date
    let historyRecordCount: Int
    let runSampleCount: Int
    let advancedSampleCount: Int
    let rules: [ComprehensiveAnalysisRule]
    let recommendedMetric: ComprehensiveAnalysisMetric
    /// 仅为解码旧版档案保留；通用大压缩不读取这些指纹字段。
    let protectedExactSignatures: [String]?
    /// 仅为解码旧版档案保留；不参与任何生成或命中判定。
    let protectedAllowedPairSignatures: [String]?
    /// 仅为解码旧版档案保留；不用于排名或截断。
    let protectedOutcomePositionCounts: [[Int]]?

    init(
        generatedAt: Date,
        historyRecordCount: Int,
        runSampleCount: Int,
        advancedSampleCount: Int,
        rules: [ComprehensiveAnalysisRule],
        recommendedMetric: ComprehensiveAnalysisMetric,
        protectedExactSignatures: [String]? = nil,
        protectedAllowedPairSignatures: [String]? = nil,
        protectedOutcomePositionCounts: [[Int]]? = nil
    ) {
        self.generatedAt = generatedAt
        self.historyRecordCount = historyRecordCount
        self.runSampleCount = runSampleCount
        self.advancedSampleCount = advancedSampleCount
        self.rules = rules
        self.recommendedMetric = recommendedMetric
        self.protectedExactSignatures = protectedExactSignatures
        self.protectedAllowedPairSignatures = protectedAllowedPairSignatures
        self.protectedOutcomePositionCounts = protectedOutcomePositionCounts
    }

    var recommendedRule: ComprehensiveAnalysisRule? {
        rules.first { $0.metric == recommendedMetric }
    }
    var requiresSPData: Bool { rules.contains { $0.metric.needsSP } }
    var requiresProbabilityData: Bool { rules.contains { $0.metric.needsProbability } }
}

/// 电脑端用32条去重历史样本离线标定的通用统计模型。
/// 特征只包含前6场的位置彩果频率，以及前5场ABCD判定值的初始/转移频率。
/// 它不保存期号、场次号、具体赛果或单据白名单。
private enum Universal150CompressionModel {
    static let version = "POS6-MARKOV5-A025-T12153545"
    static let sampleCount = 32
    static let smoothing = 0.25
    static let threshold = -12.153545257932464

    /// 列顺序固定为胜3、平1、负0。
    static let outcomePositionCounts = [
        [13, 9, 10], [10, 11, 11], [11, 8, 13],
        [12, 8, 12], [14, 12, 6], [10, 10, 12]
    ]
    /// 列顺序固定为判定值2、3、4。
    static let initialValueCounts = [10, 12, 10]
    /// 行是转移前2/3/4，列是转移后2/3/4。
    static let valueTransitionCounts = [
        [17, 16, 17],
        [20, 3, 14],
        [12, 18, 11]
    ]

    static func score(fullOutcomes: [Int], config: FilterConfig) -> Double? {
        guard fullOutcomes.count >= 6, config.logic.count >= 5 else { return nil }
        let outcomeIndex = [3: 0, 1: 1, 0: 2]
        let valueIndex = [2: 0, 3: 1, 4: 2]
        var score = 0.0
        for position in 0..<6 {
            guard let index = outcomeIndex[fullOutcomes[position]] else { return nil }
            let numerator = Double(outcomePositionCounts[position][index]) + smoothing
            let denominator = Double(sampleCount) + smoothing * 3
            score += log(numerator / denominator)
        }

        let mainOutcomes = Array(fullOutcomes.prefix(5))
        let values = zip(config.logic.prefix(5), mainOutcomes).map { $0.value(for: $1) }
        guard values.count == 5,
              let firstIndex = valueIndex[values[0]] else { return nil }
        score += log(
            (Double(initialValueCounts[firstIndex]) + smoothing)
                / (Double(sampleCount) + smoothing * 3)
        )
        for (from, to) in zip(values, values.dropFirst()) {
            guard let fromIndex = valueIndex[from], let toIndex = valueIndex[to] else { return nil }
            let row = valueTransitionCounts[fromIndex]
            let denominator = Double(row.reduce(0, +)) + smoothing * 3
            score += log((Double(row[toIndex]) + smoothing) / denominator)
        }
        return score
    }
}

/// V1–V3使用34条去重历史赛果离线标定的7项结构评分。
/// 所有组合只按前6场结构指标打分，不读取期号、场次、ABCD或具体赛果集合。
private enum Universal247ToleranceModel {
    static let version = "STRUCT7-N34-A05-TM0050756"
    static let sampleCount = 34
    static let smoothing = 0.5
    static let threshold = -0.05075598685241389

    private static let diversity = [1: 1.078286, 2: 0.047057, 3: -0.029620]
    private static let returns = [0: 0.043211, 1: -0.228681, 2: 0.172446, 3: 0.316763, 4: 0.432836]
    private static let winLossSwitches = [
        0: -0.353625, 1: 0.155452, 2: 0.195960,
        3: -0.167873, 4: -0.382433, 5: 1.375425
    ]
    private static let nonLoss = [
        0: 1.873510, 1: 0.240119, 2: -0.682071, 3: 0.515387,
        4: -0.246753, 5: -0.278252, 6: -0.278252
    ]
    private static let nonWin = [
        0: 1.873510, 1: 0.407173, 2: -0.246753, 3: -0.036682,
        4: -0.246753, 5: 0.309535, 6: 0.058220
    ]
    private static let drawRun = [
        0: 0.309535, 1: -0.062051, 2: -0.077400, 3: -0.214230,
        4: -0.524385, 5: 1.873510, 6: 1.873510
    ]
    private static let lossRun = [
        0: -0.278252, 1: 0.177179, 2: -0.456890, 3: -0.214230,
        4: 0.574227, 5: 0.774898, 6: 1.873510
    ]

    static func score(fullOutcomes: [Int]) -> Double? {
        let firstSix = Array(fullOutcomes.prefix(6))
        guard firstSix.count == 6,
              let summary = PrizeCalculator.outcomeSummary(for: firstSix),
              let diversityScore = diversity[summary.diversity],
              let returnScore = returns[summary.returns],
              let switchScore = winLossSwitches[summary.winLossSwitches],
              let nonLossScore = nonLoss[summary.nonLoss],
              let nonWinScore = nonWin[summary.nonWin],
              let drawScore = drawRun[summary.draw],
              let lossScore = lossRun[summary.loss] else { return nil }
        return diversityScore + returnScore + switchScore + nonLossScore
            + nonWinScore + drawScore + lossScore
    }

}

/// V4通用统计模型：对203个历史单元先按六场结果去重为173个样本，
/// 仅学习8项结构分类的频率；六个位置边际分布只用1%权重打破同分。
/// 模型不保存、不查询任何具体六场赛果，也不读取期号、场次或ABCD。
/// 以整期留出方式选择平滑和位置权重，最终在729种中保留247种。
private enum Universal247GeneralV4Model {
    static let version = "STRUCT8POS-U173-A0075-L001-K247-V5"
    /// 由于旧配置格式只有阈值字段，用独立标记选择V4模型；实际通过线见threshold。
    static let configurationMarker = 9.247
    static let threshold = 0.323294650828368

    private static let diversity = [1: -2.276181067854, 2: -0.025816036982, 3: 0.013794187224]
    private static let returns = [
        0: 0.047824585689, 1: -0.043908247681, 2: 0.036257793840,
        3: -0.060096111145, 4: -2.957718030267
    ]
    private static let winLossSwitches = [
        0: -0.300922118057, 1: -0.003885938842, 2: 0.292311695416,
        3: 0.323044750616, 4: -1.135678060344, 5: -1.883826867026
    ]
    private static let nonLoss = [
        0: -1.226515870827, 1: -0.047258724258, 2: -0.007346147944,
        3: 0.168558007283, 4: -0.235008829956, 5: 0.113633089405,
        6: -0.232845116514
    ]
    private static let nonWin = [
        0: -1.226515870827, 1: 0.185536656256, 2: 0.087827863193,
        3: 0.029928109987, 4: -0.061224999996, 5: -0.153280306101,
        6: -0.518458935901
    ]
    private static let drawRun = [
        0: 0.370463430438, 1: 0.039900163996, 2: -0.099677557641,
        3: -0.453998445274, 4: -0.217888412667, 5: 0.103521871085,
        6: -1.226515870827
    ]
    private static let lossRun = [
        0: -0.232845116514, 1: 0.091154015060, 2: -0.197137463748,
        3: 0.117743444699, 4: 0.063677432767, 5: 0.761162363188,
        6: -1.226515870827
    ]
    private static let outcomeCounts = [
        "0-0-6": -1.233394817018, "0-1-5": 0.354972174464,
        "0-2-4": -1.211524071026, "0-3-3": 0.054044275102,
        "0-4-2": -0.160539831347, "0-5-1": -0.302668317640,
        "0-6-0": -1.233394817018, "1-0-5": 0.748315922039,
        "1-1-4": 0.335555855979, "1-2-3": 0.228128996430,
        "1-3-2": -0.577627902506, "1-4-1": -0.017933808324,
        "1-5-0": -0.302668317640, "2-0-4": 0.520337256621,
        "2-1-3": 0.110864498509, "2-2-2": 0.150421687221,
        "2-3-1": -0.095698761664, "2-4-0": -1.211524071026,
        "3-0-3": 0.054044275102, "3-1-2": 0.171214633842,
        "3-2-1": -0.261710455684, "3-3-0": -0.840321096143,
        "4-0-2": 0.340481792322, "4-1-1": -0.350174726925,
        "4-2-0": -0.160539831347, "5-0-1": 0.748315922039,
        "5-1-0": 0.354972174464, "6-0-0": -1.233394817018
    ]
    private static let positionWeights: [[Int: Double]] = [
        [0: -0.000116128464, 1: -0.001626292987, 3: 0.001498323575],
        [0: 0.000561235783, 1: -0.003165252988, 3: 0.001935870582],
        [0: 0.000396147428, 1: -0.000472831462, 3: 0.000057562398],
        [0: -0.000472831462, 1: -0.001226838981, 3: 0.001498323575],
        [0: -0.000116128464, 1: -0.000472831462, 3: 0.000561235783],
        [0: 0.000561235783, 1: -0.000656070670, 3: 0.000057562398]
    ]

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func score(fullOutcomes: [Int]) -> Double? {
        let firstSix = Array(fullOutcomes.prefix(6))
        guard firstSix.count == 6,
              let summary = PrizeCalculator.outcomeSummary(for: firstSix),
              let diversityScore = diversity[summary.diversity],
              let returnScore = returns[summary.returns],
              let switchScore = winLossSwitches[summary.winLossSwitches],
              let nonLossScore = nonLoss[summary.nonLoss],
              let nonWinScore = nonWin[summary.nonWin],
              let drawScore = drawRun[summary.draw],
              let lossScore = lossRun[summary.loss] else { return nil }
        let lossCount = firstSix.filter { $0 == 0 }.count
        let drawCount = firstSix.filter { $0 == 1 }.count
        let winCount = firstSix.filter { $0 == 3 }.count
        guard let countScore = outcomeCounts["\(lossCount)-\(drawCount)-\(winCount)"] else {
            return nil
        }
        let positionScore = zip(firstSix, positionWeights).reduce(0.0) { partial, pair in
            partial + (pair.1[pair.0] ?? 0)
        }
        return diversityScore + returnScore + switchScore + nonLossScore
            + nonWinScore + drawScore + lossScore + countScore + positionScore
    }
}

/// V5整期留出模型：把203个样本按完整期号分为6折，每折的整期数据
/// 只能出现在验证集中。模型只保存分类汇总计数，不保存或查询具体赛果、
/// 期号、场次、记录ID。同一评分公式应用于所有单据，统一保留得分最高的405种。
private enum Universal405WholeIssueModel {
    static let version = "WHOLE-ISSUE-LOO-N203-K405-A01-V1"
    static let configurationMarker = 9.405
    static let keptCount = 405
    static let sampleCount = 203
    static let smoothing = 0.1

    private struct OutcomeMetrics {
        let countKey: Int
        let diversity: Int
        let returns: Int
        let switches: Int
        let nonLoss: Int
        let nonWin: Int
        let nonDraw: Int
        let drawRun: Int
        let lossRun: Int
    }

    private struct ValueMetrics {
        let countKey: Int
        let displacement: Int
        let varianceNumerator: Int
        let roughness: Int
        let first: Int
        let twoRun: Int
        let threeRun: Int
        let fourRun: Int
    }

    private static let outcomeCountSamples = [
        15: 2, 24: 2, 33: 5, 42: 3, 51: 1,
        105: 5, 114: 13, 123: 22, 132: 9, 141: 9, 150: 1,
        204: 8, 213: 20, 222: 28, 231: 13, 240: 1,
        303: 6, 312: 20, 321: 12, 330: 2,
        402: 6, 411: 6, 420: 3, 501: 4, 510: 2
    ]
    private static let diversitySamples = [2: 51, 3: 152]
    private static let returnSamples = [0: 86, 1: 71, 2: 38, 3: 8]
    private static let switchSamples = [0: 45, 1: 75, 2: 59, 3: 23, 4: 1]
    private static let nonLossSamples = [1: 24, 2: 54, 3: 62, 4: 27, 5: 23, 6: 13]
    private static let nonWinSamples = [1: 32, 2: 64, 3: 53, 4: 30, 5: 15, 6: 9]
    private static let nonDrawSamples = [1: 15, 2: 47, 3: 60, 4: 33, 5: 19, 6: 29]
    private static let drawRunSamples = [0: 29, 1: 110, 2: 49, 3: 10, 4: 4, 5: 1]
    private static let lossRunSamples = [0: 13, 1: 120, 2: 44, 3: 20, 4: 4, 5: 2]

    private static let valueCountSamples = [
        5: 2, 14: 3, 23: 3, 32: 5, 41: 2,
        104: 3, 113: 7, 122: 22, 131: 17, 140: 2,
        203: 5, 212: 21, 221: 27, 230: 13,
        302: 4, 311: 30, 320: 9, 401: 16, 410: 10, 500: 2
    ]
    private static let displacementSamples = [0: 4, 1: 10, 2: 44, 3: 40, 4: 60, 5: 28, 6: 15, 7: 2]
    private static let varianceSamples = [0: 4, 20: 17, 30: 30, 50: 17, 70: 49, 80: 56, 100: 21, 120: 9]
    private static let roughnessSamples = [
        0: 4, 1: 10, 2: 27, 3: 27, 4: 35, 5: 25,
        6: 33, 7: 19, 8: 11, 9: 5, 10: 5, 11: 2
    ]
    private static let firstValueSamples = [2: 83, 3: 71, 4: 49]
    private static let twoRunSamples = [0: 15, 1: 97, 2: 48, 3: 29, 4: 12, 5: 2]
    private static let threeRunSamples = [0: 32, 1: 116, 2: 43, 3: 11, 4: 1]
    private static let fourRunSamples = [0: 36, 1: 130, 2: 24, 3: 9, 4: 2, 5: 2]
    private static let pooledValueSamples = [2: 426, 3: 314, 4: 275]
    private static let transitionSamples = [
        22: 155, 23: 93, 24: 89,
        32: 107, 33: 69, 34: 81,
        42: 81, 43: 81, 44: 56
    ]

    private static let allOutcomeSequences: [[Int]] = {
        var result = [[Int]]([[]])
        for _ in 0..<6 {
            result = result.flatMap { prefix in [3, 1, 0].map { prefix + [$0] } }
        }
        return result
    }()

    private static let allValueSequences: [[Int]] = {
        var result = [[Int]]([[]])
        for _ in 0..<5 {
            result = result.flatMap { prefix in [2, 3, 4].map { prefix + [$0] } }
        }
        return result
    }()

    private static func frequency(_ values: [Int]) -> [Int: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static let uniformOutcomeCount = frequency(allOutcomeSequences.map { outcomeMetrics($0).countKey })
    private static let uniformDiversity = frequency(allOutcomeSequences.map { outcomeMetrics($0).diversity })
    private static let uniformReturns = frequency(allOutcomeSequences.map { outcomeMetrics($0).returns })
    private static let uniformSwitches = frequency(allOutcomeSequences.map { outcomeMetrics($0).switches })
    private static let uniformNonLoss = frequency(allOutcomeSequences.map { outcomeMetrics($0).nonLoss })
    private static let uniformNonWin = frequency(allOutcomeSequences.map { outcomeMetrics($0).nonWin })
    private static let uniformNonDraw = frequency(allOutcomeSequences.map { outcomeMetrics($0).nonDraw })
    private static let uniformDrawRun = frequency(allOutcomeSequences.map { outcomeMetrics($0).drawRun })
    private static let uniformLossRun = frequency(allOutcomeSequences.map { outcomeMetrics($0).lossRun })
    private static let uniformValueCount = frequency(allValueSequences.map { valueMetrics($0).countKey })
    private static let uniformDisplacement = frequency(allValueSequences.map { valueMetrics($0).displacement })
    private static let uniformVariance = frequency(allValueSequences.map { valueMetrics($0).varianceNumerator })
    private static let uniformRoughness = frequency(allValueSequences.map { valueMetrics($0).roughness })
    private static let uniformFirstValue = frequency(allValueSequences.map { valueMetrics($0).first })
    private static let uniformTwoRun = frequency(allValueSequences.map { valueMetrics($0).twoRun })
    private static let uniformThreeRun = frequency(allValueSequences.map { valueMetrics($0).threeRun })
    private static let uniformFourRun = frequency(allValueSequences.map { valueMetrics($0).fourRun })

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func score(fullOutcomes: [Int], logic: [LogicMapping]) -> Double? {
        let outcomes = Array(fullOutcomes.prefix(6))
        guard outcomes.count == 6, logic.count >= 5,
              outcomes.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return nil }
        let values = zip(logic.prefix(5), outcomes.prefix(5)).map { $0.value(for: $1) }
        let outcome = outcomeMetrics(outcomes)
        let value = valueMetrics(values)

        let outcomeScore = [
            densityScore(outcome.countKey, samples: outcomeCountSamples, uniform: uniformOutcomeCount, universe: 729, observations: sampleCount),
            densityScore(outcome.diversity, samples: diversitySamples, uniform: uniformDiversity, universe: 729, observations: sampleCount),
            densityScore(outcome.returns, samples: returnSamples, uniform: uniformReturns, universe: 729, observations: sampleCount),
            densityScore(outcome.switches, samples: switchSamples, uniform: uniformSwitches, universe: 729, observations: sampleCount),
            densityScore(outcome.nonLoss, samples: nonLossSamples, uniform: uniformNonLoss, universe: 729, observations: sampleCount),
            densityScore(outcome.nonWin, samples: nonWinSamples, uniform: uniformNonWin, universe: 729, observations: sampleCount),
            densityScore(outcome.nonDraw, samples: nonDrawSamples, uniform: uniformNonDraw, universe: 729, observations: sampleCount),
            densityScore(outcome.drawRun, samples: drawRunSamples, uniform: uniformDrawRun, universe: 729, observations: sampleCount),
            densityScore(outcome.lossRun, samples: lossRunSamples, uniform: uniformLossRun, universe: 729, observations: sampleCount)
        ].reduce(0, +)
        let valueStructureScore = [
            densityScore(value.countKey, samples: valueCountSamples, uniform: uniformValueCount, universe: 243, observations: sampleCount),
            densityScore(value.displacement, samples: displacementSamples, uniform: uniformDisplacement, universe: 243, observations: sampleCount),
            densityScore(value.varianceNumerator, samples: varianceSamples, uniform: uniformVariance, universe: 243, observations: sampleCount),
            densityScore(value.roughness, samples: roughnessSamples, uniform: uniformRoughness, universe: 243, observations: sampleCount),
            densityScore(value.first, samples: firstValueSamples, uniform: uniformFirstValue, universe: 243, observations: sampleCount),
            densityScore(value.twoRun, samples: twoRunSamples, uniform: uniformTwoRun, universe: 243, observations: sampleCount),
            densityScore(value.threeRun, samples: threeRunSamples, uniform: uniformThreeRun, universe: 243, observations: sampleCount),
            densityScore(value.fourRun, samples: fourRunSamples, uniform: uniformFourRun, universe: 243, observations: sampleCount)
        ].reduce(0, +)
        let pooledDenominator = Double(sampleCount * 5) + smoothing * 3
        var pooledValueScore = 0.0
        for item in values {
            let observed = Double(pooledValueSamples[item, default: 0]) + smoothing
            pooledValueScore += log((observed / pooledDenominator) * 3.0)
        }
        let transitionDenominator = Double(sampleCount * 4) + smoothing * 9
        var transitionScore = 0.0
        for pair in zip(values, values.dropFirst()) {
            let key = pair.0 * 10 + pair.1
            let observed = Double(transitionSamples[key, default: 0]) + smoothing
            transitionScore += log((observed / transitionDenominator) * 9.0)
        }
        return outcomeScore + 0.05 * valueStructureScore + 2.0 * pooledValueScore + 0.2 * transitionScore
    }

    static func selectTop(_ expanded: [[Int]], logic: [LogicMapping]) -> [[Int]] {
        expanded.compactMap { outcomes in
            score(fullOutcomes: outcomes, logic: logic).map { (outcomes, $0) }
        }
        .sorted { left, right in
            if abs(left.1 - right.1) > 1e-12 { return left.1 > right.1 }
            return right.0.lexicographicallyPrecedes(left.0)
        }
        .prefix(keptCount)
        .map { $0.0 }
    }

    static func passes(fullOutcomes: [Int], logic: [LogicMapping]) -> Bool {
        let target = Array(fullOutcomes.prefix(6))
        guard target.count == 6, score(fullOutcomes: target, logic: logic) != nil else { return false }
        return selectTop(allOutcomeSequences, logic: logic).contains(target)
    }

    private static func densityScore(
        _ value: Int,
        samples: [Int: Int],
        uniform: [Int: Int],
        universe: Int,
        observations: Int
    ) -> Double {
        guard let uniformCount = uniform[value], uniformCount > 0 else { return -.infinity }
        let observed = (Double(samples[value, default: 0]) + smoothing)
            / (Double(observations) + smoothing * Double(uniform.count))
        let baseline = Double(uniformCount) / Double(universe)
        return log(observed / baseline)
    }

    private static func outcomeMetrics(_ outcomes: [Int]) -> OutcomeMetrics {
        let lossCount = outcomes.filter { $0 == 0 }.count
        let drawCount = outcomes.filter { $0 == 1 }.count
        let winCount = outcomes.filter { $0 == 3 }.count
        return OutcomeMetrics(
            countKey: lossCount * 100 + drawCount * 10 + winCount,
            diversity: Set(outcomes).count,
            returns: OutcomeCondition.returns.value(in: outcomes),
            switches: OutcomeCondition.winLossSwitches.value(in: outcomes),
            nonLoss: ConsecutiveRunCondition.nonLoss.longestRun(in: outcomes),
            nonWin: ConsecutiveRunCondition.nonWin.longestRun(in: outcomes),
            nonDraw: ConsecutiveRunCondition.nonDraw.longestRun(in: outcomes),
            drawRun: ConsecutiveRunCondition.draw.longestRun(in: outcomes),
            lossRun: ConsecutiveRunCondition.loss.longestRun(in: outcomes)
        )
    }

    private static func valueMetrics(_ values: [Int]) -> ValueMetrics {
        let sum = values.reduce(0, +)
        let count2 = values.filter { $0 == 2 }.count
        let count3 = values.filter { $0 == 3 }.count
        let count4 = values.filter { $0 == 4 }.count
        return ValueMetrics(
            countKey: count2 * 100 + count3 * 10 + count4,
            displacement: zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) },
            varianceNumerator: values.reduce(0) { $0 + (5 * $1 - sum) * (5 * $1 - sum) },
            roughness: values.indices.dropLast(2).reduce(0) {
                $0 + abs(values[$1] - 2 * values[$1 + 1] + values[$1 + 2])
            },
            first: values.first ?? 0,
            twoRun: longestRun(of: 2, in: values),
            threeRun: longestRun(of: 3, in: values),
            fourRun: longestRun(of: 4, in: values)
        )
    }

    private static func longestRun(of target: Int, in values: [Int]) -> Int {
        var longest = 0
        var current = 0
        for value in values {
            current = value == target ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}

/// VIP2：对六场729种彩果统一排名，固定保留前150种。
/// 项目换算的让球胜/平/负实际数值赔率权重80%，原始3/1/0彩果形态权重20%；
/// 不使用ABCD映射的2/3/4判定值，不读取期号、场次号或单条答案。
private enum VIP2Joint150Model {
    static let version = "VIP2-REAL-HANDICAP-ODDS80-OUTCOME-SHAPE20-K150-V3"
    static let configurationMarker = 7.150
    static let keptCount = 150

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func selectTop(
        _ expanded: [[Int]],
        logic _: [LogicMapping],
        comparisonTableOdds: [[Double]]?
    ) -> [[Int]] {
        guard !expanded.isEmpty,
              let odds = normalizedProbabilityRows(comparisonTableOdds),
              odds.count == 5 else { return [] }
        let raw = expanded.compactMap { outcomes -> (outcomes: [Int], structure: Double, odds: Double)? in
            guard outcomes.count >= 6,
                  let structure = outcomeStructureScore(outcomes: outcomes) else { return nil }
            let firstFive = Array(outcomes.prefix(5))
            let oddsScore = zip(firstFive, odds).reduce(0.0) { partial, pair in
                let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                return partial + log(max(pair.1[index], 1e-15))
            }
            return (outcomes, structure, oddsScore)
        }
        guard raw.count == expanded.count else { return [] }
        let structureStats = meanAndDeviation(raw.map(\.structure))
        let oddsStats = meanAndDeviation(raw.map(\.odds))
        return raw.map { item -> (outcomes: [Int], score: Double) in
            let structureZ = (item.structure - structureStats.mean) / structureStats.deviation
            let oddsZ = (item.odds - oddsStats.mean) / oddsStats.deviation
            return (item.outcomes, 0.20 * structureZ + 0.80 * oddsZ)
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 1e-12 { return left.score > right.score }
            return right.outcomes.lexicographicallyPrecedes(left.outcomes)
        }
        .prefix(keptCount)
        .map(\.outcomes)
    }

    static func passes(
        fullOutcomes: [Int],
        logic: [LogicMapping],
        comparisonTableOdds: [[Double]]?
    ) -> Bool {
        let target = Array(fullOutcomes.prefix(6))
        guard target.count == 6 else { return false }
        let suffix = Array(fullOutcomes.dropFirst(6))
        let candidates = (0..<6).reduce([[]]) { partial, _ in
            partial.flatMap { prefix in [3, 1, 0].map { prefix + [$0] } }
        }.map { $0 + suffix }
        return selectTop(
            candidates,
            logic: logic,
            comparisonTableOdds: comparisonTableOdds
        ).contains { Array($0.prefix(6)) == target }
    }

    private static func normalizedProbabilityRows(_ odds: [[Double]]?) -> [[Double]]? {
        guard let odds, odds.count == 5,
              odds.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else {
            return nil
        }
        return odds.map { row in
            let inverse = row.map { 1 / $0 }
            let total = inverse.reduce(0, +)
            return inverse.map { $0 / total }
        }
    }

    private static func meanAndDeviation(_ values: [Double]) -> (mean: Double, deviation: Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, max(sqrt(variance), 1e-12))
    }

    private static func longestRun(_ outcomes: [Int], matching predicate: (Int) -> Bool) -> Int {
        var best = 0
        var current = 0
        for outcome in outcomes {
            current = predicate(outcome) ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    private static func featureKey(_ parts: Any...) -> String {
        parts.map { String(describing: $0) }.joined(separator: ":")
    }

    fileprivate static func structureScore(outcomes: [Int], logic: [LogicMapping]) -> Double? {
        let firstSix = Array(outcomes.prefix(6))
        let firstFive = Array(firstSix.prefix(5))
        guard firstSix.count == 6,
              firstSix.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }),
              logic.count == 5 else { return nil }
        let values = zip(logic, firstFive).map { $0.value(for: $1) }
        let total = values.reduce(0, +)
        let displacement = zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
        let variance25 = values.reduce(0) { $0 + (5 * $1 - total) * (5 * $1 - total) }
        let roughness = values.indices.dropFirst(2).reduce(0) {
            $0 + abs(values[$1] - 2 * values[$1 - 1] + values[$1 - 2])
        }
        let breakpoints = zip(firstFive, firstFive.dropFirst()).filter { $0 != $1 }.count
        let counts = [3, 1, 0].map { target in firstSix.filter { $0 == target }.count }
        let runs = [3, 1, 0].map { target in longestRun(firstSix) { $0 == target } }
        let nonRuns = [
            longestRun(firstSix) { $0 != 0 },
            longestRun(firstSix) { $0 != 1 },
            longestRun(firstSix) { $0 != 3 }
        ]
        let outcomeSum = firstSix.reduce(0, +)
        let resultReturns = OutcomeCondition.returns.value(in: firstSix)
        let switches = OutcomeCondition.winLossSwitches.value(in: firstSix)
        let diversity = Set(firstSix).count
        let productQ = values.reduce(1, *)
        var keys: [String] = []
        for (index, outcome) in firstSix.enumerated() {
            keys.append(featureKey("op", index, outcome))
            if index < 5 {
                let letter = logic[index].displayName
                keys.append(featureKey("lop", letter, outcome))
                keys.append(featureKey("lv", letter, values[index]))
                keys.append(featureKey("vp", index, values[index]))
            }
        }
        for index in 0..<5 {
            keys.append(featureKey("pair_o", index, firstSix[index], firstSix[index + 1]))
        }
        for index in 0..<4 {
            keys.append(featureKey("pair_v", index, values[index], values[index + 1]))
            keys.append(featureKey("tri_o", index, firstSix[index], firstSix[index + 1], firstSix[index + 2]))
        }
        keys += [
            featureKey("sum", total), featureKey("disp", displacement),
            featureKey("var25", variance25), featureKey("v2", values.filter { $0 == 2 }.count),
            featureKey("v4", values.filter { $0 == 4 }.count), featureKey("rough", roughness),
            featureKey("break", breakpoints), featureKey("q", productQ),
            featureKey("wins", counts[0]), featureKey("draws", counts[1]),
            featureKey("losses", counts[2]), featureKey("kinds", diversity),
            featureKey("osum", outcomeSum), featureKey("returns", resultReturns),
            featureKey("switches", switches), featureKey("wr", runs[0]),
            featureKey("dr", runs[1]), featureKey("lr", runs[2]),
            featureKey("nl", nonRuns[0]), featureKey("nd", nonRuns[1]),
            featureKey("nw", nonRuns[2]), featureKey("frontsum", firstSix.prefix(3).reduce(0, +)),
            featureKey("backsum", firstSix.suffix(3).reduce(0, +)),
            featureKey("counts", counts[0], counts[1], counts[2]),
            featureKey("runs", runs[0], runs[1], runs[2]),
            featureKey("nonruns", nonRuns[0], nonRuns[1], nonRuns[2]),
            featureKey("sum_disp", total, displacement), featureKey("sum_var", total, variance25),
            featureKey("count_run", counts[0], counts[1], counts[2], runs[0], runs[1], runs[2]),
            featureKey("shape", outcomeSum, resultReturns, switches, diversity)
        ]
        return keys.reduce(0.0) { $0 + weights[$1, default: 0] }
    }

    /// VIP2/VIP3的彩果形态只读3/1/0本身，不再把ABCD换成2/3/4。
    fileprivate static func outcomeStructureScore(outcomes: [Int]) -> Double? {
        let firstSix = Array(outcomes.prefix(6))
        guard firstSix.count == 6,
              firstSix.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return nil }
        let counts = [3, 1, 0].map { target in firstSix.filter { $0 == target }.count }
        let runs = [3, 1, 0].map { target in longestRun(firstSix) { $0 == target } }
        let nonRuns = [
            longestRun(firstSix) { $0 != 0 },
            longestRun(firstSix) { $0 != 1 },
            longestRun(firstSix) { $0 != 3 }
        ]
        let outcomeSum = firstSix.reduce(0, +)
        let resultReturns = OutcomeCondition.returns.value(in: firstSix)
        let switches = OutcomeCondition.winLossSwitches.value(in: firstSix)
        let diversity = Set(firstSix).count
        let breakpoints = zip(firstSix, firstSix.dropFirst()).filter { $0 != $1 }.count
        var keys = firstSix.indices.map { featureKey("op", $0, firstSix[$0]) }
        for index in 0..<5 {
            keys.append(featureKey("pair_o", index, firstSix[index], firstSix[index + 1]))
        }
        for index in 0..<4 {
            keys.append(featureKey("tri_o", index, firstSix[index], firstSix[index + 1], firstSix[index + 2]))
        }
        keys += [
            featureKey("break", breakpoints),
            featureKey("wins", counts[0]), featureKey("draws", counts[1]),
            featureKey("losses", counts[2]), featureKey("kinds", diversity),
            featureKey("osum", outcomeSum), featureKey("returns", resultReturns),
            featureKey("switches", switches), featureKey("wr", runs[0]),
            featureKey("dr", runs[1]), featureKey("lr", runs[2]),
            featureKey("nl", nonRuns[0]), featureKey("nd", nonRuns[1]),
            featureKey("nw", nonRuns[2]), featureKey("frontsum", firstSix.prefix(3).reduce(0, +)),
            featureKey("backsum", firstSix.suffix(3).reduce(0, +)),
            featureKey("counts", counts[0], counts[1], counts[2]),
            featureKey("runs", runs[0], runs[1], runs[2]),
            featureKey("nonruns", nonRuns[0], nonRuns[1], nonRuns[2]),
            featureKey("count_run", counts[0], counts[1], counts[2], runs[0], runs[1], runs[2]),
            featureKey("shape", outcomeSum, resultReturns, switches, diversity)
        ]
        return keys.reduce(0.0) { $0 + weights[$1, default: 0] }
    }

    private static let weights: [String: Double] = [
        "backsum:0": -0.40667498083196574,
        "backsum:1": -0.36442579108584666,
        "backsum:2": -0.14820668464164596,
        "backsum:3": 0.060004381341020444,
        "backsum:4": 0.020512725456328075,
        "backsum:5": 0.049322604656256375,
        "backsum:6": 0.45135876565013872,
        "backsum:7": 0.33627767581212409,
        "backsum:9": -0.050284630710721999,
        "break:0": -0.00095529700420391318,
        "break:1": 0.21306280993129673,
        "break:2": 0.057868332279841908,
        "break:3": -0.1006158856424552,
        "break:4": -0.17350883022167643,
        "count_run:0:0:6:0:0:6": -0.19127377069213689,
        "count_run:0:1:5:0:1:3": -0.43299345229443131,
        "count_run:0:1:5:0:1:4": 0.16181938588361355,
        "count_run:0:1:5:0:1:5": -0.20401508025049808,
        "count_run:0:2:4:0:1:2": -0.079616757599154014,
        "count_run:0:2:4:0:1:3": 0.2371078633036719,
        "count_run:0:2:4:0:1:4": 0.5212097750393998,
        "count_run:0:2:4:0:2:2": -0.32393187089837733,
        "count_run:0:2:4:0:2:3": -0.32448933444163447,
        "count_run:0:2:4:0:2:4": -0.21885515307499784,
        "count_run:0:3:3:0:1:1": -0.26769096977786799,
        "count_run:0:3:3:0:1:2": 0.36044130452482465,
        "count_run:0:3:3:0:2:1": -0.12242477432510684,
        "count_run:0:3:3:0:2:2": 0.20831455438688928,
        "count_run:0:3:3:0:2:3": 0.47814918349861807,
        "count_run:0:3:3:0:3:2": -0.40938603618560165,
        "count_run:0:3:3:0:3:3": -0.21836363653077645,
        "count_run:0:4:2:0:2:1": -0.28471831438002887,
        "count_run:0:4:2:0:2:2": -0.11284648693812067,
        "count_run:0:4:2:0:3:1": -0.23285112100190172,
        "count_run:0:4:2:0:3:2": -0.036496878373170005,
        "count_run:0:4:2:0:4:1": -0.081911141936725912,
        "count_run:0:4:2:0:4:2": 0.47978585120443967,
        "count_run:0:5:1:0:3:1": 0.48867864840289049,
        "count_run:0:5:1:0:4:1": -0.25242218468009231,
        "count_run:0:5:1:0:5:1": -0.2139540526901933,
        "count_run:0:6:0:0:6:0": 0.24000183812184844,
        "count_run:1:0:5:1:0:3": 0.13186312629120192,
        "count_run:1:0:5:1:0:4": -0.43162301427020711,
        "count_run:1:0:5:1:0:5": -0.028108919836934282,
        "count_run:1:1:4:1:1:2": -0.35484075561621931,
        "count_run:1:1:4:1:1:3": 0.45891707599558168,
        "count_run:1:1:4:1:1:4": -0.34903751509040237,
        "count_run:1:2:3:1:1:1": -1.0227243647978335,
        "count_run:1:2:3:1:1:2": 0.52304381718488957,
        "count_run:1:2:3:1:1:3": -0.3063420128836134,
        "count_run:1:2:3:1:2:1": 1.6454402267332009,
        "count_run:1:2:3:1:2:2": -0.24634332764498132,
        "count_run:1:2:3:1:2:3": -0.71545572569078997,
        "count_run:1:3:2:1:1:1": 0.32348434732827142,
        "count_run:1:3:2:1:1:2": -0.51371313976760868,
        "count_run:1:3:2:1:2:1": -0.30311245882517757,
        "count_run:1:3:2:1:2:2": -0.21591030643365758,
        "count_run:1:3:2:1:3:1": 0.76208505676314808,
        "count_run:1:3:2:1:3:2": -0.095979551208216274,
        "count_run:1:4:1:1:2:1": 0.2227954208981987,
        "count_run:1:4:1:1:3:1": -0.42005820615294448,
        "count_run:1:4:1:1:4:1": 0.18789190740786829,
        "count_run:1:5:0:1:3:0": -0.085327109816518379,
        "count_run:1:5:0:1:4:0": -0.12304759617409883,
        "count_run:1:5:0:1:5:0": 0.18839936034040322,
        "count_run:2:0:4:1:0:2": -0.62126182938109387,
        "count_run:2:0:4:1:0:3": 0.19153766341272682,
        "count_run:2:0:4:1:0:4": 0.30895419355371873,
        "count_run:2:0:4:2:0:2": 0.42086154301794354,
        "count_run:2:0:4:2:0:3": -0.075449408711485644,
        "count_run:2:0:4:2:0:4": -0.45299756382065709,
        "count_run:2:1:3:1:1:1": 0.23178526482882877,
        "count_run:2:1:3:1:1:2": -0.57023276822609159,
        "count_run:2:1:3:1:1:3": -0.18416454580206554,
        "count_run:2:1:3:2:1:1": 0.12427912615030424,
        "count_run:2:1:3:2:1:2": 0.19729792060635437,
        "count_run:2:1:3:2:1:3": 0.39408962440192152,
        "count_run:2:2:2:1:1:1": 0.45923227905450997,
        "count_run:2:2:2:1:1:2": -0.56174375260343445,
        "count_run:2:2:2:1:2:1": -0.96973742480567549,
        "count_run:2:2:2:1:2:2": -0.36059962108387278,
        "count_run:2:2:2:2:1:1": 0.096767362279984045,
        "count_run:2:2:2:2:1:2": 0.21046467727055698,
        "count_run:2:2:2:2:2:1": 0.75633796627127547,
        "count_run:2:2:2:2:2:2": 0.34604224574427939,
        "count_run:2:3:1:1:1:1": -0.17736977939577231,
        "count_run:2:3:1:1:2:1": -0.45134659375831804,
        "count_run:2:3:1:1:3:1": 0.19542346363080382,
        "count_run:2:3:1:2:1:1": 1.0377902236596046,
        "count_run:2:3:1:2:2:1": -0.92270970482107995,
        "count_run:2:3:1:2:3:1": 0.22568360052453759,
        "count_run:2:4:0:1:2:0": -0.37804124231163261,
        "count_run:2:4:0:1:3:0": 0.4974891342840837,
        "count_run:2:4:0:1:4:0": -0.023387284802756196,
        "count_run:2:4:0:2:2:0": 0.55676808383144782,
        "count_run:2:4:0:2:3:0": -0.35988156197776344,
        "count_run:2:4:0:2:4:0": 0.017704654007247578,
        "count_run:3:0:3:1:0:1": -0.22044480835515992,
        "count_run:3:0:3:1:0:2": 0.87196314717778123,
        "count_run:3:0:3:2:0:1": -0.67709114525842706,
        "count_run:3:0:3:2:0:2": 0.33135769589628339,
        "count_run:3:0:3:2:0:3": -0.27013013485259468,
        "count_run:3:0:3:3:0:2": -0.40578899591929152,
        "count_run:3:0:3:3:0:3": 0.2643370456900262,
        "count_run:3:1:2:1:1:1": 0.26325814944451376,
        "count_run:3:1:2:1:1:2": 0.91424990541359252,
        "count_run:3:1:2:2:1:1": -0.64872448457178855,
        "count_run:3:1:2:2:1:2": -0.55278349785634162,
        "count_run:3:1:2:3:1:1": 0.37704561877487569,
        "count_run:3:1:2:3:1:2": -0.37553839099377628,
        "count_run:3:2:1:1:1:1": 0.33632839930937547,
        "count_run:3:2:1:1:2:1": -0.10195543245695088,
        "count_run:3:2:1:2:1:1": -0.16074491307721575,
        "count_run:3:2:1:2:2:1": 0.15772828903589689,
        "count_run:3:2:1:3:1:1": -0.66402045970859036,
        "count_run:3:2:1:3:2:1": 0.43437346617426353,
        "count_run:3:3:0:1:1:0": 0.18254454000914666,
        "count_run:3:3:0:1:2:0": 0.90353091895484483,
        "count_run:3:3:0:2:1:0": -0.57196676419178027,
        "count_run:3:3:0:2:2:0": -0.22069626149520841,
        "count_run:3:3:0:2:3:0": -0.14160300082049229,
        "count_run:3:3:0:3:2:0": 0.41319776864211721,
        "count_run:3:3:0:3:3:0": -0.25427005187430307,
        "count_run:4:0:2:2:0:1": 0.43330369963645993,
        "count_run:4:0:2:2:0:2": -0.75034099538395582,
        "count_run:4:0:2:3:0:1": 0.15775664669778697,
        "count_run:4:0:2:3:0:2": 0.98910895743022775,
        "count_run:4:0:2:4:0:1": -0.66782697281809145,
        "count_run:4:0:2:4:0:2": 0.12408297372336062,
        "count_run:4:1:1:2:1:1": -0.060002929889889381,
        "count_run:4:1:1:3:1:1": -0.031386078057722415,
        "count_run:4:1:1:4:1:1": 0.42990296502269071,
        "count_run:4:2:0:2:1:0": 0.71415010954419977,
        "count_run:4:2:0:2:2:0": -0.23211636426836341,
        "count_run:4:2:0:3:1:0": -0.76818923827754504,
        "count_run:4:2:0:3:2:0": -0.22616743551599383,
        "count_run:4:2:0:4:2:0": 0.55581931681431418,
        "count_run:5:0:1:3:0:1": -0.21304567798374879,
        "count_run:5:0:1:4:0:1": 0.52738360334660273,
        "count_run:5:0:1:5:0:1": 0.24426913151967453,
        "count_run:5:1:0:3:1:0": 0.86266480517262589,
        "count_run:5:1:0:4:1:0": -0.55202350059417404,
        "count_run:5:1:0:5:1:0": -0.21735613438494772,
        "count_run:6:0:0:6:0:0": -0.14772037979944078,
        "counts:0:0:6": -0.19127377069213689,
        "counts:0:1:5": -0.47317839389705946,
        "counts:0:2:4": -0.18597712319785803,
        "counts:0:3:3": 0.032806805589590128,
        "counts:0:4:2": -0.26659020310954584,
        "counts:0:5:1": 0.023418207970307178,
        "counts:0:6:0": 0.24000183812184844,
        "counts:1:0:5": -0.32569824215379373,
        "counts:1:1:4": -0.23806042292312654,
        "counts:1:2:3": -0.1126442085185619,
        "counts:1:3:2": -0.040046711753453576,
        "counts:1:4:1": -0.0050118679115113496,
        "counts:1:5:0": -0.019720076833385621,
        "counts:2:0:4": -0.22249138814562783,
        "counts:2:1:3": 0.17486839744472496,
        "counts:2:2:2": -0.0019493723055800179,
        "counts:2:3:1": -0.097447263162344713,
        "counts:2:4:0": 0.30895904634432075,
        "counts:3:0:3": -0.098552499688578224,
        "counts:3:1:2": -0.031536902526705678,
        "counts:3:2:1": 0.0065738709038756218,
        "counts:3:3:0": 0.30850058416840315,
        "counts:4:0:2": 0.28986250466811736,
        "counts:4:1:1": 0.33155470940944953,
        "counts:4:2:0": 0.049878729572856779,
        "counts:5:0:1": 0.55341470730062858,
        "counts:5:1:0": 0.096483017404044649,
        "counts:6:0:0": -0.14772037979944078,
        "disp:0": 0.10951247001666446,
        "disp:1": -0.5524441283460505,
        "disp:2": 0.12000897058126549,
        "disp:3": -0.20515392507570884,
        "disp:4": 0.35709261175195134,
        "disp:5": -0.13612032057181772,
        "disp:6": 0.14474186447423448,
        "disp:7": 0.12360405678455176,
        "disp:8": 0.0041241906682679755,
        "dr:0": -0.12636281333746724,
        "dr:1": -0.12512346481072475,
        "dr:2": -0.051805381125878937,
        "dr:3": -0.072695819279412252,
        "dr:4": 0.20407358626048866,
        "dr:5": -0.025245427283058203,
        "dr:6": 0.24000183812184844,
        "draws:0": -0.12636281333746724,
        "draws:1": -0.095640193115983638,
        "draws:2": -0.21676357360204948,
        "draws:3": 0.17510814528506041,
        "draws:4": 0.039394531674756976,
        "draws:5": 0.0036252348510450259,
        "draws:6": 0.24000183812184844,
        "frontsum:0": -0.90974549658077342,
        "frontsum:1": -0.49743763387209511,
        "frontsum:2": -0.43373260535631908,
        "frontsum:3": -0.19628060696580299,
        "frontsum:4": -0.12495680506530445,
        "frontsum:5": 0.21172591817286043,
        "frontsum:6": 0.63531305472211064,
        "frontsum:7": 0.86632195712964444,
        "frontsum:9": 0.40352627481864817,
        "kinds:1": -0.098674038115792867,
        "kinds:2": 0.082959715651513527,
        "kinds:3": 0.012068449297836367,
        "lop:A:0": 5.9843493523561895,
        "lop:A:1": 4.6620295383839707,
        "lop:A:3": 1.4199212541778723,
        "lop:B:0": 1.8532289320379165,
        "lop:B:1": -1.5021317169352202,
        "lop:B:3": -4.0721806277111696,
        "lop:C:0": 4.3587432459987019,
        "lop:C:1": 2.8179639137019712,
        "lop:C:3": 2.8635120899943782,
        "lop:D:0": 2.4978404586388856,
        "lop:D:1": 1.8936589334351828,
        "lop:D:3": -0.74548327632360256,
        "losses:0": 0.82015220085185403,
        "losses:1": 0.75567176529576774,
        "losses:2": -0.018664256530568218,
        "losses:3": -0.0087145934899705655,
        "losses:4": -0.63212997457580244,
        "losses:5": -0.7956240714357099,
        "losses:6": -0.19127377069213689,
        "lr:0": 0.82015220085185403,
        "lr:1": 0.86270181924438105,
        "lr:2": -0.52740822112913299,
        "lr:3": -0.34830729833734891,
        "lr:4": -0.45467759916818545,
        "lr:5": -0.23175703225142957,
        "lr:6": -0.19127377069213689,
        "lv:A:2": 1.4199212541778723,
        "lv:A:3": 4.6620295383839707,
        "lv:A:4": 5.9843493523561895,
        "lv:B:2": -4.0721806277111696,
        "lv:B:3": 1.8532289320379165,
        "lv:B:4": -1.5021317169352202,
        "lv:C:2": 4.3587432459987019,
        "lv:C:3": 2.8635120899943782,
        "lv:C:4": 2.8179639137019712,
        "lv:D:2": 2.4978404586388856,
        "lv:D:3": 1.8936589334351828,
        "lv:D:4": -0.74548327632360256,
        "nd:0": 0.24000183812184844,
        "nd:1": 0.013588918643522291,
        "nd:2": 0.30750704663753209,
        "nd:3": -0.058724989245708556,
        "nd:4": -0.17624005208349472,
        "nd:5": -0.23813307724721203,
        "nd:6": -0.12636281333746724,
        "nl:0": -0.19127377069213689,
        "nl:1": -0.98422979527607279,
        "nl:2": -0.70390051015868949,
        "nl:3": 0.24014664007785957,
        "nl:4": 0.31785246761266173,
        "nl:5": 0.53475654357882363,
        "nl:6": 0.82015220085185403,
        "nonruns:0:6:6": -0.19127377069213689,
        "nonruns:1:1:6": -0.26769096977786799,
        "nonruns:1:2:5": -0.23885117072969447,
        "nonruns:1:2:6": 0.27902036072604991,
        "nonruns:1:3:3": -1.3563959734347333,
        "nonruns:1:3:4": 0.97528496772094952,
        "nonruns:1:3:5": 0.9928616129384904,
        "nonruns:1:3:6": -0.19479800484874488,
        "nonruns:1:4:3": 0.34076631888037373,
        "nonruns:1:4:4": -0.66086321094993938,
        "nonruns:1:4:5": -0.92207553218556582,
        "nonruns:1:4:6": 0.68065718691591681,
        "nonruns:1:5:2": -0.65495602722791402,
        "nonruns:1:5:3": -0.5829989110192958,
        "nonruns:1:5:4": 0.72202180725077492,
        "nonruns:1:5:5": -0.17938364149721667,
        "nonruns:1:5:6": -0.20401508025049808,
        "nonruns:1:6:1": -0.22044480835515992,
        "nonruns:1:6:2": 0.25037602730000602,
        "nonruns:1:6:3": 0.32128626652634656,
        "nonruns:1:6:4": -0.1218651052224219,
        "nonruns:1:6:5": -0.028108919836934282,
        "nonruns:2:1:5": 1.1516839526093534,
        "nonruns:2:1:6": -0.40710823212975139,
        "nonruns:2:2:2": -1.9805267405963209,
        "nonruns:2:2:3": 1.0525801801338621,
        "nonruns:2:2:4": 0.55148443645180101,
        "nonruns:2:2:5": 0.55117330097759298,
        "nonruns:2:2:6": -0.22383418822095524,
        "nonruns:2:3:2": 0.29432432277887444,
        "nonruns:2:3:3": 0.270121566603165,
        "nonruns:2:3:4": -0.717213560494811,
        "nonruns:2:3:5": 0.58584779986503577,
        "nonruns:2:3:6": 0.15449404604054909,
        "nonruns:2:4:2": -0.39123615558129698,
        "nonruns:2:4:3": 0.26149148884040085,
        "nonruns:2:4:4": -0.21099616778864341,
        "nonruns:2:4:5": -0.22935274621489435,
        "nonruns:2:4:6": -0.21885515307499784,
        "nonruns:2:5:1": 0.079895517990006826,
        "nonruns:2:5:2": 0.90621680283627826,
        "nonruns:2:5:3": -1.0420484971060469,
        "nonruns:2:5:4": -0.25147862294979406,
        "nonruns:2:6:1": -0.240721227238513,
        "nonruns:2:6:2": 0.0061537683368472085,
        "nonruns:2:6:3": -0.34424180120427977,
        "nonruns:2:6:4": -0.45299756382065709,
        "nonruns:3:1:3": -0.76246491500004032,
        "nonruns:3:1:4": 0.88423168888855619,
        "nonruns:3:1:5": 0.16093235860884633,
        "nonruns:3:1:6": 0.25626024284108168,
        "nonruns:3:2:2": 0.36032107949408121,
        "nonruns:3:2:3": 0.17162208829521838,
        "nonruns:3:2:4": 0.98748608693832618,
        "nonruns:3:2:5": -1.2759165980832408,
        "nonruns:3:2:6": -0.44586797324640115,
        "nonruns:3:3:1": -0.18103560745790984,
        "nonruns:3:3:2": -0.34990748166532992,
        "nonruns:3:3:3": 0.7396318253880112,
        "nonruns:3:3:4": -0.82755017644758566,
        "nonruns:3:3:5": -0.50974577050624847,
        "nonruns:3:3:6": -0.21836363653077645,
        "nonruns:3:4:1": -0.62961897397215938,
        "nonruns:3:4:2": 0.14137303003655524,
        "nonruns:3:4:3": 0.50118280398743942,
        "nonruns:3:5:1": -1.0124261618963817,
        "nonruns:3:5:2": 1.246250498077623,
        "nonruns:3:5:3": 0.18631894350956615,
        "nonruns:3:6:1": -0.054844702466390838,
        "nonruns:3:6:2": 0.58302557315068526,
        "nonruns:3:6:3": 0.2643370456900262,
        "nonruns:4:1:3": 1.1392789521657314,
        "nonruns:4:1:4": -1.0539669183505889,
        "nonruns:4:1:5": -0.2340112121312585,
        "nonruns:4:1:6": -0.33431265042742098,
        "nonruns:4:2:2": -0.067175644273982357,
        "nonruns:4:2:3": 0.1436581296863309,
        "nonruns:4:2:4": -1.1619627714094276,
        "nonruns:4:2:5": 0.31890699941250217,
        "nonruns:4:2:6": 0.47978585120443967,
        "nonruns:4:3:1": -0.67818002760470009,
        "nonruns:4:3:2": 1.2916623499173279,
        "nonruns:4:3:3": -0.47490849306191368,
        "nonruns:4:4:1": 1.3587560788175044,
        "nonruns:4:4:2": -0.13934081335666287,
        "nonruns:4:5:1": 0.98841893367389178,
        "nonruns:4:5:2": -1.2548624447786054,
        "nonruns:4:6:1": -0.13703899723227442,
        "nonruns:4:6:2": 0.12408297372336062,
        "nonruns:5:1:2": -0.71510948639034366,
        "nonruns:5:1:3": -0.19400757623605563,
        "nonruns:5:1:4": -0.095658823801373458,
        "nonruns:5:1:5": -0.49566105936828275,
        "nonruns:5:1:6": -0.2139540526901933,
        "nonruns:5:2:1": -0.2163750243542556,
        "nonruns:5:2:2": -0.48261126149739775,
        "nonruns:5:2:3": 0.33333653851325112,
        "nonruns:5:2:4": 1.3817375301948969,
        "nonruns:5:3:1": 0.19077764253463031,
        "nonruns:5:3:2": 0.68706911102389689,
        "nonruns:5:3:3": -0.7738030841950424,
        "nonruns:5:4:1": 0.63737857190066782,
        "nonruns:5:4:2": -0.74163569711817201,
        "nonruns:5:5:1": 0.98991925334860864,
        "nonruns:5:6:1": 0.24426913151967453,
        "nonruns:6:0:6": 0.24000183812184844,
        "nonruns:6:1:1": 0.18254454000914666,
        "nonruns:6:1:2": 0.5238367189573383,
        "nonruns:6:1:3": 0.4123167954270755,
        "nonruns:6:1:4": -0.14643200322767902,
        "nonruns:6:1:5": 0.18839936034040322,
        "nonruns:6:2:1": 0.14471686045918689,
        "nonruns:6:2:2": 0.10281881663194535,
        "nonruns:6:2:3": -0.50143360248913982,
        "nonruns:6:2:4": 0.017704654007247578,
        "nonruns:6:3:1": 0.097236346134176518,
        "nonruns:6:3:2": 0.18747828475585876,
        "nonruns:6:3:3": -0.25427005187430307,
        "nonruns:6:4:1": -0.55202350059417404,
        "nonruns:6:4:2": 0.55581931681431418,
        "nonruns:6:5:1": -0.21735613438494772,
        "nonruns:6:6:0": -0.14772037979944078,
        "nw:0": -0.14772037979944078,
        "nw:1": 0.72103180368155562,
        "nw:2": 0.52978176862299808,
        "nw:3": -0.07233501779583569,
        "nw:4": -0.13800094771882399,
        "nw:5": -0.14484199683151761,
        "nw:6": -0.80171471067254174,
        "op:0:0": -1.938307623317749,
        "op:0:1": 0.41236936505702265,
        "op:0:3": 1.5125489570108404,
        "op:1:0": -1.4249184475386012,
        "op:1:1": 0.31350336282508884,
        "op:1:3": 1.1098741069670313,
        "op:2:0": -1.1653219877070868,
        "op:2:1": 0.24904762025251723,
        "op:2:3": 0.91227193635845494,
        "op:3:0": -1.2486643252139433,
        "op:3:1": 0.30594398418204533,
        "op:3:3": 0.93570791485566163,
        "op:4:0": -1.3052988424376999,
        "op:4:1": 0.22813951389021592,
        "op:4:3": 1.0682519296675674,
        "op:5:0": 0.74680948189259189,
        "op:5:1": -0.099066309668710065,
        "op:5:3": -0.66081942135848681,
        "osum:0": -0.19127377069213689,
        "osum:1": -0.47317839389705946,
        "osum:10": 0.26158175233025432,
        "osum:11": 0.0065738709038756218,
        "osum:12": 0.58948592468804684,
        "osum:13": 0.33155470940944953,
        "osum:14": 0.049878729572856779,
        "osum:15": 0.55341470730062858,
        "osum:16": 0.096483017404044649,
        "osum:18": -0.14772037979944078,
        "osum:2": -0.18597712319785803,
        "osum:3": -0.28858369004955065,
        "osum:4": -0.49760064213091665,
        "osum:5": -0.088620766803389942,
        "osum:6": -0.024788463283806489,
        "osum:7": 0.16564948214143888,
        "osum:8": -0.024477419502441498,
        "osum:9": -0.18970224242738887,
        "pair_o:0:0:0": -1.2807567412365362,
        "pair_o:0:0:1": -0.44860241731832123,
        "pair_o:0:0:3": -0.32667941763014624,
        "pair_o:0:1:0": -0.27685720224288329,
        "pair_o:0:1:1": 0.32219097407796715,
        "pair_o:0:1:3": 0.4001910092635505,
        "pair_o:0:3:0": 0.059934295707669463,
        "pair_o:0:3:1": 0.4694975833209768,
        "pair_o:0:3:3": 1.0550056081131653,
        "pair_o:1:0:0": -0.68649338467285725,
        "pair_o:1:0:1": -0.20806365171139163,
        "pair_o:1:0:3": -0.60972247208962282,
        "pair_o:1:1:0": -0.64454255763151513,
        "pair_o:1:1:1": 0.55727293438517267,
        "pair_o:1:1:3": 0.45133337029985177,
        "pair_o:1:3:0": 0.094610255433841842,
        "pair_o:1:3:1": -0.059767078029570292,
        "pair_o:1:3:3": 1.1013866955952476,
        "pair_o:2:0:0": -0.97480401498562752,
        "pair_o:2:0:1": -0.2943991482635987,
        "pair_o:2:0:3": 0.027408319571014354,
        "pair_o:2:1:0": -0.23056439896741829,
        "pair_o:2:1:1": 0.18252114253861174,
        "pair_o:2:1:3": 0.32747157142887029,
        "pair_o:2:3:0": -0.1203752583060026,
        "pair_o:2:3:1": 0.43748910794484619,
        "pair_o:2:3:3": 0.6232412851581417,
        "pair_o:3:0:0": -0.98638355251918153,
        "pair_o:3:0:1": -0.41285111082395831,
        "pair_o:3:0:3": 0.073535345901445989,
        "pair_o:3:1:0": -0.36460901628036585,
        "pair_o:3:1:1": 0.18426205619925576,
        "pair_o:3:1:3": 0.49550976704815397,
        "pair_o:3:3:0": -0.043912104272262519,
        "pair_o:3:3:1": 0.46922413400005147,
        "pair_o:3:3:3": 0.55491217301705942,
        "pair_o:4:0:0": -0.054804701581234398,
        "pair_o:4:0:1": -0.6958108404541935,
        "pair_o:4:0:3": -0.63901592507501015,
        "pair_o:4:1:0": 0.41736508914591969,
        "pair_o:4:1:1": 0.19375221570298654,
        "pair_o:4:1:3": -0.37554499762289811,
        "pair_o:4:3:0": 0.44011758939358775,
        "pair_o:4:3:1": 0.37879012498695297,
        "pair_o:4:3:3": 0.30257691451289193,
        "pair_v:0:2:2": 0.87552644425768067,
        "pair_v:0:2:3": -0.15720771931332872,
        "pair_v:0:2:4": 0.42419568579559802,
        "pair_v:0:3:2": 0.031856922041557711,
        "pair_v:0:3:3": -0.6772227184715619,
        "pair_v:0:3:4": -0.77840453733727755,
        "pair_v:0:4:2": 0.22092442089811568,
        "pair_v:0:4:3": -0.24836817544206261,
        "pair_v:0:4:4": 0.25172606072758297,
        "pair_v:1:2:2": 0.7835665539809451,
        "pair_v:1:2:3": 0.020714252151470103,
        "pair_v:1:2:4": 0.3361589860299668,
        "pair_v:1:3:2": 0.021102955605992166,
        "pair_v:1:3:3": -0.61944023499898804,
        "pair_v:1:3:4": -0.49292819032577634,
        "pair_v:1:4:2": 0.3969021618889696,
        "pair_v:1:4:3": -0.43306899682354849,
        "pair_v:1:4:4": -0.055145492495356954,
        "pair_v:2:2:2": 0.93713333567631107,
        "pair_v:2:2:3": -0.080095633213761355,
        "pair_v:2:2:4": 0.33662521175098176,
        "pair_v:2:3:2": 0.043340656012848755,
        "pair_v:2:3:3": -0.94719995679864288,
        "pair_v:2:3:4": -0.15713952624865907,
        "pair_v:2:4:2": 0.11823576410551216,
        "pair_v:2:4:3": -0.30670101983774589,
        "pair_v:2:4:4": -0.014140729945715361,
        "pair_v:3:2:2": 0.95723682453987757,
        "pair_v:3:2:3": -0.18961784180010044,
        "pair_v:3:2:4": 0.31780047318863608,
        "pair_v:3:3:2": -0.09398833552111277,
        "pair_v:3:3:3": -0.78598130857011606,
        "pair_v:3:3:4": -0.44053159000282022,
        "pair_v:3:4:2": 0.43699446023165212,
        "pair_v:3:4:3": -0.39896392036666456,
        "pair_v:3:4:4": 0.12741405091768473,
        "q:1024": 0.20786430601211017,
        "q:108": -0.14272215520975123,
        "q:128": 0.11481356898268109,
        "q:144": 0.081271192380519372,
        "q:162": -0.26834639968140317,
        "q:192": 0.059635929993877845,
        "q:216": -0.12376530065855411,
        "q:243": -0.59632883446842111,
        "q:256": 0.0045361785764211487,
        "q:288": 0.13527347939227019,
        "q:32": 0.49575895497431022,
        "q:324": -0.41224012361861018,
        "q:384": -0.22278468433209481,
        "q:432": -0.23713621009485858,
        "q:48": 0.41885598484756642,
        "q:512": -0.02455535060115277,
        "q:576": -0.15691493459039171,
        "q:64": 0.3484608400652312,
        "q:72": 0.03718640409418178,
        "q:768": 0.0048383322118078515,
        "q:96": 0.20670589129586711,
        "returns:0": 0.5114042432659579,
        "returns:1": -0.16372693327073276,
        "returns:2": -0.057706176144373678,
        "returns:3": -0.048904942475131781,
        "returns:4": -0.30430250146606919,
        "rough:0": 0.10951247001666446,
        "rough:1": -0.1476532504606084,
        "rough:10": -0.41673966321525635,
        "rough:11": 0.12360405678455176,
        "rough:12": 0.0041241906682679755,
        "rough:2": -0.24245942155932287,
        "rough:3": 0.17879274088458988,
        "rough:4": 0.25479587440803086,
        "rough:5": -0.20716870282456054,
        "rough:6": 0.079952241230338797,
        "rough:7": -0.16919890447354105,
        "rough:8": -0.32599590646096932,
        "rough:9": 0.76072571344689188,
        "runs:0:0:6": -0.19127377069213689,
        "runs:0:1:1": -0.26769096977786799,
        "runs:0:1:2": 0.27902036072604991,
        "runs:0:1:3": -0.19479800484874488,
        "runs:0:1:4": 0.68065718691591681,
        "runs:0:1:5": -0.20401508025049808,
        "runs:0:2:1": -0.40710823212975139,
        "runs:0:2:2": -0.22383418822095524,
        "runs:0:2:3": 0.15449404604054909,
        "runs:0:2:4": -0.21885515307499784,
        "runs:0:3:1": 0.25626024284108168,
        "runs:0:3:2": -0.44586797324640115,
        "runs:0:3:3": -0.21836363653077645,
        "runs:0:4:1": -0.33431265042742098,
        "runs:0:4:2": 0.47978585120443967,
        "runs:0:5:1": -0.2139540526901933,
        "runs:0:6:0": 0.24000183812184844,
        "runs:1:0:1": -0.22044480835515992,
        "runs:1:0:2": 0.25037602730000602,
        "runs:1:0:3": 0.32128626652634656,
        "runs:1:0:4": -0.1218651052224219,
        "runs:1:0:5": -0.028108919836934282,
        "runs:1:1:0": 0.18254454000914666,
        "runs:1:1:1": 0.39470344764031412,
        "runs:1:1:2": -0.54469505435128107,
        "runs:1:1:3": -0.032819708592137793,
        "runs:1:1:4": -0.34903751509040237,
        "runs:1:2:0": 0.5238367189573383,
        "runs:1:2:1": 0.040145144994010229,
        "runs:1:2:2": -0.81380668201028183,
        "runs:1:2:3": -0.71545572569078997,
        "runs:1:3:0": 0.4123167954270755,
        "runs:1:3:1": 0.5347580125784257,
        "runs:1:3:2": -0.095979551208216274,
        "runs:1:4:0": -0.14643200322767902,
        "runs:1:4:1": 0.18789190740786829,
        "runs:1:5:0": 0.18839936034040322,
        "runs:2:0:1": -0.240721227238513,
        "runs:2:0:2": 0.0061537683368472085,
        "runs:2:0:3": -0.34424180120427977,
        "runs:2:0:4": -0.45299756382065709,
        "runs:2:1:0": 0.14471686045918689,
        "runs:2:1:1": 0.34632522243561426,
        "runs:2:1:2": -0.13649036623590607,
        "runs:2:1:3": 0.39408962440192152,
        "runs:2:2:0": 0.10281881663194535,
        "runs:2:2:1": -0.014518985830632278,
        "runs:2:2:2": 0.34604224574427939,
        "runs:2:3:0": -0.50143360248913982,
        "runs:2:3:1": 0.22568360052453759,
        "runs:2:4:0": 0.017704654007247578,
        "runs:3:0:1": -0.054844702466390838,
        "runs:3:0:2": 0.58302557315068526,
        "runs:3:0:3": 0.2643370456900262,
        "runs:3:1:0": 0.097236346134176518,
        "runs:3:1:1": -0.30904713940014267,
        "runs:3:1:2": -0.37553839099377628,
        "runs:3:2:0": 0.18747828475585876,
        "runs:3:2:1": 0.43437346617426353,
        "runs:3:3:0": -0.25427005187430307,
        "runs:4:0:1": -0.13703899723227442,
        "runs:4:0:2": 0.12408297372336062,
        "runs:4:1:0": -0.55202350059417404,
        "runs:4:1:1": 0.42990296502269071,
        "runs:4:2:0": 0.55581931681431418,
        "runs:5:0:1": 0.24426913151967453,
        "runs:5:1:0": -0.21735613438494772,
        "runs:6:0:0": -0.14772037979944078,
        "shape:0:0:0:1": -0.19127377069213689,
        "shape:10:0:0:2": 0.19169705192579864,
        "shape:10:0:0:3": -0.19806925128175301,
        "shape:10:0:1:3": -1.0062005486036814,
        "shape:10:0:2:3": 0.71937542183165104,
        "shape:10:1:0:2": -0.34857446782507456,
        "shape:10:1:1:3": -0.088130311332680067,
        "shape:10:1:2:3": 0.66362868446175038,
        "shape:10:1:3:3": 0.029228021948922933,
        "shape:10:2:0:2": 0.44789970202983931,
        "shape:10:2:3:3": -0.1473693842252643,
        "shape:10:3:0:2": 0.01925741776277038,
        "shape:10:3:3:3": -0.82112710441879178,
        "shape:10:3:4:3": 0.78754412183706757,
        "shape:11:0:0:3": -0.49736213489065628,
        "shape:11:0:1:3": 0.021552801905530612,
        "shape:11:1:0:3": 1.6294574273785458,
        "shape:11:1:1:3": -0.10417106627395036,
        "shape:11:1:2:3": -1.4445380636821068,
        "shape:11:2:0:3": -0.41341925287401049,
        "shape:11:2:1:3": 0.42231017986968883,
        "shape:11:2:2:3": 0.096494071169720794,
        "shape:11:3:1:3": 0.22659543317313699,
        "shape:11:3:2:3": 0.054663625374685804,
        "shape:12:0:0:2": -0.17687715601538462,
        "shape:12:0:1:2": 0.12408297372336062,
        "shape:12:0:2:2": -0.42222369678456489,
        "shape:12:1:0:2": 0.1715506304175036,
        "shape:12:1:3:2": -0.16454931901640063,
        "shape:12:2:0:2": 0.13407494104962134,
        "shape:12:2:3:2": 0.68452019648694418,
        "shape:12:2:4:2": -0.25673587536390358,
        "shape:12:3:4:2": 0.32727228275632608,
        "shape:12:4:0:2": 0.18254454000914666,
        "shape:13:0:0:3": 0.61262320574952389,
        "shape:13:0:1:3": -0.085342230328596932,
        "shape:13:1:1:3": -0.57671485582471271,
        "shape:13:1:2:3": 0.84769920524774245,
        "shape:13:2:2:3": -0.46092608101577393,
        "shape:14:0:0:2": 0.10006444468419358,
        "shape:14:1:0:2": 1.4038396902710435,
        "shape:14:2:0:2": -0.83667047738212108,
        "shape:14:3:0:2": -0.62417564549682614,
        "shape:15:0:1:2": 0.24426913151967453,
        "shape:15:1:2:2": 0.31228766054045431,
        "shape:16:0:0:2": -0.21735613438494772,
        "shape:16:1:0:2": 0.31279989774194866,
        "shape:18:0:0:1": -0.14772037979944078,
        "shape:1:0:0:2": -0.20401508025049808,
        "shape:1:1:0:2": -0.26998627588319518,
        "shape:2:0:0:2": -0.34434011747102156,
        "shape:2:1:0:2": -0.12399524076128643,
        "shape:2:2:0:2": 1.0796747150640147,
        "shape:2:3:0:2": -0.8034028066765192,
        "shape:3:0:0:2": -0.48985141555415962,
        "shape:3:0:1:2": -0.028108919836934282,
        "shape:3:1:0:2": 0.9577288695463374,
        "shape:3:1:2:2": -0.29808322749754029,
        "shape:3:2:0:2": -0.1706874534530109,
        "shape:3:4:0:2": -0.26769096977786799,
        "shape:4:0:0:2": 0.2492801753175766,
        "shape:4:0:0:3": -0.066811289691164261,
        "shape:4:0:1:3": 0.24096583764971427,
        "shape:4:1:0:2": -0.26779719799712004,
        "shape:4:1:1:3": -0.66647982902125591,
        "shape:4:1:2:3": 0.31252462525841129,
        "shape:4:2:0:2": -0.11684541652711265,
        "shape:4:2:2:3": -0.061531943169874988,
        "shape:4:3:0:2": -0.13294294611664506,
        "shape:5:0:0:2": -0.2139540526901933,
        "shape:5:0:0:3": 0.80332437990970507,
        "shape:5:0:1:3": -0.19201795260636306,
        "shape:5:1:0:2": 0.23679860661105526,
        "shape:5:1:0:3": -1.0977793385062866,
        "shape:5:1:1:3": -0.14241141784081018,
        "shape:5:1:2:3": 0.093180643996217866,
        "shape:5:2:0:3": -0.03909419513880584,
        "shape:5:2:1:3": -0.18089815647838731,
        "shape:5:2:2:3": -0.10834868239273047,
        "shape:5:3:1:3": 0.52545397369760949,
        "shape:5:3:2:3": 0.22001265964341665,
        "shape:6:0:0:1": 0.24000183812184844,
        "shape:6:0:0:3": 0.19065731723600776,
        "shape:6:0:1:2": -0.45299756382065709,
        "shape:6:0:1:3": 0.452591334813225,
        "shape:6:0:2:2": 0.6503020536432238,
        "shape:6:1:0:3": 0.95624634825733945,
        "shape:6:1:1:3": -0.05507792412129793,
        "shape:6:1:2:3": -0.8980903462318186,
        "shape:6:1:3:2": 0.059638290095233373,
        "shape:6:2:0:3": -0.2610884107759569,
        "shape:6:2:1:3": -0.093461327541028302,
        "shape:6:2:3:2": 0.18312636876692098,
        "shape:6:2:4:2": -0.31662671002311477,
        "shape:6:3:0:3": -0.34283555522746423,
        "shape:6:3:4:2": -0.35654560235107258,
        "shape:7:0:0:3": -0.23165184404929731,
        "shape:7:0:1:3": -0.61816389948465367,
        "shape:7:0:2:3": 1.0627001443671267,
        "shape:7:1:0:3": -0.40629406754816455,
        "shape:7:1:1:3": 0.24647399602075207,
        "shape:7:1:2:3": 0.53424215541286912,
        "shape:7:1:3:3": -1.4072621620750263,
        "shape:7:2:0:3": 0.86805826223464877,
        "shape:7:2:3:3": -0.31195165250575918,
        "shape:7:3:3:3": 1.0496092060681339,
        "shape:7:3:4:3": -0.63099407331972091,
        "shape:8:0:0:2": 0.18839936034040322,
        "shape:8:0:0:3": -0.080095237197562855,
        "shape:8:0:1:3": 0.53131948374329274,
        "shape:8:0:2:3": 0.3706040411415909,
        "shape:8:1:0:2": -0.20836420669486583,
        "shape:8:1:1:3": -0.086981971299548697,
        "shape:8:1:2:3": -0.68405553055744217,
        "shape:8:2:0:3": -0.19442443908471799,
        "shape:8:2:1:3": 0.10552293926356716,
        "shape:8:2:2:3": -0.56277444549153111,
        "shape:8:2:3:3": 0.59385555296957437,
        "shape:9:0:0:3": -0.75535154743650956,
        "shape:9:0:1:2": 0.2643370456900262,
        "shape:9:0:1:3": 0.62276144259704724,
        "shape:9:0:2:2": -0.67511711372406158,
        "shape:9:0:3:2": -0.096559259342718806,
        "shape:9:1:0:3": -0.36628900330734099,
        "shape:9:1:1:3": 0.57626292161094972,
        "shape:9:1:2:3": -0.14551836547936547,
        "shape:9:1:3:2": 0.27343103330686097,
        "shape:9:2:0:3": -0.45447092832651897,
        "shape:9:2:1:3": -0.040555107972954668,
        "shape:9:2:3:2": 0.15641394108649229,
        "shape:9:2:4:2": 0.19595425322674984,
        "shape:9:3:0:3": 0.44032218909237641,
        "shape:9:4:5:2": -0.22044480835515992,
        "sum:10": 0.49575895497431022,
        "sum:11": 0.41885598484756642,
        "sum:12": 0.37456376297979782,
        "sum:13": 0.060209657502449887,
        "sum:14": -0.057735002942604974,
        "sum:15": -0.60346064334782912,
        "sum:16": -0.23537273291527033,
        "sum:17": -0.45214351012455517,
        "sum:18": -0.17906108972793267,
        "sum:19": 0.0048383322118078515,
        "sum:20": 0.20786430601211017,
        "sum_disp:10:0": 0.49575895497431022,
        "sum_disp:11:1": 0.58401384920365007,
        "sum_disp:11:2": -0.15669766596743054,
        "sum_disp:12:1": 0.27244231802692709,
        "sum_disp:12:2": 0.44716918634326963,
        "sum_disp:12:3": 0.11045302848831638,
        "sum_disp:12:4": -0.44241337034303313,
        "sum_disp:13:1": -0.082123464128013399,
        "sum_disp:13:2": 0.40842775534630987,
        "sum_disp:13:3": 0.99308071524013419,
        "sum_disp:13:4": -0.10450882479052816,
        "sum_disp:13:5": -0.38265819680852414,
        "sum_disp:13:6": -0.8066174792354025,
        "sum_disp:14:1": -0.39282443426399105,
        "sum_disp:14:2": -0.58159569630997288,
        "sum_disp:14:3": -0.50053741546756481,
        "sum_disp:14:4": 0.39344591643924653,
        "sum_disp:14:5": 0.37635685755394521,
        "sum_disp:14:6": 0.14591755497885786,
        "sum_disp:14:8": 0.46433905857884566,
        "sum_disp:15:0": -0.59632883446842111,
        "sum_disp:15:2": -0.52557174638866733,
        "sum_disp:15:3": 0.11739536246974279,
        "sum_disp:15:4": 0.018249498903137602,
        "sum_disp:15:5": 0.26234647430482677,
        "sum_disp:15:6": -0.064647111491112033,
        "sum_disp:15:7": 0.12360405678455176,
        "sum_disp:16:1": -0.38991242874047777,
        "sum_disp:16:2": -0.21226789654661726,
        "sum_disp:16:3": -0.56591215503697245,
        "sum_disp:16:4": -0.15480822124013291,
        "sum_disp:16:5": 0.75653981067790421,
        "sum_disp:16:6": 0.73481103555776495,
        "sum_disp:16:8": -0.46245504672842547,
        "sum_disp:17:1": -0.56863581250321138,
        "sum_disp:17:2": 0.42799430008941292,
        "sum_disp:17:3": 0.48680345450435181,
        "sum_disp:17:4": 0.23691601257411513,
        "sum_disp:17:5": -1.2043154322626601,
        "sum_disp:17:6": 0.14414732612784514,
        "sum_disp:18:1": -0.50752729116136763,
        "sum_disp:18:2": 0.82335803310427058,
        "sum_disp:18:3": -0.92204477185872935,
        "sum_disp:18:4": 0.41367642373090358,
        "sum_disp:19:1": 0.5123339079239595,
        "sum_disp:19:2": -0.50712347868696384,
        "sum_disp:20:0": 0.20786430601211017,
        "sum_var:10:0": 0.49575895497431022,
        "sum_var:11:20": 0.41885598484756642,
        "sum_var:12:30": 0.03718640409418178,
        "sum_var:12:80": 0.3484608400652312,
        "sum_var:13:30": -0.14272215520975123,
        "sum_var:13:80": 0.20670589129586711,
        "sum_var:14:120": 0.11481356898268109,
        "sum_var:14:20": -0.26834639968140317,
        "sum_var:14:70": 0.081271192380519372,
        "sum_var:15:0": -0.59632883446842111,
        "sum_var:15:100": 0.059635929993877845,
        "sum_var:15:50": -0.12376530065855411,
        "sum_var:16:120": 0.0045361785764211487,
        "sum_var:16:20": -0.41224012361861018,
        "sum_var:16:70": 0.13527347939227019,
        "sum_var:17:30": -0.23713621009485858,
        "sum_var:17:80": -0.22278468433209481,
        "sum_var:18:30": -0.15691493459039171,
        "sum_var:18:80": -0.02455535060115277,
        "sum_var:19:20": 0.0048383322118078515,
        "sum_var:20:0": 0.20786430601211017,
        "switches:0": -0.094805684739304161,
        "switches:1": 0.20560013755280232,
        "switches:2": 0.20953374057759036,
        "switches:3": 0.085657313431693763,
        "switches:4": -0.24419137024427248,
        "switches:5": -0.22044480835515992,
        "tri_o:0:0:0:0": -0.90974549658077342,
        "tri_o:0:0:0:1": -0.23080089713694901,
        "tri_o:0:0:0:3": -0.19118577670674441,
        "tri_o:0:0:1:0": -0.18070708676936387,
        "tri_o:0:0:1:1": -0.017327994181903634,
        "tri_o:0:0:1:3": -0.25678652368984956,
        "tri_o:0:0:3:0": -0.76395261589488794,
        "tri_o:0:0:3:1": -0.25544476460450666,
        "tri_o:0:0:3:3": 0.67209124883628879,
        "tri_o:0:1:0:0": -0.091727308778517855,
        "tri_o:0:1:0:1": -0.16021969196600822,
        "tri_o:0:1:0:3": -0.025387263204849193,
        "tri_o:0:1:1:0": -0.27097452764870644,
        "tri_o:0:1:1:1": 0.45064740819113291,
        "tri_o:0:1:1:3": 0.16025135113594216,
        "tri_o:0:1:3:0": 0.43046320221651063,
        "tri_o:0:1:3:1": -0.093336950958026313,
        "tri_o:0:1:3:3": 0.062690876477458468,
        "tri_o:0:3:0:0": 0.30687966354634977,
        "tri_o:0:3:0:1": 0.18686311515345042,
        "tri_o:0:3:0:3": -0.4361545470940007,
        "tri_o:0:3:1:0": -0.23096803035216584,
        "tri_o:0:3:1:1": 0.14703159402478622,
        "tri_o:0:3:1:3": 0.56699696903983643,
        "tri_o:0:3:3:0": 0.42541563720263248,
        "tri_o:0:3:3:1": 0.2717963740282765,
        "tri_o:0:3:3:3": 0.40352627481864817,
        "tri_o:1:0:0:0": -0.65134159979613349,
        "tri_o:1:0:0:1": -0.10844641302669927,
        "tri_o:1:0:0:3": 0.063407311785171769,
        "tri_o:1:0:1:0": -0.13765722873472855,
        "tri_o:1:0:1:1": 0.25841400823309185,
        "tri_o:1:0:1:3": -0.32447064772123546,
        "tri_o:1:0:3:0": -0.43052786312942914,
        "tri_o:1:0:3:1": 0.097762754790787276,
        "tri_o:1:0:3:3": -0.31484525167601246,
        "tri_o:1:1:0:0": -0.47187515417940157,
        "tri_o:1:1:0:1": -0.25124442642376171,
        "tri_o:1:1:0:3": 0.041869285705696889,
        "tri_o:1:1:1:0": 0.12442582876083665,
        "tri_o:1:1:1:1": 0.098257697492777421,
        "tri_o:1:1:1:3": 0.35769902364997647,
        "tri_o:1:1:3:0": 0.3641052237892573,
        "tri_o:1:1:3:1": 0.085313995180113691,
        "tri_o:1:1:3:3": 0.019513026218871535,
        "tri_o:1:3:0:0": 0.12433441951202599,
        "tri_o:1:3:0:1": 0.055905709397941664,
        "tri_o:1:3:0:3": -0.076673587555846884,
        "tri_o:1:3:1:0": -0.22116675841127045,
        "tri_o:1:3:1:1": -0.16890732407073999,
        "tri_o:1:3:1:3": 0.31446777281800059,
        "tri_o:1:3:3:0": -0.059295279613938739,
        "tri_o:1:3:3:1": 0.26605320654177123,
        "tri_o:1:3:3:3": 0.92207109572807644,
        "tri_o:2:0:0:0": -0.72857239578083199,
        "tri_o:2:0:0:1": -0.48956786373506117,
        "tri_o:2:0:0:3": 0.2137914535743036,
        "tri_o:2:0:1:0": 0.036504155949158915,
        "tri_o:2:0:1:1": -0.08301556816137369,
        "tri_o:2:0:1:3": -0.26004050772601323,
        "tri_o:2:0:3:0": -0.65125074036538666,
        "tri_o:2:0:3:1": 0.16072733698246969,
        "tri_o:2:0:3:3": 0.51295506589651163,
        "tri_o:2:1:0:0": -0.021731265412860738,
        "tri_o:2:1:0:1": 0.28091580599459992,
        "tri_o:2:1:0:3": -0.49587265500604644,
        "tri_o:2:1:1:0": -0.19983286135682041,
        "tri_o:2:1:1:1": 0.42736553356600648,
        "tri_o:2:1:1:3": -0.045346515556780466,
        "tri_o:2:1:3:0": 0.37383200436690561,
        "tri_o:2:1:3:1": -0.46303553637276723,
        "tri_o:2:1:3:3": 0.41502614496688711,
        "tri_o:2:3:0:0": -0.2668604727587166,
        "tri_o:2:3:0:1": -0.22739343700583955,
        "tri_o:2:3:0:3": 0.35986818554745753,
        "tri_o:2:3:1:0": -0.21804849202088541,
        "tri_o:2:3:1:1": -0.16510515653191818,
        "tri_o:2:3:1:3": 0.81427999125592487,
        "tri_o:2:3:3:0": 0.22186795967915035,
        "tri_o:2:3:3:1": 0.77713928792232267,
        "tri_o:2:3:3:3": -0.37862402066656797,
        "tri_o:3:0:0:0": -0.40667498083196574,
        "tri_o:3:0:0:1": -0.3157770163900826,
        "tri_o:3:0:0:3": -0.29276437196520139,
        "tri_o:3:0:1:0": -0.038726458969169673,
        "tri_o:3:0:1:1": 0.18835592521611405,
        "tri_o:3:0:1:3": -0.58695949923151458,
        "tri_o:3:0:3:0": -0.25350488994450343,
        "tri_o:3:0:3:1": 0.099265517774722978,
        "tri_o:3:0:3:3": 0.22857034531098386,
        "tri_o:3:1:0:0": -0.01569514111533106,
        "tri_o:3:1:0:1": -0.35607077991448494,
        "tri_o:3:1:0:3": -0.0040436153198213191,
        "tri_o:3:1:1:0": 0.013543005223556144,
        "tri_o:3:1:1:1": 0.22500228877068057,
        "tri_o:3:1:1:3": -0.052306667701374474,
        "tri_o:3:1:3:0": 0.072881990582475728,
        "tri_o:3:1:3:1": 0.31714246862784495,
        "tri_o:3:1:3:3": 0.12653473662595893,
        "tri_o:3:3:0:0": 0.36958980383016404,
        "tri_o:3:3:0:1": -0.048341484116064121,
        "tri_o:3:3:0:3": -0.36665208212632483,
        "tri_o:3:3:1:0": 0.45599410095783882,
        "tri_o:3:3:1:1": -0.21197139239680593,
        "tri_o:3:3:1:3": 0.24689890016215357,
        "tri_o:3:3:3:0": 0.62706706693973358,
        "tri_o:3:3:3:1": -0.027890044322593351,
        "tri_o:3:3:3:3": -0.050284630710721999,
        "v2:0": -1.1642888047261959,
        "v2:1": -0.45101915346399241,
        "v2:2": 0.0038184026982296436,
        "v2:3": 0.34385641518149584,
        "v2:4": 0.74963202118306416,
        "v2:5": 0.49575895497431022,
        "v4:0": -0.03669171194611183,
        "v4:1": 0.11504983667885382,
        "v4:2": 0.0779930059397657,
        "v4:3": -0.36106511948167519,
        "v4:4": -0.019304732979501932,
        "v4:5": 0.20786430601211017,
        "var25:0": 0.10951247001666446,
        "var25:100": 0.059635929993877845,
        "var25:120": 0.12112493431303899,
        "var25:20": -0.23791656826641769,
        "var25:30": -0.47494453748682486,
        "var25:50": -0.12376530065855411,
        "var25:70": 0.21124593023070362,
        "var25:80": 0.30126061843185487,
        "vp:0:2": 1.0876023325399229,
        "vp:0:3": -1.3207051811757584,
        "vp:0:4": 0.2089505819822477,
        "vp:1:2": 1.0907277459197591,
        "vp:1:3": -1.0118960073433358,
        "vp:1:4": -0.095257007867720747,
        "vp:2:2": 1.1373601524882813,
        "vp:2:3": -0.96150044329525819,
        "vp:2:4": -0.19335720573637474,
        "vp:3:2": 1.0452046754133497,
        "vp:3:3": -1.2418373337812523,
        "vp:3:4": 0.16463154001104904,
        "vp:4:2": 1.2500899623397181,
        "vp:4:3": -1.280832968131979,
        "vp:4:4": 0.0053972904341554884,
        "wins:0": -0.80171471067254174,
        "wins:1": -0.69081710319236656,
        "wins:2": 0.14692521224719723,
        "wins:3": 0.16536677940834643,
        "wins:4": 0.65930064229998797,
        "wins:5": 0.64873135281722683,
        "wins:6": -0.14772037979944078,
        "wr:0": -0.80171471067254174,
        "wr:1": -0.024498466096396249,
        "wr:2": -0.057419331270396307,
        "wr:3": 0.55493382064814956,
        "wr:4": 0.41905754311442389,
        "wr:5": 0.027786524970412105,
        "wr:6": -0.14772037979944078,
    ]
}

/// V8联合150：对六场729种彩果统一排名，固定保留前150种。
/// 排名只读取本次赛前概率、ABCD和通用V7结构条件，不读取期号、场次号或赛果。
private enum Joint150V8Model {
    static let version = "JOINT150-P55-A45-V7B05-K150-V1"
    static let configurationMarker = 8.150
    static let keptCount = 150

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func selectTop(
        _ expanded: [[Int]],
        logic: [LogicMapping],
        probabilities: [[Double]]?
    ) -> [[Int]] {
        guard !expanded.isEmpty else { return [] }
        let marketRows = normalizedProbabilityRows(probabilities, logic: logic)
        let raw = expanded.map { outcomes -> (outcomes: [Int], market: Double, abcd: Double, v7: Bool) in
            let firstFive = Array(outcomes.prefix(logic.count))
            let values = zip(logic, firstFive).map { $0.value(for: $1) }
            let market = zip(firstFive, marketRows).reduce(0.0) { partial, pair in
                let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                return partial + log(max(pair.1[index], 1e-15))
            }
            let abcd = -Double(values.filter { $0 == 3 }.count)
                - 2 * Double(values.filter { $0 == 4 }.count)
            return (outcomes, market, abcd, passesV7(outcomes, logic: logic))
        }
        let marketStats = meanAndDeviation(raw.map(\.market))
        let abcdStats = meanAndDeviation(raw.map(\.abcd))
        return raw.map { item -> (outcomes: [Int], score: Double) in
            let marketZ = (item.market - marketStats.mean) / marketStats.deviation
            let abcdZ = (item.abcd - abcdStats.mean) / abcdStats.deviation
            return (item.outcomes, 0.55 * marketZ + 0.45 * abcdZ + (item.v7 ? 0.5 : 0))
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 1e-12 { return left.score > right.score }
            return right.outcomes.lexicographicallyPrecedes(left.outcomes)
        }
        .prefix(keptCount)
        .map(\.outcomes)
    }

    private static func normalizedProbabilityRows(
        _ probabilities: [[Double]]?,
        logic: [LogicMapping]
    ) -> [[Double]] {
        if let probabilities,
           probabilities.count == logic.count,
           probabilities.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 >= 0 } && $0.reduce(0, +) > 0 }) {
            return probabilities.map { row in
                let total = row.reduce(0, +)
                return row.map { $0 / total }
            }
        }
        return logic.map { mapping in
            let inverse = mapping.values.map { 1 / Double($0) }
            let total = inverse.reduce(0, +)
            return inverse.map { $0 / total }
        }
    }

    private static func meanAndDeviation(_ values: [Double]) -> (mean: Double, deviation: Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, max(sqrt(variance), 1e-12))
    }

    private static func passesV7(_ fullOutcomes: [Int], logic: [LogicMapping]) -> Bool {
        let firstFive = Array(fullOutcomes.prefix(logic.count))
        let firstSix = Array(fullOutcomes.prefix(6))
        guard firstFive.count == 5, firstSix.count == 6 else { return false }
        let values = zip(logic, firstFive).map { $0.value(for: $1) }
        let sum = values.reduce(0, +)
        let displacement = zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
        let mean = Double(sum) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        let transition = markovProbability(values) * 100
        let roughness = values.indices.dropLast(2).reduce(0) {
            $0 + abs(values[$1] - 2 * values[$1 + 1] + values[$1 + 2])
        }
        let breakpoints = zip(firstFive, firstFive.dropFirst()).filter { $0 != $1 }.count
        guard (12...18).contains(sum), (2...7).contains(displacement),
              variance <= 1 + 1e-12, values.filter({ $0 == 2 }).count <= 3,
              transition + 1e-12 >= 0.04, roughness <= 8, (0...4).contains(breakpoints),
              OutcomeCondition.winLossSwitches.value(in: firstSix) <= 2 else { return false }

        let seven = fullOutcomes
        let primaryFailures = [
            ConsecutiveRunCondition.nonLoss,
            ConsecutiveRunCondition.nonDraw,
            ConsecutiveRunCondition.nonWin
        ].filter { !(5...7).contains($0.longestRun(in: seven)) }.count
        guard (2...3).contains(primaryFailures) else { return false }
        if zip(seven, seven.dropFirst()).contains(where: { $0 == 1 && $1 == 1 }) { return true }
        let sameFailures = [
            (ConsecutiveRunCondition.win, 2...4),
            (ConsecutiveRunCondition.draw, 2...3),
            (ConsecutiveRunCondition.loss, 2...3)
        ].filter { !$0.1.contains($0.0.longestRun(in: seven)) }.count
        return (2...3).contains(sameFailures)
    }

    static func passes(fullOutcomes: [Int], logic: [LogicMapping]) -> Bool {
        let target = Array(fullOutcomes.prefix(6))
        guard target.count == 6, logic.count == 5 else { return false }
        let seventh = fullOutcomes.count > 6 ? fullOutcomes[6] : 0
        let candidates = cartesianOutcomes(count: 6).map { $0 + [seventh] }
        return selectTop(candidates, logic: logic, probabilities: nil)
            .contains(target + [seventh])
    }

    private static func cartesianOutcomes(count: Int) -> [[Int]] {
        guard count > 0 else { return [[]] }
        return (0..<count).reduce([[]]) { partial, _ in
            partial.flatMap { prefix in [3, 1, 0].map { prefix + [$0] } }
        }
    }

    private static func markovProbability(_ values: [Int]) -> Double {
        let prior = [2: 0.45, 3: 0.30, 4: 0.25]
        let transitions: [Int: [Int: Double]] = [
            2: [2: 0.35, 3: 0.40, 4: 0.25],
            3: [2: 0.50, 3: 0.30, 4: 0.20],
            4: [2: 0.55, 3: 0.30, 4: 0.15]
        ]
        guard let first = values.first else { return 0 }
        return zip(values, values.dropFirst()).reduce(prior[first, default: 0]) {
            $0 * transitions[$1.0, default: [:]][$1.1, default: 0]
        }
    }
}

/// VIP3：六场729种彩果统一排名，固定保留前150种。
///
/// 运行时只读取六场对照表实际数值赔率、实际让球、联赛和原始彩果形态，
/// 不使用ABCD映射的2/3/4判定值。
/// 不读取期号、场次号、比分或开奖结果。参数由26091–26098历史样本拟合，
/// 因此历史命中率只是回测描述，不是未来保证。
private enum VIP3Joint150Model {
    static let version = "VIP3-SIX-REAL-HANDICAP-ODDS-LEAGUE-OUTCOME-SHAPE-K150-V3"
    static let configurationMarker = 7.153
    static let keptCount = 150

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func selectTop(
        _ expanded: [[Int]],
        firstFiveLogic _: [LogicMapping],
        context: VIP3MatchContext?
    ) -> [[Int]] {
        guard !expanded.isEmpty,
              let context,
              context.comparisonTableOdds.count == 6,
              context.handicaps.count == 6,
              context.leagues.count == 6,
              let probabilities = normalizedProbabilityRows(context.comparisonTableOdds) else {
            return []
        }
        let cluster = clusterIndex(
            probabilities: probabilities,
            handicaps: context.handicaps
        )
        let weights = clusterWeights[cluster]
        let raw = expanded.compactMap { outcomes -> (outcomes: [Int], market: Double, residual: Double, structure: Double, count: Double, shape: Double)? in
            let firstSix = Array(outcomes.prefix(6))
            guard firstSix.count == 6,
                  let structure = VIP2Joint150Model.outcomeStructureScore(
                    outcomes: firstSix
                  ) else { return nil }
            var market = 0.0
            var residual = 0.0
            for position in 0..<6 {
                let outcomeIndex = firstSix[position] == 3 ? 0 : (firstSix[position] == 1 ? 1 : 2)
                market += log(max(probabilities[position][outcomeIndex], 1e-15))
                residual += 1.235 * correction(leagueCorrections[context.leagues[position]], outcomeIndex)
                residual += 0.569 * correction(handicapCorrections[context.handicaps[position]], outcomeIndex)
            }
            let winCount = firstSix.filter { $0 == 3 }.count
            let drawCount = firstSix.filter { $0 == 1 }.count
            let lossCount = firstSix.filter { $0 == 0 }.count
            let directSwitches = zip(firstSix, firstSix.dropFirst()).filter { Set([$0.0, $0.1]) == Set([3, 0]) }.count
            let returns = firstSix.indices.dropFirst(2).filter {
                firstSix[$0] == firstSix[$0 - 2] && firstSix[$0] != firstSix[$0 - 1]
            }.count
            let changes = zip(firstSix, firstSix.dropFirst()).filter { $0.0 != $0.1 }.count
            let countExpert = -0.3 * Double(winCount) + 0.726 * Double(drawCount) - 0.4 * Double(lossCount)
            let shapeExpert = -0.313 * Double(directSwitches) - 0.452 * Double(returns) + 0.64 * Double(changes)
            return (firstSix, 3.725 * market, residual, structure, countExpert, shapeExpert)
        }
        guard raw.count == expanded.count else { return [] }
        let stats = meanAndDeviation(raw.map(\.structure))
        return raw.map { item -> (outcomes: [Int], score: Double) in
            let structureExpert = 0.206 * (item.structure - stats.mean) / stats.deviation
            let score = weights[0] * item.market
                + weights[1] * item.residual
                + weights[2] * structureExpert
                + weights[3] * item.count
                + weights[4] * item.shape
            return (item.outcomes, score)
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 1e-12 { return left.score > right.score }
            return right.outcomes.lexicographicallyPrecedes(left.outcomes)
        }
        .prefix(keptCount)
        .map(\.outcomes)
    }

    private static func normalizedProbabilityRows(_ odds: [[Double]]) -> [[Double]]? {
        guard odds.count == 6,
              odds.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else {
            return nil
        }
        return odds.map { row in
            let inverse = row.map { 1 / $0 }
            let total = inverse.reduce(0, +)
            return inverse.map { $0 / total }
        }
    }

    private static func clusterIndex(
        probabilities: [[Double]],
        handicaps: [Int]
    ) -> Int {
        let confidence = probabilities.reduce(0.0) { $0 + ($1.max() ?? 0) } / 6
        let handicap = handicaps.reduce(0.0) { $0 + Double(abs($1)) } / 6
        return (confidence >= 0.438 ? 4 : 0)
            + (handicap >= 0.5 ? 2 : 0)
    }

    private static func meanAndDeviation(_ values: [Double]) -> (mean: Double, deviation: Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, max(sqrt(variance), 1e-12))
    }

    private static func correction(_ row: [Double]?, _ outcomeIndex: Int) -> Double {
        guard let row, row.indices.contains(outcomeIndex) else { return 0 }
        return row[outcomeIndex]
    }

    /// 顺序：market、league/handicap/logic calibration、VIP2 structure、count、shape。
    private static let clusterWeights: [[Double]] = [
        [2.00, 4.50, 7.50, 0.91, 1.00],
        [2.00, 5.25, 2.00, 2.00, 1.12],
        [1.25, 3.94, 5.36, 1.25, 2.00],
        [2.00, 5.00, 2.14, 1.00, 1.00],
        [2.00, 0.88, 0.75, 1.36, 1.88],
        [1.00, 1.25, 1.50, 0.64, 1.00],
        [1.00, 4.12, 2.24, 1.00, 1.64],
        [0.97, 7.50, 5.50, 2.00, 2.00]
    ]

    private static let handicapCorrections: [Int: [Double]] = [
        -4: [-0.039220713153, -0.039220713153, 0.045689591934],
        -3: [0.084744926386, -0.060564221781, -0.069576523453],
        -2: [-0.030622802991, 0.102166072579, -0.025376616455],
        -1: [0.039853013565, 0.171863630020, -0.151539967870],
         0: [-0.082277420546, 0.097531507823, 0.008459255532],
         1: [-0.052803650682, 0.066314204030, 0.017521653386],
         2: [0.115909466354, -0.070414720409, -0.120083547149],
         3: [-0.029762672514, 0.025764537560, 0.018051611013],
         4: [-0.019802627296, 0.093458761112, -0.019802627296]
    ]

    private static let logicCorrections: [String: [Double]] = [
        "A": [0.014776228757, -0.000833392340, -0.028417548055],
        "B": [-0.029025441713, 0.161158395507, -0.101338184070],
        "C": [-0.047656011867, 0.119960892177, -0.038232808891],
        "D": [-0.367694422776, -0.011272634540, 0.160040041306]
    ]

    private static let leagueCorrections: [String: [Double]] = [
        "J1联赛": [0.087832685848, -0.079069975693, -0.030545874592],
        "J2联赛": [-0.074400024515, 0.093861492434, -0.001818869708],
        "K1联赛": [-0.220648836629, 0.354577639313, -0.124458623161],
        "K2联赛": [0.003057835189, -0.090693855875, 0.056158054357],
        "U21欧预赛": [-0.056474508008, -0.120538305178, 0.132175063399],
        "丹甲": [-0.068796761948, 0.304767350474, -0.211131331404],
        "丹超": [-0.103575634911, -0.000313293984, 0.091497951337],
        "丹麦杯": [-0.037235868987, 0.009716702874, 0.026707598752],
        "亚冠精英联赛": [0.046945719165, -0.077410915386, -0.014188004129],
        "亚运女足": [-0.076865200895, 0.286472612499, -0.117356518272],
        "亚运男足": [0.007968499057, 0.014444206188, -0.020634194597],
        "冰岛超": [0.202811130456, -0.118130914122, -0.150908841642],
        "南俱杯": [0.115758718200, 0.073140286575, -0.236388778064],
        "友谊赛": [0.023309318245, -0.020443345392, -0.013054057859],
        "墨超": [-0.121507017561, 0.189338856229, -0.017084813709],
        "奥乙": [0.052802855341, 0.102372494740, -0.128684413031],
        "奥地利杯": [-0.182321556794, -0.051687591128, 0.197006659265],
        "奥甲": [0.132774512272, -0.162072148346, -0.072369433572],
        "巴西乙": [0.098941762919, -0.185086928320, 0.022059730315],
        "巴西杯": [-0.003884509780, 0.009069260593, -0.004051017290],
        "巴西甲": [-0.088592686634, 0.067784882443, 0.045387413367],
        "希腊杯": [-0.182321556794, 0.158733455828, 0.069424497015],
        "希腊超": [0.028887271275, 0.011121127142, -0.044659889837],
        "德乙": [0.007895102057, 0.095332162070, -0.081156130863],
        "德国杯": [-0.032789822823, 0.142021583395, -0.032789822823],
        "德甲": [0.138966144417, -0.280538257385, -0.019724347312],
        "意乙": [0.009024156346, 0.146453782555, -0.156330513046],
        "意大利杯": [-0.031813965143, -0.004469176472, 0.047943224739],
        "意甲": [-0.094191625498, 0.192434700271, -0.064940396176],
        "挪甲": [-0.003555285293, 0.207718426971, -0.130639890963],
        "挪超": [0.107946412589, -0.028543803619, -0.132117635171],
        "捷克甲": [0.074571810833, -0.081484604814, -0.023158189078],
        "日联杯": [-0.064538521138, -0.064538521138, 0.095755564794],
        "智利甲": [0.101300177442, -0.081269352010, -0.063097690588],
        "欧冠联赛": [-0.059867875660, 0.268921040172, -0.131823602594],
        "欧国联": [-0.334989887371, 0.214322197866, 0.105175845635],
        "欧罗巴联赛": [-0.085003259389, 0.000351709311, 0.077040129682],
        "比乙": [-0.019697719486, 0.150481719822, -0.090783101051],
        "比甲": [0.011541291595, 0.206388928640, -0.170751280669],
        "法乙": [-0.019627108314, 0.022378102555, 0.002971244041],
        "法甲": [0.140720013865, -0.053093131081, -0.139378227863],
        "波兰杯": [0.010370983134, -0.064538521138, 0.036049040645],
        "波兰甲": [-0.052167944639, 0.065349331041, 0.007795724115],
        "洲际杯": [0.058749633977, -0.032789822823, -0.032789822823],
        "爱甲": [-0.062679012773, 0.081654317373, 0.011771164298],
        "爱超": [-0.125833826178, 0.158362897766, 0.004564848116],
        "爱足总杯": [0.025491476420, -0.006341402213, -0.027749649909],
        "瑞典甲": [-0.246496695685, -0.107398988872, 0.283388245331],
        "瑞典超": [-0.008315775921, 0.008563540747, 0.003058690120],
        "瑞士甲": [0.091760255974, -0.062349225849, -0.052733554858],
        "瑞士超": [-0.180943760923, -0.106365874953, 0.219113723753],
        "罗甲": [0.240541556205, -0.201988462263, -0.161173657771],
        "罗马尼亚杯": [-0.125163142954, -0.008958356242, 0.103178348328],
        "美公杯": [0.008817493882, -0.064538521138, 0.041362940620],
        "美职": [-0.032911163177, 0.145986653657, -0.068465129891],
        "芬兰杯": [0.038791289992, -0.032789822823, -0.032789822823],
        "芬甲": [-0.023145616746, -0.057490078998, 0.052787688741],
        "芬超": [-0.089167686036, 0.238103952934, -0.108477254786],
        "苏冠": [-0.042035738809, -0.004169006557, 0.054642563871],
        "苏联赛杯": [-0.017198778892, 0.031453258356, -0.002582496218],
        "苏超": [-0.150871424074, 0.169155609310, 0.023838439083],
        "英乙": [0.028305221023, 0.411137942587, -0.518533919726],
        "英冠": [0.028642368588, 0.062578574759, -0.090721006972],
        "英甲": [-0.104807716238, 0.028624708038, 0.084046715774],
        "英联杯": [0.114567435907, 0.052739342977, -0.134557608841],
        "英超": [-0.493169458109, 0.306541688465, 0.134541601538],
        "英锦赛": [0.040282995499, -0.047526394730, -0.010763005834],
        "荷乙": [0.211655271831, 0.011558237534, -0.256341803825],
        "荷甲": [-0.262463165734, 0.036479118120, 0.192269098971],
        "葡甲": [0.021533409367, -0.069127001628, 0.032950045355],
        "葡超": [-0.246092440190, 0.124700565300, 0.139890147559],
        "西乙": [-0.024718258517, -0.136880533143, 0.123684880438],
        "西甲": [0.009633660376, -0.030315053629, 0.011080256378],
        "解放者杯": [0.004436168684, -0.128663676673, 0.094719521207],
        "阿根廷杯": [-0.125163142954, 0.155488902023, -0.045722784760],
        "阿职联": [0.072318258086, 0.005751663207, -0.091433086437]
    ]
}

/// V9让球欧赔和值/积值：作为条件Tab当前其他条件之后的追加层。
/// 只读取本次前5场由普通欧赔＋让球数经项目对照表换算的三项赔率，
/// 与自定义赔率积/和共用同一数值矩阵，然后应用
/// 全局固定区间。不读取期号、场次、记录ID或具体赛果特例。
private enum HandicapOddsV9Model {
    static let version = "HANDICAP-ODDS-TABLE-SUM-PRODUCT-CURRENT-CONDITIONS-LOIO236-V3"
    static let configurationMarker = 9.509
    static let sumRange = 12.42...16.37
    static let productRange = 85.05...306.71

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func metrics(
        outcomes: [Int],
        comparisonTableOdds: [[Double]]?
    ) -> (sum: Double, product: Double)? {
        guard outcomes.count >= 5,
              let comparisonTableOdds,
              comparisonTableOdds.count == 5 else { return nil }
        var odds: [Double] = []
        odds.reserveCapacity(5)
        for (outcome, row) in zip(outcomes.prefix(5), comparisonTableOdds) {
            guard row.count == 3,
                  row.allSatisfy({ $0.isFinite && $0 > 1 }) else { return nil }
            let index = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
            odds.append(row[index])
        }
        return (odds.reduce(0, +), odds.reduce(1, *))
    }

    static func passes(outcomes: [Int], comparisonTableOdds: [[Double]]?) -> Bool {
        guard let metrics = metrics(
            outcomes: outcomes,
            comparisonTableOdds: comparisonTableOdds
        ) else {
            return false
        }
        return sumRange.contains(metrics.sum) && productRange.contains(metrics.product)
    }
}

/// V10：按ABCD逻辑映射出的五场结构判定值2/3/4；
/// 这不是赔率积/和，不得冒称用户的让球赔率对照表。
/// 应用乘积Q和和值S硬过滤。V8联合评分前150注为可选预筛选，默认关闭。
private enum ProductSumV10Model {
    static let version = "V10-ABCD-Q50-299-S12-16-OPTIONAL-V8TOP150-V2"
    static let configurationMarker = 9.510
    static let productRange = 50...299
    static let sumRange = 12...16

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func passesProductAndSum(outcomes: [Int], logic: [LogicMapping]) -> Bool {
        guard outcomes.count >= logic.count, logic.count == 5 else { return false }
        let values = zip(logic, outcomes.prefix(5)).map { $0.value(for: $1) }
        return productRange.contains(values.reduce(1, *))
            && sumRange.contains(values.reduce(0, +))
    }

    static func passes(
        fullOutcomes: [Int],
        logic: [LogicMapping],
        top150Enabled: Bool
    ) -> Bool {
        (!top150Enabled || Joint150V8Model.passes(fullOutcomes: fullOutcomes, logic: logic))
            && passesProductAndSum(outcomes: fullOutcomes, logic: logic)
    }
}

struct CompressedRecord: Sendable {
    let options: [[Int]]
    let sourceRecords: [SequenceRecord]

    var compactNotation: String {
        options.map { option in
            if option.count == 1 { return String(option[0]) }
            return "(\(option.map(String.init).joined()))"
        }.joined()
    }

    func labeledNotation(
        matchNumbers: [String],
        extraMatches: [ExtraMatchSelection] = []
    ) -> String {
        let filtered = zip(matchNumbers, options).map { match, option in
            let value = option.count == 1
                ? String(option[0])
                : "(\(option.map(String.init).joined()))"
            return (match: match, value: value)
        }
        let fixed = extraMatches.map { match in
            let value = match.outcomes.count == 1
                ? String(match.outcomes[0])
                : "(\(match.compactOutcomes))"
            return (match: match.matchNumber, value: value)
        }
        return (filtered + fixed).sorted { left, right in
            if let leftNumber = Int(left.match), let rightNumber = Int(right.match) {
                return leftNumber < rightNumber
            }
            return left.match.localizedStandardCompare(right.match) == .orderedAscending
        }.map { "\($0.match)→\($0.value)" }.joined(separator: "，")
    }
}

struct TXTOutcomeExclusion: Codable, Equatable, Sendable {
    let matchNumber: String
    let outcome: Int

    var summary: String { "手动剔除：场次\(matchNumber)取值\(outcome)的整注" }
}

enum TXTBetEditingError: LocalizedError, Equatable {
    case invalidMatchNumber
    case matchNotFound
    case invalidOutcome
    case invalidBets
    case invalidMultiplier

    var errorDescription: String? {
        switch self {
        case .invalidMatchNumber: return "请输入一个有效的实际场次号。"
        case .matchNotFound: return "该场次不在这份总TXT中，请按下方列出的实际场次输入。"
        case .invalidOutcome: return "每次只能剔除一个值：3、1或0。"
        case .invalidBets: return "TXT的场次或投注数据不完整，无法重新生成。"
        case .invalidMultiplier: return "投注倍数须为1–9999。"
        }
    }
}

enum TXTBetEditor {
    static func validatedBets(_ bets: [[Int]], matchNumbers: [String]) throws -> [[Int]] {
        let numbers = matchNumbers.compactMap { Int($0) }
        guard (6...7).contains(matchNumbers.count), numbers.count == matchNumbers.count,
              numbers.allSatisfy({ $0 > 0 }), Set(numbers).count == numbers.count,
              bets.allSatisfy({ $0.count == numbers.count && $0.allSatisfy { [3, 1, 0].contains($0) } }) else {
            throw TXTBetEditingError.invalidBets
        }
        var seen = Set<[Int]>()
        return bets.filter { seen.insert($0).inserted }
    }

    static func excluding(bets: [[Int]], matchNumbers: [String], matchNumber: String, outcome: String)
        throws -> (bets: [[Int]], rule: TXTOutcomeExclusion, removedCount: Int) {
        let cleanedNumber = matchNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedNumber.isEmpty, cleanedNumber.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(cleanedNumber), number > 0 else { throw TXTBetEditingError.invalidMatchNumber }
        let cleanedOutcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["3", "1", "0"].contains(cleanedOutcome), let value = Int(cleanedOutcome) else {
            throw TXTBetEditingError.invalidOutcome
        }
        let unique = try validatedBets(bets, matchNumbers: matchNumbers)
        guard let position = matchNumbers.firstIndex(where: { Int($0) == number }) else {
            throw TXTBetEditingError.matchNotFound
        }
        let kept = unique.filter { $0[position] != value }
        return (kept, TXTOutcomeExclusion(matchNumber: matchNumbers[position], outcome: value), unique.count - kept.count)
    }

    /// Exact recompression only. A removed value must never return via supplements.
    static func exactRecords(_ bets: [[Int]]) -> [CompressedRecord] {
        guard let width = bets.first?.count else { return [] }
        let padded = bets.map { width == 6 ? $0 + [3] : $0 }
        return SequenceFilterEngine.recursivelyMergedOptionRows(padded).map {
            CompressedRecord(options: Array($0.prefix(width)), sourceRecords: [])
        }
    }
}

enum TXTBetExportPart: CaseIterable, Sendable {
    case total, e, f

    var label: String {
        switch self { case .total: return "总量"; case .e: return "E"; case .f: return "F" }
    }
}

struct TXTBetExport: Sendable {
    let matchNumbers: [String]
    let displayedMatchNumbers: [String]
    let bets: [[Int]]
    let multiplier: Int
    let rows: [CompressedRecord]
    let partitionIndices: [[Int]]

    init(matchNumbers: [String], displayedMatchNumbers: [String]? = nil, bets: [[Int]], multiplier: Int) throws {
        let unique = try TXTBetEditor.validatedBets(bets, matchNumbers: matchNumbers)
        let displayed = displayedMatchNumbers ?? matchNumbers
        guard displayed == matchNumbers || (matchNumbers.count == 7 && displayed == Array(matchNumbers.prefix(6))) else {
            throw TXTBetEditingError.invalidBets
        }
        guard (1...9999).contains(multiplier) else { throw TXTBetEditingError.invalidMultiplier }
        self.matchNumbers = matchNumbers
        self.displayedMatchNumbers = displayed
        self.bets = unique
        self.multiplier = multiplier
        rows = TXTBetEditor.exactRecords(unique)
        partitionIndices = SequenceFilterEngine.balancedTXTPartitionIndices(
            rowWeights: rows.map { $0.options.reduce(1) { $0 * $1.count } },
            maximumERows: SequenceFilterEngine.eTXTMaximumRows
        )
    }

    func selectedRows(_ part: TXTBetExportPart) -> [CompressedRecord] {
        if part == .total { return rows }
        return partitionIndices[part == .e ? 0 : 1].map { rows[$0] }
    }

    func betCount(_ part: TXTBetExportPart) -> Int {
        selectedRows(part).reduce(0) { $0 + $1.options.reduce(1) { $0 * $1.count } }
    }

    func amount(_ part: TXTBetExportPart) -> Int { betCount(part) * 2 * multiplier }

    func text(issue: String, part: TXTBetExportPart, notes: [String] = [], startTimeLines: [String] = []) -> String {
        let selected = selectedRows(part), count = betCount(part)
        let lines = selected.enumerated().map { index, row in
            "\(String(format: "%02d", index + 1)). \(row.labeledNotation(matchNumbers: displayedMatchNumbers))"
        }
        return (["期号：\(issue)", "TXT分组：\(part.label)", "投注倍数：\(multiplier)倍"]
            + startTimeLines + notes + ["最终：\(count)注", "TXT投注总行数：\(selected.count)行（不含说明行）",
                "总金额：\(amount(part))元（\(count)注 × 2元 × \(multiplier)倍）"] + lines).joined(separator: "\n")
    }
}

struct FilterStatistics: Sendable {
    let total: Int
    let afterProduct: Int
    let afterSum: Int
    let afterDisplacement: Int
    let afterVariance: Int
    let afterValueTwo: Int
    let afterTransition: Int
    let afterRoughness: Int
    let afterBreakpoint: Int
    let afterProbabilitySelection: Int
    let tripleGroups: Int
    let pairGroups: Int
    let singletonGroups: Int

    var compressedCount: Int { tripleGroups + pairGroups + singletonGroups }
    var reducedCount: Int { afterProbabilitySelection - compressedCount }
}

struct FilterQueryStage: Sendable {
    let name: String
    /// Six-match prefixes that actually survived this stage at generation time.
    let survivors: Set<[Int]>
    var failureDetails: [[Int]: String] = [:]
}

enum TXTQueryAttribution: Equatable, Sendable {
    case hit
    case excluded(String)
    case unavailable(String)
}

struct FilterResult: Sendable {
    var config: FilterConfig
    var records: [SequenceRecord]
    var compressedRecords: [CompressedRecord]
    /// 导出时固定全包场始终保留全部选项。
    var exportCompressedRecords: [CompressedRecord]
    /// 套回固定全包前、由六场条件选出的实际注数，仅用于解释数量变化。
    var preFullPackageBetCount: Int
    var stageBetCounts: [Int]
    var statistics: FilterStatistics
    var exactCompression: Bool
    let removedRecords: [SequenceRecord]
    let modelCoveragePercent: Double
    let actualFilteredPercent: Double
    let analysisBasis: String
    let previousHitFlag: Int
    let usesCurrentMatchProbabilities: Bool
    let usesRelationshipCondition: Bool
    let comprehensiveAnalysisRuleCount: Int
    let comprehensiveAnalysisToleranceRange: ClosedRange<Int>?
    let comprehensiveAnalysisRecommendedTitle: String?
    let protectedHistoryRuleCount: Int
    let protectedHistoryRecordCount: Int
    /// 仅保留字段兼容旧结果；新版禁止按固定注数强制截断，始终为 nil。
    let protectedHistoryBetCap: Int?
    var finalReductionBasis: String = ""
    var finalScoringRows: [[Double]] = []
    var generationID = UUID()
    var queryStages: [FilterQueryStage] = []
    var resolvedOddsAdaptiveSRange: ClosedRange<Int>? = nil
    /// Freeze the generation inputs; querying must not replace them with newer odds.
    var queryCustomOdds: [[Double]]? = nil
    var maximum105InputBetCount: Int? = nil
    var maximum105FailureMessage: String? = nil
    var manualTXTExclusions: [TXTOutcomeExclusion] = []
    var originalConditionStageSummaries: [String] = []
    var finalResultFilterNotes: [String] = []
    /// The request before resolving automatic rules; config keeps the actual frozen choices.
    var requestedGenerationSignature: String? = nil

    func matchesGenerationRequest(_ requested: FilterConfig?) -> Bool {
        guard let requested else { return false }
        return (requestedGenerationSignature ?? config.generationRequestSignature) == requested.generationRequestSignature
    }

    func excludingTXTOutcome(matchNumber: String, outcome: String) throws -> FilterResult {
        let edited = try TXTBetEditor.excluding(bets: uniqueExpandedBets,
            matchNumbers: config.matchNumbers + config.extraMatches.map(\.matchNumber),
            matchNumber: matchNumber, outcome: outcome)
        var updated = self
        updated.exportCompressedRecords = TXTBetEditor.exactRecords(edited.bets)
        if !updated.manualTXTExclusions.contains(edited.rule) { updated.manualTXTExclusions.append(edited.rule) }
        updated.queryStages.append(FilterQueryStage(name: edited.rule.summary,
            survivors: Set(edited.bets.map { Array($0.prefix(6)) })))
        updated.generationID = UUID()
        return updated
    }

    func queryConditionFailureReasons(for target: [Int]) -> [String] {
        guard !config.finalResultInverted,
              target.count == 6, target.allSatisfy({ [3, 1, 0].contains($0) }),
              !queryStages.isEmpty, (config.six250RelationshipEnabled || config.svip7RankOddsEnabled),
              config.conditionPackageEnabled else { return [] }
        // One candidate only. Ranking was already calculated in the background at generation.
        let reasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: target, config: config, currentOutcomeSPs: queryCustomOdds, includeRanking: false)
        return reasons
    }

    /// Explain this generated TXT, never a recalculation using newer conditions or odds.
    func inputFailureDiagnosis(for target: [Int]) -> (isHit: Bool?, text: String) {
        switch queryAttribution(for: target) {
        case .hit:
            return (true, "计算结果：前六场已过关，没有未过关原因。\n已在本次生成的最终TXT中找到该六场组合；不代表第七场也命中。")
        case .excluded(let stage):
            let failures = queryConditionFailureReasons(for: target)
            let details = failures.isEmpty ? "" : "\n未满足条件：\n" + failures.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            return (false, "计算结果：前六场未过关。" + details + "\n实际淘汰阶段：\(stage)\n依据本次生成时保存的条件、赔率及逐阶段保留记录，不使用后改条件猜测原因。")
        case .unavailable(let reason):
            return (nil, "暂不能归因：\(reason)；不会猜测未过关原因。")
        }
    }

    func queryAttribution(for target: [Int]) -> TXTQueryAttribution {
        guard target.count == 6, target.allSatisfy({ [3, 1, 0].contains($0) }) else {
            return .unavailable("须输入六场3/1/0赛果")
        }
        if uniqueExpandedBets.contains(where: { Array($0.prefix(6)) == target }) { return .hit }
        guard let initial = queryStages.first else {
            return .unavailable("该TXT没有生成时的逐阶段记录，请重新全局生成后查询")
        }
        let numbers = config.matchNumbers + config.extraMatches.map(\.matchNumber)
        for (offset, extra) in config.extraMatches.enumerated() {
            let index = config.matchNumbers.count + offset
            if index < 6, !extra.outcomes.contains(target[index]) {
                return .excluded("固定场次\(numbers[index])只选\(extra.compactOutcomes)，实际为\(target[index])")
            }
        }
        guard initial.survivors.contains(target) else {
            return .unavailable("该六场组合不在本次生成的输入全集中，请检查场次后重新生成")
        }
        var present = true
        var previousCount = initial.survivors.count
        var exclusion: String?
        for stage in queryStages.dropFirst() {
            let survives = stage.survivors.contains(target)
            if present && !survives {
                exclusion = "\(stage.name)；该阶段共\(previousCount)种六场组合进入、\(stage.survivors.count)种保留" + (stage.failureDetails[target].map { "；" + $0 } ?? "")
            }
            // Ranking versions may reconstruct from the full universe; TXT supplements may reintroduce a bet.
            if survives { exclusion = nil }
            present = survives
            previousCount = stage.survivors.count
        }
        if let exclusion {
            if exclusion.hasPrefix("\(config.structuralScopeLabel)不出现连续\(config.topFiveRelaxed ? 4 : 3)场平局") {
                return .excluded(exclusion + "；" + config.frontFiveNoTripleDrawFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("\(config.structuralScopeLabel)负个数范围") {
                return .excluded(exclusion + "；" + config.frontFiveLossCountFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("\(config.structuralScopeLabel)胜个数范围") {
                return .excluded(exclusion + "；" + config.frontFiveWinCountFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("三条件组合过滤") {
                return .excluded(exclusion + "；" + config.combinedThreeStructureFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个") {
                return .excluded(exclusion + "；" + config.sixLossCount14FailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))") {
                return .excluded(exclusion + "；" + config.frontFiveR39FailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("\(config.structuralScopeLabel)不出现连续3场负") {
                return .excluded(exclusion + "；" + config.frontFiveNoTripleLossFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("\(config.structuralScopeLabel)实际顺序M=") {
                return .excluded(exclusion + "；" + config.frontFiveActualMFailureReasons(for: target).joined(separator: "；"))
            }
            if exclusion.hasPrefix("SVIP5前五场判定值4个数") {
                return .excluded(exclusion + "；" + config.svip5FourCountFailureReasons(for: target).joined(separator: "；"))
            }
            return .excluded(exclusion)
        }
        return .unavailable("逐阶段记录与当前TXT不一致，请重新全局生成后查询")
    }

    var displayResultLines: [String] {
        exportCompressedRecords.map {
            $0.labeledNotation(matchNumbers: config.matchNumbers + config.extraMatches.map(\.matchNumber))
        }
    }

    /// 首页只展示参与过滤的主场次；固定全包和固定单选仍用于TXT导出。
    var filteredDisplayResultLines: [String] {
        if !manualTXTExclusions.isEmpty {
            var seen = Set<String>()
            return exportCompressedRecords.map { $0.labeledNotation(matchNumbers: config.matchNumbers) }
                .filter { seen.insert($0).inserted }
        }
        return compressedRecords.map {
            $0.labeledNotation(matchNumbers: config.matchNumbers)
        }
    }

    /// 完整展开所有导出行，并按整注（包含第六、七场）强制去重。
    /// 压缩行即使意外重叠，也不会重复计入页面金额或TXT。
    var uniqueExpandedBets: [[Int]] {
        var seen = Set<[Int]>()
        return exportCompressedRecords
            .flatMap { options in
                options.options.reduce([[]]) { partial, values in
                    partial.flatMap { prefix in values.map { prefix + [$0] } }
                }
            }
            .filter { seen.insert($0).inserted }
    }

    var rawExpandedBetCount: Int {
        exportCompressedRecords.reduce(0) { $0 + $1.options.reduce(1) { $0 * $1.count } }
    }

    var duplicateExpandedBetCount: Int {
        max(0, rawExpandedBetCount - uniqueExpandedBets.count)
    }

    var finalBetCount: Int {
        uniqueExpandedBets.count
    }

    private func appendingFullPackageSummary(_ lines: [String]) -> [String] {
        // Export notes describe the final stage; they are not another filtering stage.
        func annotated(_ note: String) -> [String] {
            guard !lines.isEmpty else { return [note] }
            var updated = lines
            updated[updated.count - 1] += "；" + note
            return updated
        }
        if !manualTXTExclusions.isEmpty {
            return annotated("手动剔除后精确合并：最终\(finalBetCount)注／\(displayResultLines.count)行，不补回已剔除值")
        }
        if config.txtCompactEnabled {
            return annotated("TXT递归合并：原始通过\(preFullPackageBetCount)注，实际补注\(max(0, finalBetCount - preFullPackageBetCount))注，最终\(finalBetCount)注／\(displayResultLines.count)行（目标50行，补注上限\(config.maximumTXTAdditionalBets)注）")
        }
        if config.svip5TailRemovalCount > 0 || config.svip5FourCountFilterEnabled || config.frontFiveActualMEnabled || config.frontFiveNoTripleDrawEnabled || config.frontFiveLossCountEnabled || config.frontFiveWinCountEnabled || config.combinedThreeStructureEnabled || config.sixLossCount14Enabled || config.frontFiveR39Enabled || config.frontFiveNoTripleLossEnabled {
            return annotated("SVIP5最终精确合并：共\(finalBetCount)注，不再补注")
        }
        guard preFullPackageBetCount != finalBetCount else { return lines }
        if finalBetCount > preFullPackageBetCount {
            return annotated("TXT受控合并：原始通过\(preFullPackageBetCount)注，补入\(finalBetCount - preFullPackageBetCount)注防守，合并后共\(finalBetCount)注")
        }
        let pathCount = stageBetCounts.last ?? preFullPackageBetCount
        return annotated("第六场310全包回填：条件路径\(pathCount)注，按\(config.structuralScopeLabel)去重为\(preFullPackageBetCount)个主组合，完整310计为\(finalBetCount)注")
    }

    var filterStageSummaries: [String] {
        if !finalResultFilterNotes.isEmpty {
            return originalConditionStageSummaries + finalResultFilterNotes
                + manualTXTExclusions.map(\.summary)
                + ["最终\(finalBetCount)注；TXT\(displayResultLines.count)行；精确合并，不补回"]
        }
        let off = config.disabledBasicConditions.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        var summaries = rawFilterStageSummaries
        if let count = maximum105InputBetCount {
            summaries.append("最多105注：优选前\(count)注，最终\(finalBetCount)注；不足105注不补齐，TXT行数另计。")
        }
        if let maximum105FailureMessage { summaries.append(maximum105FailureMessage) }
        if !off.isEmpty, !summaries.isEmpty {
            summaries[0] += "；已关闭：" + off.joined(separator: "、") + "（不参与过滤）"
        }
        return summaries
    }

    private var rawFilterStageSummaries: [String] {
        if config.svip11BreakpointOnlyEnabled {
            if !config.conditionPackageEnabled { return ["SVIP11已关闭，保留全部\(finalBetCount)注"] }
            return ["前6场S\(config.sumRange)，前5场实际M\(config.displacementRange)", "前5场彩果断点\(config.breakpointRange)（选场目标及硬过滤）", "指定场次不是4：\(config.noFourPositions.isEmpty ? "关闭" : config.noFourPositions.map(String.init).joined(separator: ","))", "最终\(finalBetCount)注；TXT\(displayResultLines.count)行；精确合并，不补注"]
        }
        if config.txtCompactEnabled {
            let stages = zip(queryStages, queryStages.dropFirst()).map { previous, next in
                let change = next.survivors.count - previous.survivors.count
                return "\(next.name)：\(change > 0 ? "补入" : "过滤")\(abs(change))组赛果，剩余\(next.survivors.count)组赛果"
            }
            return appendingFullPackageSummary(stages)
        }
        if !config.conditionPackageEnabled { return [config.hasIndependentConditionGroups ? "原有条件已关闭；\(config.activeIndependentGroupLabels.joined(separator: "、"))已开启，保留\(finalBetCount)注" : "六场条件总包已关闭：保留全部\(finalBetCount)注"] }
        if config.oddsAdaptiveSRangeEnabled || config.additionalSumRange != nil {
            let name = resolvedOddsAdaptiveSRange.map { "\($0.lowerBound)–\($0.upperBound)" } ?? "无法计算（缺少六场自定义赔率）"
            let stages = zip(queryStages, queryStages.dropFirst()).map { previous, next in
                "\(next.name)：过滤\(previous.survivors.count - next.survivors.count)组赛果，剩余\(next.survivors.count)组赛果"
            }
            var headers: [String] = []
            if config.isEnabled(.sum) && config.oddsAdaptiveSRangeEnabled { headers.append("赔率自适应S：\(name)") }
            if config.isEnabled(.sum), let range = config.additionalSumRange { headers.append("新增固定S：\(range.lowerBound)–\(range.upperBound)") }
            return appendingFullPackageSummary(headers + stages + ["所有开启条件取交集；最终\(finalBetCount)注；TXT共\(displayResultLines.count)行"])
        }
        if config.svip7RankOddsEnabled {
            return SequenceFilterEngine.svip7RuleTitles + ["最终\(finalBetCount)注；TXT共\(displayResultLines.count)行；精确合并，不补注、不固定截取280注"]
        }
        if config.six250RelationshipEnabled {
            return ["六场关系条件：S=\(config.six250SumRange)；实际M=\(config.six250MRange)；R=\(config.six250RRange)；判定值3最多\(config.valueThreeMaximum)个", "赔率综合分：−ln(六场校准概率乘积)−0.75×变异系数＋0.5×相邻波动，范围\(config.six250ScoreLower)–\(config.six250ScoreUpper)", "最终\(finalBetCount)注；TXT共\(displayResultLines.count)行。指定场次不是4：\(config.noFourPositions.isEmpty ? "关闭" : config.noFourPositions.map(String.init).joined(separator: ","))"] + (config.svip10Frozen160Enabled ? config.svip10AdditionalFilters.descriptions : [])
        }
        func summaries(for stages: [(String, Int, Int)]) -> [String] {
            guard stageBetCounts.count == stages.count + 1 else {
                return ["过滤阶段统计暂不可用（阶段\(stages.count)项，计数\(stageBetCounts.count)项）"]
            }
            return stages.enumerated().map { index, stage in
                "\(stage.0)：过滤\(stageBetCounts[index] - stageBetCounts[index + 1])注，剩余\(stageBetCounts[index + 1])注"
            }
        }

        if config.allConditionsToleranceEnabled {
            var stages: [(String, Int, Int)] = [
                ("基础全集（未执行乘积Q删注）", statistics.total, statistics.afterProduct),
                ("全部条件总容错\(config.allConditionsToleranceRange.lowerBound)-\(config.allConditionsToleranceRange.upperBound)项", 0, 0)
            ]
            if let tolerance = comprehensiveAnalysisToleranceRange {
                stages.append(("历史综合分析过滤（\(comprehensiveAnalysisRuleCount)项，容错\(tolerance.lowerBound)-\(tolerance.upperBound)项）", 0, 0))
            }
            if protectedHistoryRuleCount > 0 {
                stages.append(("全局答案全过最大压缩（\(protectedHistoryRecordCount)条/\(protectedHistoryRuleCount)项）", 0, 0))
            }
            if config.universal247ToleranceEnabled {
                stages.append((SequenceFilterEngine.universalCompressionStageName(threshold: config.universal247ToleranceThreshold), 0, 0))
            }
            if config.universal150CompressionEnabled {
                stages.append(("通用150注统计压缩", 0, 0))
            }
            if config.vip12ProbabilityReductionEnabled {
                stages.append(("VIP12六场联合概率低位减注≥10%", 0, 0))
            }
            if config.svip1CustomOddsGuardEnabled {
                stages.append(("SVIP1自定义赔率冷尾保护（保留83.5%）", 0, 0))
            }
            if protectedHistoryRuleCount > 0,
               let cap = protectedHistoryBetCap, cap > 0 {
                stages.append(("六位置胜平负频率排序（最多\(cap)注）", 0, 0))
            }
            if config.finalReduction != .off { stages.append((config.finalReductionDescription, 0, 0)) }
            if config.vip16Top200Enabled { stages.append(("VIP16赛前联合概率排序（最多200注）", 0, 0)) }
            if config.vip18Top200Enabled { stages.append(("VIP18校准概率＋冷门次数（最多200注）", 0, 0)) }
            if config.vip19CustomOddsTop200Enabled { stages.append(("VIP19六场自定义赔率乘积200–1500＋概率排序（最多200注）", 0, 0)) }
            if config.svip5TailRemovalCount > 0 {
                stages.append(("TXT合并补注后", 0, 0))
                stages.append(("SVIP5自定义赔率冷尾减\(config.svip5TailRemovalCount)注", 0, 0))
            }
            if config.svip5FourCountFilterEnabled {
                stages.append(("TXT组成过滤前", 0, 0))
                stages.append(("SVIP5前五场判定值4个数（最多2个）", 0, 0))
            }
            if config.frontFiveActualMEnabled {
                stages.append(("前五场实际M过滤前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)实际顺序M=\(config.frontFiveActualMRange.lowerBound)–\(config.frontFiveActualMRange.upperBound)", 0, 0))
            }
            if config.frontFiveNoTripleDrawEnabled {
                stages.append(("前五场连续平局过滤前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)不出现连续\(config.topFiveRelaxed ? 4 : 3)场平局", 0, 0))
            }
            if config.frontFiveLossCountEnabled {
                stages.append(("前五场负个数过滤前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)负个数范围", 0, 0))
            }
            if config.frontFiveWinCountEnabled {
                stages.append(("前五场胜个数过滤前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)胜个数范围", 0, 0))
            }
            if config.combinedThreeStructureEnabled {
                stages.append(("三条件组合过滤前", 0, 0))
                stages.append(("三条件组合过滤", 0, 0))
            }
            if config.sixLossCount14Enabled {
                stages.append(("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个前", 0, 0))
                stages.append(("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个", 0, 0))
            }
            if config.frontFiveR39Enabled {
                stages.append(("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))", 0, 0))
            }
            if config.frontFiveNoTripleLossEnabled {
                stages.append(("\(config.structuralScopeLabel)不出现连续3场负前", 0, 0))
                stages.append(("\(config.structuralScopeLabel)不出现连续3场负", 0, 0))
            }
            let lines = summaries(for: stages)
            return appendingFullPackageSummary(lines)
        }
        var stages: [(String, Int, Int)] = [
            ("基础全集（未执行乘积Q删注）", statistics.total, statistics.afterProduct),
            ("判定总和 S", statistics.afterProduct, statistics.afterSum),
            (config.minimumDistinctDisplacementOrders > 0
                ? "\(config.structuralScopeLabel)M=\(config.displacementRange.lowerBound)–\(config.displacementRange.upperBound)的不同排列≥\(config.minimumDistinctDisplacementOrders)种"
                : "位移 M", statistics.afterSum, statistics.afterDisplacement),
            ("稳定性 σ²", statistics.afterDisplacement, statistics.afterVariance),
            ("判定值2次数", statistics.afterVariance, statistics.afterValueTwo),
            ("马尔可夫 P_tr", statistics.afterValueTwo, statistics.afterTransition),
            ("二阶波动 R", statistics.afterTransition, statistics.afterRoughness),
            ("最终彩果断点 B", statistics.afterRoughness, statistics.afterBreakpoint)
        ]
        for position in config.activeNoFourPositions {
            let title = position == config.resolvedLowestCustomOddsNoFourPosition
                ? "4概率最低的第\(position)场判定值不是4"
                : "第\(position)场判定值不是4"
            stages.append((title, 0, 0))
        }
        if config.lowestCustomOddsNoFourEnabled,
           config.resolvedLowestCustomOddsNoFourPosition == nil {
            stages.append(("4概率最低场次禁4（赔率数据不足）", 0, 0))
        }
        if let maximum = config.frontThreeMaximumFourCount {
            stages.append(("前三场判定值4最多\(maximum)个", 0, 0))
        }
        if config.outcomeConditionToleranceEnabled, !config.enabledOutcomeConditions.isEmpty {
            stages.append(("彩果条件组（容错\(config.outcomeConditionToleranceRange.lowerBound)-\(config.outcomeConditionToleranceRange.upperBound)项）", 0, 0))
        } else {
            stages += config.enabledOutcomeConditions.map { ($0.title, 0, 0) }
        }
        if config.spProductFilterEnabled { stages.append(("SP乘积范围", 0, 0)) }
        if config.customHandicapOddsProductFilterEnabled { stages.append(("自定义让球赔率乘积", 0, 0)) }
        if config.customHandicapOddsSumFilterEnabled { stages.append(("自定义让球赔率和值", 0, 0)) }
        if config.prizeRangeFilterEnabled { stages.append(("预计奖金范围", 0, 0)) }
        if config.spRiskFilterEnabled { stages.append(("最大单场SP与高SP场次", 0, 0)) }
        if config.minimumProbabilityFilterEnabled { stages.append(("最低单场概率", 0, 0)) }
        if config.jointProbabilityFilterEnabled { stages.append(("整串全中概率", 0, 0)) }
        if config.groupFilterEnabled { stages.append(("前3场/后组分组过滤", 0, 0)) }
        if config.consecutiveRunsEnabled {
            let secondary = config.secondaryConsecutiveRunsEnabled
                ? "＋第二档\(config.secondaryConsecutiveRunRange.lowerBound)-\(config.secondaryConsecutiveRunRange.upperBound)/容错\(config.secondaryConsecutiveRunToleranceRange.lowerBound)-\(config.secondaryConsecutiveRunToleranceRange.upperBound)"
                : ""
            stages.append(("连续彩果（7场，第一档容错\(config.consecutiveRunToleranceRange.lowerBound)-\(config.consecutiveRunToleranceRange.upperBound)\(secondary)）", 0, 0))
        }
        if config.sameResultRunsEnabled {
            let protection = config.protectConsecutiveDrawPair ? "，保护相邻11" : ""
            stages.append(("连续胜平负（7场，容错\(config.sameResultRunToleranceRange.lowerBound)-\(config.sameResultRunToleranceRange.upperBound)\(protection)）", 0, 0))
        }
        if let tolerance = comprehensiveAnalysisToleranceRange {
            stages.append(("历史综合分析过滤（\(comprehensiveAnalysisRuleCount)项，容错\(tolerance.lowerBound)-\(tolerance.upperBound)项）", 0, 0))
        }
        if protectedHistoryRuleCount > 0 {
            stages.append(("全局答案全过最大压缩（\(protectedHistoryRecordCount)条/\(protectedHistoryRuleCount)项）", 0, 0))
        }
        if config.universal247ToleranceEnabled {
            stages.append((SequenceFilterEngine.universalCompressionStageName(threshold: config.universal247ToleranceThreshold), 0, 0))
        }
        if config.universal150CompressionEnabled {
            stages.append(("通用150注统计压缩", 0, 0))
        }
        if config.prizeStatisticalConditionEnabled {
            stages.append(("奖金统计条件（六串胜负切换0-2）", 0, 0))
        }
        if config.vip12ProbabilityReductionEnabled {
            stages.append(("VIP12六场联合概率低位减注≥10%", 0, 0))
        }
        if config.svip1CustomOddsGuardEnabled {
            stages.append(("SVIP1自定义赔率冷尾保护（保留83.5%）", 0, 0))
        }
        if protectedHistoryRuleCount > 0,
           let cap = protectedHistoryBetCap, cap > 0 {
            stages.append(("六位置胜平负频率排序（最多\(cap)注）", 0, 0))
        }
        if config.finalReduction != .off { stages.append((config.finalReductionDescription, 0, 0)) }
        if config.vip16Top200Enabled { stages.append(("VIP16赛前联合概率排序（最多200注）", 0, 0)) }
        if config.vip18Top200Enabled { stages.append(("VIP18校准概率＋冷门次数（最多200注）", 0, 0)) }
        if config.vip19CustomOddsTop200Enabled { stages.append(("VIP19六场自定义赔率乘积200–1500＋概率排序（最多200注）", 0, 0)) }
        if config.svip5TailRemovalCount > 0 {
            stages.append(("TXT合并补注后", 0, 0))
            stages.append(("SVIP5自定义赔率冷尾减\(config.svip5TailRemovalCount)注", 0, 0))
        }
        if config.svip5FourCountFilterEnabled {
            stages.append(("TXT组成过滤前", 0, 0))
            stages.append(("SVIP5前五场判定值4个数（最多2个）", 0, 0))
        }
        if config.frontFiveActualMEnabled {
            stages.append(("前五场实际M过滤前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)实际顺序M=\(config.frontFiveActualMRange.lowerBound)–\(config.frontFiveActualMRange.upperBound)", 0, 0))
        }
        if config.frontFiveNoTripleDrawEnabled {
            stages.append(("前五场连续平局过滤前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)不出现连续\(config.topFiveRelaxed ? 4 : 3)场平局", 0, 0))
        }
        if config.frontFiveLossCountEnabled {
            stages.append(("前五场负个数过滤前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)负个数范围", 0, 0))
        }
        if config.frontFiveWinCountEnabled {
            stages.append(("前五场胜个数过滤前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)胜个数范围", 0, 0))
        }
        if config.combinedThreeStructureEnabled {
            stages.append(("三条件组合过滤前", 0, 0))
            stages.append(("三条件组合过滤", 0, 0))
        }
        if config.sixLossCount14Enabled {
            stages.append(("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个前", 0, 0))
            stages.append(("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个", 0, 0))
        }
        if config.frontFiveR39Enabled {
            stages.append(("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))", 0, 0))
        }
        if config.frontFiveNoTripleLossEnabled {
            stages.append(("\(config.structuralScopeLabel)不出现连续3场负前", 0, 0))
            stages.append(("\(config.structuralScopeLabel)不出现连续3场负", 0, 0))
        }
        let lines = summaries(for: stages)
        return appendingFullPackageSummary(lines)
    }

    /// 给“全局答案”每个 Cell 展示的大条件统计。主过滤的8项合并为一段，
    /// 后续彩果、SP、连续条件、综合分析和大压缩仍按实际执行顺序逐段显示。
    var majorFilterStageSummaries: [String] {
        let detailed = filterStageSummaries
        if config.allConditionsToleranceEnabled {
            guard stageBetCounts.count >= 3 else { return detailed }
            let combined = "8项基础条件＋其他开启条件（总容错）：过滤\(stageBetCounts[0] - stageBetCounts[2])注，剩余\(stageBetCounts[2])注"
            return [combined] + Array(detailed.dropFirst(2))
        }
        guard stageBetCounts.count >= 9, detailed.count >= 8 else { return detailed }
        let base = "8项基础条件：过滤\(stageBetCounts[0] - stageBetCounts[8])注，剩余\(stageBetCounts[8])注"
        return [base] + Array(detailed.dropFirst(8))
    }

    var removedDisplayLines: [String] {
        removedRecords.map { record in
            zip(config.matchNumbers, record.outcomes)
                .map { "\($0.0)→\($0.1)" }
                .joined(separator: "，")
        }
    }

    /// 策略稳定度，不是中奖概率。
    var strategyConfidenceIndex: Int {
        let coverage = min(max(modelCoveragePercent, 0), 100)
        let sampleScore = min(Double(records.count) / 40.0, 1.0)
        let structuralScore = exactCompression ? 1.0 : 0.75
        return Int((coverage * 0.55 + sampleScore * 25 + structuralScore * 20).rounded())
    }

    var strategyConfidenceReason: String {
        let compression = exactCompression ? "合并结果已验证为精确覆盖" : "合并采用近似最优覆盖"
        var conditionCount = 7 + (config.outcomeConditionToleranceEnabled && !config.enabledOutcomeConditions.isEmpty
            ? 1
            : config.enabledOutcomeConditions.count)
        conditionCount += config.activeNoFourPositions.count
        if config.frontThreeMaximumFourCount != nil { conditionCount += 1 }
        if config.consecutiveRunsEnabled { conditionCount += 1 }
        if config.sameResultRunsEnabled { conditionCount += 1 }
        if config.spProductFilterEnabled { conditionCount += 1 }
        if config.customHandicapOddsProductFilterEnabled { conditionCount += 1 }
        if config.customHandicapOddsSumFilterEnabled { conditionCount += 1 }
        if config.prizeRangeFilterEnabled { conditionCount += 1 }
        if config.spRiskFilterEnabled { conditionCount += 1 }
        if config.minimumProbabilityFilterEnabled { conditionCount += 1 }
        if config.jointProbabilityFilterEnabled { conditionCount += 1 }
        if config.frontFiveLossCountEnabled { conditionCount += 1 }
        if config.frontFiveWinCountEnabled { conditionCount += 1 }
        if config.combinedThreeStructureEnabled { conditionCount += 1 }
        if config.sixLossCount14Enabled { conditionCount += 1 }
        if config.frontFiveR39Enabled { conditionCount += 1 }
        if config.frontFiveNoTripleLossEnabled { conditionCount += 1 }
        if config.vip12ProbabilityReductionEnabled { conditionCount += 1 }
        if config.svip1CustomOddsGuardEnabled { conditionCount += 1 }
        if config.vip16Top200Enabled { conditionCount += 1 }
        if config.vip18Top200Enabled { conditionCount += 1 }
        if config.vip19CustomOddsTop200Enabled { conditionCount += 1 }
        if config.groupFilterEnabled { conditionCount += 1 }
        if comprehensiveAnalysisToleranceRange != nil { conditionCount += 1 }
        if protectedHistoryRuleCount > 0 { conditionCount += 1 }
        if config.universal247ToleranceEnabled { conditionCount += 1 }
        if config.universal150CompressionEnabled { conditionCount += 1 }
        if config.prizeStatisticalConditionEnabled { conditionCount += 1 }
        if config.finalReduction != .off { conditionCount += 1 }
        return "不执行乘积Q删注；第六场全包保持完整，再执行\(conditionCount)个条件；共保留\(records.count)条主组合、\(finalBetCount)注；\(compression)。"
    }

    var knowledgeFields: String {
        "组合数学（二阶/三阶覆盖）、描述统计（S/M/方差）、马尔可夫链、条件概率与稳健决策；心理学仅用于减少人工追热、锚定和临时改规则的偏差"
    }

    var reportText: String {
        if config.svip7RankOddsEnabled {
            return (["SVIP7 · 六场赔率排名与容错", "最终：\(finalBetCount)注",
                     "TXT投注总行数：\(displayResultLines.count)行（不含说明行）",
                     "以下历史复核仅适用于开启SVIP7过滤：2025年53.83%，2026年51.38%；平均约280注，并非每组上限。",
                     "1倍命中平均奖金保守下界：2025年827.49元，2026年869.03元；历史结果不保证未来。"]
                    + filterStageSummaries + displayResultLines).joined(separator: "\n")
        }
        if config.six250RelationshipEnabled || config.oddsAdaptiveSRangeEnabled || config.additionalSumRange != nil || config.txtCompactEnabled {
            return (["六场自定义赔率关系条件", "最终：\(finalBetCount)注", "TXT投注总行数：\(displayResultLines.count)行（不含说明行）"] + filterStageSummaries + displayResultLines).joined(separator: "\n")
        }
        let results = displayResultLines.enumerated().map { index, line in
            "\(String(format: "%02d", index + 1)). \(line)"
        }
        let summary = [
            "最终：\(finalBetCount)注",
            "TXT投注总行数：\(displayResultLines.count)行（不含说明行）",
            "分析依据：\(analysisBasis == "未使用上次结果" ? analysisBasis : "上次 \(analysisBasis)")",
            analysisBasis == "未使用上次结果" ? "上次是否命中：未使用" : "上次是否命中：\(previousHitFlag)",
            config.finalReduction == .off ? "最终压缩：已关闭" : "最终压缩：\(config.finalReductionDescription)",
            "策略信心指数：\(strategyConfidenceIndex)/100（不是中奖率）",
            "信心理由：\(strategyConfidenceReason)",
            "采用领域：\(knowledgeFields)"
        ]
        let reduction = config.finalReduction == .off ? [] : ["最终压缩：\(config.finalReductionDescription)；随机种子：\(config.randomSeed)；保留注数向上取整", finalReductionBasis]
        let conditions = config.enabledOutcomeConditions.map { condition in
            let range = config.outcomeConditions[condition]!
            return "\(condition.title)范围：\(range.lowerBound)-\(range.upperBound)"
        }
        let outcomeTolerance = config.outcomeConditionToleranceEnabled ? [
            "彩果条件容错：允许\(config.outcomeConditionToleranceRange.lowerBound)-\(config.outcomeConditionToleranceRange.upperBound)项不满足"
        ] : []
        let allTolerance = config.allConditionsToleranceEnabled ? [
            "全部条件总容错：允许\(config.allConditionsToleranceRange.lowerBound)-\(config.allConditionsToleranceRange.upperBound)项不满足（乘积Q优先删除与最终压缩不计入）"
        ] : []
        let comprehensive = comprehensiveAnalysisToleranceRange.map { tolerance in
            ["历史综合分析过滤：\(comprehensiveAnalysisRuleCount)项历史共性，允许\(tolerance.lowerBound)-\(tolerance.upperBound)项不满足；最适合单项：\(comprehensiveAnalysisRecommendedTitle ?? "-")"]
        } ?? []
        let protectedHistory = protectedHistoryRuleCount > 0
            ? ["通用大压缩：由\(protectedHistoryRecordCount)条历史样本确定\(protectedHistoryRuleCount)项统计范围；所有期号、场次均使用同一规则"]
            : []
        let universal247: [String]
        if !config.universal247ToleranceEnabled {
            universal247 = []
        } else if VIP2Joint150Model.isSelected(configurationValue: config.universal247ToleranceThreshold) {
            universal247 = ["VIP2联合150：项目换算后真实让球赔率80%＋原始彩果形态20%；不使用2/3/4判定值，729种排名后固定保留前150种"]
        } else if ProductSumV10Model.isSelected(configurationValue: config.universal247ToleranceThreshold) {
            let prefix = config.productSumV10Top150Enabled
                ? "V8联合评分前150注已开启；"
                : "V8联合评分前150注已关闭；"
            universal247 = ["V10乘积Q＋和值S：\(prefix)硬过滤ABCD结构映射值的乘积Q=50–299、和值S=12–16；该Q/S不是赔率积/和"]
        } else if HandicapOddsV9Model.isSelected(configurationValue: config.universal247ToleranceThreshold) {
            universal247 = ["V9让球对照表：保留条件Tab当前其他条件；\(config.structuralScopeLabel)用普通三项欧赔＋实际让球数换算，和值12.42–16.37、积值85.05–306.71"]
        } else if Joint150V8Model.isSelected(configurationValue: config.universal247ToleranceThreshold) {
            universal247 = ["V8联合150：赛前概率55%＋ABCD等级45%，满足V7结构条件额外加0.5分；729种统一排名后固定保留前150种"]
        } else if Universal405WholeIssueModel.isSelected(configurationValue: config.universal247ToleranceThreshold) {
            universal247 = ["V5整期留出通用压缩：仅用前6场结构汇总与\(config.structuralScopeLabel)ABCD判定值汇总评分，统一保留得分最高的405种；不使用具体赛果、期号、场次或记录ID"]
        } else {
            universal247 = ["通用247综合容错：前6场结构指标统一评分；不使用期号、场次或赛果白名单"]
        }
        let universal150 = config.universal150CompressionEnabled
            ? ["通用150注统计压缩：六场彩果位置概率＋前五场判定值Markov转移；全部单据使用同一阈值，不强制截取注数"]
            : []
        let prizeStatistical = config.prizeStatisticalConditionEnabled
            ? ["奖金统计条件：只按前6场统计；胜负直接切换次数0-2"]
            : []
        let consecutiveConditions = config.consecutiveRunsEnabled ? [
            "7场连续彩果：第一档不败\(config.nonLossRunRange.lowerBound)-\(config.nonLossRunRange.upperBound)，不平\(config.nonDrawRunRange.lowerBound)-\(config.nonDrawRunRange.upperBound)，不胜\(config.nonWinRunRange.lowerBound)-\(config.nonWinRunRange.upperBound)，容错\(config.consecutiveRunToleranceRange.lowerBound)-\(config.consecutiveRunToleranceRange.upperBound)项"
                + (config.secondaryConsecutiveRunsEnabled
                    ? "；第二档三项\(config.secondaryConsecutiveRunRange.lowerBound)-\(config.secondaryConsecutiveRunRange.upperBound)，容错\(config.secondaryConsecutiveRunToleranceRange.lowerBound)-\(config.secondaryConsecutiveRunToleranceRange.upperBound)项"
                    : "")
        ] : []
        let sameResultConditions = config.sameResultRunsEnabled ? [
            "7场连续胜平负：胜\(config.winRunRange.lowerBound)-\(config.winRunRange.upperBound)，平\(config.drawRunRange.lowerBound)-\(config.drawRunRange.upperBound)，负\(config.lossRunRange.lowerBound)-\(config.lossRunRange.upperBound)，容错\(config.sameResultRunToleranceRange.lowerBound)-\(config.sameResultRunToleranceRange.upperBound)项，保护相邻11：\(config.protectConsecutiveDrawPair ? "开" : "关")"
        ] : []
        var advancedConditions: [String] = []
        if config.spProductFilterEnabled { advancedConditions.append("SP乘积：\(config.spProductRange.lowerBound)-\(config.spProductRange.upperBound)") }
        if config.customHandicapOddsProductFilterEnabled {
            let count = config.customHandicapOddsProductMatchCount ?? config.calculationMatchCount ?? config.matchNumbers.count
            advancedConditions.append("前\(count)场自定义让球赔率乘积：\(config.customHandicapOddsProductRange.lowerBound)-\(config.customHandicapOddsProductRange.upperBound)")
        }
        if config.customHandicapOddsSumFilterEnabled {
            advancedConditions.append("自定义让球赔率和值：\(config.customHandicapOddsSumRange.lowerBound)-\(config.customHandicapOddsSumRange.upperBound)")
        }
        if config.prizeRangeFilterEnabled { advancedConditions.append("预计奖金：\(config.estimatedPrizeRange.lowerBound)-\(config.estimatedPrizeRange.upperBound)（SP乘积×1.3）") }
        if config.spRiskFilterEnabled { advancedConditions.append("单场SP≤\(config.maximumSingleSP)，SP>\(config.highSPThreshold)的场次数为\(config.highSPCountRange.lowerBound)-\(config.highSPCountRange.upperBound)") }
        if config.minimumProbabilityFilterEnabled { advancedConditions.append("最低单场概率≥\(config.minimumSingleProbabilityPercent)%") }
        if config.jointProbabilityFilterEnabled { advancedConditions.append("整串全中概率：\(config.jointProbabilityPercentRange.lowerBound)%-\(config.jointProbabilityPercentRange.upperBound)%") }
        if config.vip12ProbabilityReductionEnabled {
            advancedConditions.append("VIP12联合概率减注：六场概率连乘排序，每次删除最低至少10%整注")
        }
        if config.svip1CustomOddsGuardEnabled {
            advancedConditions.append("SVIP1自定义赔率冷尾保护：在已通过组合中按六场项目自定义赔率乘积从低到高保留83.5%，去掉最冷16.5%；不使用500或澳客直接SP")
        }
        if config.vip16Top200Enabled {
            advancedConditions.append("VIP16联合概率排序：仅从已通过条件的实际单注中保留前200注；不足200注时全部保留，TXT精确合并且不补注；这是注数上限，不保证80%命中率")
        }
        if config.vip18Top200Enabled {
            advancedConditions.append("VIP18：2025冻结的泊松校准＋六场最小概率彩果次数平滑先验，严格从已通过条件的单注取前200注；2026连续六场独立回测5527/10814（51.11%），不保证未来命中")
        }
        if config.vip19CustomOddsTop200Enabled {
            advancedConditions.append("VIP19：仅使用项目自定义赔率；六场所选赔率乘积须为200–1500，再按自定义赔率反推并校准概率，最多保留前200注；禁止使用500或澳客直接SP")
        }
        if config.groupFilterEnabled { advancedConditions.append("分组过滤：\(config.groupFilterMode.title)，前3场/后组分别限制") }
        if config.svip5TailRemovalCount > 0 {
            advancedConditions.append("SVIP5实验冷尾：最终单注按前六场自定义赔率联合概率剔除最低\(config.svip5TailRemovalCount)注，至少保留1注；不保证90%整体过关率")
        }
        if config.svip5FourCountFilterEnabled {
            advancedConditions.append("SVIP5前五场判定值4个数：最多2个4；通用结构规则自然过滤，不读取赔率、不排名、不按固定注数截取；最终不再补回淘汰组合")
        }
        if config.frontFiveActualMEnabled {
            advancedConditions.append("\(config.structuralScopeLabel)实际顺序M=\(config.frontFiveActualMRange.lowerBound)–\(config.frontFiveActualMRange.upperBound)（含边界）：M=相邻判定值绝对差之和，不重排；独立于M不同排列门槛；精确合并不补回淘汰注")
        }
        if config.frontFiveNoTripleDrawEnabled {
            advancedConditions.append("\(config.structuralScopeLabel)不出现连续\(config.topFiveRelaxed ? 4 : 3)场平局：仅第1–3、2–4、3–5场三个窗口，原始彩果111即排除；第6、7场不参与；不读取赔率，不排名，不固定截取注数")
        }
        if config.frontFiveLossCountEnabled {
            advancedConditions.append("\(config.structuralScopeLabel)负个数范围：仅统计原始彩果0，范围\(config.frontFiveLossCountRange.lowerBound)–\(config.frontFiveLossCountRange.upperBound)（含边界）；第6、7场不参与；最终精确合并不补回淘汰注")
        }
        if config.frontFiveWinCountEnabled {
            advancedConditions.append("\(config.structuralScopeLabel)胜个数范围：仅统计原始彩果3，范围\(config.frontFiveWinCountRange.lowerBound)–\(config.frontFiveWinCountRange.upperBound)（含边界）；第6、7场不参与；最终精确合并不补回淘汰注")
        }
        if config.combinedThreeStructureEnabled {
            advancedConditions.append("三条件组合过滤：\(config.structuralScopeLabel)原始赛果胜\(config.expandedStructureRanges ? "0–4" : "1–4")个；六场ABCD判定值二阶波动R为\(config.combinedThreeRRange.lowerBound)–\(config.combinedThreeRRange.upperBound)；六场判定值3最多\(config.topFiveRelaxed ? 4 : 3)个。三项必须同时满足；最终精确合并不补回淘汰注")
        }
        if config.sixLossCount14Enabled {
            advancedConditions.append("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个：仅统计前六场原始赛果0，负场个数须为\(config.widerFiveConditions ? "0–5" : "1–4")个；第七场不参与；最终精确合并不补回淘汰注")
        }
        if config.frontFiveR39Enabled {
            advancedConditions.append("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))：仅统计前五场ABCD判定值的二阶波动R，须为\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))；第六、七场不参与；最终精确合并不补回淘汰注")
        }
        if config.frontFiveNoTripleLossEnabled {
            advancedConditions.append("\(config.structuralScopeLabel)不出现连续3场负：仅检查前五场三个相邻窗口，原始赛果000即排除；第六、七场不参与；最终精确合并不补回淘汰注")
        }
        let scoringDetails = config.finalReduction == .off ? [] : zip(config.matchNumbers, finalScoringRows).map { number, row in
            "场次\(number)评分（胜/平/负）：\(row.map { String($0) }.joined(separator: "/"))"
        }
        return (summary + conditions + outcomeTolerance + allTolerance + comprehensive + protectedHistory + universal247 + universal150 + prizeStatistical + consecutiveConditions + sameResultConditions + advancedConditions + reduction + scoringDetails + filterStageSummaries + results)
            .joined(separator: "\n")
    }

    /// 分享文件只保留注数和最终投注行，不附带筛选条件与评分说明。
    var shareText: String {
        let results = displayResultLines.enumerated().map { index, line in
            "\(String(format: "%02d", index + 1)). \(line)"
        }
        let supplemental = config.txtCompactEnabled && manualTXTExclusions.isEmpty ? ["原始通过：\(preFullPackageBetCount)注；实际补注：\(max(0, finalBetCount - preFullPackageBetCount))注"] : []
        return (["最终：\(finalBetCount)注", "TXT投注总行数：\(displayResultLines.count)行（不含说明行）"] + manualTXTExclusions.map(\.summary) + supplemental + results).joined(separator: "\n")
    }
}

struct OverallOddsForecast: Equatable, Sendable {
    let medianProduct: Double
    let threshold: Double
    let weakestPosition: Int
    let weakestMedianSelectedOdd: Double

    var isLow: Bool { medianProduct < threshold }
}

enum SequenceFilterEngine {
    static let eTXTMaximumRows = 15

    /// Assign complete TXT rows, never split or duplicate bets. Row counts have
    /// priority; an optional E cap sends every remaining row to F.
    static func balancedTXTPartitionIndices(rowWeights: [Int], maximumERows: Int? = nil) -> [[Int]] {
        let balancedECount = (rowWeights.count + 1) / 2
        let eCount = maximumERows.map { min(balancedECount, max(0, $0)) } ?? balancedECount
        let limits = [eCount, rowWeights.count - eCount]
        var indices: [[Int]] = [[], []]
        var weights = [0, 0]
        let ordered = rowWeights.indices.sorted {
            rowWeights[$0] == rowWeights[$1] ? $0 < $1 : rowWeights[$0] > rowWeights[$1]
        }
        for index in ordered {
            let side: Int
            if indices[0].count == limits[0] { side = 1 }
            else if indices[1].count == limits[1] { side = 0 }
            else if weights[0] != weights[1] { side = weights[0] < weights[1] ? 0 : 1 }
            else { side = indices[0].count <= indices[1].count ? 0 : 1 }
            indices[side].append(index)
            weights[side] += max(0, rowWeights[index])
        }
        return indices.map { $0.sorted() }
    }

    private static let outcomeOrder = [3, 1, 0]

    /// 以最终实际导出的每一注为样本，用六场项目自定义赔率乘积的中位数
    /// 判断整体赔率水平。这是生成前风险门禁，不改动任何一注的过滤条件。
    static func overallOddsForecast(
        bets: [[Int]],
        customOdds: [[Double]],
        threshold: Double = 500
    ) -> OverallOddsForecast? {
        let matchCount = 6
        guard !bets.isEmpty,
              customOdds.count >= matchCount,
              threshold.isFinite,
              threshold > 0,
              customOdds.prefix(matchCount).allSatisfy({ row in
                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
              }),
              bets.allSatisfy({ bet in
                  bet.count >= matchCount && bet.prefix(matchCount).allSatisfy { outcomeOrder.contains($0) }
              }) else { return nil }

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        let selectedRows: [[Double]] = (0..<matchCount).map { position in
            bets.map { bet in
                let outcome = bet[position]
                let column = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
                return customOdds[position][column]
            }
        }
        let products = bets.map { bet in
            (0..<matchCount).reduce(1.0) { partial, position in
                let outcome = bet[position]
                let column = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
                return partial * customOdds[position][column]
            }
        }
        let positionMedians = selectedRows.map(median)
        guard let weakestIndex = positionMedians.indices.min(by: {
            if abs(positionMedians[$0] - positionMedians[$1]) > 1e-12 {
                return positionMedians[$0] < positionMedians[$1]
            }
            return $0 < $1
        }) else { return nil }
        return OverallOddsForecast(
            medianProduct: median(products),
            threshold: threshold,
            weakestPosition: weakestIndex + 1,
            weakestMedianSelectedOdd: positionMedians[weakestIndex]
        )
    }

    /// 只有ABCD、没有实时赔率时使用的保守范围。
    /// ABCD决定3/1/0到判定值的映射；固定先验避免网络失败时无法更新主条件。
    static func recommendedConditions(logic: [LogicMapping]) -> RecommendedFilterConditions? {
        guard (2...8).contains(logic.count) else { return nil }
        let impliedProbabilities = logic.map { mapping in
            let inverse = mapping.values.map { 1.0 / Double($0) }
            let total = inverse.reduce(0, +)
            return inverse.map { $0 / total }
        }
        return recommendedConditions(
            logic: logic,
            outcomeProbabilities: impliedProbabilities
        )
    }

    /// 依据ABCD映射及泊松模型的3/1/0概率，为主条件生成一组保守默认值。
    /// 每项约留1%的边缘概率，五项叠加按并集上界控制在约5%以内。
    static func recommendedConditions(
        logic: [LogicMapping],
        outcomeProbabilities: [[Double]]
    ) -> RecommendedFilterConditions? {
        guard (2...8).contains(logic.count),
              outcomeProbabilities.count == logic.count,
              outcomeProbabilities.allSatisfy({ row in
                  row.count == 3
                      && row.allSatisfy { $0 >= 0 && $0.isFinite }
                      && row.reduce(0, +) > 0
              }) else { return nil }
        let probabilities = outcomeProbabilities.map { row in
            let total = row.reduce(0, +)
            return row.map { $0 / total }
        }
        struct Sample {
            let sum: Int
            let displacement: Int
            let variance: Double
            let valueTwoCount: Int
            let transitionPercent: Double
            let weight: Double
        }
        let samples = cartesianOutcomes(count: logic.count).map { outcomes in
            let values = zip(logic, outcomes).map { $0.value(for: $1) }
            let sum = values.reduce(0, +)
            let displacement = zip(values, values.dropFirst())
                .reduce(0) { $0 + abs($1.1 - $1.0) }
            let mean = Double(sum) / Double(values.count)
            let variance = values.reduce(0.0) { partial, value in
                let delta = Double(value) - mean
                return partial + delta * delta
            } / Double(values.count)
            let weight = zip(outcomes, probabilities).reduce(1.0) { partial, pair in
                let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                return partial * pair.1[index]
            }
            return Sample(
                sum: sum,
                displacement: displacement,
                variance: variance,
                valueTwoCount: values.filter { $0 == 2 }.count,
                transitionPercent: markovProbability(values) * 100,
                weight: weight
            )
        }
        func quantile(_ percentile: Double, value: (Sample) -> Double) -> Double {
            let ordered = samples.sorted { value($0) < value($1) }
            let total = ordered.reduce(0.0) { $0 + $1.weight }
            let target = min(max(percentile, 0), 1) * total
            var cumulative = 0.0
            for sample in ordered {
                cumulative += sample.weight
                if cumulative + 1e-15 >= target { return value(sample) }
            }
            return ordered.last.map(value) ?? 0
        }
        let sumLower = Int(quantile(0.005) { Double($0.sum) }.rounded())
        let sumUpper = Int(quantile(0.995) { Double($0.sum) }.rounded())
        let displacementLower = Int(quantile(0.005) { Double($0.displacement) }.rounded())
        let displacementUpper = Int(quantile(0.995) { Double($0.displacement) }.rounded())
        return RecommendedFilterConditions(
            sumRange: min(sumLower, sumUpper)...max(sumLower, sumUpper),
            displacementRange: min(displacementLower, displacementUpper)...max(displacementLower, displacementUpper),
            varianceMaximum: quantile(0.99) { $0.variance },
            valueTwoMaximum: Int(quantile(0.99) { Double($0.valueTwoCount) }.rounded()),
            transitionMinimumPercent: quantile(0.01) { $0.transitionPercent }
        )
    }

    static func calculate(
        _ config: FilterConfig,
        previousContext: PreviousResultContext?,
        currentOutcomeProbabilities: [[Double]]? = nil,
        currentOutcomeSPs: [[Double]]? = nil,
        vip4Context: VIP4MatchContext? = nil,
        vip3Context: VIP3MatchContext? = nil,
        currentMarketBettingShares: [[Double]] = [],
        applyPoissonRelationshipCondition: Bool = true,
        comprehensiveAnalysisProfile: ComprehensiveAnalysisProfile? = nil,
        comprehensiveAnalysisToleranceRange: ClosedRange<Int> = 0...0,
        protectedHistoryProfile: ComprehensiveAnalysisProfile? = nil,
        protectedHistoryToleranceRange: ClosedRange<Int> = 0...0,
        protectedHistoryBetCap: Int? = nil,
        protectedPrizeOutcomePrefixes: Set<[Int]> = [],
        captureQueryStages: Bool = false
    ) -> FilterResult {
        // These operations are deliberately outside every package switch,
        // tolerance, recovery, ranking and TXT supplementation stage.
        if config.hasFinalResultFilters {
            var baseConfig = config
            baseConfig.finalResultInverted = false
            baseConfig.finalOutcomeExclusions = []
            baseConfig.historicalOutcomeWindows = []
            baseConfig.automaticFinalOutcomeExclusions = false
            let base = calculate(baseConfig, previousContext: previousContext,
                currentOutcomeProbabilities: currentOutcomeProbabilities,
                currentOutcomeSPs: currentOutcomeSPs, vip4Context: vip4Context, vip3Context: vip3Context,
                currentMarketBettingShares: currentMarketBettingShares,
                applyPoissonRelationshipCondition: applyPoissonRelationshipCondition,
                comprehensiveAnalysisProfile: comprehensiveAnalysisProfile,
                comprehensiveAnalysisToleranceRange: comprehensiveAnalysisToleranceRange,
                protectedHistoryProfile: protectedHistoryProfile,
                protectedHistoryToleranceRange: protectedHistoryToleranceRange,
                protectedHistoryBetCap: protectedHistoryBetCap,
                protectedPrizeOutcomePrefixes: protectedPrizeOutcomePrefixes,
                captureQueryStages: captureQueryStages)
            var final = applyingFinalResultFilters(to: base, requestedConfig: config,
                currentOutcomeSPs: currentOutcomeSPs, captureQueryStages: captureQueryStages)
            final.requestedGenerationSignature = config.generationRequestSignature
            return final
        }
        if config.svip11BreakpointOnlyEnabled {
            let input = FilterConfig.svip11Input(numbers: config.matchNumbers, logic: config.logic.map(\.displayName).joined(), extras: config.extraMatches.map { "\($0.matchNumber):\($0.compactOutcomes)" }, enabled: config.conditionPackageEnabled, noFourPosition: config.noFourPositions.first, sumRange: "\(config.sumRange.lowerBound)-\(config.sumRange.upperBound)", mRange: "\(config.displacementRange.lowerBound)-\(config.displacementRange.upperBound)", breakpointRange: "\(config.breakpointRange.lowerBound)-\(config.breakpointRange.upperBound)", adaptiveS: config.oddsAdaptiveSRangeEnabled)
            let isolated = try! FilterConfig.parse(config.preservingConditionSwitches(in: input))
            if isolated.normalizedInput != config.normalizedInput || previousContext != nil || applyPoissonRelationshipCondition
                || comprehensiveAnalysisProfile != nil || protectedHistoryProfile != nil || protectedHistoryBetCap != nil || !protectedPrizeOutcomePrefixes.isEmpty {
                return calculate(isolated, previousContext: nil, currentOutcomeProbabilities: currentOutcomeProbabilities, currentOutcomeSPs: currentOutcomeSPs, applyPoissonRelationshipCondition: false, captureQueryStages: captureQueryStages)
            }
        }
        if config.svip10Frozen160Enabled {
            let input = FilterConfig.svip10Input(numbers: config.matchNumbers, logic: config.logic.map(\.displayName).joined(), extras: config.extraMatches.map { "\($0.matchNumber):\($0.compactOutcomes)" }, enabled: config.conditionPackageEnabled, scoreRange: "\(config.six250ScoreLower)-\(config.six250ScoreUpper)", noFourPosition: config.noFourPositions.first, sumRange: "\(config.six250SumRange.lowerBound)-\(config.six250SumRange.upperBound)", mRange: "\(config.six250MRange.lowerBound)-\(config.six250MRange.upperBound)", additionalFilters: config.svip10AdditionalFilters)
            let frozen = try! FilterConfig.parse(config.preservingConditionSwitches(in: input))
            if frozen.normalizedInput != config.normalizedInput || previousContext != nil || applyPoissonRelationshipCondition
                || comprehensiveAnalysisProfile != nil || protectedHistoryProfile != nil || protectedHistoryBetCap != nil || !protectedPrizeOutcomePrefixes.isEmpty {
                return calculate(frozen, previousContext: nil, currentOutcomeProbabilities: currentOutcomeProbabilities, currentOutcomeSPs: currentOutcomeSPs, applyPoissonRelationshipCondition: false, captureQueryStages: captureQueryStages)
            }
        }
        // SVIP7 is a complete, frozen package. Caller-side legacy profiles or
        // previous outcomes must not silently intersect its historical rule.
        if config.svip7RankOddsEnabled && (previousContext != nil || applyPoissonRelationshipCondition
            || comprehensiveAnalysisProfile != nil || protectedHistoryProfile != nil
            || protectedHistoryBetCap != nil || !protectedPrizeOutcomePrefixes.isEmpty) {
            return calculate(config, previousContext: nil,
                             currentOutcomeProbabilities: currentOutcomeProbabilities,
                             currentOutcomeSPs: currentOutcomeSPs,
                             applyPoissonRelationshipCondition: false,
                             captureQueryStages: captureQueryStages)
        }
        if !config.conditionPackageEnabled {
            let extras = config.extraMatches.map { "\($0.matchNumber):\($0.compactOutcomes)" }
            let independentRules = config.hasIndependentConditionGroups
                ? config.independentOutcomeConditions.map { condition in
                    let range = config.outcomeConditions[condition]!
                    return "OC_\(condition.rawValue)=\(range.lowerBound)-\(range.upperBound)"
                } + (config.highPass93GroupEnabled == true ? ["HP93GROUP=1"] : [])
                    + (config.highPass98GroupEnabled == true ? ["HP98GROUP=1"] : [])
                    + (config.highPass98FiftyGroupEnabled == true ? ["HP98FIFTYGROUP=1"] : [])
                    + (config.highPass50DoubleActive ? ["HP50DOUBLE=1"] : [])
                    + ["CALCCOUNT=6", "SUMCOUNT=6", "MCOUNT=6"] : []
            let plain = ([config.matchNumbers.joined(separator: ","), config.logic.map(\.rawValue).joined(),
                          "0-24", "0-100", "100", "6", "0", "100", "0-5", "QDROP0", "FINAL=OFF", "NO4="]
                         + independentRules + extras + ["MERGE3"]).joined(separator: "|")
            let unrestricted = try! FilterConfig.parse(plain)
            var result = calculate(unrestricted, previousContext: nil,
                                   currentOutcomeProbabilities: currentOutcomeProbabilities,
                                   currentOutcomeSPs: currentOutcomeSPs,
                                   applyPoissonRelationshipCondition: false,
                                   captureQueryStages: captureQueryStages)
            result.config = config
            return result
        }
        var requestedConfig = config
        if requestedConfig.svip10AdditionalFilters.highestDoubleProbabilityNoFourEnabled
            || requestedConfig.svip10AdditionalFilters.firstDoubleActive {
            requestedConfig.resolvedHighestDoubleProbabilityNoFourPosition =
                requestedConfig.highestDoubleProbabilityNoFourPosition(in: currentOutcomeSPs)
        }
        if requestedConfig.svip10AdditionalFilters.secondDoubleActive,
           let selection = svip10SecondDoubleSelection(
               config: requestedConfig,
               currentOutcomeProbabilities: currentOutcomeProbabilities,
               customOdds: currentOutcomeSPs
           ) {
            requestedConfig.resolvedSecondDoublePosition = selection.position
            requestedConfig.resolvedSecondDoubleRemovedOutcome = selection.removedOutcome
            requestedConfig.resolvedSecondDoubleProbability = selection.doubleProbability
            requestedConfig.resolvedSecondDoubleUsesModelProbability = selection.usesModelProbability
        }
        var config = config
        if config.six250RelationshipEnabled || config.svip7RankOddsEnabled {
            let extras = config.extraMatches.map { "\($0.matchNumber):\($0.compactOutcomes)" }
            let plain = ([config.matchNumbers.joined(separator: ","), config.logic.map(\.rawValue).joined(),
                          "0-24", "0-100", "100", "6", "0", "100", "0-5", "QDROP0", "FINAL=OFF", "NO4="]
                         + extras + ["MERGE3"]).joined(separator: "|")
            config = try! FilterConfig.parse(plain)
            config.additionalSumRange = requestedConfig.additionalSumRange
            config.oddsAdaptiveSRangeEnabled = requestedConfig.oddsAdaptiveSRangeEnabled
            config.outcomeConditions = requestedConfig.outcomeConditions
            config.highPass93GroupEnabled = requestedConfig.highPass93GroupEnabled
            config.highPass98GroupEnabled = requestedConfig.highPass98GroupEnabled
            config.highPass98FiftyGroupEnabled = requestedConfig.highPass98FiftyGroupEnabled
            config.highPass50DoubleEnabled = requestedConfig.highPass50DoubleEnabled
        }
        if config.lowestCustomOddsNoFourEnabled {
            config.resolvedLowestCustomOddsNoFourPosition = config.lowestCustomOddsNoFourPosition(in: currentOutcomeSPs)
        }
        var allOutcomes = cartesianOutcomes(count: config.matchNumbers.count)
        var svip10CoreOutcomes: [[Int]] = []
        var queryStages: [FilterQueryStage] = []
        func trace(_ name: String, _ bets: [[Int]], details: [[Int]: String] = [:]) {
            guard captureQueryStages else { return }
            queryStages.append(FilterQueryStage(name: name, survivors: Set(bets.map { Array($0.prefix(6)) }), failureDetails: details))
        }
        func traceMain(_ name: String, _ records: [SequenceRecord]) {
            guard captureQueryStages else { return }
            trace(name, records.flatMap { record in
                cartesianOptions(record.outcomes.map { [$0] } + config.extraMatches.map(\.outcomes))
            })
        }
        if captureQueryStages {
            trace("输入全集", cartesianOptions(Array(repeating: outcomeOrder, count: config.matchNumbers.count)
                + config.extraMatches.map(\.outcomes)))
        }
        if requestedConfig.six250RelationshipEnabled {
            var rules = ["六场S=\(requestedConfig.six250SumRange)", "六场实际M=\(requestedConfig.six250MRange)", "六场R=\(requestedConfig.six250RRange)", "六场判定值3最多\(requestedConfig.valueThreeMaximum)个", "自定义赔率综合分\(requestedConfig.six250ScoreLower)–\(requestedConfig.six250ScoreUpper)", "指定场次不是4"]
            if requestedConfig.svip10Frozen160Enabled { rules.append("六场判定值2最多\(requestedConfig.valueTwoMaximum)个") }
            for (index, name) in rules.enumerated() {
                var details: [[Int]: String] = [:]
                allOutcomes = allOutcomes.filter { outcomes in
                    let reasons = six250FailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: index)
                    if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                    return reasons.isEmpty
                }
                trace(name, allOutcomes, details: details)
            }
            if requestedConfig.svip10Frozen160Enabled {
                svip10CoreOutcomes = allOutcomes
                let additions = requestedConfig.svip10AdditionalFilters
                if additions.coldCountEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 0)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场赔率第三选个数\(additions.coldCountRange)", allOutcomes, details: details)
                }
                if additions.drawCountEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 1)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场平局个数\(additions.drawCountRange)", allOutcomes, details: details)
                }
                if additions.winLossSwitchEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 2)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场胜负直接切换0–2次", allOutcomes, details: details)
                }
                if additions.highestDoubleProbabilityNoFourEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 3)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    let selection = requestedConfig.highestDoubleProbabilityNoFourSelection(in: currentOutcomeSPs)
                    let title = selection.map {
                        "双选概率最高的第\($0.position)场（\(requestedConfig.matchNumbers[$0.position - 1])，\(String(format: "%.2f", $0.probability * 100))%）判定值不是4"
                    } ?? "双选概率最高场次判定值不是4（赔率不足）"
                    trace(title, allOutcomes, details: details)
                }
                if additions.firstDoubleActive {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 13)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    let selection = requestedConfig.highestDoubleProbabilityNoFourSelection(in: currentOutcomeSPs)
                    let title = selection.map {
                        additions.usesAutomaticDoubleSelection && !additions.doubleJudgmentFactors.isEmpty
                            ? "多因素第一双选第\($0.position)场（\(requestedConfig.matchNumbers[$0.position - 1])，赔率基础覆盖\(String(format: "%.2f", $0.probability * 100))%）；保留排序选中的两项"
                            : "最适合双选的第\($0.position)场（\(requestedConfig.matchNumbers[$0.position - 1])，\(additions.calibratedDoubleSelectionEnabled ? "校正双选概率" : "双选概率")\(String(format: "%.2f", $0.probability * 100))%）剔除第三选"
                    } ?? "最适合双选场次剔除第三选（赔率不足）"
                    trace(additions.adDoublesWithinSixEnabled ? "六场内\(additions.adDoubleCountWithinSix == 1 ? "唯一" : "第一")处A/D双选：A31、D10（位置不固定）" : additions.fixedFrontTwoDoublesEnabled ? "第1场按本次倾向双选31或10（1保底）" : title, allOutcomes, details: details)
                }
                if additions.secondDoubleActive {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 14)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    let title: String
                    if let position = requestedConfig.resolvedSecondDoublePosition,
                       let removedOutcome = requestedConfig.resolvedSecondDoubleRemovedOutcome,
                       let probability = requestedConfig.resolvedSecondDoubleProbability,
                       requestedConfig.matchNumbers.indices.contains(position - 1),
                       requestedConfig.logic.indices.contains(position - 1) {
                        let mappedValue = requestedConfig.logic[position - 1].value(for: removedOutcome)
                        let basis = additions.usesAutomaticDoubleSelection && !additions.doubleJudgmentFactors.isEmpty ? "多因素选择；赔率基础" : additions.calibratedDoubleSelectionEnabled ? "校正自定义赔率概率" : (requestedConfig.resolvedSecondDoubleUsesModelProbability ? "综合概率" : "赔率概率")
                        title = "第二个双选第\(position)场（\(requestedConfig.matchNumbers[position - 1])，\(basis)覆盖\(String(format: "%.2f", probability * 100))%）去掉\(removedOutcome)／判定值\(mappedValue)"
                    } else {
                        title = "第二个双选场次去掉最低概率项（概率不足）"
                    }
                    trace(additions.adDoublesWithinSixEnabled ? "六场内第二处A/D双选：A31、D10（位置不固定）" : additions.fixedFrontTwoDoublesEnabled ? "第2场独立按本次倾向双选31或10（1保底）" : title, allOutcomes, details: details)
                }
                if additions.fiveMatchMEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 4)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场实际顺序M=\(additions.fiveMatchMRange.lowerBound)–\(additions.fiveMatchMRange.upperBound)", allOutcomes, details: details)
                }
                if additions.frontFiveSameOutcomeRunMaximum2Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 5)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场同彩果最长连续≤2场", allOutcomes, details: details)
                }
                if additions.frontFiveReturnMaximum2Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 6)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场隔场回返≤2次", allOutcomes, details: details)
                }
                if additions.frontFiveNoConsecutiveDrawEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 7)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场不出现连续平局", allOutcomes, details: details)
                }
                if additions.frontFiveValueThreeMaximum2Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 8)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前5场判定值3最多2个", allOutcomes, details: details)
                }
                if additions.sixMatchFavoriteCount2To4Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 9)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场自定义赔率第一选2–4个", allOutcomes, details: details)
                }
                if additions.sixMatchFavoriteCount1To4Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 15)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场自定义赔率第一选1–4个", allOutcomes, details: details)
                }
                if additions.sixMatchMinimumOddsProductEnabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 10)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增前六场自定义赔率乘积≥\(String(format: "%.0f", additions.sixMatchMinimumOddsProduct))", allOutcomes, details: details)
                }
                if additions.sixMatchBreakpoint2To4Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 11)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场彩果断点B=2–4", allOutcomes, details: details)
                }
                if additions.sixMatchBreakpoint3To5Enabled {
                    var details: [[Int]: String] = [:]
                    allOutcomes = allOutcomes.filter { outcomes in
                        let reasons = svip10AdditionalFailureReasons(outcomes: outcomes, config: requestedConfig, customOdds: currentOutcomeSPs, onlyRule: 12)
                        if captureQueryStages && !reasons.isEmpty { details[outcomes] = reasons.joined(separator: "；") }
                        return reasons.isEmpty
                    }
                    trace("新增六场彩果断点B=\(additions.sixMatchBreakpointRange.lowerBound)–\(additions.sixMatchBreakpointRange.upperBound)", allOutcomes, details: details)
                }
                if additions.topThreeProbabilityRecovery100Enabled {
                    let base = Set(allOutcomes)
                    let rulesToKeep = [0, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 14]
                    let relaxed = svip10CoreOutcomes.filter { outcomes in
                        rulesToKeep.allSatisfy { rule in
                            svip10AdditionalFailureReasons(
                                outcomes: outcomes, config: requestedConfig,
                                customOdds: currentOutcomeSPs, onlyRule: rule
                            ).isEmpty
                        }
                    }
                    let probabilityRows: [[Double]]? = {
                        if let probabilities = currentOutcomeProbabilities,
                           probabilities.count >= requestedConfig.matchNumbers.count,
                           probabilities.prefix(requestedConfig.matchNumbers.count).allSatisfy({ row in
                               row.count == 3 && row.allSatisfy { $0.isFinite && $0 >= 0 } && row.reduce(0, +) > 0
                           }) {
                            return probabilities.prefix(requestedConfig.matchNumbers.count).map { row in
                                let total = row.reduce(0, +)
                                return row.map { $0 / total }
                            }
                        }
                        guard let odds = currentOutcomeSPs,
                              odds.count >= requestedConfig.matchNumbers.count,
                              odds.prefix(requestedConfig.matchNumbers.count).allSatisfy({ row in
                                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
                              }) else { return nil }
                        return odds.prefix(requestedConfig.matchNumbers.count).map { row in
                            let inverse = row.map { 1 / $0 }
                            let total = inverse.reduce(0, +)
                            return inverse.map { $0 / total }
                        }
                    }()
                    if let probabilityRows {
                        let pool = relaxed.filter { !base.contains($0) }
                        let recovered = pool.sorted { left, right in
                            func score(_ outcomes: [Int]) -> Double {
                                (0..<min(outcomes.count, probabilityRows.count)).reduce(0.0) { partial, index in
                                    let outcomeIndex = outcomes[index] == 3 ? 0 : (outcomes[index] == 1 ? 1 : 2)
                                    return partial + log(max(probabilityRows[index][outcomeIndex], 1e-15))
                                }
                            }
                            let leftScore = score(left)
                            let rightScore = score(right)
                            if abs(leftScore - rightScore) > 1e-15 { return leftScore > rightScore }
                            return left.lexicographicallyPrecedes(right, by: >)
                        }.prefix(100)
                        allOutcomes = Array(base.union(recovered)).sorted {
                            $0.lexicographicallyPrecedes($1, by: >)
                        }
                    }
                    trace("联合概率优先补回最多100注", allOutcomes)
                }
            }
        }
        if requestedConfig.svip7RankOddsEnabled {
            for (index, name) in svip7RuleTitles.enumerated() {
                allOutcomes = allOutcomes.filter {
                    svip7FailureReasons(outcomes: $0, customOdds: currentOutcomeSPs, onlyRule: index, disabled: requestedConfig.disabledBasicConditions).isEmpty
                }
                trace(name, allOutcomes)
            }
        }
        if config.isEnabled(.sum), let range = config.additionalSumRange {
            allOutcomes = allOutcomes.filter { outcomes in
                range.contains(zip(config.logic, outcomes).reduce(0) { $0 + $1.0.value(for: $1.1) })
            }
            trace("新增固定S=\(range.lowerBound)–\(range.upperBound)", allOutcomes)
        }
        let adaptiveSRange = config.isEnabled(.sum) && config.oddsAdaptiveSRangeEnabled
            ? oddsAdaptiveSRange(logic: config.logic, customOdds: currentOutcomeSPs) : nil
        if config.isEnabled(.sum) && config.oddsAdaptiveSRangeEnabled {
            allOutcomes = allOutcomes.filter { outcomes in
                guard let adaptiveSRange else { return false }
                let sum = zip(config.logic, outcomes).reduce(0) { $0 + $1.0.value(for: $1.1) }
                return adaptiveSRange.contains(sum)
            }
            let title = adaptiveSRange.map { "赔率自适应S=\($0.lowerBound)–\($0.upperBound)" } ?? "赔率自适应S：缺少六场自定义赔率"
            trace(title, allOutcomes)
        }
        var rankedProductOutcomes: [(index: Int, outcomes: [Int], product: Int)] = []
        rankedProductOutcomes.reserveCapacity(allOutcomes.count)
        for (index, outcomes) in allOutcomes.enumerated() {
            let values = zip(config.logic, outcomes).map { mapping, outcome in
                mapping.value(for: outcome)
            }
            rankedProductOutcomes.append(
                (index: index, outcomes: outcomes, product: values.reduce(1, *))
            )
        }
        rankedProductOutcomes.sort { left, right in
            if left.product != right.product { return left.product < right.product }
            return left.index < right.index
        }
        let factor = config.extraExpansionFactor
        // 乘积Q精确删注已取消，任何调用方都不能再把第六场全包拆成部分选项。
        let productRemovalLimit = 0
        let fullRemovalCount = productRemovalLimit / factor
        let partialRemovalCount = productRemovalLimit % factor
        let productRemovedOutcomes = Set(
            rankedProductOutcomes.prefix(fullRemovalCount).map { $0.outcomes }
        )
        let partialOutcomes = partialRemovalCount > 0 ? rankedProductOutcomes[fullRemovalCount].outcomes : nil
        func betCount(_ records: [SequenceRecord]) -> Int {
            records.reduce(0) { count, record in
                count + factor - (record.outcomes == partialOutcomes ? partialRemovalCount : 0)
            }
        }
        var afterSum: [SequenceRecord] = []
        var afterDisplacement: [SequenceRecord] = []
        var afterVariance: [SequenceRecord] = []
        var afterValueTwo: [SequenceRecord] = []
        var afterTransition: [SequenceRecord] = []
        var afterRoughness: [SequenceRecord] = []
        var accepted: [SequenceRecord] = []
        var afterBreakpoint: [SequenceRecord] = []
        var allRecords: [SequenceRecord] = []

        func selectedMetricOdds(outcomes: [Int]) -> [Double]? {
            let scoped = config.metricOutcomes(in: outcomes)
            guard let rows = currentOutcomeSPs, rows.count >= scoped.count else { return nil }
            var selected: [Double] = []
            for (row, outcome) in zip(rows.prefix(scoped.count), scoped) {
                guard row.count == 3,
                      row.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
                selected.append(row[outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)])
            }
            return selected
        }

        for outcomes in allOutcomes {
            let values = zip(config.logic, outcomes).map { $0.value(for: $1) }
            let metricValues = config.metricValues(in: values)
            let metricOutcomes = config.metricOutcomes(in: outcomes)
            let mappedSum = config.sumValues(in: values).reduce(0, +)
            let metricSum = metricValues.reduce(0, +)
            let realOddsSum = config.sumUsesOutcomeSP
                ? selectedMetricOdds(outcomes: outcomes)?.reduce(0, +)
                : nil
            let displacement = config.displacementValue(in: values)
            let mean = Double(metricSum) / Double(metricValues.count)
            let variance = metricValues.reduce(0.0) { partial, value in
                let delta = Double(value) - mean
                return partial + delta * delta
            } / Double(metricValues.count)
            let transitionProbability = markovProbability(metricValues)
            let record = SequenceRecord(
                outcomes: outcomes,
                values: values,
                sum: mappedSum,
                displacement: displacement,
                variance: variance,
                transitionProbability: transitionProbability,
                realOddsSum: realOddsSum
            )
            allRecords.append(record)
            guard !productRemovedOutcomes.contains(outcomes) else { continue }
            if config.allConditionsToleranceEnabled {
                accepted.append(record)
                continue
            }
            let passesSum = config.sumUsesOutcomeSP
                ? realOddsSum.map {
                    Double(config.sumRange.lowerBound) <= $0 && $0 <= Double(config.sumRange.upperBound)
                } == true
                : config.sumRange.contains(mappedSum)
            guard !config.isEnabled(.sum) || passesSum else { continue }
            afterSum.append(record)
            guard config.passesDisplacement(in: values) else { continue }
            afterDisplacement.append(record)
            guard !config.isEnabled(.variance) || variance <= config.varianceMaximum + 1e-12 else { continue }
            afterVariance.append(record)
            let valueTwoCount = metricValues.filter { $0 == 2 }.count
            guard !config.isEnabled(.valueTwo) || valueTwoCount <= config.valueTwoMaximum else { continue }
            afterValueTwo.append(record)
            guard !config.isEnabled(.transition) || transitionProbability + 1e-12 >= config.transitionMinimumPercent / 100 else { continue }
            afterTransition.append(record)
            let roughness = secondOrderRoughness(metricValues)
            guard !config.isEnabled(.roughness) || roughness <= config.roughnessMaximum else { continue }
            afterRoughness.append(record)
            let breakpoints = outcomeBreakpoints(metricOutcomes)
            guard !config.isEnabled(.breakpoints) || config.breakpointRange.contains(breakpoints) else { continue }
            afterBreakpoint.append(record)
            guard !config.lowestCustomOddsNoFourEnabled || config.resolvedLowestCustomOddsNoFourPosition != nil else { continue }
            guard config.activeNoFourPositions.allSatisfy({ values[$0 - 1] != 4 }) else { continue }
            if let maximum = config.frontThreeMaximumFourCount {
                guard values.prefix(3).filter({ $0 == 4 }).count <= maximum else { continue }
            }
            accepted.append(record)
        }

        if !config.allConditionsToleranceEnabled {
            traceMain(config.sumUsesOutcomeSP ? "自定义赔率和S范围校验（\(config.sumRange)，须完整自定义赔率）" : "判定总和S不在\(config.sumRange)", afterSum)
            traceMain(config.minimumDistinctDisplacementOrders > 0
                ? "前五场有效M排列不足\(config.minimumDistinctDisplacementOrders)种（M=\(config.displacementRange)）"
                : "位移M不在\(config.displacementRange)", afterDisplacement)
            traceMain("稳定性σ²超过\(config.varianceMaximum)", afterVariance)
            traceMain("判定值2次数超过\(config.valueTwoMaximum)", afterValueTwo)
            traceMain("马尔可夫P_tr低于\(config.transitionMinimumPercent)%", afterTransition)
            traceMain("二阶波动R超过\(config.roughnessMaximum)", afterRoughness)
            traceMain("最终彩果断点B不在\(config.breakpointRange)", afterBreakpoint)
        }

        // “某一场不是4”的两个开关是两个独立过滤阶段。
        // 生成记录在上面一次遍历中完成，这里依次回放条件以保留每个阶段的准确注数。
        var noFourStageBetCounts: [Int] = []
        if !config.allConditionsToleranceEnabled {
            var noFourStageRecords = afterBreakpoint
            for position in config.activeNoFourPositions {
                noFourStageRecords = noFourStageRecords.filter { $0.values[position - 1] != 4 }
                traceMain("第\(position)场判定值为4，违反指定场次禁4", noFourStageRecords)
                noFourStageBetCounts.append(betCount(noFourStageRecords))
            }
            if config.lowestCustomOddsNoFourEnabled,
               config.resolvedLowestCustomOddsNoFourPosition == nil {
                trace("最低概率场次禁4所需自定义赔率不足", [])
                noFourStageBetCounts.append(0)
            }
            if let maximum = config.frontThreeMaximumFourCount {
                noFourStageRecords = noFourStageRecords.filter {
                    $0.values.prefix(3).filter { $0 == 4 }.count <= maximum
                }
                traceMain("前三场判定值4次数超过\(maximum)", noFourStageRecords)
                noFourStageBetCounts.append(betCount(noFourStageRecords))
            }
        }
        var outcomeStageBetCounts: [Int] = []
        if !config.allConditionsToleranceEnabled,
           config.outcomeConditionToleranceEnabled,
           !config.enabledOutcomeConditions.isEmpty {
            accepted = accepted.filter { config.passesOutcomeConditions(config.metricOutcomes(in: $0.outcomes)) }
            traceMain("彩果条件超过允许容错\(config.outcomeConditionToleranceRange)", accepted)
            outcomeStageBetCounts.append(betCount(accepted))
        } else if !config.allConditionsToleranceEnabled {
            for condition in config.enabledOutcomeConditions {
                let range = config.outcomeConditions[condition]!
                accepted = accepted.filter {
                    range.contains(condition.value(in: config.metricOutcomes(in: $0.outcomes)))
                }
                traceMain("\(condition.title)不在\(range)", accepted)
                outcomeStageBetCounts.append(betCount(accepted))
            }
        }

        func selectedValues(_ matrix: [[Double]]?, outcomes: [Int], normalizeRows: Bool = false) -> [Double]? {
            guard let matrix, matrix.count >= outcomes.count else { return nil }
            var selected: [Double] = []
            selected.reserveCapacity(outcomes.count)
            for (row, outcome) in zip(matrix.prefix(outcomes.count), outcomes) {
                guard row.count == 3,
                      row.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
                let index = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
                if normalizeRows {
                    let total = row.reduce(0, +)
                    guard total > 0 else { return nil }
                    selected.append(row[index] / total)
                } else {
                    selected.append(row[index])
                }
            }
            return selected
        }
        var advancedStageBetCounts: [Int] = []
        if !config.allConditionsToleranceEnabled && config.spProductFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeSPs, outcomes: config.metricOutcomes(in: record.outcomes)) else { return false }
                return config.spProductRange.contains(values.reduce(1, *))
            }
            traceMain("自定义赔率乘积范围（原SP乘积开关）", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.customHandicapOddsProductFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(
                    currentOutcomeSPs,
                    outcomes: config.customHandicapOddsProductOutcomes(in: record.outcomes)
                ) else { return false }
                let product = values.reduce(1, *)
                return Double(config.customHandicapOddsProductRange.lowerBound) <= product
                    && product <= Double(config.customHandicapOddsProductRange.upperBound)
            }
            traceMain("自定义让球赔率乘积校验（范围\(config.customHandicapOddsProductRange)，须完整自定义赔率）", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.customHandicapOddsSumFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeSPs, outcomes: config.metricOutcomes(in: record.outcomes)) else { return false }
                let sum = values.reduce(0, +)
                return Double(config.customHandicapOddsSumRange.lowerBound) <= sum
                    && sum <= Double(config.customHandicapOddsSumRange.upperBound)
            }
            traceMain("自定义让球赔率和值校验（范围\(config.customHandicapOddsSumRange)，须完整自定义赔率）", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.prizeRangeFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeSPs, outcomes: config.metricOutcomes(in: record.outcomes)) else { return false }
                return config.estimatedPrizeRange.contains(values.reduce(1, *) * 1.3)
            }
            traceMain("预计奖金范围", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.spRiskFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeSPs, outcomes: config.metricOutcomes(in: record.outcomes)) else { return false }
                return (values.max() ?? 0) <= config.maximumSingleSP
                    && config.highSPCountRange.contains(values.filter { $0 > config.highSPThreshold }.count)
            }
            traceMain("单场赔率及高赔率场次数限制", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.minimumProbabilityFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeProbabilities, outcomes: config.metricOutcomes(in: record.outcomes), normalizeRows: true) else { return false }
                return (values.min() ?? 0) * 100 + 1e-12 >= config.minimumSingleProbabilityPercent
            }
            traceMain("最低单场概率门槛", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.jointProbabilityFilterEnabled {
            accepted = accepted.filter { record in
                guard let values = selectedValues(currentOutcomeProbabilities, outcomes: config.metricOutcomes(in: record.outcomes), normalizeRows: true) else { return false }
                return config.jointProbabilityPercentRange.contains(values.reduce(1, *) * 100)
            }
            traceMain("整串联合概率范围", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }
        if !config.allConditionsToleranceEnabled && config.groupFilterEnabled {
            accepted = accepted.filter { record in
                let scopedOutcomes = config.metricOutcomes(in: record.outcomes)
                let split = min(3, scopedOutcomes.count)
                let frontOutcomes = Array(scopedOutcomes.prefix(split))
                let backOutcomes = Array(scopedOutcomes.dropFirst(split))
                if config.groupFilterMode.usesOutcomeSum,
                   (!config.frontGroupOutcomeSumRange.contains(frontOutcomes.reduce(0, +))
                    || !config.backGroupOutcomeSumRange.contains(backOutcomes.reduce(0, +))) { return false }
                if config.groupFilterMode.usesSPProduct {
                    guard let values = selectedValues(currentOutcomeSPs, outcomes: scopedOutcomes) else { return false }
                    let frontProduct = values.prefix(split).reduce(1, *)
                    let backProduct = values.dropFirst(split).reduce(1, *)
                    if !config.frontGroupSPProductRange.contains(frontProduct)
                        || !config.backGroupSPProductRange.contains(backProduct) { return false }
                }
                return true
            }
            traceMain("前后组分组条件", accepted)
            advancedStageBetCounts.append(betCount(accepted))
        }

        // 联合概率二次过滤尚未启用：通过基础条件的组合全部保留。
        let probabilitySelection = ProbabilitySelectionOutput(
            kept: accepted,
            removed: [],
            modelCoveragePercent: 100,
            actualFilteredPercent: 0,
            usesCurrentMatchProbabilities: false,
            usesRelationshipCondition: false
        )
        var finalRecords = probabilitySelection.kept
        var compression = compress(finalRecords)
        // 完整保留的主组合可照常合并；边界主组合单独携带剩余固定场结果，防止补回已删注。
        let fullRecords = probabilitySelection.kept.filter { $0.outcomes != partialOutcomes }
        let fullCompression = partialRemovalCount == 0 ? compression : compress(fullRecords)
        var exportRecords = fullCompression.records.map {
            CompressedRecord(options: $0.options + config.extraMatches.map(\.outcomes), sourceRecords: $0.sourceRecords)
        }
        if let boundary = probabilitySelection.kept.first(where: { $0.outcomes == partialOutcomes }) {
            let fixedOutcomes = config.extraMatches.reduce([[Int]]([[]])) { prefixes, match in
                prefixes.flatMap { prefix in match.outcomes.map { prefix + [$0] } }
            }
            let remainingFixed = fixedOutcomes.dropFirst(partialRemovalCount).map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            for fixed in compress(remainingFixed).records {
                exportRecords.append(CompressedRecord(options: boundary.outcomes.map { [$0] } + fixed.options, sourceRecords: [boundary]))
            }
        }
        var allConditionsToleranceStageBetCounts: [Int] = []
        if config.allConditionsToleranceEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter { fullOutcomes in
                let mainOutcomes = Array(fullOutcomes.prefix(config.matchNumbers.count))
                let values = zip(config.logic, mainOutcomes).map { $0.value(for: $1) }
                let metricValues = config.metricValues(in: values)
                let metricOutcomes = config.metricOutcomes(in: mainOutcomes)
                let sum = config.sumValues(in: values).reduce(0, +)
                let metricSum = metricValues.reduce(0, +)
                let realOddsSum = config.sumUsesOutcomeSP
                    ? selectedValues(currentOutcomeSPs, outcomes: metricOutcomes)?.reduce(0, +)
                    : nil
                let displacement = config.displacementValue(in: values)
                let mean = Double(metricSum) / Double(metricValues.count)
                let variance = metricValues.reduce(0.0) { partial, value in
                    let delta = Double(value) - mean
                    return partial + delta * delta
                } / Double(metricValues.count)
                var failures = 0
                if config.isEnabled(.sum) && config.sumUsesOutcomeSP {
                    if realOddsSum.map({
                        Double(config.sumRange.lowerBound) <= $0
                            && $0 <= Double(config.sumRange.upperBound)
                    }) != true { failures += 1 }
                } else if config.isEnabled(.sum) && !config.sumRange.contains(sum) { failures += 1 }
                if !config.passesDisplacement(in: values) { failures += 1 }
                if config.isEnabled(.variance) && variance > config.varianceMaximum + 1e-12 { failures += 1 }
                if config.isEnabled(.valueTwo) && metricValues.filter({ $0 == 2 }).count > config.valueTwoMaximum { failures += 1 }
                if config.isEnabled(.transition) && markovProbability(metricValues) * 100 + 1e-12 < config.transitionMinimumPercent { failures += 1 }
                if config.isEnabled(.roughness) && secondOrderRoughness(metricValues) > config.roughnessMaximum { failures += 1 }
                if config.isEnabled(.breakpoints) && !config.breakpointRange.contains(outcomeBreakpoints(metricOutcomes)) { failures += 1 }
                failures += config.activeNoFourPositions.filter { values[$0 - 1] == 4 }.count
                if config.lowestCustomOddsNoFourEnabled,
                   config.resolvedLowestCustomOddsNoFourPosition == nil { failures += 1 }
                if let maximum = config.frontThreeMaximumFourCount,
                   values.prefix(3).filter({ $0 == 4 }).count > maximum { failures += 1 }
                if config.outcomeConditionToleranceEnabled,
                   !config.enabledOutcomeConditions.isEmpty {
                    // 彩果条件组有自己的容错：先按组内容错判定，
                    // 在全局容错中整组只算一个条件。
                    if !config.passesOutcomeConditions(metricOutcomes) { failures += 1 }
                } else {
                    failures += config.enabledOutcomeConditions.filter { condition in
                        guard let range = config.outcomeConditions[condition] else { return false }
                        return !range.contains(condition.value(in: metricOutcomes))
                    }.count
                }

                let spValues = selectedValues(currentOutcomeSPs, outcomes: metricOutcomes)
                let customProductSPValues = selectedValues(
                    currentOutcomeSPs,
                    outcomes: config.customHandicapOddsProductOutcomes(in: mainOutcomes)
                )
                let probabilityValues = selectedValues(
                    currentOutcomeProbabilities,
                    outcomes: metricOutcomes,
                    normalizeRows: true
                )
                if config.spProductFilterEnabled {
                    if let spValues {
                        if !config.spProductRange.contains(spValues.reduce(1, *)) { failures += 1 }
                    } else { failures += 1 }
                }
                if config.customHandicapOddsProductFilterEnabled {
                    if let customProductSPValues {
                        let product = customProductSPValues.reduce(1, *)
                        if product < Double(config.customHandicapOddsProductRange.lowerBound)
                            || product > Double(config.customHandicapOddsProductRange.upperBound) { failures += 1 }
                    } else { failures += 1 }
                }
                if config.customHandicapOddsSumFilterEnabled {
                    if let spValues {
                        let sum = spValues.reduce(0, +)
                        if sum < Double(config.customHandicapOddsSumRange.lowerBound)
                            || sum > Double(config.customHandicapOddsSumRange.upperBound) { failures += 1 }
                    } else { failures += 1 }
                }
                if config.prizeRangeFilterEnabled {
                    if let spValues {
                        if !config.estimatedPrizeRange.contains(spValues.reduce(1, *) * 1.3) { failures += 1 }
                    } else { failures += 1 }
                }
                if config.spRiskFilterEnabled {
                    if let spValues {
                        if (spValues.max() ?? 0) > config.maximumSingleSP
                            || !config.highSPCountRange.contains(spValues.filter { $0 > config.highSPThreshold }.count) {
                            failures += 1
                        }
                    } else { failures += 1 }
                }
                if config.minimumProbabilityFilterEnabled {
                    if let probabilityValues {
                        if (probabilityValues.min() ?? 0) * 100 + 1e-12 < config.minimumSingleProbabilityPercent {
                            failures += 1
                        }
                    } else { failures += 1 }
                }
                if config.jointProbabilityFilterEnabled {
                    if let probabilityValues {
                        if !config.jointProbabilityPercentRange.contains(probabilityValues.reduce(1, *) * 100) {
                            failures += 1
                        }
                    } else { failures += 1 }
                }
                if config.groupFilterEnabled {
                    let split = min(3, metricOutcomes.count)
                    var passes = true
                    if config.groupFilterMode.usesOutcomeSum {
                        passes = config.frontGroupOutcomeSumRange.contains(metricOutcomes.prefix(split).reduce(0, +))
                            && config.backGroupOutcomeSumRange.contains(metricOutcomes.dropFirst(split).reduce(0, +))
                    }
                    if config.groupFilterMode.usesSPProduct {
                        guard let spValues else { return false }
                        passes = passes
                            && config.frontGroupSPProductRange.contains(spValues.prefix(split).reduce(1, *))
                            && config.backGroupSPProductRange.contains(spValues.dropFirst(split).reduce(1, *))
                    }
                    if !passes { failures += 1 }
                }
                if config.consecutiveRunsEnabled {
                    // 连续彩果先应用其内部容错，全局只计整组通过/不通过一项。
                    if !config.passesConsecutiveRuns(fullOutcomes) { failures += 1 }
                }
                if config.sameResultRunsEnabled {
                    // 连续胜平负同理，是一个带内部容错的组合条件。
                    if !config.passesSameResultRuns(fullOutcomes) { failures += 1 }
                }
                return config.allConditionsToleranceRange.contains(failures)
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("全部条件总容错\(config.allConditionsToleranceRange)", selected)
            allConditionsToleranceStageBetCounts = [selected.count]
        }
        var consecutiveStageBetCounts: [Int] = []
        if config.consecutiveRunsEnabled && !config.allConditionsToleranceEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter(config.passesConsecutiveRuns)
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            let selectedRecords = selected.map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            exportRecords = compress(selectedRecords).records
            trace("连续彩果条件及内部容错", selected)
            consecutiveStageBetCounts = [selected.count]
        }
        var sameResultStageBetCounts: [Int] = []
        if config.sameResultRunsEnabled && !config.allConditionsToleranceEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter(config.passesSameResultRuns)
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            let selectedRecords = selected.map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            exportRecords = compress(selectedRecords).records
            trace("连续胜平负条件及内部容错", selected)
            sameResultStageBetCounts = [selected.count]
        }
        var comprehensiveAnalysisStageBetCounts: [Int] = []
        if let profile = comprehensiveAnalysisProfile {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter { fullOutcomes in
                let failures = comprehensiveAnalysisFailureCount(
                    fullOutcomes: fullOutcomes,
                    config: config,
                    profile: profile,
                    outcomeProbabilities: currentOutcomeProbabilities,
                    outcomeSPs: currentOutcomeSPs
                )
                return comprehensiveAnalysisToleranceRange.contains(failures)
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            let selectedRecords = selected.map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            exportRecords = compress(selectedRecords).records
            trace("历史综合分析条件及容错", selected)
            comprehensiveAnalysisStageBetCounts = [selected.count]
        }
        var protectedHistoryStageBetCounts: [Int] = []
        if let profile = protectedHistoryProfile {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter { fullOutcomes in
                let firstSix = Array(fullOutcomes.prefix(6))
                let failures = comprehensiveAnalysisFailureCount(
                    fullOutcomes: firstSix,
                    config: config,
                    profile: profile,
                    outcomeProbabilities: currentOutcomeProbabilities,
                    outcomeSPs: currentOutcomeSPs
                )
                let tolerance = effectiveProtectedHistoryToleranceRange(
                    base: protectedHistoryToleranceRange,
                    fullOutcomes: firstSix,
                    config: config
                )
                return tolerance.contains(failures)
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("历史保护压缩条件及容错", selected)
            protectedHistoryStageBetCounts = [selected.count]
        }
        var universal247StageBetCounts: [Int] = []
        if config.universal247ToleranceEnabled {
            let isVIP4 = VIP4Bayesian150Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            let isVIP3 = VIP3Joint150Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            let isVIP2 = VIP2Joint150Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            let isJoint150 = Joint150V8Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            let isHandicapOddsV9 = HandicapOddsV9Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            let isProductSumV10 = ProductSumV10Model.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            )
            // VIP2/V8是独立排名版本。V9/V10都必须在条件Tab已经通过的
            // 结果上叠加自己的赔率条件，不得重新从全量组合展开而绕过其他开关。
            let expanded = (isVIP4 || isVIP3 || isVIP2 || isJoint150)
                ? allRecords.flatMap { record in
                    cartesianOptions(record.outcomes.map { [$0] } + config.extraMatches.map(\.outcomes))
                }
                : exportRecords.flatMap { cartesianOptions($0.options) }
            let selected: [[Int]]
            if isVIP4 {
                selected = VIP4Bayesian150Model.selectTop(
                    expanded,
                    context: vip4Context
                )
            } else if isVIP3 {
                selected = VIP3Joint150Model.selectTop(
                    expanded,
                    firstFiveLogic: config.logic,
                    context: vip3Context
                )
            } else if isVIP2 {
                selected = VIP2Joint150Model.selectTop(
                    expanded,
                    logic: config.logic,
                    comparisonTableOdds: currentOutcomeSPs
                )
            } else if isProductSumV10 {
                let candidates = config.productSumV10Top150Enabled
                    ? Joint150V8Model.selectTop(
                        expanded,
                        logic: config.logic,
                        probabilities: currentOutcomeProbabilities
                    )
                    : expanded
                selected = candidates.filter {
                    guard ProductSumV10Model.passesProductAndSum(
                        outcomes: $0,
                        logic: config.logic
                    ) else { return false }
                    let mainOutcomes = Array($0.prefix(config.matchNumbers.count))
                    if config.customHandicapOddsProductFilterEnabled {
                        guard let odds = selectedValues(
                            currentOutcomeSPs,
                            outcomes: config.customHandicapOddsProductOutcomes(in: mainOutcomes)
                        ) else { return false }
                        let product = odds.reduce(1, *)
                        guard product >= Double(config.customHandicapOddsProductRange.lowerBound),
                              product <= Double(config.customHandicapOddsProductRange.upperBound) else { return false }
                    }
                    if config.customHandicapOddsSumFilterEnabled {
                        guard let odds = selectedValues(currentOutcomeSPs, outcomes: mainOutcomes) else { return false }
                        let sum = odds.reduce(0, +)
                        guard sum >= Double(config.customHandicapOddsSumRange.lowerBound),
                              sum <= Double(config.customHandicapOddsSumRange.upperBound) else { return false }
                    }
                    return true
                }
            } else if isHandicapOddsV9 {
                selected = expanded.filter {
                    HandicapOddsV9Model.passes(
                        outcomes: $0,
                        comparisonTableOdds: currentOutcomeSPs
                    )
                }
            } else if isJoint150 {
                selected = Joint150V8Model.selectTop(
                    expanded,
                    logic: config.logic,
                    probabilities: currentOutcomeProbabilities
                )
            } else if Universal405WholeIssueModel.isSelected(
                configurationValue: config.universal247ToleranceThreshold
            ) {
                selected = Universal405WholeIssueModel.selectTop(expanded, logic: config.logic)
            } else {
                selected = expanded.filter {
                    passesUniversal247Tolerance(
                        fullOutcomes: $0,
                        threshold: config.universal247ToleranceThreshold,
                        logic: config.logic,
                        probabilities: currentOutcomeProbabilities
                    )
                }
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = ((isVIP4 || isVIP3 || isVIP2 || isJoint150) ? allRecords : accepted).filter {
                mainOutcomes.contains($0.outcomes)
            }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("\(universalCompressionStageName(threshold: config.universal247ToleranceThreshold))", selected)
            universal247StageBetCounts = [selected.count]
        }
        var universal150StageBetCounts: [Int] = []
        if config.universal150CompressionEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter {
                passesUniversal150Compression(fullOutcomes: $0, config: config)
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("通用150注统计压缩", selected)
            universal150StageBetCounts = [selected.count]
        }
        var prizeStatisticalStageBetCounts: [Int] = []
        if config.prizeStatisticalConditionEnabled && !config.allConditionsToleranceEnabled {
            // VIP9只计算前5场；第6场保持310全包，不得因胜负切换被拆包。
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = expanded.filter {
                let main = Array($0.prefix(config.matchNumbers.count))
                return OutcomeCondition.winLossSwitches.value(in: config.metricOutcomes(in: main)) <= 2
            }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            let selectedRecords = selected.map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            exportRecords = compress(selectedRecords).records
            trace("奖金统计条件", selected)
            prizeStatisticalStageBetCounts = [selected.count]
        }
        var vip12ProbabilityStageBetCounts: [Int] = []
        if config.vip12ProbabilityReductionEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            // 正常使用六场赛前赔率拟合概率；数据缺失或不完整时，统一退回ABCD映射概率，
            // 确保开关打开后仍严格执行至少10%的减注，不会静默失效。
            let probabilityRows = finalScoring(
                config: config,
                probabilities: currentOutcomeProbabilities,
                marketShares: currentMarketBettingShares
            ).rows
            let selected = reduceVIP12ProbabilityBets(
                expanded,
                probabilities: probabilityRows,
                scoredMatchCount: config.matchNumbers.count
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(
                    outcomes: $0,
                    values: [],
                    sum: 0,
                    displacement: 0,
                    variance: 0,
                    transitionProbability: 0
                )
            }).records
            trace("VIP12六场联合概率最低10%减注", selected)
            vip12ProbabilityStageBetCounts = [selected.count]
        }
        var svip1CustomOddsGuardStageBetCounts: [Int] = []
        if config.svip1CustomOddsGuardEnabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = reduceSVIP1CustomOddsGuardBets(
                expanded,
                customOdds: currentOutcomeSPs
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(
                    outcomes: $0,
                    values: [],
                    sum: 0,
                    displacement: 0,
                    variance: 0,
                    transitionProbability: 0
                )
            }).records
            trace("SVIP1自定义赔率冷尾保护", selected)
            svip1CustomOddsGuardStageBetCounts = [selected.count]
        }
        // 禁止固定注数上限。参数仅为兼容旧调用方保留，不再对已通过条件的组合排名截取。
        let protectedHistoryCapStageBetCounts: [Int] = []
        let scoring = finalScoring(config: config, probabilities: currentOutcomeProbabilities, marketShares: currentMarketBettingShares)
        var finalStageBetCounts: [Int] = []
        if config.finalReduction != .off {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = reduceFinalBets(expanded, config: config, scores: scoring.rows)
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            let selectedRecords = selected.map { outcomes in
                SequenceRecord(outcomes: outcomes, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            exportRecords = compress(selectedRecords).records
            trace("\(config.finalReductionDescription)", selected)
            finalStageBetCounts = [selected.count]
        }
        var vip16Top200StageBetCounts: [Int] = []
        if config.vip16Top200Enabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = selectHighestProbabilityBets(
                expanded,
                probabilities: scoring.rows,
                scoredMatchCount: config.matchNumbers.count,
                maximumCount: 200
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("VIP16联合概率前200注排序", selected)
            vip16Top200StageBetCounts = [selected.count]
        }
        var vip18Top200StageBetCounts: [Int] = []
        if config.vip18Top200Enabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = selectVIP18Top200Bets(
                expanded,
                probabilities: currentOutcomeProbabilities,
                scoredMatchCount: config.matchNumbers.count
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("VIP18校准概率前200注排序", selected)
            vip18Top200StageBetCounts = [selected.count]
        }
        var vip19CustomOddsTop200StageBetCounts: [Int] = []
        if config.vip19CustomOddsTop200Enabled {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = selectVIP19CustomOddsTop200Bets(
                expanded,
                customOdds: currentOutcomeSPs,
                scoredMatchCount: config.matchNumbers.count
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = accepted.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            trace("VIP19自定义赔率前200注排序", selected)
            vip19CustomOddsTop200StageBetCounts = [selected.count]
        }
        // 仅没有任何六场级过滤时才把第六场回填为310全包。
        // 大压缩、通用150和六串胜负切换都必须保留已经筛出的精确第六场选项。
        let selectedBeforeFullPackage = exportRecords.flatMap { cartesianOptions($0.options) }
        let uniqueSelectedOutcomes = Array(Set(selectedBeforeFullPackage)).sorted { left, right in
            left.lexicographicallyPrecedes(right)
        }
        let uniqueMainOutcomes = Array(Set(selectedBeforeFullPackage.map {
            Array($0.prefix(config.matchNumbers.count))
        })).sorted { left, right in
            left.lexicographicallyPrecedes(right)
        }
        let preservesExactExtraOutcomes = config.svip11BreakpointOnlyEnabled
            || protectedHistoryProfile != nil
            || config.universal247ToleranceEnabled
            || config.universal150CompressionEnabled
            || config.prizeStatisticalConditionEnabled
            || config.vip12ProbabilityReductionEnabled
            || config.svip1CustomOddsGuardEnabled
            || config.vip16Top200Enabled
            || config.vip18Top200Enabled
            || config.vip19CustomOddsTop200Enabled
        var preFullPackageBetCount: Int
        if preservesExactExtraOutcomes {
            preFullPackageBetCount = uniqueSelectedOutcomes.count
            let exportSourceRecords = uniqueSelectedOutcomes.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            let exactExportRecords = compress(exportSourceRecords).records
            if config.vip12ProbabilityReductionEnabled
                && !config.svip1CustomOddsGuardEnabled
                && !config.vip16Top200Enabled
                && !config.vip18Top200Enabled
                && !config.vip19CustomOddsTop200Enabled {
                // VIP12第七条：先严格完成联合概率减注，再以
                // 20注以内的防守补注将TXT压向40行左右；仍超过45行
                // 时才将总补注硬上限提到28注。原始通过注一注不少。
                exportRecords = compactRowsAllowingAdditionalBets(
                    exactExportRecords,
                    sourceRecords: exportSourceRecords,
                    maximumAdditionalBets: 28,
                    preferredInitialBudget: 10,
                    preferredTargetBudget: 20,
                    targetMaximumRows: 45
                )
            } else {
                exportRecords = exactExportRecords
            }
        } else {
            preFullPackageBetCount = uniqueMainOutcomes.count
            // 回填固定场次后仍要对最终七场列表递归合并。此前这里直接生成单行，
            // 导致前面已完成的压缩在最终TXT中被拆回80多行。
            let expandedForExport = uniqueMainOutcomes.flatMap { mainOutcomes in
                cartesianOptions(mainOutcomes.map { [$0] } + config.extraMatches.map(\.outcomes))
            }
            let exportSourceRecords = expandedForExport.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }
            let exactExportRecords = compress(exportSourceRecords).records
            let usesVIP11Scopes = config.displacementMatchCount == 5
                && config.sumMatchCount == 6
                && config.calculationMatchCount == 5
                && !config.sumUsesOutcomeSP
            if usesVIP11Scopes && config.minimumDistinctDisplacementOrders > 0 {
                // SVIP4：约10注的受控补注专门换取总TXT更少的行数。
                // 补入的每注仍必须满足前5场M排列门槛和当前指定场次禁4；
                // 不按期号、场次号或历史赛果挑选例外。
                let allowedAdditionalOutcomes = Set(cartesianOptions(
                    Array(repeating: outcomeOrder, count: config.matchNumbers.count)
                        + config.extraMatches.map(\.outcomes)
                ).filter { outcomes in
                    let values = zip(config.logic, outcomes).map { $0.value(for: $1) }
                    return config.passesDisplacement(in: values)
                        && config.activeNoFourPositions.allSatisfy { values[$0 - 1] != 4 }
                        && config.frontThreeMaximumFourCount.map { maximum in
                            values.prefix(3).filter { $0 == 4 }.count <= maximum
                        } != false
                })
                exportRecords = compactRowsAllowingAdditionalBets(
                    exactExportRecords,
                    sourceRecords: exportSourceRecords,
                    maximumAdditionalBets: 12,
                    allowedAdditionalOutcomes: allowedAdditionalOutcomes,
                    preferredInitialBudget: 10,
                    preferredTargetBudget: 12,
                    targetMaximumRows: max(1, exactExportRecords.count - 10)
                )
            } else if usesVIP11Scopes {
                exportRecords = compactRowsAllowingAdditionalBets(
                    exactExportRecords,
                    sourceRecords: exportSourceRecords,
                    maximumAdditionalBets: 28
                )
            } else {
                exportRecords = exactExportRecords
            }
        }
        if captureQueryStages { trace("TXT最终回填及受控补注", exportRecords.flatMap { cartesianOptions($0.options) }) }
        var svip5TailStageBetCounts: [Int] = []
        if config.svip5TailRemovalCount > 0 {
            let expanded = exportRecords.flatMap { cartesianOptions($0.options) }
            let selected = reduceSVIP5CustomOddsTailBets(
                expanded, customOdds: currentOutcomeSPs,
                removalCount: config.svip5TailRemovalCount
            )
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            // After the final filter all exported bets are the exact selected set.
            preFullPackageBetCount = selected.count
            trace("SVIP5自定义赔率联合概率冷尾减\(config.svip5TailRemovalCount)注", selected)
            svip5TailStageBetCounts = [Set(expanded).count, selected.count]
        }
        var svip5FourCountStageBetCounts: [Int] = []
        if config.svip5FourCountFilterEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.svip5FourCountFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("SVIP5前五场判定值4个数（最多2个）", selected)
            svip5FourCountStageBetCounts = [expanded.count, selected.count]
        }
        var frontFiveActualMStageBetCounts: [Int] = []
        if config.frontFiveActualMEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveActualMFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)实际顺序M=\(config.frontFiveActualMRange.lowerBound)–\(config.frontFiveActualMRange.upperBound)", selected)
            frontFiveActualMStageBetCounts = [expanded.count, selected.count]
        }
        var frontFiveNoTripleDrawStageBetCounts: [Int] = []
        var frontFiveLossCountStageBetCounts: [Int] = []
        var frontFiveWinCountStageBetCounts: [Int] = []
        var combinedThreeStructureStageBetCounts: [Int] = []
        var sixLossCount14StageBetCounts: [Int] = []
        var frontFiveR39StageBetCounts: [Int] = []
        var frontFiveNoTripleLossStageBetCounts: [Int] = []
        var svip10StatisticalLineStageBetCounts: [Int] = []
        if config.frontFiveNoTripleDrawEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveNoTripleDrawFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)不出现连续\(config.topFiveRelaxed ? 4 : 3)场平局", selected)
            frontFiveNoTripleDrawStageBetCounts = [expanded.count, selected.count]
        }
        if config.frontFiveLossCountEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveLossCountFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)负个数范围", selected)
            frontFiveLossCountStageBetCounts = [expanded.count, selected.count]
        }
        if config.frontFiveWinCountEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveWinCountFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)胜个数范围", selected)
            frontFiveWinCountStageBetCounts = [expanded.count, selected.count]
        }
        if config.combinedThreeStructureEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.combinedThreeStructureFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("三条件组合过滤", selected)
            combinedThreeStructureStageBetCounts = [expanded.count, selected.count]
        }
        if config.sixLossCount14Enabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.sixLossCount14FailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("六场负\(config.widerFiveConditions ? "0–5" : "1–4")个", selected)
            sixLossCount14StageBetCounts = [expanded.count, selected.count]
        }
        if config.frontFiveR39Enabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveR39FailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)判定值R=\(config.sixMatchPackageScope ? "0–14" : (config.topFiveSecondRelaxed ? "0–12" : (config.topFiveRelaxed ? "1–12" : (config.widerFiveConditions ? "2–11" : (config.expandedStructureRanges ? "3–11" : "3–9")))))", selected)
            frontFiveR39StageBetCounts = [expanded.count, selected.count]
        }
        if config.frontFiveNoTripleLossEnabled {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { config.frontFiveNoTripleLossFailureReasons(for: $0).isEmpty }
            let mainOutcomes = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                               variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            trace("\(config.structuralScopeLabel)不出现连续3场负", selected)
            frontFiveNoTripleLossStageBetCounts = [expanded.count, selected.count]
        }
        if requestedConfig.svip10Frozen160Enabled
            && (requestedConfig.svip10AdditionalFilters.statisticalLineBudgetEnabled
                || requestedConfig.svip10AdditionalFilters.probabilityMass60Enabled) {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let usesLegacy50 = requestedConfig.svip10AdditionalFilters.statisticalLineBudgetEnabled
            let selection = usesLegacy50
                ? selectSVIP10StatisticalLineBudget(
                    expanded, config: requestedConfig,
                    probabilities: currentOutcomeProbabilities, customOdds: currentOutcomeSPs,
                    marketShares: currentMarketBettingShares, maximumRows: 50)
                : selectSVIP10ProbabilityMassLineBudget(
                    expanded, config: requestedConfig,
                    probabilities: currentOutcomeProbabilities, customOdds: currentOutcomeSPs,
                    marketShares: currentMarketBettingShares, maximumRows: 60)
            let mainOutcomes = Set(selection.bets.map {
                Array($0.prefix(requestedConfig.matchNumbers.count))
            })
            finalRecords = finalRecords.filter { mainOutcomes.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = selection.records
            preFullPackageBetCount = selection.bets.count
            trace(usesLegacy50
                ? "SVIP10市场概率70%＋历史结构30%统计优选（最多50行）"
                : "SVIP10整行联合概率质量优先（最多60行）", selection.bets)
            svip10StatisticalLineStageBetCounts = [expanded.count, selection.bets.count]
        }
        if requestedConfig.txtCompactEnabled {
            let original = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            preFullPackageBetCount = original.count
            exportRecords = compactTXTRecords(original, maximumAdditionalBets: requestedConfig.maximumTXTAdditionalBets, targetMaximumRows: 50)
            trace("TXT递归合并及受控补注", exportRecords.flatMap { cartesianOptions($0.options) })
        }
        // Independent condition groups remain strict even if the original
        // package uses tolerance, recovery or controlled TXT additions.
        if requestedConfig.hasIndependentConditionGroups {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let selected = expanded.filter { requestedConfig.independentOutcomeFailureReasons($0, customOdds: currentOutcomeSPs).isEmpty }
            if selected.count != expanded.count {
                let main = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
                finalRecords = finalRecords.filter { main.contains($0.outcomes) }
                compression = compress(finalRecords)
                exportRecords = compress(selected.map {
                    SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                                   variance: 0, transitionProbability: 0)
                }).records
                preFullPackageBetCount = selected.count
            }
            trace("独立条件组 · 已开分项共同通过", selected)
        }
        // 最后执行，保证后续压缩、补回、独立组处理不会重新突破105注。
        var fixedFrontDoubleStageBetCounts: [Int] = []
        // 双选属于投注布局硬约束；容错、补回和TXT合并均不能把被删方向加回来。
        if requestedConfig.svip10Frozen160Enabled && requestedConfig.conditionPackageEnabled
            && (requestedConfig.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled
                || requestedConfig.svip10AdditionalFilters.adDoublesWithinSixEnabled
                || requestedConfig.svip10AdditionalFilters.automaticDoublePairEnabled && requestedConfig.svip10AdditionalFilters.automaticDoubleCount == 1) {
            let choices = requestedConfig.automaticDoubleChoices(in: currentOutcomeSPs)
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            let dynamicAD = requestedConfig.svip10AdditionalFilters.adDoublesWithinSixEnabled
            let singleAny = !dynamicAD && !requestedConfig.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled && requestedConfig.svip10AdditionalFilters.automaticDoubleCount == 1
            let requiredCount = dynamicAD ? requestedConfig.svip10AdditionalFilters.adDoubleCountWithinSix : (singleAny ? 1 : 2)
            let validPair = choices.count == requiredCount && Set(choices.map(\.position)).count == requiredCount
                && (dynamicAD || singleAny || choices.map(\.position) == [1, 2])
            let selected = validPair ? expanded.filter { bet in
                bet.count >= 6 && choices.allSatisfy { $0.choice.retainedOutcomes.contains(bet[$0.position - 1]) }
            } : []
            let main = Set(selected.map { Array($0.prefix(requestedConfig.matchNumbers.count)) })
            finalRecords = finalRecords.filter { main.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            fixedFrontDoubleStageBetCounts = [selected.count]
            trace(dynamicAD ? "六场内\(requiredCount)处A/D双选最终校验（A31、D10，位置不固定）" : (singleAny ? "六场内唯一自动双选最终校验（31/30/10择优，类型不限）" : "前两场本次倾向双选最终校验（1保底）"), selected)
        }
        var maximum105InputBetCount: Int?
        var maximum105FailureMessage: String?
        var maximum105StageBetCounts: [Int] = []
        if requestedConfig.maximum105Active {
            let expanded = Array(Set(exportRecords.flatMap { cartesianOptions($0.options) }))
            maximum105InputBetCount = expanded.count
            let selected: [[Int]]
            if expanded.count <= 105 { selected = expanded }
            else if let ranked = selectSVIP10Fixed105Bets(expanded, customOdds: currentOutcomeSPs,
                calibrated: requestedConfig.svip10AdditionalFilters.calibratedDoubleSelectionEnabled) {
                selected = ranked
            } else {
                selected = []
                maximum105FailureMessage = "最多105注优选缺少完整六场自定义赔率，已停止生成，请补齐赔率后重试。"
            }
            let main = Set(selected.map { Array($0.prefix(config.matchNumbers.count)) })
            finalRecords = finalRecords.filter { main.contains($0.outcomes) }
            compression = compress(finalRecords)
            exportRecords = compress(selected.map {
                SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                    variance: 0, transitionProbability: 0)
            }).records
            preFullPackageBetCount = selected.count
            maximum105StageBetCounts = [selected.count]
            trace(maximum105FailureMessage ?? "最多105注优选（自定义赔率联合概率，不足不补齐）", selected)
        }
        let stageBetCounts: [Int]
        if config.allConditionsToleranceEnabled {
            var counts = [
                allOutcomes.count * factor,
                allOutcomes.count * factor - productRemovalLimit
            ]
            counts.append(contentsOf: allConditionsToleranceStageBetCounts)
            counts.append(contentsOf: comprehensiveAnalysisStageBetCounts)
            counts.append(contentsOf: protectedHistoryStageBetCounts)
            counts.append(contentsOf: universal247StageBetCounts)
            counts.append(contentsOf: universal150StageBetCounts)
            counts.append(contentsOf: vip12ProbabilityStageBetCounts)
            counts.append(contentsOf: svip1CustomOddsGuardStageBetCounts)
            counts.append(contentsOf: protectedHistoryCapStageBetCounts)
            counts.append(contentsOf: finalStageBetCounts)
            counts.append(contentsOf: vip16Top200StageBetCounts)
            counts.append(contentsOf: vip18Top200StageBetCounts)
            counts.append(contentsOf: vip19CustomOddsTop200StageBetCounts)
            counts.append(contentsOf: svip5TailStageBetCounts)
            counts.append(contentsOf: svip5FourCountStageBetCounts)
            counts.append(contentsOf: frontFiveActualMStageBetCounts)
            counts.append(contentsOf: frontFiveNoTripleDrawStageBetCounts)
            counts.append(contentsOf: frontFiveLossCountStageBetCounts)
            counts.append(contentsOf: frontFiveWinCountStageBetCounts)
            counts.append(contentsOf: combinedThreeStructureStageBetCounts)
            counts.append(contentsOf: sixLossCount14StageBetCounts)
            counts.append(contentsOf: frontFiveR39StageBetCounts)
            counts.append(contentsOf: frontFiveNoTripleLossStageBetCounts)
            counts.append(contentsOf: svip10StatisticalLineStageBetCounts)
            counts.append(contentsOf: fixedFrontDoubleStageBetCounts)
            counts.append(contentsOf: maximum105StageBetCounts)
            stageBetCounts = counts
        } else {
            var counts = [
                allOutcomes.count * factor,
                allOutcomes.count * factor - productRemovalLimit,
                betCount(afterSum), betCount(afterDisplacement), betCount(afterVariance),
                betCount(afterValueTwo), betCount(afterTransition), betCount(afterRoughness), betCount(afterBreakpoint)
            ]
            counts.append(contentsOf: noFourStageBetCounts)
            counts.append(contentsOf: outcomeStageBetCounts)
            counts.append(contentsOf: advancedStageBetCounts)
            counts.append(contentsOf: consecutiveStageBetCounts)
            counts.append(contentsOf: sameResultStageBetCounts)
            counts.append(contentsOf: comprehensiveAnalysisStageBetCounts)
            counts.append(contentsOf: protectedHistoryStageBetCounts)
            counts.append(contentsOf: universal247StageBetCounts)
            counts.append(contentsOf: universal150StageBetCounts)
            counts.append(contentsOf: prizeStatisticalStageBetCounts)
            counts.append(contentsOf: vip12ProbabilityStageBetCounts)
            counts.append(contentsOf: svip1CustomOddsGuardStageBetCounts)
            counts.append(contentsOf: protectedHistoryCapStageBetCounts)
            counts.append(contentsOf: finalStageBetCounts)
            counts.append(contentsOf: vip16Top200StageBetCounts)
            counts.append(contentsOf: vip18Top200StageBetCounts)
            counts.append(contentsOf: vip19CustomOddsTop200StageBetCounts)
            counts.append(contentsOf: svip5TailStageBetCounts)
            counts.append(contentsOf: svip5FourCountStageBetCounts)
            counts.append(contentsOf: frontFiveActualMStageBetCounts)
            counts.append(contentsOf: frontFiveNoTripleDrawStageBetCounts)
            counts.append(contentsOf: frontFiveLossCountStageBetCounts)
            counts.append(contentsOf: frontFiveWinCountStageBetCounts)
            counts.append(contentsOf: combinedThreeStructureStageBetCounts)
            counts.append(contentsOf: sixLossCount14StageBetCounts)
            counts.append(contentsOf: frontFiveR39StageBetCounts)
            counts.append(contentsOf: frontFiveNoTripleLossStageBetCounts)
            counts.append(contentsOf: svip10StatisticalLineStageBetCounts)
            counts.append(contentsOf: fixedFrontDoubleStageBetCounts)
            counts.append(contentsOf: maximum105StageBetCounts)
            stageBetCounts = counts
        }
        let tripleCount = compression.records.filter { $0.sourceRecords.count >= 3 }.count
        let pairCount = compression.records.filter { $0.sourceRecords.count == 2 }.count
        let singletonCount = compression.records.filter { $0.sourceRecords.count == 1 }.count
        let statistics = FilterStatistics(
            total: allOutcomes.count,
            afterProduct: allOutcomes.count - productRemovedOutcomes.count,
            afterSum: afterSum.count,
            afterDisplacement: afterDisplacement.count,
            afterVariance: afterVariance.count,
            afterValueTwo: afterValueTwo.count,
            afterTransition: afterTransition.count,
            afterRoughness: afterRoughness.count,
            afterBreakpoint: afterBreakpoint.count,
            afterProbabilitySelection: finalRecords.count,
            tripleGroups: tripleCount,
            pairGroups: pairCount,
            singletonGroups: singletonCount
        )
        return FilterResult(
            config: requestedConfig.six250RelationshipEnabled || requestedConfig.svip7RankOddsEnabled ? requestedConfig : config,
            records: finalRecords,
            compressedRecords: compression.records,
            exportCompressedRecords: exportRecords,
            preFullPackageBetCount: preFullPackageBetCount,
            stageBetCounts: stageBetCounts,
            statistics: statistics,
            exactCompression: compression.exact,
            removedRecords: probabilitySelection.removed,
            modelCoveragePercent: probabilitySelection.modelCoveragePercent,
            actualFilteredPercent: probabilitySelection.actualFilteredPercent,
            analysisBasis: previousContext?.displayText ?? "未使用上次结果",
            previousHitFlag: previousContext?.hitFlag ?? 0,
            usesCurrentMatchProbabilities: probabilitySelection.usesCurrentMatchProbabilities,
            usesRelationshipCondition: probabilitySelection.usesRelationshipCondition,
            comprehensiveAnalysisRuleCount: comprehensiveAnalysisProfile?.rules.count ?? 0,
            comprehensiveAnalysisToleranceRange: comprehensiveAnalysisProfile == nil ? nil : comprehensiveAnalysisToleranceRange,
            comprehensiveAnalysisRecommendedTitle: comprehensiveAnalysisProfile?.recommendedRule?.metric.title,
            protectedHistoryRuleCount: protectedHistoryProfile?.rules.count ?? 0,
            protectedHistoryRecordCount: protectedHistoryProfile?.historyRecordCount ?? 0,
            protectedHistoryBetCap: nil,
            finalReductionBasis: config.finalReduction == .product ? "按本次ABCD判定值乘积Q排序，优先删除较小Q；Q不是概率。" : scoring.basis,
            finalScoringRows: scoring.rows,
            queryStages: queryStages,
            resolvedOddsAdaptiveSRange: adaptiveSRange,
            queryCustomOdds: captureQueryStages || requestedConfig.highPass50DoubleActive ? currentOutcomeSPs : nil,
            maximum105InputBetCount: maximum105InputBetCount,
            maximum105FailureMessage: maximum105FailureMessage
        )
    }

    private static func applyingFinalResultFilters(
        to base: FilterResult, requestedConfig: FilterConfig,
        currentOutcomeSPs: [[Double]]?, captureQueryStages: Bool
    ) -> FilterResult {
        var result = base
        result.config.finalResultInverted = requestedConfig.finalResultInverted
        result.config.finalOutcomeExclusions = requestedConfig.finalOutcomeExclusions
        result.config.automaticFinalOutcomeExclusions = requestedConfig.automaticFinalOutcomeExclusions
        result.config.historicalOutcomeWindows = requestedConfig.historicalOutcomeWindows
        result.config.historicalOutcomeBeforeIssue = requestedConfig.historicalOutcomeBeforeIssue
        // A failed generation is not an empty, successfully filtered set.
        guard base.maximum105FailureMessage == nil else { return result }
        let original = base.uniqueExpandedBets
        let originalSix = Set(original.map { Array($0.prefix(6)) })
        var selected = original
        var notes: [String] = []
        var activeCuts = requestedConfig.finalOutcomeExclusions
        var recommendationMissing = false
        if requestedConfig.automaticFinalOutcomeExclusions && !activeCuts.isEmpty {
            if let recommendation = currentOutcomeSPs.flatMap({ FinalOutcomeCutRecommender.recommend(odds: $0) }) {
                let enabledSlots = Set(activeCuts.map(\.slot))
                activeCuts = recommendation.rules.filter { enabledSlots.contains($0.slot) }
                result.config.finalOutcomeExclusions = activeCuts
                result.config.automaticFinalOutcomeExclusions = false // Freeze actual choices in saved TXT.
                notes.append("自动推荐独立剔除（赛前赔率模型，非实际中奖率）：" + activeCuts.map { "第\($0.position)场去\($0.outcome)" }.joined(separator: "、"))
            } else {
                recommendationMissing = true
                result.maximum105FailureMessage = "自动推荐独立剔除缺少完整六场赛前自定义赔率，已停止生成；请补齐赔率或手动选择。"
            }
        }
        func traceFinal(_ title: String) {
            guard captureQueryStages else { return }
            result.queryStages.append(FilterQueryStage(name: title,
                survivors: Set(selected.map { Array($0.prefix(6)) })))
        }
        if requestedConfig.finalResultInverted {
            selected = cartesianOptions(Array(repeating: [3, 1, 0], count: 6)
                + requestedConfig.extraMatches.map(\.outcomes)).filter {
                    !originalSix.contains(Array($0.prefix(6)))
                }
            let title = "反选：729注减去原条件结果\(originalSix.count)注，剩余\(729 - originalSix.count)注（六场口径）"
            notes.append(title)
            traceFinal(title)
        }
        for rule in activeCuts.sorted(by: { $0.slot < $1.slot }) {
            let before = selected.count
            selected.removeAll { $0[rule.position - 1] == rule.outcome }
            let title = rule.summary + "（场号\(requestedConfig.matchNumbers[rule.position - 1])）：剔除\(before - selected.count)注，剩余\(selected.count)注"
            notes.append(title)
            traceFinal(title)
        }
        if let window = requestedConfig.historicalOutcomeWindows.max() {
            let history = HistoricalOutcomeWindows.priorRows(before: requestedConfig.historicalOutcomeBeforeIssue, limit: window)
            let excluded = Set(history.map(\.outcomes))
            let before = selected.count
            selected.removeAll { excluded.contains(Array($0.prefix(6))) }
            let title = "历史彩果去重：开关" + requestedConfig.historicalOutcomeWindows.sorted().map(String.init).joined(separator: "/")
                + "组，合并取最近\(window)组；已归档且早于\(requestedConfig.historicalOutcomeBeforeIssue)期\(history.count)组、\(excluded.count)种彩果，剔除\(before - selected.count)注，剩余\(selected.count)注"
            notes.append(title)
            traceFinal(title)
        }
        if recommendationMissing {
            selected = []
            notes.append(result.maximum105FailureMessage!)
            traceFinal(result.maximum105FailureMessage!)
        }
        let mainOutcomes = Set(selected.map { Array($0.prefix(6)) }).sorted { $0.lexicographicallyPrecedes($1) }
        let records = mainOutcomes.map { outcomes -> SequenceRecord in
            let values = zip(requestedConfig.logic, outcomes).map { $0.value(for: $1) }
            let metrics = requestedConfig.metricValues(in: values)
            let mean = Double(metrics.reduce(0, +)) / Double(metrics.count)
            let variance = metrics.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(metrics.count)
            let realOddsSum: Double? = requestedConfig.sumUsesOutcomeSP ? currentOutcomeSPs.flatMap { odds in
                guard odds.count >= 6, odds.prefix(6).allSatisfy({ $0.count == 3 }) else { return nil }
                return zip(odds.prefix(6), outcomes).reduce(0.0) { $0 + $1.0[$1.1 == 3 ? 0 : ($1.1 == 1 ? 1 : 2)] }
            } : nil
            return SequenceRecord(outcomes: outcomes, values: values,
                sum: requestedConfig.sumValues(in: values).reduce(0, +),
                displacement: requestedConfig.displacementValue(in: values), variance: variance,
                transitionProbability: markovProbability(metrics), realOddsSum: realOddsSum)
        }
        let compression = compress(records)
        result.originalConditionStageSummaries = base.filterStageSummaries.map { "原条件：" + $0 }
        result.finalResultFilterNotes = notes
        result.records = records
        result.compressedRecords = compression.records
        result.exportCompressedRecords = TXTBetEditor.exactRecords(selected)
        result.preFullPackageBetCount = selected.count
        result.exactCompression = true
        result.stageBetCounts.append(selected.count)
        let s = base.statistics
        result.statistics = FilterStatistics(total: s.total, afterProduct: s.afterProduct,
            afterSum: s.afterSum, afterDisplacement: s.afterDisplacement, afterVariance: s.afterVariance,
            afterValueTwo: s.afterValueTwo, afterTransition: s.afterTransition,
            afterRoughness: s.afterRoughness, afterBreakpoint: s.afterBreakpoint,
            afterProbabilitySelection: records.count,
            tripleGroups: compression.records.filter { $0.sourceRecords.count >= 3 }.count,
            pairGroups: compression.records.filter { $0.sourceRecords.count == 2 }.count,
            singletonGroups: compression.records.filter { $0.sourceRecords.count == 1 }.count)
        return result
    }

    static let svip7RuleTitles = [
        "六场自定义赔率乘积300–800（含边界）",
        "六场自定义赔率和值≤20",
        "赔率排名四条件容错1项：首选≥1，第三选≤3，第二选≤3，前后三场各第三选≤1"
    ]

    /// Only the first six custom-odds rows and candidate outcomes are read.
    /// An extra seventh fixture, ABCD and settled SP cannot affect selection.
    static func svip7FailureReasons(outcomes: [Int], customOdds: [[Double]]?, onlyRule: Int? = nil, disabled: Set<BasicCondition> = []) -> [String] {
        let rules: [BasicCondition] = [.oddsProduct, .oddsSum, .oddsRank]
        if let onlyRule, disabled.contains(rules[onlyRule]) { return [] }
        if rules.allSatisfy({ disabled.contains($0) }) { return [] }
        guard outcomes.count >= 6, outcomes.prefix(6).allSatisfy({ outcomeOrder.contains($0) }),
              let odds = customOdds, odds.count >= 6,
              odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else {
            return ["SVIP7需要完整六场彩果及项目自定义赔率，数据缺失时停止筛选"]
        }
        var selected: [Double] = []
        var ranks: [Int] = []
        for i in 0..<6 {
            let selectedIndex = outcomeOrder.firstIndex(of: outcomes[i])!
            let order = (0..<3).sorted {
                odds[i][$0] == odds[i][$1] ? $0 < $1 : odds[i][$0] < odds[i][$1]
            }
            selected.append(odds[i][selectedIndex])
            ranks.append(order.firstIndex(of: selectedIndex)!)
        }
        var reasons: [String] = []
        let product = selected.reduce(1, *)
        if !disabled.contains(.oddsProduct) && (onlyRule == nil || onlyRule == 0) && !(300...800).contains(product) {
            reasons.append("SVIP7自定义赔率乘积\(String(format: "%.4f", product))不在300–800")
        }
        let sum = selected.reduce(0, +)
        if !disabled.contains(.oddsSum) && (onlyRule == nil || onlyRule == 1) && sum > 20 {
            reasons.append("SVIP7自定义赔率和值\(String(format: "%.4f", sum))超过20")
        }
        if !disabled.contains(.oddsRank) && (onlyRule == nil || onlyRule == 2) {
            var rankFailures: [String] = []
            let hot = ranks.filter { $0 == 0 }.count
            let middle = ranks.filter { $0 == 1 }.count
            let cold = ranks.filter { $0 == 2 }.count
            let frontCold = ranks.prefix(3).filter { $0 == 2 }.count
            let backCold = ranks.suffix(3).filter { $0 == 2 }.count
            if hot < 1 { rankFailures.append("首选\(hot)场，少于1场") }
            if cold > 3 { rankFailures.append("第三选\(cold)场，超过3场") }
            if middle > 3 { rankFailures.append("第二选\(middle)场，超过3场") }
            if frontCold > 1 || backCold > 1 {
                rankFailures.append("前/后三场第三选\(frontCold)/\(backCold)个，存在超过1个")
            }
            if rankFailures.count > 1 {
                reasons.append("SVIP7排名条件未满足\(rankFailures.count)项，超过允许的1项：" + rankFailures.joined(separator: "；"))
            }
        }
        return reasons
    }

    static func rangeFailureReason(_ name: String, actual: Int, range: ClosedRange<Int>, unit: String = "") -> String {
        let difference = actual < range.lowerBound
            ? "低于下限\(range.lowerBound - actual)\(unit)"
            : "超过上限\(actual - range.upperBound)\(unit)"
        return "\(name)：实际\(actual)\(unit)；条件\(range.lowerBound)–\(range.upperBound)\(unit)；\(difference)"
    }

    static func scoreRangeFailureReason(actual: Double, lower: Double, upper: Double) -> String {
        let below = actual < lower
        let delta = below ? lower - actual : actual - upper
        let difference = delta > 0 && delta < 0.000001 ? "不足0.000001" : String(format: "%.6f", delta)
        return "自定义赔率综合分：实际\(String(format: "%.6f", actual))；条件\(lower)–\(upper)；\(below ? "低于下限" : "超过上限")\(difference)"
    }

    /// Frozen six-match numeric rule. Custom odds must come from the project's conversion table.
    static func six250FailureReasons(outcomes: [Int], config: FilterConfig, customOdds: [[Double]]?, onlyRule: Int? = nil, collectMessages: Bool = true, onFailure: ((Int) -> Void)? = nil) -> [String] {
        guard outcomes.count >= 6, config.logic.count == 6 else { return ["需要完整六场"] }
        let values = zip(config.logic, outcomes.prefix(6)).map { $0.value(for: $1) }
        var reasons: [String] = []
        func check(_ index: Int, _ passed: Bool, _ reason: @autoclosure () -> String) {
            let rule: BasicCondition? = [0: .sum, 1: .displacement, 2: .roughness, 3: .valueThree, 4: .score, 6: .valueTwo][index]
            if let rule, !config.isEnabled(rule) { return }
            if (onlyRule == nil || onlyRule == index) && !passed {
                onFailure?(index)
                if collectMessages { reasons.append(reason()) }
            }
        }
        let sum = values.reduce(0, +)
        let m = (0..<5).reduce(0) { $0 + abs(values[$1 + 1] - values[$1]) }
        let r = (0..<4).reduce(0) { $0 + abs(values[$1 + 2] - 2 * values[$1 + 1] + values[$1]) }
        check(0, config.six250SumRange.contains(sum), rangeFailureReason("六场S", actual: sum, range: config.six250SumRange))
        check(1, config.six250MRange.contains(m), rangeFailureReason("六场实际M", actual: m, range: config.six250MRange))
        check(2, config.six250RRange.contains(r), rangeFailureReason("六场R", actual: r, range: config.six250RRange))
        let threeCount = values.filter { $0 == 3 }.count
        check(3, threeCount <= config.valueThreeMaximum, rangeFailureReason("六场判定值3个数", actual: threeCount, range: 0...config.valueThreeMaximum, unit: "个"))
        if config.svip10Frozen160Enabled {
            let twoCount = values.filter { $0 == 2 }.count
            check(6, twoCount <= config.valueTwoMaximum, rangeFailureReason("六场判定值2个数", actual: twoCount, range: 0...config.valueTwoMaximum, unit: "个"))
        }
        if config.isEnabled(.score) && (onlyRule == nil || onlyRule == 4) {
            if let score = six250Score(outcomes: outcomes, customOdds: customOdds) {
                check(4, score >= config.six250ScoreLower && score <= config.six250ScoreUpper,
                      scoreRangeFailureReason(actual: score, lower: config.six250ScoreLower, upper: config.six250ScoreUpper))
            } else {
                check(4, false, "自定义赔率综合分：实际值无法计算（六场自定义赔率缺失或无效）；条件\(config.six250ScoreLower)–\(config.six250ScoreUpper)；差值无法计算")
            }
        }
        if onlyRule == nil || onlyRule == 5 {
            for position in config.noFourPositions {
                guard (1...6).contains(position) else {
                    check(5, false, "指定场次不是4：位置\(position)无效，允许第1–6场")
                    continue
                }
                if values[position - 1] == 4 {
                    check(5, false, "第\(position)场（场次\(config.matchNumbers[position - 1])）判定值：实际4；条件不等于4（允许2、3）；实际值属于禁选值4")
                }
            }
        }
        return reasons
    }

    /// Shared with the original score interval and the optional 180-bet ranking.
    static func six250Score(outcomes: [Int], customOdds: [[Double]]?) -> Double? {
        guard outcomes.count >= 6, outcomes.prefix(6).allSatisfy({ outcomeOrder.contains($0) }),
              let odds = customOdds, odds.count >= 6,
              odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else { return nil }
        let bias = [-0.004305971544996337, 0.07891200820715462, 0.0]
        var selected: [Double] = []
        var negativeLogJoint = 0.0
        for i in 0..<6 {
            let index = outcomes[i] == 3 ? 0 : (outcomes[i] == 1 ? 1 : 2)
            let logits = (0..<3).map { -1.071417246298114 * log(odds[i][$0]) + bias[$0] }
            let maximum = logits.max()!
            let normalizer = logits.map { exp($0 - maximum) }.reduce(0, +)
            negativeLogJoint += maximum + log(normalizer) - logits[index]
            selected.append(odds[i][index])
        }
        let total = selected.reduce(0, +)
        let mean = total / 6
        let variance = selected.reduce(0) { $0 + pow($1 - mean, 2) } / 6
        let cv = sqrt(variance) / mean
        let wave = (0..<5).reduce(0.0) { $0 + abs(selected[$1 + 1] - selected[$1]) } / total
        let score = negativeLogJoint - 0.75 * cv + 0.5 * wave
        return score.isFinite ? score : nil
    }

    /// Selects a second double from the same six matches. The first odds-based
    /// double is excluded, then the remaining match with the largest top-two
    /// probability mass is chosen. Model/market probabilities take priority;
    /// complete custom odds are a deterministic fallback.
    static func svip10SecondDoubleSelection(
        config: FilterConfig,
        currentOutcomeProbabilities: [[Double]]?,
        customOdds: [[Double]]?
    ) -> (position: Int, removedOutcome: Int, doubleProbability: Double, usesModelProbability: Bool)? {
        guard config.svip10AdditionalFilters.secondDoubleActive,
              let primaryPosition = config.highestDoubleProbabilityNoFourSelection(in: customOdds)?.position else {
            return nil
        }
        if config.svip10AdditionalFilters.usesAutomaticDoubleSelection {
            let choices = config.automaticDoubleChoices(in: customOdds)
            guard choices.count == 2 else { return nil }
            let second = choices[1]
            return (second.position, second.choice.removedOutcome, second.choice.coverage, false)
        }
        let rowsAndSource: ([[Double]], Bool)? = {
            if config.svip10AdditionalFilters.calibratedDoubleSelectionEnabled {
                guard let rows = config.doubleSelectionProbabilities(in: customOdds) else { return nil }
                return (rows, false)
            }
            if let probabilities = currentOutcomeProbabilities,
               probabilities.count >= 6,
               probabilities.prefix(6).allSatisfy({ row in
                   row.count == 3 && row.allSatisfy { $0.isFinite && $0 >= 0 } && row.reduce(0, +) > 0
               }) {
                return (probabilities.prefix(6).map { row in
                    let total = row.reduce(0, +)
                    return row.map { $0 / total }
                }, true)
            }
            guard let odds = customOdds, odds.count >= 6,
                  odds.prefix(6).allSatisfy({ row in
                      row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
                  }) else { return nil }
            return (odds.prefix(6).map { row in
                let inverse = row.map { 1 / $0 }
                let total = inverse.reduce(0, +)
                return inverse.map { $0 / total }
            }, false)
        }()
        guard let (rows, usesModelProbability) = rowsAndSource else { return nil }

        var best: (position: Int, removedOutcome: Int, doubleProbability: Double)?
        for index in 0..<6 where index + 1 != primaryPosition {
            let removedIndex = (0..<3).min { left, right in
                abs(rows[index][left] - rows[index][right]) > 1e-15
                    ? rows[index][left] < rows[index][right]
                    : left < right
            }!
            let doubleProbability = 1 - rows[index][removedIndex]
            if best == nil
                || doubleProbability > best!.doubleProbability + 1e-15
                || (abs(doubleProbability - best!.doubleProbability) <= 1e-15 && index + 1 < best!.position) {
                best = (index + 1, outcomeOrder[removedIndex], doubleProbability)
            }
        }
        guard let best else { return nil }
        return (best.position, best.removedOutcome, best.doubleProbability, usesModelProbability)
    }

    static func svip10AdditionalFailureReasons(outcomes: [Int], config: FilterConfig, customOdds: [[Double]]?, onlyRule: Int? = nil, collectMessages: Bool = true, onFailure: ((Int) -> Void)? = nil) -> [String] {
        guard config.svip10Frozen160Enabled, config.conditionPackageEnabled else { return [] }
        guard outcomes.count >= 6 else { return ["新增条件需要完整六场"] }
        let additions = config.svip10AdditionalFilters
        var reasons: [String] = []
        func fail(_ index: Int, _ message: @autoclosure () -> String) {
            onFailure?(index)
            if collectMessages { reasons.append(message()) }
        }
        if additions.coldCountEnabled && (onlyRule == nil || onlyRule == 0) {
            if let odds = customOdds, odds.count >= 6,
               odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) {
                let coldCount = (0..<6).filter { i in
                    let ordered = (0..<3).sorted { odds[i][$0] == odds[i][$1] ? $0 < $1 : odds[i][$0] < odds[i][$1] }
                    return outcomes[i] == outcomeOrder[ordered[2]]
                }.count
                if !additions.coldCountRange.contains(coldCount) {
                    fail(0, rangeFailureReason("六场自定义赔率第三选个数", actual: coldCount, range: additions.coldCountRange, unit: "个"))
                }
            } else {
                fail(0, "六场自定义赔率第三选个数：实际值无法计算（缺少完整自定义赔率）；条件\(additions.coldCountRange.lowerBound)–\(additions.coldCountRange.upperBound)个；差值无法计算")
            }
        }
        if additions.drawCountEnabled && (onlyRule == nil || onlyRule == 1) {
            let count = outcomes.prefix(6).filter { $0 == 1 }.count
            if !additions.drawCountRange.contains(count) {
                fail(1, rangeFailureReason("六场平局个数", actual: count, range: additions.drawCountRange, unit: "个"))
            }
        }
        if additions.winLossSwitchEnabled && (onlyRule == nil || onlyRule == 2) {
            let count = OutcomeCondition.winLossSwitches.value(in: Array(outcomes.prefix(5)))
            if !(0...2).contains(count) {
                fail(2, rangeFailureReason("前5场胜负直接切换次数", actual: count, range: 0...2, unit: "次"))
            }
        }
        if additions.highestDoubleProbabilityNoFourEnabled && (onlyRule == nil || onlyRule == 3) {
            if let selection = config.highestDoubleProbabilityNoFourSelection(in: customOdds),
               config.logic.indices.contains(selection.position - 1) {
                let value = config.logic[selection.position - 1].value(for: outcomes[selection.position - 1])
                if value == 4 {
                    fail(3, "双选概率最高的第\(selection.position)场（场次\(config.matchNumbers[selection.position - 1])，双选概率\(String(format: "%.2f", selection.probability * 100))%）判定值实际为4；条件要求不是4")
                }
            } else {
                fail(3, "双选概率最高场次不是4：缺少完整六场自定义赔率")
            }
        }
        if additions.fiveMatchMEnabled && (onlyRule == nil || onlyRule == 4) {
            if outcomes.count >= 5, config.logic.count >= 5 {
                let values = (0..<5).map { index in
                    config.logic[index].value(for: outcomes[index])
                }
                let m = zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
                if !additions.fiveMatchMRange.contains(m) {
                    fail(4, rangeFailureReason("前5场实际顺序M", actual: m, range: additions.fiveMatchMRange))
                }
            } else {
                fail(4, "前5场实际M：缺少完整前5场彩果或ABCD")
            }
        }
        if additions.frontFiveSameOutcomeRunMaximum2Enabled && (onlyRule == nil || onlyRule == 5) {
            if outcomes.count >= 5 {
                var longest = 1
                var current = 1
                for index in 1..<5 {
                    current = outcomes[index] == outcomes[index - 1] ? current + 1 : 1
                    longest = max(longest, current)
                }
                if longest > 2 {
                    fail(5, "前5场同彩果最长实际连续\(longest)场；条件要求最多2场")
                }
            } else {
                fail(5, "前5场同彩果连续：缺少完整前5场彩果")
            }
        }
        if additions.frontFiveReturnMaximum2Enabled && (onlyRule == nil || onlyRule == 6) {
            if outcomes.count >= 5 {
                let count = (2..<5).filter { index in
                    outcomes[index] == outcomes[index - 2] && outcomes[index] != outcomes[index - 1]
                }.count
                if count > 2 {
                    fail(6, "前5场隔场回返实际\(count)次；条件要求0–2次")
                }
            } else {
                fail(6, "前5场隔场回返：缺少完整前5场彩果")
            }
        }
        if additions.frontFiveNoConsecutiveDrawEnabled && (onlyRule == nil || onlyRule == 7) {
            if outcomes.count >= 5 {
                var longestDrawRun = 0
                var currentDrawRun = 0
                for outcome in outcomes.prefix(5) {
                    currentDrawRun = outcome == 1 ? currentDrawRun + 1 : 0
                    longestDrawRun = max(longestDrawRun, currentDrawRun)
                }
                if longestDrawRun > 1 {
                    fail(7, "前5场平局最长实际连续\(longestDrawRun)场；条件要求不出现连续平局")
                }
            } else {
                fail(7, "前5场连续平局：缺少完整前5场彩果")
            }
        }
        if additions.frontFiveValueThreeMaximum2Enabled && (onlyRule == nil || onlyRule == 8) {
            if outcomes.count >= 5, config.logic.count >= 5 {
                let count = (0..<5).filter { index in
                    config.logic[index].value(for: outcomes[index]) == 3
                }.count
                if count > 2 {
                    fail(8, "前5场判定值3实际\(count)个；条件要求最多2个")
                }
            } else {
                fail(8, "前5场判定值3个数：缺少完整前5场彩果或ABCD")
            }
        }
        if additions.sixMatchFavoriteCount2To4Enabled && (onlyRule == nil || onlyRule == 9) {
            if let odds = customOdds, odds.count >= 6,
               odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) {
                let count = (0..<6).filter { index in
                    let ordered = (0..<3).sorted {
                        odds[index][$0] == odds[index][$1] ? $0 < $1 : odds[index][$0] < odds[index][$1]
                    }
                    return outcomes[index] == outcomeOrder[ordered[0]]
                }.count
                if !(2...4).contains(count) {
                    fail(9, rangeFailureReason("六场自定义赔率第一选个数", actual: count, range: 2...4, unit: "个"))
                }
            } else {
                fail(9, "六场自定义赔率第一选个数：实际值无法计算（缺少完整自定义赔率）；条件要求2–4个")
            }
        }
        if additions.sixMatchFavoriteCount1To4Enabled && (onlyRule == nil || onlyRule == 15) {
            if let odds = customOdds, odds.count >= 6,
               odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) {
                let count = (0..<6).filter { index in
                    let ordered = (0..<3).sorted {
                        odds[index][$0] == odds[index][$1] ? $0 < $1 : odds[index][$0] < odds[index][$1]
                    }
                    return outcomes[index] == outcomeOrder[ordered[0]]
                }.count
                if !(1...4).contains(count) {
                    fail(15, rangeFailureReason("六场自定义赔率第一选个数", actual: count, range: 1...4, unit: "个"))
                }
            } else {
                fail(15, "六场自定义赔率第一选个数：实际值无法计算（缺少完整自定义赔率）；条件要求1–4个")
            }
        }
        if additions.sixMatchMinimumOddsProductEnabled && (onlyRule == nil || onlyRule == 10) {
            if let odds = customOdds, odds.count >= 6,
               odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) {
                let selected = (0..<6).map { index -> Double in
                    let outcomeIndex = outcomes[index] == 3 ? 0 : (outcomes[index] == 1 ? 1 : 2)
                    return odds[index][outcomeIndex]
                }
                let product = selected.reduce(1, *)
                if product + 1e-12 < additions.sixMatchMinimumOddsProduct {
                    fail(10, "前六场自定义赔率乘积：实际\(String(format: "%.2f", product))；条件至少\(String(format: "%.0f", additions.sixMatchMinimumOddsProduct))；低于下限\(String(format: "%.2f", additions.sixMatchMinimumOddsProduct - product))")
                }
            } else {
                fail(10, "前六场自定义赔率乘积：实际值无法计算（缺少完整自定义赔率）；条件至少\(String(format: "%.0f", additions.sixMatchMinimumOddsProduct))")
            }
        }
        if additions.sixMatchBreakpoint2To4Enabled && (onlyRule == nil || onlyRule == 11) {
            if outcomes.count >= 6 {
                let firstSix = Array(outcomes.prefix(6))
                let count = zip(firstSix, firstSix.dropFirst()).filter { $0 != $1 }.count
                if !(2...4).contains(count) {
                    fail(11, rangeFailureReason("六场彩果断点B", actual: count, range: 2...4, unit: "个"))
                }
            } else {
                fail(11, "六场彩果断点B：缺少完整前六场彩果；条件要求2–4个")
            }
        }
        if additions.sixMatchBreakpoint3To5Enabled && (onlyRule == nil || onlyRule == 12) {
            if outcomes.count >= 6 {
                let firstSix = Array(outcomes.prefix(6))
                let count = zip(firstSix, firstSix.dropFirst()).filter { $0 != $1 }.count
                if !additions.sixMatchBreakpointRange.contains(count) {
                    fail(12, rangeFailureReason("六场彩果断点B", actual: count, range: additions.sixMatchBreakpointRange, unit: "个"))
                }
            } else {
                fail(12, "六场彩果断点B：缺少完整前六场彩果；条件要求\(additions.sixMatchBreakpointRange.lowerBound)–\(additions.sixMatchBreakpointRange.upperBound)个")
            }
        }
        if additions.firstDoubleActive && (onlyRule == nil || onlyRule == 13) {
            if let selection = config.highestDoubleProbabilityTopTwoSelection(in: customOdds) {
                let position = selection.position - 1
                if outcomes[position] == selection.removedOutcome {
                    let basis = additions.calibratedDoubleSelectionEnabled ? "校正双选概率" : "双选概率"
                    if additions.adDoublesWithinSixEnabled {
                        fail(13, "六场内A/D双选第\(selection.position)场（场次\(config.matchNumbers[position])）：A保留31、D保留10，命中未保留方向\(selection.removedOutcome)")
                    } else if additions.fixedFrontTwoDoublesEnabled {
                        fail(13, "第1场按本次倾向双选\(selection.removedOutcome == 0 ? "31" : "10")（1保底）：场次\(config.matchNumbers[position])命中未保留方向\(selection.removedOutcome)")
                    } else if additions.usesAutomaticDoubleSelection && !additions.doubleJudgmentFactors.isEmpty {
                        fail(13, "第一处多因素双选第\(selection.position)场（场次\(config.matchNumbers[position])）命中被删方向\(selection.removedOutcome)／判定值\(config.logic[position].value(for: selection.removedOutcome))；赔率基础覆盖\(String(format: "%.2f", selection.probability * 100))%")
                    } else {
                    fail(13, "最适合双选的第\(selection.position)场（场次\(config.matchNumbers[position])，\(basis)\(String(format: "%.2f", selection.probability * 100))%）命中第三选；条件只保留概率最高两项")
                    }
                }
            } else {
                fail(13, "最适合双选场次保留前两项：缺少完整六场自定义赔率")
            }
        }
        if additions.secondDoubleActive && (onlyRule == nil || onlyRule == 14) {
            if let position = config.resolvedSecondDoublePosition,
               let removedOutcome = config.resolvedSecondDoubleRemovedOutcome,
               let probability = config.resolvedSecondDoubleProbability,
               outcomes.indices.contains(position - 1),
               config.matchNumbers.indices.contains(position - 1),
               config.logic.indices.contains(position - 1) {
                if outcomes[position - 1] == removedOutcome {
                    let mappedValue = config.logic[position - 1].value(for: removedOutcome)
                    let basis = additions.usesAutomaticDoubleSelection && !additions.doubleJudgmentFactors.isEmpty ? "多因素选择；赔率基础" : additions.calibratedDoubleSelectionEnabled ? "校正自定义赔率概率" : (config.resolvedSecondDoubleUsesModelProbability ? "综合概率" : "赔率概率")
                    if additions.adDoublesWithinSixEnabled {
                        fail(14, "六场内A/D双选第\(position)场（场次\(config.matchNumbers[position - 1])）：A保留31、D保留10，命中未保留方向\(removedOutcome)")
                    } else if additions.fixedFrontTwoDoublesEnabled {
                        fail(14, "第2场独立按本次倾向双选\(removedOutcome == 0 ? "31" : "10")（1保底）：场次\(config.matchNumbers[position - 1])命中未保留方向\(removedOutcome)")
                    } else {
                        fail(14, "第二个双选的第\(position)场（场次\(config.matchNumbers[position - 1])，\(basis)覆盖\(String(format: "%.2f", probability * 100))%）命中被删方向\(removedOutcome)／判定值\(mappedValue)")
                    }
                }
            } else {
                fail(14, "第二个双选场次去掉最低概率项：缺少完整六场概率或自定义赔率")
            }
        }
        return reasons
    }

    /// D is the model deviation of the six mapped values, using normalized inverse custom odds.
    static func oddsAdaptiveSRange(logic: [LogicMapping], customOdds: [[Double]]?) -> ClosedRange<Int>? {
        guard logic.count == 6, let odds = customOdds, odds.count >= 6,
              odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else { return nil }
        var variance = 0.0
        for i in 0..<6 {
            let inverse = odds[i].map { 1 / $0 }
            let total = inverse.reduce(0, +)
            let p = inverse.map { $0 / total }
            let v = logic[i].values.map(Double.init)
            let mean = zip(p, v).reduce(0.0) { $0 + $1.0 * $1.1 }
            variance += zip(p, v).reduce(0.0) { $0 + $1.0 * pow($1.1 - mean, 2) }
        }
        let d = sqrt(variance)
        if d < 1.96346872 { return 14...17 }
        if d < 1.98208079 { return 15...18 }
        return 14...19
    }

    static var universal150CompressionThreshold: Double {
        Universal150CompressionModel.threshold
    }

    static var universal247ToleranceThreshold: Double {
        Universal247ToleranceModel.threshold
    }

    static var universal247ToleranceModelVersion: String {
        VIP4Bayesian150Model.version + "+" + VIP3Joint150Model.version + "+" + VIP2Joint150Model.version + "+" + Universal247ToleranceModel.version + "+" + Universal247GeneralV4Model.version
            + "+" + Universal405WholeIssueModel.version + "+" + Joint150V8Model.version
            + "+" + HandicapOddsV9Model.version + "+" + ProductSumV10Model.version
    }

    static var universal247GeneralV4ConfigurationMarker: Double {
        Universal247GeneralV4Model.configurationMarker
    }

    static var universal405WholeIssueConfigurationMarker: Double {
        Universal405WholeIssueModel.configurationMarker
    }

    static var joint150V8ConfigurationMarker: Double {
        Joint150V8Model.configurationMarker
    }

    static var vip2ConfigurationMarker: Double {
        VIP2Joint150Model.configurationMarker
    }

    static var vip3ConfigurationMarker: Double {
        VIP3Joint150Model.configurationMarker
    }

    static var vip4ConfigurationMarker: Double {
        VIP4Bayesian150Model.configurationMarker
    }

    static func vip4SelectTop(
        _ expanded: [[Int]],
        context: VIP4MatchContext?
    ) -> [[Int]] {
        VIP4Bayesian150Model.selectTop(expanded, context: context)
    }

    static func vip3SelectTop(
        _ expanded: [[Int]],
        logic: [LogicMapping],
        context: VIP3MatchContext?
    ) -> [[Int]] {
        VIP3Joint150Model.selectTop(
            expanded,
            firstFiveLogic: logic,
            context: context
        )
    }

    static func vip2SelectTop(
        _ expanded: [[Int]],
        logic: [LogicMapping],
        comparisonTableOdds: [[Double]]?
    ) -> [[Int]] {
        VIP2Joint150Model.selectTop(
            expanded,
            logic: logic,
            comparisonTableOdds: comparisonTableOdds
        )
    }

    static var handicapOddsV9ConfigurationMarker: Double {
        HandicapOddsV9Model.configurationMarker
    }

    static var productSumV10ConfigurationMarker: Double {
        ProductSumV10Model.configurationMarker
    }

    static func usesUniversal247GeneralV4Model(threshold: Double?) -> Bool {
        Universal247GeneralV4Model.isSelected(configurationValue: threshold)
    }

    static func usesUniversal405WholeIssueModel(threshold: Double?) -> Bool {
        Universal405WholeIssueModel.isSelected(configurationValue: threshold)
    }

    static func usesJoint150V8Model(threshold: Double?) -> Bool {
        Joint150V8Model.isSelected(configurationValue: threshold)
    }

    static func usesVIP2Model(threshold: Double?) -> Bool {
        VIP2Joint150Model.isSelected(configurationValue: threshold)
    }

    static func usesVIP3Model(threshold: Double?) -> Bool {
        VIP3Joint150Model.isSelected(configurationValue: threshold)
    }

    static func usesVIP4Model(threshold: Double?) -> Bool {
        VIP4Bayesian150Model.isSelected(configurationValue: threshold)
    }

    static func usesHandicapOddsV9Model(threshold: Double?) -> Bool {
        HandicapOddsV9Model.isSelected(configurationValue: threshold)
    }

    static func usesProductSumV10Model(threshold: Double?) -> Bool {
        ProductSumV10Model.isSelected(configurationValue: threshold)
    }

    static func universalCompressionStageName(threshold: Double?) -> String {
        if usesVIP4Model(threshold: threshold) { return "VIP4贝叶斯联合150" }
        if usesVIP3Model(threshold: threshold) { return "VIP3六场赔率150" }
        if usesVIP2Model(threshold: threshold) { return "VIP2联合150" }
        if usesProductSumV10Model(threshold: threshold) { return "V10乘积Q＋和值S" }
        if usesHandicapOddsV9Model(threshold: threshold) { return "V9让球欧赔和值＋积值" }
        if usesJoint150V8Model(threshold: threshold) { return "V8联合150" }
        return usesUniversal405WholeIssueModel(threshold: threshold)
            ? "V5整期留出通用压缩" : "通用247综合容错"
    }

    static func universal247ToleranceScore(fullOutcomes: [Int]) -> Double? {
        Universal247ToleranceModel.score(fullOutcomes: fullOutcomes)
    }

    static func universal247ActiveScore(
        fullOutcomes: [Int],
        threshold: Double?,
        logic: [LogicMapping]? = nil
    ) -> Double? {
        if VIP4Bayesian150Model.isSelected(configurationValue: threshold)
            || VIP3Joint150Model.isSelected(configurationValue: threshold)
            || VIP2Joint150Model.isSelected(configurationValue: threshold)
            || ProductSumV10Model.isSelected(configurationValue: threshold)
            || HandicapOddsV9Model.isSelected(configurationValue: threshold)
            || Joint150V8Model.isSelected(configurationValue: threshold) { return nil }
        if Universal405WholeIssueModel.isSelected(configurationValue: threshold) {
            guard let logic else { return nil }
            return Universal405WholeIssueModel.score(fullOutcomes: fullOutcomes, logic: logic)
        }
        if Universal247GeneralV4Model.isSelected(configurationValue: threshold) {
            return Universal247GeneralV4Model.score(fullOutcomes: fullOutcomes)
        }
        return Universal247ToleranceModel.score(fullOutcomes: fullOutcomes)
    }

    static func passesUniversal247Tolerance(
        fullOutcomes: [Int],
        threshold: Double? = nil,
        logic: [LogicMapping]? = nil,
        probabilities: [[Double]]? = nil,
        comparisonTableOdds: [[Double]]? = nil,
        productSumV10Top150Enabled: Bool = false
    ) -> Bool {
        if ProductSumV10Model.isSelected(configurationValue: threshold) {
            guard let logic else { return false }
            return ProductSumV10Model.passes(
                fullOutcomes: fullOutcomes,
                logic: logic,
                top150Enabled: productSumV10Top150Enabled
            )
        }
        if HandicapOddsV9Model.isSelected(configurationValue: threshold) {
            return HandicapOddsV9Model.passes(
                outcomes: fullOutcomes,
                comparisonTableOdds: comparisonTableOdds
            )
        }
        if VIP2Joint150Model.isSelected(configurationValue: threshold) {
            guard let logic else { return false }
            return VIP2Joint150Model.passes(
                fullOutcomes: fullOutcomes,
                logic: logic,
                comparisonTableOdds: comparisonTableOdds
            )
        }
        if Joint150V8Model.isSelected(configurationValue: threshold) {
            guard let logic else { return false }
            return Joint150V8Model.passes(fullOutcomes: fullOutcomes, logic: logic)
        }
        if Universal405WholeIssueModel.isSelected(configurationValue: threshold) {
            guard let logic else { return false }
            return Universal405WholeIssueModel.passes(fullOutcomes: fullOutcomes, logic: logic)
        }
        if Universal247GeneralV4Model.isSelected(configurationValue: threshold) {
            guard let score = Universal247GeneralV4Model.score(fullOutcomes: fullOutcomes) else {
                return false
            }
            return score + 1e-12 >= Universal247GeneralV4Model.threshold
        }
        guard let score = universal247ToleranceScore(fullOutcomes: fullOutcomes) else {
            return false
        }
        return score + 1e-12 >= (threshold ?? universal247ToleranceThreshold)
    }

    static var universal150CompressionModelVersion: String {
        Universal150CompressionModel.version
    }

    static func universal150CompressionScore(
        fullOutcomes: [Int],
        config: FilterConfig
    ) -> Double? {
        Universal150CompressionModel.score(fullOutcomes: fullOutcomes, config: config)
    }

    static func passesUniversal150Compression(
        fullOutcomes: [Int],
        config: FilterConfig
    ) -> Bool {
        guard let score = universal150CompressionScore(
            fullOutcomes: fullOutcomes,
            config: config
        ) else { return false }
        return score + 1e-12 >= universal150CompressionThreshold
    }

    /// 所有组合统一使用条件 Tab 设置的大压缩容错，
    /// 不再根据判定值4/3的数量自动提升到0-5。
    static func effectiveProtectedHistoryToleranceRange(
        base: ClosedRange<Int>,
        fullOutcomes: [Int],
        config: FilterConfig
    ) -> ClosedRange<Int> {
        _ = fullOutcomes
        _ = config
        return base
    }

    static func comprehensiveAnalysisFailureCount(
        fullOutcomes: [Int],
        config: FilterConfig,
        profile: ComprehensiveAnalysisProfile,
        outcomeProbabilities: [[Double]]?,
        outcomeSPs: [[Double]]?
    ) -> Int {
        let mainOutcomes = Array(fullOutcomes.prefix(config.matchNumbers.count))
        guard mainOutcomes.count == config.logic.count else { return profile.rules.count }
        let values = zip(config.logic, mainOutcomes).map { $0.value(for: $1) }
        let total = values.reduce(0, +)
        let mean = Double(total) / Double(max(values.count, 1))
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(max(values.count, 1))
        let split = min(3, mainOutcomes.count)

        func selected(_ matrix: [[Double]]?, normalize: Bool = false) -> [Double]? {
            guard let matrix, matrix.count == mainOutcomes.count else { return nil }
            var result: [Double] = []
            for (row, outcome) in zip(matrix, mainOutcomes) {
                guard row.count == 3, row.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
                let index = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
                if normalize {
                    let rowTotal = row.reduce(0, +)
                    guard rowTotal > 0 else { return nil }
                    result.append(row[index] / rowTotal)
                } else {
                    result.append(row[index])
                }
            }
            return result
        }

        func empiricalTransitionPercent(_ input: [Int]) -> Double {
            guard input.count > 1 else { return 100 }
            var counts: [Int: [Int: Int]] = [:]
            var totals: [Int: Int] = [:]
            for (from, to) in zip(input, input.dropFirst()) {
                counts[from, default: [:]][to, default: 0] += 1
                totals[from, default: 0] += 1
            }
            return zip(input, input.dropFirst()).reduce(1.0) { partial, pair in
                partial * Double(counts[pair.0]?[pair.1] ?? 0) / Double(totals[pair.0] ?? 1)
            } * 100
        }

        var metrics: [ComprehensiveAnalysisMetric: Double] = [
            .productQ: Double(values.reduce(1, *)),
            .sum: Double(total),
            .displacement: Double(zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }),
            .variance: variance,
            .valueTwoCount: Double(values.filter { $0 == 2 }.count),
            .valueFourCount: Double(values.filter { $0 == 4 }.count),
            .transitionPercent: empiricalTransitionPercent(values),
            .roughness: Double(secondOrderRoughness(values)),
            .breakpoints: Double(outcomeBreakpoints(mainOutcomes)),
            .frontOutcomeSum: Double(mainOutcomes.prefix(split).reduce(0, +)),
            .backOutcomeSum: Double(mainOutcomes.dropFirst(split).reduce(0, +))
        ]
        if let summary = PrizeCalculator.outcomeSummary(for: fullOutcomes) {
            metrics[.winCount] = Double(summary.winCount)
            metrics[.drawCount] = Double(summary.drawCount)
            metrics[.lossCount] = Double(summary.lossCount)
            metrics[.diversity] = Double(summary.diversity)
            metrics[.outcomeSum] = Double(summary.outcomeSum)
            metrics[.returns] = Double(summary.returns)
            metrics[.winLossSwitches] = Double(summary.winLossSwitches)
            metrics[.nonLoss] = Double(summary.nonLoss)
            metrics[.nonDraw] = Double(summary.nonDraw)
            metrics[.nonWin] = Double(summary.nonWin)
            metrics[.winRun] = Double(summary.win)
            metrics[.drawRun] = Double(summary.draw)
            metrics[.lossRun] = Double(summary.loss)
        }
        if let sp = selected(outcomeSPs) {
            let product = sp.reduce(1, *)
            metrics[.spSum] = sp.reduce(0, +)
            metrics[.spProduct] = product
            metrics[.estimatedPrize] = product * 1.3
            metrics[.maximumSingleSP] = sp.max() ?? 0
            metrics[.highSPCount] = Double(sp.filter { $0 > 4 }.count)
            metrics[.frontSPProduct] = sp.prefix(split).reduce(1, *)
            metrics[.backSPProduct] = sp.dropFirst(split).reduce(1, *)
        }
        if let probabilities = selected(outcomeProbabilities, normalize: true) {
            metrics[.minimumProbabilityPercent] = (probabilities.min() ?? 0) * 100
            metrics[.jointProbabilityPercent] = probabilities.reduce(1, *) * 100
        }
        return profile.rules.reduce(0) { failures, rule in
            guard let value = metrics[rule.metric] else { return failures + 1 }
            return failures + (comprehensiveAnalysisRulePassesLatest(rule, value: value) ? 0 : 1)
        }
    }

    /// 大压缩档案是历史统计缓存，其内部范围不能放宽条件 Tab 的最新规则。
    /// 六串胜负直接切换统一为 0–2；即使旧档案上限是3，也必须收紧到2。
    static func comprehensiveAnalysisRulePassesLatest(
        _ rule: ComprehensiveAnalysisRule,
        value: Double
    ) -> Bool {
        let lower = rule.metric == .winLossSwitches ? 0 : rule.lowerBound
        let upper = rule.metric == .winLossSwitches ? 2 : rule.upperBound
        return value + 1e-12 >= lower && value <= upper + 1e-12
    }

    static func comprehensiveAnalysisRuleBoundsLatest(
        _ rule: ComprehensiveAnalysisRule
    ) -> (lower: Double, upper: Double) {
        guard rule.metric == .winLossSwitches else {
            return (rule.lowerBound, rule.upperBound)
        }
        return (0, 2)
    }

    static func finalScoring(config: FilterConfig, probabilities: [[Double]]?, marketShares: [[Double]]) -> (rows: [[Double]], basis: String) {
        func valid(_ row: [Double]) -> Bool {
            row.count == 3 && row.allSatisfy { $0.isFinite && $0 >= 0 }
                && row.reduce(0, +).isFinite && row.reduce(0, +) > 0
        }
        let hasModel = probabilities?.count == config.logic.count && probabilities?.allSatisfy(valid) == true
        var rows = hasModel ? probabilities! : config.logic.map { $0.values.map { 1.0 / Double($0) } }
        rows = rows.map { row in row.map { $0 / row.reduce(0, +) } }
        var marketCount = 0
        for index in rows.indices where config.marketWeightPercent > 0 {
            guard marketShares.indices.contains(index), valid(marketShares[index]) else { continue }
            let share = marketShares[index]
            let total = share.reduce(0, +)
            let weight = Double(config.marketWeightPercent) / 100
            rows[index] = (0..<3).map { rows[index][$0] * (1 - weight) + share[$0] / total * weight }
            marketCount += 1
        }
        let base = hasModel ? "本次赔率拟合的泊松胜平负模型" : "ABCD映射估计：判定值2/3/4取倒数后归一化（非实时概率）"
        let market = marketCount == 0 ? "投注占比未参与" : "\(marketCount)场有效投注占比，辅助权重\(config.marketWeightPercent)%"
        return (rows, "评分依据：\(base)；\(market)。各场评分连乘，固定场选项等权。历史战绩统计和真实投注金额未取得；综合评分是启发式排序，不是经验证的中奖概率。")
    }

    /// 按六场自定义赔率的联合概率确定性优选，计数使用去重后的展开注。
    /// 不读取场次号、期号或赛果；不足105注时保持原集合，由调用方处理不足。
    static func selectSVIP10Fixed105Bets(_ bets: [[Int]], customOdds: [[Double]]?, calibrated: Bool) -> [[Int]]? {
        guard let customOdds, customOdds.count >= 6 else { return nil }
        let rows = customOdds.prefix(6).compactMap { AutomaticDoubleSelector.probabilities(odds: $0, calibrated: calibrated) }
        guard rows.count == 6, bets.allSatisfy({ $0.count >= 6 && $0.allSatisfy { outcomeOrder.contains($0) } }) else { return nil }
        let ranked = Set(bets).map { outcomes -> (outcomes: [Int], score: Double) in
            let score = (0..<6).reduce(0.0) { total, index in
                let column = outcomes[index] == 3 ? 0 : outcomes[index] == 1 ? 1 : 2
                return total + log(rows[index][column])
            }
            return (outcomes, score)
        }.sorted {
            $0.score == $1.score ? $0.outcomes.lexicographicallyPrecedes($1.outcomes, by: >) : $0.score > $1.score
        }
        return ranked.prefix(105).map(\.outcomes)
    }

    /// SVIP10最终减注：先把已通过的投注精确递归合并，再按每个合并行内
    /// 所有组合的平均综合得分排序。综合得分由本期概率（已含可用投注占比）
    /// 与通用历史结构模型组成；保留整行，因此不会补入任何未通过的组合。
    static func selectSVIP10StatisticalLineBudget(
        _ bets: [[Int]],
        config: FilterConfig,
        probabilities: [[Double]]?,
        customOdds: [[Double]]? = nil,
        marketShares: [[Double]],
        maximumRows: Int = 50
    ) -> (bets: [[Int]], records: [CompressedRecord]) {
        let unique = Array(Set(bets)).sorted { $0.lexicographicallyPrecedes($1, by: >) }
        guard !unique.isEmpty, maximumRows > 0 else { return ([], []) }
        let source = unique.map {
            SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                           variance: 0, transitionProbability: 0)
        }
        let exactRows = compress(source).records
        guard exactRows.count > maximumRows else { return (unique, exactRows) }

        let impliedFromCustomOdds = customOdds.flatMap { odds -> [[Double]]? in
            guard odds.count >= config.matchNumbers.count else { return nil }
            let selected = Array(odds.prefix(config.matchNumbers.count))
            guard selected.allSatisfy({ row in
                row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
            }) else { return nil }
            return selected.map { row in
                let inverse = row.map { 1 / $0 }
                let total = inverse.reduce(0, +)
                return inverse.map { $0 / total }
            }
        }
        let probabilityRows = finalScoring(
            config: config,
            probabilities: probabilities ?? impliedFromCustomOdds,
            marketShares: marketShares
        ).rows
        let scoredCount = min(config.matchNumbers.count, probabilityRows.count)
        let rawScores = unique.map { outcomes -> (outcomes: [Int], market: Double, history: Double) in
            let market = (0..<min(scoredCount, outcomes.count)).reduce(0.0) { partial, position in
                let index = outcomes[position] == 3 ? 0 : (outcomes[position] == 1 ? 1 : 2)
                return partial + log(max(probabilityRows[position][index], 1e-15))
            }
            let history = Universal405WholeIssueModel.score(
                fullOutcomes: outcomes,
                logic: config.logic
            ) ?? 0
            return (outcomes, market, history)
        }
        func standardization(_ values: [Double]) -> (mean: Double, deviation: Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
            return (mean, sqrt(variance))
        }
        let marketValues = rawScores.map(\.market)
        let historyValues = rawScores.map(\.history)
        let marketStats = standardization(marketValues)
        let historyStats = standardization(historyValues)
        let combined = Dictionary(uniqueKeysWithValues: rawScores.map { item in
            let marketZ = marketStats.deviation > 1e-12
                ? (item.market - marketStats.mean) / marketStats.deviation : 0
            let historyZ = historyStats.deviation > 1e-12
                ? (item.history - historyStats.mean) / historyStats.deviation : 0
            let score = 0.70 * marketZ + 0.30 * historyZ
            return (item.outcomes, score)
        })
        let rankedRows = exactRows.sorted { left, right in
            let leftSources = left.sourceRecords.isEmpty
                ? cartesianOptions(left.options) : left.sourceRecords.map(\.outcomes)
            let rightSources = right.sourceRecords.isEmpty
                ? cartesianOptions(right.options) : right.sourceRecords.map(\.outcomes)
            let leftScore = leftSources.reduce(0.0) { $0 + combined[$1, default: 0] }
                / Double(max(1, leftSources.count))
            let rightScore = rightSources.reduce(0.0) { $0 + combined[$1, default: 0] }
                / Double(max(1, rightSources.count))
            if abs(leftScore - rightScore) > 1e-12 { return leftScore > rightScore }
            if leftSources.count != rightSources.count { return leftSources.count > rightSources.count }
            return left.compactNotation < right.compactNotation
        }
        let keptRows = Array(rankedRows.prefix(maximumRows))
        let keptBets = Array(Set(keptRows.flatMap { row in
            row.sourceRecords.isEmpty ? cartesianOptions(row.options) : row.sourceRecords.map(\.outcomes)
        })).sorted { $0.lexicographicallyPrecedes($1, by: >) }
        return (keptBets, keptRows)
    }

    /// 稳健版SVIP10减注：按每个精确合并行内所有投注的联合概率
    /// 之和排序，保留概率质量最高的完整行。这能避免平均分对大合并行
    /// 的天然惩罚，并且不拆行、不补注、不引入原条件外的投注。
    static func selectSVIP10ProbabilityMassLineBudget(
        _ bets: [[Int]],
        config: FilterConfig,
        probabilities: [[Double]]?,
        customOdds: [[Double]]? = nil,
        marketShares: [[Double]],
        maximumRows: Int = 60
    ) -> (bets: [[Int]], records: [CompressedRecord]) {
        let unique = Array(Set(bets)).sorted { $0.lexicographicallyPrecedes($1, by: >) }
        guard !unique.isEmpty, maximumRows > 0 else { return ([], []) }
        let source = unique.map {
            SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0,
                           variance: 0, transitionProbability: 0)
        }
        let exactRows = compress(source).records
        guard exactRows.count > maximumRows else { return (unique, exactRows) }

        let impliedFromCustomOdds = customOdds.flatMap { odds -> [[Double]]? in
            guard odds.count >= config.matchNumbers.count else { return nil }
            let selected = Array(odds.prefix(config.matchNumbers.count))
            guard selected.allSatisfy({ row in
                row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
            }) else { return nil }
            return selected.map { row in
                let inverse = row.map { 1 / $0 }
                let total = inverse.reduce(0, +)
                return inverse.map { $0 / total }
            }
        }
        let probabilityRows = finalScoring(
            config: config,
            probabilities: probabilities ?? impliedFromCustomOdds,
            marketShares: marketShares
        ).rows
        let scoredCount = min(config.matchNumbers.count, probabilityRows.count)
        let masses = Dictionary(uniqueKeysWithValues: unique.map { outcomes in
            let mass = (0..<min(scoredCount, outcomes.count)).reduce(1.0) { partial, position in
                let index = outcomes[position] == 3 ? 0 : (outcomes[position] == 1 ? 1 : 2)
                return partial * max(probabilityRows[position][index], 1e-15)
            }
            return (outcomes, mass)
        })
        let rankedRows = exactRows.sorted { left, right in
            let leftSources = left.sourceRecords.isEmpty
                ? cartesianOptions(left.options) : left.sourceRecords.map(\.outcomes)
            let rightSources = right.sourceRecords.isEmpty
                ? cartesianOptions(right.options) : right.sourceRecords.map(\.outcomes)
            let leftMass = leftSources.reduce(0.0) { $0 + masses[$1, default: 0] }
            let rightMass = rightSources.reduce(0.0) { $0 + masses[$1, default: 0] }
            if abs(leftMass - rightMass) > 1e-15 { return leftMass > rightMass }
            if leftSources.count != rightSources.count { return leftSources.count > rightSources.count }
            return left.compactNotation < right.compactNotation
        }
        let keptRows = Array(rankedRows.prefix(maximumRows))
        let keptBets = Array(Set(keptRows.flatMap { row in
            row.sourceRecords.isEmpty ? cartesianOptions(row.options) : row.sourceRecords.map(\.outcomes)
        })).sorted { $0.lexicographicallyPrecedes($1, by: >) }
        return (keptBets, keptRows)
    }

    /// 仅从已通过全部条件的实际单注中选择，合并顺序不影响结果。
    static func reduceVIP12ProbabilityBets(
        _ bets: [[Int]],
        probabilities: [[Double]]?,
        scoredMatchCount: Int
    ) -> [[Int]] {
        let uniqueBets = Array(Set(bets))
        let keepCount = max(1, Int((Double(uniqueBets.count) * 0.9).rounded(.down)))
        return selectHighestProbabilityBets(
            uniqueBets,
            probabilities: probabilities,
            scoredMatchCount: scoredMatchCount,
            maximumCount: keepCount
        )
    }

    /// 只使用项目换算后的六场自定义赔率。乘积越小，联合隐含概率越高。
    /// 83.5%保留线由2025年样本确定，并在2026年独立样本复核。
    /// Deterministic final subset. No supplement or full-package expansion follows it.
    static func reduceSVIP5CustomOddsTailBets(
        _ bets: [[Int]], customOdds: [[Double]]?, removalCount: Int
    ) -> [[Int]] {
        let unique = Array(Set(bets))
        guard !unique.isEmpty else { return [] }
        guard removalCount > 0 else { return unique.sorted { $0.lexicographicallyPrecedes($1, by: >) } }
        guard let customOdds, customOdds.count >= 6,
              customOdds.prefix(6).allSatisfy({ row in
                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
              }), unique.allSatisfy({ $0.count >= 6 && $0.prefix(6).allSatisfy { [3, 1, 0].contains($0) } }) else {
            return []
        }
        let keepCount = max(1, unique.count - removalCount)
        // Log products avoid overflow; per-match normalization is constant for every bet.
        return unique.map { outcomes -> (outcomes: [Int], score: Double) in
            let score = (0..<6).reduce(0.0) { sum, index in
                let column = outcomes[index] == 3 ? 0 : (outcomes[index] == 1 ? 1 : 2)
                return sum + log(customOdds[index][column])
            }
            return (outcomes, score)
        }.sorted { left, right in
            if left.score != right.score { return left.score < right.score }
            return left.outcomes.lexicographicallyPrecedes(right.outcomes, by: >)
        }.prefix(keepCount).map(\.outcomes)
    }

    static func reduceSVIP1CustomOddsGuardBets(
        _ bets: [[Int]],
        customOdds: [[Double]]?,
        scoredMatchCount: Int = 6
    ) -> [[Int]] {
        let uniqueBets = Array(Set(bets))
        guard !uniqueBets.isEmpty,
              scoredMatchCount == 6,
              let customOdds,
              customOdds.count >= scoredMatchCount,
              customOdds.prefix(scoredMatchCount).allSatisfy({ row in
                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
              }) else { return [] }
        let keepCount = max(1, uniqueBets.count * 835 / 1000)
        return uniqueBets.map { outcomes -> (outcomes: [Int], product: Double) in
            let product = zip(outcomes.prefix(scoredMatchCount), customOdds.prefix(scoredMatchCount))
                .reduce(1.0) { partial, pair in
                    let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                    return partial * pair.1[index]
                }
            return (outcomes, product)
        }
        .sorted { left, right in
            if abs(left.product - right.product) > 1e-12 { return left.product < right.product }
            return left.outcomes.lexicographicallyPrecedes(right.outcomes, by: >)
        }
        .prefix(keepCount)
        .map(\.outcomes)
    }

    /// 所有期号、场次和赛果使用相同的排序公式；赔率缺失时使用调用方统一提供的估计概率。
    static func selectHighestProbabilityBets(
        _ bets: [[Int]],
        probabilities: [[Double]]?,
        scoredMatchCount: Int,
        maximumCount: Int
    ) -> [[Int]] {
        let uniqueBets = Array(Set(bets))
        let limit = min(uniqueBets.count, max(0, maximumCount))
        guard limit > 0 else { return [] }
        guard scoredMatchCount > 0,
              let probabilities,
              probabilities.count >= scoredMatchCount else {
            return Array(uniqueBets.sorted { $0.lexicographicallyPrecedes($1, by: >) }.prefix(limit))
        }
        let normalizedRows = probabilities.prefix(scoredMatchCount).map { row -> [Double]? in
            guard row.count == 3,
                  row.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
            let total = row.reduce(0, +)
            guard total > 0 else { return nil }
            return row.map { $0 / total }
        }
        guard normalizedRows.allSatisfy({ $0 != nil }) else {
            return Array(uniqueBets.sorted { $0.lexicographicallyPrecedes($1, by: >) }.prefix(limit))
        }
        let rows = normalizedRows.compactMap { $0 }
        let ranked = uniqueBets.map { outcomes -> (outcomes: [Int], score: Double) in
            let score = zip(outcomes.prefix(scoredMatchCount), rows).reduce(1.0) { partial, pair in
                let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                return partial * pair.1[index]
            }
            return (outcomes, score)
        }.sorted { left, right in
            if abs(left.score - right.score) > 1e-15 { return left.score > right.score }
            return left.outcomes.lexicographicallyPrecedes(right.outcomes, by: >)
        }
        return ranked.prefix(limit).map { $0.outcomes }
    }

    /// Frozen on 2025 only. The same seven prior values and calibration apply to every issue.
    /// Never substitute ABCD estimates for missing model probabilities in this version.
    static func selectVIP18Top200Bets(
        _ bets: [[Int]],
        probabilities: [[Double]]?,
        scoredMatchCount: Int
    ) -> [[Int]] {
        guard scoredMatchCount == 6, let probabilities,
              probabilities.count >= 6,
              probabilities.prefix(6).allSatisfy({ row in
                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
              }) else { return [] }
        let alpha = 1.0894856919849591
        let biases = [-0.01154076573783609, 0.08139572102143769, 0.0]
        let prior = [-0.016107364886523624, -0.02359111501600322,
                     0.007008133413652477, 0.03131311952730298,
                     0.005963447592419027, -0.005364985009956289,
                     0.0007787643791086469]
        let rows = probabilities.prefix(6).map { row -> [Double] in
            let logits = (0..<3).map { alpha * log(max(row[$0], 1e-15)) + biases[$0] }
            let maximum = logits.max() ?? 0
            let expScores = logits.map { exp($0 - maximum) }
            let total = expScores.reduce(0, +)
            return expScores.map { $0 / total }
        }
        let leastLikely = rows.map { row in
            (0..<3).min { row[$0] < row[$1] } ?? 0
        }
        let ranked = Set(bets).map { outcomes -> (outcomes: [Int], score: Double) in
            var score = 0.0
            var upsetCount = 0
            for position in 0..<6 {
                let index = outcomes[position] == 3 ? 0 : (outcomes[position] == 1 ? 1 : 2)
                score += log(max(rows[position][index], 1e-15))
                if index == leastLikely[position] { upsetCount += 1 }
            }
            return (outcomes, score + prior[upsetCount])
        }.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.outcomes.lexicographicallyPrecedes(right.outcomes, by: >)
        }
        return ranked.prefix(200).map(\.outcomes)
    }

    /// VIP19第七条宪法：只接受项目让球对照表生成的自定义赔率。
    /// 先执行六场所选赔率乘积200–1500，再由同一赔率反推概率并排序。
    static func selectVIP19CustomOddsTop200Bets(
        _ bets: [[Int]],
        customOdds: [[Double]]?,
        scoredMatchCount: Int
    ) -> [[Int]] {
        guard scoredMatchCount == 6, let customOdds,
              customOdds.count >= 6,
              customOdds.prefix(6).allSatisfy({ row in
                  row.count == 3 && row.allSatisfy { $0.isFinite && $0 > 0 }
              }) else { return [] }

        let alpha = 1.0894856919849591
        let biases = [-0.01154076573783609, 0.08139572102143769, 0.0]
        let prior = [-0.013657114946, -0.025476244129, 0.010713741315,
                     0.028428283738, 0.002527787762, -0.004684613400,
                     0.002148159659]
        let oddsRows = Array(customOdds.prefix(6))
        let rows = oddsRows.map { odds -> [Double] in
            let inverse = odds.map { 1.0 / $0 }
            let inverseTotal = inverse.reduce(0, +)
            let normalized = inverse.map { $0 / inverseTotal }
            let logits = (0..<3).map { alpha * log(max(normalized[$0], 1e-15)) + biases[$0] }
            let maximum = logits.max() ?? 0
            let expScores = logits.map { exp($0 - maximum) }
            let total = expScores.reduce(0, +)
            return expScores.map { $0 / total }
        }
        let leastLikely = rows.map { row in
            (0..<3).min { row[$0] < row[$1] } ?? 0
        }
        let ranked = Set(bets).compactMap { outcomes -> (outcomes: [Int], score: Double)? in
            guard outcomes.count >= 6 else { return nil }
            var product = 1.0
            var score = 0.0
            var upsetCount = 0
            for position in 0..<6 {
                let index = outcomes[position] == 3 ? 0 : (outcomes[position] == 1 ? 1 : 2)
                product *= oddsRows[position][index]
                score += log(max(rows[position][index], 1e-15))
                if index == leastLikely[position] { upsetCount += 1 }
            }
            guard (200.0...1500.0).contains(product) else { return nil }
            return (outcomes, score + prior[upsetCount])
        }.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.outcomes.lexicographicallyPrecedes(right.outcomes, by: >)
        }
        return ranked.prefix(200).map(\.outcomes)
    }

    /// 仅从已通过全部条件的实际单注中选择，合并顺序不影响结果。
    static func reduceFinalBets(_ bets: [[Int]], config: FilterConfig, scores: [[Double]]? = nil) -> [[Int]] {
        guard config.finalReduction != .off, bets.count > 1 else { return bets }
        let ordered = bets.sorted { $0.lexicographicallyPrecedes($1, by: >) }
        let removeCount = (ordered.count / 100) * config.finalRemovalPercent
            + (ordered.count % 100) * config.finalRemovalPercent / 100
        if config.finalReduction == .product {
            var ranked: [(index: Int, outcomes: [Int], product: Int)] = []
            for (index, outcomes) in ordered.enumerated() {
                var product = 1
                for position in config.logic.indices { product *= config.logic[position].value(for: outcomes[position]) }
                ranked.append((index, outcomes, product))
            }
            ranked.sort { left, right in left.product == right.product ? left.index < right.index : left.product < right.product }
            return ranked.dropFirst(removeCount).map { $0.outcomes }
        }
        let rows = scores ?? finalScoring(config: config, probabilities: nil, marketShares: []).rows
        var generator = SeededBetRandom(seed: config.randomSeed)
        var ranked: [(index: Int, outcomes: [Int], rank: Double)] = []
        for (index, outcomes) in ordered.enumerated() {
            var score = 1.0
            for position in config.logic.indices {
                let outcome = outcomes[position]
                score *= rows[position][outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)]
            }
            let rank: Double
            if config.finalReduction == .random {
                let unit = (Double(generator.next() >> 11) + 0.5) / 9007199254740992.0
                rank = score > 0 ? -log(unit) / score : Double.infinity
            } else {
                rank = -score
            }
            ranked.append((index, outcomes, rank))
        }
        ranked.sort { left, right in left.rank == right.rank ? left.index < right.index : left.rank < right.rank }
        if config.finalReduction == .random {
            return ranked.prefix(ordered.count - removeCount).map { $0.outcomes }
        }
        // 综合评分模式按分数从高到低排列，删除头部指定比例。
        return ranked.dropFirst(removeCount).map { $0.outcomes }
    }

    private struct SeededBetRandom {
        var seed: UInt64
        mutating func next() -> UInt64 {
            seed &+= 0x9E3779B97F4A7C15
            var value = seed
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }

    static func baseFilterFailureReasons(
        for outcomes: [Int],
        config: FilterConfig,
        currentOutcomeSPs: [[Double]]? = nil,
        includeRanking: Bool = true
    ) -> [String] {
        guard config.conditionPackageEnabled else { return config.independentOutcomeFailureReasons(outcomes, customOdds: currentOutcomeSPs) }
        let additionalReasons: [String] = {
            guard config.isEnabled(.sum), let range = config.additionalSumRange, outcomes.count >= 6, config.logic.count == 6 else { return [] }
            let sum = zip(config.logic, outcomes).reduce(0) { $0 + $1.0.value(for: $1.1) }
            return range.contains(sum) ? [] : [rangeFailureReason("新增固定六场S", actual: sum, range: range)]
        }()
        let adaptiveReasons: [String] = {
            guard config.isEnabled(.sum) && config.oddsAdaptiveSRangeEnabled, outcomes.count >= 6, config.logic.count == 6 else { return [] }
            guard let range = oddsAdaptiveSRange(logic: config.logic, customOdds: currentOutcomeSPs) else { return ["赔率自适应S缺少完整六场自定义赔率"] }
            let sum = zip(config.logic, outcomes).reduce(0) { $0 + $1.0.value(for: $1.1) }
            return range.contains(sum) ? [] : [rangeFailureReason("赔率自适应六场S", actual: sum, range: range)]
        }()
        if config.svip7RankOddsEnabled {
            return svip7FailureReasons(outcomes: outcomes, customOdds: currentOutcomeSPs, disabled: config.disabledBasicConditions)
        }
        if config.six250RelationshipEnabled {
            let reasons = additionalReasons + adaptiveReasons
                + six250FailureReasons(outcomes: outcomes, config: config, customOdds: currentOutcomeSPs)
                + svip10AdditionalFailureReasons(outcomes: outcomes, config: config, customOdds: currentOutcomeSPs)
                + config.independentOutcomeFailureReasons(outcomes, customOdds: currentOutcomeSPs)
            return reasons
        }
        guard outcomes.count == config.logic.count,
              outcomes.allSatisfy({ outcomeOrder.contains($0) }) else {
            return ["实际彩果格式无效"]
        }

        let values = zip(config.logic, outcomes).map { $0.value(for: $1) }
        let metricValues = config.metricValues(in: values)
        let metricOutcomes = config.metricOutcomes(in: outcomes)
        let sum = config.sumValues(in: values).reduce(0, +)
        let metricSum = metricValues.reduce(0, +)
        let displacement = config.displacementValue(in: values)
        let mean = Double(metricSum) / Double(metricValues.count)
        let variance = metricValues.reduce(0.0) { partial, value in
            let delta = Double(value) - mean
            return partial + delta * delta
        } / Double(metricValues.count)
        let valueTwoCount = metricValues.filter { $0 == 2 }.count
        let transitionPercent = markovProbability(metricValues) * 100

        let realOddsSum: Double? = {
            guard config.sumUsesOutcomeSP,
                  let rows = currentOutcomeSPs,
                  rows.count >= metricOutcomes.count else { return nil }
            var selected: [Double] = []
            for (row, outcome) in zip(rows.prefix(metricOutcomes.count), metricOutcomes) {
                guard row.count == 3,
                      row.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
                selected.append(row[outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)])
            }
            return selected.reduce(0, +)
        }()

        var reasons: [String] = additionalReasons
        if config.isEnabled(.sum) && config.oddsAdaptiveSRangeEnabled {
            if let range = oddsAdaptiveSRange(logic: config.logic, customOdds: currentOutcomeSPs) {
                if !range.contains(sum) { reasons.append("六场S=\(sum)，不在赔率自适应范围\(range.lowerBound)–\(range.upperBound)") }
            } else { reasons.append("赔率自适应S缺少完整六场自定义赔率") }
        }
        for position in config.activeNoFourPositions where values[position - 1] == 4 {
            reasons.append("第\(position)个主场判定值为4")
        }
        if let maximum = config.frontThreeMaximumFourCount {
            let count = values.prefix(3).filter { $0 == 4 }.count
            if count > maximum {
                reasons.append("前三场判定值4出现\(count)次，超过\(maximum)次")
            }
        }
        if config.isEnabled(.sum) && config.sumUsesOutcomeSP, let realOddsSum {
            if realOddsSum < Double(config.sumRange.lowerBound)
                || realOddsSum > Double(config.sumRange.upperBound) {
                reasons.append("真实让球欧赔S=\(String(format: "%.3f", realOddsSum))，不在\(config.sumRange.lowerBound)–\(config.sumRange.upperBound)")
            }
        } else if config.isEnabled(.sum) && config.sumUsesOutcomeSP {
            reasons.append("真实让球欧赔S无法计算：前\(metricOutcomes.count)场对照赔率不完整")
        } else if config.isEnabled(.sum) && !config.sumRange.contains(sum) {
            reasons.append("S=\(sum)，不在\(config.sumRange.lowerBound)–\(config.sumRange.upperBound)")
        }
        if config.isEnabled(.displacement) && config.minimumDistinctDisplacementOrders > 0 {
            let validOrders = config.validDistinctDisplacementOrderCount(in: values)
            if validOrders < config.minimumDistinctDisplacementOrders {
                reasons.append("\(config.structuralScopeLabel)不同排列中M在\(config.displacementRange.lowerBound)–\(config.displacementRange.upperBound)的仅\(validOrders)种，少于\(config.minimumDistinctDisplacementOrders)种")
            }
        } else if config.isEnabled(.displacement) && !config.displacementRange.contains(displacement) {
            let scope = config.displacementMatchCount.map { "前\($0)场M" } ?? "M"
            reasons.append("\(scope)=\(displacement)，不在\(config.displacementRange.lowerBound)–\(config.displacementRange.upperBound)")
        }
        if config.lowestCustomOddsNoFourEnabled {
            if let position = config.lowestCustomOddsNoFourPosition(in: currentOutcomeSPs)
                ?? config.resolvedLowestCustomOddsNoFourPosition {
                if values[position - 1] == 4 {
                    reasons.append("4概率最低的第\(position)场判定值为4")
                }
            } else {
                reasons.append("4概率最低场次禁4：缺少\(config.structuralScopeLabel)完整自定义赔率")
            }
        }
        if config.isEnabled(.variance) && variance > config.varianceMaximum + 1e-12 {
            reasons.append("σ²=\(String(format: "%.3f", variance))，超过\(config.varianceMaximum)")
        }
        if config.isEnabled(.valueTwo) && valueTwoCount > config.valueTwoMaximum {
            reasons.append("判定值2出现\(valueTwoCount)次，超过\(config.valueTwoMaximum)次")
        }
        if config.isEnabled(.transition) && transitionPercent + 1e-12 < config.transitionMinimumPercent {
            reasons.append(
                "P_tr=\(String(format: "%.3f", transitionPercent))%，低于\(config.transitionMinimumPercent)%"
            )
        }
        let roughness = secondOrderRoughness(metricValues)
        if config.isEnabled(.roughness) && roughness > config.roughnessMaximum {
            reasons.append("二阶波动R=\(roughness)，超过\(config.roughnessMaximum)")
        }
        let breakpoints = outcomeBreakpoints(metricOutcomes)
        if config.isEnabled(.breakpoints) && !config.breakpointRange.contains(breakpoints) {
            reasons.append(
                "最终彩果断点B=\(breakpoints)，不在\(config.breakpointRange.lowerBound)–\(config.breakpointRange.upperBound)"
            )
        }
        let outcomeFailures = config.enabledOutcomeConditions.compactMap { condition -> String? in
            guard let range = config.outcomeConditions[condition] else { return nil }
            let value = condition.value(in: metricOutcomes)
            return range.contains(value)
                ? nil
                : "\(condition.title)=\(value)，不在\(range.lowerBound)–\(range.upperBound)"
        }
        if config.outcomeConditionToleranceEnabled {
            if !config.outcomeConditionToleranceRange.contains(outcomeFailures.count) {
                reasons.append("彩果条件有\(outcomeFailures.count)项不满足（容错\(config.outcomeConditionToleranceRange.lowerBound)-\(config.outcomeConditionToleranceRange.upperBound)项）：\(outcomeFailures.joined(separator: "、"))")
            }
        } else {
            reasons.append(contentsOf: outcomeFailures)
        }
        reasons.append(contentsOf: config.highPass50DoubleFailureReasons(outcomes, customOdds: currentOutcomeSPs))
        return reasons
    }

    /// 复现“乘积Q最低删除”的注级判定。
    ///
    /// Q删除数会把固定全包场也算为独立注。因此当删除数落在某个5场主彩果的
    /// 展开边界内时，必须结合后续固定场的实际彩果才能确定这一注是否被删。
    static func productQFilterAssessment(
        for fullOutcomes: [Int],
        config: FilterConfig
    ) -> ProductQFilterAssessment {
        let mainCount = config.matchNumbers.count
        let factor = config.extraExpansionFactor
        let candidateCount = Int(pow(3.0, Double(mainCount)))
        guard fullOutcomes.count >= mainCount,
              config.logic.count >= mainCount else {
            return ProductQFilterAssessment(
                passes: nil,
                product: nil,
                mainOutcomeRank: nil,
                mainOutcomeCount: candidateCount,
                removedExpandedBetCount: 0,
                expansionFactor: factor
            )
        }

        let mainOutcomes = Array(fullOutcomes.prefix(mainCount))
        guard mainOutcomes.allSatisfy({ outcomeOrder.contains($0) }) else {
            return ProductQFilterAssessment(
                passes: nil,
                product: nil,
                mainOutcomeRank: nil,
                mainOutcomeCount: candidateCount,
                removedExpandedBetCount: 0,
                expansionFactor: factor
            )
        }

        var ranked: [(index: Int, outcomes: [Int], product: Int)] = []
        ranked.reserveCapacity(candidateCount)
        // 不在 SwiftUI 主线统计路径中使用 zip(...).map。iOS 18 真机
        // 曾在这里进入 Swift 泛型元数据递归，最终撞到主线栈保护页。
        // 用固定 3 进制索引生成同样的 3/1/0 顺序，完全避开该运行时路径。
        for index in 0..<candidateCount {
            var encoded = index
            var candidate = Array(repeating: 0, count: mainCount)
            var product = 1
            if mainCount > 0 {
                for position in stride(from: mainCount - 1, through: 0, by: -1) {
                    let outcome = outcomeOrder[encoded % outcomeOrder.count]
                    candidate[position] = outcome
                    encoded /= outcomeOrder.count
                }
                for position in 0..<mainCount {
                    product *= config.logic[position].value(for: candidate[position])
                }
            }
            ranked.append((index, candidate, product))
        }
        ranked.sort { left, right in
            left.product == right.product ? left.index < right.index : left.product < right.product
        }
        guard let rankedIndex = ranked.firstIndex(where: { $0.outcomes == mainOutcomes }) else {
            return ProductQFilterAssessment(
                passes: nil,
                product: nil,
                mainOutcomeRank: nil,
                mainOutcomeCount: ranked.count,
                removedExpandedBetCount: 0,
                expansionFactor: factor
            )
        }

        let removalLimit = min(config.productRemovalCount, ranked.count * factor)
        let removedForThisMainOutcome = min(
            factor,
            max(0, removalLimit - rankedIndex * factor)
        )
        let product = ranked[rankedIndex].product
        let common = ProductQFilterAssessment(
            passes: removedForThisMainOutcome == 0 ? true : (removedForThisMainOutcome == factor ? false : nil),
            product: product,
            mainOutcomeRank: rankedIndex + 1,
            mainOutcomeCount: ranked.count,
            removedExpandedBetCount: removedForThisMainOutcome,
            expansionFactor: factor
        )
        guard removedForThisMainOutcome > 0,
              removedForThisMainOutcome < factor else { return common }

        let extraCount = config.extraMatches.count
        guard fullOutcomes.count >= mainCount + extraCount else { return common }
        let actualExtras = Array(fullOutcomes.dropFirst(mainCount).prefix(extraCount))
        let expandedExtras = config.extraMatches.reduce([[Int]]([[]])) { prefixes, match in
            prefixes.flatMap { prefix in match.outcomes.map { prefix + [$0] } }
        }
        guard let extraIndex = expandedExtras.firstIndex(of: actualExtras) else { return common }
        return ProductQFilterAssessment(
            passes: extraIndex >= removedForThisMainOutcome,
            product: product,
            mainOutcomeRank: rankedIndex + 1,
            mainOutcomeCount: ranked.count,
            removedExpandedBetCount: removedForThisMainOutcome,
            expansionFactor: factor
        )
    }

    /// 解释一个主场彩果在已保存策略中的淘汰阶段。
    static func missedOutcomeAnalysis(
        outcomes: [Int],
        config: FilterConfig,
        savedKeptOutcomes: Set<String>? = nil,
        currentOutcomeSPs: [[Double]]? = nil
    ) -> String {
        guard outcomes.count == config.logic.count,
              outcomes.allSatisfy({ outcomeOrder.contains($0) }) else {
            return "彩果格式无效，应为\(config.logic.count)位3/1/0。"
        }
        if config.hasFinalResultFilters {
            let compact = outcomes.map(String.init).joined()
            if savedKeptOutcomes?.contains(compact) == true {
                return "结论：该六场彩果位于当时反选及独立剔除后的最终TXT中；第7场另行核对。"
            }
            if let rule = config.finalOutcomeExclusions.first(where: { outcomes[$0.position - 1] == $0.outcome }) {
                return "结论：未通过\(rule.summary)。独立剔除在原条件和反选之后执行，不会被容错或补回恢复。"
            }
            return savedKeptOutcomes == nil
                ? "结论：缺少当时保存的最终TXT，无法判断反选及独立剔除后的命中；不能用原条件通过与否代替。"
                : "结论：该六场彩果未在当时反选及独立剔除后的最终TXT中找到；具体阶段以生成时保存的逐阶段记录为准。"
        }
        let values = zip(config.logic, outcomes).map { $0.value(for: $1) }
        let metricValues = config.metricValues(in: values)
        let sum = config.sumValues(in: values).reduce(0, +)
        let displacement = config.displacementValue(in: values)
        let metricSum = metricValues.reduce(0, +)
        let mean = Double(metricSum) / Double(metricValues.count)
        let variance = metricValues.reduce(0.0) { partial, value in
            let delta = Double(value) - mean
            return partial + delta * delta
        } / Double(metricValues.count)
        let product = metricValues.reduce(1, *)
        let scopeLabel = config.displacementMatchCount.map { "前\($0)场" } ?? ""
        let sumMetric: String = {
            guard config.sumUsesOutcomeSP else { return "S=\(sum)" }
            let scopedOutcomes = config.metricOutcomes(in: outcomes)
            guard let rows = currentOutcomeSPs, rows.count >= scopedOutcomes.count else {
                return "真实让球欧赔S=数据不完整"
            }
            let selected = zip(rows.prefix(scopedOutcomes.count), scopedOutcomes).compactMap { row, outcome -> Double? in
                guard row.count == 3, row.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
                return row[outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)]
            }
            guard selected.count == scopedOutcomes.count else { return "真实让球欧赔S=数据不完整" }
            return "真实让球欧赔S=\(String(format: "%.3f", selected.reduce(0, +)))"
        }()
        let metrics = "\(scopeLabel)判定值\(metricValues.map(String.init).joined())，Q=\(product)，\(sumMetric)，M=\(displacement)，σ²=\(String(format: "%.3f", variance))。"
        let compact = outcomes.map(String.init).joined()

        // 已保存的TXT结果是当时真正的输出。先以它为准，避免复盘时
        // 因SP/概率数据已不完整，将后续过滤误报成Q删除。
        if savedKeptOutcomes?.contains(compact) == true {
            return "结论：该5场彩果位于当时保留范围内；若最终仍未命中，请核对固定全包场和固定单选场的实际彩果。\n\(metrics)"
        }

        let failures = baseFilterFailureReasons(
            for: outcomes,
            config: config,
            currentOutcomeSPs: currentOutcomeSPs
        )
        if !failures.isEmpty {
            return "结论：基础条件未通过。\n未通过原因：\(failures.joined(separator: "；"))。\n\(metrics)"
        }

        if isFullyRemovedByProductQ(outcomes, config: config) {
            return "结论：基础指标均满足，但在乘积Q优先删除阶段被删除。\n\(metrics)"
        }

        guard savedKeptOutcomes != nil else {
            return "结论：基础条件和Q阶段均通过。缺少当时保存的最终结果，无法准确判定后续SP、概率、连续条件或最终压缩阶段。\n\(metrics)"
        }
        if config.finalReduction != .off {
            return "结论：基础条件和Q阶段均通过，但未出现在当时保留结果中；可能在后续条件或“\(config.finalReductionDescription)”阶段被删除。\n\(metrics)"
        }
        return "结论：基础条件和Q阶段均通过，但未在当时保存结果中找到；应由后续SP、概率或连续条件等阶段删除。\n\(metrics)"
    }

    /// 仅复现Q优先删除阶段，不依赖SP、概率或其他后续条件。
    private static func isFullyRemovedByProductQ(_ outcomes: [Int], config: FilterConfig) -> Bool {
        var ranked: [(index: Int, outcomes: [Int], product: Int)] = []
        for (index, candidate) in cartesianOutcomes(count: config.matchNumbers.count).enumerated() {
            let mappedValues = zip(config.logic, candidate).map { mapping, outcome in
                mapping.value(for: outcome)
            }
            ranked.append((index: index, outcomes: candidate, product: mappedValues.reduce(1, *)))
        }
        ranked.sort { left, right in
            left.product == right.product ? left.index < right.index : left.product < right.product
        }
        let removalLimit = min(config.productRemovalCount, ranked.count * config.extraExpansionFactor)
        let fullyRemovedMainCount = removalLimit / config.extraExpansionFactor
        return ranked.prefix(fullyRemovedMainCount).contains { $0.outcomes == outcomes }
    }

    private static func outcomeBreakpoints(_ outcomes: [Int]) -> Int {
        zip(outcomes, outcomes.dropFirst()).reduce(0) {
            $0 + ($1.0 == $1.1 ? 0 : 1)
        }
    }

    private static func secondOrderRoughness(_ values: [Int]) -> Int {
        guard values.count >= 3 else { return 0 }
        var total = 0
        for index in 0..<(values.count - 2) {
            let first = values[index]
            let middle = values[index + 1]
            let last = values[index + 2]
            total += abs(first - (2 * middle) + last)
        }
        return total
    }

    private struct ProbabilitySelectionOutput {
        let kept: [SequenceRecord]
        let removed: [SequenceRecord]
        let modelCoveragePercent: Double
        let actualFilteredPercent: Double
        let usesCurrentMatchProbabilities: Bool
        let usesRelationshipCondition: Bool
    }

    private struct RelationshipKey: Hashable {
        let positions: [Int]
        let outcomes: [Int]
    }

    /// 有可靠的当前赛事概率时，从联合概率最低的尾部开始删除，且被删除的
    /// 总概率质量不得超过5%。候选还必须同时满足连续二场/三场的弱链条件。
    /// 无可靠的当前赔率时改用马尔可夫概率兜底，仍然执行过滤。
    private static func probabilitySelecting(
        from records: [SequenceRecord],
        currentOutcomeProbabilities: [[Double]]?,
        applyPoissonRelationshipCondition: Bool
    ) -> ProbabilitySelectionOutput {
        guard records.count > 1 else {
            return ProbabilitySelectionOutput(
                kept: records,
                removed: [],
                modelCoveragePercent: 100,
                actualFilteredPercent: 0,
                usesCurrentMatchProbabilities: false,
                usesRelationshipCondition: false
            )
        }

        let validCurrentProbabilities = currentOutcomeProbabilities.flatMap { probabilities -> [[Double]]? in
            guard probabilities.count == records[0].outcomes.count,
                  probabilities.allSatisfy({ row in
                      row.count == 3
                          && row.allSatisfy { $0 >= 0 && $0.isFinite }
                          && row.reduce(0, +) > 0
                  }) else { return nil }
            return probabilities.map { row in
                let total = row.reduce(0, +)
                return row.map { $0 / total }
            }
        }
        let usesCurrentMatchProbabilities = validCurrentProbabilities != nil
        let usesRelationshipCondition = usesCurrentMatchProbabilities
            && applyPoissonRelationshipCondition
        let scores = records.map { record in
            if let probabilities = validCurrentProbabilities {
                return zip(record.outcomes, probabilities).reduce(1.0) { partial, pair in
                    let index = pair.0 == 3 ? 0 : (pair.0 == 1 ? 1 : 2)
                    return partial * pair.1[index]
                }
            }
            return record.transitionProbability
        }
        let pairProducts = records.map { record in
            validCurrentProbabilities.map {
                adjacentProbabilityProducts(for: record, probabilities: $0, windowSize: 2)
            } ?? []
        }
        let tripleProducts = records.map { record in
            validCurrentProbabilities.map {
                adjacentProbabilityProducts(for: record, probabilities: $0, windowSize: 3)
            } ?? []
        }
        let pairThresholds = relationshipLowTailThresholds(pairProducts, percentile: 0.20)
        let tripleThresholds = relationshipLowTailThresholds(tripleProducts, percentile: 0.20)
        let lowToHighIndices = records.indices.sorted { left, right in
            if abs(scores[left] - scores[right]) > 1e-15 {
                return scores[left] < scores[right]
            }
            return records[left].compactOutcomes > records[right].compactOutcomes
        }

        let totalScore = scores.reduce(0, +)
        let maximumRemovedScore = totalScore * 0.05
        var pairCounts = relationshipCounts(records: records, order: 2)
        var tripleCounts = relationshipCounts(records: records, order: 3)
        var removedIndices: Set<Int> = []
        var removedScore = 0.0
        for index in lowToHighIndices where removedIndices.count < records.count - 1 {
            let nextRemovedScore = removedScore + scores[index]
            guard nextRemovedScore <= maximumRemovedScore + 1e-12 else { break }
            let pairKeys = relationshipKeys(for: records[index], order: 2)
            let tripleKeys = relationshipKeys(for: records[index], order: 3)
            if usesRelationshipCondition {
                let weakPairCount = zip(pairProducts[index], pairThresholds)
                    .filter { $0.0 <= $0.1 + 1e-15 }.count
                let weakTripleCount = zip(tripleProducts[index], tripleThresholds)
                    .filter { $0.0 <= $0.1 + 1e-15 }.count
                let requiredWeakPairs = min(2, pairProducts[index].count)
                let requiredWeakTriples = tripleProducts[index].isEmpty ? 0 : 1
                guard weakPairCount >= requiredWeakPairs,
                      weakTripleCount >= requiredWeakTriples else {
                    continue
                }
            }
            guard pairKeys.allSatisfy({ pairCounts[$0, default: 0] > 1 }),
                  tripleKeys.allSatisfy({ tripleCounts[$0, default: 0] > 1 }) else {
                continue
            }
            removedIndices.insert(index)
            removedScore = nextRemovedScore
            for key in pairKeys { pairCounts[key, default: 0] -= 1 }
            for key in tripleKeys { tripleCounts[key, default: 0] -= 1 }
        }

        let kept = records.indices.compactMap { index in
            removedIndices.contains(index) ? nil : records[index]
        }
        let removed = lowToHighIndices.compactMap { index in
            removedIndices.contains(index) ? records[index] : nil
        }
        let keptScore = totalScore - removedScore
        let coveragePercent = totalScore > 0 ? keptScore / totalScore * 100 : 0
        let filteredPercent = Double(removed.count) / Double(records.count) * 100
        return ProbabilitySelectionOutput(
            kept: kept,
            removed: removed,
            modelCoveragePercent: coveragePercent,
            actualFilteredPercent: filteredPercent,
            usesCurrentMatchProbabilities: usesCurrentMatchProbabilities,
            usesRelationshipCondition: usesRelationshipCondition
        )
    }

    private static func adjacentProbabilityProducts(
        for record: SequenceRecord,
        probabilities: [[Double]],
        windowSize: Int
    ) -> [Double] {
        guard windowSize > 0, windowSize <= record.outcomes.count else { return [] }
        return (0...(record.outcomes.count - windowSize)).map { start in
            (start..<(start + windowSize)).reduce(1.0) { product, position in
                let outcome = record.outcomes[position]
                let probabilityIndex = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
                return product * probabilities[position][probabilityIndex]
            }
        }
    }

    private static func relationshipLowTailThresholds(
        _ products: [[Double]],
        percentile: Double
    ) -> [Double] {
        guard let width = products.first?.count, width > 0 else { return [] }
        return (0..<width).map { position in
            let sorted = products.map { $0[position] }.sorted()
            let rawIndex = Int((Double(sorted.count - 1) * percentile).rounded(.down))
            return sorted[min(max(rawIndex, 0), sorted.count - 1)]
        }
    }

    /// 保证任意两场及任意三场的每一种彩果投影，在保留集合中至少出现一次。
    private static func relationshipCounts(
        records: [SequenceRecord],
        order: Int
    ) -> [RelationshipKey: Int] {
        records.reduce(into: [:]) { counts, record in
            for key in relationshipKeys(for: record, order: order) {
                counts[key, default: 0] += 1
            }
        }
    }

    private static func relationshipKeys(
        for record: SequenceRecord,
        order: Int
    ) -> [RelationshipKey] {
        positionCombinations(count: record.outcomes.count, choose: order).map { positions in
            RelationshipKey(
                positions: positions,
                outcomes: positions.map { record.outcomes[$0] }
            )
        }
    }

    private static func positionCombinations(count: Int, choose: Int) -> [[Int]] {
        guard choose > 0, choose <= count else { return [] }
        func build(start: Int, remaining: Int, prefix: [Int]) -> [[Int]] {
            if remaining == 0 { return [prefix] }
            guard start <= count - remaining else { return [] }
            return (start...(count - remaining)).flatMap { index in
                build(start: index + 1, remaining: remaining - 1, prefix: prefix + [index])
            }
        }
        return build(start: 0, remaining: choose, prefix: [])
    }

    private static func markovProbability(_ values: [Int]) -> Double {
        let prior = [2: 0.45, 3: 0.30, 4: 0.25]
        guard let first = values.first else { return 0 }
        return zip(values, values.dropFirst()).reduce(prior[first, default: 0]) {
            $0 * transitionProbability(from: $1.0, to: $1.1)
        }
    }

    private static func transitionProbability(from: Int, to: Int) -> Double {
        let transitions: [Int: [Int: Double]] = [
            2: [2: 0.35, 3: 0.40, 4: 0.25],
            3: [2: 0.50, 3: 0.30, 4: 0.20],
            4: [2: 0.55, 3: 0.30, 4: 0.15]
        ]
        return transitions[from, default: [:]][to, default: 0]
    }

    private static func cartesianOutcomes(count: Int) -> [[Int]] {
        guard count > 0 else { return [[]] }
        var result: [[Int]] = [[]]
        for _ in 0..<count {
            result = result.flatMap { prefix in
                outcomeOrder.map { prefix + [$0] }
            }
        }
        return result
    }

    private struct CompressionCandidate {
        let indices: [Int]
        let differingPosition: Int?
        let mask: UInt64
        var size: Int { indices.count }
    }

    private struct CompressionOutput {
        let records: [CompressedRecord]
        let exact: Bool
    }

    private struct RectangleCandidate {
        let options: [[Int]]
        let indices: [Int]
    }

    private static func compress(_ records: [SequenceRecord]) -> CompressionOutput {
        guard !records.isEmpty else { return CompressionOutput(records: [], exact: true) }
        if records[0].outcomes.count == 7,
           Set(records.map(\.outcomes)).count == records.count {
            let recordByOutcome = Dictionary(uniqueKeysWithValues: records.map { ($0.outcomes, $0) })
            let optionRows = recursivelyMergedOptionRows(records.map(\.outcomes))
            let compressed = optionRows.map { options in
                CompressedRecord(
                    options: options,
                    sourceRecords: cartesianOptions(options).compactMap { recordByOutcome[$0] }
                )
            }
            let expanded = compressed.flatMap { cartesianOptions($0.options) }
            let exact = expanded.count == records.count
                && Set(expanded) == Set(records.map(\.outcomes))
            return CompressionOutput(records: compressed, exact: exact)
        }
        if records[0].outcomes.count == 5,
           let recursive = recursiveRectangleCompression(records) {
            return recursive
        }
        let candidates = makeCandidates(records)
        let selection: [Int]
        let exact: Bool
        if let validated = validatedDefaultSelection(records: records, candidates: candidates) {
            selection = validated
            exact = true
        } else if records.count <= 40 {
            let optimized = optimizedSelection(recordCount: records.count, candidates: candidates)
            selection = optimized.selection
            exact = optimized.provenMinimum
        } else {
            selection = greedySelection(recordCount: records.count, candidates: candidates)
            exact = false
        }

        let compressed = selection.map { candidateIndex -> CompressedRecord in
            let candidate = candidates[candidateIndex]
            let sources = candidate.indices.map { records[$0] }
            var options = sources[0].outcomes.map { [$0] }
            if let position = candidate.differingPosition {
                let present = Set(sources.map { $0.outcomes[position] })
                options[position] = outcomeOrder.filter(present.contains)
            }
            return CompressedRecord(options: options, sourceRecords: sources)
        }.sorted {
            if $0.sourceRecords.count != $1.sourceRecords.count {
                return $0.sourceRecords.count > $1.sourceRecords.count
            }
            return $0.compactNotation < $1.compactNotation
        }
        return CompressionOutput(records: compressed, exact: exact)
    }

    /// 完整7场中，反复合并“6个位置相同、仅1个位置不同”的行。
    /// 合并后的括号仍参与下一轮，因此可递归形成多个括号，同时保持精确覆盖。
    static func recursivelyMergedOptionRows(_ outcomes: [[Int]]) -> [[[Int]]] {
        guard !outcomes.isEmpty,
              outcomes.allSatisfy({ $0.count == 7 }),
              Set(outcomes).count == outcomes.count else {
            return outcomes.map { $0.map { [$0] } }
        }
        return recursivelyMergedRows(outcomes.map { $0.map { [$0] } })
    }

    private static func recursivelyMergedRows(_ initial: [[[Int]]]) -> [[[Int]]] {
        var rows = initial
        while true {
            rows.sort { optionRowKey($0) < optionRowKey($1) }
            var mergedGroup: (indices: [Int], row: [[Int]])?

            for position in 0..<7 {
                var groups: [String: [Int]] = [:]
                for index in rows.indices {
                    let key = rows[index].enumerated()
                        .filter { $0.offset != position }
                        .map { optionKey($0.element) }
                        .joined(separator: "|")
                    groups[key, default: []].append(index)
                }
                if let indices = groups.keys.sorted().compactMap({ key -> [Int]? in
                    guard let indices = groups[key], indices.count >= 2 else { return nil }
                    return indices
                }).first {
                    var merged = rows[indices[0]]
                    let present = Set(indices.flatMap { rows[$0][position] })
                    merged[position] = outcomeOrder.filter(present.contains)
                    mergedGroup = (indices, merged)
                    break
                }
            }

            guard let mergedGroup else { break }
            for index in mergedGroup.indices.sorted(by: >) {
                rows.remove(at: index)
            }
            rows.append(mergedGroup.row)
        }
        return rows.sorted { optionRowKey($0) < optionRowKey($1) }
    }

    static func compactTXTRecords(_ bets: [[Int]], maximumAdditionalBets: Int, targetMaximumRows: Int = 50) -> [CompressedRecord] {
        let original = Set(bets)
        guard !original.isEmpty else { return [] }
        let source = original.sorted { $0.lexicographicallyPrecedes($1) }.map {
            SequenceRecord(outcomes: $0, values: [], sum: 0, displacement: 0, variance: 0, transitionProbability: 0)
        }
        let exact = recursivelyMergedOptionRows(source.map(\.outcomes)).map {
            CompressedRecord(options: $0, sourceRecords: [])
        }
        guard exact.count > targetMaximumRows else { return exact }
        let compact = compactRowsAllowingAdditionalBets(exact, sourceRecords: source,
            maximumAdditionalBets: maximumAdditionalBets,
            preferredInitialBudget: min(10, maximumAdditionalBets),
            preferredTargetBudget: min(28, maximumAdditionalBets), targetMaximumRows: targetMaximumRows)
        let merged = recursivelyMergedRows(compact.map(\.options))
        let options = merged.count < compact.count ? merged : compact.map(\.options)
        let expanded = options.flatMap { cartesianOptions($0) }
        let unique = Set(expanded)
        guard original.isSubset(of: unique), unique.count == expanded.count,
              unique.count - original.count <= maximumAdditionalBets else { return exact }
        return options.map { CompressedRecord(options: $0, sourceRecords: []) }
    }

    /// 在VIP11最终TXT中用少量防守注换取更少的行数。始终保留全部原始通过注，
    /// 新增的唯一注数受硬上限约束，且每一步优先选择“减少行数最多、补注最少”的矩形。
    private static func compactRowsAllowingAdditionalBets(
        _ exactRecords: [CompressedRecord],
        sourceRecords: [SequenceRecord],
        maximumAdditionalBets: Int,
        allowedAdditionalOutcomes: Set<[Int]>? = nil,
        preferredInitialBudget: Int? = nil,
        preferredTargetBudget: Int? = nil,
        targetMaximumRows: Int? = nil
    ) -> [CompressedRecord] {
        // VIP11第五、六条：超过50行先允许补25注；压到45行上下后，
        // 还可再补最多3注。原始即在40～50行时只允许补3注。
        guard maximumAdditionalBets > 0, !sourceRecords.isEmpty else { return exactRecords }
        let primaryBudget: Int
        if let targetMaximumRows {
            guard exactRecords.count > targetMaximumRows else { return exactRecords }
            primaryBudget = maximumAdditionalBets
        } else if exactRecords.count > 50 {
            primaryBudget = min(25, maximumAdditionalBets)
        } else if (40...50).contains(exactRecords.count) {
            primaryBudget = min(3, maximumAdditionalBets)
        } else {
            return exactRecords
        }
        let initialBudgetLimit = targetMaximumRows == nil
            ? primaryBudget
            : maximumAdditionalBets
        let initialBudget = min(
            initialBudgetLimit,
            max(0, preferredInitialBudget ?? primaryBudget)
        )

        struct Candidate {
            let options: [[Int]]
            let originalIndices: [Int]
            let extraCodes: [Int]
        }

        let sourceByOutcome = Dictionary(uniqueKeysWithValues: sourceRecords.enumerated().map {
            ($0.element.outcomes, $0.offset)
        })
        func outcomeCode(_ outcomes: [Int]) -> Int {
            outcomes.reduce(0) { $0 * 4 + $1 }
        }

        // 固定单选场只有1种子集，其余每场最多7种；六场方案最多117,649个矩形。
        let optionChoices: [[[Int]]] = sourceRecords[0].outcomes.indices.map { position in
            let available = outcomeOrder.filter { value in
                sourceRecords.contains { $0.outcomes[position] == value }
            }
            return (1..<(1 << available.count)).map { mask in
                available.enumerated().compactMap { offset, value in
                    mask & (1 << offset) == 0 ? nil : value
                }
            }
        }
        var candidates: [Candidate] = []
        var chosen = optionChoices.map { $0[0] }
        func enumerateCandidates(_ position: Int) {
            if position == chosen.count {
                let expanded = cartesianOptions(chosen)
                var originals: [Int] = []
                var extras: [Int] = []
                for outcomes in expanded {
                    if let index = sourceByOutcome[outcomes] {
                        originals.append(index)
                    } else {
                        guard allowedAdditionalOutcomes?.contains(outcomes) != false else {
                            return
                        }
                        extras.append(outcomeCode(outcomes))
                    }
                }
                guard originals.count >= 2,
                      extras.count <= maximumAdditionalBets else { return }
                candidates.append(Candidate(
                    options: chosen,
                    originalIndices: originals,
                    extraCodes: extras
                ))
                return
            }
            for options in optionChoices[position] {
                chosen[position] = options
                enumerateCandidates(position + 1)
            }
        }
        enumerateCandidates(0)

        func greedyRows(extraPenalty: Double, budget: Int) -> (rows: [[[Int]]], added: Int) {
            var uncovered = Array(repeating: true, count: sourceRecords.count)
            var remaining = sourceRecords.count
            var usedExtras = Set<Int>()
            var selected: [[[Int]]] = []

            while remaining > 0 {
                var bestIndex: Int?
                var bestScore = -Double.greatestFiniteMagnitude
                var bestCovered = 0
                var bestNewExtras = Int.max
                for (index, candidate) in candidates.enumerated() {
                    // 最终TXT的各行必须互不重叠；否则界面虽然按
                    // unique计数，实际投注时同一注会在两行中重复出现。
                    guard candidate.originalIndices.allSatisfy({ uncovered[$0] }),
                          candidate.extraCodes.allSatisfy({ !usedExtras.contains($0) }) else {
                        continue
                    }
                    let newlyCovered = candidate.originalIndices.count
                    guard newlyCovered >= 2 else { continue }
                    let newExtras = candidate.extraCodes.count
                    guard usedExtras.count + newExtras <= budget else { continue }
                    let score = Double(newlyCovered) / (1 + extraPenalty * Double(newExtras))
                    if score > bestScore + 1e-12
                        || (abs(score - bestScore) <= 1e-12 && newlyCovered > bestCovered)
                        || (abs(score - bestScore) <= 1e-12
                            && newlyCovered == bestCovered && newExtras < bestNewExtras) {
                        bestIndex = index
                        bestScore = score
                        bestCovered = newlyCovered
                        bestNewExtras = newExtras
                    }
                }

                guard let bestIndex else { break }
                let best = candidates[bestIndex]
                selected.append(best.options)
                for index in best.originalIndices where uncovered[index] {
                    uncovered[index] = false
                    remaining -= 1
                }
                usedExtras.formUnion(best.extraCodes)
            }

            for index in uncovered.indices where uncovered[index] {
                selected.append(sourceRecords[index].outcomes.map { [$0] })
            }
            return (selected, usedExtras.count)
        }

        var best = (rows: exactRecords.map(\.options), added: 0)
        // 单一惩罚系数容易在某些ABCD分布上过早节省补注，
        // 造成“额度还有很多，行数却压不下去”。用一组固定系数
        // 做可复现的多起点贪心，最终优先取行数最少、其次补注最少。
        let penaltyCandidates = [0.0, 0.05, 0.20, 0.50, 1.0]
        for penalty in penaltyCandidates {
            let candidate = greedyRows(extraPenalty: penalty, budget: initialBudget)
            if candidate.rows.count < best.rows.count
                || (candidate.rows.count == best.rows.count && candidate.added < best.added) {
                best = candidate
            }
        }
        let targetBudget = min(
            maximumAdditionalBets,
            max(initialBudget, preferredTargetBudget ?? maximumAdditionalBets)
        )
        if let targetMaximumRows,
           best.rows.count > targetMaximumRows,
           targetBudget > initialBudget {
            for penalty in penaltyCandidates {
                let candidate = greedyRows(
                    extraPenalty: penalty,
                    budget: targetBudget
                )
                if candidate.rows.count < best.rows.count
                    || (candidate.rows.count == best.rows.count && candidate.added < best.added) {
                    best = candidate
                }
            }
        }
        if let targetMaximumRows,
           best.rows.count > targetMaximumRows,
           maximumAdditionalBets > targetBudget {
            for penalty in penaltyCandidates {
                let candidate = greedyRows(
                    extraPenalty: penalty,
                    budget: maximumAdditionalBets
                )
                if candidate.rows.count < best.rows.count
                    || (candidate.rows.count == best.rows.count && candidate.added < best.added) {
                    best = candidate
                }
            }
        }
        if targetMaximumRows == nil,
           exactRecords.count > 50,
           (40...50).contains(best.rows.count),
           maximumAdditionalBets >= 28 {
            for penalty in penaltyCandidates {
                let secondary = greedyRows(extraPenalty: penalty, budget: 28)
                if secondary.rows.count < best.rows.count
                    || (secondary.rows.count == best.rows.count && secondary.added < best.added) {
                    best = secondary
                }
            }
        }

        return best.rows.map { options in
            CompressedRecord(
                options: options,
                sourceRecords: cartesianOptions(options).compactMap {
                    sourceByOutcome[$0].map { sourceRecords[$0] }
                }
            )
        }.sorted { optionRowKey($0.options) < optionRowKey($1.options) }
    }

    private static func optionKey(_ option: [Int]) -> String {
        option.count == 1 ? String(option[0]) : "(\(option.map(String.init).joined()))"
    }

    private static func optionRowKey(_ options: [[Int]]) -> String {
        options.map(optionKey).joined()
    }

    /// 递归执行“其余4场相同再合并”。候选矩形必须完整包含于已通过的组合，
    /// 因此一行出现多个括号时也不会补入未通过过滤的注数。
    private static func recursiveRectangleCompression(
        _ records: [SequenceRecord]
    ) -> CompressionOutput? {
        let recordIndex = Dictionary(uniqueKeysWithValues: records.enumerated().map {
            ($0.element.outcomes, $0.offset)
        })
        guard recordIndex.count == records.count else { return nil }

        let optionSubsets = [
            [3], [1], [0], [3, 1], [3, 0], [1, 0], [3, 1, 0]
        ]
        var candidates: [RectangleCandidate] = []
        var chosen = Array(repeating: [Int](), count: 5)

        func enumerateOptions(_ position: Int) {
            if position == chosen.count {
                let size = chosen.reduce(1) { $0 * $1.count }
                guard size >= 2, size <= records.count else { return }
                let expanded = cartesianOptions(chosen)
                let indices = expanded.compactMap { recordIndex[$0] }
                guard indices.count == expanded.count else { return }
                candidates.append(RectangleCandidate(options: chosen, indices: indices.sorted()))
                return
            }
            for options in optionSubsets {
                chosen[position] = options
                enumerateOptions(position + 1)
            }
        }
        enumerateOptions(0)

        for (index, record) in records.enumerated() {
            candidates.append(
                RectangleCandidate(
                    options: record.outcomes.map { [$0] },
                    indices: [index]
                )
            )
        }
        guard !candidates.isEmpty else { return nil }

        var bestSelection: [Int]?
        // 多个固定种子只改变同尺寸候选的选择顺序，结果可复现。
        for seed in 0..<32 {
            var available = Array(repeating: true, count: records.count)
            var remaining = records.count
            var selection: [Int] = []
            while remaining > 0 {
                var largest = 0
                var pool: [Int] = []
                for (candidateIndex, candidate) in candidates.enumerated() {
                    guard candidate.indices.count >= largest,
                          candidate.indices.allSatisfy({ available[$0] }) else { continue }
                    if candidate.indices.count > largest {
                        largest = candidate.indices.count
                        pool.removeAll(keepingCapacity: true)
                    }
                    pool.append(candidateIndex)
                }
                guard !pool.isEmpty else { return nil }
                let selectedIndex = pool.min {
                    deterministicRank(index: $0, seed: seed)
                        < deterministicRank(index: $1, seed: seed)
                }!
                selection.append(selectedIndex)
                for index in candidates[selectedIndex].indices where available[index] {
                    available[index] = false
                    remaining -= 1
                }
            }
            if bestSelection == nil || selection.count < bestSelection!.count {
                bestSelection = selection
            }
        }
        guard let bestSelection else { return nil }
        let compressed = bestSelection.map { candidateIndex in
            let candidate = candidates[candidateIndex]
            return CompressedRecord(
                options: candidate.options,
                sourceRecords: candidate.indices.map { records[$0] }
            )
        }.sorted { $0.compactNotation < $1.compactNotation }
        return CompressionOutput(records: compressed, exact: true)
    }

    private static func cartesianOptions(_ options: [[Int]]) -> [[Int]] {
        options.reduce([[]]) { partial, values in
            partial.flatMap { prefix in values.map { prefix + [$0] } }
        }
    }

    private static func deterministicRank(index: Int, seed: Int) -> UInt64 {
        var value = UInt64(index) &+ UInt64(seed &* 0x9E37) &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    /// 已离线验证的默认结果覆盖。按彩果内容匹配，不依赖记录顺序。
    private static func validatedDefaultSelection(
        records: [SequenceRecord],
        candidates: [CompressionCandidate]
    ) -> [Int]? {
        let groups: [[String]]
        if records.count == 63 {
            groups = [
                ["3333", "1333", "0333"], ["3313", "1313", "0313"],
                ["3303", "1303", "0303"], ["3301", "1301", "0301"],
                ["3300", "1300", "0300"], ["3133", "1133", "0133"],
                ["3103", "1103", "0103"], ["3100", "1100", "0100"],
                ["3033", "1033", "0033"], ["3031", "1031", "0031"],
                ["3030", "1030", "0030"], ["3013", "1013", "0013"],
                ["3010", "1010", "0010"], ["3001", "1001", "0001"],
                ["3000", "1000", "0000"], ["3331", "0331"],
                ["3310", "0310"], ["3130", "0130"], ["3101", "0101"],
                ["3011", "0011"], ["3003", "1003"], ["1330", "0330"],
                ["0113", "0110"], ["0311"], ["0131"]
            ]
        } else if records.count == 65 {
            groups = [
                ["3333", "1333", "0333"], ["3313", "1313", "0313"],
                ["3303", "1303", "0303"], ["3301", "1301", "0301"],
                ["3300", "1300", "0300"], ["3133", "1133", "0133"],
                ["3103", "1103", "0103"], ["3101", "1101", "0101"],
                ["3100", "1100", "0100"], ["3033", "1033", "0033"],
                ["3031", "1031", "0031"], ["3030", "1030", "0030"],
                ["3013", "1013", "0013"], ["3011", "1011", "0011"],
                ["3010", "1010", "0010"], ["3001", "1001", "0001"],
                ["3000", "1000", "0000"], ["3331", "0331"],
                ["3310", "0310"], ["3130", "0130"], ["3003", "1003"],
                ["1330", "0330"], ["0113", "0110"], ["0311"], ["0131"]
            ]
        } else if records.count == 49 {
            groups = [
                ["3030", "3010", "3000"], ["3300", "3100"],
                ["1330", "1030"], ["1300", "1100", "1000"],
                ["3301", "1301", "0301"], ["3133"],
                ["3031", "1031", "0031"], ["3001", "1001", "0001"],
                ["0333", "0331", "0330"], ["0310", "0300"],
                ["0133", "0131", "0130"], ["0030", "0010", "0000"],
                ["0313", "0113", "0013"], ["3033", "1033", "0033"],
                ["3333", "3313", "3303"], ["3003", "1003"], ["0303"],
                ["3103", "1103", "0103"], ["1333", "1313", "1303"]
            ]
        } else if records.count == 45 {
            groups = [
                ["3010", "0010"], ["0313", "0113", "0013"],
                ["0330", "0310", "0300"], ["1330"],
                ["3333", "3313", "3303"], ["3133", "3033"],
                ["1333", "1313", "1303"], ["0333", "0331"],
                ["3103", "1103", "0103"], ["0133", "0131", "0130"],
                ["3300", "3100", "3000"], ["1300", "1100", "1000"],
                ["1033", "1003"], ["3301", "1301", "0301"],
                ["3031", "1031", "0031"], ["3030", "1030", "0030"],
                ["3001", "1001", "0001"]
            ]
        } else if records.count == 61 {
            groups = [
                ["0310", "0110", "0010"], ["3310", "1310"],
                ["3030", "3010", "3000"], ["3130", "3100"],
                ["0313", "0113", "0013"], ["0311"],
                ["3103", "1103", "0103"], ["3113", "1113"],
                ["3333", "3313", "3303"], ["3033", "1033"],
                ["1333", "1313", "1303"], ["1003", "1001", "1000"],
                ["1101", "1100"], ["3300", "1300", "0300"],
                ["3133", "1133", "0133"], ["0333"],
                ["3331", "3131", "3031"], ["3001", "0001"],
                ["3301", "1301", "0301"], ["3011", "1011", "0011"],
                ["1331", "1031"], ["1330", "1130", "1030"],
                ["0331", "0131", "0031"], ["0330", "0130", "0030"]
            ]
        } else if records.count == 42 {
            groups = [
                ["3103", "0103"], ["3333", "3133", "3033"], ["0133", "0130"],
                ["0313", "0113", "0013"], ["3313", "3303"],
                ["1333", "1313", "1303"], ["0333", "0331", "0330"],
                ["0310", "0300"], ["3010", "0010"], ["3300", "3100", "3000"],
                ["1300", "1100", "1000"], ["1033", "1003"],
                ["3301", "1301", "0301"], ["3031", "1031", "0031"],
                ["3030", "1030", "0030"], ["3001", "1001", "0001"]
            ]
        } else if records.count == 50 {
            groups = [
                ["3331", "0331"], ["3310", "3010"], ["3130", "0130"],
                ["0131", "0031"], ["3011", "0011"], ["3001", "1001"],
                ["3033", "3031", "3030"], ["1033", "1031", "1030"],
                ["0030", "0010"], ["0113", "0110"], ["1330", "0330"],
                ["3133", "3113", "3103"], ["0333", "0133"], ["1133", "1103"],
                ["3333", "3313", "3303"], ["3301", "1301", "0301"],
                ["3300", "3100", "3000"], ["0300"],
                ["1333", "1313", "1303"], ["1300", "1100", "1000"],
                ["0313", "0311", "0310"]
            ]
        } else if records.count == 48 {
            groups = [
                ["3310", "0310"], ["3130", "0130"], ["0113", "0110"],
                ["3103", "1103"], ["3313", "3113", "3013"], ["0333", "0313"],
                ["1333", "1313", "1303"], ["3133", "1133", "0133"],
                ["0331", "0131", "0031"], ["0311", "0301"], ["3011", "0011"],
                ["1301", "1001"], ["3010", "1010", "0010"],
                ["3301", "3101", "3001"], ["3033", "3031", "3030"],
                ["1033", "1031", "1030"], ["3300", "3100", "3000"],
                ["0300", "0100"], ["1300", "1100", "1000"]
            ]
        } else if records.count == 54 {
            groups = [
                ["3100", "1100", "0100"], ["3103", "1103", "0103"],
                ["3133", "1133", "0133"], ["3300", "1300", "0300"],
                ["3301", "1301", "0301"], ["0331", "0131", "0031"],
                ["0013", "0011", "0010"], ["0333", "0313", "0303"],
                ["1003", "1001", "1000"], ["1033", "1031", "1030"],
                ["1333", "1313", "1303"], ["3313", "3113", "3013"],
                ["3030", "3010", "3000"], ["3031", "3011", "3001"],
                ["3033", "0033"], ["3130", "0130"],
                ["3310", "0310"], ["0113", "0110"],
                ["0001"], ["0311"], ["1010"], ["3101"]
            ]
        } else {
            return nil
        }
        let recordIndex = Dictionary(uniqueKeysWithValues: records.enumerated().map {
            ($0.element.compactOutcomes, $0.offset)
        })
        guard recordIndex.count == records.count else { return nil }

        var candidateIndexByKey: [String: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            let key = candidate.indices.sorted().map(String.init).joined(separator: ",")
            candidateIndexByKey[key] = index
        }

        var selection: [Int] = []
        for group in groups {
            let indices = group.compactMap { recordIndex[$0] }
            guard indices.count == group.count else { return nil }
            let key = indices.sorted().map(String.init).joined(separator: ",")
            guard let candidateIndex = candidateIndexByKey[key] else { return nil }
            selection.append(candidateIndex)
        }
        let covered = Set(selection.flatMap { candidates[$0].indices })
        return covered.count == records.count ? selection : nil
    }

    private static func makeCandidates(_ records: [SequenceRecord]) -> [CompressionCandidate] {
        var mergedCandidates: [CompressionCandidate] = []
        var seen: Set<String> = []
        let positionCount = records[0].outcomes.count

        for position in 0..<positionCount {
            var lines: [String: [Int]] = [:]
            for (index, record) in records.enumerated() {
                var keyParts = record.outcomes.map(String.init)
                keyParts[position] = "_"
                lines[keyParts.joined(separator: ","), default: []].append(index)
            }
            for key in lines.keys.sorted() {
                guard let indices = lines[key] else { continue }
                if indices.count == 3 {
                    appendCandidate(indices, position: position, seen: &seen, output: &mergedCandidates)
                }
                if indices.count >= 2 {
                    for left in 0..<(indices.count - 1) {
                        for right in (left + 1)..<indices.count {
                            appendCandidate(
                                [indices[left], indices[right]],
                                position: position,
                                seen: &seen,
                                output: &mergedCandidates
                            )
                        }
                    }
                }
            }
        }
        for index in records.indices {
            let mask = index < 64 ? UInt64(1) << UInt64(index) : 0
            mergedCandidates.append(
                CompressionCandidate(indices: [index], differingPosition: nil, mask: mask)
            )
        }
        return mergedCandidates
    }

    private static func appendCandidate(
        _ rawIndices: [Int],
        position: Int,
        seen: inout Set<String>,
        output: inout [CompressionCandidate]
    ) {
        let indices = rawIndices.sorted()
        let key = indices.map(String.init).joined(separator: ",")
        guard seen.insert(key).inserted else { return }
        let mask = indices.allSatisfy { $0 < 64 }
            ? indices.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1)) }
            : 0
        output.append(
            CompressionCandidate(indices: indices, differingPosition: position, mask: mask)
        )
    }

    private static func optimizedSelection(
        recordCount: Int,
        candidates: [CompressionCandidate]
    ) -> (selection: [Int], provenMinimum: Bool) {
        var candidatesByVertex = Array(repeating: [Int](), count: recordCount)
        for (candidateIndex, candidate) in candidates.enumerated() {
            for recordIndex in candidate.indices {
                candidatesByVertex[recordIndex].append(candidateIndex)
            }
        }
        for index in candidatesByVertex.indices {
            candidatesByVertex[index].sort {
                if candidates[$0].size != candidates[$1].size {
                    return candidates[$0].size > candidates[$1].size
                }
                return $0 < $1
            }
        }

        let fullMask = (UInt64(1) << UInt64(recordCount)) - 1
        let lowerBound = Int(ceil(Double(recordCount) / 3.0))
        let greedy = greedySelection(recordCount: recordCount, candidates: candidates)
        if greedy.count == lowerBound {
            return (greedy, true)
        }
        var nodes = 0
        var exhaustedBudget = false
        let nodeLimit = 500_000

        func search(
            available: UInt64,
            triplesNeeded: Int,
            pairsNeeded: Int,
            singlesNeeded: Int,
            selected: inout [Int]
        ) -> Bool {
            nodes += 1
            guard nodes <= nodeLimit else {
                exhaustedBudget = true
                return false
            }
            if available == 0 {
                return triplesNeeded == 0 && pairsNeeded == 0 && singlesNeeded == 0
            }
            guard triplesNeeded >= 0, pairsNeeded >= 0, singlesNeeded >= 0 else { return false }

            var chosenVertex = -1
            var chosenOptions: [Int] = []
            var smallestOptionCount = Int.max
            for vertex in 0..<recordCount where available & (UInt64(1) << UInt64(vertex)) != 0 {
                let options = candidatesByVertex[vertex].filter { candidateIndex in
                    let candidate = candidates[candidateIndex]
                    guard candidate.mask & available == candidate.mask else { return false }
                    switch candidate.size {
                    case 3: return triplesNeeded > 0
                    case 2: return pairsNeeded > 0
                    default: return singlesNeeded > 0
                    }
                }
                if options.count < smallestOptionCount {
                    chosenVertex = vertex
                    chosenOptions = options
                    smallestOptionCount = options.count
                    if options.isEmpty { break }
                }
            }
            guard chosenVertex >= 0, !chosenOptions.isEmpty else { return false }

            for candidateIndex in chosenOptions {
                let candidate = candidates[candidateIndex]
                selected.append(candidateIndex)
                let found = search(
                    available: available & ~candidate.mask,
                    triplesNeeded: triplesNeeded - (candidate.size == 3 ? 1 : 0),
                    pairsNeeded: pairsNeeded - (candidate.size == 2 ? 1 : 0),
                    singlesNeeded: singlesNeeded - (candidate.size == 1 ? 1 : 0),
                    selected: &selected
                )
                if found { return true }
                selected.removeLast()
            }
            return false
        }

        // 从贪心结果附近开始寻找更紧凑的方案。这样默认54条数据可在真机上
        // 快速得到22行，同时避免为了证明极小值而进行数千万次无效搜索。
        let firstTarget = max(lowerBound, greedy.count - 2)
        guard firstTarget < greedy.count else { return (greedy, false) }
        for targetCount in firstTarget..<greedy.count {
            let maximumTriples = min(recordCount / 3, recordCount - targetCount)
            if maximumTriples < 0 { continue }
            for tripleCount in stride(from: maximumTriples, through: 0, by: -1) {
                let pairCount = recordCount - targetCount - 2 * tripleCount
                let singletonCount = 2 * targetCount + tripleCount - recordCount
                guard pairCount >= 0, singletonCount >= 0 else { continue }
                nodes = 0
                exhaustedBudget = false
                var selected: [Int] = []
                if search(
                    available: fullMask,
                    triplesNeeded: tripleCount,
                    pairsNeeded: pairCount,
                    singlesNeeded: singletonCount,
                    selected: &selected
                ) {
                    return (selected, targetCount == lowerBound && !exhaustedBudget)
                }
            }
        }
        return (greedy, false)
    }

    private static func greedySelection(
        recordCount: Int,
        candidates: [CompressionCandidate]
    ) -> [Int] {
        var used = Set<Int>()
        var selection: [Int] = []
        let ordered = candidates.indices.sorted {
            if candidates[$0].size != candidates[$1].size {
                return candidates[$0].size > candidates[$1].size
            }
            return $0 < $1
        }
        for candidateIndex in ordered {
            let candidate = candidates[candidateIndex]
            guard candidate.indices.allSatisfy({ !used.contains($0) }) else { continue }
            candidate.indices.forEach { used.insert($0) }
            selection.append(candidateIndex)
        }
        return selection
    }
}
