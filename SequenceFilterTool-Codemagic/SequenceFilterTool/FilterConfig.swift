import Foundation

enum LogicMapping: String, CaseIterable, Sendable {
    case a
    case b
    case c
    case d

    /// Values align with the outcome order 3, 1, 0.
    var values: [Int] {
        switch self {
        case .a: return [2, 3, 4]
        case .b: return [2, 4, 3]
        case .c: return [3, 4, 2]
        case .d: return [4, 3, 2]
        }
    }

    func value(for outcome: Int) -> Int {
        switch outcome {
        case 3: return values[0]
        case 1: return values[1]
        default: return values[2]
        }
    }

    var displayName: String { rawValue.uppercased() }

    /// VIP2–VIP4的ABCD统一入口：只根据项目对照表换算后的
    /// 让球胜/平/负欧赔排序生成，不读取外部ABCD或页面让球SP。
    static func derivedFromComparisonTableOdds(_ odds: [Double]) -> LogicMapping? {
        guard odds.count == 3,
              odds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let inverse = odds.map { 1 / $0 }
        let total = inverse.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        let probabilities = inverse.map { $0 / total }
        let orderedIndices = probabilities.indices.sorted {
            if abs(probabilities[$0] - probabilities[$1]) > 1e-12 {
                return probabilities[$0] > probabilities[$1]
            }
            return $0 < $1
        }
        var rankedValues = [0, 0, 0]
        for (rank, index) in orderedIndices.enumerated() {
            rankedValues[index] = rank + 2
        }
        if let exact = allCases.first(where: { $0.values == rankedValues }) {
            return exact
        }
        return allCases.min { left, right in
            let leftDistance = zip(left.values, rankedValues).reduce(0) {
                $0 + ($1.0 - $1.1) * ($1.0 - $1.1)
            }
            let rightDistance = zip(right.values, rankedValues).reduce(0) {
                $0 + ($1.0 - $1.1) * ($1.0 - $1.1)
            }
            return leftDistance < rightDistance
        }
    }
}

struct ExtraMatchSelection: Equatable, Sendable {
    let matchNumber: String
    let outcomes: [Int]

    var compactOutcomes: String { outcomes.map(String.init).joined() }
    var labeledNotation: String {
        outcomes.count == 1
            ? "\(matchNumber)→\(outcomes[0])"
            : "\(matchNumber)→(\(compactOutcomes))"
    }
}

/// 只统计主场的原始彩果（3/1/0），顺序与输入一致。
enum OutcomeCondition: String, CaseIterable, Sendable {
    case wins = "WINS", draws = "DRAWS", losses = "LOSSES"
    case winRun = "WRUN", drawRun = "DRUN", lossRun = "LRUN"
    case diversity = "KINDS", outcomeSum = "OSUM", returns = "RETURN", winLossSwitches = "WLSWITCH"
    case adjacentDrawPairs = "DPAIR", nonDrawRun = "NDRUN"
    case winDrawSwitches = "WDSWITCH", drawLossSwitches = "DLSWITCH", drawSegments = "DSEG"
    case adjacentWinPairs = "WPAIR", adjacentLossPairs = "LPAIR"
    case differentTriples = "DIFF3", isolatedWins = "ISOWIN", lossSegments = "LSEG"

    case hpTRI1 = "TRI1"
    case hpP211 = "P211"
    case hpNONP3 = "NONP3"
    case hpP113 = "P113"
    case hpP131 = "P131"
    case hpP110 = "P110"
    case hpP101 = "P101"
    case hpMAXCOUNT = "MAXCOUNT"
    case hpP203 = "P203"
    case hpP213 = "P213"
    case hpP231 = "P231"
    case hpP201 = "P201"
    case hpP210 = "P210"
    case hpSAMEPAIR = "SAMEPAIR"
    case hpRET3 = "RET3"
    case hpRET0 = "RET0"
    case hpRET1 = "RET1"
    case hpEQ3 = "EQ3"
    case hpP333 = "P333"
    case hpP330 = "P330"
    case hpP303 = "P303"
    case hpP300 = "P300"
    case hpP301 = "P301"
    case hpP331 = "P331"
    case hpP313 = "P313"
    case hpP310 = "P310"
    case hpP311 = "P311"
    case hpTRI3 = "TRI3"
    case hpTRI0 = "TRI0"
    case hpHDOSUM = "HDOSUM"
    case hpHD0 = "HD0"
    case hpHD3 = "HD3"
    case hpHD1 = "HD1"
    case hpSAMETRI = "SAMETRI"
    case hpP233 = "P233"

    case h98R001 = "H98_001"
    case h98R002 = "H98_002"
    case h98R003 = "H98_003"
    case h98R004 = "H98_004"
    case h98R005 = "H98_005"
    case h98R006 = "H98_006"
    case h98R007 = "H98_007"
    case h98R008 = "H98_008"
    case h98R009 = "H98_009"
    case h98R010 = "H98_010"
    case h98R011 = "H98_011"
    case h98R012 = "H98_012"
    case h98R013 = "H98_013"
    case h98R014 = "H98_014"
    case h98R015 = "H98_015"
    case h98R016 = "H98_016"
    case h98R017 = "H98_017"
    case h98R018 = "H98_018"
    case h98R019 = "H98_019"
    case h98R020 = "H98_020"
    case h98R021 = "H98_021"
    case h98R022 = "H98_022"
    case h98R023 = "H98_023"
    case h98R024 = "H98_024"
    case h98R025 = "H98_025"
    case h98R026 = "H98_026"
    case h98R027 = "H98_027"
    case h98R028 = "H98_028"
    case h98R029 = "H98_029"
    case h98R030 = "H98_030"
    case h98R031 = "H98_031"
    case h98R032 = "H98_032"
    case h98R033 = "H98_033"
    case h98R034 = "H98_034"
    case h98R035 = "H98_035"
    case h98R036 = "H98_036"
    case h98R037 = "H98_037"
    case h98R038 = "H98_038"
    case h98R039 = "H98_039"
    case h98R040 = "H98_040"
    case h98R041 = "H98_041"
    case h98R042 = "H98_042"
    case h98R043 = "H98_043"
    case h98R044 = "H98_044"
    case h98R045 = "H98_045"
    case h98R046 = "H98_046"
    case h98R047 = "H98_047"
    case h98R048 = "H98_048"
    case h98R049 = "H98_049"
    case h98R050 = "H98_050"
    case h98R051 = "H98_051"
    case h98R052 = "H98_052"
    case h98R053 = "H98_053"
    case h98R054 = "H98_054"
    case h98R055 = "H98_055"
    case h98R056 = "H98_056"
    case h98R057 = "H98_057"
    case h98R058 = "H98_058"
    case h98R059 = "H98_059"
    case h98R060 = "H98_060"
    case h98R061 = "H98_061"
    case h98R062 = "H98_062"
    case h98R063 = "H98_063"
    case h98R064 = "H98_064"
    case h98R065 = "H98_065"
    case h98R066 = "H98_066"
    case h98R067 = "H98_067"
    case h98R068 = "H98_068"
    case h98R069 = "H98_069"
    case h98R070 = "H98_070"
    case h98R071 = "H98_071"
    case h98R072 = "H98_072"
    case h98R073 = "H98_073"
    case h98R074 = "H98_074"
    case h98R075 = "H98_075"
    case h98R076 = "H98_076"
    case h98R077 = "H98_077"
    case h98R078 = "H98_078"
    case h98R079 = "H98_079"
    case h98R080 = "H98_080"
    case h98R081 = "H98_081"
    case h98R082 = "H98_082"
    case h98R083 = "H98_083"
    case h98R084 = "H98_084"
    case h98R085 = "H98_085"
    case h98R086 = "H98_086"
    case h98R087 = "H98_087"
    case h98R088 = "H98_088"
    case h98R089 = "H98_089"
    case h98R090 = "H98_090"
    case h98R091 = "H98_091"
    case h98R092 = "H98_092"
    case h98R093 = "H98_093"
    case h98R094 = "H98_094"
    case h98R095 = "H98_095"
    case h98R096 = "H98_096"
    case h98R097 = "H98_097"
    case h98R098 = "H98_098"
    case h98R099 = "H98_099"
    case h98R100 = "H98_100"

    case f98R001 = "F98_001"
    case f98R002 = "F98_002"
    case f98R003 = "F98_003"
    case f98R004 = "F98_004"
    case f98R005 = "F98_005"
    case f98R006 = "F98_006"
    case f98R007 = "F98_007"
    case f98R008 = "F98_008"
    case f98R009 = "F98_009"
    case f98R010 = "F98_010"
    case f98R011 = "F98_011"
    case f98R012 = "F98_012"
    case f98R013 = "F98_013"
    case f98R014 = "F98_014"
    case f98R015 = "F98_015"
    case f98R016 = "F98_016"
    case f98R017 = "F98_017"
    case f98R018 = "F98_018"
    case f98R019 = "F98_019"
    case f98R020 = "F98_020"
    case f98R021 = "F98_021"
    case f98R022 = "F98_022"
    case f98R023 = "F98_023"
    case f98R024 = "F98_024"
    case f98R025 = "F98_025"
    case f98R026 = "F98_026"
    case f98R027 = "F98_027"
    case f98R028 = "F98_028"
    case f98R029 = "F98_029"
    case f98R030 = "F98_030"
    case f98R031 = "F98_031"
    case f98R032 = "F98_032"
    case f98R033 = "F98_033"
    case f98R034 = "F98_034"
    case f98R035 = "F98_035"
    case f98R036 = "F98_036"
    case f98R037 = "F98_037"
    case f98R038 = "F98_038"
    case f98R039 = "F98_039"
    case f98R040 = "F98_040"
    case f98R041 = "F98_041"
    case f98R042 = "F98_042"
    case f98R043 = "F98_043"
    case f98R044 = "F98_044"
    case f98R045 = "F98_045"
    case f98R046 = "F98_046"
    case f98R047 = "F98_047"
    case f98R048 = "F98_048"
    case f98R049 = "F98_049"
    case f98R050 = "F98_050"

    static let highPassAdditions: [(condition: OutcomeCondition, range: ClosedRange<Int>)] = [
        (.adjacentDrawPairs, 0...1), (.nonDrawRun, 2...6), (.winDrawSwitches, 0...2),
        (.drawLossSwitches, 0...2), (.drawSegments, 0...2)
    ]

    static let highPass93Additions: [(condition: OutcomeCondition, range: ClosedRange<Int>)] =
        HighPass93Catalog.ordered.map { ($0.condition, $0.range) }
    var isHighPass93: Bool { HighPass93Catalog.byCondition[self] != nil }
    static let highPass98Additions: [(condition: OutcomeCondition, range: ClosedRange<Int>)] =
        HighPass98Catalog.ordered.map { ($0.condition, $0.range) }
    var isHighPass98: Bool { HighPass98Catalog.byCondition[self] != nil }
    static let highPass98FiftyAdditions: [(condition: OutcomeCondition, range: ClosedRange<Int>)] =
        HighPass98FiftyCatalog.ordered.map { ($0.condition, $0.range) }
    var isHighPass98Fifty: Bool { HighPass98FiftyCatalog.byCondition[self] != nil }

    /// “胜的总场数”已停用；保留枚举值只用于读取旧历史配置。
    static var activeCases: [OutcomeCondition] {
        allCases.filter { $0 != .wins }
    }

    /// Archived inputs keep their original predicates; current editors no
    /// longer offer the removed, nonconsecutive relative-position patterns.
    var isRelativePositionCondition: Bool {
        guard let definition = HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self] else { return false }
        if case .pattern(let offsets, _) = definition.metric {
            return offsets != Array(0..<offsets.count)
        }
        return false
    }
    static var editorCases: [OutcomeCondition] {
        activeCases.filter { !$0.isRelativePositionCondition }
    }

    var title: String {
        switch self {
        case .wins: return "胜的总场数"
        case .draws: return "平的总场数"
        case .losses: return "负的总场数"
        case .winRun: return "最长连续胜"
        case .drawRun: return "最长连续平"
        case .lossRun: return "最长连续负"
        case .diversity: return "彩果种类数"
        case .outcomeSum: return "彩果和值（3/1/0）"
        case .returns: return "隔场回返次数"
        case .winLossSwitches: return "胜负直接切换次数"
        case .adjacentDrawPairs: return "连续平局相邻对数"
        case .nonDrawRun: return "最长连续不平"
        case .winDrawSwitches: return "胜平直接切换次数"
        case .drawLossSwitches: return "平负直接切换次数"
        case .drawSegments: return "平局段数"
        case .adjacentWinPairs: return "连续胜相邻对数"
        case .adjacentLossPairs: return "连续负相邻对数"
        case .differentTriples: return "连续三场彩果全异次数"
        case .isolatedWins: return "孤立胜场数"
        case .lossSegments: return "负局段数"
        default: return (HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self])?.title ?? HighPass93Catalog.byCondition[self]!.title
        }
    }

    var help: String {
        switch self {
        case .wins, .draws, .losses: return "统计该彩果在主场中出现的总次数。"
        case .winRun, .drawRun, .lossRun: return "统计该彩果最长连续段的场数；未出现记0。例如33310的最长连续胜为3。"
        case .diversity: return "主场出现多少种彩果，范围1–3。"
        case .outcomeSum: return "原始彩果相加，例如31031的和值为8。"
        case .returns: return "连续三场首尾相同、中间不同记1次，可重叠；31313记3次。"
        case .winLossSwitches: return "相邻30或03各记1次；经过平局不计。"
        case .adjacentDrawPairs: return "相邻11记1对，可重叠；111记2对，两段分开的11也共记2对。"
        case .nonDrawRun: return "连续彩果都不是1的最长段长度；默认2–6要求六场中至少出现一次相邻两场都不平。"
        case .winDrawSwitches: return "相邻31或13各记1次；经过负不计。"
        case .drawLossSwitches: return "相邻10或01各记1次；经过胜不计。"
        case .drawSegments: return "每一段连续平局算1段；没有平局记0，111算1段，13101算3段。"
        case .adjacentWinPairs: return "六场中相邻33记1对，可重叠；333记2对，3333记3对。"
        case .adjacentLossPairs: return "六场中相邻00记1对，可重叠；000记2对，0000记3对。"
        case .differentTriples: return "六场中逐个查看连续三场，同时有3、1、0记1次，可重叠；31031记3次。"
        case .isolatedWins: return "六场中，胜的左右相邻场都不是胜时记1场；首尾只检查存在的一侧。313记2场，33记0场。"
        case .lossSegments: return "六场中每一段连续负算1段；没有负记0，000算1段，03010算3段。"
        default: return (HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self])?.help ?? HighPass93Catalog.byCondition[self]!.help
        }
    }

    func maximum(matchCount: Int) -> Int {
        switch self {
        case .diversity: return min(3, matchCount)
        case .outcomeSum: return 3 * matchCount
        case .returns, .differentTriples: return max(0, matchCount - 2)
        case .winLossSwitches, .winDrawSwitches, .drawLossSwitches, .adjacentDrawPairs,
             .adjacentWinPairs, .adjacentLossPairs:
            return max(0, matchCount - 1)
        case .drawSegments, .lossSegments, .isolatedWins: return (matchCount + 1) / 2
        default: return (HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self])?.metric.maximum(matchCount)
                ?? HighPass93Catalog.byCondition[self]?.metric.maximum(matchCount) ?? matchCount
        }
    }

    func value(in outcomes: [Int]) -> Int {
        switch self {
        case .wins, .draws, .losses:
            let target = self == .wins ? 3 : (self == .draws ? 1 : 0)
            return outcomes.filter { $0 == target }.count
        case .winRun, .drawRun, .lossRun:
            let target = self == .winRun ? 3 : (self == .drawRun ? 1 : 0)
            var longest = 0
            var current = 0
            for outcome in outcomes {
                current = outcome == target ? current + 1 : 0
                longest = max(longest, current)
            }
            return longest
        case .diversity: return Set(outcomes).count
        case .outcomeSum: return outcomes.reduce(0, +)
        case .returns:
            guard outcomes.count >= 3 else { return 0 }
            var count = 0
            for index in 2..<outcomes.count {
                let repeats = outcomes[index] == outcomes[index - 2]
                let differentMiddle = outcomes[index] != outcomes[index - 1]
                if repeats && differentMiddle { count += 1 }
            }
            return count
        case .winLossSwitches:
            return zip(outcomes, outcomes.dropFirst()).filter {
                ($0 == 3 && $1 == 0) || ($0 == 0 && $1 == 3)
            }.count
        case .adjacentDrawPairs:
            return zip(outcomes, outcomes.dropFirst()).filter { $0 == 1 && $1 == 1 }.count
        case .nonDrawRun:
            return ConsecutiveRunCondition.nonDraw.longestRun(in: outcomes)
        case .winDrawSwitches:
            return zip(outcomes, outcomes.dropFirst()).filter {
                ($0 == 3 && $1 == 1) || ($0 == 1 && $1 == 3)
            }.count
        case .drawLossSwitches:
            return zip(outcomes, outcomes.dropFirst()).filter {
                ($0 == 1 && $1 == 0) || ($0 == 0 && $1 == 1)
            }.count
        case .drawSegments:
            return outcomes.indices.filter { outcomes[$0] == 1 && ($0 == 0 || outcomes[$0 - 1] != 1) }.count
        case .adjacentWinPairs, .adjacentLossPairs:
            let target = self == .adjacentWinPairs ? 3 : 0
            return zip(outcomes, outcomes.dropFirst()).filter { $0 == target && $1 == target }.count
        case .differentTriples:
            guard outcomes.count >= 3 else { return 0 }
            return (2..<outcomes.count).filter { Set(outcomes[($0 - 2)...$0]).count == 3 }.count
        case .isolatedWins:
            return outcomes.indices.filter { outcomes[$0] == 3
                && ($0 == 0 || outcomes[$0 - 1] != 3)
                && ($0 + 1 == outcomes.count || outcomes[$0 + 1] != 3) }.count
        case .lossSegments:
            return outcomes.indices.filter { outcomes[$0] == 0 && ($0 == 0 || outcomes[$0 - 1] != 0) }.count
        default: return (HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self])?.metric.value(outcomes)
                ?? HighPass93Catalog.byCondition[self]!.metric.value(outcomes)
        }
    }

    /// These counts apply only to the frozen default range and existing six-match dataset.
    func highPassHistoricalReference(rangeText: String) -> String? {
        guard let range = (Self.highPassAdditions + Self.highPass93Additions + Self.highPass98Additions + Self.highPass98FiftyAdditions).first(where: { $0.condition == self })?.range,
              rangeText.replacingOccurrences(of: "–", with: "-").trimmingCharacters(in: .whitespaces)
                == "\(range.lowerBound)-\(range.upperBound)" else { return nil }
        let counts: (Int, Int, Int)
        switch self {
        case .adjacentDrawPairs: counts = (2254, 1752, 636)
        case .nonDrawRun: counts = (2269, 1769, 644)
        case .winDrawSwitches: counts = (2234, 1729, 655)
        case .drawLossSwitches: counts = (2255, 1739, 655)
        case .drawSegments: counts = (2329, 1811, 685)
        case .adjacentWinPairs: counts = (2303, 1761, 704)
        case .adjacentLossPairs: counts = (2322, 1810, 704)
        case .differentTriples: counts = (2327, 1782, 687)
        case .isolatedWins: counts = (2313, 1784, 697)
        case .lossSegments: counts = (2289, 1753, 685)
        default:
            if let definition = HighPass98FiftyCatalog.byCondition[self] ?? HighPass98Catalog.byCondition[self] {
                counts = (definition.hits2025, definition.hits2026, definition.retainedBets)
            } else if let definition = HighPass93Catalog.byCondition[self] {
                counts = (definition.hits2025, definition.hits2026, definition.retainedBets)
            } else { return nil }
        }
        return String(format: "默认范围单项历史：2025 %d/2439＝%.2f%%；2026 %d/1884＝%.2f%%。每组保留%d/729注，过滤%.2f%%。第7场不计；修改范围需重算，各项不能相乘作为总过关率，历史不保证未来。",
            counts.0, Double(counts.0) / 2439 * 100, counts.1, Double(counts.1) / 1884 * 100,
            counts.2, Double(729 - counts.2) / 729 * 100)
    }
}

// BEGIN GENERATED HIGH PASS 93 CATALOG
// Frozen absolute count/structure rules. Historical percentages are references,
// never runtime thresholds. Regenerate with Analysis/generate_svvv93_catalog_20261031.py.
enum SixMatchCountMetric: Sendable {
    case pair(Int, Int, Int), sameTriple(Int), returnTo(Int), isolated(Int), segments(Int)
    case nonPair(Int), halfCountDifference(Int), equalDistance(Int)
    case samePairs, allSameTriple, differentTriple, halfSumDifference, maxCount
    case pattern([Int], [Int])

    func maximum(_ n: Int) -> Int {
        switch self {
        case .pair(let d, _, _), .equalDistance(let d): return max(0, n - d)
        case .samePairs, .nonPair: return max(0, n - 1)
        case .sameTriple, .returnTo, .allSameTriple, .differentTriple: return max(0, n - 2)
        case .isolated, .segments: return (n + 1) / 2
        case .halfCountDifference: return (n + 1) / 2
        case .halfSumDifference: return 3 * ((n + 1) / 2)
        case .maxCount: return n
        case .pattern(let offsets, _): return max(0, n - (offsets.last ?? n))
        }
    }

    func value(_ o: [Int]) -> Int {
        switch self {
        case .pair(let d, let a, let b):
            guard o.count > d else { return 0 }
            return (0..<(o.count - d)).filter { o[$0] == a && o[$0 + d] == b }.count
        case .sameTriple(let a):
            guard o.count >= 3 else { return 0 }
            return (2..<o.count).filter { o[$0] == a && o[$0 - 1] == a && o[$0 - 2] == a }.count
        case .returnTo(let a):
            guard o.count >= 3 else { return 0 }
            return (2..<o.count).filter { o[$0] == a && o[$0 - 2] == a && o[$0 - 1] != a }.count
        case .isolated(let a):
            return o.indices.filter { o[$0] == a && ($0 == 0 || o[$0 - 1] != a)
                && ($0 + 1 == o.count || o[$0 + 1] != a) }.count
        case .segments(let a):
            return o.indices.filter { o[$0] == a && ($0 == 0 || o[$0 - 1] != a) }.count
        case .nonPair(let a): return zip(o, o.dropFirst()).filter { $0 != a && $1 != a }.count
        case .halfCountDifference(let a):
            return abs(o.prefix(o.count / 2).filter { $0 == a }.count - o.dropFirst(o.count / 2).filter { $0 == a }.count)
        case .equalDistance(let d):
            guard o.count > d else { return 0 }
            return (0..<(o.count - d)).filter { o[$0] == o[$0 + d] }.count
        case .samePairs: return zip(o, o.dropFirst()).filter { $0 == $1 }.count
        case .allSameTriple:
            guard o.count >= 3 else { return 0 }
            return (2..<o.count).filter { o[$0] == o[$0 - 1] && o[$0] == o[$0 - 2] }.count
        case .differentTriple:
            guard o.count >= 3 else { return 0 }
            return (2..<o.count).filter { Set(o[($0 - 2)...$0]).count == 3 }.count
        case .halfSumDifference: return abs(o.prefix(o.count / 2).reduce(0, +) - o.dropFirst(o.count / 2).reduce(0, +))
        case .maxCount: return [3, 1, 0].map { a in o.filter { $0 == a }.count }.max() ?? 0
        case .pattern(let offsets, let targets):
            guard let span = offsets.last, o.count > span, offsets.count == targets.count else { return 0 }
            var count = 0
            for start in 0..<(o.count - span) {
                var matched = true
                for (offset, target) in zip(offsets, targets) where o[start + offset] != target {
                    matched = false
                    break
                }
                if matched { count += 1 }
            }
            return count
        }
    }
}

struct HighPass93Definition: Sendable {
    let condition: OutcomeCondition
    let title: String
    let help: String
    let metric: SixMatchCountMetric
    let range: ClosedRange<Int>
    let hits2025: Int
    let hits2026: Int
    let retainedBets: Int
}

enum HighPass93Catalog {
    static let ordered: [HighPass93Definition] = [
        .init(condition: .adjacentWinPairs, title: "连续胜相邻对数", help: "只在本组六场内，比较第i场与第i+1场，前者为胜、后者为胜记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 3, 3), range: 0...2, hits2025: 2303, hits2026: 1761, retainedBets: 704),
        .init(condition: .adjacentLossPairs, title: "连续负相邻对数", help: "只在本组六场内，比较第i场与第i+1场，前者为负、后者为负记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 0, 0), range: 0...2, hits2025: 2322, hits2026: 1810, retainedBets: 704),
        .init(condition: .differentTriples, title: "连续三场彩果全异次数", help: "本组六场逐个查看连续三场，同时有3、1、0记1次，可重叠。", metric: .differentTriple, range: 0...2, hits2025: 2327, hits2026: 1782, retainedBets: 687),
        .init(condition: .isolatedWins, title: "孤立胜场数", help: "本组六场中，胜的左右邻场都不是胜记1场；首尾只检查存在的一侧。", metric: .isolated(3), range: 0...2, hits2025: 2313, hits2026: 1784, retainedBets: 697),
        .init(condition: .lossSegments, title: "负局段数", help: "本组六场中每段连续负算1段，没有负记0；000算1段，03010算3段。", metric: .segments(0), range: 0...2, hits2025: 2289, hits2026: 1753, retainedBets: 685),
        .init(condition: .hpTRI1, title: "连续三场全平次数", help: "本组六场的每个连续三场窗口都为平时记1次；窗口可重叠。", metric: .sameTriple(1), range: 0...0, hits2025: 2273, hits2026: 1772, retainedBets: 648),
        .init(condition: .hpP211, title: "间距2的平到平次数", help: "只在本组六场内，比较第i场与第i+2场，前者为平、后者为平记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 1, 1), range: 0...1, hits2025: 2292, hits2026: 1791, retainedBets: 660),
        .init(condition: .hpNONP3, title: "相邻两场都非胜的对数", help: "本组六场中，相邻两场都不是胜记1对；可重叠。", metric: .nonPair(3), range: 0...4, hits2025: 2294, hits2026: 1780, retainedBets: 665),
        .init(condition: .hpP113, title: "间距1的平到胜次数", help: "只在本组六场内，比较第i场与第i+1场，前者为平、后者为胜记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 1, 3), range: 0...1, hits2025: 2293, hits2026: 1781, retainedBets: 677),
        .init(condition: .hpP131, title: "间距1的胜到平次数", help: "只在本组六场内，比较第i场与第i+1场，前者为胜、后者为平记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 3, 1), range: 0...1, hits2025: 2293, hits2026: 1788, retainedBets: 677),
        .init(condition: .hpP110, title: "间距1的平到负次数", help: "只在本组六场内，比较第i场与第i+1场，前者为平、后者为负记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 1, 0), range: 0...1, hits2025: 2310, hits2026: 1783, retainedBets: 677),
        .init(condition: .hpP101, title: "间距1的负到平次数", help: "只在本组六场内，比较第i场与第i+1场，前者为负、后者为平记1次；逐个位置计数，可重叠。间距1表示中间隔0场。", metric: .pair(1, 0, 1), range: 0...1, hits2025: 2323, hits2026: 1789, retainedBets: 677),
        .init(condition: .hpMAXCOUNT, title: "同一彩果最多场数", help: "本组六场分别统计胜、平、负的场数，取三个场数中的最大值。", metric: .maxCount, range: 0...4, hits2025: 2272, hits2026: 1767, retainedBets: 690),
        .init(condition: .hpP203, title: "间距2的负到胜次数", help: "只在本组六场内，比较第i场与第i+2场，前者为负、后者为胜记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 0, 3), range: 0...1, hits2025: 2288, hits2026: 1760, retainedBets: 693),
        .init(condition: .hpP213, title: "间距2的平到胜次数", help: "只在本组六场内，比较第i场与第i+2场，前者为平、后者为胜记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 1, 3), range: 0...1, hits2025: 2346, hits2026: 1795, retainedBets: 693),
        .init(condition: .hpP231, title: "间距2的胜到平次数", help: "只在本组六场内，比较第i场与第i+2场，前者为胜、后者为平记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 3, 1), range: 0...1, hits2025: 2327, hits2026: 1804, retainedBets: 693),
        .init(condition: .hpP201, title: "间距2的负到平次数", help: "只在本组六场内，比较第i场与第i+2场，前者为负、后者为平记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 0, 1), range: 0...1, hits2025: 2331, hits2026: 1808, retainedBets: 693),
        .init(condition: .hpP210, title: "间距2的平到负次数", help: "只在本组六场内，比较第i场与第i+2场，前者为平、后者为负记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 1, 0), range: 0...1, hits2025: 2344, hits2026: 1822, retainedBets: 693),
        .init(condition: .hpSAMEPAIR, title: "相邻同彩果对数", help: "本组六场中相邻彩果相同记1对；不区分胜平负，可重叠。", metric: .samePairs, range: 0...3, hits2025: 2312, hits2026: 1799, retainedBets: 696),
        .init(condition: .hpRET3, title: "胜隔场回返次数", help: "本组六场中，连续三场首尾都是胜、中间不是胜记1次；可重叠。", metric: .returnTo(3), range: 0...1, hits2025: 2304, hits2026: 1797, retainedBets: 701),
        .init(condition: .hpRET0, title: "负隔场回返次数", help: "本组六场中，连续三场首尾都是负、中间不是负记1次；可重叠。", metric: .returnTo(0), range: 0...1, hits2025: 2341, hits2026: 1798, retainedBets: 701),
        .init(condition: .hpRET1, title: "平隔场回返次数", help: "本组六场中，连续三场首尾都是平、中间不是平记1次；可重叠。", metric: .returnTo(1), range: 0...1, hits2025: 2374, hits2026: 1841, retainedBets: 701),
        .init(condition: .hpEQ3, title: "间距3彩果相同次数", help: "本组六场比较第i场与第i+3场，彩果相同记1次。", metric: .equalDistance(3), range: 0...2, hits2025: 2339, hits2026: 1824, retainedBets: 702),
        .init(condition: .hpP333, title: "间距3的胜到胜次数", help: "只在本组六场内，比较第i场与第i+3场，前者为胜、后者为胜记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 3, 3), range: 0...1, hits2025: 2298, hits2026: 1774, retainedBets: 704),
        .init(condition: .hpP330, title: "间距3的胜到负次数", help: "只在本组六场内，比较第i场与第i+3场，前者为胜、后者为负记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 3, 0), range: 0...1, hits2025: 2323, hits2026: 1786, retainedBets: 704),
        .init(condition: .hpP303, title: "间距3的负到胜次数", help: "只在本组六场内，比较第i场与第i+3场，前者为负、后者为胜记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 0, 3), range: 0...1, hits2025: 2338, hits2026: 1789, retainedBets: 704),
        .init(condition: .hpP300, title: "间距3的负到负次数", help: "只在本组六场内，比较第i场与第i+3场，前者为负、后者为负记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 0, 0), range: 0...1, hits2025: 2324, hits2026: 1818, retainedBets: 704),
        .init(condition: .hpP301, title: "间距3的负到平次数", help: "只在本组六场内，比较第i场与第i+3场，前者为负、后者为平记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 0, 1), range: 0...1, hits2025: 2374, hits2026: 1821, retainedBets: 704),
        .init(condition: .hpP331, title: "间距3的胜到平次数", help: "只在本组六场内，比较第i场与第i+3场，前者为胜、后者为平记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 3, 1), range: 0...1, hits2025: 2373, hits2026: 1826, retainedBets: 704),
        .init(condition: .hpP313, title: "间距3的平到胜次数", help: "只在本组六场内，比较第i场与第i+3场，前者为平、后者为胜记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 1, 3), range: 0...1, hits2025: 2369, hits2026: 1827, retainedBets: 704),
        .init(condition: .hpP310, title: "间距3的平到负次数", help: "只在本组六场内，比较第i场与第i+3场，前者为平、后者为负记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 1, 0), range: 0...1, hits2025: 2386, hits2026: 1838, retainedBets: 704),
        .init(condition: .hpP311, title: "间距3的平到平次数", help: "只在本组六场内，比较第i场与第i+3场，前者为平、后者为平记1次；逐个位置计数，可重叠。间距3表示中间隔2场。", metric: .pair(3, 1, 1), range: 0...1, hits2025: 2410, hits2026: 1857, retainedBets: 704),
        .init(condition: .hpTRI3, title: "连续三场全胜次数", help: "本组六场的每个连续三场窗口都为胜时记1次；窗口可重叠。", metric: .sameTriple(3), range: 0...1, hits2025: 2333, hits2026: 1782, retainedBets: 708),
        .init(condition: .hpTRI0, title: "连续三场全负次数", help: "本组六场的每个连续三场窗口都为负时记1次；窗口可重叠。", metric: .sameTriple(0), range: 0...1, hits2025: 2341, hits2026: 1823, retainedBets: 708),
        .init(condition: .hpHDOSUM, title: "前后三场彩果和值差", help: "本组前3场的3/1/0彩果和值与后3场和值之差的绝对值。", metric: .halfSumDifference, range: 0...6, hits2025: 2362, hits2026: 1806, retainedBets: 709),
        .init(condition: .hpHD0, title: "前后三场负场数差", help: "本组前3场的负场数与后3场的负场数之差的绝对值。", metric: .halfCountDifference(0), range: 0...2, hits2025: 2396, hits2026: 1830, retainedBets: 713),
        .init(condition: .hpHD3, title: "前后三场胜场数差", help: "本组前3场的胜场数与后3场的胜场数之差的绝对值。", metric: .halfCountDifference(3), range: 0...2, hits2025: 2374, hits2026: 1833, retainedBets: 713),
        .init(condition: .hpHD1, title: "前后三场平场数差", help: "本组前3场的平场数与后3场的平场数之差的绝对值。", metric: .halfCountDifference(1), range: 0...2, hits2025: 2405, hits2026: 1865, retainedBets: 713),
        .init(condition: .hpSAMETRI, title: "连续三场同彩果次数", help: "本组六场中每个连续三场窗口的彩果都相同时记1次；333、111、000均计，可重叠。", metric: .allSameTriple, range: 0...2, hits2025: 2374, hits2026: 1841, retainedBets: 714),
        .init(condition: .hpP233, title: "间距2的胜到胜次数", help: "只在本组六场内，比较第i场与第i+2场，前者为胜、后者为胜记1次；逐个位置计数，可重叠。间距2表示中间隔1场。", metric: .pair(2, 3, 3), range: 0...2, hits2025: 2387, hits2026: 1833, retainedBets: 720)
    ]
    static let byCondition = Dictionary(uniqueKeysWithValues: ordered.map { ($0.condition, $0) })
}
// END GENERATED HIGH PASS 93 CATALOG

// BEGIN GENERATED HIGH PASS 98 CATALOG
// Frozen count rules, not runtime probability thresholds.
struct HighPass98Definition: Sendable {
    let condition: OutcomeCondition
    let title: String
    let help: String
    let metric: SixMatchCountMetric
    let range: ClosedRange<Int>
    let hits2025: Int
    let hits2026: Int
    let retainedBets: Int
}
enum HighPass98Catalog {
    static let ordered: [HighPass98Definition] = [
        .init(condition: .h98R001, title: "连续2场彩果11次数", help: "在本组六场内逐个起点查看连续2场，依次为彩果11时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1], [1, 1]), range: 0...2, hits2025: 2397, hits2026: 1857, retainedBets: 704),
        .init(condition: .h98R002, title: "连续3场彩果111次数", help: "在本组六场内逐个起点查看连续3场，依次为彩果111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2], [1, 1, 1]), range: 0...1, hits2025: 2401, hits2026: 1864, retainedBets: 708),
        .init(condition: .h98R003, title: "相对位置1/2/3/5彩果0110次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果0110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [0, 1, 1, 0]), range: 0...0, hits2025: 2391, hits2026: 1854, retainedBets: 711),
        .init(condition: .h98R004, title: "相对位置1/2/3/5彩果0111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果0111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [0, 1, 1, 1]), range: 0...0, hits2025: 2409, hits2026: 1861, retainedBets: 711),
        .init(condition: .h98R005, title: "相对位置1/2/3/5彩果1010次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 0, 1, 0]), range: 0...0, hits2025: 2400, hits2026: 1852, retainedBets: 711),
        .init(condition: .h98R006, title: "相对位置1/2/3/5彩果1011次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 0, 1, 1]), range: 0...0, hits2025: 2403, hits2026: 1854, retainedBets: 711),
        .init(condition: .h98R007, title: "相对位置1/2/3/5彩果1031次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 0, 3, 1]), range: 0...0, hits2025: 2394, hits2026: 1856, retainedBets: 711),
        .init(condition: .h98R008, title: "相对位置1/2/3/5彩果1100次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 0, 0]), range: 0...0, hits2025: 2391, hits2026: 1861, retainedBets: 711),
        .init(condition: .h98R009, title: "相对位置1/2/3/5彩果1101次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 0, 1]), range: 0...0, hits2025: 2411, hits2026: 1854, retainedBets: 711),
        .init(condition: .h98R010, title: "相对位置1/2/3/5彩果1131次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 3, 1]), range: 0...0, hits2025: 2408, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R011, title: "相对位置1/2/3/5彩果1301次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1301时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 3, 0, 1]), range: 0...0, hits2025: 2395, hits2026: 1850, retainedBets: 711),
        .init(condition: .h98R012, title: "相对位置1/2/3/5彩果1310次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 3, 1, 0]), range: 0...0, hits2025: 2393, hits2026: 1859, retainedBets: 711),
        .init(condition: .h98R013, title: "相对位置1/2/3/5彩果3101次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果3101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [3, 1, 0, 1]), range: 0...0, hits2025: 2399, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R014, title: "相对位置1/2/3/5彩果3111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果3111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [3, 1, 1, 1]), range: 0...0, hits2025: 2402, hits2026: 1860, retainedBets: 711),
        .init(condition: .h98R015, title: "相对位置1/2/4/5彩果0101次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果0101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [0, 1, 0, 1]), range: 0...0, hits2025: 2401, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R016, title: "相对位置1/2/4/5彩果0110次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果0110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [0, 1, 1, 0]), range: 0...0, hits2025: 2393, hits2026: 1853, retainedBets: 711),
        .init(condition: .h98R017, title: "相对位置1/2/4/5彩果0111次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果0111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [0, 1, 1, 1]), range: 0...0, hits2025: 2399, hits2026: 1857, retainedBets: 711),
        .init(condition: .h98R018, title: "相对位置1/2/4/5彩果0113次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果0113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [0, 1, 1, 3]), range: 0...0, hits2025: 2403, hits2026: 1849, retainedBets: 711),
        .init(condition: .h98R019, title: "相对位置1/2/4/5彩果0311次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果0311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [0, 3, 1, 1]), range: 0...0, hits2025: 2391, hits2026: 1853, retainedBets: 711),
        .init(condition: .h98R020, title: "相对位置1/2/4/5彩果1001次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1001时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 0, 0, 1]), range: 0...0, hits2025: 2393, hits2026: 1856, retainedBets: 711),
        .init(condition: .h98R021, title: "相对位置1/2/4/5彩果1010次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 0, 1, 0]), range: 0...0, hits2025: 2402, hits2026: 1848, retainedBets: 711),
        .init(condition: .h98R022, title: "相对位置1/2/4/5彩果1011次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 0, 1, 1]), range: 0...0, hits2025: 2404, hits2026: 1857, retainedBets: 711),
        .init(condition: .h98R023, title: "相对位置1/2/4/5彩果1013次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 0, 1, 3]), range: 0...0, hits2025: 2402, hits2026: 1850, retainedBets: 711),
        .init(condition: .h98R024, title: "相对位置1/2/4/5彩果1101次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 0, 1]), range: 0...0, hits2025: 2402, hits2026: 1856, retainedBets: 711),
        .init(condition: .h98R025, title: "相对位置1/2/4/5彩果1110次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 1, 0]), range: 0...0, hits2025: 2401, hits2026: 1861, retainedBets: 711),
        .init(condition: .h98R026, title: "相对位置1/2/4/5彩果1113次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 1, 3]), range: 0...0, hits2025: 2403, hits2026: 1860, retainedBets: 711),
        .init(condition: .h98R027, title: "相对位置1/2/4/5彩果1131次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 3, 1]), range: 0...0, hits2025: 2407, hits2026: 1854, retainedBets: 711),
        .init(condition: .h98R028, title: "相对位置1/2/4/5彩果1310次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 3, 1, 0]), range: 0...0, hits2025: 2407, hits2026: 1851, retainedBets: 711),
        .init(condition: .h98R029, title: "相对位置1/2/4/5彩果1313次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1313时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 3, 1, 3]), range: 0...0, hits2025: 2400, hits2026: 1848, retainedBets: 711),
        .init(condition: .h98R030, title: "相对位置1/2/4/5彩果1331次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1331时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 3, 3, 1]), range: 0...0, hits2025: 2395, hits2026: 1848, retainedBets: 711),
        .init(condition: .h98R031, title: "相对位置1/2/4/5彩果3101次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果3101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [3, 1, 0, 1]), range: 0...0, hits2025: 2391, hits2026: 1856, retainedBets: 711),
        .init(condition: .h98R032, title: "相对位置1/2/4/5彩果3111次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果3111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [3, 1, 1, 1]), range: 0...0, hits2025: 2406, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R033, title: "相对位置1/3/4/5彩果0011次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果0011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [0, 0, 1, 1]), range: 0...0, hits2025: 2397, hits2026: 1850, retainedBets: 711),
        .init(condition: .h98R034, title: "相对位置1/3/4/5彩果0113次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果0113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [0, 1, 1, 3]), range: 0...0, hits2025: 2399, hits2026: 1848, retainedBets: 711),
        .init(condition: .h98R035, title: "相对位置1/3/4/5彩果1011次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 0, 1, 1]), range: 0...0, hits2025: 2407, hits2026: 1855, retainedBets: 711),
        .init(condition: .h98R036, title: "相对位置1/3/4/5彩果1013次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 0, 1, 3]), range: 0...0, hits2025: 2393, hits2026: 1850, retainedBets: 711),
        .init(condition: .h98R037, title: "相对位置1/3/4/5彩果1031次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 0, 3, 1]), range: 0...0, hits2025: 2395, hits2026: 1849, retainedBets: 711),
        .init(condition: .h98R038, title: "相对位置1/3/4/5彩果1100次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 0, 0]), range: 0...0, hits2025: 2394, hits2026: 1852, retainedBets: 711),
        .init(condition: .h98R039, title: "相对位置1/3/4/5彩果1101次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 0, 1]), range: 0...0, hits2025: 2396, hits2026: 1865, retainedBets: 711),
        .init(condition: .h98R040, title: "相对位置1/3/4/5彩果1110次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 1, 0]), range: 0...0, hits2025: 2417, hits2026: 1867, retainedBets: 711),
        .init(condition: .h98R041, title: "相对位置1/3/4/5彩果1113次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 1, 3]), range: 0...0, hits2025: 2404, hits2026: 1861, retainedBets: 711),
        .init(condition: .h98R042, title: "相对位置1/3/4/5彩果1131次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 3, 1]), range: 0...0, hits2025: 2397, hits2026: 1856, retainedBets: 711),
        .init(condition: .h98R043, title: "相对位置1/3/4/5彩果1301次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1301时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 3, 0, 1]), range: 0...0, hits2025: 2392, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R044, title: "相对位置1/3/4/5彩果1310次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 3, 1, 0]), range: 0...0, hits2025: 2394, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R045, title: "相对位置1/3/4/5彩果1311次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 3, 1, 1]), range: 0...0, hits2025: 2399, hits2026: 1858, retainedBets: 711),
        .init(condition: .h98R046, title: "相对位置1/3/4/5彩果1313次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1313时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 3, 1, 3]), range: 0...0, hits2025: 2408, hits2026: 1847, retainedBets: 711),
        .init(condition: .h98R047, title: "相对位置1/3/4/5彩果1331次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1331时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 3, 3, 1]), range: 0...0, hits2025: 2394, hits2026: 1849, retainedBets: 711),
        .init(condition: .h98R048, title: "相对位置1/2/3/5彩果1110次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 1, 0]), range: 0...0, hits2025: 2405, hits2026: 1860, retainedBets: 712),
        .init(condition: .h98R049, title: "相对位置1/2/3/5彩果1111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 1, 1]), range: 0...0, hits2025: 2408, hits2026: 1872, retainedBets: 712),
        .init(condition: .h98R050, title: "相对位置1/2/3/5彩果1113次数", help: "在本组六场内逐个起点查看相对位置1/2/3/5，依次为彩果1113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 4], [1, 1, 1, 3]), range: 0...0, hits2025: 2402, hits2026: 1866, retainedBets: 712),
        .init(condition: .h98R051, title: "相对位置1/2/4/5彩果1100次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 0, 0]), range: 0...0, hits2025: 2405, hits2026: 1853, retainedBets: 712),
        .init(condition: .h98R052, title: "相对位置1/2/4/5彩果1111次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果1111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [1, 1, 1, 1]), range: 0...0, hits2025: 2418, hits2026: 1863, retainedBets: 712),
        .init(condition: .h98R053, title: "相对位置1/2/4/5彩果3311次数", help: "在本组六场内逐个起点查看相对位置1/2/4/5，依次为彩果3311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 4], [3, 3, 1, 1]), range: 0...0, hits2025: 2394, hits2026: 1847, retainedBets: 712),
        .init(condition: .h98R054, title: "相对位置1/3/4/5彩果0111次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果0111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [0, 1, 1, 1]), range: 0...0, hits2025: 2407, hits2026: 1861, retainedBets: 712),
        .init(condition: .h98R055, title: "相对位置1/3/4/5彩果1111次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果1111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [1, 1, 1, 1]), range: 0...0, hits2025: 2405, hits2026: 1859, retainedBets: 712),
        .init(condition: .h98R056, title: "相对位置1/3/4/5彩果3111次数", help: "在本组六场内逐个起点查看相对位置1/3/4/5，依次为彩果3111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2, 3, 4], [3, 1, 1, 1]), range: 0...0, hits2025: 2405, hits2026: 1857, retainedBets: 712),
        .init(condition: .h98R057, title: "相对位置1/3彩果11次数", help: "在本组六场内逐个起点查看相对位置1/3，依次为彩果11时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 2], [1, 1]), range: 0...2, hits2025: 2426, hits2026: 1880, retainedBets: 720),
        .init(condition: .h98R058, title: "相对位置1/5彩果00次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果00时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [0, 0]), range: 0...1, hits2025: 2393, hits2026: 1857, retainedBets: 720),
        .init(condition: .h98R059, title: "相对位置1/5彩果01次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果01时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [0, 1]), range: 0...1, hits2025: 2412, hits2026: 1868, retainedBets: 720),
        .init(condition: .h98R060, title: "相对位置1/5彩果03次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果03时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [0, 3]), range: 0...1, hits2025: 2399, hits2026: 1847, retainedBets: 720),
        .init(condition: .h98R061, title: "相对位置1/5彩果10次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果10时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [1, 0]), range: 0...1, hits2025: 2410, hits2026: 1870, retainedBets: 720),
        .init(condition: .h98R062, title: "相对位置1/5彩果11次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果11时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [1, 1]), range: 0...1, hits2025: 2423, hits2026: 1866, retainedBets: 720),
        .init(condition: .h98R063, title: "相对位置1/5彩果13次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果13时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [1, 3]), range: 0...1, hits2025: 2413, hits2026: 1865, retainedBets: 720),
        .init(condition: .h98R064, title: "相对位置1/5彩果31次数", help: "在本组六场内逐个起点查看相对位置1/5，依次为彩果31时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 4], [3, 1]), range: 0...1, hits2025: 2409, hits2026: 1862, retainedBets: 720),
        .init(condition: .h98R065, title: "相对位置1/2/3/6彩果0000次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0000时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 0, 0]), range: 0...0, hits2025: 2396, hits2026: 1854, retainedBets: 720),
        .init(condition: .h98R066, title: "相对位置1/2/3/6彩果0001次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0001时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 0, 1]), range: 0...0, hits2025: 2410, hits2026: 1855, retainedBets: 720),
        .init(condition: .h98R067, title: "相对位置1/2/3/6彩果0003次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0003时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 0, 3]), range: 0...0, hits2025: 2394, hits2026: 1851, retainedBets: 720),
        .init(condition: .h98R068, title: "相对位置1/2/3/6彩果0010次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 1, 0]), range: 0...0, hits2025: 2413, hits2026: 1855, retainedBets: 720),
        .init(condition: .h98R069, title: "相对位置1/2/3/6彩果0011次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 1, 1]), range: 0...0, hits2025: 2417, hits2026: 1868, retainedBets: 720),
        .init(condition: .h98R070, title: "相对位置1/2/3/6彩果0013次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 1, 3]), range: 0...0, hits2025: 2409, hits2026: 1856, retainedBets: 720),
        .init(condition: .h98R071, title: "相对位置1/2/3/6彩果0030次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0030时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 3, 0]), range: 0...0, hits2025: 2395, hits2026: 1857, retainedBets: 720),
        .init(condition: .h98R072, title: "相对位置1/2/3/6彩果0031次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 3, 1]), range: 0...0, hits2025: 2413, hits2026: 1867, retainedBets: 720),
        .init(condition: .h98R073, title: "相对位置1/2/3/6彩果0033次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0033时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 0, 3, 3]), range: 0...0, hits2025: 2399, hits2026: 1855, retainedBets: 720),
        .init(condition: .h98R074, title: "相对位置1/2/3/6彩果0100次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 0, 0]), range: 0...0, hits2025: 2416, hits2026: 1860, retainedBets: 720),
        .init(condition: .h98R075, title: "相对位置1/2/3/6彩果0101次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 0, 1]), range: 0...0, hits2025: 2421, hits2026: 1866, retainedBets: 720),
        .init(condition: .h98R076, title: "相对位置1/2/3/6彩果0103次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0103时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 0, 3]), range: 0...0, hits2025: 2403, hits2026: 1864, retainedBets: 720),
        .init(condition: .h98R077, title: "相对位置1/2/3/6彩果0110次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 1, 0]), range: 0...0, hits2025: 2424, hits2026: 1865, retainedBets: 720),
        .init(condition: .h98R078, title: "相对位置1/2/3/6彩果0111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 1, 1]), range: 0...0, hits2025: 2424, hits2026: 1871, retainedBets: 720),
        .init(condition: .h98R079, title: "相对位置1/2/3/6彩果0113次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 1, 3]), range: 0...0, hits2025: 2415, hits2026: 1870, retainedBets: 720),
        .init(condition: .h98R080, title: "相对位置1/2/3/6彩果0130次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0130时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 3, 0]), range: 0...0, hits2025: 2411, hits2026: 1866, retainedBets: 720),
        .init(condition: .h98R081, title: "相对位置1/2/3/6彩果0131次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 3, 1]), range: 0...0, hits2025: 2416, hits2026: 1872, retainedBets: 720),
        .init(condition: .h98R082, title: "相对位置1/2/3/6彩果0133次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0133时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 1, 3, 3]), range: 0...0, hits2025: 2417, hits2026: 1854, retainedBets: 720),
        .init(condition: .h98R083, title: "相对位置1/2/3/6彩果0300次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0300时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 0, 0]), range: 0...0, hits2025: 2398, hits2026: 1854, retainedBets: 720),
        .init(condition: .h98R084, title: "相对位置1/2/3/6彩果0301次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0301时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 0, 1]), range: 0...0, hits2025: 2406, hits2026: 1854, retainedBets: 720),
        .init(condition: .h98R085, title: "相对位置1/2/3/6彩果0310次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 1, 0]), range: 0...0, hits2025: 2413, hits2026: 1862, retainedBets: 720),
        .init(condition: .h98R086, title: "相对位置1/2/3/6彩果0311次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 1, 1]), range: 0...0, hits2025: 2420, hits2026: 1864, retainedBets: 720),
        .init(condition: .h98R087, title: "相对位置1/2/3/6彩果0313次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0313时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 1, 3]), range: 0...0, hits2025: 2406, hits2026: 1856, retainedBets: 720),
        .init(condition: .h98R088, title: "相对位置1/2/3/6彩果0330次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0330时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 3, 0]), range: 0...0, hits2025: 2393, hits2026: 1853, retainedBets: 720),
        .init(condition: .h98R089, title: "相对位置1/2/3/6彩果0331次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0331时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 3, 1]), range: 0...0, hits2025: 2404, hits2026: 1862, retainedBets: 720),
        .init(condition: .h98R090, title: "相对位置1/2/3/6彩果0333次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果0333时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [0, 3, 3, 3]), range: 0...0, hits2025: 2400, hits2026: 1849, retainedBets: 720),
        .init(condition: .h98R091, title: "相对位置1/2/3/6彩果1000次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1000时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 0, 0]), range: 0...0, hits2025: 2402, hits2026: 1864, retainedBets: 720),
        .init(condition: .h98R092, title: "相对位置1/2/3/6彩果1001次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1001时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 0, 1]), range: 0...0, hits2025: 2416, hits2026: 1862, retainedBets: 720),
        .init(condition: .h98R093, title: "相对位置1/2/3/6彩果1003次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1003时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 0, 3]), range: 0...0, hits2025: 2399, hits2026: 1856, retainedBets: 720),
        .init(condition: .h98R094, title: "相对位置1/2/3/6彩果1010次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 1, 0]), range: 0...0, hits2025: 2417, hits2026: 1863, retainedBets: 720),
        .init(condition: .h98R095, title: "相对位置1/2/3/6彩果1011次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 1, 1]), range: 0...0, hits2025: 2420, hits2026: 1871, retainedBets: 720),
        .init(condition: .h98R096, title: "相对位置1/2/3/6彩果1013次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 1, 3]), range: 0...0, hits2025: 2416, hits2026: 1866, retainedBets: 720),
        .init(condition: .h98R097, title: "相对位置1/2/3/6彩果1030次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1030时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 3, 0]), range: 0...0, hits2025: 2414, hits2026: 1862, retainedBets: 720),
        .init(condition: .h98R098, title: "相对位置1/2/3/6彩果1031次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 3, 1]), range: 0...0, hits2025: 2416, hits2026: 1861, retainedBets: 720),
        .init(condition: .h98R099, title: "相对位置1/2/3/6彩果1033次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1033时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 0, 3, 3]), range: 0...0, hits2025: 2416, hits2026: 1858, retainedBets: 720),
        .init(condition: .h98R100, title: "相对位置1/2/3/6彩果1100次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 0, 0]), range: 0...0, hits2025: 2423, hits2026: 1868, retainedBets: 720)
    ]
    static let byCondition = Dictionary(uniqueKeysWithValues: ordered.map { ($0.condition, $0) })
}
// END GENERATED HIGH PASS 98 CATALOG

// BEGIN GENERATED HIGH PASS 98 FIFTY CATALOG
enum HighPass98FiftyCatalog {
    static let ordered: [HighPass98Definition] = [
        .init(condition: .f98R001, title: "相对位置1/2/3/6彩果1101次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 0, 1]), range: 0...0, hits2025: 2413, hits2026: 1876, retainedBets: 720),
        .init(condition: .f98R002, title: "相对位置1/2/3/6彩果1103次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1103时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 0, 3]), range: 0...0, hits2025: 2420, hits2026: 1863, retainedBets: 720),
        .init(condition: .f98R003, title: "相对位置1/2/3/6彩果1110次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 1, 0]), range: 0...0, hits2025: 2422, hits2026: 1876, retainedBets: 720),
        .init(condition: .f98R004, title: "相对位置1/2/3/6彩果1111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 1, 1]), range: 0...0, hits2025: 2426, hits2026: 1871, retainedBets: 720),
        .init(condition: .f98R005, title: "相对位置1/2/3/6彩果1113次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 1, 3]), range: 0...0, hits2025: 2415, hits2026: 1872, retainedBets: 720),
        .init(condition: .f98R006, title: "相对位置1/2/3/6彩果1130次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1130时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 3, 0]), range: 0...0, hits2025: 2411, hits2026: 1864, retainedBets: 720),
        .init(condition: .f98R007, title: "相对位置1/2/3/6彩果1131次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 3, 1]), range: 0...0, hits2025: 2425, hits2026: 1864, retainedBets: 720),
        .init(condition: .f98R008, title: "相对位置1/2/3/6彩果1133次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1133时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 1, 3, 3]), range: 0...0, hits2025: 2412, hits2026: 1866, retainedBets: 720),
        .init(condition: .f98R009, title: "相对位置1/2/3/6彩果1300次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1300时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 0, 0]), range: 0...0, hits2025: 2406, hits2026: 1868, retainedBets: 720),
        .init(condition: .f98R010, title: "相对位置1/2/3/6彩果1301次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1301时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 0, 1]), range: 0...0, hits2025: 2419, hits2026: 1868, retainedBets: 720),
        .init(condition: .f98R011, title: "相对位置1/2/3/6彩果1303次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1303时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 0, 3]), range: 0...0, hits2025: 2414, hits2026: 1849, retainedBets: 720),
        .init(condition: .f98R012, title: "相对位置1/2/3/6彩果1310次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 1, 0]), range: 0...0, hits2025: 2411, hits2026: 1863, retainedBets: 720),
        .init(condition: .f98R013, title: "相对位置1/2/3/6彩果1311次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 1, 1]), range: 0...0, hits2025: 2414, hits2026: 1869, retainedBets: 720),
        .init(condition: .f98R014, title: "相对位置1/2/3/6彩果1313次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1313时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 1, 3]), range: 0...0, hits2025: 2413, hits2026: 1868, retainedBets: 720),
        .init(condition: .f98R015, title: "相对位置1/2/3/6彩果1330次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1330时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 3, 0]), range: 0...0, hits2025: 2401, hits2026: 1858, retainedBets: 720),
        .init(condition: .f98R016, title: "相对位置1/2/3/6彩果1331次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1331时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 3, 1]), range: 0...0, hits2025: 2414, hits2026: 1865, retainedBets: 720),
        .init(condition: .f98R017, title: "相对位置1/2/3/6彩果1333次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果1333时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [1, 3, 3, 3]), range: 0...0, hits2025: 2401, hits2026: 1858, retainedBets: 720),
        .init(condition: .f98R018, title: "相对位置1/2/3/6彩果3000次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3000时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 0, 0]), range: 0...0, hits2025: 2405, hits2026: 1855, retainedBets: 720),
        .init(condition: .f98R019, title: "相对位置1/2/3/6彩果3001次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3001时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 0, 1]), range: 0...0, hits2025: 2414, hits2026: 1857, retainedBets: 720),
        .init(condition: .f98R020, title: "相对位置1/2/3/6彩果3003次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3003时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 0, 3]), range: 0...0, hits2025: 2401, hits2026: 1848, retainedBets: 720),
        .init(condition: .f98R021, title: "相对位置1/2/3/6彩果3010次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 1, 0]), range: 0...0, hits2025: 2407, hits2026: 1859, retainedBets: 720),
        .init(condition: .f98R022, title: "相对位置1/2/3/6彩果3011次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 1, 1]), range: 0...0, hits2025: 2416, hits2026: 1862, retainedBets: 720),
        .init(condition: .f98R023, title: "相对位置1/2/3/6彩果3013次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 1, 3]), range: 0...0, hits2025: 2407, hits2026: 1864, retainedBets: 720),
        .init(condition: .f98R024, title: "相对位置1/2/3/6彩果3031次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 3, 1]), range: 0...0, hits2025: 2409, hits2026: 1860, retainedBets: 720),
        .init(condition: .f98R025, title: "相对位置1/2/3/6彩果3033次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3033时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 0, 3, 3]), range: 0...0, hits2025: 2394, hits2026: 1856, retainedBets: 720),
        .init(condition: .f98R026, title: "相对位置1/2/3/6彩果3100次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 0, 0]), range: 0...0, hits2025: 2417, hits2026: 1862, retainedBets: 720),
        .init(condition: .f98R027, title: "相对位置1/2/3/6彩果3101次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 0, 1]), range: 0...0, hits2025: 2418, hits2026: 1865, retainedBets: 720),
        .init(condition: .f98R028, title: "相对位置1/2/3/6彩果3103次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3103时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 0, 3]), range: 0...0, hits2025: 2407, hits2026: 1857, retainedBets: 720),
        .init(condition: .f98R029, title: "相对位置1/2/3/6彩果3110次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3110时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 1, 0]), range: 0...0, hits2025: 2410, hits2026: 1869, retainedBets: 720),
        .init(condition: .f98R030, title: "相对位置1/2/3/6彩果3111次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3111时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 1, 1]), range: 0...0, hits2025: 2419, hits2026: 1870, retainedBets: 720),
        .init(condition: .f98R031, title: "相对位置1/2/3/6彩果3113次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3113时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 1, 3]), range: 0...0, hits2025: 2412, hits2026: 1866, retainedBets: 720),
        .init(condition: .f98R032, title: "相对位置1/2/3/6彩果3130次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3130时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 3, 0]), range: 0...0, hits2025: 2413, hits2026: 1854, retainedBets: 720),
        .init(condition: .f98R033, title: "相对位置1/2/3/6彩果3131次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3131时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 3, 1]), range: 0...0, hits2025: 2405, hits2026: 1867, retainedBets: 720),
        .init(condition: .f98R034, title: "相对位置1/2/3/6彩果3133次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3133时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 1, 3, 3]), range: 0...0, hits2025: 2404, hits2026: 1851, retainedBets: 720),
        .init(condition: .f98R035, title: "相对位置1/2/3/6彩果3301次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3301时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 3, 0, 1]), range: 0...0, hits2025: 2400, hits2026: 1860, retainedBets: 720),
        .init(condition: .f98R036, title: "相对位置1/2/3/6彩果3310次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3310时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 3, 1, 0]), range: 0...0, hits2025: 2405, hits2026: 1850, retainedBets: 720),
        .init(condition: .f98R037, title: "相对位置1/2/3/6彩果3311次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3311时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 3, 1, 1]), range: 0...0, hits2025: 2408, hits2026: 1868, retainedBets: 720),
        .init(condition: .f98R038, title: "相对位置1/2/3/6彩果3313次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3313时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 3, 1, 3]), range: 0...0, hits2025: 2403, hits2026: 1853, retainedBets: 720),
        .init(condition: .f98R039, title: "相对位置1/2/3/6彩果3331次数", help: "在本组六场内逐个起点查看相对位置1/2/3/6，依次为彩果3331时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 2, 5], [3, 3, 3, 1]), range: 0...0, hits2025: 2403, hits2026: 1853, retainedBets: 720),
        .init(condition: .f98R040, title: "相对位置1/2/4/6彩果0000次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0000时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 0, 0]), range: 0...0, hits2025: 2394, hits2026: 1860, retainedBets: 720),
        .init(condition: .f98R041, title: "相对位置1/2/4/6彩果0001次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0001时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 0, 1]), range: 0...0, hits2025: 2406, hits2026: 1864, retainedBets: 720),
        .init(condition: .f98R042, title: "相对位置1/2/4/6彩果0003次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0003时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 0, 3]), range: 0...0, hits2025: 2397, hits2026: 1855, retainedBets: 720),
        .init(condition: .f98R043, title: "相对位置1/2/4/6彩果0010次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0010时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 1, 0]), range: 0...0, hits2025: 2405, hits2026: 1858, retainedBets: 720),
        .init(condition: .f98R044, title: "相对位置1/2/4/6彩果0011次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0011时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 1, 1]), range: 0...0, hits2025: 2418, hits2026: 1864, retainedBets: 720),
        .init(condition: .f98R045, title: "相对位置1/2/4/6彩果0013次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0013时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 1, 3]), range: 0...0, hits2025: 2413, hits2026: 1857, retainedBets: 720),
        .init(condition: .f98R046, title: "相对位置1/2/4/6彩果0030次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0030时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 3, 0]), range: 0...0, hits2025: 2405, hits2026: 1848, retainedBets: 720),
        .init(condition: .f98R047, title: "相对位置1/2/4/6彩果0031次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0031时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 3, 1]), range: 0...0, hits2025: 2416, hits2026: 1862, retainedBets: 720),
        .init(condition: .f98R048, title: "相对位置1/2/4/6彩果0033次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0033时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 0, 3, 3]), range: 0...0, hits2025: 2392, hits2026: 1850, retainedBets: 720),
        .init(condition: .f98R049, title: "相对位置1/2/4/6彩果0100次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0100时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 1, 0, 0]), range: 0...0, hits2025: 2418, hits2026: 1865, retainedBets: 720),
        .init(condition: .f98R050, title: "相对位置1/2/4/6彩果0101次数", help: "在本组六场内逐个起点查看相对位置1/2/4/6，依次为彩果0101时记1次；只统计完全落在组六场内的窗口，允许重叠。", metric: .pattern([0, 1, 3, 5], [0, 1, 0, 1]), range: 0...0, hits2025: 2423, hits2026: 1869, retainedBets: 720)
    ]
    static let byCondition = Dictionary(uniqueKeysWithValues: ordered.map { ($0.condition, $0) })
}
// END GENERATED HIGH PASS 98 FIFTY CATALOG

enum ConsecutiveRunCondition: String, CaseIterable, Sendable {
    case nonLoss
    case nonDraw
    case nonWin
    case win
    case draw
    case loss

    var title: String {
        switch self {
        case .nonLoss: return "连续不败"
        case .nonDraw: return "连续不平"
        case .nonWin: return "连续不胜"
        case .win: return "连续胜"
        case .draw: return "连续平"
        case .loss: return "连续负"
        }
    }

    func longestRun(in outcomes: [Int]) -> Int {
        var longest = 0
        var current = 0
        for outcome in outcomes {
            let matches: Bool
            switch self {
            case .nonLoss: matches = outcome != 0
            case .nonDraw: matches = outcome != 1
            case .nonWin: matches = outcome != 3
            case .win: matches = outcome == 3
            case .draw: matches = outcome == 1
            case .loss: matches = outcome == 0
            }
            current = matches ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}

enum FinalReductionMode: String, CaseIterable, Sendable {
    case off = "OFF"
    case product = "QHALF"
    case probability = "SCOREHALF"
    case random = "RANDOMHALF"

    var title: String {
        switch self {
        case .off: return "关闭"
        case .product: return "Q排序"
        case .probability: return "删除ABCD综合评分最高项"
        case .random: return "ABCD加权随机"
        }
    }
}

enum GroupFilterMode: String, CaseIterable, Sendable {
    case outcomeSum = "SUM"
    case spProduct = "SP"
    case both = "BOTH"

    var title: String {
        switch self {
        case .outcomeSum: return "彩果和值"
        case .spProduct: return "SP乘积"
        case .both: return "和值 + SP乘积"
        }
    }

    var usesOutcomeSum: Bool { self != .spProduct }
    var usesSPProduct: Bool { self != .outcomeSum }
}

/// Appended to SVIP10 only. Old archived inputs omit these tokens and keep all three off.
/// Selection inputs deliberately contain no results, scores or match status.
struct AutomaticDoubleCandidate: Equatable, Sendable {
    let number: Int
    let logic: LogicMapping
    let odds: [Double]
    var evidence: DoubleMarketEvidence? = nil
}

struct AutomaticDoubleChoice: Equatable, Sendable {
    let number: Int
    let retainedOutcomes: [Int]
    let mappedPair: [Int]
    let coverage: Double
    var judgmentScore: Double? = nil
    var rankingScore: Double { judgmentScore ?? coverage }
    var removedOutcome: Int { [3, 1, 0].first { !retainedOutcomes.contains($0) }! }
}

struct AutomaticDoubleSelection: Equatable, Sendable {
    let matches: [AutomaticDoubleCandidate]
    let choices: [AutomaticDoubleChoice]
    let candidateCount: Int
    /// Model estimate under independent fixtures, distinct from historical hits.
    var estimatedJointCoverage: Double { choices.reduce(1) { $0 * $1.coverage } }
}

enum AutomaticDoubleSelector {
    static func probabilities(odds: [Double], calibrated: Bool) -> [Double]? {
        guard odds.count == 3, odds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let inverse = odds.map { 1 / $0 }, total = inverse.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        let p = inverse.map { $0 / total }
        guard calibrated else { return p }
        // Frozen on 2024 only; no fitting against the displayed 2025/2026 results.
        let temperature = exp(-0.13572934380182766)
        let offsets = [-0.054715759879316705, 0.12267614425842781, 0.0]
        let logits = p.enumerated().map { log(max(1e-12, min(1, $0.element))) / temperature + offsets[$0.offset] }
        let weights = logits.map { exp($0 - logits.max()!) }, sum = weights.reduce(0, +)
        return weights.map { $0 / sum }
    }

    static func choice(_ match: AutomaticDoubleCandidate, calibrated: Bool, factors: Set<DoubleJudgmentFactor> = []) -> AutomaticDoubleChoice? {
        guard let p = probabilities(odds: match.odds, calibrated: calibrated) else { return nil }
        let scores = DoubleJudgmentScorer.scores(match, calibrated: calibrated, factors: factors) ?? p
        let outcomes = [3, 1, 0]
        // Compare all pairs explicitly; mapped value 4 is allowed in either pair.
        let pairs = [[2, 3], [2, 4], [3, 4]].map { pair in
            let retained = outcomes.filter { pair.contains(match.logic.value(for: $0)) }
            return AutomaticDoubleChoice(number: match.number, retainedOutcomes: retained, mappedPair: pair,
                coverage: outcomes.indices.filter { retained.contains(outcomes[$0]) }.reduce(0) { $0 + p[$1] },
                judgmentScore: factors.isEmpty ? nil : outcomes.indices.filter { retained.contains(outcomes[$0]) }.reduce(0) { $0 + scores[$1] })
        }
        return pairs.sorted {
            abs($0.rankingScore - $1.rankingScore) > 1e-15 ? $0.rankingScore > $1.rankingScore : $0.mappedPair.lexicographicallyPrecedes($1.mappedPair)
        }.first
    }

    /// 胜负倾向决定主选，平局只作保底，不能返回30双选。
    static func directionalChoice(_ match: AutomaticDoubleCandidate, calibrated: Bool,
                                  factors: Set<DoubleJudgmentFactor> = []) -> AutomaticDoubleChoice? {
        guard let p = probabilities(odds: match.odds, calibrated: calibrated) else { return nil }
        let scores = DoubleJudgmentScorer.scores(match, calibrated: calibrated, factors: factors) ?? p
        let retained = scores[0] >= scores[2] ? [3, 1] : [1, 0]
        return AutomaticDoubleChoice(number: match.number, retainedOutcomes: retained,
            mappedPair: retained.map { match.logic.value(for: $0) }.sorted(),
            coverage: retained.reduce(0) { $0 + p[$1 == 3 ? 0 : ($1 == 1 ? 1 : 2)] },
            judgmentScore: factors.isEmpty ? nil : retained.reduce(0) { $0 + scores[$1 == 3 ? 0 : ($1 == 1 ? 1 : 2)] })
    }

    /// A/D由对照表实际排序决定：A保留31，D保留10，B/C不符合选场要求。
    static func frontADChoice(_ match: AutomaticDoubleCandidate, calibrated: Bool,
                              factors: Set<DoubleJudgmentFactor> = []) -> AutomaticDoubleChoice? {
        guard match.logic == .a || match.logic == .d,
              let p = probabilities(odds: match.odds, calibrated: calibrated) else { return nil }
        let retained = match.logic == .a ? [3, 1] : [1, 0]
        let scores = DoubleJudgmentScorer.scores(match, calibrated: calibrated, factors: factors) ?? p
        let indices = retained.map { $0 == 3 ? 0 : ($0 == 1 ? 1 : 2) }
        return AutomaticDoubleChoice(number: match.number, retainedOutcomes: retained,
            mappedPair: retained.map { match.logic.value(for: $0) }.sorted(),
            coverage: indices.reduce(0) { $0 + p[$1] },
            judgmentScore: factors.isEmpty ? nil : indices.reduce(0) { $0 + scores[$1] })
    }

    static func choices(in matches: [AutomaticDoubleCandidate], calibrated: Bool, factors: Set<DoubleJudgmentFactor> = [], fixedFrontTwo: Bool = false, requireFrontTwoAD: Bool = false, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> [AutomaticDoubleChoice] {
        if adDoublesWithinSix {
            let eligible = matches.compactMap { frontADChoice($0, calibrated: calibrated, factors: factors) }.sorted {
                abs($0.rankingScore - $1.rankingScore) > 1e-15 ? $0.rankingScore > $1.rankingScore : $0.number < $1.number
            }
            guard (1...2).contains(adDoubleCountWithinSix) else { return [] }
            return eligible.count >= adDoubleCountWithinSix ? Array(eligible.prefix(adDoubleCountWithinSix)) : []
        }
        if fixedFrontTwo {
            if requireFrontTwoAD { return matches.prefix(2).compactMap { frontADChoice($0, calibrated: calibrated, factors: factors) } }
            return matches.prefix(2).compactMap { directionalChoice($0, calibrated: calibrated, factors: factors) }
        }
        guard (1...2).contains(automaticDoubleCount) else { return [] }
        return matches.compactMap { choice($0, calibrated: calibrated, factors: factors) }.sorted {
            abs($0.rankingScore - $1.rankingScore) > 1e-15 ? $0.rankingScore > $1.rankingScore : $0.number < $1.number
        }.prefix(automaticDoubleCount).map { $0 }
    }

    /// The ticket is exactly [first, first+5]. Missing data or a conflicting
    /// seventh fixture stops selection; never replace a fixture from outside.
    static func recommend(first: Int, candidates: [AutomaticDoubleCandidate], excluding: Set<Int> = [],
                          calibrated: Bool, factors: Set<DoubleJudgmentFactor> = []) -> AutomaticDoubleSelection? {
        guard first > 0, first <= Int.max - 6 else { return nil }
        return recommend(numbers: Array(first..<(first + 6)), candidates: candidates,
            excluding: excluding, calibrated: calibrated, factors: factors)
    }

    /// 双选只在明确选定的六场内比较，兼容补齐ABCD后的非连续场次。
    static func recommend(numbers requested: [Int], candidates: [AutomaticDoubleCandidate], excluding: Set<Int> = [],
                          calibrated: Bool, factors: Set<DoubleJudgmentFactor> = [], fixedFrontTwo: Bool = false, requireFrontTwoAD: Bool = false, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> AutomaticDoubleSelection? {
        guard requested.count == 6, Set(requested).count == 6, requested.allSatisfy({ $0 > 0 }),
              requested == requested.sorted() else { return nil }
        guard Set(requested).isDisjoint(with: excluding) else { return nil }
        let filtered = candidates.filter { requested.contains($0.number)
            && probabilities(odds: $0.odds, calibrated: calibrated) != nil }
        let matches = Dictionary(filtered.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.number < $1.number }
        guard matches.map(\.number) == requested else { return nil }
        let selected = choices(in: matches, calibrated: calibrated, factors: factors, fixedFrontTwo: fixedFrontTwo, requireFrontTwoAD: requireFrontTwoAD, adDoublesWithinSix: adDoublesWithinSix, adDoubleCountWithinSix: adDoubleCountWithinSix, automaticDoubleCount: automaticDoubleCount)
        guard (adDoublesWithinSix || fixedFrontTwo) || selected.count == automaticDoubleCount else { return nil }
        guard !(adDoublesWithinSix || fixedFrontTwo && requireFrontTwoAD) || selected.count == (adDoublesWithinSix ? adDoubleCountWithinSix : 2) else { return nil }
        return AutomaticDoubleSelection(matches: matches, choices: selected, candidateCount: 6)
    }

}

struct SVIP10AdditionalFilters: Equatable, Sendable {
    var firstDoubleActive: Bool { highestDoubleProbabilityTopTwoEnabled || fixedFrontTwoDoublesEnabled || adDoublesWithinSixEnabled }
    var secondDoubleActive: Bool {
        if adDoublesWithinSixEnabled && adDoubleCountWithinSix == 1 { return false }
        if !adDoublesWithinSixEnabled && automaticDoublePairEnabled && automaticDoubleCount == 1 { return false }
        return secondDoubleLowestProbabilityEnabled || fixedFrontTwoDoublesEnabled || adDoublesWithinSixEnabled
    }
    var usesAutomaticDoubleSelection: Bool { automaticDoublePairEnabled || fixedFrontTwoDoublesEnabled || adDoublesWithinSixEnabled }
    var coldCountEnabled = false
    var coldCountRange = 0...2
    var drawCountEnabled = false
    var drawCountRange = 0...3
    var winLossSwitchEnabled = false
    /// 旧归档兼容：双选概率最高场次的ABCD判定值不能为4。
    var highestDoubleProbabilityNoFourEnabled = false
    /// 当前规则：选择双选概率最高的场次，只保留概率最高的两个彩果。
    var highestDoubleProbabilityTopTwoEnabled = false
    /// 排除上面的第一处双选后，再选一场并剔除模型概率最低的彩果。
    var secondDoubleLowestProbabilityEnabled = false
    /// 固定2024参数校正自定义赔率概率，两处双选使用同一口径。
    var calibratedDoubleSelectionEnabled = false
    var automaticDoublePairEnabled = false
    /// 选场时向后补齐六场的全部ABCD，允许不连续；旧归档缺字段时关闭。
    var allABCDSelectionEnabled = false
    var doubleJudgmentFactors: Set<DoubleJudgmentFactor> = []
    var doubleMarketEvidence: [DoubleMarketEvidence] = []
    /// 前5场实际顺序M；范围默认3...6并可编辑起止值。
    var fiveMatchMEnabled = false
    var fiveMatchMRange = 3...6
    /// 前5场同一彩果最长连续2场，第6/7场不参与。
    var frontFiveSameOutcomeRunMaximum2Enabled = false
    /// 前5场的A-B-A隔场回返最多2次，第6/7场不参与。
    var frontFiveReturnMaximum2Enabled = false
    /// 前5场不允许相邻两场都是平局（1-1）。
    var frontFiveNoConsecutiveDrawEnabled = false
    /// 前5场ABCD判定值3最多2个。
    var frontFiveValueThreeMaximum2Enabled = false
    /// 六场中选到自定义赔率第一选（最低赔率）2...4个。
    var sixMatchFavoriteCount2To4Enabled = false
    /// 当前规则：六场中选到自定义赔率第一选（最低赔率）1...4个。
    var sixMatchFavoriteCount1To4Enabled = false
    /// 前六场所选自定义赔率连乘的下限。
    var sixMatchMinimumOddsProductEnabled = false
    var sixMatchMinimumOddsProduct = 380.0
    /// 前六场原始彩果相邻变化次数为2...4。
    var sixMatchBreakpoint2To4Enabled = false
    /// 前六场原始彩果相邻变化次数；旧归档未保存范围时沿用3...5。
    var sixMatchBreakpoint3To5Enabled = false
    var sixMatchBreakpointRange = 3...5
    /// 从仅因前5场M或第一选个数被删的组合中，按联合概率最多补回100注。
    var topThreeProbabilityRecovery100Enabled = false
    var statisticalLineBudgetEnabled = false
    var probabilityMass60Enabled = false
    /// 最多105注；只优选已通过组合，不足时不补齐。旧归档默认关闭。
    var maximum105Enabled = false
    var fixedFrontTwoDoublesEnabled = false
    var frontTwoADEnabled = false
    var adDoublesWithinSixEnabled = false
    /// Absent from archived inputs means the original two A/D doubles.
    var adDoubleCountWithinSix = 2
    /// Non-A/D automatic selection; absent archived token keeps the original pair.
    var automaticDoubleCount = 2

    var protocolTokens: String {
        "S10COLDON=\(coldCountEnabled ? 1 : 0)|S10COLD=\(coldCountRange.lowerBound)-\(coldCountRange.upperBound)|S10DRAWON=\(drawCountEnabled ? 1 : 0)|S10DRAW=\(drawCountRange.lowerBound)-\(drawCountRange.upperBound)|S10WLON=\(winLossSwitchEnabled ? 1 : 0)|S10DBLNO4=\(highestDoubleProbabilityNoFourEnabled ? 1 : 0)|S10DBLTOP2=\(highestDoubleProbabilityTopTwoEnabled ? 1 : 0)|S10DBL2LOW=\(secondDoubleLowestProbabilityEnabled ? 1 : 0)|S10DBLCAL=\(calibratedDoubleSelectionEnabled ? 1 : 0)|S10AUTOPAIR=\(automaticDoublePairEnabled ? 1 : 0)|S10ABCDSELECT=\(allABCDSelectionEnabled ? 1 : 0)|S10FACTORS=\(DoubleJudgmentFactor.text(doubleJudgmentFactors))|S10MARKET=\(DoubleMarketEvidence.encoded(doubleMarketEvidence))|S10F5MON=\(fiveMatchMEnabled ? 1 : 0)|S10F5MRANGE=\(fiveMatchMRange.lowerBound)-\(fiveMatchMRange.upperBound)|S10F5RUN2ON=\(frontFiveSameOutcomeRunMaximum2Enabled ? 1 : 0)|S10F5RET2ON=\(frontFiveReturnMaximum2Enabled ? 1 : 0)|S10F5NO11ON=\(frontFiveNoConsecutiveDrawEnabled ? 1 : 0)|S10F5V3MAX2ON=\(frontFiveValueThreeMaximum2Enabled ? 1 : 0)|S10FAV24ON=\(sixMatchFavoriteCount2To4Enabled ? 1 : 0)|S10FAV14ON=\(sixMatchFavoriteCount1To4Enabled ? 1 : 0)|S10ODDSPROD6ON=\(sixMatchMinimumOddsProductEnabled ? 1 : 0)|S10ODDSPROD6MIN=\(sixMatchMinimumOddsProduct)|S10B24ON=\(sixMatchBreakpoint2To4Enabled ? 1 : 0)|S10B35ON=\(sixMatchBreakpoint3To5Enabled ? 1 : 0)|S10BRANGE=\(sixMatchBreakpointRange.lowerBound)-\(sixMatchBreakpointRange.upperBound)|S10REC100=\(topThreeProbabilityRecovery100Enabled ? 1 : 0)|S10LINE50=\(statisticalLineBudgetEnabled ? 1 : 0)|S10MASS60=\(probabilityMass60Enabled ? 1 : 0)|S10MAX105=\(maximum105Enabled ? 1 : 0)|S10FRONTAD=\(frontTwoADEnabled ? 1 : 0)|S10FRONTDBL=\(fixedFrontTwoDoublesEnabled ? 1 : 0)|S10ADWITHIN6=\(adDoublesWithinSixEnabled ? 1 : 0)" + (adDoubleCountWithinSix == 2 ? "" : "|S10ADCOUNT=\(adDoubleCountWithinSix)") + (automaticDoubleCount == 2 ? "" : "|S10DBLCOUNT=\(automaticDoubleCount)")
    }
    var descriptions: [String] {
        var rows: [String] = []
        if coldCountEnabled { rows.append("六场自定义赔率第三选\(coldCountRange.lowerBound)–\(coldCountRange.upperBound)个") }
        if drawCountEnabled { rows.append("六场平局\(drawCountRange.lowerBound)–\(drawCountRange.upperBound)个") }
        if winLossSwitchEnabled { rows.append("前5场胜负直接切换0–2次") }
        if highestDoubleProbabilityNoFourEnabled { rows.append("双选概率最高的场次判定值不是4") }
        if adDoublesWithinSixEnabled { rows.append(adDoubleCountWithinSix == 1 ? "在所选六场内择优选一场A/D：A双选31、D双选10，位置不固定，其余五场全选" : "在所选六场内择优选两场A/D：A双选31、D双选10，位置不固定，其余四场全选") }
        if firstDoubleActive && !adDoublesWithinSixEnabled { rows.append(fixedFrontTwoDoublesEnabled ? "第1场查找A或D：A双选31、D双选10，1作保底" : "最适合双选场次仅保留概率前两项") }
        if secondDoubleActive && !adDoublesWithinSixEnabled { rows.append(fixedFrontTwoDoublesEnabled ? "第2场独立查找A或D，AA/AD/DA/DD均可；后四场连续" : "第二个双选场次去掉最低概率项") }
        if calibratedDoubleSelectionEnabled { rows.append("双选概率校正（实验，固定2024参数）") }
        if fiveMatchMEnabled { rows.append("前5场实际M=\(fiveMatchMRange.lowerBound)–\(fiveMatchMRange.upperBound)") }
        if frontFiveSameOutcomeRunMaximum2Enabled { rows.append("前5场同彩果最长连续≤2场") }
        if frontFiveReturnMaximum2Enabled { rows.append("前5场隔场回返≤2次") }
        if frontFiveNoConsecutiveDrawEnabled { rows.append("前5场不出现连续平局") }
        if frontFiveValueThreeMaximum2Enabled { rows.append("前5场判定值3最多2个") }
        if sixMatchFavoriteCount2To4Enabled { rows.append("六场自定义赔率第一选2–4个") }
        if sixMatchFavoriteCount1To4Enabled { rows.append("六场自定义赔率第一选1–4个") }
        if sixMatchMinimumOddsProductEnabled {
            let minimumText = String(format: "%.0f", sixMatchMinimumOddsProduct)
            rows.append("前六场自定义赔率乘积≥\(minimumText)")
        }
        if sixMatchBreakpoint2To4Enabled { rows.append("六场彩果断点B=2–4") }
        if sixMatchBreakpoint3To5Enabled { rows.append("六场彩果断点B=\(sixMatchBreakpointRange.lowerBound)–\(sixMatchBreakpointRange.upperBound)") }
        if topThreeProbabilityRecovery100Enabled { rows.append("联合概率优先补回最多100注") }
        if statisticalLineBudgetEnabled { rows.append("市场概率＋历史结构统计优选，最多50行") }
        if probabilityMass60Enabled { rows.append("概率质量优先，最多60行") }
        if maximum105Enabled { rows.append("最多105注：自定义赔率联合概率优选；不足不补齐") }
        return rows
    }
}

/// Missing switch tokens keep historical inputs enabled, preserving their original meaning.
enum BasicCondition: String, CaseIterable, Sendable {
    case sum, displacement, variance, valueTwo, transition, roughness, breakpoints
    case valueThree, score, oddsProduct, oddsSum, oddsRank

    var title: String {
        switch self {
        case .sum: return "和值S"
        case .displacement: return "位移M"
        case .variance: return "稳定性方差"
        case .valueTwo: return "判定值2个数"
        case .transition: return "转移率"
        case .roughness: return "二阶波动R"
        case .breakpoints: return "彩果断点B"
        case .valueThree: return "判定值3个数"
        case .score: return "自定义综合评分"
        case .oddsProduct: return "自定义赔率乘积"
        case .oddsSum: return "自定义赔率和值"
        case .oddsRank: return "赔率排名"
        }
    }
}

struct ConditionTextCommand: Equatable {
    let id: String
    let value: String?
    let enabled: Bool
}

/// Natural phrasing is normalized locally; unrecognized or ambiguous clauses
/// are rejected as a batch rather than silently changing a different condition.
enum ConditionValueFormat { case integerRange, decimalRange, integerMaximum, decimalMaximum, integerMinimum, decimalMinimum }

struct ConditionTextRule {
    let id: String
    let title: String
    let aliases: [String]
    var format: ConditionValueFormat? = nil
    var maximum: Double = 0
    /// Fixed engine rules accept their existing threshold, never invent a new one.
    var fixedValue: String? = nil
    var exclusionGroup: String? = nil
}

struct ConditionTextError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ConditionTextParser {
    private static let actions: [(String, Bool)] = [
        ("不要开启", false), ("不要打开", false), ("不用开启", false), ("别开启", false), ("别打开", false),
        ("关闭", false), ("关掉", false), ("关了", false), ("关上", false), ("停用", false), ("禁用", false),
        ("取消", false), ("不开", false), ("不要", false), ("不用", false), ("去掉", false),
        ("开启", true), ("启用", true), ("打开", true), ("开着", true), ("开了", true), ("开", true), ("关", false)
    ]

    static func interpret(_ text: String, rules: [ConditionTextRule]) throws -> [ConditionTextCommand] {
        var aliases: [String: String] = [:]
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        for rule in rules {
            for alias in rule.aliases + [rule.title] {
                let name = normalize(alias).lowercased()
                if let old = aliases[name], old != rule.id { throw failure("条件名称“\(alias)”有歧义，请使用完整名称") }
                aliases[name] = rule.id
            }
        }
        let commands = try parse(text, aliases: aliases)
        let validated = try commands.map { command in
            guard let rule = byID[command.id] else { throw failure("无法找到该条件") }
            guard var value = command.value else { return command }
            guard let format = rule.format else { throw failure("“\(rule.title)”只支持开启或关闭；请勿附加数值") }
            if rule.id == BasicCondition.transition.rawValue { value = value.replacingOccurrences(of: "%", with: "") }
            let canonical = try validateValue(value, format: format, maximum: rule.maximum, title: rule.title)
            if let fixed = rule.fixedValue {
                guard canonical == fixed else { throw failure("“\(rule.title)”当前是固定条件（\(fixed)），不能改成\(canonical)") }
                return ConditionTextCommand(id: command.id, value: nil, enabled: command.enabled)
            }
            return ConditionTextCommand(id: command.id, value: canonical, enabled: command.enabled)
        }
        var enabledGroups = Set<String>()
        for command in validated where command.enabled {
            if let group = byID[command.id]?.exclusionGroup, !enabledGroups.insert(group).inserted {
                throw failure("这批指令包含互斥的条件（例如50行与60行优选），请选择其中一种")
            }
        }
        return validated
    }

    static func validateValue(_ input: String, format: ConditionValueFormat,
                              maximum: Double, title: String) throws -> String {
        var text = canonicalValue(normalize(input))
        let isRange = format == .integerRange || format == .decimalRange
        let isMinimum = format == .integerMinimum || format == .decimalMinimum
        let isInteger = format == .integerRange || format == .integerMaximum || format == .integerMinimum
        func label(_ number: Double) -> String {
            number.formatted(.number.grouping(.never).precision(.fractionLength(0...8)).locale(Locale(identifier: "en_US_POSIX")))
        }
        let operators = ["<=", ">=", "<", ">", "="]
        if let op = operators.first(where: text.hasPrefix) {
            guard let number = Double(text.dropFirst(op.count)), number.isFinite else { throw failure("\(title)的数值不完整") }
            if op == "<" || op == ">" {
                guard isInteger, number.rounded() == number else { throw failure("\(title)暂不支持不含边界的小数；请明确写“不超过”或“至少”的数值") }
            }
            let bound = number + (op == "<" ? -1 : (op == ">" ? 1 : 0))
            if isRange {
                switch op {
                case "<=", "<": text = "0-" + label(bound)
                case ">=", ">": text = label(bound) + "-" + label(maximum)
                default: text = label(bound)
                }
            } else {
                guard op != "=", isMinimum ? (op == ">=" || op == ">") : (op == "<=" || op == "<") else {
                    throw failure("\(title)只能设置\(isMinimum ? "下限" : "上限")，不能表示这个范围或精确个数")
                }
                text = label(bound)
            }
        }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, (isRange ? (1...2).contains(numbers.count) : numbers.count == 1),
              numbers.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= maximum
                  && (!isInteger || $0.rounded() == $0) }),
              numbers.first! <= numbers.last! else {
            throw failure("\(title)请输入0–\(maximum.formatted())内的\(isInteger ? "整数" : "数值")\(isRange ? "范围，起点不能大于终点" : (isMinimum ? "下限" : "上限"))；“左右、少一点”等说法请补充具体范围")
        }
        return isRange ? "\(label(numbers[0]))-\(label(numbers.last!))" : label(numbers[0])
    }

    static func parse(_ text: String, aliases: [String: String]) throws -> [ConditionTextCommand] {
        guard text.count <= 2000 else { throw failure("一次请输入2000字以内的条件") }
        var aliasIDs: [String: String] = [:]
        for (name, id) in aliases {
            let key = normalize(name).lowercased()
            guard !key.isEmpty, aliasIDs[key] == nil || aliasIDs[key] == id else { throw failure("条件名称有歧义，请使用完整名称") }
            aliasIDs[key] = id
        }
        let names = aliasIDs.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        var normalized = normalize(text)
        for separator in ["，", "、", "；", ";", "。", "\n", "\r"] { normalized = normalized.replacingOccurrences(of: separator, with: ",") }
        let namePattern = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        if !namePattern.isEmpty {
            normalized = replacing(normalized, pattern: "(?:并且|而且|同时|以及|然后|另外|还有|再把|并把|并将|且把|且将|并|且|和|及)(?=(?:(?:请|帮我|把|将|开启|关闭|启用|禁用|停用|打开|关掉))*(?:\(namePattern)))", with: ",", caseInsensitive: true)
        }
        var pending = normalized.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !pending.isEmpty else { throw failure("请输入条件，例如：和值十五到二十、平局最多两场") }
        var commands: [ConditionTextCommand] = []
        while !pending.isEmpty {
            let original = pending.removeFirst()
            var remaining = stripLeading(original, words: ["麻烦你", "麻烦", "请帮我", "帮我", "请", "我想要", "我想", "我要", "给我", "把", "将", "增加一个", "添加一个", "增加", "添加", "设置", "设定"])
            var enabled = true
            var implicitValue: String?
            var ambiguousNegation = false
            // “不要平局” means zero draws; “不要连平” means a longest run <=1.
            // An explicit “条件” suffix instead means disabling that condition.
            for absence in ["不允许有", "不能有", "不出现", "不允许", "禁止", "不要", "不留", "去掉"] where remaining.hasPrefix(absence) {
                let subject = String(remaining.dropFirst(absence.count)).lowercased()
                if let name = names.first(where: { subject == $0 }),
                   let id = aliasIDs[name], id == "OC_DRAWS" || id == "draws" || id == "OC_LOSSES" || id == "extra.0" {
                    remaining = subject; implicitValue = "0"; break
                }
                if let name = names.first(where: { subject == $0 }),
                   let id = aliasIDs[name], ["OC_DRUN", "OC_WRUN", "OC_LRUN", "drawRun"].contains(id) {
                    remaining = subject; implicitValue = "<=1"; break
                }
            }
            if implicitValue == nil, let action = actions.first(where: { remaining.hasPrefix($0.0) }) {
                enabled = action.1
                ambiguousNegation = ["不要", "去掉", "不用"].contains(action.0)
                remaining = String(remaining.dropFirst(action.0.count))
                remaining = stripLeading(remaining, words: ["这个", "该", "把", "将"])
            }
            let lower = remaining.lowercased()
            guard let name = names.first(where: { lower.hasPrefix($0) }), let id = aliasIDs[name] else {
                throw failure("暂时没理解“\(original)”；可写“和值15到20、平局最多2场、关闭第二双选”")
            }
            var value = String(remaining.dropFirst(name.count))
            // Split adjacent subjects too: “S15-20M3-8平局最多2场”. Only a
            // recognized next subject can start a new clause; leftover text fails validation.
            var nextStart: String.Index?
            for nextName in names {
                if let range = value.range(of: nextName, options: .caseInsensitive),
                   nextStart == nil || range.lowerBound < nextStart! { nextStart = range.lowerBound }
            }
            if let start = nextStart, start > value.startIndex {
                pending.insert(String(value[start...]), at: 0)
                value = String(value[..<start])
            }
            value = stripLeading(value, words: ["这个条件", "该条件", "条件", "这个开关", "开关"])
            value = stripLeading(value, words: ["设置为", "设为", "调整为", "调整到", "改成", "改为", "调到", "调成", "设置成", "保持", "继续"])
            while value.first == ":" || value.first == "=" { value.removeFirst() }
            if let action = actions.first(where: { value == $0.0 }) {
                enabled = action.1; value = ""
            }
            let canonical = implicitValue ?? canonicalValue(value)
            if ambiguousNegation && !canonical.isEmpty { throw failure("“\(original)”可能是关闭条件，也可能是排除该范围；请明确写“关闭”或具体允许范围") }
            commands.append(ConditionTextCommand(id: id, value: canonical.isEmpty ? nil : canonical, enabled: enabled))
        }
        guard Set(commands.map(\.id)).count == commands.count else { throw failure("同一批输入中有重复条件，请合并为一个明确范围或开关指令") }
        return commands
    }

    private static func failure(_ message: String) -> ConditionTextError { ConditionTextError(message: message) }

    private static func normalize(_ input: String) -> String {
        var text = input.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input
        text = text.replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "､", with: ",")
        for (from, to) in [("≤","<="),("≥",">="),("～","-"),("~","-"),("–","-"),("—","-"),("−","-")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        text = replacing(text, pattern: "[^\\S\\r\\n]+", with: "")
        let pattern = "[0-9零〇一二两三四五六七八九十百千万点]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text), let number = chineseNumber(String(text[range])) else { continue }
                text.replaceSubrange(range, with: number)
            }
        }
        return text
    }

    private static func chineseNumber(_ text: String) -> String? {
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,
            "0":0,"1":1,"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9]
        let parts = text.split(separator: "点", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty else { return nil }
        let integer = String(parts[0])
        var total = 0, section = 0, digit = 0
        if integer.allSatisfy({ digits[$0] != nil }) {
            guard let number = Int(integer.map { String(digits[$0]!) }.joined()) else { return nil }
            total = number
        } else {
            for character in integer {
                if let number = digits[character] { digit = number }
                else if let unit: Int = ["十":10,"百":100,"千":1000][character] { section += max(1, digit) * unit; digit = 0 }
                else if character == "万" { total += (section + digit) * 10000; section = 0; digit = 0 }
                else { return nil }
            }
            total += section + digit
        }
        guard parts.count == 2 else { return String(total) }
        guard !parts[1].isEmpty, parts[1].allSatisfy({ digits[$0] != nil }) else { return nil }
        return String(total) + "." + parts[1].map { String(digits[$0]!) }.joined()
    }

    private static func canonicalValue(_ input: String) -> String {
        var text = input
        for (from, to) in [("≤","<="),("≥",">="),("～","-"),("~","-"),("–","-"),("—","-"),("−","-")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        text = stripLeading(text, words: [":", "设置为", "设为", "调整为", "调整到", "改成", "改为", "调到", "调成", "保留", "控制在", "限制在", "范围是", "范围为", "范围", "在", "为", "是"])
        for (from, to) in [("大于等于",">="),("小于等于","<="),("不要超过","<="),("不能超过","<="),("别超过","<="),("不超过","<="),("不能多于","<="),("不多于","<="),("不大于","<="),("不高于","<="),("最多","<="),("至多","<="),("上限","<="),("至少",">="),("最少",">="),("不低于",">="),("不小于",">="),("不少于",">="),("下限",">="),("超过",">"),("多于",">"),("大于",">"),("高于",">"),("少于","<"),("小于","<"),("低于","<"),("正好","="),("恰好","="),("刚好","="),("等于","=")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        for unit in ["场", "个", "次", "分", "注", "行", "倍", "项"] { text = text.replacingOccurrences(of: unit, with: "") }
        for suffix in ["就可以", "都可以", "就行", "即可", "含边界", "之间"] where text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        for (suffix, op) in [("以内","<="),("以下","<="),("之内","<="),("以上",">=")] where text.hasSuffix(suffix) {
            text = op + text.dropLast(suffix.count)
            break
        }
        text = text.replacingOccurrences(of: "到", with: "-").replacingOccurrences(of: "至", with: "-")
        text = replacing(text, pattern: "^>=([0-9]+(?:\\.[0-9]+)?)(?:且|并且|并|和|同时)?<=([0-9]+(?:\\.[0-9]+)?)$", with: "$1-$2")
        text = replacing(text, pattern: "^<=([0-9]+(?:\\.[0-9]+)?)(?:且|并且|并|和|同时)?>=([0-9]+(?:\\.[0-9]+)?)$", with: "$2-$1")
        text = text.replacingOccurrences(of: "和", with: "-")
        if text == "没有" || text == "不留" { return "=0" }
        return text
    }

    private static func stripLeading(_ input: String, words: [String]) -> String {
        var text = input
        let ordered = words.sorted { $0.count > $1.count }
        while let prefix = ordered.first(where: { !text.isEmpty && text.hasPrefix($0) }) { text.removeFirst(prefix.count) }
        return text
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String, caseInsensitive: Bool = false) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}

/// Two independent, final-stage exclusions. Positions refer to the six selected
/// fixtures, so changing the start fixture or replaying history preserves the rule.
struct FinalOutcomeExclusion: Equatable, Sendable {
    let slot: Int
    let position: Int
    let outcome: Int

    var summary: String { "独立剔除\(slot)：第\(position)场去掉彩果\(outcome)" }
}

struct FilterConfig: Equatable, Sendable {
    var disabledBasicConditions: Set<BasicCondition> = []
    var valueThreeMaximum = 5

    func isEnabled(_ condition: BasicCondition) -> Bool {
        !disabledBasicConditions.contains(condition)
    }

    static func appendingConditionSwitches(
        to input: String, disabled: Set<BasicCondition>, valueThreeMaximum: Int = 5,
        outcomeRanges: [OutcomeCondition: String] = [:]
    ) -> String {
        var fields = input.components(separatedBy: "|")
        fields.removeAll { $0.hasPrefix("BASEOFF=") || $0.hasPrefix("VALUE3MAX=") }
        // Only replace the explicitly supplied outcome keys; unrelated legacy settings survive.
        fields.removeAll { field in outcomeRanges.keys.contains { field.hasPrefix("OC_\($0.rawValue)=") } }
        let index = fields.indices.dropFirst(7).first { fields[$0].contains(":") } ?? max(0, fields.count - 1)
        var tokens: [String] = []
        if !disabled.isEmpty { tokens.append("BASEOFF=" + disabled.map(\.rawValue).sorted().joined(separator: ",")) }
        if valueThreeMaximum != 5 { tokens.append("VALUE3MAX=\(valueThreeMaximum)") }
        tokens += outcomeRanges.sorted { $0.key.rawValue < $1.key.rawValue }.map { "OC_\($0.key.rawValue)=\($0.value)" }
        fields.insert(contentsOf: tokens, at: index)
        return fields.joined(separator: "|")
    }

    func preservingConditionSwitches(in input: String) -> String {
        var fields = input.components(separatedBy: "|")
        if svip10Frozen160Enabled {
            fields[5] = String(valueTwoMaximum)
            fields = fields.map { $0.hasPrefix("R250=")
                ? "R250=\(six250RRange.lowerBound)-\(six250RRange.upperBound)" : $0 }
        }
        let switched = Self.appendingConditionSwitches(to: fields.joined(separator: "|"), disabled: disabledBasicConditions,
            valueThreeMaximum: valueThreeMaximum,
            outcomeRanges: outcomeConditions.mapValues { "\($0.lowerBound)-\($0.upperBound)" })
        let withForty = Self.appendingHighPass93Group(to: switched, enabled: highPass93GroupEnabled)
        let withHundred = Self.appendingHighPass98Group(to: withForty, enabled: highPass98GroupEnabled)
        let withFifty = Self.appendingHighPass98FiftyGroup(to: withHundred, enabled: highPass98FiftyGroupEnabled)
        return Self.appendingHighPass50Double(to: withFifty, enabled: highPass50DoubleEnabled)
    }

    static func appendingHighPass93Group(to input: String, enabled: Bool?) -> String {
        var fields = input.components(separatedBy: "|").filter { !$0.hasPrefix("HP93GROUP=") }
        if let enabled {
            let boundary = fields.indices.dropFirst(7).first { fields[$0].contains(":") || fields[$0] == "MERGE3" } ?? fields.endIndex
            fields.insert("HP93GROUP=\(enabled ? 1 : 0)", at: boundary)
        }
        return fields.joined(separator: "|")
    }
    static func appendingHighPass98Group(to input: String, enabled: Bool?) -> String {
        var fields = input.components(separatedBy: "|").filter { !$0.hasPrefix("HP98GROUP=") }
        if let enabled {
            let boundary = fields.indices.dropFirst(7).first { fields[$0].contains(":") || fields[$0] == "MERGE3" } ?? fields.endIndex
            fields.insert("HP98GROUP=\(enabled ? 1 : 0)", at: boundary)
        }
        return fields.joined(separator: "|")
    }
    static func appendingHighPass98FiftyGroup(to input: String, enabled: Bool?) -> String {
        var fields = input.components(separatedBy: "|").filter { !$0.hasPrefix("HP98FIFTYGROUP=") }
        if let enabled {
            let boundary = fields.indices.dropFirst(7).first { fields[$0].contains(":") || fields[$0] == "MERGE3" } ?? fields.endIndex
            fields.insert("HP98FIFTYGROUP=\(enabled ? 1 : 0)", at: boundary)
        }
        return fields.joined(separator: "|")
    }
    static func appendingHighPass50Double(to input: String, enabled: Bool) -> String {
        var fields = input.components(separatedBy: "|").filter { !$0.hasPrefix("HP50DOUBLE=") }
        if enabled {
            let boundary = fields.indices.dropFirst(7).first { fields[$0].contains(":") || fields[$0] == "MERGE3" } ?? fields.endIndex
            fields.insert("HP50DOUBLE=1", at: boundary)
        }
        return fields.joined(separator: "|")
    }
    let matchNumbers: [String]
    let logic: [LogicMapping]
    let sumRange: ClosedRange<Int>
    let displacementRange: ClosedRange<Int>
    /// nil 表示M使用全部主场次；VIP9/VIP10固定为5，VIP11固定为6。
    var displacementMatchCount: Int? = nil
    /// nil 表示S沿用其他条件的计算场数；VIP11固定为6。
    var sumMatchCount: Int? = nil
    /// VIP10/VIP11固定为5：第6场不参与S、M以外的条件计算。
    var calculationMatchCount: Int? = nil
    /// VIP10的S使用项目换算后的真实让球欧赔和，不使用2/3/4判定值和。
    var sumUsesOutcomeSP = false
    let varianceMaximum: Double
    let valueTwoMaximum: Int
    let transitionMinimumPercent: Double
    let roughnessMaximum: Int
    let breakpointRange: ClosedRange<Int>
    let productRemovalCount: Int
    var noFourPositions: [Int] = []
    /// SVIP4：五场判定值不同排列中，M在配置范围内的排列至少达到此数。
    var minimumDistinctDisplacementOrders: Int = 0
    /// Optional final reduction, using only six project custom odds rows.
    var svip5TailRemovalCount: Int = 0
    /// 通用组成约束：前5场最多2个判定值4。
    var svip5FourCountFilterEnabled = false
    /// 独立于排列门槛：前五场实际顺序的相邻绝对差之和须为3...6。
    var frontFiveActualMEnabled = false
    var frontFiveActualMRange: ClosedRange<Int> = 3...6
    /// 原始彩果前五场不允许111连续段；第六、七场不计入。
    var frontFiveNoTripleDrawEnabled = false
    var frontFiveLossCountEnabled = false
    var frontFiveLossCountRange: ClosedRange<Int> = 1...5
    var frontFiveWinCountEnabled = false
    var combinedThreeStructureEnabled = false
    var svip11BreakpointOnlyEnabled = false
    var svip10Frozen160Enabled = false
    var svip10AdditionalFilters = SVIP10AdditionalFilters()
    var six250ScoreLower = -Double.greatestFiniteMagnitude
    var six250ScoreUpper = 6.517035527170335
    var txtCompactEnabled = false
    var maximumTXTAdditionalBets = 50
    var additionalSumRange: ClosedRange<Int>? = nil
    var oddsAdaptiveSRangeEnabled = false
    var six250SumRange = 12...22
    var six250MRange = 0...7
    var six250RRange = 0...14
    var six250RelationshipEnabled = false
    /// SVIP7固定六场赔率区间与排名容错；不与旧条件包取交集。
    var svip7RankOddsEnabled = false
    var sixMatchPackageScope = false
    var conditionPackageEnabled = true
    /// nil preserves legacy single-package archives. Explicit values make the
    /// forty count/structure rules independent of the original package switch.
    var highPass93GroupEnabled: Bool? = nil
    var highPass98GroupEnabled: Bool? = nil
    var highPass98FiftyGroupEnabled: Bool? = nil
    var highPass50DoubleEnabled = false
    var highPass50DoubleActive: Bool { highPass98FiftyGroupEnabled == true && highPass50DoubleEnabled }
    var hasIndependentConditionGroups: Bool {
        highPass93GroupEnabled == true || highPass98GroupEnabled == true || highPass98FiftyGroupEnabled == true
    }
    var activeIndependentGroupLabels: [String] {
        (highPass93GroupEnabled == true ? ["40条条件组"] : [])
            + (highPass98GroupEnabled == true ? ["第三组条件"] : [])
            + (highPass98FiftyGroupEnabled == true ? ["第四组条件"] : [])
    }
    var structuralMatchCount: Int { sixMatchPackageScope ? 6 : 5 }
    var structuralScopeLabel: String { sixMatchPackageScope ? "六场" : "前5场" }
    var topFiveSecondRelaxed = false
    var topFiveRelaxed = false
    var widerFiveConditions = false
    var expandedStructureRanges = false
    var combinedThreeRRange: ClosedRange<Int> = 5...12
    var sixLossCount14Enabled = false
    var frontFiveR39Enabled = false
    var frontFiveNoTripleLossEnabled = false
    var frontFiveWinCountRange: ClosedRange<Int> = 1...5
    /// SVIP4：用项目自定义让球赔率计算每场判定值4的归一化隐含概率，选最低的一场禁4。
    var lowestCustomOddsNoFourEnabled = false
    /// 本次计算从赔率解析；不写入持久化条件，也不沿用上一期。
    var resolvedLowestCustomOddsNoFourPosition: Int? = nil
    /// SVIP10：本次从六场赔率选择双选概率最高场次；不跨期沿用。
    var resolvedHighestDoubleProbabilityNoFourPosition: Int? = nil
    /// SVIP10：排除第一处双选后，本次自动选出的第二处双选及剔除彩果；不跨期沿用。
    var resolvedSecondDoublePosition: Int? = nil
    var resolvedSecondDoubleRemovedOutcome: Int? = nil
    var resolvedSecondDoubleProbability: Double? = nil
    var resolvedSecondDoubleUsesModelProbability = false
    var frontThreeMaximumFourCount: Int? = nil
    let probabilityRemovalPercent: Double
    let extraMatches: [ExtraMatchSelection]
    let mergeEnabled: Bool
    var outcomeConditions: [OutcomeCondition: ClosedRange<Int>] = [:]
    var outcomeConditionToleranceEnabled = false
    var outcomeConditionToleranceRange: ClosedRange<Int> = 0...0
    var allConditionsToleranceEnabled = false
    var allConditionsToleranceRange: ClosedRange<Int> = 0...0
    var finalReduction: FinalReductionMode = .off
    var randomSeed: UInt64 = 1
    var marketWeightPercent: Int = 15
    var finalRemovalPercent: Int = 50
    var consecutiveRunsEnabled = false
    var nonLossRunRange: ClosedRange<Int> = 3...7
    var nonDrawRunRange: ClosedRange<Int> = 3...7
    var nonWinRunRange: ClosedRange<Int> = 3...7
    var consecutiveRunToleranceRange: ClosedRange<Int> = 0...1
    /// 连续彩果第二档：默认与3–7＋0–1取交集，形成5–7＋2–3的高阈值保护。
    var secondaryConsecutiveRunsEnabled = false
    var secondaryConsecutiveRunRange: ClosedRange<Int> = 5...7
    var secondaryConsecutiveRunToleranceRange: ClosedRange<Int> = 2...3
    var sameResultRunsEnabled = false
    var winRunRange: ClosedRange<Int> = 2...7
    var drawRunRange: ClosedRange<Int> = 2...7
    var lossRunRange: ClosedRange<Int> = 2...7
    var sameResultRunToleranceRange: ClosedRange<Int> = 2...3
    var protectConsecutiveDrawPair = false
    var spProductFilterEnabled = false
    var spProductRange: ClosedRange<Double> = 20...1500
    /// 按前5场所选让球胜平负赔率计算，选择器每50一档。
    var customHandicapOddsProductFilterEnabled = false
    var customHandicapOddsProductRange: ClosedRange<Int> = 50...300
    /// nil沿用普通计算范围；VIP12显式指定前六场。
    var customHandicapOddsProductMatchCount: Int? = nil
    /// 按前5场所选让球胜平负赔率计算，选择器每1一档。
    var customHandicapOddsSumFilterEnabled = false
    var customHandicapOddsSumRange: ClosedRange<Int> = 12...16
    var prizeRangeFilterEnabled = false
    var estimatedPrizeRange: ClosedRange<Double> = 26...1950
    var spRiskFilterEnabled = false
    var maximumSingleSP: Double = 5
    var highSPThreshold: Double = 4
    var highSPCountRange: ClosedRange<Int> = 0...1
    var minimumProbabilityFilterEnabled = false
    var minimumSingleProbabilityPercent: Double = 15
    var jointProbabilityFilterEnabled = false
    var jointProbabilityPercentRange: ClosedRange<Double> = 0.1...100
    /// VIP12：在VIP11全部条件通过后，按六场赛前概率连乘排序，
    /// 每次固定删除联合概率最低的至少10%整注。
    var vip12ProbabilityReductionEnabled = false
    /// SVIP1：在其他条件和VIP12完成后，仅用项目六场自定义赔率乘积排序，
    /// 保留较热的83.5%整注，去掉最冷16.5%。不使用500或澳客直接SP。
    var svip1CustomOddsGuardEnabled = false
    /// VIP16：全部已启用条件通过后，按六场赛前联合概率统一排序，最多保留200注。
    var vip16Top200Enabled = false
    /// VIP18：以2025冻结校准及冷门次数平滑系数，在已通过条件的整注中取前200注。
    var vip18Top200Enabled = false
    /// VIP19：仅用项目自定义赔率，先限制六场赔率乘积200–1500，再取概率排序前200注。
    var vip19CustomOddsTop200Enabled = false
    var groupFilterEnabled = false
    var groupFilterMode: GroupFilterMode = .both
    var frontGroupOutcomeSumRange: ClosedRange<Int> = 0...9
    var backGroupOutcomeSumRange: ClosedRange<Int> = 0...6
    var frontGroupSPProductRange: ClosedRange<Double> = 1...200
    var backGroupSPProductRange: ClosedRange<Double> = 1...100
    /// 由奖金模块完整6场记录统计得到的胜负直接切换条件：0–2。
    /// 独立于普通5场彩果条件，作用于展开后的完整投注组合。
    var prizeStatisticalConditionEnabled: Bool = false
    /// 由同一批记录统计得到的前5场胜/平计数配比条件。
    var prizeStatisticalCountPatternEnabled: Bool = false
    /// 由32条历史样本离线标定的通用概率阈值。
    /// 只使用六个彩果位置分布与前五场判定值转移，不读取期号、场次号或具体赛果白名单。
    var universal150CompressionEnabled: Bool = false
    /// 由34条已去重历史样本离线标定的通用结构评分。
    /// 只读取前6场彩果的7个结构指标，不读取期号、场次、ABCD或具体赛果白名单。
    var universal247ToleranceEnabled: Bool = false
    /// 通用247的通用得分阈值。越低保留的组合越多。
    var universal247ToleranceThreshold: Double = -0.050756
    /// V10可选的V8联合评分前150注预筛选；默认关闭。
    var productSumV10Top150Enabled: Bool = false
    var finalResultInverted = false
    var finalOutcomeExclusions: [FinalOutcomeExclusion] = []
    var automaticFinalOutcomeExclusions = false
    var historicalOutcomeWindows: [Int] = []
    var historicalOutcomeBeforeIssue: String = ""
    var hasFinalResultFilters: Bool { finalResultInverted || !finalOutcomeExclusions.isEmpty || !historicalOutcomeWindows.isEmpty }

    /// Keep these outside package/tolerance switches and append only active rules.
    /// Omitting all three leaves old normalized inputs and archives unchanged.
    static func appendingFinalResultFilters(to input: String, values: [String: String]) -> String {
        var fields = input.components(separatedBy: "|").filter {
            !["RESULTINVERT=", "RESULTCUT1=", "RESULTCUT2=", "RESULTWINDOWS=", "RESULTBEFORE=", "RESULTAUTO="].contains(where: $0.hasPrefix)
        }
        var tokens: [String] = []
        if values["finalResultInverted"] == "1" { tokens.append("RESULTINVERT=1") }
        for slot in 1...2 where values["finalOutcomeExclusion\(slot)Enabled"] == "1" {
            let position = values["finalOutcomeExclusion\(slot)Position"] ?? "1"
            let outcome = values["finalOutcomeExclusion\(slot)Outcome"] ?? "3"
            tokens.append("RESULTCUT\(slot)=\(position),\(outcome)")
        }
        if values["automaticFinalOutcomeExclusions"] == "1" { tokens.append("RESULTAUTO=1") }
        let windows = [50, 100, 150, 200].filter { values["historyWindow\($0)Enabled"] == "1" }
        if !windows.isEmpty {
            tokens.append("RESULTWINDOWS=" + windows.map(String.init).joined(separator: ","))
            tokens.append("RESULTBEFORE=" + (values["historyWindowBeforeIssue"] ?? ""))
        }
        let boundary = fields.indices.dropFirst(7).first { fields[$0].contains(":") } ?? fields.endIndex
        fields.insert(contentsOf: tokens, at: boundary)
        return fields.joined(separator: "|")
    }

    /// Auto picker values are placeholders; enabled slots and all real settings still matter.
    static func canonicalFinalOutcomeRequestTokens(in input: String) -> String {
        var fields = input.components(separatedBy: "|")
        guard fields.contains("RESULTAUTO=1") else { return input }
        for slot in 1...2 {
            fields = fields.map { $0.hasPrefix("RESULTCUT\(slot)=") ? "RESULTCUT\(slot)=\(slot),3" : $0 }
        }
        return fields.joined(separator: "|")
    }

    var generationRequestSignature: String {
        Self.canonicalFinalOutcomeRequestTokens(in: normalizedInput)
    }

    static let current = FilterConfig(
        matchNumbers: ["1", "2", "3", "4", "5"],
        logic: [.c, .c, .c, .b, .c],
        sumRange: 12...19,
        displacementRange: 3...11,
        varianceMaximum: 3,
        valueTwoMaximum: 4,
        transitionMinimumPercent: 0.15,
        roughnessMaximum: 9,
        breakpointRange: 2...6,
        productRemovalCount: 0,
        probabilityRemovalPercent: 50,
        extraMatches: [
            ExtraMatchSelection(matchNumber: "6", outcomes: [3, 1, 0]),
            ExtraMatchSelection(matchNumber: "7", outcomes: [3])
        ],
        mergeEnabled: true
    )

    static let currentInput = "1,2,3,4,5|CCCBC|12-19|3-11|3|4|0.15|9|2-6|QDROP0|6:310|7:3|MERGE3"


    /// SVIP6 contains exactly three selectable layers: six-S, manual NOT4 and the frozen broad package.
    static func svip6Input(numbers: [String], logic: String, extras: [String], sumRange: String, sumEnabled: Bool, noFourPosition: Int?, broadPackageEnabled: Bool) -> String {
        var fields: [String]
        if broadPackageEnabled {
            fields = "295,296,297,298,299,300|CBBBCB|13-22|1-6|1|4|0.01|14|1-5|QDROP0|FINAL=OFF|SEED=1|MKTW=0|RATE=20|OC_WLSWITCH=0-3|OCTOLON=0|OCTOL=0-1|ALLTOLON=0|ALLTOL=0-1|RUNS=0|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=2-3|RUN2ON=0|RUN2RANGE=5-7|RUN2TOL=2-3|SAMERUNS=0|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=0|SPPRODON=0|SPPROD=30.0-900.0|HODDSPRODON=1|HODDSPROD=0-2500|HODDSSUMON=0|HODDSSUM=12-16|PRIZEON=0|PRIZE=26.0-1950.0|SPRISKON=0|MAXSP=10.0|HIGHSPTH=4.5|HIGHSPCOUNT=0-2|MINPROBON=0|MINPROB=15.0|JOINTPROBON=0|JOINTPROB=0.1-100.0|VIP12PROBON=0|SVIP1ODDSGUARDON=0|VIP16TOP200ON=0|VIP18TOP200ON=0|VIP19CUSTOMTOP200ON=0|GROUPON=0|GROUPMODE=BOTH|GFSUM=0-9|GBSUM=0-6|GFSP=1.0-200.0|GBSP=1.0-100.0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=0|U247TH=-0.050756|V10TOP150ON=0|HODDSPRODCOUNT=6|MCOUNT=6|SUMCOUNT=6|CALCCOUNT=6|F5LOSS13ON=1|F5LOSSRANGE=0-5|F5WINON=1|STRUCT3ON=1|SIXSCOPE=1|PACKAGEON=1|TOP5SECOND=1|TOP5RELAX=1|FIVEWIDE=1|STRUCTRELAX=1|STRUCT3R=1-18|F6LOSS14ON=1|F5R39ON=1|F5NO000ON=0|F5WINRANGE=0-5|F5NO111ON=1|F5ACTUALM36ON=1|F5ACTUALMRANGE=0-9|SVIP5FOURCAPON=0|SVIP5DROP=0|MPERM=1|NO4LOWODDS=0|NO4=".components(separatedBy: "|")
        } else {
            fields = ["", "", "0-24", "0-100", "100", "6", "0", "100", "0-5", "QDROP0", "FINAL=OFF", "SIXSCOPE=1", "SUMCOUNT=6", "MCOUNT=6", "CALCCOUNT=6", "PACKAGEON=1", "NO4="]
        }
        fields[0] = numbers.joined(separator: ",")
        fields[1] = logic
        if sumEnabled, let range = try? parseRange(sumRange, labels: []) {
            let lower = broadPackageEnabled ? max(13, range.lowerBound) : range.lowerBound
            let upper = broadPackageEnabled ? min(22, range.upperBound) : range.upperBound
            fields[2] = lower <= upper ? "\(lower)-\(upper)" : "0-0"
        }
        fields.removeAll { $0.hasPrefix("NO4=") || $0.hasPrefix("NO4LOWODDS=") }
        fields.append("NO4SINGLE=1")
        fields.append("NO4=\(noFourPosition.map(String.init) ?? "")")
        return (fields + extras + ["MERGE3"]).joined(separator: "|")
    }

    static func svip9Input(numbers: [String], logic: String, extras: [String], sumRange: String, fixedEnabled: Bool, adaptiveEnabled: Bool, noFourPosition: Int?, broadPackageEnabled: Bool) -> String {
        var fields = svip6Input(numbers: numbers, logic: logic, extras: extras, sumRange: sumRange, sumEnabled: fixedEnabled, noFourPosition: noFourPosition, broadPackageEnabled: broadPackageEnabled).components(separatedBy: "|")
        let index = fields.firstIndex { $0.contains(":") } ?? fields.count - 1
        fields.insert("ADAPTIVES=\(adaptiveEnabled ? 1 : 0)", at: index)
        return fields.joined(separator: "|")
    }

    /// Preserve every SVIP5 flag/range; compose new S filters without overwriting the legacy S.
    static func svip9Input(inheritingSVIP5 input: String, fixedRange: String, fixedEnabled: Bool, adaptiveEnabled: Bool, legacyEnabled: Bool, compactEnabled: Bool = false, maximumAdditionalBets: Int = 50) -> String {
        let fields = input.components(separatedBy: "|")
        let boundary = fields.firstIndex { $0.contains(":") } ?? fields.count
        let extras = fields.filter { $0.contains(":") }
        var main = Array(fields.prefix(boundary)).filter { $0 != "MERGE3" }
        if !legacyEnabled {
            let noFour = main.filter { $0.hasPrefix("NO4=") || $0.hasPrefix("NO4LOWODDS=") || $0 == "NO4SINGLE=1" }
            main = [fields[0], fields[1], "0-24", "0-100", "100", "6", "0", "100", "0-5", "QDROP0", "FINAL=OFF", "SIXSCOPE=1", "SUMCOUNT=6", "MCOUNT=6", "CALCCOUNT=6"] + noFour
        }
        main.removeAll { $0.hasPrefix("PACKAGEON=") || $0.hasPrefix("ADAPTIVES=") || $0.hasPrefix("EXTRASUM=") || $0.hasPrefix("TXT50=") || $0.hasPrefix("TXTADD=") }
        main += ["PACKAGEON=1", "ADAPTIVES=\(adaptiveEnabled ? 1 : 0)", "TXT50=\(compactEnabled ? 1 : 0)", "TXTADD=\(maximumAdditionalBets)"]
        if fixedEnabled { main.append("EXTRASUM=\(fixedRange)") }
        return (main + extras + ["MERGE3"]).joined(separator: "|")
    }

    /// The original frozen160 rule is independent of editable SVIP5/SVIP9 state.
    static func svip11Input(numbers: [String], logic: String, extras: [String], enabled: Bool = true, noFourPosition: Int? = 1, sumRange: String = "14-20", mRange: String = "2-7", breakpointRange: String = "2-4", adaptiveS: Bool = false) -> String {
        ([numbers.joined(separator: ","), logic, enabled && !adaptiveS ? sumRange : "0-24", enabled ? mRange : "0-100", "100", "6", "0", "100", enabled ? breakpointRange : "0-5",
          "FINAL=OFF", "SVIP11=1", "SIX250=0", "SVIP10=0", "CALCCOUNT=5", "SUMCOUNT=6", "MCOUNT=5", "MPERM=0",
          "TXT50=0", "ADAPTIVES=\(enabled && adaptiveS ? 1 : 0)", "NO4SINGLE=1", "NO4=\(enabled ? (noFourPosition.map(String.init) ?? "") : "")", "PACKAGEON=\(enabled ? 1 : 0)"]
         + extras + ["MERGE3"]).joined(separator: "|")
    }

    static func svip10Input(numbers: [String], logic: String, extras: [String], enabled: Bool = true, scoreRange: String = "5.8-6.8", noFourPosition: Int? = nil, sumRange: String = "15-20", mRange: String = "3-7", additionalFilters: SVIP10AdditionalFilters = .init()) -> String {
        let bounds = scoreRange.split(separator: "-").map(String.init)
        let lower = bounds.count == 2 ? bounds[0] : "5.8"
        let upper = bounds.count == 2 ? bounds[1] : "6.8"
        return ([numbers.joined(separator: ","), logic, "0-24", "0-100", "100", "4", "0", "100", "0-5",
          "FINAL=OFF", "SVIP10=1", additionalFilters.protocolTokens, "SIX250=1", "SCOREMIN250=\(lower)", "SCORE250=\(upper)", "S250=\(sumRange)", "M250=\(mRange)", "R250=0-15",
          "SIXSCOPE=1", "SUMCOUNT=6", "MCOUNT=6", "CALCCOUNT=6", "TXT50=0", "ADAPTIVES=0", "NO4SINGLE=1", "NO4=\(noFourPosition.map(String.init) ?? "")", "PACKAGEON=\(enabled ? 1 : 0)"]
         + extras + ["MERGE3"]).joined(separator: "|")
    }

    /// Keep raw picker text so the shared parser can reject invalid ranges instead of resetting them.
    static func appendingSVIP10AdditionalInput(_ input: String, coldEnabled: Bool, coldRange: String, drawEnabled: Bool, drawRange: String, winLossSwitchEnabled: Bool = false, highestDoubleProbabilityTopTwoEnabled: Bool = false, secondDoubleLowestProbabilityEnabled: Bool = false, fiveMatchMEnabled: Bool = false, fiveMatchMRange: String = "2-6", frontFiveSameOutcomeRunMaximum2Enabled: Bool = false, frontFiveReturnMaximum2Enabled: Bool = false, frontFiveNoConsecutiveDrawEnabled: Bool = false, frontFiveValueThreeMaximum2Enabled: Bool = false, sixMatchFavoriteCount2To4Enabled: Bool = false, sixMatchFavoriteCount1To4Enabled: Bool = false, sixMatchMinimumOddsProductEnabled: Bool = false, sixMatchMinimumOddsProduct: String = "380", sixMatchBreakpoint3To5Enabled: Bool = false, topThreeProbabilityRecovery100Enabled: Bool = false, statisticalLineBudgetEnabled: Bool = false, probabilityMass60Enabled: Bool = false, calibratedDoubleSelectionEnabled: Bool = false, sixMatchBreakpointRange: String = "3-5", automaticDoublePairEnabled: Bool = false, judgmentFactors: Set<DoubleJudgmentFactor> = [], marketEvidence: [DoubleMarketEvidence] = [], allABCDSelectionEnabled: Bool = false, maximum105Enabled: Bool = false, frontTwoADEnabled: Bool = false, fixedFrontTwoDoublesEnabled: Bool = false, adDoublesWithinSixEnabled: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> String {
        var fields = input.components(separatedBy: "|").filter {
            !["S10COLDON=", "S10COLD=", "S10DRAWON=", "S10DRAW=", "S10WLON=", "S10DBLNO4=", "S10DBLTOP2=", "S10DBL2LOW=", "S10DBLCAL=", "S10AUTOPAIR=", "S10ABCDSELECT=", "S10FACTORS=", "S10MARKET=", "S10AUTOPOOL=", "S10F5MON=", "S10F5MSTART=", "S10F5MRANGE=", "S10F5V2ON=", "S10F5P30ON=", "S10F5RUN2ON=", "S10F5RET2ON=", "S10F5NO11ON=", "S10F5V3MAX2ON=", "S10FAV24ON=", "S10FAV14ON=", "S10ODDSPROD6ON=", "S10ODDSPROD6MIN=", "S10B24ON=", "S10B35ON=", "S10BRANGE=", "S10REC100=", "S10LINE50=", "S10MASS60=", "S10MAX105=", "S10FRONTAD=", "S10FRONTDBL=", "S10ADWITHIN6=", "S10ADCOUNT=", "S10DBLCOUNT=", "S10CAP250=", "S10CAP180="].contains(where: $0.hasPrefix)
                && $0 != "MERGE3"
        }
        // Conditions must precede the fixed matches: the parser treats every
        // field after the first "场次:彩果" as another fixed match.
        let extraStart = fields.indices.dropFirst(7).first { fields[$0].contains(":") } ?? fields.endIndex
        fields.insert(contentsOf: [
            "S10COLDON=\(coldEnabled ? 1 : 0)", "S10COLD=\(coldRange)",
            "S10DRAWON=\(drawEnabled ? 1 : 0)", "S10DRAW=\(drawRange)",
            "S10WLON=\(winLossSwitchEnabled ? 1 : 0)",
            "S10DBLNO4=0",
            "S10DBLTOP2=\(highestDoubleProbabilityTopTwoEnabled ? 1 : 0)",
            "S10DBL2LOW=\(secondDoubleLowestProbabilityEnabled ? 1 : 0)",
            "S10DBLCAL=\(calibratedDoubleSelectionEnabled ? 1 : 0)",
            "S10AUTOPAIR=\(automaticDoublePairEnabled ? 1 : 0)",
            "S10ABCDSELECT=\(allABCDSelectionEnabled ? 1 : 0)",
            "S10FACTORS=\(DoubleJudgmentFactor.text(judgmentFactors))",
            "S10MARKET=\(DoubleMarketEvidence.encoded(marketEvidence))",
            "S10F5MON=\(fiveMatchMEnabled ? 1 : 0)",
            "S10F5MRANGE=\(fiveMatchMRange)",
            "S10F5RUN2ON=\(frontFiveSameOutcomeRunMaximum2Enabled ? 1 : 0)",
            "S10F5RET2ON=\(frontFiveReturnMaximum2Enabled ? 1 : 0)",
            "S10F5NO11ON=\(frontFiveNoConsecutiveDrawEnabled ? 1 : 0)",
            "S10F5V3MAX2ON=\(frontFiveValueThreeMaximum2Enabled ? 1 : 0)",
            "S10FAV24ON=\(sixMatchFavoriteCount2To4Enabled ? 1 : 0)",
            "S10FAV14ON=\(sixMatchFavoriteCount1To4Enabled ? 1 : 0)",
            "S10ODDSPROD6ON=\(sixMatchMinimumOddsProductEnabled ? 1 : 0)",
            "S10ODDSPROD6MIN=\(sixMatchMinimumOddsProduct)",
            "S10B24ON=0",
            "S10B35ON=\(sixMatchBreakpoint3To5Enabled ? 1 : 0)",
            "S10BRANGE=\(sixMatchBreakpointRange)",
            "S10REC100=\(topThreeProbabilityRecovery100Enabled ? 1 : 0)",
            "S10LINE50=\(statisticalLineBudgetEnabled ? 1 : 0)",
            "S10MASS60=\(probabilityMass60Enabled ? 1 : 0)",
            "S10MAX105=\(maximum105Enabled ? 1 : 0)",
            "S10FRONTAD=\(frontTwoADEnabled ? 1 : 0)",
            "S10FRONTDBL=\(fixedFrontTwoDoublesEnabled ? 1 : 0)",
            "S10ADWITHIN6=\(adDoublesWithinSixEnabled ? 1 : 0)"
        ] + (adDoubleCountWithinSix == 2 ? [] : ["S10ADCOUNT=\(adDoubleCountWithinSix)"]) + (automaticDoubleCount == 2 ? [] : ["S10DBLCOUNT=\(automaticDoubleCount)"]), at: extraStart)
        fields.append("MERGE3")
        return fields.joined(separator: "|")
    }

    static func parse(_ rawInput: String) throws -> FilterConfig {
        let normalized = rawInput
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "－", with: "-")

        let fields = normalized
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count >= 10 else {
            throw FilterConfigError.invalidFieldCount
        }
        // 兼容历史记录：旧Q、断点和值4字段只跳过，不再参与过滤。

        let matches = fields[0]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard (2...8).contains(matches.count), Set(matches).count == matches.count else {
            throw FilterConfigError.invalidMatches
        }

        let logicLetters = fields[1]
            .lowercased()
            .filter { "abcd".contains($0) }
        let mappings = logicLetters.compactMap { LogicMapping(rawValue: String($0)) }
        guard mappings.count == matches.count else {
            throw FilterConfigError.logicCountMismatch(expected: matches.count)
        }

        let sumRange = try parseRange(fields[2], labels: ["s", "sum"])
        let displacementRange = try parseRange(fields[3], labels: ["m", "displacement"])
        let varianceText = stripLabel(fields[4], labels: ["v", "variance", "σ²", "σ2"])
            .replacingOccurrences(of: "<=", with: "")
            .replacingOccurrences(of: "≤", with: "")
        guard let variance = Double(varianceText), variance >= 0 else {
            throw FilterConfigError.invalidVariance
        }

        guard let valueTwoMaximum = Int(fields[5]), valueTwoMaximum >= 0 else {
            throw FilterConfigError.invalidValueTwoMaximum
        }

        guard let transitionMinimumPercent = Double(fields[6]), transitionMinimumPercent >= 0 else {
            throw FilterConfigError.invalidTransitionMinimum
        }

        guard let extraStart = fields.indices.dropFirst(7).first(where: { fields[$0].contains(":") }),
              extraStart < fields.count - 1 else {
            throw FilterConfigError.invalidExtra("固定单选")
        }
        // 新格式在索引7直接保存R；旧格式可能在它前面保留Q/断点等废弃字段。
        let legacyConditionFields = fields[7..<extraStart]
        let roughnessMaximum = legacyConditionFields.reversed().compactMap { Int($0) }.first ?? 6
        guard roughnessMaximum >= 0 else {
            throw FilterConfigError.invalidSequenceMaximum
        }
        let breakpointRange: ClosedRange<Int>
        if fields[7].contains("-") {
            // 旧格式索引7是已废弃的Q；只识别后续形如0-6的断点范围。
            breakpointRange = legacyConditionFields.dropFirst().compactMap {
                try? parseRange($0, labels: ["b", "breakpoint"])
            }.first(where: { $0.lowerBound >= 0 && $0.upperBound <= matches.count })
                ?? 0...(matches.count - 1)
        } else if legacyConditionFields.count >= 2,
                  fields[8].contains("-") {
            breakpointRange = try parseRange(fields[8], labels: ["b", "breakpoint"])
        } else {
            breakpointRange = 0...(matches.count - 1)
        }
        // 已取消乘积Q精确删注：它会把第六场全包拆成不完整选项。
        // 仍接受旧TXT中的QDROP字段，但统一按0解析，确保历史方案也不会再执行。
        let productRemovalCount = 0
        let noFourText = legacyConditionFields.first { $0.uppercased().hasPrefix("NO4=") }?.dropFirst(4) ?? ""
        let explicitSingleNoFourMode = legacyConditionFields.contains {
            $0.uppercased() == "NO4SINGLE=1"
        }
        let noFourParts = noFourText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var noFourPositions = noFourParts.compactMap(Int.init)
        guard noFourParts.count == noFourPositions.count,
              noFourPositions.allSatisfy({ (1...matches.count).contains($0) }) else {
            throw FilterConfigError.invalidRange("禁止4的位置须为1到\(matches.count)")
        }
        let frontFiveNoTripleDrawEnabled = try enabledField(prefix: "F5NO111ON=", title: "前五场无连续三场平局")
        let frontFiveLossCountEnabled = try enabledField(prefix: "F5LOSS13ON=", title: "前五场负个数范围")
        let sixScope = try enabledField(prefix: "SIXSCOPE=", title: "六场总包口径")
        let svip7Enabled = try enabledField(prefix: "SVIP7=", title: "SVIP7六场赔率排名过滤")
        if svip7Enabled {
            guard matches.count == 6 else {
                throw FilterConfigError.invalidRange("SVIP7需要完整六个主场次")
            }
            guard try !enabledField(prefix: "SIX250=", title: "六场约250注关系条件") else {
                throw FilterConfigError.invalidRange("SVIP7与六场250条件不能同时开启")
            }
        }
        let frontFiveLossCountRange = try parseRange(try uniqueFieldValue(prefix: "F5LOSSRANGE=") ?? (frontFiveLossCountEnabled ? "1-3" : "1-5"), labels: [])
        let frontFiveWinCountEnabled = try enabledField(prefix: "F5WINON=", title: "前五场胜个数范围")
        let combinedThreeStructureEnabled = try enabledField(prefix: "STRUCT3ON=", title: "三条件组合过滤")
        let combinedThreeRRange = try parseRange(try uniqueFieldValue(prefix: "STRUCT3R=") ?? "5-12", labels: [])
        guard combinedThreeRRange.lowerBound >= 0, combinedThreeRRange.upperBound <= 18 else {
            throw FilterConfigError.invalidRange("六场组合R范围须在0–18之间")
        }

        let sixLossCount14Enabled = try enabledField(prefix: "F6LOSS14ON=", title: "六场负1–4个")
        let frontFiveR39Enabled = try enabledField(prefix: "F5R39ON=", title: "前5场判定值R=3–9")
        let frontFiveNoTripleLossEnabled = try enabledField(prefix: "F5NO000ON=", title: "前5场不出现连续3场负")
        let frontFiveWinCountRange = try parseRange(try uniqueFieldValue(prefix: "F5WINRANGE=") ?? "1-5", labels: [])
        guard frontFiveLossCountRange.lowerBound >= 0, frontFiveLossCountRange.upperBound <= 5,
              frontFiveWinCountRange.lowerBound >= 0, frontFiveWinCountRange.upperBound <= 5 else {
            throw FilterConfigError.invalidRange("前五场胜/负个数范围须在0–5之间")
        }

        let frontFiveActualMEnabled = try enabledField(prefix: "F5ACTUALM36ON=", title: "前五场实际M范围")
        let frontFiveActualMRange = try parseRange(try uniqueFieldValue(prefix: "F5ACTUALMRANGE=") ?? "3-6", labels: [])
        guard frontFiveActualMRange.lowerBound >= 0, frontFiveActualMRange.upperBound <= (sixScope ? 10 : 8) else {
            throw FilterConfigError.invalidRange("实际M范围超出当前场数允许的范围")
        }

        let svip5FourCountFilterEnabled = try enabledField(prefix: "SVIP5FOURCAPON=", title: "前五场判定值4个数")
        let svip5TailText = try uniqueFieldValue(prefix: "SVIP5DROP=") ?? "0"
        guard let svip5TailRemovalCount = Int(svip5TailText), [0, 30].contains(svip5TailRemovalCount) else {
            throw FilterConfigError.invalidRange("SVIP5冷尾减注须为0或30")
        }
        let minimumDistinctDisplacementOrders = Int(try uniqueFieldValue(prefix: "MPERM=") ?? "0") ?? -1
        guard (0...120).contains(minimumDistinctDisplacementOrders) else {
            throw FilterConfigError.invalidRange("前五场M有效不同排列数须为0到120")
        }
        let lowestCustomOddsNoFourEnabled = try enabledField(
            prefix: "NO4LOWODDS=", title: "判定值4最低概率场次禁4"
        )
        var frontThreeMaximumFourCount: Int?
        if let token = legacyConditionFields.first(where: {
            $0.uppercased().hasPrefix("MAX4F3=")
        }) {
            let valueText = token.dropFirst("MAX4F3=".count)
            guard matches.count >= 3,
                  let value = Int(valueText), (0...3).contains(value) else {
                throw FilterConfigError.invalidRange("前三场判定值4上限须为0到3")
            }
            frontThreeMaximumFourCount = value
        } else {
            frontThreeMaximumFourCount = nil
        }
        let displacementMatchCount: Int?
        if let token = legacyConditionFields.first(where: {
            $0.uppercased().hasPrefix("MCOUNT=")
        }) {
            let valueText = token.dropFirst("MCOUNT=".count)
            guard let value = Int(valueText), (2...matches.count).contains(value) else {
                throw FilterConfigError.invalidRange("M计算场数须为2到\(matches.count)")
            }
            displacementMatchCount = value
        } else {
            displacementMatchCount = nil
        }
        let sumMatchCount: Int?
        if let token = legacyConditionFields.first(where: {
            $0.uppercased().hasPrefix("SUMCOUNT=")
        }) {
            let valueText = token.dropFirst("SUMCOUNT=".count)
            guard let value = Int(valueText), (2...matches.count).contains(value) else {
                throw FilterConfigError.invalidRange("S计算场数须为2到\(matches.count)")
            }
            sumMatchCount = value
        } else {
            sumMatchCount = nil
        }
        let calculationMatchCount: Int?
        if let token = legacyConditionFields.first(where: {
            $0.uppercased().hasPrefix("CALCCOUNT=")
        }) {
            let valueText = token.dropFirst("CALCCOUNT=".count)
            guard let value = Int(valueText), (2...matches.count).contains(value) else {
                throw FilterConfigError.invalidRange("条件计算场数须为2到\(matches.count)")
            }
            calculationMatchCount = value
        } else {
            calculationMatchCount = nil
        }
        let sumUsesOutcomeSP = legacyConditionFields.contains {
            $0.uppercased() == "REALSUM=1"
        }
        // VIP6/7/8的六场方案已把旧“指定一场不是4”替换为
        // “前三场判定值4最多1个”。旧快照仍会携带NO4，解析时自动迁移。
        if matches.count == 6,
           frontThreeMaximumFourCount == nil,
           !noFourPositions.isEmpty,
           !explicitSingleNoFourMode {
            noFourPositions = []
            frontThreeMaximumFourCount = 1
        }

        var outcomeConditions: [OutcomeCondition: ClosedRange<Int>] = [:]
        for field in legacyConditionFields where field.uppercased().hasPrefix("OC_") {
            let parts = field.uppercased().split(separator: "=", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let condition = OutcomeCondition(rawValue: String(parts[0].dropFirst(3))),
                  outcomeConditions[condition] == nil else {
                throw FilterConfigError.invalidRange("新增彩果条件：\(field)")
            }
            let range = try parseRange(String(parts[1]), labels: [])
            guard range.lowerBound >= 0, range.upperBound <= condition.maximum(matchCount: matches.count) else {
                throw FilterConfigError.invalidRange("\(condition.title)须在0–\(condition.maximum(matchCount: matches.count))内")
            }
            outcomeConditions[condition] = range
        }

        func uniqueFieldValue(prefix: String) throws -> String? {
            let matching = legacyConditionFields.filter { $0.uppercased().hasPrefix(prefix) }
            guard matching.count <= 1 else {
                throw FilterConfigError.invalidRange("连续彩果条件重复")
            }
            return matching.first.map { String($0.dropFirst(prefix.count)) }
        }
        func enabledField(prefix: String, title: String, default defaultValue: Bool = false) throws -> Bool {
            switch try uniqueFieldValue(prefix: prefix)?.uppercased() {
            case nil: return defaultValue
            case "0", "OFF": return false
            case "1", "ON": return true
            default: throw FilterConfigError.invalidRange("\(title)开关无效")
            }
        }
        func doubleRangeField(prefix: String, title: String, default defaultValue: ClosedRange<Double>) throws -> ClosedRange<Double> {
            guard let text = try uniqueFieldValue(prefix: prefix) else { return defaultValue }
            let range = try parseDoubleRange(text)
            guard range.lowerBound >= 0, range.upperBound.isFinite else {
                throw FilterConfigError.invalidRange("\(title)须为非负数区间")
            }
            return range
        }
        let outcomeConditionToleranceEnabled = try enabledField(
            prefix: "OCTOLON=",
            title: "彩果条件容错"
        )
        let outcomeConditionToleranceText = try uniqueFieldValue(prefix: "OCTOL=") ?? "0-0"
        let outcomeConditionToleranceRange = try parseRange(outcomeConditionToleranceText, labels: [])
        guard outcomeConditionToleranceRange.lowerBound >= 0,
              outcomeConditionToleranceRange.upperBound <= OutcomeCondition.activeCases.count,
              (!outcomeConditionToleranceEnabled || !outcomeConditions.isEmpty) else {
            throw FilterConfigError.invalidRange("彩果条件容错项数须在0–\(OutcomeCondition.activeCases.count)内")
        }
        let allConditionsToleranceEnabled = try enabledField(
            prefix: "ALLTOLON=",
            title: "全部条件容错"
        )
        let allConditionsToleranceText = try uniqueFieldValue(prefix: "ALLTOL=") ?? "0-0"
        let allConditionsToleranceRange = try parseRange(allConditionsToleranceText, labels: [])
        guard allConditionsToleranceRange.lowerBound >= 0,
              allConditionsToleranceRange.upperBound <= 30 else {
            throw FilterConfigError.invalidRange("全部条件容错项数须在0–30内")
        }
        let consecutiveRunsEnabled: Bool
        switch try uniqueFieldValue(prefix: "RUNS=")?.uppercased() ?? "0" {
        case "0", "OFF": consecutiveRunsEnabled = false
        case "1", "ON": consecutiveRunsEnabled = true
        default: throw FilterConfigError.invalidRange("连续彩果条件开关无效")
        }
        func consecutiveRange(prefix: String, title: String) throws -> ClosedRange<Int> {
            let text = try uniqueFieldValue(prefix: prefix) ?? "3-7"
            let range = try parseRange(text, labels: [])
            guard range.lowerBound >= 3, range.upperBound <= 7 else {
                throw FilterConfigError.invalidRange("\(title)须在3–7内")
            }
            return range
        }
        let nonLossRunRange = try consecutiveRange(prefix: "NLRUN=", title: "连续不败")
        let nonDrawRunRange = try consecutiveRange(prefix: "NDRUN=", title: "连续不平")
        let nonWinRunRange = try consecutiveRange(prefix: "NWRUN=", title: "连续不胜")
        let toleranceText = try uniqueFieldValue(prefix: "RUNTOL=") ?? "0-1"
        let consecutiveRunToleranceRange = try parseRange(toleranceText, labels: [])
        guard consecutiveRunToleranceRange.lowerBound >= 0,
              consecutiveRunToleranceRange.upperBound <= 3 else {
            throw FilterConfigError.invalidRange("连续彩果容错范围须在0–3内")
        }
        let secondaryConsecutiveRunsEnabled = try enabledField(
            prefix: "RUN2ON=",
            title: "连续彩果第二档"
        )
        let secondaryRangeText = try uniqueFieldValue(prefix: "RUN2RANGE=") ?? "5-7"
        let secondaryConsecutiveRunRange = try parseRange(secondaryRangeText, labels: [])
        guard secondaryConsecutiveRunRange.lowerBound >= 3,
              secondaryConsecutiveRunRange.upperBound <= 7 else {
            throw FilterConfigError.invalidRange("连续彩果第二档须在3–7内")
        }
        let secondaryToleranceText = try uniqueFieldValue(prefix: "RUN2TOL=") ?? "2-3"
        let secondaryConsecutiveRunToleranceRange = try parseRange(secondaryToleranceText, labels: [])
        guard secondaryConsecutiveRunToleranceRange.lowerBound >= 0,
              secondaryConsecutiveRunToleranceRange.upperBound <= 3 else {
            throw FilterConfigError.invalidRange("连续彩果第二档容错范围须在0–3内")
        }

        let sameResultRunsEnabled: Bool
        switch try uniqueFieldValue(prefix: "SAMERUNS=")?.uppercased() ?? "0" {
        case "0", "OFF": sameResultRunsEnabled = false
        case "1", "ON": sameResultRunsEnabled = true
        default: throw FilterConfigError.invalidRange("连续胜平负条件开关无效")
        }
        func sameResultRange(prefix: String, title: String) throws -> ClosedRange<Int> {
            let text = try uniqueFieldValue(prefix: prefix) ?? "2-7"
            let range = try parseRange(text, labels: [])
            guard range.lowerBound >= 2, range.upperBound <= 7 else {
                throw FilterConfigError.invalidRange("\(title)须在2–7内")
            }
            return range
        }
        let winRunRange = try sameResultRange(prefix: "WINRUN=", title: "连续胜")
        let drawRunRange = try sameResultRange(prefix: "DRAWRUN=", title: "连续平")
        let lossRunRange = try sameResultRange(prefix: "LOSSRUN=", title: "连续负")
        let sameResultToleranceText = try uniqueFieldValue(prefix: "SAMERUNTOL=") ?? "2-3"
        let sameResultRunToleranceRange = try parseRange(sameResultToleranceText, labels: [])
        guard sameResultRunToleranceRange.lowerBound >= 0,
              sameResultRunToleranceRange.upperBound <= 3 else {
            throw FilterConfigError.invalidRange("连续胜平负容错范围须在0–3内")
        }
        let protectConsecutiveDrawPair = try enabledField(
            prefix: "PROTECT11=",
            title: "连续两个1保护"
        )

        let spProductFilterEnabled = try enabledField(prefix: "SPPRODON=", title: "SP乘积")
        let spProductRange = try doubleRangeField(prefix: "SPPROD=", title: "SP乘积", default: 20...1500)
        let customHandicapOddsProductFilterEnabled = try enabledField(
            prefix: "HODDSPRODON=",
            title: "自定义让球赔率乘积"
        )
        let customHandicapOddsProductRange = try parseRange(
            try uniqueFieldValue(prefix: "HODDSPROD=") ?? "50-300",
            labels: []
        )
        guard customHandicapOddsProductRange.lowerBound >= 0,
              customHandicapOddsProductRange.upperBound <= 5000,
              customHandicapOddsProductRange.lowerBound.isMultiple(of: 50),
              customHandicapOddsProductRange.upperBound.isMultiple(of: 50) else {
            throw FilterConfigError.invalidRange("自定义让球赔率乘积须在0–5000内且每50一档")
        }
        let customHandicapOddsProductMatchCount: Int?
        if let text = try uniqueFieldValue(prefix: "HODDSPRODCOUNT="),
           let value = Int(text), value > 0 {
            guard value <= matches.count else {
                throw FilterConfigError.invalidRange("自定义让球赔率乘积场次数须在1–\(matches.count)内")
            }
            customHandicapOddsProductMatchCount = value
        } else {
            customHandicapOddsProductMatchCount = nil
        }
        let customHandicapOddsSumFilterEnabled = try enabledField(
            prefix: "HODDSSUMON=",
            title: "自定义让球赔率和值"
        )
        let customHandicapOddsSumRange = try parseRange(
            try uniqueFieldValue(prefix: "HODDSSUM=") ?? "12-16",
            labels: []
        )
        guard customHandicapOddsSumRange.lowerBound >= 0,
              customHandicapOddsSumRange.upperBound <= 100 else {
            throw FilterConfigError.invalidRange("自定义让球赔率和值须在0–100内")
        }
        let prizeRangeFilterEnabled = try enabledField(prefix: "PRIZEON=", title: "预计奖金")
        let estimatedPrizeRange = try doubleRangeField(prefix: "PRIZE=", title: "预计奖金", default: 26...1950)
        let spRiskFilterEnabled = try enabledField(prefix: "SPRISKON=", title: "SP风险")
        let maximumSingleSP = try uniqueFieldValue(prefix: "MAXSP=").flatMap(Double.init) ?? 5
        let highSPThreshold = try uniqueFieldValue(prefix: "HIGHSPTH=").flatMap(Double.init) ?? 4
        let highSPCountText = try uniqueFieldValue(prefix: "HIGHSPCOUNT=") ?? "0-1"
        let highSPCountRange = try parseRange(highSPCountText, labels: [])
        guard maximumSingleSP > 0, maximumSingleSP.isFinite,
              highSPThreshold > 0, highSPThreshold.isFinite,
              highSPCountRange.lowerBound >= 0,
              highSPCountRange.upperBound <= matches.count else {
            throw FilterConfigError.invalidRange("SP风险参数无效")
        }
        let minimumProbabilityFilterEnabled = try enabledField(prefix: "MINPROBON=", title: "最低单场概率")
        let minimumSingleProbabilityPercent = try uniqueFieldValue(prefix: "MINPROB=").flatMap(Double.init) ?? 15
        guard minimumSingleProbabilityPercent.isFinite,
              (0...100).contains(minimumSingleProbabilityPercent) else {
            throw FilterConfigError.invalidRange("最低单场概率须在0–100%内")
        }
        let jointProbabilityFilterEnabled = try enabledField(prefix: "JOINTPROBON=", title: "整串全中概率")
        let jointProbabilityPercentRange = try doubleRangeField(
            prefix: "JOINTPROB=",
            title: "整串全中概率",
            default: 0.1...100
        )
        guard jointProbabilityPercentRange.upperBound <= 100 else {
            throw FilterConfigError.invalidRange("整串全中概率须在0–100%内")
        }
        let svip10ColdRange = try parseRange(try uniqueFieldValue(prefix: "S10COLD=") ?? "0-2", labels: [])
        let svip10DrawRange = try parseRange(try uniqueFieldValue(prefix: "S10DRAW=") ?? "0-3", labels: [])
        let svip10FiveMatchMRange = try parseRange(try uniqueFieldValue(prefix: "S10F5MRANGE=") ?? "3-6", labels: [])
        let svip10BreakpointRange = try parseRange(try uniqueFieldValue(prefix: "S10BRANGE=") ?? "3-5", labels: [])
        guard svip10BreakpointRange.lowerBound >= 0, svip10BreakpointRange.upperBound <= 5 else {
            throw FilterConfigError.invalidRange("SVIP10六场断点数范围须在0–5内")
        }
        let svip10SixMatchMinimumOddsProduct = try uniqueFieldValue(prefix: "S10ODDSPROD6MIN=").flatMap(Double.init) ?? 380
        guard svip10ColdRange.lowerBound >= 0, svip10ColdRange.upperBound <= 6,
              svip10DrawRange.lowerBound >= 0, svip10DrawRange.upperBound <= 6 else {
            throw FilterConfigError.invalidRange("SVIP10新增个数范围须在0–6内")
        }
        guard svip10FiveMatchMRange.lowerBound >= 0, svip10FiveMatchMRange.upperBound <= 8 else {
            throw FilterConfigError.invalidRange("SVIP10前5场实际M范围须在0–8内")
        }
        guard svip10SixMatchMinimumOddsProduct.isFinite, svip10SixMatchMinimumOddsProduct > 0 else {
            throw FilterConfigError.invalidRange("SVIP10前六场自定义赔率乘积下限须大于0")
        }
        guard let judgmentFactors = DoubleJudgmentFactor.parse(try uniqueFieldValue(prefix: "S10FACTORS=") ?? ""),
              let marketEvidence = DoubleMarketEvidence.decoded(try uniqueFieldValue(prefix: "S10MARKET=") ?? ""),
              marketEvidence.allSatisfy({ matches.compactMap(Int.init).contains($0.number) }) else {
            throw FilterConfigError.invalidRange("双选判断因素或赛前市场快照无效")
        }
        guard let adDoubleCountWithinSix = Int(try uniqueFieldValue(prefix: "S10ADCOUNT=") ?? "2"),
              (1...2).contains(adDoubleCountWithinSix) else {
            throw FilterConfigError.invalidRange("六场内A/D双选场数只允许1或2")
        }
        guard let automaticDoubleCount = Int(try uniqueFieldValue(prefix: "S10DBLCOUNT=") ?? "2"), (1...2).contains(automaticDoubleCount) else {
            throw FilterConfigError.invalidRange("自动双选场数只允许1或2")
        }
        let svip10Additions = SVIP10AdditionalFilters(
            coldCountEnabled: try enabledField(prefix: "S10COLDON=", title: "六场赔率第三选个数"),
            coldCountRange: svip10ColdRange,
            drawCountEnabled: try enabledField(prefix: "S10DRAWON=", title: "六场平局个数"),
            drawCountRange: svip10DrawRange,
            winLossSwitchEnabled: try enabledField(prefix: "S10WLON=", title: "前5场胜负直接切换0–2"),
            highestDoubleProbabilityNoFourEnabled: try enabledField(prefix: "S10DBLNO4=", title: "双选概率最高场次不是4"),
            highestDoubleProbabilityTopTwoEnabled: try enabledField(prefix: "S10DBLTOP2=", title: "最适合双选场次保留概率前两项"),
            secondDoubleLowestProbabilityEnabled: try enabledField(prefix: "S10DBL2LOW=", title: "第二个双选场次去掉最低概率项"),
            calibratedDoubleSelectionEnabled: try enabledField(prefix: "S10DBLCAL=", title: "双选概率校正"),
            automaticDoublePairEnabled: try enabledField(prefix: "S10AUTOPAIR=", title: "自动择优双选"),
            allABCDSelectionEnabled: try enabledField(prefix: "S10ABCDSELECT=", title: "六场补齐ABCD自动选场"),
            doubleJudgmentFactors: judgmentFactors, doubleMarketEvidence: marketEvidence,
            fiveMatchMEnabled: try enabledField(prefix: "S10F5MON=", title: "前5场实际M范围"),
            fiveMatchMRange: svip10FiveMatchMRange,
            frontFiveSameOutcomeRunMaximum2Enabled: try enabledField(prefix: "S10F5RUN2ON=", title: "前5场同彩果最长连续2场"),
            frontFiveReturnMaximum2Enabled: try enabledField(prefix: "S10F5RET2ON=", title: "前5场隔场回返最多2次"),
            frontFiveNoConsecutiveDrawEnabled: try enabledField(prefix: "S10F5NO11ON=", title: "前5场不连续平局"),
            frontFiveValueThreeMaximum2Enabled: try enabledField(prefix: "S10F5V3MAX2ON=", title: "前5场判定值3最多2个"),
            sixMatchFavoriteCount2To4Enabled: try enabledField(prefix: "S10FAV24ON=", title: "六场自定义赔率第一选2–4个"),
            sixMatchFavoriteCount1To4Enabled: try enabledField(prefix: "S10FAV14ON=", title: "六场自定义赔率第一选1–4个"),
            sixMatchMinimumOddsProductEnabled: try enabledField(prefix: "S10ODDSPROD6ON=", title: "前六场自定义赔率乘积下限"),
            sixMatchMinimumOddsProduct: svip10SixMatchMinimumOddsProduct,
            sixMatchBreakpoint2To4Enabled: try enabledField(prefix: "S10B24ON=", title: "六场彩果断点2–4"),
            sixMatchBreakpoint3To5Enabled: try enabledField(prefix: "S10B35ON=", title: "六场彩果断点3–5"),
            sixMatchBreakpointRange: svip10BreakpointRange,
            topThreeProbabilityRecovery100Enabled: try enabledField(prefix: "S10REC100=", title: "联合概率优先补回最多100注"),
            statisticalLineBudgetEnabled: try enabledField(prefix: "S10LINE50=", title: "SVIP10统计优选50行"),
            probabilityMass60Enabled: try enabledField(prefix: "S10MASS60=", title: "SVIP10概率质量优选60行"),
            maximum105Enabled: try enabledField(prefix: "S10MAX105=", title: "最多105注"),
            fixedFrontTwoDoublesEnabled: try enabledField(prefix: "S10FRONTDBL=", title: "前两场胜负倾向双选"),
            frontTwoADEnabled: try enabledField(prefix: "S10FRONTAD=", title: "前两场只选A/D"),
            adDoublesWithinSixEnabled: try enabledField(prefix: "S10ADWITHIN6=", title: "六场内A/D双选"),
            adDoubleCountWithinSix: adDoubleCountWithinSix, automaticDoubleCount: automaticDoubleCount)
        let vip12ProbabilityReductionEnabled = try enabledField(
            prefix: "VIP12PROBON=",
            title: "VIP12联合概率减注"
        )
        let svip1CustomOddsGuardEnabled = try enabledField(
            prefix: "SVIP1ODDSGUARDON=",
            title: "SVIP1自定义赔率冷尾保护"
        )
        let vip16Top200Enabled = try enabledField(
            prefix: "VIP16TOP200ON=",
            title: "VIP16联合概率前200注"
        )
        let vip18Top200Enabled = try enabledField(
            prefix: "VIP18TOP200ON=",
            title: "VIP18校准概率前200注"
        )
        let vip19CustomOddsTop200Enabled = try enabledField(
            prefix: "VIP19CUSTOMTOP200ON=",
            title: "VIP19六场自定义赔率乘积及前200注"
        )
        let groupFilterEnabled = try enabledField(prefix: "GROUPON=", title: "分组过滤")
        let prizeStatisticalConditionEnabled = try enabledField(
            prefix: "PRIZESTATON=",
            title: "奖金统计条件"
        )
        let prizeStatisticalCountPatternEnabled = try enabledField(
            prefix: "PRIZECOUNTON=",
            title: "奖金胜平配比条件"
        )
        let universal150CompressionEnabled = try enabledField(
            prefix: "U150ON=",
            title: "通用150注统计压缩"
        )
        let universal247ToleranceEnabled = try enabledField(
            prefix: "U247ON=",
            title: "通用247综合容错"
        )
        let universal247ToleranceThreshold = try uniqueFieldValue(prefix: "U247TH=")
            .flatMap(Double.init) ?? -0.050756
        guard universal247ToleranceThreshold.isFinite,
              (-10...10).contains(universal247ToleranceThreshold) else {
            throw FilterConfigError.invalidRange("通用247阈值须在-10到10之间")
        }
        let productSumV10Top150Enabled = try enabledField(
            prefix: "V10TOP150ON=",
            title: "V10的V8联合评分前150注"
        )
        guard let groupFilterMode = GroupFilterMode(
            rawValue: try uniqueFieldValue(prefix: "GROUPMODE=")?.uppercased() ?? "BOTH"
        ) else {
            throw FilterConfigError.invalidRange("分组过滤模式无效")
        }
        let frontCount = min(3, matches.count)
        let backCount = matches.count - frontCount
        let frontGroupOutcomeSumRange = try parseRange(
            try uniqueFieldValue(prefix: "GFSUM=") ?? "0-\(frontCount * 3)", labels: []
        )
        let backGroupOutcomeSumRange = try parseRange(
            try uniqueFieldValue(prefix: "GBSUM=") ?? "0-\(max(0, backCount * 3))", labels: []
        )
        let frontGroupSPProductRange = try doubleRangeField(
            prefix: "GFSP=", title: "前组SP乘积", default: 1...200
        )
        let backGroupSPProductRange = try doubleRangeField(
            prefix: "GBSP=", title: "后组SP乘积", default: 1...100
        )
        guard !groupFilterEnabled || backCount > 0,
              frontGroupOutcomeSumRange.lowerBound >= 0,
              frontGroupOutcomeSumRange.upperBound <= frontCount * 3,
              backGroupOutcomeSumRange.lowerBound >= 0,
              backGroupOutcomeSumRange.upperBound <= backCount * 3 else {
            throw FilterConfigError.invalidRange("分组和值范围超出当前场次")
        }

        let reductionFields = legacyConditionFields.filter { $0.uppercased().hasPrefix("FINAL=") }
        let seedFields = legacyConditionFields.filter { $0.uppercased().hasPrefix("SEED=") }
        guard reductionFields.count <= 1, seedFields.count <= 1,
              let reduction = FinalReductionMode(rawValue: reductionFields.first.map { String($0.dropFirst(6)).uppercased() } ?? "OFF"),
              let seed = UInt64(seedFields.first.map { String($0.dropFirst(5)) } ?? "1") else {
            throw FilterConfigError.invalidRange("最终减半模式或随机种子无效；种子须为非负整数")
        }

        let rateFields = legacyConditionFields.filter { $0.uppercased().hasPrefix("RATE=") }
        guard rateFields.count <= 1,
              let rate = Int(rateFields.first.map { String($0.dropFirst(5)) } ?? "50"),
              [20, 30, 50].contains(rate) else {
            throw FilterConfigError.invalidRange("最终压缩比例须为20、30或50")
        }
        let marketFields = legacyConditionFields.filter { $0.uppercased().hasPrefix("MKTW=") }
        guard marketFields.count <= 1,
              let marketWeight = Int(marketFields.first.map { String($0.dropFirst(5)) } ?? "15"),
              (0...30).contains(marketWeight) else {
            throw FilterConfigError.invalidRange("市场占比权重须为0到30")
        }
        let extras = try fields[extraStart..<(fields.count - 1)].enumerated().map { offset, field in
            try parseExtra(field, label: offset == 0 ? "固定单选" : "固定项")
        }
        // 全局答案使用“前5场主项＋第6场全包310”生成完整729注，
        // 这种合法的六串配置不需要再虚构一个第7场单选。
        let allMatchNumbers = matches + extras.map(\.matchNumber)
        guard Set(allMatchNumbers).count == allMatchNumbers.count else {
            throw FilterConfigError.duplicateMatchNumber
        }

        let mergeToken = fields[fields.count - 1].uppercased()
        let merge = mergeToken == "MERGE3" || mergeToken.contains("三场相同")
        guard merge else {
            throw FilterConfigError.invalidMergeMode
        }

        let scoreText = try uniqueFieldValue(prefix: "SCORE250=") ?? "6.517035527170335"
        guard let scoreUpper = Double(scoreText), scoreUpper.isFinite, scoreUpper >= 0 else { throw FilterConfigError.invalidRange("综合评分上限必须为非负有限数") }
        let scoreLowerText = try uniqueFieldValue(prefix: "SCOREMIN250=")
        let scoreLower = scoreLowerText.flatMap(Double.init) ?? -Double.greatestFiniteMagnitude
        guard scoreLower.isFinite, scoreLower <= scoreUpper,
              scoreLowerText == nil || Double(scoreLowerText!) != nil else {
            throw FilterConfigError.invalidRange("综合评分起点必须为非负有限数，且不超过终点")
        }
        let txtBudgetText = try uniqueFieldValue(prefix: "TXTADD=") ?? "50"
        guard let txtBudget = Int(txtBudgetText), (0...200).contains(txtBudget) else { throw FilterConfigError.invalidRange("补注上限必须在0–200注之间") }
        let disabledNames = (try uniqueFieldValue(prefix: "BASEOFF=") ?? "")
            .split(separator: ",").map(String.init)
        let disabledRules = disabledNames.compactMap(BasicCondition.init(rawValue:))
        guard disabledRules.count == disabledNames.count,
              Set(disabledRules).count == disabledRules.count else {
            throw FilterConfigError.invalidRange("基础条件开关包含未知或重复项目")
        }
        let valueThreeText = try uniqueFieldValue(prefix: "VALUE3MAX=") ?? "5"
        guard let valueThreeMaximum = Int(valueThreeText), (0...8).contains(valueThreeMaximum) else {
            throw FilterConfigError.invalidRange("判定值3最多个数须为0–8的整数")
        }
        let finalResultInverted = try enabledField(prefix: "RESULTINVERT=", title: "反选")
        let finalOutcomeExclusions = try (1...2).compactMap { slot -> FinalOutcomeExclusion? in
            guard let text = try uniqueFieldValue(prefix: "RESULTCUT\(slot)=") else { return nil }
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2, let position = Int(parts[0]), (1...6).contains(position),
                  let outcome = Int(parts[1]), [3, 1, 0].contains(outcome) else {
                throw FilterConfigError.invalidRange("独立剔除\(slot)须选择第1–6场和一个彩果3、1或0")
            }
            return FinalOutcomeExclusion(slot: slot, position: position, outcome: outcome)
        }
        let automaticFinalOutcomeExclusions = try enabledField(prefix: "RESULTAUTO=", title: "自动推荐独立剔除")
        let historyText = try uniqueFieldValue(prefix: "RESULTWINDOWS=") ?? ""
        let historicalOutcomeWindows = historyText.isEmpty ? [] : historyText.components(separatedBy: ",").compactMap(Int.init)
        let historicalOutcomeBeforeIssue = try uniqueFieldValue(prefix: "RESULTBEFORE=") ?? ""
        guard historyText.isEmpty || (historicalOutcomeWindows.count == historyText.components(separatedBy: ",").count
            && Set(historicalOutcomeWindows).count == historicalOutcomeWindows.count
            && historicalOutcomeWindows.allSatisfy({ [50, 100, 150, 200].contains($0) })
            && historicalOutcomeBeforeIssue.count == 5 && historicalOutcomeBeforeIssue.allSatisfy(\.isNumber)) else {
            throw FilterConfigError.invalidRange("历史彩果去重须选择50/100/150/200组，并输入5位期号（不支持日期）")
        }
        guard !finalResultInverted && finalOutcomeExclusions.isEmpty && historicalOutcomeWindows.isEmpty && !automaticFinalOutcomeExclusions || matches.count == 6 else {
            throw FilterConfigError.invalidRange("反选及独立剔除需要完整六个主场次")
        }
        return FilterConfig(
            disabledBasicConditions: Set(disabledRules),
            valueThreeMaximum: valueThreeMaximum,
            matchNumbers: matches,
            logic: mappings,
            sumRange: sumRange,
            displacementRange: displacementRange,
            displacementMatchCount: sixScope ? 6 : displacementMatchCount,
            sumMatchCount: sumMatchCount,
            calculationMatchCount: sixScope ? 6 : calculationMatchCount,
            sumUsesOutcomeSP: sumUsesOutcomeSP,
            varianceMaximum: variance,
            valueTwoMaximum: valueTwoMaximum,
            transitionMinimumPercent: transitionMinimumPercent,
            roughnessMaximum: roughnessMaximum,
            breakpointRange: breakpointRange,
            productRemovalCount: productRemovalCount,
            noFourPositions: Array(Set(noFourPositions)).sorted(),
            minimumDistinctDisplacementOrders: minimumDistinctDisplacementOrders,
            svip5TailRemovalCount: svip5TailRemovalCount,
            svip5FourCountFilterEnabled: svip5FourCountFilterEnabled,
            frontFiveActualMEnabled: frontFiveActualMEnabled,
            frontFiveActualMRange: frontFiveActualMRange,
            frontFiveNoTripleDrawEnabled: frontFiveNoTripleDrawEnabled,
            frontFiveLossCountEnabled: frontFiveLossCountEnabled,
            frontFiveLossCountRange: frontFiveLossCountRange,
            frontFiveWinCountEnabled: frontFiveWinCountEnabled,
            combinedThreeStructureEnabled: combinedThreeStructureEnabled,
            svip11BreakpointOnlyEnabled: try enabledField(prefix: "SVIP11=", title: "SVIP11仅断点和禁4"),
            svip10Frozen160Enabled: try enabledField(prefix: "SVIP10=", title: "SVIP10原约160注方案"),
            svip10AdditionalFilters: svip10Additions,
            six250ScoreLower: scoreLower,
            six250ScoreUpper: scoreUpper,
            txtCompactEnabled: try enabledField(prefix: "TXT50=", title: "TXT补注压行"),
            maximumTXTAdditionalBets: txtBudget,
            additionalSumRange: try uniqueFieldValue(prefix: "EXTRASUM=").map { try parseRange($0, labels: []) },
            oddsAdaptiveSRangeEnabled: try enabledField(prefix: "ADAPTIVES=", title: "赔率自适应S范围"),
            six250SumRange: try parseRange(try uniqueFieldValue(prefix: "S250=") ?? "12-22", labels: []),
            six250MRange: try parseRange(try uniqueFieldValue(prefix: "M250=") ?? "0-7", labels: []),
            six250RRange: try parseRange(try uniqueFieldValue(prefix: "R250=") ?? "0-14", labels: []),
            six250RelationshipEnabled: try enabledField(prefix: "SIX250=", title: "六场约250注关系条件"),
            svip7RankOddsEnabled: svip7Enabled,
            sixMatchPackageScope: sixScope,
            conditionPackageEnabled: try uniqueFieldValue(prefix: "PACKAGEON=") == nil ? true : enabledField(prefix: "PACKAGEON=", title: "条件总包开关"),
            highPass93GroupEnabled: try uniqueFieldValue(prefix: "HP93GROUP=") == nil ? nil : enabledField(prefix: "HP93GROUP=", title: "40条条件总开关"),
            highPass98GroupEnabled: try uniqueFieldValue(prefix: "HP98GROUP=") == nil ? nil : enabledField(prefix: "HP98GROUP=", title: "100条条件总开关"),
            highPass98FiftyGroupEnabled: try uniqueFieldValue(prefix: "HP98FIFTYGROUP=") == nil ? nil : enabledField(prefix: "HP98FIFTYGROUP=", title: "50条条件总开关"),
            highPass50DoubleEnabled: try enabledField(prefix: "HP50DOUBLE=", title: "某一场自动双选"),
            topFiveSecondRelaxed: try enabledField(prefix: "TOP5SECOND=", title: "前五项第二次放宽"),
            topFiveRelaxed: try enabledField(prefix: "TOP5RELAX=", title: "前五项放宽"),
            widerFiveConditions: try enabledField(prefix: "FIVEWIDE=", title: "五项放宽范围"),
            expandedStructureRanges: try enabledField(prefix: "STRUCTRELAX=", title: "扩展结构范围"),
            combinedThreeRRange: combinedThreeRRange,
            sixLossCount14Enabled: sixLossCount14Enabled,
            frontFiveR39Enabled: frontFiveR39Enabled,
            frontFiveNoTripleLossEnabled: frontFiveNoTripleLossEnabled,
            frontFiveWinCountRange: frontFiveWinCountRange,
            lowestCustomOddsNoFourEnabled: lowestCustomOddsNoFourEnabled,
            frontThreeMaximumFourCount: frontThreeMaximumFourCount,
            probabilityRemovalPercent: 50,
            extraMatches: extras,
            mergeEnabled: merge,
            outcomeConditions: outcomeConditions,
            outcomeConditionToleranceEnabled: outcomeConditionToleranceEnabled,
            outcomeConditionToleranceRange: outcomeConditionToleranceRange,
            allConditionsToleranceEnabled: allConditionsToleranceEnabled,
            allConditionsToleranceRange: allConditionsToleranceRange,
            finalReduction: reduction,
            randomSeed: seed,
            marketWeightPercent: marketWeight,
            finalRemovalPercent: rate,
            consecutiveRunsEnabled: consecutiveRunsEnabled,
            nonLossRunRange: nonLossRunRange,
            nonDrawRunRange: nonDrawRunRange,
            nonWinRunRange: nonWinRunRange,
            consecutiveRunToleranceRange: consecutiveRunToleranceRange,
            secondaryConsecutiveRunsEnabled: secondaryConsecutiveRunsEnabled,
            secondaryConsecutiveRunRange: secondaryConsecutiveRunRange,
            secondaryConsecutiveRunToleranceRange: secondaryConsecutiveRunToleranceRange,
            sameResultRunsEnabled: sameResultRunsEnabled,
            winRunRange: winRunRange,
            drawRunRange: drawRunRange,
            lossRunRange: lossRunRange,
            sameResultRunToleranceRange: sameResultRunToleranceRange,
            protectConsecutiveDrawPair: protectConsecutiveDrawPair,
            spProductFilterEnabled: spProductFilterEnabled,
            spProductRange: spProductRange,
            customHandicapOddsProductFilterEnabled: customHandicapOddsProductFilterEnabled,
            customHandicapOddsProductRange: customHandicapOddsProductRange,
            customHandicapOddsProductMatchCount: customHandicapOddsProductMatchCount,
            customHandicapOddsSumFilterEnabled: customHandicapOddsSumFilterEnabled,
            customHandicapOddsSumRange: customHandicapOddsSumRange,
            prizeRangeFilterEnabled: prizeRangeFilterEnabled,
            estimatedPrizeRange: estimatedPrizeRange,
            spRiskFilterEnabled: spRiskFilterEnabled,
            maximumSingleSP: maximumSingleSP,
            highSPThreshold: highSPThreshold,
            highSPCountRange: highSPCountRange,
            minimumProbabilityFilterEnabled: minimumProbabilityFilterEnabled,
            minimumSingleProbabilityPercent: minimumSingleProbabilityPercent,
            jointProbabilityFilterEnabled: jointProbabilityFilterEnabled,
            jointProbabilityPercentRange: jointProbabilityPercentRange,
            vip12ProbabilityReductionEnabled: vip12ProbabilityReductionEnabled,
            svip1CustomOddsGuardEnabled: svip1CustomOddsGuardEnabled,
            vip16Top200Enabled: vip16Top200Enabled,
            vip18Top200Enabled: vip18Top200Enabled,
            vip19CustomOddsTop200Enabled: vip19CustomOddsTop200Enabled,
            groupFilterEnabled: groupFilterEnabled,
            groupFilterMode: groupFilterMode,
            frontGroupOutcomeSumRange: frontGroupOutcomeSumRange,
            backGroupOutcomeSumRange: backGroupOutcomeSumRange,
            frontGroupSPProductRange: frontGroupSPProductRange,
            backGroupSPProductRange: backGroupSPProductRange,
            prizeStatisticalConditionEnabled: prizeStatisticalConditionEnabled,
            prizeStatisticalCountPatternEnabled: prizeStatisticalCountPatternEnabled,
            universal150CompressionEnabled: universal150CompressionEnabled,
            universal247ToleranceEnabled: universal247ToleranceEnabled,
            universal247ToleranceThreshold: universal247ToleranceThreshold,
            productSumV10Top150Enabled: productSumV10Top150Enabled,
            finalResultInverted: finalResultInverted,
            finalOutcomeExclusions: finalOutcomeExclusions,
            automaticFinalOutcomeExclusions: automaticFinalOutcomeExclusions,
            historicalOutcomeWindows: historicalOutcomeWindows, historicalOutcomeBeforeIssue: historicalOutcomeBeforeIssue
        )
    }

    var normalizedInput: String {
        let logicText = logic.map(\.displayName).joined()
        let finalResultTokens = (finalResultInverted ? "RESULTINVERT=1|" : "")
            + finalOutcomeExclusions.sorted { $0.slot < $1.slot }.map {
                "RESULTCUT\($0.slot)=\($0.position),\($0.outcome)|"
            }.joined()
        let automaticFinalToken = automaticFinalOutcomeExclusions ? "RESULTAUTO=1|" : ""
        let historicalTokens = historicalOutcomeWindows.isEmpty ? "" : "RESULTWINDOWS=" + historicalOutcomeWindows.sorted().map(String.init).joined(separator: ",") + "|RESULTBEFORE=" + historicalOutcomeBeforeIssue + "|"
        let consecutiveTokens = "RUNS=\(consecutiveRunsEnabled ? 1 : 0)|NLRUN=\(nonLossRunRange.lowerBound)-\(nonLossRunRange.upperBound)|NDRUN=\(nonDrawRunRange.lowerBound)-\(nonDrawRunRange.upperBound)|NWRUN=\(nonWinRunRange.lowerBound)-\(nonWinRunRange.upperBound)|RUNTOL=\(consecutiveRunToleranceRange.lowerBound)-\(consecutiveRunToleranceRange.upperBound)|RUN2ON=\(secondaryConsecutiveRunsEnabled ? 1 : 0)|RUN2RANGE=\(secondaryConsecutiveRunRange.lowerBound)-\(secondaryConsecutiveRunRange.upperBound)|RUN2TOL=\(secondaryConsecutiveRunToleranceRange.lowerBound)-\(secondaryConsecutiveRunToleranceRange.upperBound)|SAMERUNS=\(sameResultRunsEnabled ? 1 : 0)|WINRUN=\(winRunRange.lowerBound)-\(winRunRange.upperBound)|DRAWRUN=\(drawRunRange.lowerBound)-\(drawRunRange.upperBound)|LOSSRUN=\(lossRunRange.lowerBound)-\(lossRunRange.upperBound)|SAMERUNTOL=\(sameResultRunToleranceRange.lowerBound)-\(sameResultRunToleranceRange.upperBound)|PROTECT11=\(protectConsecutiveDrawPair ? 1 : 0)|"
        let advancedTokens = "SPPRODON=\(spProductFilterEnabled ? 1 : 0)|SPPROD=\(spProductRange.lowerBound)-\(spProductRange.upperBound)|HODDSPRODON=\(customHandicapOddsProductFilterEnabled ? 1 : 0)|HODDSPROD=\(customHandicapOddsProductRange.lowerBound)-\(customHandicapOddsProductRange.upperBound)|HODDSSUMON=\(customHandicapOddsSumFilterEnabled ? 1 : 0)|HODDSSUM=\(customHandicapOddsSumRange.lowerBound)-\(customHandicapOddsSumRange.upperBound)|PRIZEON=\(prizeRangeFilterEnabled ? 1 : 0)|PRIZE=\(estimatedPrizeRange.lowerBound)-\(estimatedPrizeRange.upperBound)|SPRISKON=\(spRiskFilterEnabled ? 1 : 0)|MAXSP=\(maximumSingleSP)|HIGHSPTH=\(highSPThreshold)|HIGHSPCOUNT=\(highSPCountRange.lowerBound)-\(highSPCountRange.upperBound)|MINPROBON=\(minimumProbabilityFilterEnabled ? 1 : 0)|MINPROB=\(minimumSingleProbabilityPercent)|JOINTPROBON=\(jointProbabilityFilterEnabled ? 1 : 0)|JOINTPROB=\(jointProbabilityPercentRange.lowerBound)-\(jointProbabilityPercentRange.upperBound)|VIP12PROBON=\(vip12ProbabilityReductionEnabled ? 1 : 0)|SVIP1ODDSGUARDON=\(svip1CustomOddsGuardEnabled ? 1 : 0)|VIP16TOP200ON=\(vip16Top200Enabled ? 1 : 0)|VIP18TOP200ON=\(vip18Top200Enabled ? 1 : 0)|VIP19CUSTOMTOP200ON=\(vip19CustomOddsTop200Enabled ? 1 : 0)|GROUPON=\(groupFilterEnabled ? 1 : 0)|GROUPMODE=\(groupFilterMode.rawValue)|GFSUM=\(frontGroupOutcomeSumRange.lowerBound)-\(frontGroupOutcomeSumRange.upperBound)|GBSUM=\(backGroupOutcomeSumRange.lowerBound)-\(backGroupOutcomeSumRange.upperBound)|GFSP=\(frontGroupSPProductRange.lowerBound)-\(frontGroupSPProductRange.upperBound)|GBSP=\(backGroupSPProductRange.lowerBound)-\(backGroupSPProductRange.upperBound)|PRIZESTATON=\(prizeStatisticalConditionEnabled ? 1 : 0)|PRIZECOUNTON=\(prizeStatisticalCountPatternEnabled ? 1 : 0)|U150ON=\(universal150CompressionEnabled ? 1 : 0)|U247ON=\(universal247ToleranceEnabled ? 1 : 0)|U247TH=\(universal247ToleranceThreshold.formatted(.number.precision(.fractionLength(0...6))))|V10TOP150ON=\(productSumV10Top150Enabled ? 1 : 0)|"
        let customOddsProductCountToken = "HODDSPRODCOUNT=\(customHandicapOddsProductMatchCount ?? 0)|"
        let outcomeToleranceTokens = "OCTOLON=\(outcomeConditionToleranceEnabled ? 1 : 0)|OCTOL=\(outcomeConditionToleranceRange.lowerBound)-\(outcomeConditionToleranceRange.upperBound)|ALLTOLON=\(allConditionsToleranceEnabled ? 1 : 0)|ALLTOL=\(allConditionsToleranceRange.lowerBound)-\(allConditionsToleranceRange.upperBound)|"
        let frontThreeToken = frontThreeMaximumFourCount.map { "MAX4F3=\($0)|" } ?? ""
        let singleNoFourToken = matchNumbers.count == 6
            && frontThreeMaximumFourCount == nil
            && !noFourPositions.isEmpty
            ? "NO4SINGLE=1|"
            : ""
        let displacementCountToken = displacementMatchCount.map { "MCOUNT=\($0)|" } ?? ""
        let sumCountToken = sumMatchCount.map { "SUMCOUNT=\($0)|" } ?? ""
        let calculationCountToken = calculationMatchCount.map { "CALCCOUNT=\($0)|" } ?? ""
        let realSumToken = sumUsesOutcomeSP ? "REALSUM=1|" : ""
        let extraSumToken = (additionalSumRange.map { "EXTRASUM=\($0.lowerBound)-\($0.upperBound)|" } ?? "")
            + (highPass93GroupEnabled.map { "HP93GROUP=\($0 ? 1 : 0)|" } ?? "")
            + (highPass98GroupEnabled.map { "HP98GROUP=\($0 ? 1 : 0)|" } ?? "")
            + (highPass98FiftyGroupEnabled.map { "HP98FIFTYGROUP=\($0 ? 1 : 0)|" } ?? "")
            + (highPass50DoubleEnabled ? "HP50DOUBLE=1|" : "")
        let extras = finalResultTokens + automaticFinalToken + historicalTokens + extraSumToken + svip10AdditionalFilters.protocolTokens + "|SVIP11=\(svip11BreakpointOnlyEnabled ? 1 : 0)|SVIP10=\(svip10Frozen160Enabled ? 1 : 0)|SCOREMIN250=\(six250ScoreLower)|SCORE250=\(six250ScoreUpper)|TXT50=\(txtCompactEnabled ? 1 : 0)|TXTADD=\(maximumTXTAdditionalBets)|ADAPTIVES=\(oddsAdaptiveSRangeEnabled ? 1 : 0)|SVIP7=\(svip7RankOddsEnabled ? 1 : 0)|FINAL=\(finalReduction.rawValue)|SEED=\(randomSeed)|MKTW=\(marketWeightPercent)|RATE=\(finalRemovalPercent)|" + outcomeConditionTokens + outcomeToleranceTokens + consecutiveTokens + advancedTokens + customOddsProductCountToken + displacementCountToken + sumCountToken + calculationCountToken + realSumToken + "F5LOSS13ON=\(frontFiveLossCountEnabled ? 1 : 0)|F5LOSSRANGE=\(frontFiveLossCountRange.lowerBound)-\(frontFiveLossCountRange.upperBound)|F5WINON=\(frontFiveWinCountEnabled ? 1 : 0)|STRUCT3ON=\(combinedThreeStructureEnabled ? 1 : 0)|S250=\(six250SumRange.lowerBound)-\(six250SumRange.upperBound)|M250=\(six250MRange.lowerBound)-\(six250MRange.upperBound)|R250=\(six250RRange.lowerBound)-\(six250RRange.upperBound)|SIX250=\(six250RelationshipEnabled ? 1 : 0)|SIXSCOPE=\(sixMatchPackageScope ? 1 : 0)|PACKAGEON=\(conditionPackageEnabled ? 1 : 0)|TOP5SECOND=\(topFiveSecondRelaxed ? 1 : 0)|TOP5RELAX=\(topFiveRelaxed ? 1 : 0)|FIVEWIDE=\(widerFiveConditions ? 1 : 0)|STRUCTRELAX=\(expandedStructureRanges ? 1 : 0)|STRUCT3R=\(combinedThreeRRange.lowerBound)-\(combinedThreeRRange.upperBound)|F6LOSS14ON=\(sixLossCount14Enabled ? 1 : 0)|F5R39ON=\(frontFiveR39Enabled ? 1 : 0)|F5NO000ON=\(frontFiveNoTripleLossEnabled ? 1 : 0)|F5WINRANGE=\(frontFiveWinCountRange.lowerBound)-\(frontFiveWinCountRange.upperBound)|F5NO111ON=\(frontFiveNoTripleDrawEnabled ? 1 : 0)|F5ACTUALM36ON=\(frontFiveActualMEnabled ? 1 : 0)|F5ACTUALMRANGE=\(frontFiveActualMRange.lowerBound)-\(frontFiveActualMRange.upperBound)|SVIP5FOURCAPON=\(svip5FourCountFilterEnabled ? 1 : 0)|SVIP5DROP=\(svip5TailRemovalCount)|MPERM=\(minimumDistinctDisplacementOrders)|NO4LOWODDS=\(lowestCustomOddsNoFourEnabled ? 1 : 0)|" + singleNoFourToken + "NO4=\(noFourPositions.map(String.init).joined(separator: ","))|" + frontThreeToken + extraMatches.map { "\($0.matchNumber):\($0.compactOutcomes)" }.joined(separator: "|")
        return Self.appendingConditionSwitches(to: "\(matchNumbers.joined(separator: ","))|\(logicText)|\(sumRange.lowerBound)-\(sumRange.upperBound)|\(displacementRange.lowerBound)-\(displacementRange.upperBound)|\(varianceMaximum.formatted(.number.precision(.fractionLength(0...4))))|\(valueTwoMaximum)|\(transitionMinimumPercent.formatted(.number.precision(.fractionLength(0...4))))|\(roughnessMaximum)|\(breakpointRange.lowerBound)-\(breakpointRange.upperBound)|QDROP\(productRemovalCount)|\(extras)|MERGE3", disabled: disabledBasicConditions, valueThreeMaximum: valueThreeMaximum)
    }

    /// 只读取本注前五场判定值；没有赔率、注数、期号或历史记录特例。
    func svip5FourCountFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && svip5FourCountFilterEnabled else { return [] }
        guard logic.count >= structuralMatchCount, outcomes.count >= structuralMatchCount,
              outcomes.prefix(structuralMatchCount).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["\(structuralScopeLabel)判定值4个数无法计算：缺少完整\(structuralMatchCount)场彩果或ABCD"]
        }
        let values = zip(logic.prefix(structuralMatchCount), outcomes.prefix(structuralMatchCount)).map { $0.value(for: $1) }
        let fours = values.filter { $0 == 4 }.count
        var reasons: [String] = []
        if fours > 2 { reasons.append("\(structuralScopeLabel)判定值4出现\(fours)次，要求最多2次") }
        return reasons
    }

    func frontFiveActualMFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveActualMEnabled else { return [] }
        guard logic.count >= structuralMatchCount, outcomes.count >= structuralMatchCount,
              outcomes.prefix(structuralMatchCount).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["\(structuralScopeLabel)实际M无法计算：缺少完整\(structuralMatchCount)场彩果或ABCD"]
        }
        let values = zip(logic.prefix(structuralMatchCount), outcomes.prefix(structuralMatchCount)).map { $0.value(for: $1) }
        let m = zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
        return frontFiveActualMRange.contains(m) ? [] : ["\(structuralScopeLabel)按实际顺序计算M=\(m)，不在\(frontFiveActualMRange.lowerBound)–\(frontFiveActualMRange.upperBound)（含边界）"]
    }

    /// Count raw losses, independently of ABCD mapping and match six/seven.
    func frontFiveLossCountFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveLossCountEnabled else { return [] }
        guard outcomes.count >= structuralMatchCount, outcomes.prefix(structuralMatchCount).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["\(structuralScopeLabel)负个数无法计算：缺少完整\(structuralMatchCount)场3/1/0彩果"]
        }
        let losses = outcomes.prefix(structuralMatchCount).filter { $0 == 0 }.count
        return frontFiveLossCountRange.contains(losses) ? [] : ["\(structuralScopeLabel)负（彩果0）共\(losses)个，不在\(frontFiveLossCountRange.lowerBound)–\(frontFiveLossCountRange.upperBound)个（含边界）"]
    }

    func sixLossCount14FailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && sixLossCount14Enabled else { return [] }
        guard outcomes.count >= 6, outcomes.prefix(6).allSatisfy({ [3,1,0].contains($0) }) else {
            return ["六场负个数无法计算：缺少完整六场3/1/0赛果"]
        }
        let count = outcomes.prefix(6).filter { $0 == 0 }.count
        let range = widerFiveConditions ? 0...5 : 1...4
        return range.contains(count) ? [] : ["前六场负（赛果0）共\(count)个，不在\(range.lowerBound)–\(range.upperBound)个"]
    }

    func frontFiveR39FailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveR39Enabled else { return [] }
        guard logic.count >= structuralMatchCount, outcomes.count >= structuralMatchCount,
              outcomes.prefix(structuralMatchCount).allSatisfy({ [3,1,0].contains($0) }) else {
            return ["\(structuralScopeLabel)R无法计算：缺少完整\(structuralMatchCount)场赛果或ABCD"]
        }
        let values = zip(logic.prefix(structuralMatchCount), outcomes.prefix(structuralMatchCount)).map { $0.value(for: $1) }
        let r = (0..<(structuralMatchCount - 2)).reduce(0) { $0 + abs(values[$1+2] - 2*values[$1+1] + values[$1]) }
        let range = sixMatchPackageScope ? 0...14 : (topFiveSecondRelaxed ? 0...12 : (topFiveRelaxed ? 1...12 : (widerFiveConditions ? 2...11 : (expandedStructureRanges ? 3...11 : 3...9))))
        return range.contains(r) ? [] : ["\(structuralScopeLabel)判定值二阶波动R=\(r)，不在\(range.lowerBound)–\(range.upperBound)"]
    }

    func frontFiveNoTripleLossFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveNoTripleLossEnabled else { return [] }
        guard outcomes.count >= structuralMatchCount, outcomes.prefix(structuralMatchCount).allSatisfy({ [3,1,0].contains($0) }) else {
            return ["\(structuralScopeLabel)连续负无法计算：缺少完整\(structuralMatchCount)场3/1/0赛果"]
        }
        return (0...(structuralMatchCount - 3)).compactMap { start in
            outcomes[start...start+2].allSatisfy { $0 == 0 }
                ? "\(structuralScopeLabel)第\(start+1)–\(start+3)场连续3场负（000）" : nil
        }
    }

    /// A single switch requires all three fixed structure rules to pass.
    func combinedThreeStructureFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && combinedThreeStructureEnabled else { return [] }
        guard outcomes.count >= 6, logic.count >= 6,
              outcomes.prefix(6).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["三条件组合无法计算：缺少完整六场赛果或ABCD"]
        }
        let wins = outcomes.prefix(structuralMatchCount).filter { $0 == 3 }.count
        let values = zip(logic.prefix(6), outcomes.prefix(6)).map { $0.value(for: $1) }
        let roughness = (0..<4).reduce(0) { $0 + abs(values[$1 + 2] - 2 * values[$1 + 1] + values[$1]) }
        let threes = values.filter { $0 == 3 }.count
        var reasons: [String] = []
        let winRange = sixMatchPackageScope ? 0...5 : (expandedStructureRanges ? 0...4 : 1...4)
        if !winRange.contains(wins) { reasons.append("组合条件1：\(structuralScopeLabel)胜共\(wins)个，不在\(winRange.lowerBound)–\(winRange.upperBound)个") }
        if !combinedThreeRRange.contains(roughness) { reasons.append("组合条件2：六场判定值二阶波动R=\(roughness)，不在\(combinedThreeRRange.lowerBound)–\(combinedThreeRRange.upperBound)") }
        let maximumThrees = topFiveRelaxed ? 4 : 3
        if threes > maximumThrees { reasons.append("组合条件3：六场判定值3共\(threes)个，超过\(maximumThrees)个") }
        return reasons
    }

    func frontFiveWinCountFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveWinCountEnabled else { return [] }
        guard outcomes.count >= structuralMatchCount, outcomes.prefix(structuralMatchCount).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["\(structuralScopeLabel)胜个数无法计算：缺少完整\(structuralMatchCount)场3/1/0彩果"]
        }
        let losses = outcomes.prefix(structuralMatchCount).filter { $0 == 3 }.count
        return frontFiveWinCountRange.contains(losses) ? [] : ["\(structuralScopeLabel)胜（彩果3）共\(losses)个，不在\(frontFiveWinCountRange.lowerBound)–\(frontFiveWinCountRange.upperBound)个（含边界）"]
    }

    func frontFiveNoTripleDrawFailureReasons(for outcomes: [Int]) -> [String] {
        guard conditionPackageEnabled && frontFiveNoTripleDrawEnabled else { return [] }
        guard outcomes.count >= structuralMatchCount, outcomes.prefix(structuralMatchCount).allSatisfy({ [3, 1, 0].contains($0) }) else {
            return ["\(structuralScopeLabel)连续平局无法计算：缺少完整\(structuralMatchCount)场3/1/0彩果"]
        }
        let length = topFiveRelaxed ? 4 : 3
        return (0...(structuralMatchCount - length)).compactMap { start in
            outcomes[start..<(start + length)].allSatisfy({ $0 == 1 })
                ? "\(structuralScopeLabel)第\(start + 1)–\(start + length)场连续\(length)场平局" : nil
        }
    }

    func metricValues(in values: [Int]) -> [Int] {
        let count = min(calculationMatchCount ?? values.count, values.count)
        return Array(values.prefix(count))
    }

    func sumValues(in values: [Int]) -> [Int] {
        let count = min(sumMatchCount ?? calculationMatchCount ?? values.count, values.count)
        return Array(values.prefix(count))
    }

    func metricOutcomes(in outcomes: [Int]) -> [Int] {
        let count = min(calculationMatchCount ?? outcomes.count, outcomes.count)
        return Array(outcomes.prefix(count))
    }

    func customHandicapOddsProductOutcomes(in outcomes: [Int]) -> [Int] {
        let count = min(customHandicapOddsProductMatchCount ?? calculationMatchCount ?? outcomes.count, outcomes.count)
        return Array(outcomes.prefix(count))
    }

    /// 生成前必须补齐的自定义让球赔率场次数。
    ///
    /// SVIP2 的大部分基础指标只计算前 5 场，但自定义赔率乘积明确计算前 6 场。
    /// 数据加载层必须使用较大的那个范围，否则第 6 场会被误报为
    /// “缺少完整普通胜/平/负欧赔”。
    var requiredCustomOddsMatchCount: Int {
        let available = matchNumbers.count
        let normalCount = min(calculationMatchCount ?? available, available)
        let productCount = customHandicapOddsProductFilterEnabled
            ? min(customHandicapOddsProductMatchCount ?? normalCount, available)
            : normalCount
        let guardCount = svip1CustomOddsGuardEnabled ? min(6, available) : normalCount
        let autoCutCount = automaticFinalOutcomeExclusions && !finalOutcomeExclusions.isEmpty ? min(6, available) : normalCount
        return max(normalCount, productCount, guardCount, autoCutCount)
    }

    /// VIP10的连续类条件也严格只计算前5场；第6场全包和第7场固定单选
    /// 都不能反向改变前5场是否通过。
    func calculationSequenceOutcomes(in outcomes: [Int]) -> [Int] {
        guard let count = calculationMatchCount else { return outcomes }
        return Array(outcomes.prefix(min(count, outcomes.count)))
    }

    var activeNoFourPositions: [Int] {
        let count = svip11BreakpointOnlyEnabled ? logic.count : (calculationMatchCount ?? logic.count)
        let positions = noFourPositions + (resolvedLowestCustomOddsNoFourPosition.map { [$0] } ?? [])
        return Array(Set(positions.filter { $0 <= count })).sorted()
    }

    func displacementValue(in values: [Int]) -> Int {
        let count = min(displacementMatchCount ?? calculationMatchCount ?? values.count, values.count)
        let scoped = Array(values.prefix(count))
        return zip(scoped, scoped.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
    }

    /// 只数不同判定值序列；相同判定值互换不重复计数。
    func validDistinctDisplacementOrderCount(in values: [Int]) -> Int {
        let count = min(displacementMatchCount ?? calculationMatchCount ?? values.count, values.count)
        guard count == 5 || (sixMatchPackageScope && count == 6) else { return 0 }
        var remaining = [2: 0, 3: 0, 4: 0]
        for value in values.prefix(count) { remaining[value, default: 0] += 1 }
        var valid = 0
        func walk(_ depth: Int, _ previous: Int?, _ displacement: Int) {
            if depth == count {
                if displacementRange.contains(displacement) { valid += 1 }
                return
            }
            for value in 2...4 where remaining[value, default: 0] > 0 {
                remaining[value, default: 0] -= 1
                walk(depth + 1, value, displacement + (previous.map { abs(value - $0) } ?? 0))
                remaining[value, default: 0] += 1
            }
        }
        walk(0, nil, 0)
        return valid
    }

    func passesDisplacement(in values: [Int]) -> Bool {
        guard isEnabled(.displacement) else { return true }
        return minimumDistinctDisplacementOrders > 0
            ? validDistinctDisplacementOrderCount(in: values) >= minimumDistinctDisplacementOrders
            : displacementRange.contains(displacementValue(in: values))
    }

    func lowestFourProbabilityNoFourSelection(in odds: [[Double]]?) -> (position: Int, probability: Double)? {
        guard lowestCustomOddsNoFourEnabled else { return nil }
        guard let odds, odds.count >= 5, logic.count >= 5 else { return nil }
        let candidates = odds.prefix(5).enumerated().compactMap { index, row -> (Int, Double)? in
            guard row.count == 3,
                  row.allSatisfy({ $0.isFinite && $0 > 0 }),
                  let fourOutcomeIndex = logic[index].values.firstIndex(of: 4) else { return nil }
            let inverse = row.map { 1 / $0 }
            let total = inverse.reduce(0, +)
            guard total.isFinite, total > 0 else { return nil }
            return (index + 1, inverse[fourOutcomeIndex] / total)
        }
        guard candidates.count == 5 else { return nil }
        return candidates.min { left, right in
            abs(left.1 - right.1) <= 1e-15 ? left.0 < right.0 : left.1 < right.1
        }
    }

    func lowestCustomOddsNoFourPosition(in odds: [[Double]]?) -> Int? {
        lowestFourProbabilityNoFourSelection(in: odds)?.position
    }

    /// 双选概率＝该场归一化隐含概率最高的两项之和。
    /// 同分时固定选择更靠前的场次，保证同一赔率输入得到稳定结果。
    func highestDoubleProbabilityNoFourSelection(in odds: [[Double]]?) -> (position: Int, probability: Double)? {
        guard (svip10AdditionalFilters.highestDoubleProbabilityNoFourEnabled
                || svip10AdditionalFilters.firstDoubleActive
                || svip10AdditionalFilters.secondDoubleActive),
              let rows = doubleSelectionProbabilities(in: odds) else { return nil }
        if svip10AdditionalFilters.adDoublesWithinSixEnabled {
            guard let first = automaticDoubleChoices(in: odds).first else { return nil }
            return (first.position, first.choice.coverage)
        }
        if svip10AdditionalFilters.usesAutomaticDoubleSelection, let first = automaticDoubleChoices(in: odds).first {
            return (first.position, first.choice.coverage)
        }
        let candidates = rows.enumerated().map { index, row -> (Int, Double) in
            let probabilities = row.sorted(by: >)
            return (index + 1, probabilities[0] + probabilities[1])
        }
        return candidates.max { left, right in
            abs(left.1 - right.1) <= 1e-15 ? left.0 > right.0 : left.1 < right.1
        }
    }

    /// The only calibrated probability source for both double selections.
    /// Parameters are frozen from the 2024-only probe, never fitted on-device.
    func doubleSelectionProbabilities(in odds: [[Double]]?) -> [[Double]]? {
        guard let odds, odds.count >= 6 else { return nil }
        let rows = odds.prefix(6).compactMap { AutomaticDoubleSelector.probabilities(odds: $0, calibrated: svip10AdditionalFilters.calibratedDoubleSelectionEnabled) }
        return rows.count == 6 ? rows : nil
    }

    func automaticDoubleChoices(in odds: [[Double]]?) -> [(position: Int, choice: AutomaticDoubleChoice)] {
        guard let odds, odds.count >= 6, logic.count >= 6, matchNumbers.count >= 6 else { return [] }
        let candidates = (0..<6).compactMap { index -> AutomaticDoubleCandidate? in
            guard let number = Int(matchNumbers[index]) else { return nil }
            return AutomaticDoubleCandidate(number: number, logic: logic[index], odds: odds[index],
                evidence: svip10AdditionalFilters.doubleMarketEvidence.first { $0.number == number })
        }
        guard candidates.count == 6, candidates.allSatisfy({ AutomaticDoubleSelector.probabilities(odds: $0.odds, calibrated: false) != nil }) else { return [] }
        return AutomaticDoubleSelector.choices(in: candidates, calibrated: svip10AdditionalFilters.calibratedDoubleSelectionEnabled, factors: svip10AdditionalFilters.doubleJudgmentFactors, fixedFrontTwo: svip10AdditionalFilters.fixedFrontTwoDoublesEnabled, requireFrontTwoAD: svip10AdditionalFilters.frontTwoADEnabled, adDoublesWithinSix: svip10AdditionalFilters.adDoublesWithinSixEnabled, adDoubleCountWithinSix: svip10AdditionalFilters.adDoubleCountWithinSix, automaticDoubleCount: svip10AdditionalFilters.automaticDoubleCount).compactMap { choice in
            guard let position = matchNumbers.firstIndex(of: String(choice.number)) else { return nil }
            return (position + 1, choice)
        }
    }

    func highestDoubleProbabilityTopTwoSelection(in odds: [[Double]]?)
        -> (position: Int, removedOutcome: Int, probability: Double)? {
        if svip10AdditionalFilters.usesAutomaticDoubleSelection {
            guard let first = automaticDoubleChoices(in: odds).first else { return nil }
            return (first.position, first.choice.removedOutcome, first.choice.coverage)
        }
        guard let selection = highestDoubleProbabilityNoFourSelection(in: odds),
              let rows = doubleSelectionProbabilities(in: odds), let odds else { return nil }
        let position = selection.position - 1
        let ordered = (0..<3).sorted { left, right in
            if svip10AdditionalFilters.calibratedDoubleSelectionEnabled {
                let difference = rows[position][left] - rows[position][right]
                return abs(difference) > 1e-15 ? difference > 0 : left < right
            }
            let difference = odds[position][left] - odds[position][right]
            return abs(difference) > 1e-12 ? difference < 0 : left < right
        }
        return (selection.position, [3, 1, 0][ordered[2]], selection.probability)
    }

    func highestDoubleProbabilityNoFourPosition(in odds: [[Double]]?) -> Int? {
        highestDoubleProbabilityNoFourSelection(in: odds)?.position
    }

    var finalReductionDescription: String {
        finalReduction == .off ? "关闭" : "\(finalReduction.title) · 减\(finalRemovalPercent)%（保留\(100 - finalRemovalPercent)%）"
    }

    var enabledOutcomeConditions: [OutcomeCondition] {
        OutcomeCondition.activeCases.filter {
            outcomeConditions[$0] != nil
                && ($0.isHighPass98Fifty ? (highPass98FiftyGroupEnabled ?? conditionPackageEnabled)
                    : ($0.isHighPass98 ? (highPass98GroupEnabled ?? conditionPackageEnabled)
                    : ($0.isHighPass93 ? (highPass93GroupEnabled ?? conditionPackageEnabled) : conditionPackageEnabled)))
        }
    }

    var independentOutcomeConditions: [OutcomeCondition] {
        enabledOutcomeConditions.filter {
            $0.isHighPass93 && highPass93GroupEnabled == true || $0.isHighPass98 && highPass98GroupEnabled == true
                || $0.isHighPass98Fifty && highPass98FiftyGroupEnabled == true
        }
    }

    var outcomeConditionTokens: String {
        OutcomeCondition.activeCases.filter { outcomeConditions[$0] != nil }.map { condition in
            let range = outcomeConditions[condition]!
            return "OC_\(condition.rawValue)=\(range.lowerBound)-\(range.upperBound)|"
        }.joined()
    }

    func outcomeConditionFailureCount(in outcomes: [Int]) -> Int {
        let scoped = metricOutcomes(in: outcomes)
        return enabledOutcomeConditions.filter { condition in
            guard let range = outcomeConditions[condition] else { return false }
            return !range.contains(condition.value(in: scoped))
        }.count
    }

    func passesOutcomeConditions(_ outcomes: [Int]) -> Bool {
        let failureCount = outcomeConditionFailureCount(in: outcomes)
        return outcomeConditionToleranceEnabled
            ? outcomeConditionToleranceRange.contains(failureCount)
            : failureCount == 0
    }

    func independentHighPass93FailureReasons(_ outcomes: [Int]) -> [String] {
        guard highPass93GroupEnabled == true else { return [] }
        let six = Array(outcomes.prefix(6))
        return enabledOutcomeConditions.filter(\.isHighPass93).compactMap { condition in
            let range = outcomeConditions[condition]!
            let value = condition.value(in: six)
            return range.contains(value) ? nil : "\(condition.title)：实际\(value)，要求\(range.lowerBound)–\(range.upperBound)"
        }
    }

    /// Recomputed from this six-match group's custom odds only. Stable ties
    /// prefer the earlier match and outcome order 3, 1, 0.
    func highPass50DoubleSelection(in odds: [[Double]]?) -> (position: Int, outcomes: [Int], probability: Double)? {
        guard let odds, odds.count >= 6,
              odds.prefix(6).allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else { return nil }
        var best: (position: Int, outcomes: [Int], probability: Double)?
        for (index, row) in odds.prefix(6).enumerated() {
            let inverse = row.map { 1 / $0 }
            let total = inverse.reduce(0, +)
            guard total.isFinite, total > 0 else { return nil }
            let probabilities = inverse.map { $0 / total }
            let order = (0..<3).sorted {
                probabilities[$0] == probabilities[$1] ? $0 < $1 : probabilities[$0] > probabilities[$1]
            }
            let coverage = probabilities[order[0]] + probabilities[order[1]]
            if best == nil || coverage > best!.probability {
                best = (index + 1, order.prefix(2).map { [3, 1, 0][$0] }, coverage)
            }
        }
        return best
    }

    func highPass50DoubleFailureReasons(_ outcomes: [Int], customOdds: [[Double]]?) -> [String] {
        guard highPass50DoubleActive else { return [] }
        guard outcomes.count >= 6, let selection = highPass50DoubleSelection(in: customOdds) else {
            return ["某一场自动双选：缺少完整六场彩果或自定义赔率"]
        }
        return selection.outcomes.contains(outcomes[selection.position - 1]) ? []
            : ["某一场自动双选：第\(selection.position)场只保留\(selection.outcomes.map(String.init).joined(separator: "/"))"]
    }

    func independentOutcomeFailureReasons(_ outcomes: [Int], customOdds: [[Double]]? = nil) -> [String] {
        let six = Array(outcomes.prefix(6))
        return independentOutcomeConditions.compactMap { condition in
            let range = outcomeConditions[condition]!
            let value = condition.value(in: six)
            return range.contains(value) ? nil : "\(condition.title)：实际\(value)，要求\(range.lowerBound)–\(range.upperBound)"
        } + highPass50DoubleFailureReasons(outcomes, customOdds: customOdds)
    }

    var extraExpansionFactor: Int {
        extraMatches.reduce(1) { $0 * $1.outcomes.count }
    }

    var maximum105Active: Bool {
        svip10Frozen160Enabled && conditionPackageEnabled && svip10AdditionalFilters.maximum105Enabled
    }

    var requiresSPData: Bool {
        if automaticFinalOutcomeExclusions && !finalOutcomeExclusions.isEmpty { return true }
        if svip10Frozen160Enabled && conditionPackageEnabled && (svip10AdditionalFilters.fixedFrontTwoDoublesEnabled || svip10AdditionalFilters.adDoublesWithinSixEnabled) { return true }
        if maximum105Active { return true }
        if highPass50DoubleActive { return true }
        if svip7RankOddsEnabled || six250RelationshipEnabled { return conditionPackageEnabled }
        return oddsAdaptiveSRangeEnabled || sumUsesOutcomeSP || spProductFilterEnabled || prizeRangeFilterEnabled || spRiskFilterEnabled
            || customHandicapOddsProductFilterEnabled || customHandicapOddsSumFilterEnabled
            || svip1CustomOddsGuardEnabled
            || svip5TailRemovalCount > 0
            || vip19CustomOddsTop200Enabled
            || (groupFilterEnabled && groupFilterMode.usesSPProduct)
            || (universal247ToleranceEnabled
                && (SequenceFilterEngine.usesHandicapOddsV9Model(
                    threshold: universal247ToleranceThreshold
                ) || SequenceFilterEngine.usesVIP3Model(
                    threshold: universal247ToleranceThreshold
                ) || SequenceFilterEngine.usesVIP2Model(
                    threshold: universal247ToleranceThreshold
                )))
    }

    var requiresProbabilityData: Bool {
        requiresStrictProbabilityData || vip12ProbabilityReductionEnabled || vip16Top200Enabled || vip18Top200Enabled
    }

    /// 这两类条件没有概率就无法判定通过/不通过；VIP12则允许用ABCD映射概率继续。
    var requiresStrictProbabilityData: Bool {
        minimumProbabilityFilterEnabled || jointProbabilityFilterEnabled || vip18Top200Enabled
    }

    func consecutiveRunFailureCount(in outcomes: [Int]) -> Int {
        let scoped = calculationSequenceOutcomes(in: outcomes)
        let configured: [(ConsecutiveRunCondition, ClosedRange<Int>)] = [
            (.nonLoss, nonLossRunRange),
            (.nonDraw, nonDrawRunRange),
            (.nonWin, nonWinRunRange)
        ]
        return configured.filter { condition, range in
            !range.contains(condition.longestRun(in: scoped))
        }.count
    }

    func passesConsecutiveRuns(_ outcomes: [Int]) -> Bool {
        let scoped = calculationSequenceOutcomes(in: outcomes)
        guard consecutiveRunsEnabled else { return true }
        guard consecutiveRunToleranceRange.contains(consecutiveRunFailureCount(in: outcomes)) else {
            return false
        }
        guard secondaryConsecutiveRunsEnabled else { return true }
        let secondaryFailures = [
            ConsecutiveRunCondition.nonLoss,
            ConsecutiveRunCondition.nonDraw,
            ConsecutiveRunCondition.nonWin
        ].filter {
            !secondaryConsecutiveRunRange.contains($0.longestRun(in: scoped))
        }.count
        return secondaryConsecutiveRunToleranceRange.contains(secondaryFailures)
    }

    func sameResultRunFailureCount(in outcomes: [Int]) -> Int {
        let scoped = calculationSequenceOutcomes(in: outcomes)
        let configured: [(ConsecutiveRunCondition, ClosedRange<Int>)] = [
            (.win, winRunRange),
            (.draw, drawRunRange),
            (.loss, lossRunRange)
        ]
        return configured.filter { condition, range in
            !range.contains(condition.longestRun(in: scoped))
        }.count
    }

    func passesSameResultRuns(_ outcomes: [Int]) -> Bool {
        let scoped = calculationSequenceOutcomes(in: outcomes)
        guard sameResultRunsEnabled else { return true }
        if protectConsecutiveDrawPair,
           zip(scoped, scoped.dropFirst()).contains(where: { pair in
               pair.0 == 1 && pair.1 == 1
           }) {
            return true
        }
        return sameResultRunToleranceRange.contains(sameResultRunFailureCount(in: outcomes))
    }

    private static func parseRange(_ input: String, labels: [String]) throws -> ClosedRange<Int> {
        let text = stripLabel(input, labels: labels)
        let components = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2,
              let lower = Int(components[0]),
              let upper = Int(components[1]),
              lower <= upper else {
            throw FilterConfigError.invalidRange(input)
        }
        return lower...upper
    }

    private static func parseDoubleRange(_ input: String) throws -> ClosedRange<Double> {
        let components = input.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2,
              let lower = Double(components[0]),
              let upper = Double(components[1]),
              lower.isFinite, upper.isFinite,
              lower <= upper else {
            throw FilterConfigError.invalidRange(input)
        }
        return lower...upper
    }

    private static func stripLabel(_ input: String, labels: [String]) -> String {
        var result = input.lowercased().replacingOccurrences(of: " ", with: "")
        for label in labels {
            result = result.replacingOccurrences(of: label.lowercased(), with: "")
        }
        return result
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private static func parseExtra(_ input: String, label: String) throws -> ExtraMatchSelection {
        let pieces = input.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 2 else { throw FilterConfigError.invalidExtra(label) }
        let match = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = pieces[1].compactMap { Int(String($0)) }
        let valid = Set(requested).isSubset(of: Set([3, 1, 0]))
        guard !match.isEmpty, valid, !requested.isEmpty, Set(requested).count == requested.count else {
            throw FilterConfigError.invalidExtra(label)
        }
        let ordered = [3, 1, 0].filter(Set(requested).contains)
        return ExtraMatchSelection(matchNumber: match, outcomes: ordered)
    }
}

enum FilterConfigError: LocalizedError, Equatable {
    case invalidFieldCount
    case invalidMatches
    case logicCountMismatch(expected: Int)
    case invalidRange(String)
    case invalidVariance
    case invalidValueTwoMaximum
    case invalidTransitionMinimum
    case invalidSequenceMaximum
    case invalidProductRemovalCount
    case invalidExtra(String)
    case duplicateMatchNumber
    case invalidMergeMode

    var errorDescription: String? {
        switch self {
        case .invalidFieldCount:
            return "请输入：5个主场次|5位逻辑|S|M|方差|值2上限|P_tr下限%|R上限|断点B范围|固定全包场:310|固定单选场:彩果|MERGE3"
        case .invalidMatches:
            return "场次号需为2至8个不重复值，并用英文逗号分隔。"
        case .logicCountMismatch(let expected):
            return "逻辑数组必须与场次数量一致，当前需要\(expected)个A/B/C/D字符。"
        case .invalidRange(let value):
            return "范围格式无效：\(value)，请使用“最小值-最大值”。"
        case .invalidVariance:
            return "方差上限无效。"
        case .invalidValueTwoMaximum:
            return "判定值2的次数上限无效。"
        case .invalidTransitionMinimum:
            return "马尔可夫转移概率下限无效。"
        case .invalidSequenceMaximum:
            return "二阶波动上限无效。"
        case .invalidProductRemovalCount:
            return "乘积优先删除条数无效。"
        case .invalidExtra(let label):
            return "\(label)输入无效，请使用“场次号:彩果”，例如5:3、6:31、7:310。"
        case .duplicateMatchNumber:
            return "5个主场次、固定全包场与固定单选场的场次号不能重复。"
        case .invalidMergeMode:
            return "当前仅支持MERGE3（三场相同合并）模式。"
        }
    }
}

/// A named settings package keeps the original engine/version and every switch.
/// Fixture inputs and transient query state always belong to the current session.
enum SVVVConditionPackage {
    static let id = "svvv"
    static let storageKey = "sequenceFilter.svvvPackage.v1"
    static let migrationKey = "sequenceFilter.svvvPackage.20261031.v1"
    static let highPassMigrationKey = "sequenceFilter.svvvHighPassFive.20261031.v1"
    static let highPass93MigrationKey = "sequenceFilter.svvvHighPass93Five.20261031.v1"
    static let highPass40MigrationKey = "sequenceFilter.svvvHighPass93Forty.20261031.v1"
    static let highPass100MigrationKey = "sequenceFilter.svvvHighPass98Hundred.20261031.v1"
    static let highPass50MigrationKey = "sequenceFilter.svvvHighPass98Fifty.20261031.v1"
    static let relativePositionRemovalKey = "sequenceFilter.svvvRemoveRelativePosition.20261031.v1"

    static func removingRelativePositionConditions(from values: [String: String]) -> [String: String] {
        var updated = values
        let removed = Set(OutcomeCondition.activeCases.filter(\.isRelativePositionCondition).map { "OC_" + $0.rawValue })
        for condition in OutcomeCondition.activeCases where condition.isRelativePositionCondition {
            updated.removeValue(forKey: "OC_" + condition.rawValue)
            updated.removeValue(forKey: "OCON_" + condition.rawValue)
        }
        if let entered = values["enteredConditionIDs"] {
            updated["enteredConditionIDs"] = entered.split(separator: ",").map(String.init)
                .filter { !removed.contains($0) }.joined(separator: ",")
        }
        return updated
    }

    static func addingHighPassConditions(to values: [String: String]) -> [String: String] {
        addingConditions(OutcomeCondition.highPassAdditions, to: values)
    }

    static func addingHighPass93Conditions(to values: [String: String]) -> [String: String] {
        var updated = addingConditions(OutcomeCondition.highPass93Additions, to: values)
        if updated != values || values["svvvSelected"] == "1" && values["selectedConditionVersionID"] == "svip10-frozen-160" {
            updated["svvvHighPass40Enabled"] = "1"
        }
        return updated
    }

    static func addingHighPass98Conditions(to values: [String: String]) -> [String: String] {
        guard values["svvvSelected"] == "1", values["selectedConditionVersionID"] == "svip10-frozen-160" else { return values }
        var updated = addingConditions(OutcomeCondition.highPass98Additions, to: values)
        updated["svvvHighPass100Enabled"] = "1"
        return updated
    }

    static func addingHighPass98FiftyConditions(to values: [String: String]) -> [String: String] {
        guard values["svvvSelected"] == "1", values["selectedConditionVersionID"] == "svip10-frozen-160" else { return values }
        var updated = addingConditions(OutcomeCondition.highPass98FiftyAdditions, to: values)
        updated["svvvHighPass50Enabled"] = "1"
        updated["svvvHighPass50DoubleEnabled"] = "1"
        return updated
    }

    private static func addingConditions(_ additions: [(condition: OutcomeCondition, range: ClosedRange<Int>)],
                                         to values: [String: String]) -> [String: String] {
        guard values["svvvSelected"] == "1", values["selectedConditionVersionID"] == "svip10-frozen-160" else { return values }
        var updated = values
        var entered = (values["enteredConditionIDs"] ?? "").split(separator: ",").map(String.init)
        for (condition, range) in additions {
            let key = "OC_" + condition.rawValue
            updated[key] = "\(range.lowerBound)-\(range.upperBound)"
            updated["OCON_" + condition.rawValue] = "1"
            if !entered.contains(key) { entered.append(key) }
        }
        updated["enteredConditionIDs"] = entered.joined(separator: ",")
        return updated
    }

    static func snapshot(from values: [String: String]) -> [String: String] {
        let sessionKeys: Set<String> = [
            "svvvSelected", "svvvp11Selected", "conditionTextInput", "filterSchemeArchiveEnabled",
            "beijingSingleIssueInput", "logicInput", "abcdSource", "betMultiplierInput",
            "fixedFullMatchInput", "singleMatchInput", "singleOutcomeInput",
            "vipSeventhNumber", "vipSeventhOutcome", "vip1StartInput", "vip1EndInput",
            "prizeDelayedMatchNumbersInput", "txtDisplaysSeventhMatch"
        ]
        let sessionPrefixes = ["match", "previousMatch", "manual", "prizeMatchInput",
                               "firstMatchStartTime", "seventhMatchStartTime"]
        return FilterInputDefaults.removingFixed105Limit(from: values.filter { key, _ in
            !sessionKeys.contains(key) && !sessionPrefixes.contains(where: { key.hasPrefix($0) })
        })
    }

    static func restoring(_ package: [String: String], onto current: [String: String]) -> [String: String] {
        var values = current
        values.merge(snapshot(from: removingRelativePositionConditions(from: package))) { _, saved in saved }
        values["svvvSelected"] = "1"
        return removingRelativePositionConditions(from: values)
    }
}

/// Separate named preset; loading it never copies fixture numbers or the manual seventh.
enum SVVVP11ConditionPackage {
    static let id = "svvvp11"
    static let storageKey = "sequenceFilter.svvvp11Package.v2"
    static let previousStorageKey = "sequenceFilter.beforeSVVVP11.v1"
    static let scoreRange = "0-6.7"
    static let minimumOddsProduct = 350.0
    static let nonDrawRunRange = 2...6

    static func recommendedConfig() throws -> FilterConfig {
        var additions = SVIP10AdditionalFilters()
        additions.highestDoubleProbabilityTopTwoEnabled = true
        additions.secondDoubleLowestProbabilityEnabled = true // Legacy UI switch; count one disables this leg.
        additions.calibratedDoubleSelectionEnabled = true
        additions.automaticDoublePairEnabled = true
        additions.adDoublesWithinSixEnabled = false
        additions.automaticDoubleCount = 1
        additions.adDoubleCountWithinSix = 1
        additions.sixMatchMinimumOddsProductEnabled = true
        additions.sixMatchMinimumOddsProduct = minimumOddsProduct
        additions.doubleJudgmentFactors = Set(DoubleJudgmentFactor.allCases)
        let input = FilterConfig.svip10Input(numbers: ["1", "2", "3", "4", "5", "6"],
            logic: "AAAAAA", extras: ["7:3"], scoreRange: scoreRange,
            sumRange: "12-24", mRange: "0-10", additionalFilters: additions)
        var config = try FilterConfig.parse(input)
        config.disabledBasicConditions = Set(BasicCondition.allCases.filter { $0 != .score })
        config.outcomeConditions = [.nonDrawRun: nonDrawRunRange]
        return config
    }

    static func recommendedValues(onto current: [String: String]) throws -> [String: String] {
        let config = try recommendedConfig()
        var values = FilterInputDefaults.values(from: config)
        values["svip10ScoreRangeInput"] = scoreRange
        values["svip10SumRangeInput"] = "12-24"
        values["svip10MRangeInput"] = "0-10"
        values["svip10Enabled"] = "1"
        values["svvvp11PresetRevision"] = "unrestricted-40-prize-v2"
        values["vipConditionsEnabled"] = "1"
        values["currentConditionPackageEnabled"] = "1"
        values["selectedConditionVersionID"] = "svip10-frozen-160"
        values["inputExperienceMode"] = "v1"
        values["svvvHighPass40Enabled"] = "0"
        values["svvvHighPass100Enabled"] = "0"
        values["svvvHighPass50Enabled"] = "0"
        values["svvvHighPass50DoubleEnabled"] = "0"
        values["noFourPositionFilterEnabled"] = "0"
        values["secondNoFourPositionFilterEnabled"] = "0"
        return restoring(values, onto: current)
    }

    static func restoring(_ package: [String: String], onto current: [String: String]) -> [String: String] {
        var values = current
        values.merge(SVVVConditionPackage.snapshot(from: package)) { _, saved in saved }
        values["svvvSelected"] = "0"
        values["svvvp11Selected"] = "1"
        return FilterInputDefaults.currentDirectionalDoubleSettings(from: values)
    }

    static func restoringPrevious(_ package: [String: String], onto current: [String: String]) -> [String: String] {
        var values = current
        values.merge(SVVVConditionPackage.snapshot(from: package)) { _, saved in saved }
        values["svvvSelected"] = package["svvvSelected"] ?? "0"
        values["svvvp11Selected"] = "0"
        return FilterInputDefaults.currentDirectionalDoubleSettings(from: values)
    }
}

/// 从历史成功计算迁移为表单默认值，不恢复旧ABCD，避免跨期沿用。
enum FilterInputDefaults {
    /// 当前条件按实际通过组合出注；旧105截取只留给历史TXT协议回放。
    static func removingFixed105Limit(from values: [String: String]) -> [String: String] {
        var updated = values
        updated["svip10Maximum105Enabled"] = "0"
        return updated
    }

    static func currentDirectionalDoubleSettings(from values: [String: String]) -> [String: String] {
        guard values["selectedConditionVersionID"] == "svip10-frozen-160" else { return values }
        var updated = removingFixed105Limit(from: values)
        // svip10NoFourEnabled is also used by SVIP11's independent 禁4 rule.
        // Preserve it; the live SVIP10 protocol separately disables TOP2.
        for key in ["svip10AutomaticDoublePairEnabled", "svip10SecondDoubleLowestProbabilityEnabled",
                    "svip10CalibratedDoubleSelectionEnabled", "svvvHighPass50DoubleEnabled"] { updated[key] = "0" }
        updated["svip10ADDoubleCountWithinSix"] = "1"
        updated["svip10ADDoublesWithinSixEnabled"] = "0"
        updated["svip10AutomaticDoubleCount"] = "1"
        updated["svip10FrontTwoADEnabled"] = "0"
        updated["svip10FixedFrontTwoDoublesEnabled"] = "0"
        updated["svip10AllABCDEnabled"] = "0"
        if updated["matchSearchStartInput"] == nil {
            updated["matchSearchStartInput"] = values["match1Input"] ?? "1"
        }
        return updated
    }

    /// Live form/global generation only. Archived explicit double protocols
    /// continue to parse and replay through FilterConfig without this migration.
    static func removingLiveDoubleRestrictions(from input: String) -> String {
        let disabled = Set(["S10DBLNO4", "S10DBLTOP2", "S10DBL2LOW", "S10AUTOPAIR", "S10DBLCAL",
                            "S10FRONTDBL", "S10FRONTAD", "S10ADWITHIN6", "S10ABCDSELECT", "HP50DOUBLE"])
        return input.components(separatedBy: "|").map { field in
            let name = String(field.prefix { $0 != "=" })
            return disabled.contains(name) ? name + "=0" : field
        }.joined(separator: "|")
    }

    /// SVIP10 displays every outcome switch, so enabling one must take effect
    /// even when it was not added through the condition text editor.
    static func enabledEditorOutcomeRanges(values: [String: String],
                                          defaultRanges: [OutcomeCondition: String] = [:]) -> [OutcomeCondition: String] {
        let isSVIP10 = values["selectedConditionVersionID"] == "svip10-frozen-160"
        let entered = Set((values["enteredConditionIDs"] ?? "").split(separator: ",").map(String.init))
        var ranges: [OutcomeCondition: String] = [:]
        for condition in OutcomeCondition.editorCases
            where values["OCON_" + condition.rawValue] == "1"
                && (isSVIP10 || entered.contains("OC_" + condition.rawValue)) {
            if isSVIP10 && condition == .draws { continue } // Unified SVIP10 draw switch.
            ranges[condition] = values["OC_" + condition.rawValue]
                ?? defaultRanges[condition]
                ?? "\(condition == .diversity ? 1 : 0)-\(condition.maximum(matchCount: isSVIP10 ? 6 : 5))"
        }
        return ranges
    }

    static func values(from config: FilterConfig) -> [String: String] {
        var values: [String: String] = [
            "svip10ColdCountEnabled": config.svip10AdditionalFilters.coldCountEnabled ? "1" : "0",
            "svip10ColdCountRangeInput": "\(config.svip10AdditionalFilters.coldCountRange.lowerBound)-\(config.svip10AdditionalFilters.coldCountRange.upperBound)",
            "svip10DrawCountEnabled": config.svip10AdditionalFilters.drawCountEnabled ? "1" : "0",
            "svip10DrawCountRangeInput": "\(config.svip10AdditionalFilters.drawCountRange.lowerBound)-\(config.svip10AdditionalFilters.drawCountRange.upperBound)",
            "svip10WinLossSwitchEnabled": config.svip10AdditionalFilters.winLossSwitchEnabled ? "1" : "0",
            "svip10NoFourEnabled": (config.svip10AdditionalFilters.highestDoubleProbabilityNoFourEnabled || config.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled) ? "1" : "0",
            "svip10SecondDoubleLowestProbabilityEnabled": config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled ? "1" : "0",
            "svip10AutomaticDoublePairEnabled": config.svip10AdditionalFilters.automaticDoublePairEnabled ? "1" : "0",
            "svip10AllABCDEnabled": config.svip10AdditionalFilters.allABCDSelectionEnabled ? "1" : "0",
            "svip10DoubleJudgmentFactors": DoubleJudgmentFactor.text(config.svip10AdditionalFilters.doubleJudgmentFactors),
            "svip10CalibratedDoubleSelectionEnabled": config.svip10AdditionalFilters.calibratedDoubleSelectionEnabled ? "1" : "0",
            "svip10FiveMatchMEnabled": config.svip10AdditionalFilters.fiveMatchMEnabled ? "1" : "0",
            "svip10FiveMatchMRangeInput": "\(config.svip10AdditionalFilters.fiveMatchMRange.lowerBound)-\(config.svip10AdditionalFilters.fiveMatchMRange.upperBound)",
            "svip10FrontFiveSameOutcomeRunMaximum2Enabled": config.svip10AdditionalFilters.frontFiveSameOutcomeRunMaximum2Enabled ? "1" : "0",
            "svip10FrontFiveReturnMaximum2Enabled": config.svip10AdditionalFilters.frontFiveReturnMaximum2Enabled ? "1" : "0",
            "svip10FrontFiveNoConsecutiveDrawEnabled": config.svip10AdditionalFilters.frontFiveNoConsecutiveDrawEnabled ? "1" : "0",
            "svip10FrontFiveValueThreeMaximum2Enabled": config.svip10AdditionalFilters.frontFiveValueThreeMaximum2Enabled ? "1" : "0",
            "svip10SixMatchFavoriteCount2To4Enabled": config.svip10AdditionalFilters.sixMatchFavoriteCount2To4Enabled ? "1" : "0",
            "svip10SixMatchFavoriteCount1To4Enabled": config.svip10AdditionalFilters.sixMatchFavoriteCount1To4Enabled ? "1" : "0",
            "svip10SixMatchMinimumOddsProductEnabled": config.svip10AdditionalFilters.sixMatchMinimumOddsProductEnabled ? "1" : "0",
            "svip10SixMatchMinimumOddsProductInput": String(format: "%.0f", config.svip10AdditionalFilters.sixMatchMinimumOddsProduct),
            "svip10SixMatchBreakpoint2To4Enabled": config.svip10AdditionalFilters.sixMatchBreakpoint2To4Enabled ? "1" : "0",
            "svip10SixMatchBreakpoint3To5Enabled": config.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled ? "1" : "0",
            "svip10SixMatchBreakpointRangeInput": "\(config.svip10AdditionalFilters.sixMatchBreakpointRange.lowerBound)-\(config.svip10AdditionalFilters.sixMatchBreakpointRange.upperBound)",
            "svip10TopThreeProbabilityRecovery100Enabled": config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled ? "1" : "0",
            "svip10StatisticalLineBudgetEnabled": config.svip10AdditionalFilters.statisticalLineBudgetEnabled ? "1" : "0",
            "svip10ProbabilityMass60Enabled": config.svip10AdditionalFilters.probabilityMass60Enabled ? "1" : "0",
            "svip10Maximum105Enabled": config.svip10AdditionalFilters.maximum105Enabled ? "1" : "0",
            "svip10FixedFrontTwoDoublesEnabled": config.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled ? "1" : "0",
            "svip10FrontTwoADEnabled": config.svip10AdditionalFilters.frontTwoADEnabled ? "1" : "0",
            "svip10ADDoublesWithinSixEnabled": config.svip10AdditionalFilters.adDoublesWithinSixEnabled ? "1" : "0",
            "svip10ADDoubleCountWithinSix": String(config.svip10AdditionalFilters.adDoubleCountWithinSix),
            "svip10AutomaticDoubleCount": String(config.svip10AdditionalFilters.automaticDoubleCount),
            "svip7RankOddsEnabled": config.svip7RankOddsEnabled ? "1" : "0",
            "enteredConditionIDs": config.outcomeConditions.keys.map { "OC_" + $0.rawValue }.sorted().joined(separator: ","),
            "disabledBasicConditions": config.disabledBasicConditions.map(\.rawValue).sorted().joined(separator: ","),
            "valueThreeMaximumInput": String(config.valueThreeMaximum),
            "svip10RRangeInput": "\(config.six250RRange.lowerBound)-\(config.six250RRange.upperBound)",
            "svip10ValueTwoMaximumInput": String(config.valueTwoMaximum),
            "sumInput": "\(config.sumRange.lowerBound)-\(config.sumRange.upperBound)",
            "displacementInput": "\(config.displacementRange.lowerBound)-\(config.displacementRange.upperBound)",
            "svip4MinimumDistinctMOrdersInput": String(config.minimumDistinctDisplacementOrders),
            "svip5TailReductionEnabled": config.svip5TailRemovalCount > 0 ? "1" : "0",
            "svip5FourCountFilterEnabled": config.svip5FourCountFilterEnabled ? "1" : "0",
            "frontFiveActualMEnabled": config.frontFiveActualMEnabled ? "1" : "0",
            "frontFiveActualMRangeInput": "\(config.frontFiveActualMRange.lowerBound)-\(config.frontFiveActualMRange.upperBound)",
            "frontFiveNoTripleDrawEnabled": config.frontFiveNoTripleDrawEnabled ? "1" : "0",
            "frontFiveLossCountEnabled": config.frontFiveLossCountEnabled ? "1" : "0",
            "frontFiveWinCountEnabled": config.frontFiveWinCountEnabled ? "1" : "0",
            "combinedThreeStructureEnabled": config.combinedThreeStructureEnabled ? "1" : "0",
            "combinedThreeRRangeInput": "\(config.combinedThreeRRange.lowerBound)-\(config.combinedThreeRRange.upperBound)",
            "sixLossCount14Enabled": config.sixLossCount14Enabled ? "1" : "0",
            "frontFiveR39Enabled": config.frontFiveR39Enabled ? "1" : "0",
            "frontFiveNoTripleLossEnabled": config.frontFiveNoTripleLossEnabled ? "1" : "0",
            "frontFiveLossCountRangeInput": "\(config.frontFiveLossCountRange.lowerBound)-\(config.frontFiveLossCountRange.upperBound)",
            "frontFiveWinCountRangeInput": "\(config.frontFiveWinCountRange.lowerBound)-\(config.frontFiveWinCountRange.upperBound)",
            "varianceInput": String(config.varianceMaximum),
            "valueTwoMaximumInput": String(config.valueTwoMaximum),
            "transitionMinimumInput": String(config.transitionMinimumPercent),
            "roughnessMaximumInput": String(config.roughnessMaximum),
            "breakpointInput": "\(config.breakpointRange.lowerBound)-\(config.breakpointRange.upperBound)",
            "productRemovalCountInput": "0",
            "frontThreeMaximumFourFilterEnabled": config.frontThreeMaximumFourCount == nil ? "0" : "1",
            "noFourPositionFilterEnabled": config.noFourPositions.isEmpty ? "0" : "1",
            "noFourPositionInput": config.noFourPositions.first.map(String.init) ?? "1",
            "secondNoFourPositionFilterEnabled": config.noFourPositions.count > 1 ? "1" : "0",
            "secondNoFourPositionInput": config.noFourPositions.dropFirst().first.map(String.init) ?? "2",
            "outcomeConditionToleranceEnabled": config.outcomeConditionToleranceEnabled ? "1" : "0",
            "outcomeConditionToleranceInput": "\(config.outcomeConditionToleranceRange.lowerBound)-\(config.outcomeConditionToleranceRange.upperBound)",
            "allConditionsToleranceEnabled": config.allConditionsToleranceEnabled ? "1" : "0",
            "allConditionsToleranceInput": "\(config.allConditionsToleranceRange.lowerBound)-\(config.allConditionsToleranceRange.upperBound)",
            "consecutiveRunsEnabled": config.consecutiveRunsEnabled ? "1" : "0",
            "nonLossRunInput": "\(config.nonLossRunRange.lowerBound)-\(config.nonLossRunRange.upperBound)",
            "nonDrawRunInput": "\(config.nonDrawRunRange.lowerBound)-\(config.nonDrawRunRange.upperBound)",
            "nonWinRunInput": "\(config.nonWinRunRange.lowerBound)-\(config.nonWinRunRange.upperBound)",
            "consecutiveRunTolerance": "\(config.consecutiveRunToleranceRange.lowerBound)-\(config.consecutiveRunToleranceRange.upperBound)",
            "secondaryConsecutiveRunsEnabled": config.secondaryConsecutiveRunsEnabled ? "1" : "0",
            "secondaryConsecutiveRunRangeInput": "\(config.secondaryConsecutiveRunRange.lowerBound)-\(config.secondaryConsecutiveRunRange.upperBound)",
            "secondaryConsecutiveRunToleranceInput": "\(config.secondaryConsecutiveRunToleranceRange.lowerBound)-\(config.secondaryConsecutiveRunToleranceRange.upperBound)",
            "sameResultRunsEnabled": config.sameResultRunsEnabled ? "1" : "0",
            "winRunInput": "\(config.winRunRange.lowerBound)-\(config.winRunRange.upperBound)",
            "drawRunInput": "\(config.drawRunRange.lowerBound)-\(config.drawRunRange.upperBound)",
            "lossRunInput": "\(config.lossRunRange.lowerBound)-\(config.lossRunRange.upperBound)",
            "sameResultRunTolerance": "\(config.sameResultRunToleranceRange.lowerBound)-\(config.sameResultRunToleranceRange.upperBound)",
            "protectConsecutiveDrawPair": config.protectConsecutiveDrawPair ? "1" : "0",
            "spProductFilterEnabled": config.spProductFilterEnabled ? "1" : "0",
            "spProductRangeInput": "\(config.spProductRange.lowerBound)-\(config.spProductRange.upperBound)",
            "customHandicapOddsProductFilterEnabled": config.customHandicapOddsProductFilterEnabled ? "1" : "0",
            "customHandicapOddsProductMinimum": String(config.customHandicapOddsProductRange.lowerBound),
            "customHandicapOddsProductMaximum": String(config.customHandicapOddsProductRange.upperBound),
            "customHandicapOddsProductMatchCount": String(config.customHandicapOddsProductMatchCount ?? 0),
            "customHandicapOddsSumFilterEnabled": config.customHandicapOddsSumFilterEnabled ? "1" : "0",
            "customHandicapOddsSumMinimum": String(config.customHandicapOddsSumRange.lowerBound),
            "customHandicapOddsSumMaximum": String(config.customHandicapOddsSumRange.upperBound),
            "prizeRangeFilterEnabled": config.prizeRangeFilterEnabled ? "1" : "0",
            "estimatedPrizeRangeInput": "\(config.estimatedPrizeRange.lowerBound)-\(config.estimatedPrizeRange.upperBound)",
            "spRiskFilterEnabled": config.spRiskFilterEnabled ? "1" : "0",
            "maximumSingleSPInput": String(config.maximumSingleSP),
            "highSPThresholdInput": String(config.highSPThreshold),
            "highSPCountRangeInput": "\(config.highSPCountRange.lowerBound)-\(config.highSPCountRange.upperBound)",
            "minimumProbabilityFilterEnabled": config.minimumProbabilityFilterEnabled ? "1" : "0",
            "minimumSingleProbabilityInput": String(config.minimumSingleProbabilityPercent),
            "jointProbabilityFilterEnabled": config.jointProbabilityFilterEnabled ? "1" : "0",
            "jointProbabilityRangeInput": "\(config.jointProbabilityPercentRange.lowerBound)-\(config.jointProbabilityPercentRange.upperBound)",
            "vip12ProbabilityReductionEnabled": config.vip12ProbabilityReductionEnabled ? "1" : "0",
            "vip16Top200Enabled": config.vip16Top200Enabled ? "1" : "0",
            "vip18Top200Enabled": config.vip18Top200Enabled ? "1" : "0",
            "vip19CustomOddsTop200Enabled": config.vip19CustomOddsTop200Enabled ? "1" : "0",
            "groupFilterEnabled": config.groupFilterEnabled ? "1" : "0",
            "groupFilterMode": config.groupFilterMode.rawValue,
            "frontGroupOutcomeSumInput": "\(config.frontGroupOutcomeSumRange.lowerBound)-\(config.frontGroupOutcomeSumRange.upperBound)",
            "backGroupOutcomeSumInput": "\(config.backGroupOutcomeSumRange.lowerBound)-\(config.backGroupOutcomeSumRange.upperBound)",
            "frontGroupSPProductInput": "\(config.frontGroupSPProductRange.lowerBound)-\(config.frontGroupSPProductRange.upperBound)",
            "backGroupSPProductInput": "\(config.backGroupSPProductRange.lowerBound)-\(config.backGroupSPProductRange.upperBound)",
            "universal150CompressionEnabled": config.universal150CompressionEnabled ? "1" : "0",
            "universal247ToleranceEnabled": config.universal247ToleranceEnabled ? "1" : "0",
            "universal247ToleranceThresholdInput": config.universal247ToleranceThreshold.formatted(
                .number.precision(.fractionLength(0...6))
            ),
            "productSumV10Top150Enabled": config.productSumV10Top150Enabled ? "1" : "0"
        ]
        if let single = config.extraMatches.first(where: { $0.outcomes.count == 1 }) {
            values["singleOutcomeInput"] = single.compactOutcomes
        }
        if config.svip7RankOddsEnabled {
            values["selectedConditionVersionID"] = "svip7-odds-rank-280"
            values["vipConditionsEnabled"] = "1"
            values["currentConditionPackageEnabled"] = config.conditionPackageEnabled ? "1" : "0"
        }
        if let enabled = config.highPass93GroupEnabled {
            values["svvvHighPass40Enabled"] = enabled ? "1" : "0"
        }
        if let enabled = config.highPass98GroupEnabled {
            values["svvvHighPass100Enabled"] = enabled ? "1" : "0"
        }
        if let enabled = config.highPass98FiftyGroupEnabled {
            values["svvvHighPass50Enabled"] = enabled ? "1" : "0"
            values["svvvHighPass50DoubleEnabled"] = config.highPass50DoubleEnabled ? "1" : "0"
        }
        for condition in OutcomeCondition.activeCases {
            values["OC_" + condition.rawValue] = config.outcomeConditions[condition].map {
                "\($0.lowerBound)-\($0.upperBound)"
            } ?? ""
            values["OCON_" + condition.rawValue] = config.outcomeConditions[condition] == nil ? "0" : "1"
        }
        for n in [50, 100, 150, 200] { values["historyWindow\(n)Enabled"] = config.historicalOutcomeWindows.contains(n) ? "1" : "0" }
        values["historyWindowBeforeIssue"] = config.historicalOutcomeBeforeIssue
        values["automaticFinalOutcomeExclusions"] = config.automaticFinalOutcomeExclusions ? "1" : "0"
        values["finalResultInverted"] = config.finalResultInverted ? "1" : "0"
        for slot in 1...2 {
            let rule = config.finalOutcomeExclusions.first { $0.slot == slot }
            values["finalOutcomeExclusion\(slot)Enabled"] = rule == nil ? "0" : "1"
            values["finalOutcomeExclusion\(slot)Position"] = String(rule?.position ?? slot)
            values["finalOutcomeExclusion\(slot)Outcome"] = String(rule?.outcome ?? 3)
        }
        return values
    }
}


/// Immutable bundled, settled six-outcome archive. Strict issue cutoff prevents same-issue leakage.
/// Window sizes count groups, not distinct strings. Repeated strings are removed only once.
enum HistoricalOutcomeWindows {
    struct Row: Codable, Sendable { let issue: String; let start: Int; let outcomes: [Int] }
    static let rows: [Row] = {
        guard let url = Bundle.main.url(forResource: "HistoricalOutcomeWindows", withExtension: "json"),
              let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return decoded.filter { $0.outcomes.count == 6 && $0.outcomes.allSatisfy { [3, 1, 0].contains($0) } }
            .sorted { $0.issue == $1.issue ? $0.start < $1.start : $0.issue < $1.issue }
    }()
    static func priorRows(before issue: String, limit: Int, archive: [Row] = rows) -> [Row] {
        guard issue.count == 5, issue.allSatisfy(\.isNumber), limit > 0 else { return [] }
        return Array(archive.filter { $0.issue < issue }.suffix(limit))
    }
}


/// Fixed 2024-calibrated odds model. No observed outcomes or settled prizes are inputs.
/// One lowest-probability raw outcome per match; choose the two safest distinct matches.
enum FinalOutcomeCutRecommender {
    struct Recommendation: Equatable, Sendable {
        let rules: [FinalOutcomeExclusion]
        let removedProbabilities: [Double]
        var estimatedCoverage: Double { removedProbabilities.reduce(1) { $0 * (1 - $1) } }
    }
    static func recommend(odds: [[Double]]) -> Recommendation? {
        guard odds.count >= 6 else { return nil }
        var candidates: [(Int, Int, Double)] = []
        for position in 0..<6 {
            guard let p = AutomaticDoubleSelector.probabilities(odds: odds[position], calibrated: true) else { return nil }
            let index = p.indices.min { p[$0] == p[$1] ? $0 < $1 : p[$0] < p[$1] }!
            candidates.append((position + 1, [3,1,0][index], p[index]))
        }
        let chosen = Array(candidates.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }.prefix(2))
        return Recommendation(rules: chosen.enumerated().map { FinalOutcomeExclusion(slot: $0.offset + 1, position: $0.element.0, outcome: $0.element.1) }, removedProbabilities: chosen.map { $0.2 })
    }
    static func shouldApply(enabled: Bool, selectionKey: String, manualSelectionKey: String) -> Bool {
        enabled && !selectionKey.isEmpty && selectionKey != manualSelectionKey
    }
}

/// Atomic fixture-number edit; never permits duplicate matches in a ticket.
enum MatchNumberReplacement {
    enum Failure: LocalizedError {
        case invalid, missing, duplicate, same
        var errorDescription: String? {
            switch self {
            case .invalid: return "场号须为正整数，当前已选场次也必须完整且不重复。"
            case .missing: return "原场号不在当前已选场次中。"
            case .duplicate: return "新场号已在当前已选场次中，不能重复选同一场比赛。"
            case .same: return "原场号和新场号相同，无需替换。"
            }
        }
    }
    static func replacing(_ selected: [String], from: String, to: String) throws -> [String] {
        func number(_ value: String) -> Int? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.allSatisfy(\.isNumber), let n = Int(value), n > 0, n < Int.max - 6 else { return nil }
            return n
        }
        guard let old = number(from), let new = number(to) else { throw Failure.invalid }
        let numbers = selected.compactMap(number)
        guard !numbers.isEmpty, numbers.count == selected.count, Set(numbers).count == numbers.count else { throw Failure.invalid }
        guard old != new else { throw Failure.same }
        guard let index = numbers.firstIndex(of: old) else { throw Failure.missing }
        guard !numbers.contains(new) else { throw Failure.duplicate }
        var result = selected
        result[index] = String(new)
        return result
    }
}
