import Foundation
import CoreFoundation

enum ScoreMatchPagination {
    static func pageRanges(totalCount: Int, pageSize: Int = 30) -> [Range<Int>] {
        guard totalCount > 0, pageSize > 0 else { return [] }
        return stride(from: 0, to: totalCount, by: pageSize).map { start in
            start..<min(start + pageSize, totalCount)
        }
    }
}

enum HistoricalBatchPlanner {
    static func groupStarts(maximumMatchNumber: Int) -> [Int] {
        guard maximumMatchNumber >= 7 else { return [] }
        return Array(stride(from: 2, through: maximumMatchNumber - 5, by: 6))
    }

    static func ticketMatchNumbers(start: Int) -> [String] {
        Array(start...(start + 5)).map(String.init) + ["1"]
    }
}

private actor BeijingSingleScorePageCache {
    static let shared = BeijingSingleScorePageCache()
    private var matchesByIssue: [String: [BeijingSingleMatch]] = [:]

    func matches(for issue: String) -> [BeijingSingleMatch]? {
        matchesByIssue[issue]
    }

    func store(_ matches: [BeijingSingleMatch], for issue: String) {
        matchesByIssue[issue] = matches
    }
}

struct BeijingSingleMatch: Equatable, Sendable {
    let issue: String
    let matchNumber: String
    let fixtureID: String
    let league: String
    let matchTime: String
    let status: String
    let homeTeam: String
    let awayTeam: String
    let handicap: Int?
    /// 500参考SP，顺序为让球胜、让球平、让球负。
    let referenceSP: [Double]
    /// 500页面中的百家平均欧赔，顺序为普通胜、平、负。
    let marketOdds: [Double]
    /// 来源明确发布的胜平负投注占比；缺失时为空，不从赔率反推。
    let marketBettingShares: [Double]
    let homeScore: Int?
    let awayScore: Int?
    /// 官方开奖后仅保留的中奖方向SP。
    let settledSP: Double?

    init(
        issue: String,
        matchNumber: String,
        fixtureID: String,
        league: String,
        matchTime: String,
        status: String,
        homeTeam: String,
        awayTeam: String,
        handicap: Int?,
        referenceSP: [Double],
        marketOdds: [Double] = [],
        marketBettingShares: [Double] = [],
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        settledSP: Double? = nil
    ) {
        self.issue = issue
        self.matchNumber = matchNumber
        self.fixtureID = fixtureID
        self.league = league
        self.matchTime = matchTime
        self.status = status
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.handicap = handicap
        self.referenceSP = referenceSP
        self.marketOdds = marketOdds
        self.marketBettingShares = marketBettingShares
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.settledSP = settledSP
    }

    var handicapOutcome: Int? {
        guard let handicap, let homeScore, let awayScore else { return nil }
        let difference = homeScore + handicap - awayScore
        return difference > 0 ? 3 : (difference == 0 ? 1 : 0)
    }

    var hasStarted: Bool { !status.contains("未") }

    func replacingHandicap(_ value: Int?) -> BeijingSingleMatch {
        BeijingSingleMatch(
            issue: issue,
            matchNumber: matchNumber,
            fixtureID: fixtureID,
            league: league,
            matchTime: matchTime,
            status: status,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            handicap: value,
            referenceSP: referenceSP,
            marketOdds: marketOdds,
            marketBettingShares: marketBettingShares,
            homeScore: homeScore,
            awayScore: awayScore,
            settledSP: settledSP
        )
    }

    func replacingMarketOdds(_ odds: [Double]) -> BeijingSingleMatch {
        BeijingSingleMatch(issue: issue, matchNumber: matchNumber, fixtureID: fixtureID, league: league,
            matchTime: matchTime, status: status, homeTeam: homeTeam, awayTeam: awayTeam, handicap: handicap,
            referenceSP: referenceSP, marketOdds: odds, marketBettingShares: marketBettingShares,
            homeScore: homeScore, awayScore: awayScore, settledSP: settledSP)
    }

    /// 仅在数据源明确写出延期时长时识别，避免把普通“已开赛/完”误判为延期。
    var postponementHours: Double? {
        let source = "\(status) \(matchTime)"
        let patterns = [
            #"(?i)(?:延期|推迟|延迟|postponed|delay)[^0-9]{0,8}(\d+(?:\.\d+)?)\s*(?:小时|小時|h)"#,
            #"(?i)(\d+(?:\.\d+)?)\s*(?:小时|小時|h)[^0-9]{0,8}(?:延期|推迟|延迟|postponed|delay)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
                  let range = Range(match.range(at: 1), in: source),
                  let hours = Double(source[range]) else { continue }
            return hours
        }
        return nil
    }

    var isPostponedOver12Hours: Bool {
        postponementHours.map { $0 > 12 } == true
    }

    /// 进入推荐模型前隔离比分与赛果，避免已开赛/完场数据直接倒灌。
    var resultBlindCopy: BeijingSingleMatch {
        BeijingSingleMatch(
            issue: issue,
            matchNumber: matchNumber,
            fixtureID: fixtureID,
            league: league,
            matchTime: matchTime,
            status: hasStarted ? "已开赛·赛果已隔离" : status,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            handicap: handicap,
            referenceSP: referenceSP,
            marketOdds: marketOdds,
            marketBettingShares: marketBettingShares,
            homeScore: nil,
            awayScore: nil,
            settledSP: settledSP
        )
    }
}

struct AsianHandicapPoint: Equatable, Sendable {
    let homeWater: Double
    let handicap: String
    let awayWater: Double

    var displayText: String {
        "主水 \(String(format: "%.3f", homeWater))  │  \(handicap)  │  客水 \(String(format: "%.3f", awayWater))"
    }
}

struct AsianHandicapQuote: Equatable, Sendable {
    let companyID: Int
    let companyName: String
    let initial: AsianHandicapPoint?
    let current: AsianHandicapPoint
}

/// Display-only values from the 500 Beijing Single scoreboard. Never a filter input.
struct SeventhMatchMarketSnapshot: Equatable, Sendable {
    let match: BeijingSingleMatch
    let asianHandicap: String?
    let capturedAt: Date
    var asianQuote: AsianHandicapQuote? = nil
    var asianQuoteMessage: String? = nil

    var referenceSPText: String {
        if match.referenceSP.count == 3,
           match.referenceSP.allSatisfy({ $0.isFinite && $0 > 0 }) {
            return zip(["胜", "平", "负"], match.referenceSP).map {
                "\($0.0) \(String(format: "%.2f", $0.1))"
            }.joined(separator: "  ")
        }
        if let settled = match.settledSP, settled.isFinite, settled > 0,
           let outcome = match.handicapOutcome {
            let direction = outcome == 3 ? "胜" : (outcome == 1 ? "平" : "负")
            return "开奖SP：\(direction) \(String(format: "%.2f", settled))（三项未齐）"
        }
        return "未发布完整三项SP"
    }
}

/// 查询页的终局门禁。临时比分、已开赛状态或普通延期都不是最终结果；
/// 唯一例外是数据源明确写出延期超过12小时，该场才按1处理。
enum QueryFinalityGate {
    static func isFinallyEnded(_ match: BeijingSingleMatch) -> Bool {
        match.settledSP != nil
            || match.status.contains("完")
            || match.status.contains("结束")
            || match.status.lowercased().contains("finished")
    }

    static func permitsResult(
        matches: [BeijingSingleMatch],
        expectedCount: Int
    ) -> Bool {
        expectedCount > 0
            && matches.count == expectedCount
            && matches.allSatisfy { match in
                (isFinallyEnded(match) && match.handicapOutcome != nil)
                    || match.isPostponedOver12Hours
            }
    }

    static func resolvedOutcome(_ match: BeijingSingleMatch) -> Int? {
        if isFinallyEnded(match), let outcome = match.handicapOutcome {
            return outcome
        }
        return match.isPostponedOver12Hours ? 1 : nil
    }
}

/// Input-page prize query: the user requests published SP for payouts, and the
/// generation-time reference SP for estimates. This does not alter filter odds.
struct TXTQuerySPSnapshot: Equatable, Sendable {
    let issue: String
    let matchNumber: String
    let values: [Double]
    let capturedAt: Date

    static func capture(_ matches: [BeijingSingleMatch], at date: Date = Date()) -> [Self] {
        matches.compactMap { match in
            guard match.referenceSP.count == 3 else { return nil }
            return Self(issue: match.issue, matchNumber: match.matchNumber,
                        values: match.referenceSP, capturedAt: date)
        }
    }
}

struct TXTQueryPrizeAmount: Equatable, Sendable {
    let amount: Double?
    let isEstimate: Bool
    let message: String
}

struct TXTQuerySeventhPrize: Equatable, Sendable {
    let outcome: Int?
    let prize: TXTQueryPrizeAmount
}

struct TXTQueryPrizeReport: Equatable, Sendable {
    let six: TXTQueryPrizeAmount
    let seven: [TXTQuerySeventhPrize]
    let multiplier: Int

    var displayText: String {
        func line(_ title: String, _ prize: TXTQueryPrizeAmount) -> String {
            guard let amount = prize.amount else { return "\(title)：暂无法计算；\(prize.message)" }
            return "\(title)\(prize.isEstimate ? "（预估）" : "")：¥\(String(format: "%.2f", amount))\n\(prize.message)"
        }
        var lines = ["奖金按\(multiplier)倍计算，对应赛果SP连乘后×1.3。", line("六场总奖金", six)]
        for row in seven {
            let suffix = seven.count > 1 ? "（第7场选\(row.outcome.map(String.init) ?? "-")）" : ""
            lines.append(line("七场总奖金" + suffix, row.prize))
        }
        return lines.joined(separator: "\n")
    }
}

enum TXTQueryPrizeCalculator {
    private struct Factor {
        let value: Double
        let estimated: Bool
        let note: String
    }

    static func calculate(
        issue: String, matchNumbers: [String], firstSixOutcomes: [Int],
        seventhOptions: [Int], matches: [BeijingSingleMatch],
        snapshots: [TXTQuerySPSnapshot], isSimulation: Bool, multiplier: Int = 1
    ) -> TXTQueryPrizeReport {
        func unavailable(_ message: String) -> TXTQueryPrizeAmount {
            TXTQueryPrizeAmount(amount: nil, isEstimate: true, message: message)
        }
        func sameNumber(_ a: String, _ b: String) -> Bool {
            guard let a = Int(a), let b = Int(b) else { return false }
            return a == b
        }
        func match(_ number: String) -> BeijingSingleMatch? {
            matches.first { $0.issue == issue && sameNumber($0.matchNumber, number) }
        }
        func factor(_ number: String, outcome: Int) -> Factor? {
            guard let column = [3,1,0].firstIndex(of: outcome) else { return nil }
            let current = match(number)
            if let current, current.isPostponedOver12Hours {
                return Factor(value: 1, estimated: false, note: "场次\(number)延期>12小时，按1.00")
            }
            if let current, QueryFinalityGate.isFinallyEnded(current),
               current.handicapOutcome == outcome,
               let settled = current.settledSP, settled.isFinite, settled > 0 {
                return Factor(value: settled, estimated: false, note: "场次\(number)开奖SP \(String(format: "%.2f", settled))")
            }
            if let saved = snapshots.first(where: { $0.issue == issue && sameNumber($0.matchNumber, number) }),
               saved.values.count == 3, saved.values[column].isFinite, saved.values[column] > 0 {
                return Factor(value: saved.values[column], estimated: true,
                              note: "场次\(number)生成时SP \(String(format: "%.2f", saved.values[column]))")
            }
            if let current, current.referenceSP.count == 3,
               current.referenceSP[column].isFinite, current.referenceSP[column] > 0 {
                return Factor(value: current.referenceSP[column], estimated: true,
                              note: "场次\(number)查询时SP \(String(format: "%.2f", current.referenceSP[column]))（生成时未保存）")
            }
            return nil
        }
        func amount(_ factors: [Factor], note: String = "") -> TXTQueryPrizeAmount {
            let total = factors.reduce(1.0) { $0 * $1.value } * Double(multiplier) * 1.3
            guard total.isFinite else { return unavailable("SP乘积超出可计算范围") }
            let estimated = isSimulation || factors.contains { $0.estimated }
            let details = factors.map(\.note).joined(separator: "；")
            return TXTQueryPrizeAmount(amount: total, isEstimate: estimated,
                                       message: [isSimulation ? "手动赛果模拟金额" : "", note, details].filter { !$0.isEmpty }.joined(separator: "；"))
        }
        guard matchNumbers.count >= 6, firstSixOutcomes.count == 6,
              firstSixOutcomes.allSatisfy({ [3,1,0].contains($0) }), multiplier > 0 else {
            let missing = unavailable("缺少有效六场赛果、场次或投注倍数")
            return TXTQueryPrizeReport(six: missing, seven: [.init(outcome: nil, prize: missing)], multiplier: multiplier)
        }
        var factors: [Factor] = []
        var missingNumbers: [String] = []
        for (number,outcome) in zip(matchNumbers.prefix(6), firstSixOutcomes) {
            if let selected = factor(number, outcome: outcome) { factors.append(selected) }
            else { missingNumbers.append(number) }
        }
        let six = missingNumbers.isEmpty ? amount(factors) : unavailable("场次\(missingNumbers.joined(separator: "、"))缺少对应赛果SP")
        guard matchNumbers.count >= 7, !seventhOptions.isEmpty else {
            return TXTQueryPrizeReport(six: six, seven: [.init(outcome: nil, prize: unavailable("当前TXT没有第7场投注选项"))], multiplier: multiplier)
        }
        let seventhNumber = matchNumbers[6]
        let options = Set(seventhOptions.filter { [3,1,0].contains($0) }).sorted(by: >)
        if let seventh = match(seventhNumber), QueryFinalityGate.isFinallyEnded(seventh),
           let actual = seventh.handicapOutcome {
            let seven: TXTQueryPrizeAmount
            if !missingNumbers.isEmpty { seven = unavailable("前六场对应赛果SP不完整") }
            else if let sp = factor(seventhNumber, outcome: actual) { seven = amount(factors + [sp], note: "第7场按实际赛果\(actual)的SP计算，不判断投注选项是否命中") }
            else { seven = unavailable("第7场\(seventhNumber)缺少赛果\(actual)对应SP") }
            return TXTQueryPrizeReport(six: six, seven: [.init(outcome: actual, prize: seven)], multiplier: multiplier)
        }
        let rows = options.map { outcome -> TXTQuerySeventhPrize in
            let prize: TXTQueryPrizeAmount
            if !missingNumbers.isEmpty { prize = unavailable("前六场对应赛果SP不完整") }
            else if let sp = factor(seventhNumber, outcome: outcome) {
                let calculated = amount(factors + [sp], note: "第7场\(seventhNumber)尚未开奖，假设赛果为\(outcome)")
                prize = TXTQueryPrizeAmount(amount: calculated.amount, isEstimate: true, message: calculated.message)
            } else { prize = unavailable("第7场\(seventhNumber)缺少赛果\(outcome)对应SP") }
            return TXTQuerySeventhPrize(outcome: outcome, prize: prize)
        }
        return TXTQueryPrizeReport(six: six, seven: rows, multiplier: multiplier)
    }
}


/// 第三条宪法的唯一生产实现：完整普通欧赔＋实际让球数
/// 经项目的 Poisson/Dixon–Coles 让球赔率对照表口径，换算为让球胜/平/负。
/// 页面 `referenceSP` 即使完整也不直接使用，避免当前生成与历史回算口径分裂。
enum HandicapOddsComparisonTable {
    private static let maximumGoals = 18
    private static let dixonColesRho = -0.08

    private struct ConversionKey: Hashable {
        let odds: [Double]
        let handicap: Int
    }

    /// 只缓存纯函数的精确输入；报价或让球改变会生成不同键。
    /// 页面验证、选场、双选与生成可复用结果，不重复拟合相同赔率。
    private final class ConversionCache: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [ConversionKey: [Double]] = [:]

        func value(for key: ConversionKey) -> [Double]? {
            lock.lock()
            defer { lock.unlock() }
            return rows[key]
        }

        func store(_ value: [Double], for key: ConversionKey) {
            lock.lock()
            defer { lock.unlock() }
            if rows.count >= 2048 { rows.removeAll(keepingCapacity: true) }
            rows[key] = value
        }
    }

    private static let conversionCache = ConversionCache()

    private static let coarseGoalGrid: [(home: Double, away: Double, normal: [Double])] = {
        var result: [(Double, Double, [Double])] = []
        result.reserveCapacity(44 * 44)
        for homeIndex in 2...45 {
            let home = Double(homeIndex) / 10
            for awayIndex in 2...45 {
                let away = Double(awayIndex) / 10
                result.append((home, away, resultProbabilities(home: home, away: away, handicap: 0)))
            }
        }
        return result
    }()

    static func convertedOdds(ordinaryOdds: [Double], handicap: Int) -> [Double]? {
        guard ordinaryOdds.count == 3,
              ordinaryOdds.allSatisfy({ $0.isFinite && $0 > 1 }) else { return nil }
        let key = ConversionKey(odds: ordinaryOdds, handicap: handicap)
        if let cached = conversionCache.value(for: key) { return cached }
        guard let converted = calculateConvertedOdds(ordinaryOdds: ordinaryOdds, handicap: handicap) else { return nil }
        conversionCache.store(converted, for: key)
        return converted
    }

    private static func calculateConvertedOdds(ordinaryOdds: [Double], handicap: Int) -> [Double]? {
        let inverse = ordinaryOdds.map { 1 / $0 }
        let inverseTotal = inverse.reduce(0, +)
        guard inverseTotal.isFinite, inverseTotal > 0 else { return nil }
        let target = inverse.map { $0 / inverseTotal }

        // 不让球仍经过对照表口径去水，不直接返回普通欧赔。
        if handicap == 0 {
            return target.map { 1 / max($0, 1e-12) }
        }

        var bestHome = 1.3
        var bestAway = 1.1
        var bestError = Double.greatestFiniteMagnitude
        for candidate in coarseGoalGrid {
            let error = squaredError(candidate.normal, target)
            if error < bestError {
                bestError = error
                bestHome = candidate.home
                bestAway = candidate.away
            }
        }

        let startHome = max(0.05, bestHome - 0.12)
        let startAway = max(0.05, bestAway - 0.12)
        for homeIndex in 0...24 {
            let home = startHome + Double(homeIndex) * 0.01
            for awayIndex in 0...24 {
                let away = startAway + Double(awayIndex) * 0.01
                let normal = resultProbabilities(home: home, away: away, handicap: 0)
                let error = squaredError(normal, target)
                if error < bestError {
                    bestError = error
                    bestHome = home
                    bestAway = away
                }
            }
        }

        let probabilities = resultProbabilities(
            home: bestHome,
            away: bestAway,
            handicap: handicap
        )
        guard probabilities.count == 3,
              probabilities.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return probabilities.map { 1 / max($0, 1e-12) }
    }

    private static func squaredError(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).reduce(0) { result, pair in
            let delta = pair.0 - pair.1
            return result + delta * delta
        }
    }

    private static func resultProbabilities(home: Double, away: Double, handicap: Int) -> [Double] {
        let homeProbabilities = poissonProbabilities(lambda: home)
        let awayProbabilities = poissonProbabilities(lambda: away)
        var result = [0.0, 0.0, 0.0]
        var total = 0.0
        for homeGoals in 0...maximumGoals {
            for awayGoals in 0...maximumGoals {
                var adjustment = 1.0
                switch (homeGoals, awayGoals) {
                case (0, 0): adjustment = 1 - home * away * dixonColesRho
                case (0, 1): adjustment = 1 + home * dixonColesRho
                case (1, 0): adjustment = 1 + away * dixonColesRho
                case (1, 1): adjustment = 1 - dixonColesRho
                default: break
                }
                let value = max(
                    0,
                    homeProbabilities[homeGoals] * awayProbabilities[awayGoals] * adjustment
                )
                total += value
                let difference = homeGoals + handicap - awayGoals
                result[difference > 0 ? 0 : (difference == 0 ? 1 : 2)] += value
            }
        }
        guard total > 0 else { return [] }
        return result.map { $0 / total }
    }

    private static func poissonProbabilities(lambda: Double) -> [Double] {
        var result = Array(repeating: 0.0, count: maximumGoals + 1)
        result[0] = exp(-lambda)
        for goals in 1...maximumGoals {
            result[goals] = result[goals - 1] * lambda / Double(goals)
        }
        return result
    }
}

enum HandicapOddsComparisonTableMatrix {
    static func rows(
        matchNumbers: [String],
        matches: [BeijingSingleMatch]
    ) -> [[Double]]? {
        let byNumber = Dictionary(uniqueKeysWithValues: matches.compactMap { match in
            Int(match.matchNumber).map { ($0, match) }
        })
        let selected = matchNumbers.compactMap { value -> [Double]? in
            guard let number = Int(value), let match = byNumber[number],
                  let handicap = match.handicap,
                  let converted = HandicapOddsComparisonTable.convertedOdds(
                    ordinaryOdds: match.marketOdds,
                    handicap: handicap
                  ) else {
                return nil
            }
            return converted
        }
        return selected.count == matchNumbers.count ? selected : nil
    }

    static func missingMatchNumbers(
        matchNumbers: [String],
        matches: [BeijingSingleMatch]
    ) -> [String] {
        let byNumber = Dictionary(uniqueKeysWithValues: matches.compactMap { match in
            Int(match.matchNumber).map { ($0, match) }
        })
        return matchNumbers.filter { value in
            guard let number = Int(value), let match = byNumber[number] else { return true }
            guard let handicap = match.handicap else { return true }
            return HandicapOddsComparisonTable.convertedOdds(
                ordinaryOdds: match.marketOdds,
                handicap: handicap
            ) == nil
        }
    }

    /// 使用“普通胜/平/负欧赔＋实际让球＋项目对照表”一次生成完整ABCD。
    /// ABCD不依赖Poisson展示模型，避免某一场展示分析失败时把已经完整的
    /// 六场对照表数据一并判成不可用。
    static func logic(
        matchNumbers: [String],
        matches: [BeijingSingleMatch]
    ) -> String? {
        guard let convertedRows = rows(matchNumbers: matchNumbers, matches: matches) else {
            return nil
        }
        let mappings = convertedRows.compactMap(LogicMapping.derivedFromComparisonTableOdds)
        guard mappings.count == matchNumbers.count else { return nil }
        return mappings.map(\.displayName).joined()
    }
}

struct VIP1SevenLeg: Codable, Equatable, Sendable {
    let number: Int
    let home: String
    let away: String
    let matchTime: String
    let options: [Int]
    let customOdds: [Double]
    let coverageProbability: Double
    /// Probability mass outside the most likely custom-odds outcome.
    var upsetProbability: Double {
        guard customOdds.count==3, customOdds.allSatisfy({$0.isFinite && $0>0}) else { return 0 }
        let inverse=customOdds.map{1/$0},total=inverse.reduce(0,+)
        return total.isFinite && total>0 ? 1-(inverse.max()! / total) : 0
    }
    var kind: String { options.count == 1 ? "单选" : (options.count == 2 ? "双选" : "全包") }
    var outcomeText: String { options.map { $0 == 3 ? "胜" : ($0 == 1 ? "平" : "负") }.joined(separator: "/") }
}

struct VIP1SevenSelection: Codable, Equatable, Sendable {
    let issue: String
    let start: Int
    let end: Int
    let legs: [VIP1SevenLeg]
    func missReasons(outcomes: [Int]) -> [String] {
        guard outcomes.count == legs.count else { return [] }
        func label(_ value: Int) -> String { value == 3 ? "胜(3)" : (value == 1 ? "平(1)" : "负(0)") }
        return zip(legs,outcomes).enumerated().compactMap { index,pair in
            let (leg,actual)=pair
            guard !leg.options.contains(actual) else { return nil }
            return "第\(index+1)场／场次\(leg.number) · \(leg.home) vs \(leg.away)：\(leg.kind)选\(leg.options.map(label).joined(separator:"/"))，实际让球赛果为\(label(actual))，未覆盖。"
        }
    }
    var betCount: Int { legs.reduce(1) { $0 * $1.options.count } }
    var jointCoverageProbability: Double { legs.reduce(1) { $0 * $1.coverageProbability } }
    /// VIP1 and VIP2 both export E/F. Split the first double-selection leg so
    /// both rows are non-empty, disjoint, and together cover every original bet.
    var txtPartitions: [VIP1SevenTXTPartition] {
        let doubleIndices = legs.indices.filter { legs[$0].options.count == 2 }
        guard (1...2).contains(doubleIndices.count),
              legs.allSatisfy({ (1...3).contains($0.options.count) }),
              let splitIndex = doubleIndices.first else {
            return [VIP1SevenTXTPartition(label: nil, options: legs.map(\.options))]
        }
        let splitOptions = legs[splitIndex].options
        var eOptions = legs.map(\.options)
        var fOptions = eOptions
        eOptions[splitIndex] = [splitOptions[0]]
        fOptions[splitIndex] = [splitOptions[1]]
        return [
            VIP1SevenTXTPartition(label: "E", options: eOptions),
            VIP1SevenTXTPartition(label: "F", options: fOptions)
        ]
    }
    var txtRow: String {
        CompressedRecord(options: legs.map(\.options), sourceRecords: []).labeledNotation(matchNumbers: legs.map { String($0.number) })
    }
    func txt(multiplier: Int) -> String {
        let doubles = legs.filter { $0.options.count == 2 }.count
        let singles = legs.filter { $0.options.count == 1 }.count
        let version = singles == 1 ? 1 : 2
        let rows = txtPartitions.enumerated().map { index, partition in
            let row = CompressedRecord(options: partition.options, sourceRecords: [])
                .labeledNotation(matchNumbers: legs.map { String($0.number) })
            let prefix = partition.label.map { "\($0)：" } ?? String(format: "%02d. ", index + 1)
            return "\(prefix)\(row)"
        }
        return (["北单第\(issue)期 · VIP\(version)", "范围：\(start)–\(end)；六场方案", "口径：项目自定义让球胜/平/负赔率倒数归一化，不读取实际赛果", "结构：\(singles)单选＋\(doubles)双选＋4场全包；\(betCount)注；TXT\(txtPartitions.count)行；\(multiplier)倍", "总金额：\(betCount * 2 * multiplier)元", "估计覆盖概率：\(String(format: "%.2f", jointCoverageProbability * 100))%（独立假设，非历史命中率）"] + rows).joined(separator: "\n")
    }
}

struct VIP1SevenTXTPartition: Equatable, Sendable {
    let label: String?
    let options: [[Int]]
    var betCount: Int { options.reduce(1) { $0 * $1.count } }
}

enum VIP1SevenSelectionError: LocalizedError {
    case invalidRange, missingEndpoint(Int), insufficientInterior(Int), mixedIssues, noEligibleSingle
    var errorDescription: String? {
        switch self {
        case .invalidRange: return "请输入有效的起点和终点，终点须大于起点。"
        case .missingEndpoint(let n): return "第\(n)场缺少完整普通三项欧赔或实际让球，无法计算自定义赔率。"
        case .insufficientInterior(let n): return "范围内只有\(n)场自定义赔率完整的比赛，至少需要6场。"
        case .mixedIssues: return "候选场次期号不一致，请刷新本期数据。"
        case .noEligibleSingle: return "范围内没有自定义赔率不低于2.00的可用单选方向。"
        }
    }
}

enum VIP1SevenMatchSelector {
    static let minimumSingleCustomOdds = 2.0

    static func eligibleSingleIndex(customOdds: [Double], probabilities: [Double]) -> Int? {
        guard customOdds.count == probabilities.count else { return nil }
        return customOdds.indices
            .filter { customOdds[$0].isFinite && customOdds[$0] >= minimumSingleCustomOdds }
            .max { lhs, rhs in
                let difference = probabilities[lhs] - probabilities[rhs]
                return abs(difference) > 1e-14 ? difference < 0 : lhs > rhs
            }
    }

    /// Prefer matches with an actual non-zero handicap for VIP1's single leg.
    /// Fall back to level-ball matches only when the range has no eligible
    /// handicap match, so generation does not fail unnecessarily.
    static func preferredSingleCandidateIndices(
        handicaps: [Int],
        hasEligibleDirection: [Bool]
    ) -> [Int] {
        guard handicaps.count == hasEligibleDirection.count else { return [] }
        let eligible = hasEligibleDirection.indices.filter { hasEligibleDirection[$0] }
        let handicapEligible = eligible.filter { handicaps[$0] != 0 }
        return handicapEligible.isEmpty ? eligible : handicapEligible
    }

    /// Select one or two distinct double legs using only custom odds; fill to six.
    static func select(start: Int, end: Int, matches: [BeijingSingleMatch], doubleCount: Int = 1) throws -> VIP1SevenSelection {
        guard start > 0, end > start, (1...2).contains(doubleCount) else { throw VIP1SevenSelectionError.invalidRange }
        struct Profile { let match: BeijingSingleMatch; let number: Int; let handicap: Int; let odds: [Double]; let p: [Double]; let indices: [Int]; let singleIndex: Int?
            var coverage: Double { indices.reduce(0) { $0+p[$1] } }
        }
        let profiles: [Profile] = matches.compactMap { match in
            guard let n=Int(match.matchNumber), (start...end).contains(n), let handicap=match.handicap,
                  let odds=HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: match.marketOdds, handicap: handicap),
                  odds.count==3, odds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
            let inverse=odds.map { 1 / $0 }; let total=inverse.reduce(0,+)
            guard total.isFinite, total>0 else { return nil }
            let p=inverse.map{$0/total}
            let indices=Array((0..<3).sorted { a,b in abs(p[a]-p[b])>1e-14 ? p[a]>p[b] : a<b }.prefix(2))
            let singleIndex=eligibleSingleIndex(customOdds: odds, probabilities: p)
            return Profile(match:match.resultBlindCopy,number:n,handicap:handicap,odds:odds,p:p,indices:indices,singleIndex:singleIndex)
        }.sorted { $0.number < $1.number }
        let unique=Dictionary(profiles.map{($0.number,$0)},uniquingKeysWith:{first,_ in first}).values.sorted{$0.number<$1.number}
        guard unique.count>=6 else { throw VIP1SevenSelectionError.insufficientInterior(unique.count) }
        guard Set(unique.map{$0.match.issue}).count==1 else { throw VIP1SevenSelectionError.mixedIssues }
        var doubleNumbers=Set<Int>()
        var singleNumber: Int?
        if doubleCount == 1 {
            var best = -Double.infinity
            let candidateIndices = preferredSingleCandidateIndices(
                handicaps: unique.map(\.handicap),
                hasEligibleDirection: unique.map { $0.singleIndex != nil }
            )
            for candidateIndex in candidateIndices {
                let single=unique[candidateIndex]
                guard let singleIndex=single.singleIndex else { continue }
                for dual in unique where dual.number != single.number {
                    let mass=single.p[singleIndex] * dual.coverage
                    if mass > best + 1e-14 {
                        best=mass; singleNumber=single.number; doubleNumbers=[dual.number]
                    }
                }
            }
            guard singleNumber != nil else { throw VIP1SevenSelectionError.noEligibleSingle }
        } else {
            doubleNumbers=Set(unique.sorted { a,b in abs(a.coverage-b.coverage)>1e-14 ? a.coverage>b.coverage : a.number<b.number }.prefix(2).map(\.number))
        }
        let chosen=unique.filter{doubleNumbers.contains($0.number) || $0.number==singleNumber}
        let fullCandidates=unique.filter{!doubleNumbers.contains($0.number) && $0.number != singleNumber}.sorted { a,b in
            let x=1-a.p.max()!, y=1-b.p.max()!
            return abs(x-y)>1e-14 ? x>y : a.number<b.number
        }
        let selected=(chosen+fullCandidates.prefix(4)).sorted{$0.number<$1.number}
        let order=[3,1,0]
        let legs=selected.map { p -> VIP1SevenLeg in
            let indices: [Int]
            if p.number==singleNumber { indices=[p.singleIndex!] }
            else { indices=doubleNumbers.contains(p.number) ? p.indices : [0,1,2] }
            return VIP1SevenLeg(number:p.number,home:p.match.homeTeam,away:p.match.awayTeam,matchTime:p.match.matchTime,
                options:order.enumerated().filter{indices.contains($0.offset)}.map(\.element),customOdds:p.odds,coverageProbability:indices.reduce(0){$0+p.p[$1]})
        }
        return VIP1SevenSelection(issue:unique[0].match.issue,start:start,end:end,legs:legs)
    }
}

struct VIP6MatchRecommendation: Equatable, Sendable {
    let mainMatchNumbers: [Int]
    let mCoverageProbability: Double
    let logic: String
    let noFourPosition: Int
    let noFourProbability: Double
    let secondLowestNoFourPosition: Int
    let secondLowestNoFourProbability: Double
    let outsideFirstMatchDayCount: Int
    var automaticDoubleSelection: AutomaticDoubleSelection? = nil

    var sixthMatchNumber: Int { mainMatchNumbers.last ?? 0 }
}

/// VIP6自动选场：用户只给第一场，后续场次使用项目换算后的真实让球赔率。
/// M=4–8仍保持工程既有定义；真实赔率只负责给每种赛果赋权，绝不按期号、
/// 场次号或历史赛果建立白名单。
enum VIP6MatchRecommender {
    enum ABCDSelectionError: LocalizedError {
        case invalidFirst(Int)
        case notFound
        case frontTwoADNotFound
        case directionalPairNotFound
        case adPairWithinSixNotFound
        case adSingleWithinSixNotFound

        var errorDescription: String? {
            switch self {
            case .invalidFirst(let number):
                return "首场第\(number)场缺少完整普通欧赔或实际让球，或与第7场重复，请核对后重试。"
            case .frontTwoADNotFound:
                return "输入编号之后找不到两场A/D并保留足够的后续场次组成六场，请调整起始编号或补齐赔率。"
            case .directionalPairNotFound:
                return "没有找到两场明确胜负倾向且后面有连续四场完整赔率的组合，请调整起点或补齐赔率。"
            case .adSingleWithinSixNotFound:
                return "从起点顺延后仍未找到一场A/D，请调整起点或补齐赔率；第7场不参与。"
            case .adPairWithinSixNotFound:
                return "已从输入起点向后查找完整赔率场次，仍找不到至少含两场A/D的六场，请调整起点或补齐赔率。"
            case .notFound:
                return "本期首场之后的有效候选不足六场，或缺少A、B、C、D中的类型，无法补齐六场ABCD。"
            }
        }
    }

    static func allABCDMatchNumbers(firstMatchNumber: Int, matches: [BeijingSingleMatch],
                                    excludingMatchNumbers: Set<Int> = []) throws -> [Int] {
        try selectMatchNumbers(firstMatchNumber: firstMatchNumber, matches: matches,
            excludingMatchNumbers: excludingMatchNumbers, requireAllABCD: true, requireFrontTwoAD: false)
    }

    struct ADSelectionFixture: Sendable {
        let number: Int
        let logic: LogicMapping
    }

    /// 真机选场与历史回测共用；只看类型，不接触赛果。
    static func fillingADMatchNumbers<S: Sequence>(initial: [ADSelectionFixture], later: S, requiredCount: Int = 2) throws -> [Int]
        where S.Element == ADSelectionFixture {
        let failure: ABCDSelectionError = requiredCount == 1 ? .adSingleWithinSixNotFound : .adPairWithinSixNotFound
        guard (1...2).contains(requiredCount), initial.count == 6, Set(initial.map(\.number)).count == 6,
              initial.map(\.number) == initial.map(\.number).sorted() else {
            throw failure
        }
        var selected = initial
        func enough() -> Bool { selected.filter { $0.logic == .a || $0.logic == .d }.count >= requiredCount }
        if enough() { return selected.map(\.number) }
        var seen = Set(initial.map(\.number))
        for candidate in later {
            try Task.checkCancellation()
            guard candidate.number > initial.last!.number, seen.insert(candidate.number).inserted,
                  candidate.logic == .a || candidate.logic == .d else { continue }
            guard let replace = selected.indices.dropFirst().last(where: {
                selected[$0].logic == .b || selected[$0].logic == .c
            }) else { throw failure }
            selected[replace] = candidate
            selected.sort { $0.number < $1.number }
            if enough() { return selected.map(\.number) }
        }
        throw failure
    }

    /// 从输入编号向后找；开启前两场A/D时允许移动首场，且补齐ABCD不得替换这两个位置。
    /// 只使用完整对照表输入，排除第七场，不读取赛果。
    static func selectMatchNumbers(firstMatchNumber: Int, matches: [BeijingSingleMatch],
                                   excludingMatchNumbers: Set<Int> = [], requireAllABCD: Bool,
                                   requireFrontTwoAD: Bool, fixedFrontTwoDoubles: Bool = false,
                                   calibrated: Bool = true, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2) throws -> [Int] {
        if adDoublesWithinSix {
            // 保留起点和已有A/D；不足两场时顺延，用新A/D替换靠后的B/C。
            let numbers: [Int]
            do {
                numbers = try selectMatchNumbers(firstMatchNumber: firstMatchNumber, matches: matches,
                    excludingMatchNumbers: excludingMatchNumbers, requireAllABCD: false, requireFrontTwoAD: false)
            } catch ABCDSelectionError.notFound {
                throw adDoubleCountWithinSix == 1 ? ABCDSelectionError.adSingleWithinSixNotFound : .adPairWithinSixNotFound
            }
            let selected = numbers.compactMap { number in
                matches.lazy.filter { Int($0.matchNumber) == number }.compactMap(profile).first
            }
            let lastInitial = numbers.last!
            let later = matches.enumerated().filter {
                guard let number = Int($0.element.matchNumber) else { return false }
                return number > lastInitial && !excludingMatchNumbers.contains(number)
            }.sorted {
                let left = Int($0.element.matchNumber)!, right = Int($1.element.matchNumber)!
                return left == right ? $0.offset < $1.offset : left < right
            }.map(\.element)
            return try fillingADMatchNumbers(initial: selected.map { ADSelectionFixture(number: $0.number, logic: $0.logic) },
                later: later.lazy.compactMap { match in
                    profile(match).map { ADSelectionFixture(number: $0.number, logic: $0.logic) }
                }, requiredCount: adDoubleCountWithinSix)
        }
        if fixedFrontTwoDoubles {
            return try directionalMatchNumbers(firstMatchNumber: firstMatchNumber, matches: matches,
                excluding: excludingMatchNumbers, calibrated: calibrated, requireFrontTwoAD: requireFrontTwoAD)
        }
        guard firstMatchNumber > 0 else { throw ABCDSelectionError.invalidFirst(firstMatchNumber) }
        // 先筛选场号再换算；按顺序惰性读取，凑齐规则后不再拟合整期其他比赛。
        let ordered = matches.enumerated().filter {
            guard let number = Int($0.element.matchNumber) else { return false }
            return number >= firstMatchNumber && !excludingMatchNumbers.contains(number)
        }.sorted {
            let left = Int($0.element.matchNumber)!, right = Int($1.element.matchNumber)!
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        var iterator = ordered.makeIterator()
        var seen: Set<Int> = []
        func nextProfile() throws -> Profile? {
            while let match = iterator.next() {
                try Task.checkCancellation()
                guard let candidate = profile(match), seen.insert(candidate.number).inserted else { continue }
                return candidate
            }
            return nil
        }
        var selected: [Profile]
        let locked: Int
        if requireFrontTwoAD {
            var front: [Profile] = []
            while front.count < 2, let candidate = try nextProfile() {
                if candidate.logic == .a || candidate.logic == .d { front.append(candidate) }
            }
            guard front.count == 2 else { throw ABCDSelectionError.frontTwoADNotFound }
            selected = front
            while selected.count < 6, let candidate = try nextProfile() { selected.append(candidate) }
            guard selected.count == 6 else { throw ABCDSelectionError.frontTwoADNotFound }
            locked = 2
        } else {
            guard let first = try nextProfile(), first.number == firstMatchNumber else { throw ABCDSelectionError.invalidFirst(firstMatchNumber) }
            selected = [first]
            while selected.count < 6, let candidate = try nextProfile() { selected.append(candidate) }
            guard selected.count == 6 else { throw ABCDSelectionError.notFound }
            locked = 1
        }
        if !requireAllABCD { return selected.map(\.number) }
        while Set(selected.map(\.logic)).count < LogicMapping.allCases.count,
              let candidate = try nextProfile() {
            let types = Set(selected.map(\.logic))
            if types.contains(candidate.logic) { continue }
            let counts = Dictionary(grouping: selected, by: \.logic).mapValues(\.count)
            guard let replace = selected.indices.dropFirst(locked).last(where: {
                counts[selected[$0].logic, default: 0] > 1
            }) else { throw ABCDSelectionError.notFound }
            selected[replace] = candidate
            selected.sort { $0.number < $1.number }
        }
        guard Set(selected.map(\.logic)) == Set(LogicMapping.allCases) else { throw ABCDSelectionError.notFound }
        return selected.map(\.number)
    }

    /// 从输入起点按场号顺延，取最先符合胜负倾向的两场，再取最近连续四场。
    /// 不限制ABCD，不读赛果；胜/负主选需高于平与反方向，不跨全期比较强弱。
    static func directionalMatchNumbers(firstMatchNumber: Int, matches: [BeijingSingleMatch],
                                        excluding: Set<Int> = [], calibrated: Bool, requireFrontTwoAD: Bool = false) throws -> [Int] {
        guard firstMatchNumber > 0 else { throw ABCDSelectionError.invalidFirst(firstMatchNumber) }
        var candidates: [Int: AutomaticDoubleCandidate] = [:]
        for match in matches {
            try Task.checkCancellation()
            guard let number = Int(match.matchNumber), number >= firstMatchNumber, !excluding.contains(number),
                  candidates[number] == nil, let handicap = match.handicap,
                  let odds = HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: match.marketOdds, handicap: handicap),
                  let logic = LogicMapping.derivedFromComparisonTableOdds(odds) else { continue }
            candidates[number] = AutomaticDoubleCandidate(number: number, logic: logic, odds: odds)
        }
        let numbers = candidates.keys.sorted()
        let available = Set(numbers)
        let blocks = numbers.filter { start in
            start <= Int.max - 3 && (start...(start + 3)).allSatisfy(available.contains)
        }
        var first: Int?
        for number in numbers {
            try Task.checkCancellation()
            guard let candidate = candidates[number] else { continue }
            if requireFrontTwoAD {
                guard candidate.logic == .a || candidate.logic == .d else { continue }
            } else {
                guard let p = AutomaticDoubleSelector.probabilities(odds: candidate.odds, calibrated: calibrated) else { continue }
                let primary = max(p[0], p[2]), opposite = min(p[0], p[2])
                guard primary > p[1], primary > opposite else { continue }
            }
            guard let selectedFirst = first else { first = number; continue }
            guard let tail = blocks.first(where: { $0 > number }) else { break }
            return [selectedFirst, number] + Array(tail...(tail + 3))
        }
        throw ABCDSelectionError.directionalPairNotFound
    }

    private struct Profile: Sendable {
        let number: Int
        let distribution: [Double] // 下标0/1/2分别对应M判定值2/3/4
        let balance: Double
        let logic: LogicMapping
        let dayKey: String?
    }

    private struct Candidate {
        var indices: [Int]
        var score: Double
        var outsideFirstMatchDayCount: Int
    }

    private struct DeterministicGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    /// Exact probability under independent, normalized inverse-custom-odds outcomes.
    /// Five fixtures have four boundaries, so requested 3–5 is exactly 3–4.
    static func frontFiveBreakpointProbability(_ probabilities: [[Double]], range: ClosedRange<Int> = 2...4) -> Double {
        guard range.lowerBound >= 0, range.upperBound <= 4, probabilities.count == 5,
              probabilities.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 >= 0 } && abs($0.reduce(0, +) - 1) < 1e-8 }) else { return 0 }
        var state = Array(repeating: 0.0, count: 15)
        for o in 0..<3 { state[o] = probabilities[0][o] }
        for row in probabilities.dropFirst() {
            var next = Array(repeating: 0.0, count: 15)
            for breaks in 0...4 {
                for previous in 0..<3 where state[breaks * 3 + previous] > 0 {
                    for outcome in 0..<3 {
                        let updated = breaks + (previous == outcome ? 0 : 1)
                        if updated <= 4 { next[updated * 3 + outcome] += state[breaks * 3 + previous] * row[outcome] }
                    }
                }
            }
            state = next
        }
        return range.reduce(0.0) { total, count in total + state[(count * 3)..<(count * 3 + 3)].reduce(0, +) }
    }

    /// Exhaustive for <=24 later profiles; bounded beam + coordinate improvement for larger pools.
    /// First fixture stays anchored, ordering stays numeric, sixth is the next valid fixture.
    /// No outcomes/scores/status/settled SP enter this search.
    static func recommendFrontFiveBreakpoints(firstMatchNumber: Int, matches: [BeijingSingleMatch], excludingMatchNumbers: Set<Int> = [], breakpointRange: ClosedRange<Int> = 2...4) -> VIP6MatchRecommendation? {
        let profiles = Dictionary(matches.compactMap(profile).filter { !excludingMatchNumbers.contains($0.number) }.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.number < $1.number }
        guard let firstIndex = profiles.firstIndex(where: { $0.number == firstMatchNumber }) else { return nil }
        let pool = Array(profiles[firstIndex...])
        guard pool.count >= 6 else { return nil }
        // Convert mapped2/3/4 probabilities back to actual win/draw/loss before counting breaks.
        let probabilities = pool.map { p in [3, 1, 0].map { p.distribution[p.logic.value(for: $0) - 2] } }
        func score(_ indices: [Int]) -> Double {
            var rows = indices.map { probabilities[$0] }
            while rows.count < 5 { rows.append([1.0 / 3, 1.0 / 3, 1.0 / 3]) }
            return frontFiveBreakpointProbability(rows, range: breakpointRange)
        }
        struct Trial { let indices: [Int]; let score: Double }
        func better(_ a: Trial, _ b: Trial) -> Bool {
            if abs(a.score - b.score) > 1e-14 { return a.score > b.score }
            return a.indices.lexicographicallyPrecedes(b.indices)
        }
        var best = Trial(indices: [0, 1, 2, 3, 4], score: score([0, 1, 2, 3, 4]))
        if pool.count <= 25 {
            for a in 1..<(pool.count - 4) {
                for b in (a + 1)..<(pool.count - 3) {
                    for c in (b + 1)..<(pool.count - 2) {
                        for d in (c + 1)..<(pool.count - 1) {
                            let indices = [0, a, b, c, d]
                            let trial = Trial(indices: indices, score: score(indices))
                            if better(trial, best) { best = trial }
                        }
                    }
                }
            }
        } else {
            var beam = [Trial(indices: [0], score: score([0]))]
            for length in 2...5 {
                if Task.isCancelled { return nil }
                var next: [Trial] = []
                for trial in beam {
                    let lower = trial.indices.last! + 1
                    let upper = pool.count - 1 - (6 - length)
                    if lower > upper { continue }
                    for index in lower...upper {
                        let indices = trial.indices + [index]
                        next.append(Trial(indices: indices, score: score(indices)))
                    }
                }
                next.sort(by: better)
                beam = Array(next.prefix(96))
            }
            for seed in beam.prefix(16) {
                var current = seed
                for _ in 0..<3 {
                    if Task.isCancelled { return nil }
                    var changed = false
                    for position in 1...4 {
                        let lower = current.indices[position - 1] + 1
                        let upper = position == 4 ? pool.count - 2 : current.indices[position + 1] - 1
                        var improved = current
                        for index in lower...upper {
                            var indices = current.indices; indices[position] = index
                            let trial = Trial(indices: indices, score: score(indices))
                            if better(trial, improved) { improved = trial }
                        }
                        if improved.indices != current.indices { changed = true; current = improved }
                    }
                    if !changed { break }
                }
                if better(current, best) { best = current }
            }
        }
        let selected = (best.indices + [best.indices.last! + 1]).map { pool[$0] }
        let ranked = selected.enumerated().sorted {
            if abs($0.element.distribution[2] - $1.element.distribution[2]) > 1e-14 {
                return $0.element.distribution[2] < $1.element.distribution[2]
            }
            return $0.offset < $1.offset
        }
        return VIP6MatchRecommendation(mainMatchNumbers: selected.map(\.number), mCoverageProbability: best.score,
            logic: selected.map { $0.logic.displayName }.joined(), noFourPosition: ranked[0].offset + 1,
            noFourProbability: ranked[0].element.distribution[2], secondLowestNoFourPosition: ranked[1].offset + 1,
            secondLowestNoFourProbability: ranked[1].element.distribution[2],
            outsideFirstMatchDayCount: selected.dropFirst().filter { $0.dayKey != selected[0].dayKey }.count)
    }

    /// 首页连续选场：用户输入第一场后，固定使用该场与后续5个连续场次。
    /// 赛前概率只用于计算M覆盖率与“默认不为4”位置，不再用于替换场次。
    static func recommendAutomaticDoubles(firstMatchNumber: Int, matches: [BeijingSingleMatch],
                                         excludingMatchNumbers: Set<Int> = [], calibrated: Bool,
                                         factors: Set<DoubleJudgmentFactor> = [], evidence: [DoubleMarketEvidence] = [], matchNumbers: [Int]? = nil,
                                         fixedFrontTwo: Bool = false, requireFrontTwoAD: Bool = false, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> VIP6MatchRecommendation? {
        let requested = matchNumbers ?? Array(firstMatchNumber..<(firstMatchNumber + 6))
        let requestedSet = Set(requested)
        let verified = factors.isEmpty ? [] : DoubleMarketDataClient.verifiedEvidence(evidence, matches: matches, matchNumbers: requested)
        let quoted = DoubleMarketDataClient.applyingVerifiedQuotes(verified, to: matches)
        let candidates = quoted.compactMap { match -> AutomaticDoubleCandidate? in
            let blind = match.resultBlindCopy
            guard let number = Int(blind.matchNumber), requestedSet.contains(number), let handicap = blind.handicap,
                  let odds = HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: blind.marketOdds, handicap: handicap),
                  let logic = LogicMapping.derivedFromComparisonTableOdds(odds) else { return nil }
            return AutomaticDoubleCandidate(number: number, logic: logic, odds: odds,
                evidence: verified.first { $0.number == number && $0.issue == blind.issue && $0.fixtureID == blind.fixtureID && $0.handicap == handicap
                    && DoubleMarketDataClient.kickoff(issue: blind.issue, matchTime: blind.matchTime) == $0.kickoff })
        }
        guard let selected = AutomaticDoubleSelector.recommend(numbers: requested, candidates: candidates,
            excluding: excludingMatchNumbers, calibrated: calibrated, factors: factors, fixedFrontTwo: fixedFrontTwo,
            requireFrontTwoAD: requireFrontTwoAD, adDoublesWithinSix: adDoublesWithinSix, adDoubleCountWithinSix: adDoubleCountWithinSix, automaticDoubleCount: automaticDoubleCount) else { return nil }
        return VIP6MatchRecommendation(mainMatchNumbers: selected.matches.map(\.number), mCoverageProbability: 0,
            logic: selected.matches.map { $0.logic.displayName }.joined(), noFourPosition: 1, noFourProbability: 0,
            secondLowestNoFourPosition: 2, secondLowestNoFourProbability: 0, outsideFirstMatchDayCount: 0,
            automaticDoubleSelection: selected)
    }

    static func recommendConsecutive(
        firstMatchNumber: Int,
        matches: [BeijingSingleMatch],
        displacementMatchCount: Int = 6,
        displacementRange: ClosedRange<Int> = 4...8
    ) -> VIP6MatchRecommendation? {
        guard firstMatchNumber > 0, firstMatchNumber <= Int.max - 6 else { return nil }
        return recommendMatches(numbers: Array(firstMatchNumber..<(firstMatchNumber + 6)), matches: matches,
            displacementMatchCount: displacementMatchCount, displacementRange: displacementRange)
    }

    static func recommendMatches(numbers requestedNumbers: [Int], matches: [BeijingSingleMatch],
                                 displacementMatchCount: Int = 6, displacementRange: ClosedRange<Int> = 4...8) -> VIP6MatchRecommendation? {
        guard requestedNumbers.count == 6, Set(requestedNumbers).count == 6,
              requestedNumbers.allSatisfy({ $0 > 0 }), requestedNumbers == requestedNumbers.sorted() else { return nil }
        let requestedSet = Set(requestedNumbers)
        let byNumber = Dictionary(matches.filter {
            Int($0.matchNumber).map(requestedSet.contains) == true
        }.compactMap(profile).map { ($0.number, $0) },
            uniquingKeysWith: { first, _ in first })
        let main = requestedNumbers.compactMap { byNumber[$0] }
        guard main.count == 6, main.map(\.number) == requestedNumbers else { return nil }

        let noFourCandidates = main.prefix(min(displacementMatchCount, main.count)).enumerated()
        guard let noFour = noFourCandidates.min(by: { left, right in
            let leftProbability = left.element.distribution[2]
            let rightProbability = right.element.distribution[2]
            if abs(leftProbability - rightProbability) > 1e-15 {
                return leftProbability < rightProbability
            }
            return left.offset < right.offset
        }) else { return nil }
        let ascendingNoFourCandidates = noFourCandidates.sorted { left, right in
            let leftProbability = left.element.distribution[2]
            let rightProbability = right.element.distribution[2]
            if abs(leftProbability - rightProbability) > 1e-15 {
                return leftProbability < rightProbability
            }
            return left.offset < right.offset
        }
        guard ascendingNoFourCandidates.count >= 2 else { return nil }
        let secondLowestNoFour = ascendingNoFourCandidates[1]

        let firstDay = main[0].dayKey
        let outsideDayCount = firstDay.map { day in
            main.dropFirst().filter { $0.dayKey != day }.count
        } ?? 0
        return VIP6MatchRecommendation(
            mainMatchNumbers: requestedNumbers,
            mCoverageProbability: coverage(
                first: main[0],
                selected: Array(main.dropFirst()),
                matchCount: displacementMatchCount,
                range: displacementRange
            ),
            logic: main.map { $0.logic.displayName }.joined(),
            noFourPosition: noFour.offset + 1,
            noFourProbability: noFour.element.distribution[2],
            secondLowestNoFourPosition: secondLowestNoFour.offset + 1,
            secondLowestNoFourProbability: secondLowestNoFour.element.distribution[2],
            outsideFirstMatchDayCount: outsideDayCount
        )
    }

    static func recommend(
        firstMatchNumber: Int,
        matches: [BeijingSingleMatch]
    ) -> VIP6MatchRecommendation? {
        guard firstMatchNumber > 0 else { return nil }
        let profiles = matches.compactMap(profile).sorted { $0.number < $1.number }
        guard let first = profiles.first(where: { $0.number == firstMatchNumber }) else { return nil }
        let later = profiles.filter { $0.number > firstMatchNumber }
        // 第六场也是M的主计算场，因此第一场之后需要5场。
        guard later.count >= 5 else { return nil }

        var seeds: [Candidate] = []
        func retain(_ indices: [Int], in seeds: inout [Candidate]) {
            guard indices.count == 5,
                  Set(indices).count == 5,
                  indices == indices.sorted() else { return }
            let score = coverage(first: first, selected: indices.map { later[$0] })
            let outsideDayCount = first.dayKey.map { day in
                indices.filter { later[$0].dayKey != day }.count
            } ?? 0
            if seeds.contains(where: { $0.indices == indices }) { return }
            seeds.append(Candidate(
                indices: indices,
                score: score,
                outsideFirstMatchDayCount: outsideDayCount
            ))
            seeds.sort(by: isBetter)
            if seeds.count > 72 { seeds.removeLast(seeds.count - 72) }
        }

        // 赔率最均衡的场次全部交叉，给搜索一个稳定的高质量起点。
        let balanced = later.indices.sorted {
            if let firstDay = first.dayKey {
                let lhsSameDay = later[$0].dayKey == firstDay
                let rhsSameDay = later[$1].dayKey == firstDay
                if lhsSameDay != rhsSameDay { return lhsSameDay }
            }
            if abs(later[$0].balance - later[$1].balance) > 1e-15 {
                return later[$0].balance > later[$1].balance
            }
            return later[$0].number < later[$1].number
        }.prefix(min(13, later.count))
        let balancedIndices = Array(balanced).sorted()
        if balancedIndices.count >= 5 {
            for a in 0..<(balancedIndices.count - 4) {
                for b in (a + 1)..<(balancedIndices.count - 3) {
                    for c in (b + 1)..<(balancedIndices.count - 2) {
                        for d in (c + 1)..<(balancedIndices.count - 1) {
                            for e in (d + 1)..<balancedIndices.count {
                                retain(
                                    [balancedIndices[a], balancedIndices[b], balancedIndices[c], balancedIndices[d], balancedIndices[e]],
                                    in: &seeds
                                )
                            }
                        }
                    }
                }
            }
        }

        // 固定种子的全期抽样避免只看热门或只看连续场次；相同输入必得相同结果。
        var generator = DeterministicGenerator(
            state: UInt64(firstMatchNumber) &* 2_609_801 &+ UInt64(later.count)
        )
        let selectableCount = later.count
        for _ in 0..<30_000 {
            var picked = Set<Int>()
            while picked.count < 5 {
                picked.insert(Int(generator.next() % UInt64(selectableCount)))
            }
            retain(picked.sorted(), in: &seeds)
        }
        guard !seeds.isEmpty else { return nil }

        // 对每个高质量起点逐位置穷举替换，直到真实赔率覆盖率不再提高。
        var refined: [Candidate] = []
        for seed in seeds {
            var current = seed
            for _ in 0..<6 {
                var changed = false
                for position in 0..<5 {
                    let lower = position == 0 ? 0 : current.indices[position - 1] + 1
                    let upper = position == 4
                        ? later.count - 1
                        : current.indices[position + 1] - 1
                    guard lower <= upper else { continue }
                    var bestIndex = current.indices[position]
                    var bestScore = current.score
                    var bestOutsideDayCount = current.outsideFirstMatchDayCount
                    for index in lower...upper where !current.indices.contains(index) {
                        var trial = current.indices
                        trial[position] = index
                        let score = coverage(first: first, selected: trial.map { later[$0] })
                        let outsideDayCount = first.dayKey.map { day in
                            trial.filter { later[$0].dayKey != day }.count
                        } ?? 0
                        let candidate = Candidate(
                            indices: trial,
                            score: score,
                            outsideFirstMatchDayCount: outsideDayCount
                        )
                        let incumbent = Candidate(
                            indices: current.indices,
                            score: bestScore,
                            outsideFirstMatchDayCount: bestOutsideDayCount
                        )
                        if isBetter(candidate, incumbent) {
                            bestIndex = index
                            bestScore = score
                            bestOutsideDayCount = outsideDayCount
                        }
                    }
                    if bestIndex != current.indices[position] {
                        current.indices[position] = bestIndex
                        current.score = bestScore
                        current.outsideFirstMatchDayCount = bestOutsideDayCount
                        changed = true
                    }
                }
                if !changed { break }
            }
            refined.append(current)
        }
        guard let best = refined.sorted(by: isBetter).first else { return nil }

        let selected = best.indices.map { later[$0] }
        let main = [first] + selected
        guard let noFour = main.enumerated().min(by: { left, right in
            let leftProbability = left.element.distribution[2]
            let rightProbability = right.element.distribution[2]
            if abs(leftProbability - rightProbability) > 1e-15 {
                return leftProbability < rightProbability
            }
            return left.offset < right.offset
        }) else { return nil }
        let ascendingNoFourCandidates = main.enumerated().sorted { left, right in
            let leftProbability = left.element.distribution[2]
            let rightProbability = right.element.distribution[2]
            if abs(leftProbability - rightProbability) > 1e-15 {
                return leftProbability < rightProbability
            }
            return left.offset < right.offset
        }
        guard ascendingNoFourCandidates.count >= 2 else { return nil }
        let secondLowestNoFour = ascendingNoFourCandidates[1]
        return VIP6MatchRecommendation(
            mainMatchNumbers: main.map(\.number),
            mCoverageProbability: best.score,
            logic: main.map { $0.logic.displayName }.joined(),
            noFourPosition: noFour.offset + 1,
            noFourProbability: noFour.element.distribution[2],
            secondLowestNoFourPosition: secondLowestNoFour.offset + 1,
            secondLowestNoFourProbability: secondLowestNoFour.element.distribution[2],
            outsideFirstMatchDayCount: best.outsideFirstMatchDayCount
        )
    }

    private static func profile(_ match: BeijingSingleMatch) -> Profile? {
        guard let number = Int(match.matchNumber),
              let handicap = match.handicap,
              let odds = HandicapOddsComparisonTable.convertedOdds(
                ordinaryOdds: match.marketOdds,
                handicap: handicap
              ),
              let logic = LogicMapping.derivedFromComparisonTableOdds(odds) else { return nil }
        let inverse = odds.map { 1 / $0 }
        let total = inverse.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        let probabilities = inverse.map { $0 / total }
        var distribution = Array(repeating: 0.0, count: 3)
        for (index, outcome) in [3, 1, 0].enumerated() {
            distribution[logic.value(for: outcome) - 2] += probabilities[index]
        }
        let entropy = -probabilities.reduce(0.0) { partial, probability in
            partial + probability * log(max(probability, 1e-15))
        } / log(3)
        return Profile(
            number: number,
            distribution: distribution,
            balance: entropy,
            logic: logic,
            dayKey: dayKey(match.matchTime)
        )
    }

    private static func dayKey(_ matchTime: String) -> String? {
        let prefix = String(matchTime.prefix(5))
        return prefix.range(of: #"^\d{2}-\d{2}$"#, options: .regularExpression) == nil
            ? nil
            : prefix
    }

    private static func isBetter(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.outsideFirstMatchDayCount != right.outsideFirstMatchDayCount {
            return left.outsideFirstMatchDayCount < right.outsideFirstMatchDayCount
        }
        if abs(left.score - right.score) > 1e-15 { return left.score > right.score }
        return lexicographicallyPrecedes(left.indices, right.indices)
    }

    private static func coverage(
        first: Profile,
        selected: [Profile],
        matchCount: Int = 6,
        range: ClosedRange<Int> = 4...8
    ) -> Double {
        let profiles = Array(([first] + selected).prefix(max(2, matchCount)))
        guard let firstProfile = profiles.first else { return 0 }
        var state = Array(repeating: 0.0, count: 27)
        for valueIndex in 0..<3 {
            state[valueIndex] = firstProfile.distribution[valueIndex]
        }
        for profile in profiles.dropFirst() {
            var next = Array(repeating: 0.0, count: 27)
            for displacement in 0...8 {
                for previousIndex in 0..<3 {
                    let probability = state[displacement * 3 + previousIndex]
                    guard probability > 0 else { continue }
                    for valueIndex in 0..<3 {
                        let newDisplacement = min(
                            8,
                            displacement + abs(valueIndex - previousIndex)
                        )
                        next[newDisplacement * 3 + valueIndex] +=
                            probability * profile.distribution[valueIndex]
                    }
                }
            }
            state = next
        }
        let validRange = max(0, range.lowerBound)...min(8, range.upperBound)
        return validRange.reduce(0.0) { total, displacement in
            total + state[(displacement * 3)..<(displacement * 3 + 3)].reduce(0, +)
        }
    }

    private static func lexicographicallyPrecedes(_ left: [Int], _ right: [Int]) -> Bool {
        for (lhs, rhs) in zip(left, right) where lhs != rhs { return lhs < rhs }
        return left.count < right.count
    }
}

struct PrizeRunSummary: Codable, Equatable, Sendable {
    let nonLoss: Int
    let nonWin: Int
    let nonDraw: Int
    let win: Int
    let draw: Int
    let loss: Int
    let winCount: Int
    let drawCount: Int
    let lossCount: Int
    let diversity: Int
    let outcomeSum: Int
    let returns: Int
    let winLossSwitches: Int

    init(
        nonLoss: Int,
        nonWin: Int,
        nonDraw: Int,
        win: Int = 0,
        draw: Int = 0,
        loss: Int = 0,
        winCount: Int = 0,
        drawCount: Int = 0,
        lossCount: Int = 0,
        diversity: Int = 0,
        outcomeSum: Int = 0,
        returns: Int = 0,
        winLossSwitches: Int = 0
    ) {
        self.nonLoss = nonLoss
        self.nonWin = nonWin
        self.nonDraw = nonDraw
        self.win = win
        self.draw = draw
        self.loss = loss
        self.winCount = winCount
        self.drawCount = drawCount
        self.lossCount = lossCount
        self.diversity = diversity
        self.outcomeSum = outcomeSum
        self.returns = returns
        self.winLossSwitches = winLossSwitches
    }

    private enum CodingKeys: String, CodingKey {
        case nonLoss, nonWin, nonDraw, win, draw, loss
        case winCount, drawCount, lossCount, diversity, outcomeSum, returns, winLossSwitches
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nonLoss = try values.decode(Int.self, forKey: .nonLoss)
        nonWin = try values.decode(Int.self, forKey: .nonWin)
        nonDraw = try values.decode(Int.self, forKey: .nonDraw)
        win = try values.decodeIfPresent(Int.self, forKey: .win) ?? 0
        draw = try values.decodeIfPresent(Int.self, forKey: .draw) ?? 0
        loss = try values.decodeIfPresent(Int.self, forKey: .loss) ?? 0
        winCount = try values.decodeIfPresent(Int.self, forKey: .winCount) ?? 0
        drawCount = try values.decodeIfPresent(Int.self, forKey: .drawCount) ?? 0
        lossCount = try values.decodeIfPresent(Int.self, forKey: .lossCount) ?? 0
        diversity = try values.decodeIfPresent(Int.self, forKey: .diversity) ?? 0
        outcomeSum = try values.decodeIfPresent(Int.self, forKey: .outcomeSum) ?? 0
        returns = try values.decodeIfPresent(Int.self, forKey: .returns) ?? 0
        winLossSwitches = try values.decodeIfPresent(Int.self, forKey: .winLossSwitches) ?? 0
    }
}

struct SeventhOutcomeEstimate: Codable, Equatable, Sendable {
    let outcome: Int
    let sp: Double
    let amount: Double
    let runSummary: PrizeRunSummary
}

struct SeventhOutcomeRunSummary: Codable, Equatable, Sendable {
    let outcome: Int
    let runSummary: PrizeRunSummary
}

enum PrizeCalculator {
    static func handicapSP(for match: BeijingSingleMatch) -> Double? {
        guard let outcome = match.handicapOutcome, match.referenceSP.count == 3 else { return nil }
        let index = outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)
        let value = match.referenceSP[index]
        return value > 0 && value.isFinite ? value : nil
    }

    static func selectedSP(for match: BeijingSingleMatch) -> Double? {
        if let settledSP = match.settledSP, settledSP > 0, settledSP.isFinite {
            return settledSP
        }
        return handicapSP(for: match)
    }

    static func selectedSP(for match: BeijingSingleMatch, replacingValuesAbove limit: Double) -> Double? {
        guard let original = selectedSP(for: match) else { return nil }
        if original > limit, let handicap = handicapSP(for: match) { return handicap }
        return original
    }

    static func amount(
        for matches: [BeijingSingleMatch],
        replacingValuesAbove limit: Double? = nil,
        treatingMatchNumbersAsUnit unitMatchNumbers: Set<String> = []
    ) -> Double? {
        guard (6...7).contains(matches.count) else { return nil }
        let values = matches.compactMap { match in
            if unitMatchNumbers.contains(match.matchNumber) { return 1.0 }
            if let limit { return selectedSP(for: match, replacingValuesAbove: limit) }
            return selectedSP(for: match)
        }
        guard values.count == matches.count else { return nil }
        return values.reduce(1.3, *)
    }

    static func isFullySettled(_ matches: [BeijingSingleMatch]) -> Bool {
        (6...7).contains(matches.count) && matches.allSatisfy {
            $0.settledSP.map { $0 > 0 && $0.isFinite } == true
        }
    }

    static func runSummary(for matches: [BeijingSingleMatch]) -> PrizeRunSummary? {
        guard (6...7).contains(matches.count) else { return nil }
        let outcomes = matches.compactMap(\.handicapOutcome)
        guard outcomes.count == matches.count else { return nil }
        return runSummary(for: outcomes)
    }

    /// 从已保存的彩果重建全部条件指标，用于兼容旧版查询记录。
    static func outcomeSummary(for outcomes: [Int]) -> PrizeRunSummary? {
        guard (6...7).contains(outcomes.count),
              outcomes.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return nil }
        return runSummary(for: outcomes)
    }

    static func seventhOutcomeEstimates(
        firstSix: [BeijingSingleMatch],
        seventh: BeijingSingleMatch,
        useHandicapSP: Bool,
        treatingFirstSixMatchNumbersAsUnit unitMatchNumbers: Set<String> = []
    ) -> [SeventhOutcomeEstimate]? {
        guard firstSix.count == 6 else { return nil }
        let firstSixValues = firstSix.compactMap { match in
            if unitMatchNumbers.contains(match.matchNumber) { return 1.0 }
            return selectedSP(for: match)
        }
        let firstSixOutcomes = firstSix.compactMap(\.handicapOutcome)
        guard firstSixValues.count == 6, firstSixOutcomes.count == 6 else { return nil }
        let seventhOdds = useHandicapSP ? seventh.referenceSP : seventh.marketOdds
        guard seventhOdds.count == 3,
              seventhOdds.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        let baseAmount = firstSixValues.reduce(1.3, *)
        return [(3, seventhOdds[0]), (0, seventhOdds[2])].map { outcome, sp in
            SeventhOutcomeEstimate(
                outcome: outcome,
                sp: sp,
                amount: baseAmount * sp,
                runSummary: runSummary(for: firstSixOutcomes + [outcome])
            )
        }
    }

    static func seventhOutcomeRunSummaries(firstSixOutcomes: [Int]) -> [SeventhOutcomeRunSummary]? {
        guard firstSixOutcomes.count == 6,
              firstSixOutcomes.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return nil }
        return [3, 0].map { outcome in
            SeventhOutcomeRunSummary(
                outcome: outcome,
                runSummary: runSummary(for: firstSixOutcomes + [outcome])
            )
        }
    }

    static func redLightConditionCount(for summary: PrizeRunSummary) -> Int {
        [
            summary.nonLoss >= 5,
            summary.nonWin >= 4,
            summary.nonDraw >= 4
        ].filter { $0 }.count
    }

    static func hasConsecutiveDrawPair(in outcomes: [Int]) -> Bool {
        zip(outcomes, outcomes.dropFirst()).contains { pair in
            pair.0 == 1 && pair.1 == 1
        }
    }

    static func sameResultRunsAtLeastTwoCount(in outcomes: [Int]) -> Int {
        guard let summary = outcomeSummary(for: outcomes) else { return 0 }
        return [summary.win, summary.draw, summary.loss].filter { $0 >= 2 }.count
    }

    /// 奖金模块爆红：连续3/1/0中至少两项长度≥2，且没有相邻11保护。
    static func shouldExplodeRed(for outcomes: [Int]) -> Bool {
        sameResultRunsAtLeastTwoCount(in: outcomes) >= 2
            && !hasConsecutiveDrawPair(in: outcomes)
    }

    private static func runSummary(for outcomes: [Int]) -> PrizeRunSummary {
        return PrizeRunSummary(
            nonLoss: ConsecutiveRunCondition.nonLoss.longestRun(in: outcomes),
            nonWin: ConsecutiveRunCondition.nonWin.longestRun(in: outcomes),
            nonDraw: ConsecutiveRunCondition.nonDraw.longestRun(in: outcomes),
            win: ConsecutiveRunCondition.win.longestRun(in: outcomes),
            draw: ConsecutiveRunCondition.draw.longestRun(in: outcomes),
            loss: ConsecutiveRunCondition.loss.longestRun(in: outcomes),
            winCount: OutcomeCondition.wins.value(in: outcomes),
            drawCount: OutcomeCondition.draws.value(in: outcomes),
            lossCount: OutcomeCondition.losses.value(in: outcomes),
            diversity: OutcomeCondition.diversity.value(in: outcomes),
            outcomeSum: OutcomeCondition.outcomeSum.value(in: outcomes),
            returns: OutcomeCondition.returns.value(in: outcomes),
            winLossSwitches: OutcomeCondition.winLossSwitches.value(in: outcomes)
        )
    }
}

struct ScoreProbability: Equatable, Sendable {
    let homeGoals: Int
    let awayGoals: Int
    let probability: Double

    var displayText: String {
        "\(homeGoals):\(awayGoals) \(String(format: "%.1f", probability * 100))%"
    }
}

struct GoalModelAnalysis: Identifiable, Equatable, Sendable {
    let match: BeijingSingleMatch
    let homeExpectedGoals: Double
    let awayExpectedGoals: Double
    let handicapProbabilities: [Double]
    let normalProbabilities: [Double]
    let overTwoPointFiveProbability: Double
    let bothTeamsScoreProbability: Double
    let topScores: [ScoreProbability]
    let recommendedLogic: LogicMapping
    let exactLogicPattern: Bool
    let fitError: Double

    var id: String { "\(match.issue)-\(match.matchNumber)" }

    /// 第三条宪法指定的让球赔率对照表结果。
    /// 仅使用完整普通欧赔＋实际让球数，不读取页面让球SP。
    var handicapFairOdds: [Double] {
        guard let handicap = match.handicap else { return [] }
        return HandicapOddsComparisonTable.convertedOdds(
            ordinaryOdds: match.marketOdds,
            handicap: handicap
        ) ?? []
    }

    /// 模型内部可靠度评分，不代表真实中奖概率。
    /// 由概率区分度、赔率拟合质量、数据完整度和ABCD映射精度共同构成。
    var confidenceIndex: Int {
        guard handicapProbabilities.count == 3 else { return 0 }
        let ordered = handicapProbabilities.sorted(by: >)
        let gap = ordered[0] - ordered[1]
        let separationScore = min(max(gap / 0.20, 0), 1)
        let fitScore = min(max(1 - sqrt(fitError / 0.02), 0), 1)
        let dataScore: Double
        if match.hasStarted {
            dataScore = 0.55
        } else {
            dataScore = match.marketOdds.count == 3 ? 1.0 : 0.65
        }
        let mappingScore = exactLogicPattern ? 1.0 : 0.5
        let weighted = separationScore * 0.40
            + fitScore * 0.30
            + dataScore * 0.20
            + mappingScore * 0.10
        return Int((weighted * 100).rounded())
    }

    var confidenceText: String {
        switch confidenceIndex {
        case 75...: return "较高"
        case 55..<75: return "中等"
        default: return "偏低"
        }
    }

    var confidenceReason: String {
        guard handicapProbabilities.count == 3 else { return "概率数据不完整" }
        let ordered = handicapProbabilities.sorted(by: >)
        let gapPoints = (ordered[0] - ordered[1]) * 100
        let dataDescription: String
        if match.hasStarted {
            dataDescription = "已开赛，比分与赛果已强制隔离，信心已降权"
        } else {
            dataDescription = match.marketOdds.count == 3 ? "完整市场欧赔" : "500参考SP"
        }
        let mappingDescription = exactLogicPattern ? "ABCD精确映射" : "ABCD近似映射"
        return "前两项概率差\(String(format: "%.1f", gapPoints))个百分点；拟合误差\(String(format: "%.5f", fitError))；\(dataDescription)；\(mappingDescription)"
    }

    var logicNote: String {
        exactLogicPattern
            ? "概率顺序与\(recommendedLogic.displayName)完全一致"
            : "平局概率最高，A–D没有完全对应项；采用最接近的\(recommendedLogic.displayName)"
    }
}

enum OddsConfidenceDecision: String, Equatable, Sendable {
    case bet = "适合投注"
    case observe = "只观察"
    case skip = "不投注"
}

/// 新一期的赛前赔率门槛。它只用项目让球赔率对照表生成的概率，
/// 不读取比分、赛果、期号特例或页面让球 SP。
struct OddsConfidenceRecommendation: Equatable, Sendable {
    let decision: OddsConfidenceDecision
    let matchNumber: String
    let outcome: Int
    let outcomeProbability: Double
    let runnerUpProbability: Double
    let probabilityGap: Double
    let modelConfidenceIndex: Int
    let breakEvenProbability: Double
    let bettingThreshold: Double
    let totalCost: Double
    let missReturn: Double
    let averageHitPayout: Double
    let explanation: String

    var topologyText: String { "1单＋5个三选（243注）" }
}

enum OddsConfidenceGate {
    /// 243注×2元＋200元防守成本。
    static let defaultTotalCost = 686.0
    static let defaultMissReturn = 200.0
    /// 26091–26098已中样本的平均命中奖金，仅作为V1经济门槛基线。
    static let defaultAverageHitPayout = 929.18
    static let minimumGreenThreshold = 0.70
    static let observationThreshold = 0.54
    static let safetyMargin = 0.03

    static func evaluate(
        analyses: [GoalModelAnalysis],
        totalCost: Double = defaultTotalCost,
        missReturn: Double = defaultMissReturn,
        averageHitPayout: Double = defaultAverageHitPayout
    ) -> OddsConfidenceRecommendation? {
        guard analyses.count >= 5,
              totalCost.isFinite,
              missReturn.isFinite,
              averageHitPayout.isFinite,
              averageHitPayout > missReturn else { return nil }

        let eligible = analyses.filter(isEligible)
        guard eligible.count == analyses.count else { return nil }

        // 与离线验证相同：把归一化熵最低（概率最集中）的一场作为单选。
        guard let best = eligible.min(by: {
            normalizedEntropy($0.handicapProbabilities) < normalizedEntropy($1.handicapProbabilities)
        }) else { return nil }
        return evaluateCandidate(
            best,
            totalCost: totalCost,
            missReturn: missReturn,
            averageHitPayout: averageHitPayout
        )
    }

    /// 比分 Tab 逐场标注使用。计算规则与输入 Tab 的整组推荐完全一致。
    static func evaluateCandidate(
        _ analysis: GoalModelAnalysis,
        totalCost: Double = defaultTotalCost,
        missReturn: Double = defaultMissReturn,
        averageHitPayout: Double = defaultAverageHitPayout
    ) -> OddsConfidenceRecommendation? {
        guard isEligible(analysis),
              totalCost.isFinite,
              missReturn.isFinite,
              averageHitPayout.isFinite,
              averageHitPayout > missReturn else { return nil }
        let ordered = analysis.handicapProbabilities.enumerated().sorted { $0.element > $1.element }
        guard ordered.count == 3 else { return nil }
        let outcomeByIndex = [3, 1, 0]
        let topProbability = ordered[0].element
        let runnerUp = ordered[1].element
        let gap = topProbability - runnerUp

        let breakEven = min(max(
            (totalCost - missReturn) / (averageHitPayout - missReturn),
            0
        ), 1)
        let greenThreshold = min(max(minimumGreenThreshold, breakEven + safetyMargin), 1)
        let decision: OddsConfidenceDecision
        let explanation: String
        if topProbability >= greenThreshold,
           analysis.confidenceIndex >= 75,
           gap >= 0.15 {
            decision = .bet
            explanation = "单选覆盖率、模型信心和前两项概率差同时达标。"
        } else if topProbability >= observationThreshold,
                  analysis.confidenceIndex >= 55 {
            decision = .observe
            explanation = "有明显首选，但尚未跨过含安全余量的盈亏平衡线，仅记录模拟。"
        } else {
            decision = .skip
            explanation = "赔率概率不够集中，或模型信心不足，本组不投注。"
        }

        return OddsConfidenceRecommendation(
            decision: decision,
            matchNumber: analysis.match.matchNumber,
            outcome: outcomeByIndex[ordered[0].offset],
            outcomeProbability: topProbability,
            runnerUpProbability: runnerUp,
            probabilityGap: gap,
            modelConfidenceIndex: analysis.confidenceIndex,
            breakEvenProbability: breakEven,
            bettingThreshold: greenThreshold,
            totalCost: totalCost,
            missReturn: missReturn,
            averageHitPayout: averageHitPayout,
            explanation: explanation
        )
    }

    private static func isEligible(_ analysis: GoalModelAnalysis) -> Bool {
        !analysis.match.hasStarted
            && analysis.match.handicap != nil
            && analysis.match.marketOdds.count == 3
            && analysis.handicapFairOdds.count == 3
            && analysis.handicapProbabilities.count == 3
            && analysis.handicapProbabilities.allSatisfy { $0.isFinite && $0 > 0 }
    }

    private static func normalizedEntropy(_ probabilities: [Double]) -> Double {
        guard probabilities.count == 3 else { return 1 }
        let total = probabilities.reduce(0, +)
        guard total.isFinite, total > 0 else { return 1 }
        let entropy = probabilities.reduce(0.0) { partial, value in
            let probability = value / total
            return partial - probability * log(max(probability, 1e-12))
        }
        return entropy / log(3)
    }
}

enum GoalModelError: LocalizedError, Equatable {
    case invalidIssue
    case issueNotFoundForDate(String)
    case invalidMatchNumbers
    case invalidResponse
    case dataSourceUnavailable
    case matchNotFound(String)
    case matchAlreadyStarted(String)
    case handicapUnavailable(String)
    case oddsUnavailable(String)
    case resultUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidIssue:
            return "请输入5位北单期号（如26093），或日期09-10、260910、20260910。"
        case .issueNotFoundForDate(let date):
            return "没有自动匹配到\(date)对应的北单期号，请直接输入期号。"
        case .invalidMatchNumbers:
            return "请输入有效且不重复的北单场次号。"
        case .invalidResponse:
            return "返回的页面无法识别为北单数据。"
        case .dataSourceUnavailable:
            return "暂时无法连接数据源。"
        case .matchNotFound(let number):
            return "所选期号中没有找到第\(number)场，请核对期号和场次号。"
        case .matchAlreadyStarted(let number):
            return "第\(number)场已经开赛或结束；为避免赛果倒灌，进球模型只分析状态为“未”的比赛。"
        case .handicapUnavailable(let number):
            return "第\(number)场尚未发布北单让球，暂不能生成ABCD推荐。"
        case .oddsUnavailable(let number):
            return "第\(number)场缺少有效的完整欧赔或让球SP，暂不能分析。"
        case .resultUnavailable(let number):
            return "第\(number)场尚无完整赛果，暂不能作为上一次结果。"
        }
    }
}

enum ABCDDataSource: String, CaseIterable {
    case automatic = "自动：500 → 澳客"
    case fiveHundred = "500"
    case okooo = "澳客"
}

struct ABCDFetchResult: Sendable {
    let analyses: [GoalModelAnalysis]
    let source: String
}

enum MultiSourceABCDClient {
    private static func loadMatches(source: ABCDDataSource, issue: String, numbers: [String]) async throws -> [BeijingSingleMatch] {
        if source == .fiveHundred {
            return try await FiveHundredBeijingSingleClient.fetch(issue: issue, matchNumbers: numbers)
        }
        return try await OkoooBeijingSingleClient.fetch(issue: issue, matchNumbers: numbers)
    }

    static func fetch(
        issue: String,
        matchNumbers: [String],
        source: ABCDDataSource,
        load: (ABCDDataSource, String, [String]) async throws -> [BeijingSingleMatch] = loadMatches
    ) async throws -> ABCDFetchResult {
        let sources: [ABCDDataSource] = source == .automatic ? [.fiveHundred, .okooo] : [source]
        var failures: [String] = []
        for provider in sources {
            try Task.checkCancellation()
            do {
                let matches = try await load(provider, issue, matchNumbers)
                guard matches.count == matchNumbers.count,
                      zip(matches, matchNumbers).allSatisfy({ $0.issue == issue && Int($0.matchNumber) == Int($1) }) else {
                    throw GoalModelError.invalidResponse
                }
                let analyses = try matches.map(PoissonGoalModel.analyze)
                try Task.checkCancellation()
                guard analyses.count == matchNumbers.count else { throw GoalModelError.invalidResponse }
                return ABCDFetchResult(analyses: analyses, source: provider.rawValue)
            } catch {
                try Task.checkCancellation()
                failures.append("\(provider.rawValue)：\(error.localizedDescription)")
            }
        }
        throw NSError(domain: "ABCD", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")])
    }
}

enum OkoooBeijingSingleClient {
    static func fetch(issue: String, matchNumbers: [String]) async throws -> [BeijingSingleMatch] {
        guard issue.count >= 5, issue.allSatisfy(\.isNumber) else { throw GoalModelError.invalidIssue }
        let urls = [
            "https://www.okooo.com/danchang/shengfu/jiangjin/\(issue)/",
            "https://www.okooo.com/danchang/jiangjin/"
        ]
        var failures: [String] = []
        for address in urls {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: URL(string: address)!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw GoalModelError.invalidResponse }
                guard (200...299).contains(http.statusCode) else {
                    throw NSError(domain: "ABCD.HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                }
                guard let html = FiveHundredBeijingSingleClient.decodeHTML(data) else { throw GoalModelError.invalidResponse }
                let matches = parse(html: html, issue: issue)
                return try matchNumbers.map { number in
                    guard let match = matches.first(where: { Int($0.matchNumber) == Int(number) }) else {
                        throw GoalModelError.matchNotFound(number)
                    }
                    guard match.marketOdds.count == 3, match.marketOdds.allSatisfy({ $0.isFinite && $0 > 1 }) else {
                        throw GoalModelError.oddsUnavailable(number)
                    }
                    return match
                }
            } catch {
                try Task.checkCancellation()
                failures.append(error.localizedDescription)
            }
        }
        throw NSError(domain: "ABCD.Okooo", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")])
    }

    static func fetchCompletedResults(issue: String, matchNumbers: [String]) async throws -> [BeijingSingleMatch] {
        guard issue.count >= 5, issue.allSatisfy(\.isNumber) else { throw GoalModelError.invalidIssue }
        let urls = [
            "https://www.okooo.com/danchang/shengfu/jiangjin/\(issue)/",
            "https://www.okooo.com/danchang/jiangjin/"
        ]
        var failures: [String] = []
        for address in urls {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: URL(string: address)!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let html = FiveHundredBeijingSingleClient.decodeHTML(data) else {
                    throw GoalModelError.invalidResponse
                }
                let matches = parse(html: html, issue: issue)
                return try matchNumbers.map { number in
                    guard let match = matches.first(where: { Int($0.matchNumber) == Int(number) }) else {
                        throw GoalModelError.matchNotFound(number)
                    }
                    guard match.handicapOutcome != nil else {
                        throw GoalModelError.resultUnavailable(number)
                    }
                    return match
                }
            } catch {
                try Task.checkCancellation()
                failures.append(error.localizedDescription)
            }
        }
        throw NSError(
            domain: "Result.Okooo",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")]
        )
    }

    static func parse(html: String, issue: String) -> [BeijingSingleMatch] {
        // 必须核对选中期号，不能将站点重定向到当前期的结果当作请求期。
        let selected = FiveHundredBeijingSingleClient.firstCapture(
            pattern: #"(?is)<select\b[^>]*id=["']SelectLotteryNo["'][^>]*>(.*?)</select>"#, in: html
        ) ?? ""
        let options = FiveHundredBeijingSingleClient.captures(pattern: #"(?is)<option\b([^>]*)>"#, in: selected)
        guard options.contains(where: { option in
            let attributes = option[0]
            return attributes.range(of: #"\bselected\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                && FiveHundredBeijingSingleClient.firstCapture(pattern: #"value=["'](\d+)["']"#, in: attributes) == issue
        }) else { return [] }
        let rows = FiveHundredBeijingSingleClient.captures(
            pattern: #"(?is)<tr\b[^>]*id=["']Match_(\d+)["'][^>]*>(.*?)</tr>"#, in: html
        )
        return rows.compactMap { row in
            let number = row[0]
            let cells = FiveHundredBeijingSingleClient.captures(pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#, in: row[1]).map { $0[0] }
            guard cells.count >= 8 else { return nil }
            func span(_ suffix: String, in cell: String) -> String? {
                FiveHundredBeijingSingleClient.firstCapture(
                    pattern: "(?is)<span\\b[^>]*id=[\"']MatchOrder\(number)_\(suffix)[\"'][^>]*>(.*?)</span>", in: cell
                ).map(FiveHundredBeijingSingleClient.plainText)
            }
            guard let home = span("HomeName", in: cells[3]), !home.isEmpty,
                  let away = span("AwayName", in: cells[4]), !away.isEmpty,
                  let handicapText = span("HandicapNumber", in: cells[3]),
                  let handicap = handicapText.isEmpty ? 0 : Int(handicapText) else { return nil }
            let odds = cells[5...7].compactMap { Double(FiveHundredBeijingSingleClient.plainText($0)) }
            let score = cells.dropFirst(8).compactMap { cell -> (Int, Int)? in
                guard let groups = FiveHundredBeijingSingleClient.captures(
                    pattern: #"\b(\d+)\s*[:：]\s*(\d+)\b"#,
                    in: FiveHundredBeijingSingleClient.plainText(cell)
                ).first,
                      groups.count == 2,
                      let homeScore = Int(groups[0]),
                      let awayScore = Int(groups[1]) else { return nil }
                return (homeScore, awayScore)
            }.first
            return BeijingSingleMatch(
                issue: issue, matchNumber: number, fixtureID: "okooo-\(issue)-\(number)",
                league: FiveHundredBeijingSingleClient.plainText(cells[1]),
                matchTime: FiveHundredBeijingSingleClient.plainText(cells[2]),
                status: score == nil ? "赛果已隔离" : "已结束", homeTeam: home, awayTeam: away,
                handicap: handicap, referenceSP: [], marketOdds: odds,
                homeScore: score?.0, awayScore: score?.1
            )
        }
    }
}

enum FiveHundredBeijingSingleClient {
    /// 500 的旧比分页在 iPhone UA 下会重定向到不含赔率数据的移动页。
    /// 桌面 UA 才会返回 table_match 和 liveOddsList。
    private static let legacyLiveDesktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    /// 整期批量计算专用：只下载一次页面，再返回当期全部场次。
    /// 避免按 6 场一组反复请求同一个 1MB 左右的历史页面。
    static func fetchAllIssueMatches(issue: String, firstMatchNumberForDoubles: Int? = nil,
                                     excludingMatchNumbers: Set<Int> = [], firstMatchNumberForSelection: Int? = nil,
                                     requireAllABCD: Bool = true, requireFrontTwoAD: Bool = false,
                                     fixedFrontTwoDoubles: Bool = false, calibratedForSelection: Bool = true, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanIssue.count == 5, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        let html = try await downloadHTML(issue: cleanIssue) { html in
            let parsed = parse(html: html, issue: cleanIssue)
            guard !parsed.isEmpty else {
                throw GoalModelError.invalidResponse
            }
            if let first = firstMatchNumberForSelection {
                _ = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: first, matches: parsed,
                    excludingMatchNumbers: excludingMatchNumbers, requireAllABCD: requireAllABCD, requireFrontTwoAD: requireFrontTwoAD,
                    fixedFrontTwoDoubles: fixedFrontTwoDoubles, calibrated: calibratedForSelection, adDoublesWithinSix: adDoublesWithinSix, adDoubleCountWithinSix: adDoubleCountWithinSix)
            }
            // A transaction table can parse while lacking ordinary odds. For
            // continuous-six doubles that must trigger the existing score-page
            // fallback, rather than accepting an unusable candidate pool.
            if let first = firstMatchNumberForDoubles,
               VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: first, matches: parsed,
                   excludingMatchNumbers: excludingMatchNumbers, calibrated: false) == nil {
                throw GoalModelError.oddsUnavailable(String(first))
            }
        }
        let matches = parse(html: html, issue: cleanIssue).sorted {
            (Int($0.matchNumber) ?? Int.max) < (Int($1.matchNumber) ?? Int.max)
        }
        guard !matches.isEmpty else { throw GoalModelError.invalidResponse }
        return matches
    }

    /// 5位为北单期号；6/8位数字为日期，不能直接拼成期号请求。
    static func dateInput(_ input: String) -> (monthDay: String, yearPrefix: String?)? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var monthDay = clean
        var year: String?
        if clean.count == 6, clean.allSatisfy(\.isNumber) {
            year = String(clean.prefix(2))
            let digits = Array(clean)
            monthDay = String(digits[2...3]) + "-" + String(digits[4...5])
        } else if clean.count == 8, clean.allSatisfy(\.isNumber), clean.hasPrefix("20") {
            year = String(clean.dropFirst(2).prefix(2))
            let digits = Array(clean)
            monthDay = String(digits[4...5]) + "-" + String(digits[6...7])
        } else if clean.range(of: #"^20\d{2}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            year = String(clean.dropFirst(2).prefix(2))
            monthDay = String(clean.suffix(5))
            guard clean.dropFirst(4).first == "-" else { return nil }
        }
        guard monthDay.range(of: #"^\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              calendarDate(monthDay, issue: (year ?? "26") + "001") != nil else { return nil }
        return (monthDay, year)
    }

    static func publishedIssues(html: String) -> [String] {
        let select = firstCapture(pattern: #"(?is)<select\b[^>]*id=["']expect_select["'][^>]*>(.*?)</select>"#, in: html) ?? ""
        return captures(pattern: #"(?is)<option\b[^>]*value=["'](\d{5})["']"#, in: select).map { $0[0] }
    }

    static func resolveIssue(input: String, anchorIssue: String) async throws -> String {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count == 5, clean.allSatisfy(\.isNumber) { return clean }
        guard let date = dateInput(clean) else { throw GoalModelError.invalidIssue }
        let currentHTML = try await downloadHTML(issue: "")
        let published = publishedIssues(html: currentHTML)
        guard let latest = published.first else { throw GoalModelError.invalidResponse }
        let year = date.yearPrefix ?? String(latest.prefix(2))
        let month = Int(date.monthDay.prefix(2))!
        // 北单一期覆盖多天：只遍历站点真实发布的期号，并检查每一场日期。
        let candidates = published.filter { issue in
            guard issue.hasPrefix(year), let issueMonth = Int(issue.dropFirst(2).prefix(2)) else { return false }
            return issueMonth == month || issueMonth == month - 1
        }.prefix(20)
        for issue in candidates {
            try Task.checkCancellation()
            let html: String
            if issue == latest {
                html = currentHTML
            } else {
                do { html = try await downloadHTML(issue: issue) }
                catch { try Task.checkCancellation(); continue }
            }
            if parse(html: html, issue: issue).contains(where: { $0.matchTime.hasPrefix(date.monthDay + " ") }) {
                return issue
            }
        }
        throw GoalModelError.issueNotFoundForDate(clean)
    }

    static func fetch(issue: String, matchNumbers: [String]) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        let cleanedNumbers = matchNumbers.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // VIP 横截面条件会同时读取“当前六场＋上一组六场”，最多 12 场。
        // 这里原先沿用单组 8 场上限，会在首页全局生成尚未联网前就误报
        // “缺少完整普通胜平负欧赔或让球数”。保留合理上限以防异常输入。
        guard (1...24).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else {
            throw GoalModelError.invalidMatchNumbers
        }

        let html = try await downloadHTML(issue: cleanIssue) { html in
            _ = try selectMatches(html: html, issue: cleanIssue, matchNumbers: cleanedNumbers)
        }
        return try selectMatches(html: html, issue: cleanIssue, matchNumbers: cleanedNumbers)
    }

    static func selectMatches(html: String, issue: String, matchNumbers: [String]) throws -> [BeijingSingleMatch] {
        let allMatches = parse(html: html, issue: issue)
        var selected: [BeijingSingleMatch] = []
        for number in matchNumbers {
            guard let match = allMatches.first(where: { normalizedNumber($0.matchNumber) == normalizedNumber(number) }) else {
                throw GoalModelError.matchNotFound(number)
            }
            guard match.handicap != nil else { throw GoalModelError.handicapUnavailable(number) }
            let hasReferenceSP = match.referenceSP.count == 3
                && match.referenceSP.allSatisfy({ $0 > 1.0 && $0.isFinite })
            let hasMarketOdds = match.marketOdds.count == 3
                && match.marketOdds.allSatisfy({ $0 > 1.0 && $0.isFinite })
            guard hasReferenceSP || hasMarketOdds else {
                throw GoalModelError.oddsUnavailable(number)
            }
            selected.append(match.resultBlindCopy)
        }
        return selected
    }

    static func fetchCompletedResults(issue: String, matchNumbers: [String]) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        let cleanedNumbers = matchNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (5...7).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else {
            throw GoalModelError.invalidMatchNumbers
        }
        // 交易页可能尚未正式开奖，但直播页在比赛结束后已经有比分。
        // 用完整赛果校验每个入口；当前入口缺少比分时继续回退到下一个数据源。
        let html = try await downloadHTML(issue: cleanIssue) { html in
            _ = try selectCompletedMatches(html: html, issue: cleanIssue, matchNumbers: cleanedNumbers)
        }
        return try selectCompletedMatches(html: html, issue: cleanIssue, matchNumbers: cleanedNumbers)
    }

    /// 返回当前可见的赛况；未开赛可无比分，比赛中可返回临时比分，不要求全部结束。
    static func fetchLiveMatches(issue: String, matchNumbers: [String]) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumbers = matchNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        guard (1...8).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else {
            throw GoalModelError.invalidMatchNumbers
        }
        func selectedMatches(from html: String) throws -> [BeijingSingleMatch] {
            let allMatches = parse(html: html, issue: cleanIssue)
            return try cleanedNumbers.map { number in
                guard let match = allMatches.first(where: {
                    normalizedNumber($0.matchNumber) == normalizedNumber(number)
                }) else {
                    throw GoalModelError.matchNotFound(number)
                }
                return match
            }
        }
        let html = try await downloadHTML(issue: cleanIssue) { html in
            _ = try selectedMatches(from: html)
        }
        return try selectedMatches(from: html)
    }

    /// 比分 Tab 使用：每次从500北单比分页刷新整期赛况，不复用历史赔率缓存。
    static func fetchIssueScoreboard(issue: String, requiringExplicitStatus: Bool = false) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let html = try await downloadScoreboardHTML(issue: cleanIssue)
        return try parseScoreboard(html: html, issue: cleanIssue, requiringExplicitStatus: requiringExplicitStatus)
    }

    /// Forward validation must not treat a trade page's mere score presence as finality.
    static func parseScoreboard(html: String, issue: String, requiringExplicitStatus: Bool = false) throws -> [BeijingSingleMatch] {
        if requiringExplicitStatus {
            let select = firstCapture(pattern: #"(?is)<select\b[^>]*id=["']sel_expect["'][^>]*>(.*?)</select>"#, in: html) ?? ""
            let options = captures(pattern: #"(?is)<option\b([^>]*)>"#, in: select).compactMap(\.first)
            let selected = options.filter { $0.range(of: #"\bselected\b"#, options: [.regularExpression,.caseInsensitive]) != nil }
            let active = selected.isEmpty && options.count == 1 ? options : selected
            guard active.count == 1,
                  firstCapture(pattern: #"value=["'](\d+)["']"#, in: active[0]) == issue else { throw GoalModelError.invalidResponse }
        }
        var matches = parseLegacyLivePage(html: html, issue: issue)
        if matches.isEmpty && !requiringExplicitStatus { matches = parse(html: html, issue: issue) }
        guard !matches.isEmpty else { throw GoalModelError.invalidResponse }
        return matches.sorted {
            (Int($0.matchNumber) ?? Int.max) < (Int($1.matchNumber) ?? Int.max)
        }
    }

    static func fetchSeventhMatchMarket(issue: String, matchNumber: String) async throws -> SeventhMatchMarketSnapshot {
        guard let number = Int(matchNumber), number > 0,
              matchNumber.allSatisfy(\.isNumber) else { throw GoalModelError.invalidMatchNumbers }
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let html = try await downloadScoreboardHTML(issue: cleanIssue)
        try Task.checkCancellation()
        var snapshot = try await Task.detached(priority: .utility) {
            try parseSeventhMatchMarket(html: html, issue: cleanIssue, matchNumber: String(number))
        }.value
        do {
            let companySelect = firstCapture(pattern: #"(?is)<select\b[^>]*id=["']sel_company["'][^>]*>(.*?)</select>"#, in: html) ?? ""
            let name = firstCapture(pattern: #"(?is)<option\b[^>]*value=["']3["'][^>]*>(.*?)</option>"#, in: companySelect).map(plainText)
            snapshot.asianQuote = try await fetchAsianHandicapQuote(fixtureID: snapshot.match.fixtureID,
                companyName: name.flatMap { $0.isEmpty ? nil : $0 } ?? "500默认机构（3）")
        } catch {
            try Task.checkCancellation()
            snapshot.asianQuoteMessage = "水位未发布或获取失败，可刷新重试"
        }
        return snapshot
    }

    /// Same endpoint and ordering as the scoreboard's hover popup:
    /// root[0] = Asian handicap, [0] = opening, [1] = current.
    static func parseAsianHandicapQuote(data: Data, companyName: String = "500默认机构（3）") throws -> AsianHandicapQuote {
        guard let markets = try JSONSerialization.jsonObject(with: data) as? [Any],
              let asian = markets.first as? [Any], asian.count >= 2 else { throw GoalModelError.invalidResponse }
        func point(_ raw: Any) -> AsianHandicapPoint? {
            guard let row = raw as? [Any], row.count == 3,
                  let line = row[1] as? String else { return nil }
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !["-", "--", "封"].contains(cleaned) else { return nil }
            func water(_ value: Any) -> Double? {
                let number: Double?
                if let text = value as? String { number = Double(text) }
                else if let numeric = value as? NSNumber, CFGetTypeID(numeric) != CFBooleanGetTypeID() { number = numeric.doubleValue }
                else { number = nil }
                guard let number, number.isFinite, number > 0 else { return nil }
                return number
            }
            guard let home = water(row[0]), let away = water(row[2]) else { return nil }
            return AsianHandicapPoint(homeWater: home, handicap: cleaned, awayWater: away)
        }
        guard let current = point(asian[1]) else { throw GoalModelError.invalidResponse }
        return AsianHandicapQuote(companyID: 3, companyName: companyName, initial: point(asian[0]), current: current)
    }

    private static func fetchAsianHandicapQuote(fixtureID: String, companyName: String) async throws -> AsianHandicapQuote {
        guard !fixtureID.isEmpty, fixtureID.allSatisfy(\.isNumber) else { throw GoalModelError.invalidResponse }
        var components = URLComponents(string: "https://live.500.com/json/odds.php")!
        components.queryItems = [URLQueryItem(name: "fid", value: fixtureID), URLQueryItem(name: "cid", value: "3")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(legacyLiveDesktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://live.500.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GoalModelError.invalidResponse
        }
        return try parseAsianHandicapQuote(data: data, companyName: companyName)
    }

    static func parseSeventhMatchMarket(html: String, issue: String, matchNumber: String,
                                       capturedAt: Date = Date()) throws -> SeventhMatchMarketSnapshot {
        guard issue.count == 5, issue.allSatisfy(\.isNumber) else { throw GoalModelError.invalidIssue }
        guard let number = Int(matchNumber), number > 0,
              matchNumber.allSatisfy(\.isNumber) else { throw GoalModelError.invalidMatchNumbers }
        if let publishedIssue = firstCapture(
            pattern: #"(?i)window\.live_cur_expect\s*=\s*["'](\d{5})["']"#, in: html
        ), publishedIssue != issue { throw GoalModelError.invalidResponse }
        guard let match = parseLegacyLivePage(html: html, issue: issue).first(where: {
            Int($0.matchNumber) == number
        }) else { throw GoalModelError.matchNotFound(matchNumber) }
        let row = firstCapture(
            pattern: "(?is)<tr\\s+id=[\"']a\(match.fixtureID)[\"'][^>]*>(.*?)</tr>", in: html
        ) ?? ""
        let cells = captures(pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#, in: row).compactMap(\.first)
        let rawLine = cells.count > 6 ? firstCapture(
            pattern: #"(?is)<a\b[^>]*\bdata-(?:pb|ao)=["'][^"']*["'][^>]*>(.*?)</a>"#,
            in: cells[6]
        ).map(plainText) : nil
        let line = rawLine.flatMap { $0.isEmpty || ["-", "--", "封"].contains($0) ? nil : $0 }
        return SeventhMatchMarketSnapshot(match: match, asianHandicap: line, capturedAt: capturedAt)
    }

    private static func downloadScoreboardHTML(issue: String) async throws -> String {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanIssue.count == 5, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }

        var components = URLComponents(string: "https://live.500.com/zqdc.php")
        components?.queryItems = [URLQueryItem(name: "e", value: cleanIssue)]
        guard let url = components?.url else { throw GoalModelError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            legacyLiveDesktopUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://live.500.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let html = decodeHTML(data) else {
            throw GoalModelError.invalidResponse
        }
        return html
    }

    /// 已结束场次专用：必须取到让球胜/平/负三项完整SP。
    /// 历史交易页若只剩中奖方向的单个SP，验证会失败，downloadHTML会继续
    /// 回退到500直播/历史页，从 liveOddsList.rqsp 取完整三项赔率。
    static func fetchHistoricalHandicapOdds(
        issue: String,
        matchNumbers: [String]
    ) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumbers = matchNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        guard (1...8).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else {
            throw GoalModelError.invalidMatchNumbers
        }

        func selectedMatches(from html: String) throws -> [BeijingSingleMatch] {
            let allMatches = parse(html: html, issue: cleanIssue)
            return try cleanedNumbers.map { number in
                guard let match = allMatches.first(where: {
                    normalizedNumber($0.matchNumber) == normalizedNumber(number)
                }) else {
                    throw GoalModelError.matchNotFound(number)
                }
                guard match.handicap != nil else { throw GoalModelError.handicapUnavailable(number) }
                guard match.referenceSP.count == 3,
                      match.referenceSP.allSatisfy({ $0 > 1 && $0.isFinite }) else {
                    throw GoalModelError.oddsUnavailable(number)
                }
                return match
            }
        }

        let html = try await downloadHTML(issue: cleanIssue) { html in
            _ = try selectedMatches(from: html)
        }
        return try selectedMatches(from: html)
    }

    /// 直接从500比分页取往期场次。不先访问交易页，避免完场后只剩
    /// 单个开奖SP的交易页提前结束数据源回退。比分页 liveOddsList[fixture]["0"]
    /// 仍保留完整普通胜/平/负赔率，可结合让球数重建让球概率。
    static func fetchScorePageOdds(
        issue: String,
        matchNumbers: [String]
    ) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumbers = matchNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else {
            throw GoalModelError.invalidIssue
        }
        // VIP 横截面条件可同时需要当前六场与上一组六场。
        guard (1...24).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else {
            throw GoalModelError.invalidMatchNumbers
        }

        func selectCompleteMatches(from matches: [BeijingSingleMatch]) throws -> [BeijingSingleMatch] {
            try cleanedNumbers.map { number in
                guard let match = matches.first(where: {
                    normalizedNumber($0.matchNumber) == normalizedNumber(number)
                }) else {
                    throw GoalModelError.matchNotFound(number)
                }
                guard match.handicap != nil else { throw GoalModelError.handicapUnavailable(number) }
                guard match.marketOdds.count == 3,
                      match.marketOdds.allSatisfy({ $0 > 1 && $0.isFinite }) else {
                    throw GoalModelError.oddsUnavailable(number)
                }
                return match
            }
        }

        // 旧版比分页缓存只有在本次需要的所有场次仍完整时才能复用。
        // 避免某一场曾经缺欧赔后，后续点“全局生成”永久被旧缓存卡住。
        if let cached = await BeijingSingleScorePageCache.shared.matches(for: cleanIssue),
           let selected = try? selectCompleteMatches(from: cached) {
            return selected
        }

        var failures: [String] = []
        do {
            var components = URLComponents(string: "https://live.500.com/zqdc.php")
            components?.queryItems = [URLQueryItem(name: "e", value: cleanIssue)]
            guard let url = components?.url else { throw GoalModelError.invalidResponse }
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                // 500 现在会把 iPhone UA 重定向到不含 liveOddsList 的新移动页。
                // 使用桌面 UA 取回仍包含普通欧赔＋实际让球数的数据页。
                legacyLiveDesktopUserAgent,
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://live.500.com/", forHTTPHeaderField: "Referer")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let html = decodeHTML(data),
                  html.contains("table_match"), html.contains("liveOddsList") else {
                throw GoalModelError.invalidResponse
            }
            let parsed = parseLegacyLivePage(html: html, issue: cleanIssue)
            guard !parsed.isEmpty else { throw GoalModelError.invalidResponse }
            let selected = try selectCompleteMatches(from: parsed)
            await BeijingSingleScorePageCache.shared.store(parsed, for: cleanIssue)
            return selected
        } catch {
            try Task.checkCancellation()
            failures.append("比分页：\(error.localizedDescription)")
        }

        // 当比分页临时不可用时，当前期交易页仍有同一套普通欧赔和让球数。
        // downloadHTML 会对选中场次做完整性校验，不会回退到让球 SP。
        do {
            let html = try await downloadHTML(issue: cleanIssue) { html in
                _ = try selectCompleteMatches(from: parse(html: html, issue: cleanIssue))
            }
            let parsed = parse(html: html, issue: cleanIssue)
            let selected = try selectCompleteMatches(from: parsed)
            await BeijingSingleScorePageCache.shared.store(parsed, for: cleanIssue)
            return selected
        } catch {
            try Task.checkCancellation()
            failures.append("交易页：\(error.localizedDescription)")
        }

        // 500 两个页面中若个别场次临时缺字段，最后从澳客按相同的期号、
        // 场次号读取完整普通欧赔＋实际让球数。仍严格走项目赔率对照表，
        // 不使用网页让球 SP 代替普通胜平负欧赔。
        do {
            let parsed = try await OkoooBeijingSingleClient.fetch(
                issue: cleanIssue,
                matchNumbers: cleanedNumbers
            )
            let selected = try selectCompleteMatches(from: parsed)
            await BeijingSingleScorePageCache.shared.store(parsed, for: cleanIssue)
            return selected
        } catch {
            try Task.checkCancellation()
            failures.append("澳客：\(error.localizedDescription)")
        }

        throw NSError(
            domain: "ComparisonTableOdds.500",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")]
        )
    }

    /// 奖金页使用原始SP和开奖SP，不隔离赛果。
    static func fetchPrizeMatches(
        issue: String,
        matchNumbers: [String],
        requireHandicapSP: Bool = false
    ) async throws -> [BeijingSingleMatch] {
        let cleanIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumbers = matchNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleanIssue.isEmpty, cleanIssue.allSatisfy(\.isNumber) else { throw GoalModelError.invalidIssue }
        guard (1...8).contains(cleanedNumbers.count),
              cleanedNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              Set(cleanedNumbers).count == cleanedNumbers.count else { throw GoalModelError.invalidMatchNumbers }
        let html = try await downloadHTML(issue: cleanIssue) { html in
            _ = try selectPrizeMatches(
                html: html,
                issue: cleanIssue,
                matchNumbers: cleanedNumbers,
                requireHandicapSP: requireHandicapSP
            )
        }
        return try selectPrizeMatches(
            html: html,
            issue: cleanIssue,
            matchNumbers: cleanedNumbers,
            requireHandicapSP: requireHandicapSP
        )
    }

    private static func selectPrizeMatches(
        html: String,
        issue: String,
        matchNumbers: [String],
        requireHandicapSP: Bool
    ) throws -> [BeijingSingleMatch] {
        let allMatches = parse(html: html, issue: issue)
        return try matchNumbers.enumerated().map { index, number in
            guard let match = allMatches.first(where: { normalizedNumber($0.matchNumber) == normalizedNumber(number) }) else {
                throw GoalModelError.matchNotFound(number)
            }
            let hasCurrentSP = match.referenceSP.count == 3
                && match.referenceSP.allSatisfy { $0 > 0 && $0.isFinite }
            let hasMarketSP = match.marketOdds.count == 3
                && match.marketOdds.allSatisfy { $0 > 0 && $0.isFinite }
            let hasSettledSP = match.settledSP.map { $0 > 0 && $0.isFinite } == true
            if matchNumbers.count == 7 && index == 6 {
                guard requireHandicapSP ? hasCurrentSP : hasMarketSP else {
                    throw GoalModelError.oddsUnavailable(number)
                }
                return match
            }
            guard match.handicapOutcome != nil else { throw GoalModelError.resultUnavailable(number) }
            guard hasCurrentSP || hasSettledSP else {
                throw GoalModelError.oddsUnavailable(number)
            }
            return match
        }
    }

    private static func selectCompletedMatches(
        html: String,
        issue: String,
        matchNumbers: [String]
    ) throws -> [BeijingSingleMatch] {
        let allMatches = parse(html: html, issue: issue)
        return try matchNumbers.map { number in
            guard let match = allMatches.first(where: { normalizedNumber($0.matchNumber) == normalizedNumber(number) }) else {
                throw GoalModelError.matchNotFound(number)
            }
            guard match.handicapOutcome != nil else { throw GoalModelError.resultUnavailable(number) }
            return match
        }
    }

    static func parse(html: String, issue: String) -> [BeijingSingleMatch] {
        let legacyMatches = parseLegacyLivePage(html: html, issue: issue)
        if !legacyMatches.isEmpty { return legacyMatches }
        return parseTradePage(html: html, issue: issue)
    }

    private static func parseLegacyLivePage(html: String, issue: String) -> [BeijingSingleMatch] {
        let rowPattern = #"(?is)<tr\s+id=[\"']a(\d+)[\"'][^>]*>(.*?)</tr>"#
        let oddsByFixture = marketOddsByFixture(in: html)
        let handicapSPByFixture = handicapSPByFixture(in: html)
        return captures(pattern: rowPattern, in: html).compactMap { groups in
            guard groups.count == 2 else { return nil }
            let fixtureID = groups[0]
            let row = groups[1]
            let cells = captures(pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#, in: row)
                .compactMap(\.first)
            guard cells.count >= 10 else { return nil }

            let matchNumber = lastInteger(in: plainText(cells[0])) ?? ""
            guard !matchNumber.isEmpty else { return nil }
            let league = plainText(cells[1])
            let matchTime = plainText(cells[3])
            let status = plainText(cells[4])
            let homeTeam = linkTexts(in: cells[5]).last ?? plainText(cells[5])
            let awayTeam = linkTexts(in: cells[7]).first ?? plainText(cells[7])

            let cellReferenceSP = captures(pattern: #"(?is)<span\b[^>]*>(.*?)</span>"#, in: cells[9])
                .compactMap(\.first)
                .map(plainText)
                .compactMap(Double.init)
            let referenceSP = cellReferenceSP.count == 3
                ? cellReferenceSP
                : (handicapSPByFixture[fixtureID] ?? cellReferenceSP)
            let handicapText = firstCapture(
                pattern: #"(?is)class=[\"'][^\"']*sp_(?:sr|rq)[^\"']*[\"'][^>]*>\s*\(([+-]?\d+)\)"#,
                in: cells[5]
            )
            // 500新版比分页使用sp_rq，旧版使用sp_sr；没有标记即为0球。
            let handicap = handicapText.flatMap(Int.init) ?? 0
            let scores = linkTexts(in: cells[6]).compactMap(Int.init)
            let settledSP = scores.count >= 2 && cellReferenceSP.count == 1 ? cellReferenceSP.first : nil

            return BeijingSingleMatch(
                issue: issue,
                matchNumber: matchNumber,
                fixtureID: fixtureID,
                league: league,
                matchTime: matchTime,
                status: status,
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                handicap: handicap,
                referenceSP: referenceSP,
                marketOdds: oddsByFixture[fixtureID] ?? [],
                homeScore: scores.count >= 2 ? scores[0] : nil,
                awayScore: scores.count >= 2 ? scores[1] : nil,
                settledSP: settledSP
            )
        }
    }

    /// 真机优先使用的500北单交易页解析器，支持expect查询当前期及往期。
    private static func parseTradePage(html: String, issue: String) -> [BeijingSingleMatch] {
        captures(pattern: #"(?is)<tr\b([^>]*)>(.*?)</tr>"#, in: html).compactMap { groups in
            guard groups.count == 2 else { return nil }
            let attributes = groups[0]
            guard attributes.range(
                of: #"class\s*=\s*[\"'][^\"']*\bvs_lines\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil else { return nil }
            let cells = captures(pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#, in: groups[1])
                .compactMap(\.first)
            guard cells.count >= 11 else { return nil }

            let fixtureID = firstCapture(pattern: #"\bfid\s*=\s*[\"']?(\d+)"#, in: attributes) ?? ""
            let matchNumber = firstCapture(
                pattern: #"(?is)class=[\"'][^\"']*\bchnum\b[^\"']*[\"'][^>]*>\s*(\d+)"#,
                in: cells[0]
            ) ?? lastInteger(in: plainText(cells[0])) ?? ""
            guard !matchNumber.isEmpty else { return nil }

            let date = firstCapture(pattern: #"scheduleDate:'(\d{4}-\d{2}-\d{2})'"#, in: attributes)
            let time = plainText(cells[2])
            // scheduleDate groups the selling day; after-midnight fixtures can
            // close on the next calendar day. Prefer the source's full cutoff.
            let datedCutoff = firstCapture(pattern: #"endTime:\s*'20\d{2}-(\d{2}-\d{2}\s+\d{2}:\d{2})'"#, in: attributes)
            let matchTime = datedCutoff ?? date.map { "\($0.suffix(5)) \(time)" } ?? time
            let handicap = firstCapture(
                pattern: #"rangqiuNum:'([+-]?\d+)'"#,
                in: attributes
            ).flatMap(Int.init) ?? firstSignedInteger(in: plainText(cells[4]))
            let marketOdds = captures(
                pattern: #"(?is)class=[\"'][^\"']*\bpjoz\b[^\"']*[\"'][^>]*>\s*([0-9]+(?:\.[0-9]+)?)"#,
                in: cells[6]
            ).compactMap(\.first).compactMap(Double.init)
            let marketShares = publishedBettingShares(in: cells[6])
            let referenceSP = cells[8...10].compactMap { cell in
                firstCapture(
                    pattern: #"(?is)class=[\"'][^\"']*\bsp_value\b[^\"']*[\"'][^>]*>\s*([0-9]+(?:\.[0-9]+)?)"#,
                    in: cell
                ).flatMap(Double.init)
            }
            let scoreParts = captures(
                pattern: #"(\d+)\s*[:：]\s*(\d+)"#,
                in: plainText(cells[7])
            ).first ?? []
            let homeScore = scoreParts.count == 2 ? Int(scoreParts[0]) : nil
            let awayScore = scoreParts.count == 2 ? Int(scoreParts[1]) : nil
            let isDisabled = attributes.range(of: "disabled:'yes'", options: .caseInsensitive) != nil
            let resultCellText = plainText(cells[7])
            let isPostponed = cells[7].localizedCaseInsensitiveContains("later.gif")
                || resultCellText.contains("延期")
                || resultCellText.contains("改期")

            return BeijingSingleMatch(
                issue: issue,
                matchNumber: matchNumber,
                fixtureID: fixtureID,
                league: linkTexts(in: cells[1]).first ?? plainText(cells[1]),
                matchTime: matchTime,
                status: homeScore != nil ? "完" : (isPostponed ? "改期" : (isDisabled ? "已开赛" : "未")),
                homeTeam: linkTexts(in: cells[3]).last ?? plainText(cells[3]),
                awayTeam: linkTexts(in: cells[5]).first ?? plainText(cells[5]),
                handicap: handicap,
                referenceSP: referenceSP,
                marketOdds: marketOdds,
                marketBettingShares: marketShares,
                homeScore: homeScore,
                awayScore: awayScore,
                settledSP: homeScore != nil && referenceSP.count == 1 ? referenceSP.first : nil
            )
        }
    }

    static func publishedBettingShares(in cell: String) -> [Double] {
        let parts = captures(pattern: #"(?is)<span\b[^>]*class=["'][^"']*\btzbl\b[^"']*["'][^>]*>(.*?)</span>"#, in: cell)
        guard parts.count == 3 else { return [] }
        let values = parts.compactMap { Double(plainText($0[0]).replacingOccurrences(of: "%", with: "")) }
        guard values.count == 3, values.allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { return [] }
        let sum = values.reduce(0, +)
        guard (99...101).contains(sum) else { return [] }
        return values.map { $0 / sum }
    }

    private static func downloadHTML(issue: String, validate: (String) throws -> Void = { _ in }) async throws -> String {
        let sources = [
            ("https://trade.500.com/bjdc/", "expect", "vs_table", "https://trade.500.com/bjdc/"),
            ("https://live.500.com/zqdc.php", "e", "table_match", "https://live.500.com/")
        ]
        var failures: [String] = []
        for (base, queryName, marker, referer) in sources {
            try Task.checkCancellation()
            var components = URLComponents(string: base)
            components?.queryItems = issue.isEmpty ? nil : [URLQueryItem(name: queryName, value: issue)]
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue(referer, forHTTPHeaderField: "Referer")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw GoalModelError.invalidResponse }
                guard (200...299).contains(http.statusCode) else {
                    throw NSError(domain: "ABCD.HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                }
                guard let html = decodeHTML(data), html.contains(marker) else { throw GoalModelError.invalidResponse }
                // 页面有表格并不代表所选5场有完整赔率；验证失败后继续下一个入口。
                try validate(html)
                return html
            } catch {
                try Task.checkCancellation()
                let host = URL(string: base)?.host ?? base
                failures.append("\(host)：\(error.localizedDescription)")
            }
        }
        throw NSError(domain: "ABCD.500", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")])
    }

    private static func isValidMonthDay(_ value: String) -> Bool {
        guard value.range(of: #"^\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        return calendarDate(value, issue: "26001") != nil
    }

    private static func calendarDate(_ monthDay: String, issue: String) -> Date? {
        let parts = monthDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let issueYear = Int(issue.prefix(2)).map { 2000 + $0 } ?? Calendar.current.component(.year, from: Date())
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = issueYear
        components.month = parts[0]
        components.day = parts[1]
        guard let date = components.date else { return nil }
        let verified = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        return verified.month == parts[0] && verified.day == parts[1] ? date : nil
    }

    private static func primaryMatchDate(_ matches: [BeijingSingleMatch]) -> String? {
        let dates = matches.compactMap { match -> String? in
            let prefix = String(match.matchTime.prefix(5))
            return isValidMonthDay(prefix) ? prefix : nil
        }
        let counts = Dictionary(grouping: dates, by: { $0 }).mapValues(\.count)
        return counts.max { left, right in
            if left.value != right.value { return left.value < right.value }
            return left.key > right.key
        }?.key
    }

    private static func marketOddsByFixture(in html: String) -> [String: [Double]] {
        oddsByFixture(in: html, key: "0")
    }

    private static func handicapSPByFixture(in html: String) -> [String: [Double]] {
        oddsByFixture(in: html, key: "rqsp")
    }

    private static func oddsByFixture(in html: String, key: String) -> [String: [Double]] {
        guard let json = firstCapture(
            pattern: #"(?is)var\s+liveOddsList\s*=\s*(\{.*?\})\s*;"#,
            in: html
        ), let data = json.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: [Double]] = [:]
        for (fixtureID, rawEntry) in root {
            guard let entry = rawEntry as? [String: Any],
                  let rawOdds = entry[key] as? [Any] else { continue }
            let odds = rawOdds.compactMap { value -> Double? in
                if let text = value as? String { return Double(text) }
                if let number = value as? NSNumber { return number.doubleValue }
                return nil
            }
            if odds.count == 3 { result[fixtureID] = odds }
        }
        return result
    }

    static func decodeHTML(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    private static func normalizedNumber(_ input: String) -> Int? { Int(input) }

    private static func lastInteger(in text: String) -> String? {
        captures(pattern: #"(\d+)"#, in: text).compactMap(\.first).last
    }

    private static func firstSignedInteger(in text: String) -> Int? {
        firstCapture(pattern: #"([+-]?\d+)"#, in: text).flatMap(Int.init)
    }

    private static func linkTexts(in html: String) -> [String] {
        captures(pattern: #"(?is)<a\b[^>]*>(.*?)</a>"#, in: html)
            .compactMap(\.first)
            .map(plainText)
            .filter { !$0.isEmpty }
    }

    fileprivate static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func captures(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }
        }
    }

    fileprivate static func firstCapture(pattern: String, in text: String) -> String? {
        captures(pattern: pattern, in: text).first?.first
    }
}

enum PoissonGoalModel {
    private static let maximumGoals = 10
    private static let dixonColesRho = -0.08

    static func analyze(_ match: BeijingSingleMatch) throws -> GoalModelAnalysis {
        let match = match.resultBlindCopy
        guard let handicap = match.handicap else {
            throw GoalModelError.handicapUnavailable(match.matchNumber)
        }
        let fittingOdds = match.marketOdds.count == 3 ? match.marketOdds : match.referenceSP
        let fittingHandicap = match.marketOdds.count == 3 ? 0 : handicap
        guard fittingOdds.count == 3 else {
            throw GoalModelError.oddsUnavailable(match.matchNumber)
        }
        let inverse = fittingOdds.map { 1 / $0 }
        let inverseTotal = inverse.reduce(0, +)
        let target = inverse.map { $0 / inverseTotal }
        let fitted = fitExpectedGoals(target: target, handicap: fittingHandicap)
        let matrix = scoreMatrix(homeLambda: fitted.home, awayLambda: fitted.away)
        let handicapProbabilities = resultProbabilities(matrix: matrix, handicap: handicap)
        let normalProbabilities = resultProbabilities(matrix: matrix, handicap: 0)

        var over = 0.0
        var bothTeams = 0.0
        var scores: [ScoreProbability] = []
        for home in 0...maximumGoals {
            for away in 0...maximumGoals {
                let probability = matrix[home][away]
                if home + away >= 3 { over += probability }
                if home > 0, away > 0 { bothTeams += probability }
                if home <= 5, away <= 5 {
                    scores.append(ScoreProbability(homeGoals: home, awayGoals: away, probability: probability))
                }
            }
        }
        scores.sort {
            if abs($0.probability - $1.probability) > 1e-15 { return $0.probability > $1.probability }
            if $0.homeGoals != $1.homeGoals { return $0.homeGoals < $1.homeGoals }
            return $0.awayGoals < $1.awayGoals
        }
        let logic = recommendedLogic(for: handicapProbabilities)

        return GoalModelAnalysis(
            match: match,
            homeExpectedGoals: fitted.home,
            awayExpectedGoals: fitted.away,
            handicapProbabilities: handicapProbabilities,
            normalProbabilities: normalProbabilities,
            overTwoPointFiveProbability: over,
            bothTeamsScoreProbability: bothTeams,
            topScores: Array(scores.prefix(3)),
            recommendedLogic: logic.mapping,
            exactLogicPattern: logic.exact,
            fitError: fitted.error
        )
    }

    static func recommendedLogic(for probabilities: [Double]) -> (mapping: LogicMapping, exact: Bool) {
        precondition(probabilities.count == 3)
        let orderedIndices = probabilities.indices.sorted {
            if abs(probabilities[$0] - probabilities[$1]) > 1e-12 {
                return probabilities[$0] > probabilities[$1]
            }
            return $0 < $1
        }
        var values = [0, 0, 0]
        for (rank, index) in orderedIndices.enumerated() { values[index] = rank + 2 }
        let exact = LogicMapping.allCases.first { $0.values == values }
        if let exact { return (exact, true) }

        let closest = LogicMapping.allCases.min { left, right in
            squaredDistance(left.values, values) < squaredDistance(right.values, values)
        } ?? .a
        return (closest, false)
    }

    private static func squaredDistance(_ lhs: [Int], _ rhs: [Int]) -> Int {
        zip(lhs, rhs).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
    }

    private static func fitExpectedGoals(target: [Double], handicap: Int) -> (home: Double, away: Double, error: Double) {
        var best = (home: 1.3, away: 1.1, error: Double.greatestFiniteMagnitude)
        for homeIndex in 2...45 {
            let home = Double(homeIndex) / 10
            for awayIndex in 2...45 {
                let away = Double(awayIndex) / 10
                let error = fitError(home: home, away: away, target: target, handicap: handicap)
                if error < best.error { best = (home, away, error) }
            }
        }

        let startHome = max(0.05, best.home - 0.12)
        let startAway = max(0.05, best.away - 0.12)
        for homeIndex in 0...24 {
            let home = startHome + Double(homeIndex) * 0.01
            for awayIndex in 0...24 {
                let away = startAway + Double(awayIndex) * 0.01
                let error = fitError(home: home, away: away, target: target, handicap: handicap)
                if error < best.error { best = (home, away, error) }
            }
        }
        return best
    }

    private static func fitError(home: Double, away: Double, target: [Double], handicap: Int) -> Double {
        let probabilities = resultProbabilities(
            matrix: scoreMatrix(homeLambda: home, awayLambda: away),
            handicap: handicap
        )
        return zip(probabilities, target).reduce(0) {
            let delta = $1.0 - $1.1
            return $0 + delta * delta
        }
    }

    private static func resultProbabilities(matrix: [[Double]], handicap: Int) -> [Double] {
        var result = [0.0, 0.0, 0.0]
        for home in 0...maximumGoals {
            for away in 0...maximumGoals {
                let adjustedDifference = home + handicap - away
                let index = adjustedDifference > 0 ? 0 : (adjustedDifference == 0 ? 1 : 2)
                result[index] += matrix[home][away]
            }
        }
        let total = result.reduce(0, +)
        return result.map { $0 / total }
    }

    private static func scoreMatrix(homeLambda: Double, awayLambda: Double) -> [[Double]] {
        let home = poissonProbabilities(lambda: homeLambda)
        let away = poissonProbabilities(lambda: awayLambda)
        var matrix = Array(
            repeating: Array(repeating: 0.0, count: maximumGoals + 1),
            count: maximumGoals + 1
        )
        var total = 0.0
        for homeGoals in 0...maximumGoals {
            for awayGoals in 0...maximumGoals {
                var adjustment = 1.0
                switch (homeGoals, awayGoals) {
                case (0, 0): adjustment = 1 - homeLambda * awayLambda * dixonColesRho
                case (0, 1): adjustment = 1 + homeLambda * dixonColesRho
                case (1, 0): adjustment = 1 + awayLambda * dixonColesRho
                case (1, 1): adjustment = 1 - dixonColesRho
                default: break
                }
                let value = max(0, home[homeGoals] * away[awayGoals] * adjustment)
                matrix[homeGoals][awayGoals] = value
                total += value
            }
        }
        for homeGoals in 0...maximumGoals {
            for awayGoals in 0...maximumGoals {
                matrix[homeGoals][awayGoals] /= total
            }
        }
        return matrix
    }

    private static func poissonProbabilities(lambda: Double) -> [Double] {
        var probabilities = Array(repeating: 0.0, count: maximumGoals + 1)
        probabilities[0] = exp(-lambda)
        if maximumGoals > 0 {
            for goals in 1...maximumGoals {
                probabilities[goals] = probabilities[goals - 1] * lambda / Double(goals)
            }
        }
        return probabilities
    }
}
