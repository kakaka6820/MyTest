import Foundation

/// Prospective only: no scores, outcomes or retrospective predictions enter a forecast.
struct DoubleForwardForecast: Codable, Equatable, Sendable, Identifiable {
    static let modelVersion = "bounded-market-tminus120-v2"
    static let allABCDModelVersion = modelVersion + "-abcd-fill-v1"
    static let frontTwoADModelVersion = modelVersion + "-front-ad-v1"
    static let frontTwoADAllABCDModelVersion = modelVersion + "-front-ad-abcd-v1"
    static let rankedFrontTwoModelVersion = modelVersion + "-front-two-direction-tail4-v1"
    static let fixedFrontTwoModelVersion = modelVersion + "-front-two-sequential-tail4-v1"
    static let frontTwoADTailModelVersion = modelVersion + "-front-ad-tail4-v1"
    static let adWithinSixModelVersion = modelVersion + "-ad-within-six-v1"
    static let adWithinSixFillModelVersion = modelVersion + "-ad-within-six-fill-v1"
    static let singleADWithinSixModelVersion = modelVersion + "-single-ad-within-six-fill-v1"
    static let singleAnyWithinSixModelVersion = modelVersion + "-single-any-within-six-v1"
    static func selectionModelVersion(allABCD: Bool, frontTwoAD: Bool, fixedFrontTwo: Bool = false, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> String {
        if adDoublesWithinSix { return adDoubleCountWithinSix == 1 ? singleADWithinSixModelVersion : adWithinSixFillModelVersion }
        if !fixedFrontTwo && automaticDoubleCount == 1 { return singleAnyWithinSixModelVersion }
        if fixedFrontTwo { return frontTwoAD ? frontTwoADTailModelVersion : fixedFrontTwoModelVersion }
        return frontTwoAD ? (allABCD ? frontTwoADAllABCDModelVersion : frontTwoADModelVersion)
            : (allABCD ? allABCDModelVersion : modelVersion)
    }
    private var usesFixedFrontTwo: Bool { [Self.fixedFrontTwoModelVersion, Self.rankedFrontTwoModelVersion, Self.frontTwoADTailModelVersion].contains(version) }
    private var usesAllABCD: Bool { version == Self.allABCDModelVersion || version == Self.frontTwoADAllABCDModelVersion }
    private var usesFrontTwoAD: Bool { [Self.frontTwoADModelVersion, Self.frontTwoADAllABCDModelVersion, Self.frontTwoADTailModelVersion].contains(version) }
    private var usesADWithinSix: Bool { [Self.adWithinSixModelVersion, Self.adWithinSixFillModelVersion, Self.singleADWithinSixModelVersion].contains(version) }
    struct Fixture: Codable, Equatable, Sendable {
        let number: Int
        let fixtureID: String
        let handicap: Int
        let cutoff: Date
        let logic: String
        let odds: [Double]
        let marketCapturedAt: Date?
    }
    struct Leg: Codable, Equatable, Sendable {
        let number: Int
        let retained: [Int]
        let mappedPair: [Int]
        init(_ choice: AutomaticDoubleChoice) {
            number = choice.number; retained = choice.retainedOutcomes; mappedPair = choice.mappedPair
        }
    }
    let id: UUID
    let version: String
    let issue: String
    let first: Int
    let recordedAt: Date
    let cutoff: Date
    let calibrated: Bool
    let factors: String
    let fixtures: [Fixture]
    let selected: [Leg]
    let baseline: [Leg]
    var groupKey: String {
        if version == Self.singleAnyWithinSixModelVersion { return "\(issue):single-any-within-six:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if version == Self.singleADWithinSixModelVersion { return "\(issue):single-ad-within-six-fill:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if version == Self.adWithinSixFillModelVersion { return "\(issue):ad-within-six-fill:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if version == Self.adWithinSixModelVersion { return "\(issue):ad-within-six:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if version == Self.frontTwoADTailModelVersion { return "\(issue):front-ad-tail4:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if version == Self.fixedFrontTwoModelVersion { return "\(issue):front-two-sequential:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if usesFixedFrontTwo { return "\(issue):front-two-direction:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        if usesFrontTwoAD { return "\(issue):front-ad:\(fixtures.map { String($0.number) }.joined(separator: ","))" }
        return version == Self.allABCDModelVersion
            ? "\(issue):abcd:\(fixtures.map { String($0.number) }.joined(separator: ","))"
            : "\(issue):\(first)"
    }
    var cohortKey: String { Self.cohort(calibrated: calibrated, factors: factors, version: version) }
    static func cohort(calibrated: Bool, factors: String, version: String = modelVersion) -> String {
        "\(version)|\(calibrated)|\(factors)"
    }

    static func make(selection: AutomaticDoubleSelection, matches: [BeijingSingleMatch],
                     calibrated: Bool, factors: Set<DoubleJudgmentFactor>, now: Date = Date(),
                     allABCDSelection: Bool = false, frontTwoADSelection: Bool = false, fixedFrontTwoDoubles: Bool = false, adDoublesWithinSix: Bool = false, adDoubleCountWithinSix: Int = 2, automaticDoubleCount: Int = 2) -> Self? {
        guard let first = selection.matches.first?.number, first > 0, first < Int.max - 6,
              selection.matches.count == 6, Set(selection.matches.map(\.number)).count == 6,
              selection.matches.map(\.number) == selection.matches.map(\.number).sorted(),
              let issue = matches.first?.issue else { return nil }
        if allABCDSelection && Set(selection.matches.map(\.logic)) != Set(LogicMapping.allCases) { return nil }
        if frontTwoADSelection && !selection.matches.prefix(2).allSatisfy({ $0.logic == .a || $0.logic == .d }) { return nil }
        if !adDoublesWithinSix && !fixedFrontTwoDoubles && !allABCDSelection && !frontTwoADSelection && selection.matches.map(\.number) != Array(first..<(first + 6)) { return nil }
        var fixtures: [Fixture] = []
        for candidate in selection.matches {
            let rows = matches.filter { Int($0.matchNumber) == candidate.number && $0.issue == issue }
            guard rows.count == 1, let match = rows.first, match.status.contains("未"),
                  match.homeScore == nil, match.awayScore == nil, match.settledSP == nil,
                  let handicap = match.handicap,
                  let time = DoubleMarketDataClient.kickoff(issue: issue, matchTime: match.matchTime), time > now,
                  !match.fixtureID.isEmpty else { return nil }
            fixtures.append(Fixture(number: candidate.number, fixtureID: match.fixtureID, handicap: handicap,
                cutoff: time, logic: candidate.logic.rawValue, odds: candidate.odds,
                marketCapturedAt: candidate.evidence?.capturedAt))
        }
        // Compare the same six quotes and calibration, with only the extra factors removed.
        guard let base = AutomaticDoubleSelector.recommend(numbers: selection.matches.map(\.number), candidates: selection.matches, calibrated: calibrated, fixedFrontTwo: fixedFrontTwoDoubles, requireFrontTwoAD: frontTwoADSelection, adDoublesWithinSix: adDoublesWithinSix, adDoubleCountWithinSix: adDoubleCountWithinSix, automaticDoubleCount: automaticDoubleCount),
              let firstTime = fixtures.map(\.cutoff).min() else { return nil }
        let cutoff = firstTime.addingTimeInterval(-DoubleMarketDataClient.decisionLeadTime)
        let value = Self(id: UUID(), version: selectionModelVersion(allABCD: allABCDSelection, frontTwoAD: frontTwoADSelection, fixedFrontTwo: fixedFrontTwoDoubles, adDoublesWithinSix: adDoublesWithinSix, adDoubleCountWithinSix: adDoubleCountWithinSix, automaticDoubleCount: automaticDoubleCount), issue: issue, first: first, recordedAt: now,
            cutoff: cutoff, calibrated: calibrated, factors: DoubleJudgmentFactor.text(factors),
            fixtures: fixtures, selected: selection.choices.map(Leg.init), baseline: base.choices.map(Leg.init))
        return value.isValid ? value : nil
    }

    var isValid: Bool {
        guard issue.count == 5, issue.allSatisfy(\.isNumber), first > 0, first < Int.max - 6,
              !version.isEmpty, DoubleJudgmentFactor.parse(factors) != nil,
              fixtures.count == 6, Set(fixtures.map(\.number)).count == 6,
              fixtures.first?.number == first, fixtures.map(\.number) == fixtures.map(\.number).sorted(),
              Set(fixtures.map(\.fixtureID)).count == 6,
              recordedAt.timeIntervalSince1970 > 946684800, recordedAt < cutoff,
              fixtures.map(\.cutoff).min()?.addingTimeInterval(-DoubleMarketDataClient.decisionLeadTime) == cutoff,
              fixtures.allSatisfy({ !$0.fixtureID.isEmpty && DoubleJudgmentScorer.validOdds($0.odds)
                  && LogicMapping(rawValue: $0.logic) != nil
                  && ($0.marketCapturedAt.map { $0 <= recordedAt && $0 < cutoff } ?? true) }) else { return false }
        if usesAllABCD && Set(fixtures.map(\.logic)) != Set(LogicMapping.allCases.map(\.rawValue)) { return false }
        if usesFrontTwoAD && !fixtures.prefix(2).allSatisfy({ $0.logic == "a" || $0.logic == "d" }) { return false }
        if !usesADWithinSix && !usesFixedFrontTwo && !usesAllABCD && !usesFrontTwoAD && fixtures.map(\.number) != Array(first..<(first + 6)) { return false }
        if usesADWithinSix {
            guard [selected, baseline].allSatisfy({ legs in
                legs.allSatisfy { leg in
                    guard let fixture = fixtures.first(where: { $0.number == leg.number }) else { return false }
                    return (fixture.logic == "a" && leg.retained == [3, 1])
                        || (fixture.logic == "d" && leg.retained == [1, 0])
                }
            }) else { return false }
        }
        if usesFixedFrontTwo {
            let tail = Array(fixtures.suffix(4).map(\.number))
            guard zip(tail, tail.dropFirst()).allSatisfy({ $1 == $0 + 1 }),
                  [selected, baseline].allSatisfy({ legs in
                      legs.map(\.number) == fixtures.prefix(2).map(\.number)
                          && legs.allSatisfy { Set($0.retained) == Set([3, 1]) || Set($0.retained) == Set([1, 0]) }
                  }) else { return false }
            if version == Self.frontTwoADTailModelVersion {
                guard [selected, baseline].allSatisfy({ legs in
                    zip(legs, fixtures.prefix(2)).allSatisfy { leg, fixture in
                        leg.retained == (fixture.logic == "a" ? [3, 1] : [1, 0])
                    }
                }) else { return false }
            }
        }
        return [selected, baseline].allSatisfy { legs in
            legs.count == ([Self.singleADWithinSixModelVersion, Self.singleAnyWithinSixModelVersion].contains(version) ? 1 : 2)
                && Set(legs.map(\.number)).count == legs.count && legs.allSatisfy { leg in
                guard let fixture = fixtures.first(where: { $0.number == leg.number }),
                      let logic = LogicMapping(rawValue: fixture.logic) else { return false }
                return leg.retained.count == 2 && Set(leg.retained).count == 2
                    && Set(leg.retained).isSubset(of: [3,1,0])
                    && [[2,3], [2,4], [3,4]].contains(leg.mappedPair)
                    && Set(leg.retained.map { logic.value(for: $0) }) == Set(leg.mappedPair)
            }
        }
    }
}

struct DoubleForwardSettlement: Codable, Equatable, Sendable {
    struct Score: Codable, Equatable, Sendable {
        let number: Int
        let fixtureID: String
        let home: Int
        let away: Int
        let status: String
    }
    let forecastID: UUID
    let observedAt: Date
    let scores: [Score]
    let source: String
    static func make(forecast: DoubleForwardForecast, matches: [BeijingSingleMatch], now: Date) -> Self? {
        guard forecast.isValid, forecast.fixtures.allSatisfy({ $0.cutoff < now }) else { return nil }
        var scores: [Score] = []
        for fixture in forecast.fixtures {
            let rows = matches.filter { $0.issue == forecast.issue && Int($0.matchNumber) == fixture.number
                && $0.fixtureID == fixture.fixtureID }
            guard rows.count == 1, let match = rows.first, QueryFinalityGate.isFinallyEnded(match),
                  !match.status.contains("未"), !match.status.contains("中断"), !match.status.contains("取消"),
                  !match.isPostponedOver12Hours, let home = match.homeScore, let away = match.awayScore,
                  home >= 0, away >= 0 else { return nil }
            scores.append(Score(number: fixture.number, fixtureID: fixture.fixtureID, home: home, away: away, status: match.status))
        }
        return Self(forecastID: forecast.id, observedAt: now, scores: scores, source: "500北单比分页·明确完赛")
    }
    func outcomes(for forecast: DoubleForwardForecast) -> [Int:Int]? {
        guard forecastID == forecast.id, scores.count == 6, observedAt > forecast.cutoff,
              Set(scores.map(\.number)).count == 6 else { return nil }
        var result: [Int:Int] = [:]
        for fixture in forecast.fixtures {
            guard let score = scores.first(where: { $0.number == fixture.number && $0.fixtureID == fixture.fixtureID }),
                  score.home >= 0, score.away >= 0 else { return nil }
            // Always use the handicap locked in the prediction, even if the live page changes it.
            let delta = score.home + fixture.handicap - score.away
            result[fixture.number] = delta > 0 ? 3 : (delta == 0 ? 1 : 0)
        }
        return result
    }
}

struct DoubleForwardSummary: Sendable {
    struct Row: Identifiable, Sendable {
        let forecast: DoubleForwardForecast
        let selectedHit: Bool?
        let baselineHit: Bool?
        var id: UUID { forecast.id }
    }
    let registered: Int
    let settled: Int
    let selectedHits: Int
    let baselineHits: Int
    let improved: Int
    let worsened: Int
    let rows: [Row]
    var pending: Int { registered - settled }
    var hasOverlappingFixtures: Bool {
        let ids = rows.filter { $0.selectedHit != nil }.flatMap { row in
            row.forecast.fixtures.map { "\(row.forecast.issue):\($0.fixtureID)" }
        }
        return Set(ids).count != ids.count
    }
    /// Wilson interval prevents a tiny perfect streak from looking like established accuracy.
    var confidenceInterval: ClosedRange<Double>? {
        guard settled > 0, !hasOverlappingFixtures else { return nil }
        let n = Double(settled), p = Double(selectedHits) / n, z2 = 3.841458820694124
        let center = (p + z2/(2*n))/(1+z2/n)
        let half = sqrt(z2 * (p*(1-p)/n + z2/(4*n*n)))/(1+z2/n)
        return max(0,center-half)...min(1,center+half)
    }
}

/// One final forecast per six-match group: the last displayed pre-cutoff recommendation.
/// Pick that forecast BEFORE filtering by model/settings; no retrospective best-version picking.
actor DoubleForwardValidationStore {
    static let shared = DoubleForwardValidationStore()
    private struct Ledger: Codable {
        var version = 1
        var forecasts: [DoubleForwardForecast] = []
        var settlements: [DoubleForwardSettlement] = []
    }
    private let file: URL
    private var cached: Ledger?
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DoubleForwardValidation", isDirectory: true)
        file = base.appendingPathComponent("ledger-v1.json")
    }
    private func load() throws -> Ledger {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: file.path) else { return Ledger() }
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        guard ledger.version == 1, ledger.forecasts.allSatisfy(\.isValid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        cached = ledger; return ledger
    }
    private func save(_ ledger: Ledger) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ledger).write(to: file, options: .atomic)
        cached = ledger
    }
    private func latest(_ ledger: Ledger) -> [DoubleForwardForecast] {
        var groups: [String:DoubleForwardForecast] = [:]
        for forecast in ledger.forecasts {
            if groups[forecast.groupKey].map({ $0.recordedAt <= forecast.recordedAt }) ?? true {
                groups[forecast.groupKey] = forecast
            }
        }
        return groups.values.sorted { $0.recordedAt > $1.recordedAt }
    }
    @discardableResult func record(_ forecast: DoubleForwardForecast, now: Date = Date()) throws -> Bool {
        guard forecast.isValid, abs(forecast.recordedAt.timeIntervalSince(now)) < 60, now < forecast.cutoff else { return false }
        var ledger = try load()
        let previous = ledger.forecasts.filter { $0.groupKey == forecast.groupKey }
        // A changed source date cannot reopen an already locked group.
        guard previous.allSatisfy({ now < $0.cutoff && forecast.recordedAt > $0.recordedAt }) else { return false }
        if let last = previous.last, last.cohortKey == forecast.cohortKey,
           last.fixtures == forecast.fixtures, last.selected == forecast.selected, last.baseline == forecast.baseline { return false }
        ledger.forecasts.append(forecast)
        try save(ledger); return true
    }
    func issuesDue(now: Date = Date()) throws -> [String] {
        // Recent settled records are rechecked for source corrections as well.
        let ledger = try load()
        let settledIDs = Set(ledger.settlements.map(\.forecastID))
        let rows = latest(ledger).filter { $0.cutoff < now
            && (!settledIDs.contains($0.id) || now.timeIntervalSince($0.cutoff) < 30*86400) }
        return Array(Set(rows.map(\.issue))).sorted().reversed()
    }
    func reconcile(matches: [BeijingSingleMatch], now: Date = Date()) throws {
        var ledger = try load(), changed = false
        for forecast in latest(ledger) {
            guard let proof = DoubleForwardSettlement.make(forecast: forecast, matches: matches, now: now) else { continue }
            if let prior = ledger.settlements.last(where: { $0.forecastID == forecast.id }), prior.scores == proof.scores { continue }
            ledger.settlements.append(proof); changed = true
        }
        if changed { try save(ledger) }
    }
    func summary(cohort: String, now: Date = Date()) throws -> DoubleForwardSummary {
        let ledger = try load()
        let forecasts = latest(ledger).filter { $0.cohortKey == cohort }
        var rows: [DoubleForwardSummary.Row] = [], settled = 0, hits = 0, baseline = 0, improved = 0, worsened = 0
        for forecast in forecasts {
            let proof = ledger.settlements.last { $0.forecastID == forecast.id && $0.observedAt <= now }
            let outcomes = proof?.outcomes(for: forecast)
            let hit = outcomes.map { outcomes in forecast.selected.allSatisfy { leg in leg.retained.contains(outcomes[leg.number] ?? -1) } }
            let base = outcomes.map { outcomes in forecast.baseline.allSatisfy { leg in leg.retained.contains(outcomes[leg.number] ?? -1) } }
            if let hit, let base { settled += 1; hits += hit ? 1 : 0; baseline += base ? 1 : 0
                improved += hit && !base ? 1 : 0; worsened += !hit && base ? 1 : 0 }
            rows.append(.init(forecast: forecast, selectedHit: hit, baselineHit: base))
        }
        return DoubleForwardSummary(registered: forecasts.count, settled: settled, selectedHits: hits,
            baselineHits: baseline, improved: improved, worsened: worsened, rows: rows)
    }
}
