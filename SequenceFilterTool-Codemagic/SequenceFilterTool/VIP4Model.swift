import Foundation

/// VIP4 的单场赛前输入。所有让球赔率必须由普通欧赔和实际让球经项目对照表换算。
struct VIP4MatchInput: Equatable, Sendable {
    let comparisonTableOdds: [Double]
    let ordinaryOdds: [Double]
    let handicap: Int
    let league: String
    let logic: LogicMapping
    let homeExpectedGoals: Double
    let awayExpectedGoals: Double
    let fitError: Double
}

/// previousOutcomes 是同一期前一个已结束六场组的彩果；缺失时自动退化为不带转移修正的通用概率模型。
struct VIP4MatchContext: Equatable, Sendable {
    let matches: [VIP4MatchInput]
    let previousOutcomes: [Int]?
}

enum VIP4Bayesian150Model {
    static let configurationMarker = 7.154
    static let fallbackVersion = "VIP4-REAL-HANDICAP-ODDS-BAYES-NO-234-K150-TOP2-V3"
    static let keptCount = 150

    private struct Asset: Decodable, Sendable {
        let version: String
        let outcomes: [Int]
        let featureNames: [String]
        let classes: [Int]
        let intercepts: [Double]
        let coefficients: [[Double]]
        let positionTransition: [[[Double]]]
        let aggregateTransition: [[Double]]
        let portfolioWeights: [Double]
        let transitionLogWeight: Double
        let gateMassWeight: Double
        let recommendedGroupsPerIssue: Int
        let keptBetsPerGroup: Int

        enum CodingKeys: String, CodingKey {
            case version, outcomes, classes, intercepts, coefficients
            case featureNames = "feature_names"
            case positionTransition = "position_transition"
            case aggregateTransition = "aggregate_transition"
            case portfolioWeights = "portfolio_weights"
            case transitionLogWeight = "transition_log_weight"
            case gateMassWeight = "gate_mass_weight"
            case recommendedGroupsPerIssue = "recommended_groups_per_issue"
            case keptBetsPerGroup = "kept_bets_per_group"
        }
    }

    private static let asset: Asset? = {
        guard let url = Bundle.main.url(forResource: "VIP4Model", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Asset.self, from: data)
    }()

    static var version: String {
        (asset?.version ?? fallbackVersion) + "+REAL-HANDICAP-ODDS-NO-234-V3"
    }

    static func isSelected(configurationValue: Double?) -> Bool {
        guard let configurationValue else { return false }
        return abs(configurationValue - configurationMarker) < 0.000_001
    }

    static func selectTop(
        _ expanded: [[Int]],
        context: VIP4MatchContext?
    ) -> [[Int]] {
        guard !expanded.isEmpty,
              let model = asset,
              let context,
              context.matches.count == 6,
              model.portfolioWeights.count == 3,
              model.keptBetsPerGroup == keptCount,
              let rawRows = probabilityRows(context.matches.map(\.comparisonTableOdds)),
              let calibratedRows = calibratedProbabilities(context.matches, model: model) else {
            return []
        }
        let transitionRows = transitionAdjustedRows(
            rawRows,
            previousOutcomes: context.previousOutcomes,
            model: model
        )
        let ranked = expanded.enumerated().compactMap { originalIndex, outcomes -> (Int, [Int], Double)? in
            let firstSix = Array(outcomes.prefix(6))
            guard firstSix.count == 6 else { return nil }
            var rawJoint = 1.0
            var calibratedJoint = 1.0
            var transitionJoint = 1.0
            for position in 0..<6 {
                guard let outcomeIndex = outcomeIndex(firstSix[position]) else { return nil }
                rawJoint *= rawRows[position][outcomeIndex]
                calibratedJoint *= calibratedRows[position][outcomeIndex]
                transitionJoint *= transitionRows[position][outcomeIndex]
            }
            let score = model.portfolioWeights[0] * rawJoint
                + model.portfolioWeights[1] * calibratedJoint
                + model.portfolioWeights[2] * transitionJoint
            return (originalIndex, firstSix, score)
        }
        guard ranked.count == expanded.count else { return [] }
        return ranked.sorted { left, right in
            if abs(left.2 - right.2) > 1e-18 { return left.2 > right.2 }
            return left.0 < right.0
        }
        .prefix(keptCount)
        .map(\.1)
    }

    /// 当一期有多个六场组时，可用该值与 meanRawConfidence 在期内排名，只推荐前2组。
    static func top150Mass(context: VIP4MatchContext?) -> Double? {
        guard let context else { return nil }
        let all = cartesianOutcomes(count: 6)
        guard let model = asset,
              let raw = probabilityRows(context.matches.map(\.comparisonTableOdds)),
              let calibrated = calibratedProbabilities(context.matches, model: model) else { return nil }
        let adjusted = transitionAdjustedRows(raw, previousOutcomes: context.previousOutcomes, model: model)
        let scores = all.compactMap { outcomes -> Double? in
            var values = [1.0, 1.0, 1.0]
            for position in 0..<6 {
                guard let index = outcomeIndex(outcomes[position]) else { return nil }
                values[0] *= raw[position][index]
                values[1] *= calibrated[position][index]
                values[2] *= adjusted[position][index]
            }
            return zip(model.portfolioWeights, values).reduce(0) { $0 + $1.0 * $1.1 }
        }
        guard scores.count == 729 else { return nil }
        return scores.sorted(by: >).prefix(keptCount).reduce(0, +)
    }

    static func meanRawConfidence(context: VIP4MatchContext?) -> Double? {
        guard let context,
              let rows = probabilityRows(context.matches.map(\.comparisonTableOdds)) else { return nil }
        return rows.map { $0.max() ?? 0 }.reduce(0, +) / Double(rows.count)
    }

    private static func calibratedProbabilities(_ matches: [VIP4MatchInput], model: Asset) -> [[Double]]? {
        guard matches.count == 6,
              model.coefficients.count == model.classes.count,
              model.intercepts.count == model.classes.count,
              model.coefficients.allSatisfy({ $0.count == model.featureNames.count }) else { return nil }
        return matches.map { match in
            let values = featureValues(match, names: model.featureNames)
            let logits = model.classes.indices.map { classIndex in
                model.intercepts[classIndex]
                    + zip(model.coefficients[classIndex], values).reduce(0) { $0 + $1.0 * $1.1 }
            }
            let maximum = logits.max() ?? 0
            let exponentials = logits.map { exp($0 - maximum) }
            let total = exponentials.reduce(0, +)
            var ordered = Array(repeating: 0.0, count: 3)
            for (sourceIndex, classValue) in model.classes.enumerated() where ordered.indices.contains(classValue) {
                ordered[classValue] = exponentials[sourceIndex] / max(total, 1e-15)
            }
            return ordered
        }
    }

    private static func featureValues(_ match: VIP4MatchInput, names: [String]) -> [Double] {
        let p = normalizedProbabilities(match.comparisonTableOdds) ?? [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let ordinary = normalizedProbabilities(match.ordinaryOdds) ?? [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let numeric: [String: Double] = [
            "p3": p[0], "p1": p[1], "p0": p[2],
            "log_3_0": log(max(p[0], 1e-15) / max(p[2], 1e-15)),
            "log_1_0": log(max(p[1], 1e-15) / max(p[2], 1e-15)),
            "maximum": p.max() ?? 0,
            "entropy": -p.reduce(0) { $0 + $1 * log(max($1, 1e-15)) },
            "ordinary_p3": ordinary[0], "ordinary_p1": ordinary[1], "ordinary_p0": ordinary[2],
            "ordinary_log_3_0": log(max(ordinary[0], 1e-15) / max(ordinary[2], 1e-15)),
            "ordinary_log_1_0": log(max(ordinary[1], 1e-15) / max(ordinary[2], 1e-15)),
            "handicap": Double(match.handicap), "abs_handicap": Double(abs(match.handicap)),
            "home_lambda": match.homeExpectedGoals, "away_lambda": match.awayExpectedGoals,
            "lambda_difference": match.homeExpectedGoals - match.awayExpectedGoals,
            "fit_error": match.fitError
        ]
        let leagueFeature = "league=league=\(match.league)"
        return names.map { name in
            // VIP4 V3开始不再使用ABCD→2/3/4的类别特征。
            if name.hasPrefix("logic=logic=") { return 0 }
            if name == leagueFeature { return 1 }
            return numeric[name] ?? 0
        }
    }

    private static func transitionAdjustedRows(
        _ raw: [[Double]],
        previousOutcomes: [Int]?,
        model: Asset
    ) -> [[Double]] {
        guard let previousOutcomes,
              previousOutcomes.count == 6,
              model.positionTransition.count == 6,
              model.aggregateTransition.count == 3 else { return raw }
        return raw.enumerated().map { position, row in
            guard let previousIndex = outcomeIndex(previousOutcomes[position]),
                  model.positionTransition[position].indices.contains(previousIndex),
                  model.aggregateTransition.indices.contains(previousIndex) else { return row }
            let positionRow = model.positionTransition[position][previousIndex]
            let aggregateRow = model.aggregateTransition[previousIndex]
            guard positionRow.count == 3, aggregateRow.count == 3 else { return row }
            let adjusted = row.indices.map { index in
                let transition = 0.65 * positionRow[index] + 0.35 * aggregateRow[index]
                return exp(log(max(row[index], 1e-15)) + model.transitionLogWeight * log(max(transition, 1e-15)))
            }
            let total = adjusted.reduce(0, +)
            return adjusted.map { $0 / max(total, 1e-15) }
        }
    }

    private static func probabilityRows(_ odds: [[Double]]) -> [[Double]]? {
        guard odds.count == 6 else { return nil }
        let rows = odds.compactMap(normalizedProbabilities)
        return rows.count == 6 ? rows : nil
    }

    private static func normalizedProbabilities(_ odds: [Double]) -> [Double]? {
        guard odds.count == 3, odds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let inverse = odds.map { 1 / $0 }
        let total = inverse.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        return inverse.map { $0 / total }
    }

    private static func outcomeIndex(_ outcome: Int) -> Int? {
        switch outcome {
        case 3: return 0
        case 1: return 1
        case 0: return 2
        default: return nil
        }
    }

    private static func cartesianOutcomes(count: Int) -> [[Int]] {
        guard count > 0 else { return [[]] }
        return (0..<count).reduce([[]]) { partial, _ in
            partial.flatMap { prefix in [3, 1, 0].map { prefix + [$0] } }
        }
    }
}
