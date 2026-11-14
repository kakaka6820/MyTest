import Foundation

/// Separate archive for the user-requested William Hill / Macau source pair.
/// It never edits the frozen bounded-market-tminus120-v2 experiment or inputs.
struct MarketRecordSample: Codable, Equatable, Sendable {
    var capturedAt: Date
    var europeanCompanyID = 293
    var european: [Double]
    var openingEuropean: [Double]? = nil
    var asianCompanyID = 5
    var asian: DoubleAsianPoint? = nil
    var openingAsian: DoubleAsianPoint? = nil

    var isValid: Bool {
        europeanCompanyID == 293 && asianCompanyID == 5
            && (european.isEmpty || DoubleJudgmentScorer.validOdds(european))
            && (openingEuropean.map(DoubleJudgmentScorer.validOdds) ?? true)
            && [asian, openingAsian].compactMap { $0 }.allSatisfy(DoubleMarketEvidence.validAsian)
            && (!european.isEmpty || asian != nil)
            && capturedAt.timeIntervalSince1970 > 946684800
            && capturedAt <= Date().addingTimeInterval(60)
    }
}

struct MarketMatchRecord: Codable, Identifiable, Sendable {
    var issue: String
    var number: Int
    var fixtureID: String
    var league: String
    var home: String
    var away: String
    var kickoff: Date?
    var handicap: Int?
    var status: String
    var homeScore: Int?
    var awayScore: Int?
    /// Legacy single quotes have no verified observation time and stay outside
    /// the time series and every measured recommendation hit rate.
    var archivedEuropean: [Double]? = nil
    var samples: [MarketRecordSample] = []
    var message: String? = nil
    var id: String { "\(issue):\(number):\(fixtureID)" }
    var year: Int { 2000 + (Int(issue.prefix(2)) ?? 0) }
    var isFinal: Bool {
        !status.contains("未") && ["完", "结束", "finished"].contains(where: status.lowercased().contains)
            && homeScore.map { $0 >= 0 } == true && awayScore.map { $0 >= 0 } == true
    }
    var actualOutcome: Int? {
        guard isFinal, let handicap, let homeScore, let awayScore else { return nil }
        let delta = homeScore + handicap - awayScore
        return delta > 0 ? 3 : delta == 0 ? 1 : 0
    }
    var current: MarketRecordSample? { samples.max { $0.capturedAt < $1.capturedAt } }
    var latestEuropean: MarketRecordSample? { samples.filter { DoubleJudgmentScorer.validOdds($0.european) }.max { $0.capturedAt < $1.capturedAt } }
    var latestAsian: MarketRecordSample? { samples.filter { $0.asian != nil }.max { $0.capturedAt < $1.capturedAt } }

    /// A recently observed price at or before a time; never relabel a later close.
    func sample(before date: Date, freshness: TimeInterval? = nil, asian: Bool = false) -> MarketRecordSample? {
        let found = samples.filter { $0.isValid && $0.capturedAt <= date
            && (asian ? $0.asian != nil : DoubleJudgmentScorer.validOdds($0.european)) }.max { $0.capturedAt < $1.capturedAt }
        guard let found, freshness.map({ date.timeIntervalSince(found.capturedAt) <= $0 }) ?? true else { return nil }
        return found
    }
    func stage(hoursBefore: Double, asian: Bool = false) -> MarketRecordSample? {
        kickoff.flatMap { sample(before: $0.addingTimeInterval(-hoursBefore * 3600), freshness: 1800, asian: asian) }
    }
}

struct MarketRecordIdentity: Codable, Equatable, Sendable {
    var number: Int
    var fixtureID: String
    var handicap: Int
    var kickoff: Date
}

struct MarketRecordCandidate: Codable, Sendable {
    var issue: String
    var first: Int
    var registeredAt: Date
    var cutoff: Date
    var fixtures: [MarketRecordIdentity]
    /// The already-inspected setup issue stays exploratory. A new source/model
    /// gets its own untouched future cohort; it cannot clean the old v2 batch.
    var exploratory: Bool
    var priorObservedSamples: Bool? = nil
    var key: String { "\(issue):\(first)" }
}

struct MarketRecordLeg: Codable, Sendable {
    var number: Int
    var handicap: Int
    var mappedPair: [Int]
    var retained: [Int]
    var evidenceAt: Date
}

struct MarketRecordRecommendation: Codable, Identifiable, Sendable {
    var issue: String
    var first: Int
    var modelVersion = "william-macau-observed-v1"
    var madeAt: Date
    var cutoff: Date
    var fixtures: [MarketRecordIdentity]
    var legs: [MarketRecordLeg]
    var kind: String // prospective, exploratory, archiveReference
    var id: String { "\(issue):\(first)" }
}

struct MarketRecordsArchive: Codable, Sendable {
    var version = 1
    var generatedAt = Date()
    var coverageNote = "2025、2026年已发现的北单比赛；历史缺失阶段待补，2026截至采集当日。"
    var records: [MarketMatchRecord] = []
    var candidates: [MarketRecordCandidate] = []
    var recommendations: [MarketRecordRecommendation] = []

    func validate() throws {
        guard version == 1, Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ r in
                  r.issue.count == 5 && r.issue.allSatisfy(\.isNumber) && [2025, 2026].contains(r.year)
                      && (1...10000).contains(r.number) && !r.fixtureID.isEmpty && r.fixtureID.allSatisfy(\.isNumber)
                      && r.samples.allSatisfy(\.isValid)
              }), Set(candidates.map(\.key)).count == candidates.count,
              Set(recommendations.map(\.id)).count == recommendations.count,
              recommendations.allSatisfy({ p in
                  p.first > 0 && p.first <= 9995
                      && p.fixtures.count == 6 && p.fixtures.map(\.number) == Array(p.first..<(p.first+6))
                      && Set(p.fixtures.map(\.fixtureID)).count == 6 && p.legs.count == 2
                      && Set(p.legs.map(\.number)).count == 2
                      && p.legs.allSatisfy { leg in
                          p.fixtures.contains { $0.number == leg.number && $0.handicap == leg.handicap }
                              && [[2,3],[2,4],[3,4]].contains(leg.mappedPair)
                              && Set(leg.retained).count == 2 && Set(leg.retained).isSubset(of:[3,1,0])
                      }
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    mutating func merge(_ incoming: [MarketMatchRecord]) {
        var rows = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var row in incoming {
            if let old = rows[row.id] {
                var points = Dictionary(old.samples.map { ($0.capturedAt, $0) }, uniquingKeysWith: { _, b in b })
                for point in row.samples where point.isValid { points[point.capturedAt] = point }
                row.samples = Array(points.values.sorted { $0.capturedAt < $1.capturedAt }.suffix(256))
                // A transient scrape failure must not erase explicitly final scores.
                if !row.isFinal && old.isFinal {
                    row.status = old.status; row.homeScore = old.homeScore; row.awayScore = old.awayScore
                }
            }
            rows[row.id] = row
        }
        records = rows.values.sorted { $0.issue == $1.issue ? $0.number < $1.number : $0.issue < $1.issue }
        generatedAt = Date()
    }

    mutating func register(_ metadata: [MarketMatchRecord], now: Date = Date(), setupIssue: String = "26108") {
        guard let issue = metadata.first?.issue else { return }
        let maxNumber = metadata.map(\.number).max() ?? 0
        for first in HistoricalBatchPlanner.groupStarts(maximumMatchNumber: maxNumber) {
            let six = metadata.filter { (first..<(first+6)).contains($0.number) }.sorted { $0.number < $1.number }
            guard six.count == 6, six.allSatisfy({ $0.issue == issue && $0.status.contains("未") }),
                  let identities = Self.identities(six), let earliest = identities.map(\.kickoff).min(),
                  now < earliest.addingTimeInterval(-7200),
                  !candidates.contains(where: { $0.issue == issue && $0.first == first }) else { continue }
            let alreadyObserved = six.contains { row in records.contains { $0.id == row.id && !$0.samples.isEmpty } }
            candidates.append(MarketRecordCandidate(issue: issue, first: first, registeredAt: now,
                cutoff: earliest.addingTimeInterval(-7200), fixtures: identities,
                exploratory: issue <= setupIssue, priorObservedSamples: alreadyObserved))
        }
    }

    static func identities(_ rows: [MarketMatchRecord]) -> [MarketRecordIdentity]? {
        var result: [MarketRecordIdentity] = []
        for row in rows {
            guard let handicap = row.handicap, let kickoff = row.kickoff else { return nil }
            result.append(MarketRecordIdentity(number: row.number, fixtureID: row.fixtureID, handicap: handicap, kickoff: kickoff))
        }
        return result
    }

    mutating func updateRecommendations(now: Date = Date()) {
        let issues = Dictionary(grouping: records, by: \.issue)
        var saved = Dictionary(recommendations.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for (issue, rows) in issues {
            for first in HistoricalBatchPlanner.groupStarts(maximumMatchNumber: rows.map(\.number).max() ?? 0) {
                let key = "\(issue):\(first)"
                if let old = saved[key], old.kind != "archiveReference", now >= old.cutoff { continue }
                let six = rows.filter { (first..<(first+6)).contains($0.number) }.sorted { $0.number < $1.number }
                let candidate = candidates.first { $0.key == key }
                if let result = MarketRecordSelector.recommend(six, candidate: candidate, now: now) {
                    if result.kind == "archiveReference", let old=saved[key], old.kind != "archiveReference" { continue }
                    saved[key] = result
                }
            }
        }
        recommendations = saved.values.sorted { $0.issue == $1.issue ? $0.first < $1.first : $0.issue < $1.issue }
    }
}

enum MarketRecordSelector {
    static func recommend(_ six: [MarketMatchRecord], candidate: MarketRecordCandidate?, now: Date) -> MarketRecordRecommendation? {
        guard six.count == 6, let first = six.first?.number,
              six.map(\.number) == Array(first..<(first+6)), Set(six.map(\.issue)).count == 1,
              let identities = MarketRecordsArchive.identities(six),
              let earliest = identities.map(\.kickoff).min() else { return nil }
        let cutoff = earliest.addingTimeInterval(-7200)
        let beforeLock = now < cutoff
        var scored: [(MarketRecordLeg, Double)] = []
        var completeEvidence = true
        for row in six {
            let sample = beforeLock ? row.sample(before: now, freshness:1800) : row.sample(before: cutoff)
            let asianSample = row.sample(before: beforeLock ? now : cutoff, freshness:beforeLock ? 1800:nil, asian: true)
            let imported = row.archivedEuropean.map { MarketRecordSample(capturedAt: .distantPast, european: $0) }
            let quote = sample ?? row.latestEuropean ?? imported
            guard let quote, let handicap = row.handicap,
                  let odds = HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: quote.european, handicap: handicap),
                  let logic = LogicMapping.derivedFromComparisonTableOdds(odds),
                  let base = AutomaticDoubleSelector.probabilities(odds: odds, calibrated: true) else { return nil }
            completeEvidence = completeEvidence && sample != nil
                && (candidate.map { c in quote.capturedAt >= c.registeredAt
                    && (asianSample.map { $0.capturedAt >= c.registeredAt } ?? true) } ?? false)
            var adjustment = [0.0, 0, 0]
            // Comparisons use only this book's observed Euro prices and Macau's
            // Asian prices. Missing historical stages never become synthetic ticks.
            if sample != nil {
                let firstObserved = row.samples.filter { $0.capturedAt <= quote.capturedAt && DoubleJudgmentScorer.validOdds($0.european) }.min { $0.capturedAt < $1.capturedAt }
                if let firstObserved, quote.capturedAt.timeIntervalSince(firstObserved.capturedAt) >= 45,
                   let initialOdds = HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: firstObserved.european, handicap: handicap),
                   let p0 = AutomaticDoubleSelector.probabilities(odds: initialOdds, calibrated: true) {
                    for i in 0..<3 { adjustment[i] += max(-0.025, min(0.025, (base[i]-p0[i])*0.20)) }
                }
                if let a = asianSample?.openingAsian, let b = asianSample?.asian {
                    let delta = max(-0.02, min(0.02, -(b.line-a.line)*0.03))
                    adjustment[0] += delta; adjustment[2] -= delta
                    if abs(a.line-b.line) < 0.0001 {
                        func home(_ p: DoubleAsianPoint) -> Double { let x=1/(1+p.homeWater), y=1/(1+p.awayWater); return x/(x+y) }
                        let water = max(-0.01, min(0.01, (home(b)-home(a))*0.20))
                        adjustment[0] += water; adjustment[2] -= water
                    }
                }
            }
            let score = base.indices.map { max(0.001, base[$0]+max(-0.04,min(0.04,adjustment[$0]))) }
            let options = [[2,3],[2,4],[3,4]].map { pair -> (MarketRecordLeg, Double) in
                let kept = [3,1,0].filter { pair.contains(logic.value(for: $0)) }
                let value = [3,1,0].indices.filter { kept.contains([3,1,0][$0]) }.reduce(0) { $0+score[$1] } / score.reduce(0,+)
                return (MarketRecordLeg(number: row.number, handicap: handicap, mappedPair: pair, retained: kept,
                    evidenceAt: max(quote.capturedAt, asianSample?.capturedAt ?? .distantPast)), value)
            }
            scored.append(options.sorted { abs($0.1-$1.1)>1e-15 ? $0.1>$1.1 : $0.0.mappedPair.lexicographicallyPrecedes($1.0.mappedPair) }.first!)
        }
        let legs = scored.sorted { abs($0.1-$1.1)>1e-15 ? $0.1>$1.1 : $0.0.number<$1.0.number }.prefix(2).map(\.0)
        let validRegistration = candidate.map { c in
            c.fixtures == identities && c.cutoff == cutoff && c.registeredAt <= now
                && legs.allSatisfy { $0.evidenceAt >= c.registeredAt }
        } ?? false
        let unstarted = six.allSatisfy { $0.status.contains("未") && $0.homeScore == nil && $0.awayScore == nil }
        let kind = beforeLock && unstarted && completeEvidence && validRegistration
            ? (candidate!.exploratory || candidate!.priorObservedSamples == true ? "exploratory" : "prospective") : "archiveReference"
        return MarketRecordRecommendation(issue: six[0].issue, first: first, madeAt: now, cutoff: cutoff,
            fixtures: identities, legs: legs, kind: kind)
    }
}

struct MarketRecordStatistics: Sendable {
    var registered = 0, settled = 0, hits = 0, firstHits = 0, secondHits = 0, pending = 0, unavailable = 0
    var rate: Double? { settled == 0 ? nil : Double(hits)/Double(settled) }
    static func calculate(_ archive: MarketRecordsArchive, year: Int) -> Self {
        var result = Self()
        let records = Dictionary(archive.records.map { ($0.id, $0) }, uniquingKeysWith: { a,_ in a })
        let candidates = archive.candidates.filter { $0.issue.hasPrefix(String(year % 100)) && !$0.exploratory }
        result.registered = candidates.count
        for candidate in candidates {
            if candidate.priorObservedSamples == true { result.unavailable += 1; continue }
            guard let prediction = archive.recommendations.first(where: { $0.id == candidate.key && $0.kind == "prospective" }),
                  prediction.madeAt >= candidate.registeredAt, prediction.madeAt < candidate.cutoff,
                  prediction.cutoff == candidate.cutoff, prediction.fixtures == candidate.fixtures else { result.unavailable += 1; continue }
            var outcomes: [Int:Int] = [:]
            for f in candidate.fixtures {
                if let row = records["\(candidate.issue):\(f.number):\(f.fixtureID)"], row.isFinal,
                   let home=row.homeScore, let away=row.awayScore {
                    let delta=home+f.handicap-away; outcomes[f.number] = delta>0 ? 3 : delta==0 ? 1 : 0
                }
            }
            guard outcomes.count == 6 else { result.pending += 1; continue }
            guard prediction.legs.count==2,Set(prediction.legs.map(\.number)).count==2,
                  prediction.legs.allSatisfy({ outcomes[$0.number] != nil }) else { result.unavailable += 1; continue }
            let hits=prediction.legs.map { $0.retained.contains(outcomes[$0.number]!) }
            result.settled += 1; result.firstHits += hits[0] ? 1:0; result.secondHits += hits[1] ? 1:0
            result.hits += hits.allSatisfy { $0 } ? 1:0
        }
        return result
    }
}

enum MarketRecordsClient {
    static func download(_ url: URL) async throws -> Data {
        var request=URLRequest(url:url); request.timeoutInterval=20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36",forHTTPHeaderField:"User-Agent")
        request.setValue("https://live.500.com/",forHTTPHeaderField:"Referer")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let response=response as? HTTPURLResponse,(200...299).contains(response.statusCode) else { throw GoalModelError.invalidResponse }
        return data
    }
    static func metadata(html: String, issue: String) throws -> [MarketMatchRecord] {
        try FiveHundredBeijingSingleClient.parseScoreboard(html:html,issue:issue,requiringExplicitStatus:true).compactMap { match in
            guard let number=Int(match.matchNumber) else { return nil }
            return MarketMatchRecord(issue:issue,number:number,fixtureID:match.fixtureID,league:match.league,
                home:match.homeTeam,away:match.awayTeam,kickoff:DoubleMarketDataClient.kickoff(issue:issue,matchTime:match.matchTime),
                handicap:match.handicap,status:match.status,homeScore:match.homeScore,awayScore:match.awayScore)
        }
    }
    static func europeanQuotes(html: String) throws -> [String:[Double]] {
        let regex=try NSRegularExpression(pattern:#"(?is)var\s+liveOddsList\s*=\s*(\{.*?\})\s*;"#)
        guard let match=regex.firstMatch(in:html,range:NSRange(html.startIndex...,in:html)),
              let range=Range(match.range(at:1),in:html), let data=String(html[range]).data(using:.utf8),
              let entries=try JSONSerialization.jsonObject(with:data) as? [String:[String:Any]] else { throw GoalModelError.invalidResponse }
        var result:[String:[Double]]=[:]
        for (fid,entry) in entries {
            guard let raw=entry["293"] as? [Any] else { continue }
            let quote=raw.compactMap { Double(String(describing:$0)) }
            if DoubleJudgmentScorer.validOdds(quote) { result[fid]=quote }
        }
        return result
    }
    /// cid=293 on odds.php silently falls back to Bet365. Only its verified
    /// Macau channel (5) is used here; Euro quotes come from liveOddsList[293].
    static func macau(fixtureID:String) async throws -> DoubleBookQuote {
        guard fixtureID.allSatisfy(\.isNumber), !fixtureID.isEmpty else { throw GoalModelError.invalidResponse }
        let data=try await download(URL(string:"https://live.500.com/json/odds.php?fid=\(fixtureID)&cid=5")!)
        return try DoubleMarketDataClient.parseQuote(data:data,companyID:5)
    }
}
