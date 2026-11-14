import XCTest
@testable import SequenceFilterTool

final class SequenceFilterEngineTests: XCTestCase {
    private func finalResultFixture() throws -> FilterConfig {
        let original = try calibratedDoubleConfig(enabled: false)
        return try FilterConfig.parse(FilterInputDefaults.removingLiveDoubleRestrictions(from: original.normalizedInput))
    }

    private func finalFixtureResult(_ config: FilterConfig, captureQueryStages: Bool = false) -> FilterResult {
        SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeSPs: Array(repeating: [3,3,3], count: 6), captureQueryStages: captureQueryStages)
    }

    private func sixPrefixes(_ result: FilterResult) -> Set<[Int]> {
        Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) })
    }

    func testMatchNumberReplacementPreservesOrderAndRejectsConflictsAtomically() throws {
        let selected = ["1","2","3","4","5","6","200"]
        XCTAssertEqual(try MatchNumberReplacement.replacing(selected, from: "3", to: "20"), ["1","2","20","4","5","6","200"])
        XCTAssertEqual(try MatchNumberReplacement.replacing(selected, from: "200", to: "201"), ["1","2","3","4","5","6","201"])
        XCTAssertEqual(try MatchNumberReplacement.replacing(selected, from: " 01 ", to: "020"), ["20","2","3","4","5","6","200"])
        for pair in [("3","2"),("3","3"),("0","20"),("3","2.5"),("99","20"),("3","-2")] {
            XCTAssertThrowsError(try MatchNumberReplacement.replacing(selected, from: pair.0, to: pair.1))
        }
        XCTAssertEqual(selected, ["1","2","3","4","5","6","200"])
    }

    func testAutomaticFinalCutResultMatchesItsRequestAfterFreezingAndPickerRefresh() throws {
        var request = try finalResultFixture()
        request.automaticFinalOutcomeExclusions = true
        request.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 1), .init(slot: 2, position: 2, outcome: 1)]
        var odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        odds[0] = [1,100,2]; odds[5] = [2,3,50]
        let result = SequenceFilterEngine.calculate(request, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        XCTAssertNotEqual(request.normalizedInput, result.config.normalizedInput)
        XCTAssertTrue(result.matchesGenerationRequest(request))
        request.finalOutcomeExclusions = result.config.finalOutcomeExclusions
        XCTAssertTrue(result.matchesGenerationRequest(request))
        XCTAssertFalse(result.config.automaticFinalOutcomeExclusions)
        XCTAssertEqual(result.queryAttribution(for: [3,3,3,3,3,3]), .hit)
        request.automaticFinalOutcomeExclusions = false // A deliberate manual edit is a new request.
        XCTAssertFalse(result.matchesGenerationRequest(request))
        request.automaticFinalOutcomeExclusions = true
        request.finalOutcomeExclusions.removeLast()
        XCTAssertFalse(result.matchesGenerationRequest(request))
        XCTAssertFalse(result.matchesGenerationRequest(nil))
    }

    func testGenerationRequestSignatureRejectsRealChangesAndPreservesManualValues() throws {
        var request = try finalResultFixture()
        request.automaticFinalOutcomeExclusions = true
        request.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 1), .init(slot: 2, position: 2, outcome: 1)]
        let result = finalFixtureResult(request)
        var fields = request.normalizedInput.components(separatedBy: "|")
        fields[0] = (["1000"] + request.matchNumbers.dropFirst()).joined(separator: ",")
        var changed = try FilterConfig.parse(fields.joined(separator: "|"))
        XCTAssertFalse(result.matchesGenerationRequest(changed))
        changed = request; changed.six250ScoreUpper = 9.5
        XCTAssertFalse(result.matchesGenerationRequest(changed))
        changed = request; changed.finalResultInverted = true
        XCTAssertFalse(result.matchesGenerationRequest(changed))
        changed = request; changed.historicalOutcomeWindows = [100]; changed.historicalOutcomeBeforeIssue = "26092"
        XCTAssertFalse(result.matchesGenerationRequest(changed))
        var manual = try finalResultFixture()
        manual.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 1)]
        let manualResult = finalFixtureResult(manual)
        XCTAssertTrue(manualResult.matchesGenerationRequest(manual))
        manual.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 0)]
        XCTAssertFalse(manualResult.matchesGenerationRequest(manual))
    }

    func testAutomaticFinalCutsChooseTwoDistinctLowProbabilityOutcomes() throws {
        var odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        odds[0] = [1,100,2]; odds[5] = [2,3,50]
        let r = try XCTUnwrap(FinalOutcomeCutRecommender.recommend(odds: odds))
        XCTAssertEqual(r.rules, [.init(slot: 1, position: 1, outcome: 1), .init(slot: 2, position: 6, outcome: 0)])
        XCTAssertGreaterThan(r.estimatedCoverage, 0.95)
        odds[0] = [3,3,3]; odds[2] = [100,1,2]
        XCTAssertEqual(FinalOutcomeCutRecommender.recommend(odds: odds)?.rules[0], .init(slot: 1, position: 3, outcome: 3))
        XCTAssertNil(FinalOutcomeCutRecommender.recommend(odds: []))
        odds[0] = [0,1,2]
        XCTAssertNil(FinalOutcomeCutRecommender.recommend(odds: odds))
    }

    func testAutomaticFinalCutsFreezeActualRulesAndRespectSwitches() throws {
        var config = try finalResultFixture()
        config.automaticFinalOutcomeExclusions = true
        config.finalOutcomeExclusions = [.init(slot: 1, position: 2, outcome: 1), .init(slot: 2, position: 3, outcome: 1)]
        var odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        odds[0] = [1,100,2]; odds[5] = [2,3,50]
        let r = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        XCTAssertEqual(r.finalBetCount, 324)
        XCTAssertFalse(r.config.automaticFinalOutcomeExclusions)
        XCTAssertEqual(r.config.finalOutcomeExclusions, [.init(slot: 1, position: 1, outcome: 1), .init(slot: 2, position: 6, outcome: 0)])
        XCTAssertTrue(r.uniqueExpandedBets.allSatisfy { $0[0] != 1 && $0[5] != 0 })
        let frozen = try FilterConfig.parse(r.config.normalizedInput)
        XCTAssertEqual(sixPrefixes(finalFixtureResult(frozen)), sixPrefixes(r))
        config.finalOutcomeExclusions.removeFirst()
        let single = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(single.finalBetCount, 486)
        XCTAssertEqual(single.config.finalOutcomeExclusions, [.init(slot: 2, position: 6, outcome: 0)])
        config.automaticFinalOutcomeExclusions = false
        XCTAssertEqual(finalFixtureResult(config).config.finalOutcomeExclusions, config.finalOutcomeExclusions)
    }

    func testAutomaticFinalCutsMissingOddsStopInsteadOfUsingStaleValues() throws {
        var config = try finalResultFixture()
        config.automaticFinalOutcomeExclusions = true
        config.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 1)]
        config.finalResultInverted = true
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(result.finalBetCount, 0)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.maximum105FailureMessage?.contains("自动推荐独立剔除缺少") == true)
        XCTAssertTrue(result.config.automaticFinalOutcomeExclusions)
        XCTAssertEqual(result.statistics.afterProbabilitySelection, 0)
    }

    func testAutomaticFinalCutsProtocolAndManualSelectionProtection() throws {
        let base = try finalResultFixture().normalizedInput
        let input = FilterConfig.appendingFinalResultFilters(to: base, values: ["automaticFinalOutcomeExclusions":"1", "finalOutcomeExclusion1Enabled":"1", "finalOutcomeExclusion1Position":"1", "finalOutcomeExclusion1Outcome":"1"])
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.automaticFinalOutcomeExclusions)
        XCTAssertTrue(config.requiresSPData)
        var fiveMetrics = config
        fiveMetrics.calculationMatchCount = 5
        XCTAssertEqual(fiveMetrics.requiredCustomOddsMatchCount, 6)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterConfig.appendingFinalResultFilters(to: input, values: [:]), base)
        XCTAssertFalse(FinalOutcomeCutRecommender.shouldApply(enabled: true, selectionKey: "26112|1,2,3,4,5,6", manualSelectionKey: "26112|1,2,3,4,5,6"))
        XCTAssertTrue(FinalOutcomeCutRecommender.shouldApply(enabled: true, selectionKey: "26112|2,3,4,5,6,7", manualSelectionKey: "26112|1,2,3,4,5,6"))
        XCTAssertFalse(FinalOutcomeCutRecommender.shouldApply(enabled: false, selectionKey: "new", manualSelectionKey: "old"))
    }

    func testAutomaticFinalCutsBacktestResolvesEachGroupsOwnOdds() async throws {
        var config = try finalResultFixture()
        config.automaticFinalOutcomeExclusions = true
        config.finalOutcomeExclusions = [.init(slot: 1, position: 1, outcome: 3), .init(slot: 2, position: 2, outcome: 1)]
        var first = Array(repeating: [3.0,3.0,3.0], count: 6)
        first[0] = [1,100,2]; first[5] = [2,3,50]
        var second = Array(repeating: [3.0,3.0,3.0], count: 6)
        second[1] = [100,1,2]; second[4] = [2,50,3]
        let data = ConditionEffectDataset(version: 1, source: "automatic-cut-per-group", groups: [
            .init(year: 2025, issue: "25011", start: 2, logic: "AAAAAA", outcomes: [3,3,3,3,3,3], odds: first),
            .init(year: 2026, issue: "26011", start: 2, logic: "AAAAAA", outcomes: [3,1,3,3,3,3], odds: second)])
        let summary = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(summary.combined, ConditionPassRateYear(groups: 2, hits: 2))
    }

    func testHistoryWindowProtocolPersistenceAndValidation() throws {
        let base = try finalResultFixture().normalizedInput
        let values = ["historyWindow50Enabled":"1", "historyWindow150Enabled":"1", "historyWindowBeforeIssue":"26092"]
        let input = FilterConfig.appendingFinalResultFilters(to: base, values: values)
        let config = try FilterConfig.parse(input)
        XCTAssertEqual(config.historicalOutcomeWindows, [50,150])
        XCTAssertEqual(config.historicalOutcomeBeforeIssue, "26092")
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["historyWindow150Enabled"], "1")
        XCTAssertEqual(FilterInputDefaults.values(from: config)["historyWindow200Enabled"], "0")
        XCTAssertEqual(FilterConfig.appendingFinalResultFilters(to: input, values: [:]), base)
        for text in ["RESULTWINDOWS=20|RESULTBEFORE=26092", "RESULTWINDOWS=50,50|RESULTBEFORE=26092", "RESULTWINDOWS=50|RESULTBEFORE=11-05", "RESULTWINDOWS=50"] {
            XCTAssertThrowsError(try FilterConfig.parse(base + "|" + text))
        }
    }

    func testHistoryWindowStrictPriorIssueAndGroupCount() {
        let rows = (0..<250).map { HistoricalOutcomeWindows.Row(issue: $0 < 210 ? "25001" : "25002", start: $0, outcomes: [3,1,0,3,1,0]) }
        let prior = HistoricalOutcomeWindows.priorRows(before: "25002", limit: 150, archive: rows)
        XCTAssertEqual(prior.count, 150)
        XCTAssertEqual(prior.first?.start, 60)
        XCTAssertTrue(prior.allSatisfy { $0.issue == "25001" })
        XCTAssertEqual(Set(prior.map(\.outcomes)).count, 1)
        XCTAssertTrue(HistoricalOutcomeWindows.priorRows(before: "25001", limit: 200, archive: rows).isEmpty)
        XCTAssertTrue(HistoricalOutcomeWindows.priorRows(before: "", limit: 200, archive: rows).isEmpty)
    }

    func testAllFourHistoryWindowsMatchExactSetAndExports() throws {
        let base = try finalResultFixture()
        let universe = sixPrefixes(finalFixtureResult(base))
        XCTAssertFalse(HistoricalOutcomeWindows.rows.isEmpty)
        for n in [50,100,150,200] {
            var config = base
            config.historicalOutcomeWindows = [n]
            config.historicalOutcomeBeforeIssue = "26092"
            let rows = HistoricalOutcomeWindows.priorRows(before: "26092", limit: n)
            XCTAssertEqual(rows.count, n)
            let expected = universe.subtracting(Set(rows.map(\.outcomes)))
            let result = finalFixtureResult(config, captureQueryStages: true)
            XCTAssertEqual(sixPrefixes(result), expected)
            XCTAssertEqual(result.finalBetCount, expected.count)
            XCTAssertEqual(result.statistics.afterProbabilitySelection, expected.count)
            XCTAssertEqual(Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) }), expected)
            config.historicalOutcomeWindows = [50,100,150,200].filter { $0 <= n }
            XCTAssertEqual(sixPrefixes(finalFixtureResult(config)), expected)
        }
    }

    func testHistoryExclusionsRunAfterInverseAndIndependentCuts() throws {
        var config = try finalResultFixture()
        config.outcomeConditions = [.losses: 2...2]
        config.finalResultInverted = true
        config.finalOutcomeExclusions = [FinalOutcomeExclusion(slot: 1, position: 2, outcome: 1)]
        let base = finalFixtureResult(config)
        config.historicalOutcomeWindows = [200]
        config.historicalOutcomeBeforeIssue = "26092"
        let expected = sixPrefixes(base).subtracting(Set(HistoricalOutcomeWindows.priorRows(before: "26092", limit: 200).map(\.outcomes)))
        let result = finalFixtureResult(config, captureQueryStages: true)
        XCTAssertEqual(sixPrefixes(result), expected)
        XCTAssertTrue(result.finalResultFilterNotes.last!.contains("历史彩果去重"))
        XCTAssertEqual(result.config.historicalOutcomeWindows, [200])
    }

    func testHistoryBacktestUsesSampleIssueInsteadOfCurrentIssue() async throws {
        var config = try finalResultFixture()
        config.historicalOutcomeWindows = [200]
        config.historicalOutcomeBeforeIssue = "26092"
        let old = Set(HistoricalOutcomeWindows.priorRows(before: "25011", limit: 200).map(\.outcomes))
        let later = Set(HistoricalOutcomeWindows.priorRows(before: "26092", limit: 200).map(\.outcomes))
        let target = try XCTUnwrap(later.subtracting(old).sorted { $0.lexicographicallyPrecedes($1) }.first)
        let data = ConditionEffectDataset(version: 1, source: "history-cutoff-test", groups: [
            ConditionEffectGroup(year: 2025, issue: "25011", start: 2, logic: "AAAAAA", outcomes: target,
                odds: Array(repeating: [3,3,3], count: 6)),
            ConditionEffectGroup(year: 2026, issue: "26011", start: 2, logic: "AAAAAA", outcomes: [3,3,3,3,3,3],
                odds: Array(repeating: [3,3,3], count: 6))])
        let result = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(result.years[2025], ConditionPassRateYear(groups: 1, hits: 1))
        XCTAssertEqual(result.combined.groups, 2)
    }

    func testResultInverseIsExact729ComplementOfCombinedFinalOutput() throws {
        var config = try finalResultFixture()
        config.outcomeConditions = [.losses: 2...2]
        let base = finalFixtureResult(config)
        XCTAssertEqual(base.finalBetCount, 240)
        config.finalResultInverted = true
        let inverse = finalFixtureResult(config, captureQueryStages: true)
        XCTAssertEqual(inverse.finalBetCount, 489)
        XCTAssertTrue(sixPrefixes(base).isDisjoint(with: sixPrefixes(inverse)))
        XCTAssertEqual(sixPrefixes(base).union(sixPrefixes(inverse)).count, 729)
        XCTAssertEqual(inverse.records.count, 489)
        XCTAssertEqual(inverse.statistics.afterProbabilitySelection, 489)
        XCTAssertTrue(inverse.finalResultFilterNotes.joined().contains("729注减去原条件结果240注"))
        XCTAssertEqual(inverse.queryAttribution(for: [3,3,3,3,3,3]), .hit)
        guard case .excluded(let stage) = inverse.queryAttribution(for: [0,0,1,1,1,1]) else {
            return XCTFail("An original passing bet must be removed by inversion")
        }
        XCTAssertTrue(stage.contains("反选"))
        XCTAssertTrue(inverse.queryConditionFailureReasons(for: [0,0,1,1,1,1]).isEmpty)
        let saved = Set(sixPrefixes(inverse).map { $0.map(String.init).joined() })
        XCTAssertTrue(SequenceFilterEngine.missedOutcomeAnalysis(outcomes: [0,0,1,1,1,1],
            config: inverse.config, savedKeptOutcomes: saved).contains("未在当时反选"))
        XCTAssertTrue(SequenceFilterEngine.missedOutcomeAnalysis(outcomes: [3,3,3,3,3,3],
            config: inverse.config, savedKeptOutcomes: saved).contains("最终TXT中"))
    }

    func testIndependentCutsRunAfterInverseAndNeverReturnThroughRecovery() throws {
        var config = try finalResultFixture()
        config.outcomeConditions = [.losses: 2...2, .nonDrawRun: 2...6]
        config.svip10Frozen160Enabled = false
        config.six250RelationshipEnabled = false
        config.txtCompactEnabled = true
        config.maximumTXTAdditionalBets = 20
        let base = finalFixtureResult(config)
        let baseSet = sixPrefixes(base)
        config.finalResultInverted = true
        config.finalOutcomeExclusions = [FinalOutcomeExclusion(slot: 1, position: 1, outcome: 1),
            FinalOutcomeExclusion(slot: 2, position: 4, outcome: 0)]
        let result = finalFixtureResult(config, captureQueryStages: true)
        let universe = finalFixtureResult(try finalResultFixture())
        let expected = sixPrefixes(universe).subtracting(baseSet).filter { $0[0] != 1 && $0[3] != 0 }
        XCTAssertEqual(sixPrefixes(result), Set(expected))
        XCTAssertTrue(result.exportCompressedRecords.allSatisfy { !$0.options[0].contains(1) && !$0.options[3].contains(0) })
        XCTAssertEqual(result.uniqueExpandedBets.count, result.rawExpandedBetCount)
        XCTAssertTrue(result.queryStages.suffix(3).map(\.name)[0].hasPrefix("反选"))
        XCTAssertTrue(result.queryStages.last!.name.contains("独立剔除2"))
    }

    func testIndependentCutsWorkWithPackageOffAndSamePosition() throws {
        var config = try finalResultFixture()
        config.conditionPackageEnabled = false
        config.finalOutcomeExclusions = [FinalOutcomeExclusion(slot: 1, position: 2, outcome: 3),
            FinalOutcomeExclusion(slot: 2, position: 5, outcome: 1)]
        XCTAssertEqual(finalFixtureResult(config).finalBetCount, 324)
        config.finalOutcomeExclusions[1] = FinalOutcomeExclusion(slot: 2, position: 2, outcome: 0)
        let samePosition = finalFixtureResult(config)
        XCTAssertEqual(samePosition.finalBetCount, 243)
        XCTAssertTrue(samePosition.uniqueExpandedBets.allSatisfy { $0[1] == 1 })
        config.finalOutcomeExclusions[1] = FinalOutcomeExclusion(slot: 2, position: 2, outcome: 3)
        XCTAssertEqual(finalFixtureResult(config).finalBetCount, 486)
        config.finalOutcomeExclusions = []
        XCTAssertEqual(finalFixtureResult(config).finalBetCount, 729)
    }

    func testResultInverseEmptyAndFullAndSeventhExportAmounts() throws {
        var config = try finalResultFixture()
        config.finalResultInverted = true
        XCTAssertEqual(finalFixtureResult(config).finalBetCount, 0)
        config.outcomeConditions = [.draws: 6...6, .losses: 6...6]
        XCTAssertEqual(finalFixtureResult(config).finalBetCount, 729)
        var fields = config.normalizedInput.components(separatedBy: "|")
        fields[0] = "235,236,237,238,239,240"
        fields = fields.map { $0 == "7:3" ? "399:10" : $0 }
        config = try FilterConfig.parse(fields.joined(separator: "|"))
        config.finalOutcomeExclusions = [FinalOutcomeExclusion(slot: 1, position: 6, outcome: 0)]
        let result = finalFixtureResult(config)
        XCTAssertEqual(sixPrefixes(result).count, 486)
        XCTAssertEqual(result.finalBetCount, 972)
        XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[6] }), [1,0])
        let export = try TXTBetExport(matchNumbers: config.matchNumbers + config.extraMatches.map(\.matchNumber),
            bets: result.uniqueExpandedBets, multiplier: 3)
        XCTAssertEqual(export.betCount(.total), 972)
        XCTAssertEqual(export.amount(.total), 5832)
        XCTAssertEqual(export.betCount(.e) + export.betCount(.f), 972)
        XCTAssertEqual(export.amount(.e) + export.amount(.f), 5832)
        XCTAssertTrue(export.text(issue: "26111", part: .total).contains("总金额：5832元"))
    }

    func testFinalResultSettingsRoundTripSwitchesAndInvalidInput() throws {
        let base = try finalResultFixture().normalizedInput
        var values = ["finalResultInverted":"1", "finalOutcomeExclusion1Enabled":"0",
            "finalOutcomeExclusion1Position":"3", "finalOutcomeExclusion1Outcome":"0",
            "finalOutcomeExclusion2Enabled":"1", "finalOutcomeExclusion2Position":"6", "finalOutcomeExclusion2Outcome":"1"]
        let input = FilterConfig.appendingFinalResultFilters(to: base, values: values)
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.finalResultInverted)
        XCTAssertEqual(config.finalOutcomeExclusions, [FinalOutcomeExclusion(slot: 2, position: 6, outcome: 1)])
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["finalOutcomeExclusion2Outcome"], "1")
        XCTAssertEqual(FilterInputDefaults.currentDirectionalDoubleSettings(from: values), values)
        values["finalResultInverted"] = "0"; values["finalOutcomeExclusion2Enabled"] = "0"
        XCTAssertEqual(FilterConfig.appendingFinalResultFilters(to: input, values: values), base)
        XCTAssertFalse(try FilterConfig.parse(base).hasFinalResultFilters)
        for token in ["RESULTCUT1=0,3", "RESULTCUT1=7,3", "RESULTCUT1=1,4", "RESULTCUT1=1,31", "RESULTINVERT=2", "RESULTCUT1=1,3|RESULTCUT1=2,1"] {
            let invalid = base.replacingOccurrences(of: "|7:3|", with: "|" + token + "|7:3|")
            XCTAssertThrowsError(try FilterConfig.parse(invalid), token)
        }
    }

    func testCompleteBacktestIncludesInverseAndIndependentCuts() async throws {
        var config = try finalResultFixture()
        config.outcomeConditions = [.losses: 2...2]
        config.finalResultInverted = true
        config.finalOutcomeExclusions = [FinalOutcomeExclusion(slot: 2, position: 6, outcome: 0)]
        let groups = [([3,3,3,3,3,3], 2), ([0,0,1,1,1,1], 8), ([3,3,3,3,3,0], 14)]
        let data = ConditionEffectDataset(version: 1, source: "post-filter-fixture", groups: [2025,2026].flatMap { year in
            groups.map { outcomes, start in
                ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: start,
                    logic: "AAAAAA", outcomes: outcomes, odds: Array(repeating: [3,3,3], count: 6))
            }
        })
        let summary = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(summary.combined, ConditionPassRateYear(groups: 6, hits: 2))
        XCTAssertEqual(summary.years[2025], ConditionPassRateYear(groups: 3, hits: 1))
        XCTAssertEqual(summary.years[2026], ConditionPassRateYear(groups: 3, hits: 1))
    }

    func testLiveNoDoubleRestrictionsRestoreThirdOutcomeToActualTXT() throws {
        var old = try calibratedDoubleConfig(enabled: false)
        old.svip10AdditionalFilters.automaticDoublePairEnabled = true
        old.svip10AdditionalFilters.automaticDoubleCount = 1
        old.highPass98FiftyGroupEnabled = true
        old.highPass50DoubleEnabled = true
        let odds = [[1.5, 30.0, 1.6]] + Array(repeating: [3.0, 3.0, 3.0], count: 5)
        let liveInput = FilterInputDefaults.removingLiveDoubleRestrictions(from: old.normalizedInput)
        let live = try FilterConfig.parse(liveInput)
        XCTAssertFalse(live.svip10AdditionalFilters.firstDoubleActive)
        XCTAssertFalse(live.svip10AdditionalFilters.secondDoubleActive)
        XCTAssertFalse(live.svip10AdditionalFilters.usesAutomaticDoubleSelection)
        XCTAssertFalse(live.highPass50DoubleActive)
        let generated = SequenceFilterEngine.calculate(live, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(generated.finalBetCount, 729)
        XCTAssertTrue(generated.exportCompressedRecords.contains { $0.options[0].contains(1) })
        for index in 0..<6 { XCTAssertEqual(Set(generated.uniqueExpandedBets.map { $0[index] }), [3,1,0]) }
        XCTAssertEqual(FilterInputDefaults.removingLiveDoubleRestrictions(from: liveInput), liveInput)
        // The archived protocol is still an explicit single-double rule.
        XCTAssertTrue(try FilterConfig.parse(old.normalizedInput).svip10AdditionalFilters.firstDoubleActive)
        XCTAssertTrue(try FilterConfig.parse(old.normalizedInput).highPass50DoubleActive)
    }

    func testNoDoubleStartupMigrationPreservesIndependentNoFourAndScore() throws {
        for noFour in ["0", "1"] {
            let old = ["selectedConditionVersionID":"svip10-frozen-160", "svip10NoFourEnabled":noFour,
                "noFourPositionFilterEnabled":"1", "noFourPositionInput":"3", "svip10ScoreRangeInput":"5.5-7",
                "svip10AutomaticDoublePairEnabled":"1", "svip10SecondDoubleLowestProbabilityEnabled":"1",
                "svip10ADDoublesWithinSixEnabled":"1", "svip10FixedFrontTwoDoublesEnabled":"1",
                "svvvHighPass50DoubleEnabled":"1", "OC_NDRUN":"2-6", "svip10SixMatchMinimumOddsProductInput":"250"]
            let live = FilterInputDefaults.currentDirectionalDoubleSettings(from: old)
            for key in ["svip10AutomaticDoublePairEnabled", "svip10SecondDoubleLowestProbabilityEnabled",
                        "svip10ADDoublesWithinSixEnabled", "svip10FixedFrontTwoDoublesEnabled", "svvvHighPass50DoubleEnabled"] {
                XCTAssertEqual(live[key], "0", key)
            }
            for key in ["svip10NoFourEnabled", "noFourPositionFilterEnabled", "noFourPositionInput", "svip10ScoreRangeInput",
                        "OC_NDRUN", "svip10SixMatchMinimumOddsProductInput"] { XCTAssertEqual(live[key], old[key], key) }
            XCTAssertEqual(FilterInputDefaults.currentDirectionalDoubleSettings(from: live), live)
            var other = old; other["selectedConditionVersionID"] = "svip11-breakpoint-selection"
            XCTAssertEqual(FilterInputDefaults.currentDirectionalDoubleSettings(from: other), other)
        }
    }

    func testNoDoubleHistoricalRateUsesAllThreeOutcomesAndNoDoubleStatistics() async throws {
        var old = try calibratedDoubleConfig(enabled: false)
        old.svip10AdditionalFilters.automaticDoublePairEnabled = true
        old.svip10AdditionalFilters.automaticDoubleCount = 1
        let archive = ConditionEffectDataset(version: 1, source: "no-double", groups: [2025,2026].map { year in
            ConditionEffectGroup(year: year, issue: year == 2025 ? "25011":"26011", start: 2, logic: "BCBCBC",
                outcomes: [1,3,3,3,3,3], odds: [[1.5,30,1.6]] + Array(repeating:[3,3,3],count:5))
        })
        let live = FilterInputDefaults.removingLiveDoubleRestrictions(from: old.normalizedInput)
        let full = try await CompleteConditionBacktest.run(input: live, dataset: archive)
        XCTAssertEqual(full.combined, ConditionPassRateYear(groups: 2, hits: 2))
        let standalone = try await ConditionEffectAnalysis.passRate(input: live, dataset: archive)
        XCTAssertEqual(standalone.twoDoubleCombined.groups, 0)
        XCTAssertFalse(ConditionEffectAnalysis.rules(for: try FilterConfig.parse(live)).contains { ["extra.13","extra.14"].contains($0.id) })
    }

    private func explicitShareFixture() throws -> SharedTXTQueryRecord {
        let numbers = ["235","236","237","238","239","240","399"]
        let bets = [[3,3,3,3,3,3,0],[1,3,3,3,3,3,0],[0,3,3,3,3,3,0]]
        let export = try TXTBetExport(matchNumbers: numbers, bets: bets, multiplier: 3)
        return SharedTXTQueryRecord(id: UUID(), sharedAt: Date(), issue:"26111", filename:"generated.txt",
            txtContent:export.text(issue:"26111",part:.total), normalizedInput:"frozen-input", matchNumbers:numbers,
            betOutcomes:bets, finalBetCount:bets.count, conditionSignature:"old-signature",lastCheckedAt:nil,
            observedOutcomes:nil, observedHandicaps:nil, verificationMessage:nil, isFinalResult:false,
            isHit:nil,prizeAmount:nil,prizeSPValues:nil)
    }

    func testOnlyExplicitShareAdmitsRecordAndRepeatContentIsDeduplicated() throws {
        let source = try explicitShareFixture()
        XCTAssertTrue(ExplicitTXTShareArchive.confirmed([source]).isEmpty)
        XCTAssertTrue(ExplicitTXTShareArchive.admitting(source, into: []).isEmpty)
        let first = try ExplicitTXTShareArchive.snapshot(source:source,text:source.txtContent!,filename:"shared.txt",now:Date(timeIntervalSince1970:100))
        let repeatShare = try ExplicitTXTShareArchive.snapshot(source:source,text:source.txtContent!,filename:"another-name.txt",now:Date(timeIntervalSince1970:200))
        let saved = ExplicitTXTShareArchive.admitting(repeatShare, into:ExplicitTXTShareArchive.admitting(first,into:[]))
        XCTAssertEqual(saved.count,1)
        XCTAssertEqual(saved.first?.explicitShareInitiatedAt, Date(timeIntervalSince1970:200))
        XCTAssertEqual(saved.first?.txtContent, source.txtContent)
        XCTAssertEqual(saved.first?.betOutcomes, source.betOutcomes)
        XCTAssertNil(source.explicitShareInitiatedAt)
    }

    func testEditedTXTShareKeepsOriginalAndFreezesActualNewContent() throws {
        let source = try explicitShareFixture()
        let original = try ExplicitTXTShareArchive.snapshot(source:source,text:source.txtContent!,filename:"total.txt")
        let edited = try TXTBetEditor.excluding(bets:source.betOutcomes,matchNumbers:source.matchNumbers,matchNumber:"235",outcome:"1")
        let export = try TXTBetExport(matchNumbers:source.matchNumbers,bets:edited.bets,multiplier:3)
        var revision = source
        // A revised source has different frozen bets, while the old record stays untouched.
        revision = SharedTXTQueryRecord(id: UUID(),sharedAt:Date(),issue:source.issue,filename:"edited.txt",
            txtContent:export.text(issue:source.issue,part:.total),normalizedInput:source.normalizedInput,
            matchNumbers:source.matchNumbers,betOutcomes:edited.bets,finalBetCount:edited.bets.count,
            conditionSignature:nil,lastCheckedAt:nil,observedOutcomes:nil,observedHandicaps:nil,
            verificationMessage:nil,isFinalResult:false,isHit:nil,prizeAmount:nil,prizeSPValues:nil,
            manualTXTExclusions:[edited.rule])
        XCTAssertEqual(ExplicitTXTShareArchive.admitting(revision,into:[original]).count,1) // editing is not sharing
        let shared = try ExplicitTXTShareArchive.snapshot(source:revision,text:revision.txtContent!,filename:revision.filename)
        let saved = ExplicitTXTShareArchive.admitting(shared,into:[original])
        XCTAssertEqual(saved.count,2)
        XCTAssertEqual(shared.finalBetCount,2)
        XCTAssertTrue(shared.txtContent!.contains("12元"))
        XCTAssertFalse(shared.betOutcomes.contains { $0[0] == 1 })
        XCTAssertEqual(original.betOutcomes.count,3)
        XCTAssertNotEqual(ExplicitTXTShareArchive.contentKey(original), ExplicitTXTShareArchive.contentKey(shared))
        let restored = try JSONDecoder().decode([SharedTXTQueryRecord].self, from:JSONEncoder().encode(saved))
        XCTAssertEqual(ExplicitTXTShareArchive.confirmed(restored).count,2)
        XCTAssertEqual(restored.map(\.txtContent),saved.map(\.txtContent))
    }

    func testSharedPartWithHiddenSeventhKeepsOnlyActuallySharedBets() throws {
        let source = try explicitShareFixture()
        let subset = Array(source.betOutcomes.prefix(1))
        let export = try TXTBetExport(matchNumbers:source.matchNumbers,displayedMatchNumbers:Array(source.matchNumbers.prefix(6)),bets:subset,multiplier:3)
        let text = export.text(issue:source.issue,part:.total)
        let shared = try ExplicitTXTShareArchive.snapshot(source:source,text:text,filename:"E.txt")
        XCTAssertEqual(shared.betOutcomes,subset)
        XCTAssertEqual(shared.finalBetCount,1)
        XCTAssertEqual(shared.displayedMatchNumbers,Array(source.matchNumbers.prefix(6)))
        XCTAssertEqual(shared.matchNumbers.count,7)
        XCTAssertEqual(shared.txtContent,text)
        XCTAssertThrowsError(try ExplicitTXTShareArchive.snapshot(source:source,text:"没有投注行",filename:"bad.txt"))
    }

    func testShareMigrationPreservesLegacyBytesAndDoesNotInventShareEvidence() throws {
        let suite = "mustwin-explicit-share-test-"+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let record = try explicitShareFixture()
        let bytes = try JSONEncoder().encode([record])
        for key in ExplicitTXTShareArchive.legacyKeys { defaults.set(bytes,forKey:key) }
        ExplicitTXTShareArchive.preserveLegacyHistoryOnce(defaults:defaults)
        let backup = try XCTUnwrap(defaults.dictionary(forKey:ExplicitTXTShareArchive.legacyBackupKey))
        for key in ExplicitTXTShareArchive.legacyKeys {
            XCTAssertEqual(backup[key] as? Data,bytes)
            XCTAssertEqual(defaults.data(forKey:key),bytes)
        }
        let decoded = try JSONDecoder().decode([SharedTXTQueryRecord].self,from:bytes)
        XCTAssertTrue(ExplicitTXTShareArchive.confirmed(decoded).isEmpty)
        defaults.set(Data("new-generated-data".utf8),forKey:ExplicitTXTShareArchive.legacyKeys[0])
        ExplicitTXTShareArchive.preserveLegacyHistoryOnce(defaults:defaults)
        XCTAssertEqual(defaults.dictionary(forKey:ExplicitTXTShareArchive.legacyBackupKey)?[ExplicitTXTShareArchive.legacyKeys[0]] as? Data,bytes)
        let shared = try ExplicitTXTShareArchive.snapshot(source:record,text:record.txtContent!,filename:record.filename)
        defaults.set(try JSONEncoder().encode([shared]),forKey:ExplicitTXTShareArchive.storageKey)
        let restarted = try JSONDecoder().decode([SharedTXTQueryRecord].self,from:try XCTUnwrap(defaults.data(forKey:ExplicitTXTShareArchive.storageKey)))
        XCTAssertEqual(ExplicitTXTShareArchive.confirmed(restarted).count,1)
    }

    private struct ConstantSampleGenerator: RandomNumberGenerator {
        let value: UInt64
        mutating func next() -> UInt64 { value }
    }

    func testSampleBatchesPartitionOnlyFirst4200ArchivedGroups() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json"))
        let archive = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
        XCTAssertEqual(archive.groups.count, 4323)
        var covered: [String] = []
        for index in 0..<14 {
            let plan = try CompleteConditionSamplePlan(totalGroupCount: archive.groups.count, batchIndex: index)
            let subset = try plan.dataset(from: archive)
            XCTAssertEqual(plan.batchNumber, index + 1)
            XCTAssertEqual(subset.groups.count, 300)
            XCTAssertEqual(plan.tailCount, 123)
            XCTAssertEqual(subset.groups.first?.issue, archive.groups[index * 300].issue)
            covered += subset.groups.map { "\($0.issue):\($0.start)" }
        }
        XCTAssertEqual(covered.count, 4200)
        XCTAssertEqual(Set(covered).count, 4200)
        XCTAssertEqual(covered, archive.groups.prefix(4200).map { "\($0.issue):\($0.start)" })
        XCTAssertTrue(Set(covered).isDisjoint(with: archive.groups.suffix(123).map { "\($0.issue):\($0.start)" }))
        XCTAssertThrowsError(try CompleteConditionSamplePlan(totalGroupCount: 4199, batchIndex: 0))
        XCTAssertThrowsError(try CompleteConditionSamplePlan(totalGroupCount: 4323, batchIndex: 14))
        XCTAssertThrowsError(try CompleteConditionSamplePlan(totalGroupCount: 4323, batchIndex: -1))
    }

    func testUniformSampleDrawCanReachEveryBatchIncludingBothEnds() throws {
        // The midpoint of each equal 1/14 interval of UInt64 should map to
        // that batch through Swift's unbiased bounded random implementation.
        for index in 0..<14 {
            var generator = ConstantSampleGenerator(value: UInt64.max / 28 * UInt64(index * 2 + 1))
            let plan = try CompleteConditionSamplePlan.draw(totalGroupCount: 4323, using: &generator)
            XCTAssertEqual(plan.batchIndex, index)
        }
    }

    func testSampleSessionFreezesDrawAndRejectsEverySupersededPublication() throws {
        var session = CompleteConditionBacktestSession()
        let original = CompleteConditionBacktestRequest(input: "conditions-A", sampled: true, redraw: 0)
        let first = session.begin(original)
        var generator = ConstantSampleGenerator(value: UInt64.max / 28)
        let plan = try session.freezeSample(totalGroupCount: 4323, using: &generator, runID: first, request: original)
        generator = ConstantSampleGenerator(value: UInt64.max)
        XCTAssertEqual(try session.freezeSample(totalGroupCount: 4323, using: &generator, runID: first, request: original), plan)
        // Foreground/resume replaces the worker, retaining the logical draw.
        let resumed = session.begin(original)
        XCTAssertFalse(session.accepts(first, request: original))
        XCTAssertEqual(try session.freezeSample(totalGroupCount: 4323, using: &generator, runID: resumed, request: original), plan)
        XCTAssertTrue(session.accepts(resumed, request: original))
        let changed = CompleteConditionBacktestRequest(input: "conditions-B", sampled: true, redraw: 0)
        let second = session.begin(changed)
        XCTAssertNil(session.sample)
        XCTAssertFalse(session.accepts(resumed, request: original)) // progress, result and error share this guard
        XCTAssertThrowsError(try session.freezeSample(totalGroupCount: 4323, using: &generator, runID: resumed, request: original))
        let replacement = try session.freezeSample(totalGroupCount: 4323, using: &generator, runID: second, request: changed)
        XCTAssertEqual(replacement.batchIndex, 13)
        let redraw = CompleteConditionBacktestRequest(input: changed.input, sampled: true, redraw: 1)
        _ = session.begin(redraw)
        XCTAssertNil(session.sample)
        XCTAssertFalse(session.accepts(second, request: changed))
    }

    private func sampleTestArchive() -> ConditionEffectDataset {
        ConditionEffectDataset(version: 1, source: "sampling-test", groups: (0..<4323).map { index in
            let year = index < 2439 ? 2025 : 2026
            return ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: index * 6 + 2,
                logic: "BCBCBC", outcomes: [3, 3, 3, 3, 3, 3],
                odds: [[1.5, 30, 1.6]] + Array(repeating: [3, 3, 3], count: 5))
        })
    }

    func testSampledFullEngineRunsOnly300AndAllowsSingleYearWithoutAD() async throws {
        actor ProgressLog {
            var points: [(Int, Int)] = []
            func record(_ done: Int, _ total: Int) { points.append((done, total)) }
            func values() -> [(Int, Int)] { points }
        }
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.automaticDoubleCount = 1
        let archive = sampleTestArchive()
        let plan = try CompleteConditionSamplePlan(totalGroupCount: archive.groups.count, batchIndex: 0)
        let log = ProgressLog()
        let summary = try await CompleteConditionBacktest.runSample(input: config.normalizedInput, archive: archive, plan: plan) {
            await log.record($0, $1)
        }
        XCTAssertEqual(summary.sample, plan)
        XCTAssertEqual(summary.combined, ConditionPassRateYear(groups: 300, hits: 300))
        XCTAssertEqual(summary.years[2025]?.groups, 300)
        XCTAssertNil(summary.years[2026])
        XCTAssertEqual(summary.excluded.values.reduce(0, +), 0)
        let progress = await log.values()
        XCTAssertEqual(progress.last?.0, 300)
        XCTAssertTrue(progress.allSatisfy { $0.1 == 300 && $0.0 <= 300 })
    }

    func testSampledFullEngineHonorsCancellationBeforeCompletingBatch() async throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.automaticDoubleCount = 1
        let input = config.normalizedInput, archive = sampleTestArchive()
        let plan = try CompleteConditionSamplePlan(totalGroupCount: archive.groups.count, batchIndex: 13)
        let work = Task {
            try await CompleteConditionBacktest.runSample(input: input, archive: archive, plan: plan) { done, total in
                XCTAssertEqual(total, 300)
                XCTAssertEqual(done, 1)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { _ = try await work.value; XCTFail("Cancelled sampling returned a result") }
        catch is CancellationError { }
    }

    func testCurrentSingleAnyDoubleHistoricalJointRateIsNotAnADReference() async throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.automaticDoubleCount = 1
        let archive = sampleTestArchive()
        let data = ConditionEffectDataset(version: 1, source: "single-any", groups: [archive.groups[0], archive.groups[3000]])
        let summary = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(summary.twoDoubleCombined, ConditionPassRateYear(groups: 2, hits: 2))
        XCTAssertTrue(summary.usesAutomaticPairs)
        XCTAssertTrue(ConditionEffectAnalysis.rules(for: config).contains { $0.title == "一场31/30/10自动双选" && $0.enabled })
    }

    func testCurrentRestoredSettingsRemoveADWithoutChangingOtherConditions() throws {
        let old = ["selectedConditionVersionID": "svip10-frozen-160", "svip10ADDoublesWithinSixEnabled": "1",
            "svip10AutomaticDoubleCount": "2", "svip10ScoreRangeInput": "5.5-6.8", "svip10NoFourEnabled": "1",
            "noFourPositionFilterEnabled": "1", "noFourPositionInput": "3", "OC_NDRUN": "2-6",
            "svip10SixMatchMinimumOddsProductInput": "250", "matchSearchStartInput": "235"]
        let updated = FilterInputDefaults.currentDirectionalDoubleSettings(from: old)
        XCTAssertEqual(updated["svip10ADDoublesWithinSixEnabled"], "0")
        XCTAssertEqual(updated["svip10AutomaticDoubleCount"], "1")
        for key in ["svip10ScoreRangeInput", "svip10NoFourEnabled", "noFourPositionFilterEnabled", "noFourPositionInput",
                    "OC_NDRUN", "svip10SixMatchMinimumOddsProductInput", "matchSearchStartInput"] {
            XCTAssertEqual(updated[key], old[key], key)
        }
        XCTAssertEqual(FilterInputDefaults.currentDirectionalDoubleSettings(from: updated), updated)
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = updated["svip10AutomaticDoublePairEnabled"] == "1"
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = updated["svip10ADDoublesWithinSixEnabled"] == "1"
        config.svip10AdditionalFilters.automaticDoubleCount = Int(updated["svip10AutomaticDoubleCount"]!)!
        var fields = config.normalizedInput.components(separatedBy: "|"); fields[1] = "BCBCBC"
        config = try FilterConfig.parse(FilterInputDefaults.removingLiveDoubleRestrictions(from: fields.joined(separator: "|")))
        let matches = abcdFillMatches("BCBCBCAD")
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: config.svip10AdditionalFilters.adDoublesWithinSixEnabled), [1,2,3,4,5,6])
        let odds = [[1.5, 30.0, 1.6]] + Array(repeating: [3.0, 3.0, 3.0], count: 5)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(result.finalBetCount, 729)
        XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[0] }), [3, 1, 0])
        XCTAssertFalse(config.svip10AdditionalFilters.usesAutomaticDoubleSelection)
    }

    func testTXTExclusionUsesActualMatchNumberAndKeepsOtherBetsExactly() throws {
        let numbers = ["235", "261", "12", "7", "90", "6", "399"]
        let bets = [[3,1,0,3,1,0,3], [1,3,0,3,1,0,3], [0,1,0,3,1,0,1], [3,0,0,3,1,0,1]]
        let revision = try TXTBetEditor.excluding(bets: bets + [bets[0]], matchNumbers: numbers,
            matchNumber: " 0261 ", outcome: "1")
        XCTAssertEqual(revision.bets, [bets[1], bets[3]])
        XCTAssertEqual(revision.removedCount, 2)
        XCTAssertEqual(revision.rule, TXTOutcomeExclusion(matchNumber: "261", outcome: 1))
        XCTAssertEqual(Set(revision.bets), Set(bets.filter { $0[1] != 1 }))
    }

    func testTXTExclusionRebuildsTotalEFAndAmountsFromExactRemainingBets() throws {
        let numbers = ["235", "236", "237", "238", "239", "240", "399"]
        let bets = (0..<7).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
            .filter { $0.reduce(0,+) % 3 == 0 }
        let revision = try TXTBetEditor.excluding(bets: bets, matchNumbers: numbers, matchNumber: "237", outcome: "0")
        let export = try TXTBetExport(matchNumbers: numbers, bets: revision.bets, multiplier: 3)
        let e = export.selectedRows(.e).flatMap { expandedOutcomes($0.options) }
        let f = export.selectedRows(.f).flatMap { expandedOutcomes($0.options) }
        XCTAssertEqual(Set(e + f), Set(revision.bets))
        XCTAssertEqual(e.count + f.count, revision.bets.count)
        XCTAssertTrue(Set(e).isDisjoint(with: Set(f)))
        XCTAssertLessThanOrEqual(export.selectedRows(.e).count, 15)
        XCTAssertEqual(export.selectedRows(.e).count + export.selectedRows(.f).count, export.rows.count)
        XCTAssertEqual(export.betCount(.total), export.betCount(.e) + export.betCount(.f))
        XCTAssertEqual(export.amount(.total), revision.bets.count * 2 * 3)
        XCTAssertEqual(export.amount(.total), export.amount(.e) + export.amount(.f))
        for part in TXTBetExportPart.allCases {
            let text = export.text(issue: "26111", part: part, notes: [revision.rule.summary])
            XCTAssertTrue(text.contains("最终：\(export.betCount(part))注"))
            XCTAssertTrue(text.contains("总金额：\(export.amount(part))元"))
            let parsed = try SharedTXTImportParser.parse(text)
            XCTAssertEqual(parsed.betOutcomes.count, export.betCount(part))
            XCTAssertTrue(parsed.betOutcomes.allSatisfy { $0[2] != 0 })
        }
    }

    func testTXTExclusionSupportsRepeatedEditsSixMatchesHiddenSeventhAndZeroBets() throws {
        let numbers = ["11", "12", "13", "14", "15", "16", "99"]
        let bets = [[3,1,0,3,1,0,3], [3,1,0,3,1,0,1], [0,1,0,3,1,0,3]]
        let first = try TXTBetEditor.excluding(bets: bets, matchNumbers: numbers, matchNumber: "99", outcome: "1")
        let hidden = try TXTBetExport(matchNumbers: numbers, displayedMatchNumbers: Array(numbers.prefix(6)), bets: first.bets, multiplier: 5)
        XCTAssertEqual(hidden.betCount(.total), 2)
        XCTAssertEqual(hidden.amount(.total), 20)
        XCTAssertFalse(hidden.text(issue: "26111", part: .total).contains("99→"))
        let second = try TXTBetEditor.excluding(bets: first.bets, matchNumbers: numbers, matchNumber: "11", outcome: "3")
        XCTAssertEqual(second.bets, [bets[2]])
        let third = try TXTBetEditor.excluding(bets: second.bets, matchNumbers: numbers, matchNumber: "11", outcome: "0")
        let empty = try TXTBetExport(matchNumbers: numbers, bets: third.bets, multiplier: 5)
        for part in TXTBetExportPart.allCases {
            XCTAssertEqual(empty.betCount(part), 0)
            XCTAssertEqual(empty.amount(part), 0)
            XCTAssertTrue(empty.text(issue: "26111", part: part).contains("最终：0注"))
        }
        let six = try TXTBetExport(matchNumbers: Array(numbers.prefix(6)), bets: [[3,1,0,3,1,0], [0,1,0,3,1,0]], multiplier: 1)
        XCTAssertEqual(Set(six.rows.flatMap { expandedOutcomes($0.options) }), Set(six.bets))
        XCTAssertEqual(try SharedTXTImportParser.parse(six.text(issue: "26111", part: .total)).betOutcomes.count, 2)
    }

    func testTXTExclusionRejectsUnknownMatchesAndInvalidValuesWithoutChangingSource() throws {
        let numbers = ["1", "2", "3", "4", "5", "6"]
        let bets = [[3,1,0,3,1,0]]
        for (number, value, expected) in [("7", "1", TXTBetEditingError.matchNotFound),
            ("", "1", .invalidMatchNumber), ("1,2", "1", .invalidMatchNumber),
            ("1", "31", .invalidOutcome), ("1", "2", .invalidOutcome), ("1", "", .invalidOutcome)] {
            XCTAssertThrowsError(try TXTBetEditor.excluding(bets: bets, matchNumbers: numbers, matchNumber: number, outcome: value)) {
                XCTAssertEqual($0 as? TXTBetEditingError, expected)
            }
        }
        XCTAssertEqual(bets, [[3,1,0,3,1,0]])
        let unchanged = try TXTBetEditor.excluding(bets: bets, matchNumbers: numbers, matchNumber: "1", outcome: "1")
        XCTAssertEqual(unchanged.removedCount, 0)
        XCTAssertEqual(unchanged.bets, bets)
        XCTAssertThrowsError(try TXTBetExport(matchNumbers: numbers, bets: [[3,1]], multiplier: 1))
        XCTAssertThrowsError(try TXTBetExport(matchNumbers: numbers, bets: bets, multiplier: 0))
    }

    func testTXTExclusionUpdatesGeneratedCountAndFrozenQueryWithoutRestoringRemovedValues() throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.automaticDoubleCount = 1
        let odds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        let original = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        let numbers = config.matchNumbers + config.extraMatches.map(\.matchNumber)
        let target = try XCTUnwrap(original.uniqueExpandedBets.first)
        let updated = try original.excludingTXTOutcome(matchNumber: numbers[2], outcome: String(target[2]))
        let expected = Set(original.uniqueExpandedBets.filter { $0[2] != target[2] })
        XCTAssertEqual(Set(updated.uniqueExpandedBets), expected)
        XCTAssertEqual(updated.finalBetCount, expected.count)
        XCTAssertLessThan(updated.finalBetCount, original.finalBetCount)
        XCTAssertNotEqual(updated.generationID, original.generationID)
        XCTAssertEqual(updated.config, original.config)
        XCTAssertEqual(updated.queryCustomOdds, original.queryCustomOdds)
        if case .excluded(let reason) = updated.queryAttribution(for: Array(target.prefix(6))) {
            XCTAssertTrue(reason.contains("手动剔除"))
        } else { XCTFail("A removed target must be attributed to the manual edit") }
        XCTAssertTrue(updated.shareText.contains("手动剔除"))
    }

    func testSVVVP11PreservesSessionAndKeepsOldPackageSeparate() throws {
        let old = ["svvvSelected": "1", "selectedConditionVersionID": "svip10-frozen-160",
            "matchSearchStartInput": "249", "match1Input": "249", "fixedFullMatchInput": "254",
            "singleMatchInput": "399", "singleOutcomeInput": "0", "betMultiplierInput": "2",
            "logicInput": "DBCCCB", "beijingSingleIssueInput": "26111",
            "svip10ScoreRangeInput": "5-8", "svip10SixMatchMinimumOddsProductEnabled": "1",
            "OCON_NDRUN": "1", "OC_NDRUN": "3-6"]
        let original = old
        let values = try SVVVP11ConditionPackage.recommendedValues(onto: old)
        for key in ["matchSearchStartInput", "match1Input", "fixedFullMatchInput", "singleMatchInput",
                    "singleOutcomeInput", "betMultiplierInput", "logicInput", "beijingSingleIssueInput"] {
            XCTAssertEqual(values[key], old[key], key)
        }
        XCTAssertEqual(old, original)
        XCTAssertEqual(values["svvvSelected"], "0")
        XCTAssertEqual(values["svvvp11Selected"], "1")
        XCTAssertEqual(values["svip10ScoreRangeInput"], SVVVP11ConditionPackage.scoreRange)
        XCTAssertEqual(values["svip10Maximum105Enabled"], "0")
        XCTAssertEqual(values["svip10ADDoubleCountWithinSix"], "1")
        XCTAssertEqual(values["svip10ADDoublesWithinSixEnabled"], "0")
        XCTAssertEqual(values["svip10AutomaticDoubleCount"], "1")
        XCTAssertEqual(values["svip10SixMatchMinimumOddsProductEnabled"], "1")
        XCTAssertEqual(values["svip10SixMatchMinimumOddsProductInput"].flatMap(Double.init), 350)
        XCTAssertEqual(values["OCON_NDRUN"], "1")
        XCTAssertEqual(values["OC_NDRUN"], "2-6")
        let restored = SVVVConditionPackage.restoring(SVVVConditionPackage.snapshot(from: old), onto: values)
        XCTAssertEqual(restored["svip10ScoreRangeInput"], "5-8")
        XCTAssertEqual(restored["OC_NDRUN"], "3-6")
        XCTAssertNil(SVVVConditionPackage.snapshot(from: values)["svvvp11Selected"])
        var changedSession = values
        changedSession["matchSearchStartInput"] = "333"
        changedSession["singleMatchInput"] = "444"
        let previous = SVVVP11ConditionPackage.restoringPrevious(old, onto: changedSession)
        XCTAssertEqual(previous["svip10ScoreRangeInput"], "5-8")
        XCTAssertEqual(previous["OC_NDRUN"], "3-6")
        XCTAssertEqual(previous["svvvSelected"], "1")
        XCTAssertEqual(previous["svvvp11Selected"], "0")
        XCTAssertEqual(previous["matchSearchStartInput"], "333")
        XCTAssertEqual(previous["singleMatchInput"], "444")
    }

    func testSVVVP11ProductionUsesRecommendedIntersectionWithoutBetCap() throws {
        let template = try SVVVP11ConditionPackage.recommendedConfig()
        var fields = template.normalizedInput.components(separatedBy: "|")
        fields[1] = "BCADBC"
        let config = try FilterConfig.parse(fields.joined(separator: "|"))
        XCTAssertEqual(config, try FilterConfig.parse(config.normalizedInput))
        let odds = [[1.7, 3.6, 4.8], [3.8, 3.3, 1.9], [1.9, 3.2, 4.1],
                    [4.0, 3.4, 1.8], [2.3, 3.1, 3.0], [2.8, 3.0, 2.4]]
        let choices = config.automaticDoubleChoices(in: odds)
        XCTAssertEqual(choices.count, 1)
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in
            rows.flatMap { row in [3, 1, 0].map { row + [$0] } }
        }
        let expected = Set(patterns.filter { row in
            choices.allSatisfy { $0.choice.retainedOutcomes.contains(row[$0.position - 1]) }
                && (SequenceFilterEngine.six250Score(outcomes: row, customOdds: odds).map {
                    $0 >= config.six250ScoreLower && $0 <= config.six250ScoreUpper
                } ?? false)
                && (0..<6).reduce(1.0, { product, i in
                    product * odds[i][row[i] == 3 ? 0 : (row[i] == 1 ? 1 : 2)]
                }) >= SVVVP11ConditionPackage.minimumOddsProduct
                && SVVVP11ConditionPackage.nonDrawRunRange.contains(OutcomeCondition.nonDrawRun.value(in: row))
        }.map { $0 + [3] })
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
        XCTAssertNil(result.maximum105InputBetCount)
        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertNotEqual(result.finalBetCount, 105)
        XCTAssertLessThan(result.finalBetCount, 486)
    }

    func testSingleAnyDoubleAllowsAllThreePairsAtEveryPositionWithoutAD() throws {
        for position in 0..<6 {
            for (special, retained) in [([1.5, 1.6, 30.0], [3, 1]), ([1.5, 30.0, 1.6], [3, 0]), ([30.0, 1.5, 1.6], [1, 0])] {
                var config = try calibratedDoubleConfig(enabled: false)
                config.svip10AdditionalFilters.automaticDoublePairEnabled = true
                config.svip10AdditionalFilters.automaticDoubleCount = 1
                var fields = config.normalizedInput.components(separatedBy: "|"); fields[1] = "BCBCBC"
                config = try FilterConfig.parse(fields.joined(separator: "|"))
                var odds = Array(repeating: [3.0, 3.0, 3.0], count: 6); odds[position] = special
                let choice = try XCTUnwrap(config.automaticDoubleChoices(in: odds).first)
                XCTAssertEqual(config.automaticDoubleChoices(in: odds).count, 1)
                XCTAssertEqual(choice.position, position + 1)
                XCTAssertEqual(choice.choice.retainedOutcomes, retained)
                let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
                XCTAssertEqual(result.finalBetCount, 486)
                for index in 0..<6 {
                    XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[index] }), Set(index == position ? retained : [3, 1, 0]))
                }
            }
        }
    }

    func testSingleAnyDoubleProtocolAndHardLayoutSurviveRecovery() throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.automaticDoubleCount = 1
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let legacy = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("S10DBLCOUNT=") }.joined(separator: "|")
        XCTAssertEqual(try FilterConfig.parse(legacy).svip10AdditionalFilters.automaticDoubleCount, 2)
        for invalid in ["0", "3", "abc"] {
            XCTAssertThrowsError(try FilterConfig.parse(legacy + "|S10DBLCOUNT=" + invalid))
        }
        XCTAssertThrowsError(try FilterConfig.parse(config.normalizedInput + "|S10DBLCOUNT=1"))
        let odds = [[1.5, 30.0, 1.6]] + Array(repeating: [3.0, 3.0, 3.0], count: 5)
        for tolerance in [false, true] {
            config.allConditionsToleranceEnabled = tolerance; config.allConditionsToleranceRange = 0...20
            config.txtCompactEnabled = true; config.maximumTXTAdditionalBets = 50
            config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled = true
            let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
            XCTAssertEqual(result.finalBetCount, 486)
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { $0[0] != 1 })
        }
    }

    func testSingleAnyDoubleKeepsInitialBCSixAndSeparateForecast() throws {
        let matches = abcdFillMatches("BCBCBCAD")
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: false)
        XCTAssertEqual(numbers, [1, 2, 3, 4, 5, 6])
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, matchNumbers: numbers, automaticDoubleCount: 1)?.automaticDoubleSelection)
        XCTAssertEqual(selection.choices.count, 1)
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, automaticDoubleCount: 1))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.singleAnyWithinSixModelVersion)
        XCTAssertEqual(forecast.selected.count, 1)
        XCTAssertTrue(forecast.groupKey.contains("single-any-within-six"))
        XCTAssertNotEqual(forecast.cohortKey, DoubleForwardForecast.cohort(calibrated: false, factors: "", version: DoubleForwardForecast.singleADWithinSixModelVersion))
    }

    func testSingleADDoubleUsesAnyPositionAndLeavesFiveFullBags() throws {
        for position in 0..<6 {
            for letter in [Character("A"), Character("D")] {
                var letters = Array("BCBCBC"); letters[position] = letter
                let mappings = letters.map { LogicMapping(rawValue: String($0).lowercased())! }
                let odds = mappings.map { $0.values.map(Double.init) }
                var fields = try calibratedDoubleConfig().normalizedInput.components(separatedBy: "|")
                fields[1] = String(letters)
                var config = try FilterConfig.parse(fields.joined(separator: "|"))
                config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
                config.svip10AdditionalFilters.adDoubleCountWithinSix = 1
                XCTAssertFalse(config.svip10AdditionalFilters.secondDoubleActive)
                XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
                let choices = config.automaticDoubleChoices(in: odds)
                XCTAssertEqual(choices.count, 1); XCTAssertEqual(choices.first?.position, position + 1)
                let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
                XCTAssertEqual(result.finalBetCount, 486)
                XCTAssertNil(result.maximum105InputBetCount)
                for index in 0..<6 {
                    let expected = index == position ? (letter == "A" ? [3, 1] : [1, 0]) : [3, 1, 0]
                    XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[index] }), Set(expected))
                }
            }
        }
    }

    func testSingleADFillNeedsOnlyOneAndExcludesManualSeventh() throws {
        for (letters, excluded, expected) in [
            ("BCBCBDAD", Set<Int>(), [1, 2, 3, 4, 5, 6]),
            ("BCBCBCAD", Set<Int>(), [1, 2, 3, 4, 5, 7]),
            ("BCBCBCAD", Set([7]), [1, 2, 3, 4, 5, 8])
        ] {
            let matches = abcdFillMatches(letters)
            let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
                excludingMatchNumbers: excluded, requireAllABCD: false, requireFrontTwoAD: false,
                adDoublesWithinSix: true, adDoubleCountWithinSix: 1)
            XCTAssertEqual(numbers, expected)
            let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                matches: matches, excludingMatchNumbers: excluded, calibrated: true, matchNumbers: numbers,
                adDoublesWithinSix: true, adDoubleCountWithinSix: 1)?.automaticDoubleSelection)
            XCTAssertEqual(selection.choices.count, 1)
        }
        XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("BCBCBC"), requireAllABCD: false, requireFrontTwoAD: false,
            adDoublesWithinSix: true, adDoubleCountWithinSix: 1))
    }

    func testSingleADProtocolRecoveryAndForecastStaySeparateFromLegacyPair() throws {
        let matches = abcdFillMatches("BCABCD")
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, adDoublesWithinSix: true, adDoubleCountWithinSix: 1)?.automaticDoubleSelection)
        var fields = try calibratedDoubleConfig(enabled: false).normalizedInput.components(separatedBy: "|")
        fields[1] = selection.matches.map { $0.logic.displayName }.joined()
        var config = try FilterConfig.parse(fields.joined(separator: "|"))
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
        config.svip10AdditionalFilters.adDoubleCountWithinSix = 1
        let old = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("S10ADCOUNT=") }.joined(separator: "|")
        let legacy = try FilterConfig.parse(old)
        XCTAssertEqual(legacy.svip10AdditionalFilters.adDoubleCountWithinSix, 2)
        XCTAssertEqual(legacy.automaticDoubleChoices(in: selection.matches.map(\.odds)).count, 2)
        for tolerance in [false, true] {
            config.allConditionsToleranceEnabled = tolerance; config.allConditionsToleranceRange = 0...20
            config.txtCompactEnabled = true; config.maximumTXTAdditionalBets = 50
            config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled = true
            let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: selection.matches.map(\.odds))
            XCTAssertEqual(result.finalBetCount, 486)
            let choice = try XCTUnwrap(config.automaticDoubleChoices(in: selection.matches.map(\.odds)).first)
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { choice.choice.retainedOutcomes.contains($0[choice.position - 1]) })
        }
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, adDoublesWithinSix: true, adDoubleCountWithinSix: 1))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.singleADWithinSixModelVersion)
        XCTAssertEqual(forecast.selected.count, 1)
        XCTAssertNotEqual(forecast.version, DoubleForwardForecast.adWithinSixFillModelVersion)
    }

    func testCompleteHistoricalRateBackfillsADAndExcludesMissingPaths() async throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
        func groups(secondStart: Int) -> [ConditionEffectGroup] {
            [2025, 2026].flatMap { year in
                [ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: 2,
                    logic: "BBBBBB", outcomes: [3, 3, 3, 3, 3, 3], odds: Array(repeating: LogicMapping.b.values.map(Double.init), count: 6)),
                 ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: secondStart,
                    logic: "ADBBBB", outcomes: [3, 0, 3, 3, 3, 3], odds: [LogicMapping.a, .d, .b, .b, .b, .b].map { $0.values.map(Double.init) })]
            }
        }
        let complete = try await CompleteConditionBacktest.run(input: config.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups(secondStart: 8)))
        XCTAssertEqual(complete.combined, ConditionPassRateYear(groups: 4, hits: 4))
        XCTAssertEqual(complete.excluded.values.reduce(0, +), 0)
        let missing = try await CompleteConditionBacktest.run(input: config.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups(secondStart: 14)))
        XCTAssertEqual(missing.combined, ConditionPassRateYear(groups: 2, hits: 2))
        XCTAssertEqual(missing.excluded, [2025: 1, 2026: 1])
    }

    func testCompleteHistoricalRateKeepsCurrentRangesAndSwitches() async throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
        config.outcomeConditions = [.draws: 0...0]
        let odds = [LogicMapping.a, .d, .b, .b, .b, .b].map { $0.values.map(Double.init) }
        let actual = [3, 0, 3, 0, 1, 1]
        let data = ConditionEffectDataset(version: 1, source: "test", groups: [2025, 2026].map { year in
            ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: 2,
                logic: "ADBBBB", outcomes: actual, odds: odds)
        })
        let strict = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(strict.combined, ConditionPassRateYear(groups: 2, hits: 0))
        config.outcomeConditions = [.draws: 0...6]
        let relaxed = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(relaxed.combined, ConditionPassRateYear(groups: 2, hits: 2))
        XCTAssertNotEqual(relaxed.input, strict.input)
        config.outcomeConditions = [.draws: 0...0]
        config.conditionPackageEnabled = false
        let disabled = try await CompleteConditionBacktest.run(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(disabled.combined, ConditionPassRateYear(groups: 2, hits: 2))
    }

    func testADWithinSixSupportsEveryPositionAndPairWithoutReorderingSix() throws {
        for first in 0..<5 {
            for second in (first + 1)..<6 {
                for pair in ["AA", "AD", "DA", "DD"] {
                    var letters = Array("BCBCBC")
                    letters[first] = Array(pair)[0]; letters[second] = Array(pair)[1]
                    let matches = abcdFillMatches(String(letters) + "ADAD")
                    let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
                        matches: matches, requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true)
                    XCTAssertEqual(numbers, [1, 2, 3, 4, 5, 6])
                    for calibrated in [false, true] {
                        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                            matches: Array(matches.reversed()), calibrated: calibrated, matchNumbers: numbers,
                            adDoublesWithinSix: true)?.automaticDoubleSelection)
                        XCTAssertEqual(Set(selection.choices.map(\.number)), [first + 1, second + 1])
                        for choice in selection.choices {
                            XCTAssertEqual(choice.retainedOutcomes, letters[choice.number - 1] == "A" ? [3, 1] : [1, 0])
                        }
                    }
                    if first == 2 && second == 5 {
                        let recommendation = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                            matches: matches, calibrated: true, matchNumbers: numbers, adDoublesWithinSix: true))
                        var fields = try calibratedDoubleConfig().normalizedInput.components(separatedBy: "|")
                        fields[1] = recommendation.logic
                        var config = try FilterConfig.parse(fields.joined(separator: "|"))
                        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
                        let odds = try XCTUnwrap(recommendation.automaticDoubleSelection?.matches.map(\.odds))
                        let result = SequenceFilterEngine.calculate(config, previousContext: nil,
                            currentOutcomeSPs: odds, captureQueryStages: true)
                        XCTAssertEqual(result.finalBetCount, 324)
                        XCTAssertNil(result.maximum105InputBetCount)
                        for index in 0..<6 {
                            let expected = index == first || index == second
                                ? (letters[index] == "A" ? [3, 1] : [1, 0]) : [3, 1, 0]
                            XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[index] }), Set(expected))
                        }
                        XCTAssertTrue(result.queryStages.contains { $0.name.contains("位置不固定") })
                    }
                }
            }
        }
    }

    func testADWithinSixSelectsOnlyTwoAndFillsMissingADByReplacingBC() throws {
        let candidates: [AutomaticDoubleCandidate] = [
            .init(number: 1, logic: .b, odds: [1.01, 1.02, 1000]),
            .init(number: 2, logic: .a, odds: [2, 3, 4]),
            .init(number: 3, logic: .c, odds: [1000, 1.01, 1.02]),
            .init(number: 4, logic: .d, odds: [12, 5, 1.3]),
            .init(number: 5, logic: .a, odds: [1.3, 5, 10]),
            .init(number: 6, logic: .d, odds: [4, 3, 2])]
        let selection = try XCTUnwrap(AutomaticDoubleSelector.recommend(numbers: Array(1...6),
            candidates: candidates, calibrated: false, adDoublesWithinSix: true))
        XCTAssertEqual(Set(selection.choices.map(\.number)), [4, 5])
        XCTAssertEqual(selection.matches.map(\.number), Array(1...6))
        for (letters, expected) in [("BCBCBCADAD", [1, 2, 3, 4, 7, 8]), ("BCABBCADAD", [1, 2, 3, 4, 5, 7])] {
            let matches = abcdFillMatches(letters)
            let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
                requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true)
            XCTAssertEqual(numbers, expected)
            XCTAssertEqual(numbers, try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
                matches: Array(matches.reversed()), requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true))
            XCTAssertNil(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                matches: matches, calibrated: false, matchNumbers: Array(1...6), adDoublesWithinSix: true))
            let filled = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                matches: matches, calibrated: false, matchNumbers: numbers, adDoublesWithinSix: true)?.automaticDoubleSelection)
            XCTAssertEqual(filled.matches.map(\.number), expected)
            XCTAssertEqual(filled.choices.count, 2)
            XCTAssertTrue(filled.choices.allSatisfy { choice in
                let match = filled.matches.first { $0.number == choice.number }!
                return choice.retainedOutcomes == (match.logic == .a ? [3, 1] : [1, 0])
            })
        }
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: abcdFillMatches("BCAABBD"),
            excludingMatchNumbers: [4], requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true)
        XCTAssertEqual(numbers, [1, 2, 3, 5, 6, 7])
    }

    func testADFillPreservesStartAndExistingADExcludesSeventhAndStopsWhenExhausted() throws {
        for pair in ["AA", "AD", "DA", "DD"] {
            let matches = abcdFillMatches("BCBCBC" + pair + "AD")
            let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
                requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true)
            XCTAssertEqual(numbers, [1, 2, 3, 4, 7, 8])
        }
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("BCBCBAD"), requireAllABCD: false, requireFrontTwoAD: false,
            adDoublesWithinSix: true), [1, 2, 3, 4, 6, 7])
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("ABBCBCBD"), requireAllABCD: false, requireFrontTwoAD: false,
            adDoublesWithinSix: true), [1, 2, 3, 4, 5, 8])
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("BCBCBCADAD"), excludingMatchNumbers: [7], requireAllABCD: false,
            requireFrontTwoAD: false, adDoublesWithinSix: true), [1, 2, 3, 4, 8, 9])
        for letters in ["BCBCBCBCBC", "BCABBCBCBC", "BCAD"] {
            XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
                matches: abcdFillMatches(letters), requireAllABCD: false, requireFrontTwoAD: false,
                adDoublesWithinSix: true)) { error in
                    XCTAssertTrue(error.localizedDescription.contains("仍找不到至少含两场A/D"))
                }
        }
    }

    func testADWithinSixProtocolAndForecastKeepLegacySeparate() throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let old = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("S10ADWITHIN6=") }.joined(separator: "|")
        XCTAssertFalse(try FilterConfig.parse(old).svip10AdditionalFilters.adDoublesWithinSixEnabled)
        let matches = abcdFillMatches("BCABCD")
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, adDoublesWithinSix: true)?.automaticDoubleSelection)
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, adDoublesWithinSix: true))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.adWithinSixFillModelVersion)
        XCTAssertEqual(Set(forecast.selected.map(\.number)), [3, 6])
        XCTAssertNotEqual(forecast.cohortKey, DoubleForwardForecast.cohort(calibrated: false, factors: "", version: DoubleForwardForecast.frontTwoADTailModelVersion))
        var archived = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(forecast)) as? [String: Any])
        archived["version"] = DoubleForwardForecast.adWithinSixModelVersion
        let previous = try JSONDecoder().decode(DoubleForwardForecast.self, from: JSONSerialization.data(withJSONObject: archived))
        XCTAssertTrue(previous.isValid)
        XCTAssertNotEqual(previous.cohortKey, forecast.cohortKey)
        XCTAssertNotEqual(previous.groupKey, forecast.groupKey)

        let fillMatches = abcdFillMatches("BCBCBCAD")
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: fillMatches,
            requireAllABCD: false, requireFrontTwoAD: false, adDoublesWithinSix: true)
        let fillSelection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: fillMatches, calibrated: false, matchNumbers: numbers, adDoublesWithinSix: true)?.automaticDoubleSelection)
        let fillForecast = try XCTUnwrap(DoubleForwardForecast.make(selection: fillSelection, matches: fillMatches,
            calibrated: false, factors: [], now: now, adDoublesWithinSix: true))
        XCTAssertTrue(fillForecast.isValid)
        XCTAssertEqual(fillForecast.fixtures.map(\.number), [1, 2, 3, 4, 7, 8])
    }

    func testADWithinSixRecoveryAndToleranceCannotRestoreRemovedDirections() throws {
        let matches = abcdFillMatches("BCABCD")
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, adDoublesWithinSix: true)?.automaticDoubleSelection)
        var fields = try calibratedDoubleConfig(enabled: false).normalizedInput.components(separatedBy: "|")
        fields[1] = "BCABCD"
        var config = try FilterConfig.parse(fields.joined(separator: "|"))
        config.svip10AdditionalFilters.adDoublesWithinSixEnabled = true
        config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled = true
        config.outcomeConditions = [.wins: 0...0]
        for tolerance in [false, true] {
            config.allConditionsToleranceEnabled = tolerance
            config.allConditionsToleranceRange = 0...20
            let result = SequenceFilterEngine.calculate(config, previousContext: nil,
                currentOutcomeSPs: selection.matches.map(\.odds))
            XCTAssertFalse(result.uniqueExpandedBets.isEmpty)
            XCTAssertLessThanOrEqual(result.finalBetCount, 324)
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
                selection.choices.allSatisfy { $0.retainedOutcomes.contains(bet[$0.number - 1]) }
            })
        }
    }

    func testFrontADTailAllowsEveryADPairAndKeepsTailConsecutive() throws {
        for pair in ["AA", "AD", "DA", "DD"] {
            let matches = abcdFillMatches("BC" + pair + "BCBCBC")
            let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
                requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true, calibrated: true)
            XCTAssertEqual(numbers, [3, 4, 5, 6, 7, 8])
            XCTAssertEqual(numbers, try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
                matches: Array(matches.reversed()), requireAllABCD: false, requireFrontTwoAD: true,
                fixedFrontTwoDoubles: true, calibrated: false))
            let recommendation = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
                matches: matches, calibrated: true, matchNumbers: numbers, fixedFrontTwo: true, requireFrontTwoAD: true))
            XCTAssertEqual(String(recommendation.logic.prefix(2)), pair)
            let expected = pair.map { $0 == "A" ? [3, 1] : [1, 0] }
            XCTAssertEqual(recommendation.automaticDoubleSelection?.choices.map(\.retainedOutcomes), expected)
            var fields = try calibratedDoubleConfig().normalizedInput.components(separatedBy: "|")
            fields[0] = numbers.map(String.init).joined(separator: ",")
            fields[1] = recommendation.logic
            fields = fields.map { $0 == "7:3" ? "99:3" : $0 }
            var config = try FilterConfig.parse(fields.joined(separator: "|"))
            config.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled = true
            config.svip10AdditionalFilters.frontTwoADEnabled = true
            let odds = try XCTUnwrap(recommendation.automaticDoubleSelection?.matches.map(\.odds))
            let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
            XCTAssertEqual(result.finalBetCount, 324)
            for index in 0..<2 { XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[index] }), Set(expected[index])) }
        }
    }

    func testFrontADTailSkipsBCAndSeventhWithoutRequiringAllABCD() throws {
        let matches = abcdFillMatches("BCABBDBBBBBB")
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true)
        XCTAssertEqual(numbers, [3, 6, 7, 8, 9, 10])
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: abcdFillMatches("BCABADBBBBBB"),
            excludingMatchNumbers: [3], requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true),
            [5, 6, 7, 8, 9, 10])
        XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 4, matches: matches,
            requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true))
        XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("BCBCBCBCBCBC"), requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true))
        let noCompleteTail = matches.filter { $0.matchNumber != "9" }
        XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: noCompleteTail,
            requireAllABCD: false, requireFrontTwoAD: true, fixedFrontTwoDoubles: true))
        for letter in [LogicMapping.b, .c] {
            XCTAssertNil(AutomaticDoubleSelector.frontADChoice(.init(number: 1, logic: letter, odds: [1.5, 100, 2]), calibrated: false))
        }
    }

    func testFrontADTailUsesSeparateForwardCohortAndKeepsLegacyReadable() throws {
        let matches = abcdFillMatches("BCADBBBBBB")
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, matchNumbers: [3, 4, 5, 6, 7, 8], fixedFrontTwo: true,
            requireFrontTwoAD: true)?.automaticDoubleSelection)
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, frontTwoADSelection: true, fixedFrontTwoDoubles: true))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.frontTwoADTailModelVersion)
        XCTAssertNotEqual(forecast.version, DoubleForwardForecast.fixedFrontTwoModelVersion)
        var archived = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(forecast)) as? [String: Any])
        archived["version"] = DoubleForwardForecast.fixedFrontTwoModelVersion
        let old = try JSONDecoder().decode(DoubleForwardForecast.self, from: JSONSerialization.data(withJSONObject: archived))
        XCTAssertTrue(old.isValid)
        XCTAssertNotEqual(old.cohortKey, forecast.cohortKey)
    }

    func testDirectionalDoubleAlwaysUses31Or10AndKeepsFirstTwoPositions() throws {
        for logic in LogicMapping.allCases {
            for (odds, expected) in [([2.0, 100, 3], [3, 1]), ([3.0, 100, 2], [1, 0])] {
                let choice = try XCTUnwrap(AutomaticDoubleSelector.directionalChoice(
                    .init(number: 10, logic: logic, odds: odds), calibrated: false))
                XCTAssertEqual(choice.retainedOutcomes, expected)
                XCTAssertEqual(Set(choice.mappedPair), Set(expected.map { logic.value(for: $0) }))
            }
        }
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled = true
        let choices = config.automaticDoubleChoices(in: calibrationFixtureOdds)
        XCTAssertEqual(choices.map(\.position), [1, 2])
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertEqual(result.finalBetCount, 324)
        for choice in choices {
            XCTAssertTrue(choice.choice.retainedOutcomes.contains(1))
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { choice.choice.retainedOutcomes.contains($0[choice.position - 1]) })
        }
        for index in 2..<6 { XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[index] }), Set([3, 1, 0])) }
        config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled = true
        config.outcomeConditions = [.wins: 0...0]
        let recovered = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertFalse(recovered.uniqueExpandedBets.isEmpty)
        XCTAssertTrue(recovered.uniqueExpandedBets.allSatisfy { bet in
            choices.allSatisfy { $0.choice.retainedOutcomes.contains(bet[$0.position - 1]) }
        })
    }

    func testDirectionalDoublesChangeIndependentlyWithCurrentOddsAcrossAllFourPairings() throws {
        let winOdds = [1.5, 5.0, 8.0], lossOdds = [8.0, 5.0, 1.5]
        let pairings = [([3, 1], [3, 1]), ([3, 1], [1, 0]), ([1, 0], [1, 0]), ([1, 0], [3, 1])]
        for calibrated in [false, true] {
            var config = try calibratedDoubleConfig(enabled: calibrated)
            config.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled = true
            config.svip10AdditionalFilters.automaticDoublePairEnabled = true
            for (first, second) in pairings {
                let odds = [first == [3, 1] ? winOdds : lossOdds,
                            second == [3, 1] ? winOdds : lossOdds]
                    + Array(repeating: [2.0, 100.0, 3.0], count: 4)
                let expected = [first, second]
                let recommendation = try XCTUnwrap(AutomaticDoubleSelector.recommend(numbers: Array(1...6),
                    candidates: (0..<6).map { .init(number: $0 + 1, logic: config.logic[$0], odds: odds[$0]) },
                    calibrated: calibrated, fixedFrontTwo: true))
                XCTAssertEqual(recommendation.choices.map(\.retainedOutcomes), expected)
                let choices = config.automaticDoubleChoices(in: odds)
                XCTAssertEqual(choices.map(\.position), [1, 2])
                XCTAssertEqual(choices.map { $0.choice.retainedOutcomes }, expected)
                let generated = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
                XCTAssertEqual(generated.finalBetCount, 324)
                for index in 0..<2 {
                    XCTAssertEqual(Set(generated.uniqueExpandedBets.map { $0[index] }), Set(expected[index]))
                }
                // 模拟同一场次用上次生成配置再次生成，已解析的旧方向不能盖过新赔率。
                config = generated.config
            }
        }
    }

    private func directionalTestMatches() -> [BeijingSingleMatch] {
        [1, 2, 4, 6, 7, 8, 9, 10, 11, 12].map { number in
            let odds = number == 1 ? [10.0, 1.1, 10] : (number == 2 ? [1.2, 10, 20] : (number == 4 ? [20.0, 10, 1.2] : [2, 3, 4]))
            return BeijingSingleMatch(issue: "26108", matchNumber: String(number), fixtureID: "direction-\(number)",
                league: "test", matchTime: "10-29 21:00", status: "未", homeTeam: "主", awayTeam: "客",
                handicap: 0, referenceSP: [], marketOdds: odds)
        }
    }

    func testDirectionalSelectionRejectsDrawLedFixtureAndKeepsTailConsecutiveWithoutABCD() throws {
        let matches = directionalTestMatches()
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            excludingMatchNumbers: [7], requireAllABCD: false, requireFrontTwoAD: false,
            fixedFrontTwoDoubles: true, calibrated: false)
        XCTAssertEqual(numbers, [2, 4, 8, 9, 10, 11])
        XCTAssertEqual(numbers, try VIP6MatchRecommender.directionalMatchNumbers(firstMatchNumber: 1,
            matches: Array(matches.reversed()), excluding: [7], calibrated: false))
        let recommendation = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, excludingMatchNumbers: [7], calibrated: false, matchNumbers: numbers, fixedFrontTwo: true))
        XCTAssertLessThan(Set(recommendation.logic).count, 4)
        XCTAssertEqual(recommendation.automaticDoubleSelection?.choices.map(\.retainedOutcomes), [[3, 1], [1, 0]])
        XCTAssertThrowsError(try VIP6MatchRecommender.directionalMatchNumbers(firstMatchNumber: 1,
            matches: Array(matches.prefix(3)), calibrated: false))
    }

    func testDirectionalSelectionUsesEarliestEligiblePairForEachStartInsteadOfGlobalRanking() throws {
        let matches = (1...16).map { number in
            let odds: [Double] = number == 1 ? [10, 1.1, 10]
                : (number == 8 ? [1.2, 10, 20] : (number == 9 ? [20, 10, 1.2] : [2, 3, 4]))
            return BeijingSingleMatch(issue: "26108", matchNumber: String(number), fixtureID: "sequential-\(number)",
                league: "test", matchTime: "10-29 21:00", status: "未", homeTeam: "主", awayTeam: "客",
                handicap: 0, referenceSP: [], marketOdds: odds)
        }
        func select(_ start: Int, excluding: Set<Int> = [], pool: [BeijingSingleMatch]? = nil) throws -> [Int] {
            try VIP6MatchRecommender.directionalMatchNumbers(firstMatchNumber: start,
                matches: pool ?? matches, excluding: excluding, calibrated: false)
        }
        XCTAssertEqual(try select(1), [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try select(3), [3, 4, 5, 6, 7, 8])
        XCTAssertEqual(try select(8), [8, 9, 10, 11, 12, 13])
        XCTAssertEqual(try select(1, excluding: [3]), [2, 4, 5, 6, 7, 8])
        let missingOdds = matches.map { $0.matchNumber == "6" ? $0.replacingMarketOdds([]) : $0 }
        XCTAssertEqual(try select(1, pool: missingOdds), [2, 3, 7, 8, 9, 10])
        XCTAssertEqual(try select(1, pool: Array(matches.reversed())), [2, 3, 4, 5, 6, 7])
        XCTAssertThrowsError(try select(13))
    }

    func testDirectionalProtocolSettingsAndForwardValidationHaveSeparateCohort() throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.fixedFrontTwoDoublesEnabled = true
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let legacy = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("S10FRONTDBL=") }.joined(separator: "|")
        XCTAssertFalse(try FilterConfig.parse(legacy).svip10AdditionalFilters.fixedFrontTwoDoublesEnabled)
        let old = ["selectedConditionVersionID": "svip10-frozen-160", "svip10FrontTwoADEnabled": "1", "svip10AllABCDEnabled": "1", "svip10Maximum105Enabled": "1", "match1Input": "1", "svip10ScoreRangeInput": "5.5-7.5"]
        let updated = FilterInputDefaults.currentDirectionalDoubleSettings(from: old)
        XCTAssertEqual(updated["svip10Maximum105Enabled"], "0")
        XCTAssertEqual(updated["svip10FrontTwoADEnabled"], "0")
        XCTAssertEqual(updated["svip10AllABCDEnabled"], "0")
        XCTAssertEqual(updated["svip10FixedFrontTwoDoublesEnabled"], "0")
        XCTAssertEqual(updated["svip10ADDoublesWithinSixEnabled"], "0")
        XCTAssertEqual(updated["svip10AutomaticDoubleCount"], "1")
        XCTAssertEqual(updated["match1Input"], "1")
        XCTAssertEqual(updated["matchSearchStartInput"], "1")
        XCTAssertEqual(updated["svip10ScoreRangeInput"], "5.5-7.5")
        var withSearchStart = old
        withSearchStart["match1Input"] = "235"
        withSearchStart["matchSearchStartInput"] = "176"
        XCTAssertEqual(FilterInputDefaults.currentDirectionalDoubleSettings(from: withSearchStart)["matchSearchStartInput"], "176")
        XCTAssertNil(SVVVConditionPackage.snapshot(from: withSearchStart)["matchSearchStartInput"])
        XCTAssertEqual(SVVVConditionPackage.restoring(old, onto: withSearchStart)["matchSearchStartInput"], "176")
        let matches = directionalTestMatches()
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, matchNumbers: [2, 4, 8, 9, 10, 11], fixedFrontTwo: true)?.automaticDoubleSelection)
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches, calibrated: false,
            factors: [], now: Date(timeIntervalSince1970: 1_767_225_600), fixedFrontTwoDoubles: true))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.fixedFrontTwoModelVersion)
        XCTAssertNotEqual(forecast.cohortKey, DoubleForwardForecast.cohort(calibrated: false, factors: ""))
        var archived = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(forecast)) as? [String: Any])
        archived["version"] = DoubleForwardForecast.rankedFrontTwoModelVersion
        let ranked = try JSONDecoder().decode(DoubleForwardForecast.self, from: JSONSerialization.data(withJSONObject: archived))
        XCTAssertTrue(ranked.isValid)
        XCTAssertNotEqual(ranked.cohortKey, forecast.cohortKey)
        XCTAssertNotEqual(ranked.groupKey, forecast.groupKey)
    }

    func testCurrentSettingsCannotRestoreLegacy105Limit() throws {
        var old = FilterInputDefaults.values(from: try maximum105Reference(261).config)
        old["svip10Maximum105Enabled"] = "1"
        old["svip10FrontTwoADEnabled"] = "1"
        old["svip10AllABCDEnabled"] = "1"
        old["match1Input"] = "261"
        let updated = FilterInputDefaults.removingFixed105Limit(from: old)
        var expected = old
        expected["svip10Maximum105Enabled"] = "0"
        XCTAssertEqual(updated, expected)
        XCTAssertEqual(FilterInputDefaults.removingFixed105Limit(from: updated), updated)
        XCTAssertEqual(SVVVConditionPackage.snapshot(from: old)["svip10Maximum105Enabled"], "0")
        let restored = SVVVConditionPackage.restoring(old, onto: old)
        XCTAssertEqual(restored["svip10Maximum105Enabled"], "0")
        XCTAssertEqual(restored["svip10FrontTwoADEnabled"], "1")
        XCTAssertEqual(restored["svip10AllABCDEnabled"], "1")
        XCTAssertEqual(restored["match1Input"], "261")
    }

    func testConditionOnlyGenerationRetains159And92Without105Stage() throws {
        for (first, maximumTwos, count) in [(235, 4, 105), (261, 4, 159), (235, 3, 92)] {
            let reference = try maximum105Reference(first)
            var fields = reference.config.normalizedInput.components(separatedBy: "|")
            fields[5] = String(maximumTwos)
            let config = try FilterConfig.parse(fields.joined(separator: "|"))
            XCTAssertFalse(config.maximum105Active)
            let result = SequenceFilterEngine.calculate(config, previousContext: nil,
                currentOutcomeSPs: reference.odds, captureQueryStages: true)
            XCTAssertEqual(result.finalBetCount, count)
            XCTAssertEqual(result.uniqueExpandedBets.count, count)
            XCTAssertNil(result.maximum105InputBetCount)
            XCTAssertFalse(result.queryStages.contains { $0.name.contains("最多105注") })
            XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("最多105注") })
        }
    }

    func testComparisonTableCacheKeepsOddsAndHandicapsSeparateAcrossConcurrentCalls() async throws {
        let inputs: [([Double], Int)] = [
            ([1.91, 3.41, 4.11], -1), ([1.91, 3.41, 4.11], 1),
            ([2.31, 3.41, 3.09], -1), ([2.31, 3.41, 3.09], 0)
        ]
        let expected = try inputs.map { odds, handicap in
            try XCTUnwrap(HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: odds, handicap: handicap))
        }
        XCTAssertNotEqual(expected[0], expected[1])
        XCTAssertNotEqual(expected[0], expected[2])
        await withTaskGroup(of: (Int, [Double]?).self) { group in
            for index in 0..<80 {
                group.addTask {
                    let input = inputs[index % inputs.count]
                    return (index % inputs.count, HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: input.0, handicap: input.1))
                }
            }
            for await (index, result) in group { XCTAssertEqual(result, expected[index]) }
        }
        XCTAssertNil(HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: [.nan, 3, 4], handicap: -1))
        XCTAssertNil(HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: [1, 3, 4], handicap: -1))
    }

    func testFrontTwoADSelectionMovesPastBCStartAndKeepsSixOrdered() throws {
        let matches = abcdFillMatches("BCBCBCDABCBCAA")
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: true, requireFrontTwoAD: true)
        XCTAssertEqual(numbers, [7, 8, 9, 10, 11, 12])
        let recommendation = try XCTUnwrap(VIP6MatchRecommender.recommendMatches(numbers: numbers, matches: matches))
        XCTAssertEqual(recommendation.logic, "DABCBC")
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: Array(matches.reversed()),
            requireAllABCD: true, requireFrontTwoAD: true), numbers)
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: true, requireFrontTwoAD: false), [1, 2, 3, 4, 7, 8])
    }

    func testFrontTwoADAllowsAAADDAAndDDAndProtectsBothPositions() throws {
        for letters in ["BBABAACCCCDB", "BBDBDDCCCCAB"] {
            let matches = abcdFillMatches(letters)
            let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
                requireAllABCD: true, requireFrontTwoAD: true)
            XCTAssertEqual(numbers, [3, 5, 6, 7, 11, 12])
            let r = try XCTUnwrap(VIP6MatchRecommender.recommendMatches(numbers: numbers, matches: matches))
            XCTAssertTrue(r.logic.prefix(2).allSatisfy { "AD".contains($0) })
            XCTAssertEqual(Set(r.logic), Set("ABCD"))
        }
        for letters in ["BCADBCBC", "BCDABCBC"] {
            XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: abcdFillMatches(letters),
                requireAllABCD: true, requireFrontTwoAD: true), [3, 4, 5, 6, 7, 8])
        }
        XCTAssertEqual(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: abcdFillMatches("BBABAACCCCDB"),
            requireAllABCD: false, requireFrontTwoAD: true), [3, 5, 6, 7, 8, 9])
    }

    func testFrontTwoADRejectsMissingPairsShortPoolsAndSeventhConflicts() throws {
        for letters in ["BCBCBCBCBC", "DCCBCCBCC", "BCBCDA"] {
            XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
                matches: abcdFillMatches(letters), requireAllABCD: true, requireFrontTwoAD: true))
        }
        XCTAssertThrowsError(try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("BCBCBCDABCBCAA"), excludingMatchNumbers: [7], requireAllABCD: true, requireFrontTwoAD: true))
        let matches = abcdFillMatches("BCADBCADBCBC")
        let changed = matches.map { $0.matchNumber == "3" ? $0.replacingMarketOdds([3, 4, 2]) : $0 }
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: changed,
            requireAllABCD: true, requireFrontTwoAD: true)
        XCTAssertEqual(numbers, [4, 7, 8, 9, 10, 11])
    }

    func testFrontTwoADSwitchAndSeparateForwardCohortRoundTrip() throws {
        var config = try maximum105Reference(235).config
        XCTAssertFalse(config.svip10AdditionalFilters.frontTwoADEnabled)
        config.svip10AdditionalFilters.frontTwoADEnabled = true
        let parsed = try FilterConfig.parse(config.normalizedInput)
        XCTAssertTrue(parsed.svip10AdditionalFilters.frontTwoADEnabled)
        XCTAssertEqual(FilterInputDefaults.values(from: parsed)["svip10FrontTwoADEnabled"], "1")
        XCTAssertEqual(SVVVConditionPackage.snapshot(from: ["svip10FrontTwoADEnabled": "0"])["svip10FrontTwoADEnabled"], "0")
        let matches = abcdFillMatches("BCBCBCDABCBCAA")
        let numbers = try VIP6MatchRecommender.selectMatchNumbers(firstMatchNumber: 1, matches: matches,
            requireAllABCD: true, requireFrontTwoAD: true)
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: numbers[0],
            matches: matches, calibrated: false, matchNumbers: numbers)?.automaticDoubleSelection)
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, allABCDSelection: true, frontTwoADSelection: true))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.frontTwoADAllABCDModelVersion)
        XCTAssertNotEqual(forecast.cohortKey, DoubleForwardForecast.cohort(calibrated: false, factors: "", version: DoubleForwardForecast.allABCDModelVersion))
    }

    private func maximum105Reference(_ first: Int) throws -> (config: FilterConfig, odds: [[Double]]) {
        var fields = #"235,236,237,238,239,240|DABCBB|0-24|0-100|100|4|0|100|0-5|QDROP0|S10COLDON=1|S10COLD=0-4|S10DRAWON=1|S10DRAW=0-3|S10WLON=1|S10DBLNO4=0|S10DBLTOP2=1|S10DBL2LOW=1|S10DBLCAL=1|S10AUTOPAIR=1|S10FACTORS=euro,asianLine,asianWater,books,funds,reverse,crowd,drawGap|S10MARKET=|S10F5MON=1|S10F5MRANGE=2-8|S10F5RUN2ON=0|S10F5RET2ON=0|S10F5NO11ON=0|S10F5V3MAX2ON=0|S10FAV24ON=0|S10FAV14ON=0|S10ODDSPROD6ON=1|S10ODDSPROD6MIN=250.0|S10B24ON=0|S10B35ON=1|S10BRANGE=2-5|S10REC100=0|S10LINE50=0|S10MASS60=0|SVIP11=0|SVIP10=1|SCOREMIN250=5.5|SCORE250=7.5|TXT50=0|TXTADD=50|ADAPTIVES=0|SVIP7=0|FINAL=OFF|SEED=1|MKTW=15|RATE=50|OC_KINDS=2-3|OC_OSUM=2-15|OC_NDRUN=3-6|OCTOLON=0|OCTOL=0-0|ALLTOLON=0|ALLTOL=0-0|RUNS=0|NLRUN=3-7|NDRUN=3-7|NWRUN=3-7|RUNTOL=0-1|RUN2ON=0|RUN2RANGE=5-7|RUN2TOL=2-3|SAMERUNS=0|WINRUN=2-7|DRAWRUN=2-7|LOSSRUN=2-7|SAMERUNTOL=2-3|PROTECT11=0|SPPRODON=0|SPPROD=20.0-1500.0|HODDSPRODON=0|HODDSPROD=50-300|HODDSSUMON=0|HODDSSUM=12-16|PRIZEON=0|PRIZE=26.0-1950.0|SPRISKON=0|MAXSP=5.0|HIGHSPTH=4.0|HIGHSPCOUNT=0-1|MINPROBON=0|MINPROB=15.0|JOINTPROBON=0|JOINTPROB=0.1-100.0|VIP12PROBON=0|SVIP1ODDSGUARDON=0|VIP16TOP200ON=0|VIP18TOP200ON=0|VIP19CUSTOMTOP200ON=0|GROUPON=0|GROUPMODE=BOTH|GFSUM=0-9|GBSUM=0-9|GFSP=1.0-200.0|GBSP=1.0-100.0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=0|U247TH=-0.050756|V10TOP150ON=0|HODDSPRODCOUNT=0|MCOUNT=6|SUMCOUNT=6|CALCCOUNT=6|F5LOSS13ON=0|F5LOSSRANGE=1-5|F5WINON=0|STRUCT3ON=0|S250=15-20|M250=2-8|R250=2-15|SIX250=1|SIXSCOPE=1|PACKAGEON=1|TOP5SECOND=0|TOP5RELAX=0|FIVEWIDE=0|STRUCTRELAX=0|STRUCT3R=5-12|F6LOSS14ON=0|F5R39ON=0|F5NO000ON=0|F5WINRANGE=1-5|F5NO111ON=0|F5ACTUALM36ON=0|F5ACTUALMRANGE=3-6|SVIP5FOURCAPON=0|SVIP5DROP=0|MPERM=0|NO4LOWODDS=0|NO4=|BASEOFF=sum,valueThree,variance|399:3|MERGE3"#.components(separatedBy: "|")
        if first == 261 {
            fields[0] = "261,262,263,264,272,276"
            fields[1] = "CCBBDA"
        }
        let odds: [[Double]] = first == 235 ? [[4.665564676066071, 4.559034787458852, 1.7657892522892678], [2.0385931983045764, 3.7392377915426187, 4.1316942361360125], [2.3251207729468595, 3.5482885729331226, 3.471151864825881], [2.9846153846153842, 3.5925925925925926, 2.586666666666666], [2.5267949513759564, 3.849330181245075, 2.903126114346844], [2.541095890410959, 3.388127853881279, 3.2121212121212124]] : [[3.3161888483153343, 3.9152423176884272, 2.25714789353076], [2.6902725831937766, 4.550127763424469, 2.4478821075407255], [2.2078467921955776, 5.075635514689252, 2.856731828268472], [2.333614425566846, 4.495085878407987, 2.8652060856682], [3.66185034371032, 3.575434996366124, 2.2359971125310802], [1.9288389513108612, 3.6165730337078648, 4.8768939393939394]]
        return (try FilterConfig.parse(fields.joined(separator: "|")), odds)
    }

    func testMaximum105Reproduces235AndTrims261WithoutAddingBets() throws {
        for first in [235, 261] {
            let reference = try maximum105Reference(first)
            let baseline = SequenceFilterEngine.calculate(reference.config, previousContext: nil, currentOutcomeSPs: reference.odds)
            XCTAssertEqual(baseline.finalBetCount, first == 235 ? 105 : 159)
            var config = reference.config
            config.svip10AdditionalFilters.maximum105Enabled = true
            let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds, captureQueryStages: true)
            XCTAssertEqual(result.finalBetCount, 105)
            XCTAssertEqual(result.maximum105InputBetCount, baseline.finalBetCount)
            XCTAssertNil(result.maximum105FailureMessage)
            XCTAssertTrue(Set(result.uniqueExpandedBets).isSubset(of: Set(baseline.uniqueExpandedBets)))
            XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("最多105注") })
            if first == 235 {
                XCTAssertEqual(Set(result.uniqueExpandedBets), Set(baseline.uniqueExpandedBets))
                XCTAssertEqual(result.displayResultLines.count, 28)
            } else {
                let removed = try XCTUnwrap(baseline.uniqueExpandedBets.first { !Set(result.uniqueExpandedBets).contains($0) })
                if case .excluded(let stage) = result.queryAttribution(for: Array(removed.prefix(6))) {
                    XCTAssertTrue(stage.contains("最多105注"))
                } else { XCTFail("105优选删除的投注必须归因到该阶段") }
            }
        }
    }

    func testMaximum105Leaves92AndZeroUnchangedAndDisablesWithMaster() throws {
        let reference = try maximum105Reference(235)
        var fields = reference.config.normalizedInput.components(separatedBy: "|")
        fields[5] = "3"
        var config = try FilterConfig.parse(fields.joined(separator: "|"))
        let baseline = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds)
        XCTAssertEqual(baseline.finalBetCount, 92)
        config.svip10AdditionalFilters.maximum105Enabled = true
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds)
        XCTAssertEqual(result.finalBetCount, 92)
        XCTAssertEqual(Set(result.uniqueExpandedBets), Set(baseline.uniqueExpandedBets))
        config.outcomeConditions[.outcomeSum] = 18...18
        XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds).finalBetCount, 0)
        config.conditionPackageEnabled = false
        let disabled = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds)
        XCTAssertEqual(disabled.finalBetCount, 729)
        XCTAssertNil(disabled.maximum105InputBetCount)
    }

    func testMaximum105CapsExpandedSeventhAndRequiresOddsForRanking() throws {
        let reference = try maximum105Reference(261)
        var fields = reference.config.normalizedInput.components(separatedBy: "|")
        fields = fields.map { $0 == "399:3" ? "399:310" : $0 }
        var config = try FilterConfig.parse(fields.joined(separator: "|"))
        let baseline = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds)
        XCTAssertEqual(baseline.finalBetCount, 159 * 3)
        config.svip10AdditionalFilters.maximum105Enabled = true
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: reference.odds)
        XCTAssertEqual(result.finalBetCount, 105)
        XCTAssertTrue(Set(result.uniqueExpandedBets).isSubset(of: Set(baseline.uniqueExpandedBets)))
        config.disabledBasicConditions = Set(BasicCondition.allCases)
        config.outcomeConditions = [:]
        config.svip10AdditionalFilters = SVIP10AdditionalFilters(maximum105Enabled: true)
        XCTAssertTrue(config.requiresSPData)
        let missing = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(missing.finalBetCount, 0)
        XCTAssertNotNil(missing.maximum105FailureMessage)
    }

    func testMaximum105SwitchRoundTripsAndLegacyArchivesStayOff() throws {
        let reference = try maximum105Reference(235)
        XCTAssertFalse(reference.config.svip10AdditionalFilters.maximum105Enabled)
        var config = reference.config
        config.svip10AdditionalFilters.maximum105Enabled = true
        let parsed = try FilterConfig.parse(config.normalizedInput)
        XCTAssertTrue(parsed.maximum105Active)
        XCTAssertEqual(parsed, config)
        XCTAssertEqual(FilterInputDefaults.values(from: parsed)["svip10Maximum105Enabled"], "1")
        XCTAssertEqual(SVVVConditionPackage.snapshot(from: ["svip10Maximum105Enabled": "0"])["svip10Maximum105Enabled"], "0")
        let encoded = FilterConfig.appendingSVIP10AdditionalInput(config.normalizedInput,
            coldEnabled: true, coldRange: "0-4", drawEnabled: true, drawRange: "0-3", maximum105Enabled: false)
        XCTAssertFalse(try FilterConfig.parse(encoded).maximum105Active)
        XCTAssertEqual(encoded.components(separatedBy: "|").filter { $0.hasPrefix("S10MAX105=") }.count, 1)
        XCTAssertEqual(try FilterConfig.parse(encoded).extraMatches.map(\.matchNumber), ["399"])
    }

    func testFixed105SelectorUsesExpandedUniqueBetsAndIsDeterministic() throws {
        let universe = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { r in [3, 1, 0].map { r + [$0] } } }
        let odds = Array(repeating: [2.0, 3.5, 4.0], count: 6)
        let selected = try XCTUnwrap(SequenceFilterEngine.selectSVIP10Fixed105Bets(universe + universe,
            customOdds: odds, calibrated: true))
        XCTAssertEqual(selected.count, 105)
        XCTAssertEqual(Set(selected).count, 105)
        XCTAssertEqual(selected.first, Array(repeating: 3, count: 6))
        XCTAssertEqual(selected, SequenceFilterEngine.selectSVIP10Fixed105Bets(Array(universe.reversed()), customOdds: odds, calibrated: true))
        let equalOdds = Array(repeating: [3.0, 3.0, 3.0], count: 6)
        XCTAssertEqual(SequenceFilterEngine.selectSVIP10Fixed105Bets(universe, customOdds: equalOdds, calibrated: false),
            Array(universe.prefix(105)))
    }

    func testFixed105SelectorNeverAddsFilteredBetsAndRejectsMissingOdds() throws {
        let bets = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { r in [3, 1, 0].map { r + [$0] } } }
        let odds = Array(repeating: [2.0, 3.5, 4.0], count: 6)
        for count in [0, 92, 105, 159] {
            let passed = Array(bets.prefix(count))
            let selected = try XCTUnwrap(SequenceFilterEngine.selectSVIP10Fixed105Bets(passed, customOdds: odds, calibrated: false))
            XCTAssertEqual(selected.count, min(count, 105))
            XCTAssertTrue(Set(selected).isSubset(of: Set(passed)))
        }
        XCTAssertNil(SequenceFilterEngine.selectSVIP10Fixed105Bets(bets, customOdds: nil, calibrated: false))
        XCTAssertNil(SequenceFilterEngine.selectSVIP10Fixed105Bets(bets, customOdds: Array(odds.prefix(5)), calibrated: false))
    }

    private func abcdFillMatches(_ letters: String) -> [BeijingSingleMatch] {
        letters.enumerated().map { index, letter in
            let logic = LogicMapping(rawValue: String(letter).lowercased())!
            return BeijingSingleMatch(issue: "26111", matchNumber: String(index + 1), fixtureID: "abcd-fill-\(index + 1)",
                league: "测试", matchTime: "11-03 20:00", status: "未", homeTeam: "主", awayTeam: "客",
                handicap: 0, referenceSP: [], marketOdds: logic.values.map(Double.init))
        }
    }

    func testABCDFillKeepsFirstAndSixMatchesWhileAddingLaterMissingTypes() throws {
        let matches = abcdFillMatches("BCBCBCACD")
        let numbers = try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1, matches: matches)
        XCTAssertEqual(numbers, [1, 2, 3, 4, 7, 9])
        let recommendation = try XCTUnwrap(VIP6MatchRecommender.recommendMatches(numbers: numbers, matches: matches))
        XCTAssertEqual(Set(recommendation.logic), Set("ABCD"))
        XCTAssertEqual(recommendation.mainMatchNumbers, numbers)
        XCTAssertEqual(recommendation.sixthMatchNumber, 9)
        let doubles = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, matchNumbers: numbers)?.automaticDoubleSelection)
        XCTAssertEqual(doubles.matches.map(\.number), numbers)
        XCTAssertEqual(doubles.choices.count, 2)
        XCTAssertTrue(doubles.choices.allSatisfy { numbers.contains($0.number) })
    }

    func testABCDFillPreservesAnAlreadyCompleteGroupAndNeverLosesRareTypes() throws {
        XCTAssertEqual(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("ABCDABCD")), [1, 2, 3, 4, 5, 6])
        let matches = abcdFillMatches("ABBBBBCCCD")
        let selected = try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1, matches: matches)
        XCTAssertEqual(selected, [1, 2, 3, 4, 7, 10])
        XCTAssertEqual(Set(try XCTUnwrap(VIP6MatchRecommender.recommendMatches(numbers: selected, matches: matches)).logic), Set("ABCD"))
    }

    func testABCDFillStopsWhenTypesOrSixCandidatesAreUnavailable() {
        for letters in ["BCBCBCBCBC", "ABCABCABC", "ABCD"] {
            XCTAssertThrowsError(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1,
                matches: abcdFillMatches(letters)))
        }
        XCTAssertThrowsError(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 0,
            matches: abcdFillMatches("ABCDAB")))
        XCTAssertThrowsError(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1,
            matches: abcdFillMatches("ABCDAB"), excludingMatchNumbers: [1]))
    }

    func testABCDFillSkipsSeventhAndUnavailableCandidatesAndIgnoresResults() throws {
        let matches = abcdFillMatches("BCBCBCACDA")
        let numbers = try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1,
            matches: matches, excludingMatchNumbers: [7])
        XCTAssertEqual(numbers, [1, 2, 3, 4, 9, 10])
        let invalid = matches.map { match in
            BeijingSingleMatch(issue: match.issue, matchNumber: match.matchNumber, fixtureID: match.fixtureID,
                league: match.league, matchTime: match.matchTime, status: "完", homeTeam: match.homeTeam,
                awayTeam: match.awayTeam, handicap: match.handicap, referenceSP: [99, 99, 99],
                marketOdds: match.matchNumber == "7" ? [] : match.marketOdds, homeScore: 9, awayScore: 0)
        }
        XCTAssertEqual(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1, matches: invalid), numbers)
        XCTAssertThrowsError(try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 7, matches: invalid))
    }

    func testABCDFillSwitchRoundTripsAndOldArchivesRemainOff() throws {
        let base = FilterConfig.svip10Input(numbers: ["1", "2", "3", "4", "7", "9"], logic: "BCBCAD", extras: ["99:1"])
        XCTAssertFalse(try FilterConfig.parse(base).svip10AdditionalFilters.allABCDSelectionEnabled)
        let enabled = FilterConfig.appendingSVIP10AdditionalInput(base, coldEnabled: false, coldRange: "0-6",
            drawEnabled: false, drawRange: "0-6", allABCDSelectionEnabled: true)
        let config = try FilterConfig.parse(enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.allABCDSelectionEnabled)
        XCTAssertEqual(config, try FilterConfig.parse(config.normalizedInput))
        XCTAssertEqual(config.extraMatches.map(\.matchNumber), ["99"])
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip10AllABCDEnabled"], "1")
        let disabled = FilterConfig.appendingSVIP10AdditionalInput(enabled, coldEnabled: false, coldRange: "0-6",
            drawEnabled: false, drawRange: "0-6", allABCDSelectionEnabled: false)
        XCTAssertFalse(try FilterConfig.parse(disabled).svip10AdditionalFilters.allABCDSelectionEnabled)
        XCTAssertEqual(disabled.components(separatedBy: "|").filter { $0.hasPrefix("S10ABCDSELECT=") }.count, 1)
        let values = ["svip10AllABCDEnabled": "0", "match1Input": "1"]
        XCTAssertEqual(SVVVConditionPackage.snapshot(from: values)["svip10AllABCDEnabled"], "0")
    }

    func testABCDFillForecastUsesActualSixAndSeparateCohort() throws {
        let matches = abcdFillMatches("BCBCBCACD")
        let numbers = try VIP6MatchRecommender.allABCDMatchNumbers(firstMatchNumber: 1, matches: matches)
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, matchNumbers: numbers)?.automaticDoubleSelection)
        let now = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26111", matchTime: "11-02 10:00"))
        XCTAssertNil(DoubleForwardForecast.make(selection: selection, matches: matches, calibrated: false, factors: [], now: now))
        let forecast = try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: [], now: now, allABCDSelection: true))
        XCTAssertTrue(forecast.isValid)
        XCTAssertEqual(forecast.fixtures.map(\.number), numbers)
        XCTAssertEqual(forecast.version, DoubleForwardForecast.allABCDModelVersion)
        XCTAssertNotEqual(forecast.cohortKey, DoubleForwardForecast.cohort(calibrated: false, factors: ""))
        XCTAssertTrue(forecast.groupKey.contains("1,2,3,4,7,9"))
    }

    func testRelativePositionRemovalPurgesOnlyThose148ConditionsAndPreservesSwitches() throws {
        let removed=OutcomeCondition.activeCases.filter(\.isRelativePositionCondition)
        XCTAssertEqual(removed.count,148)
        XCTAssertTrue(OutcomeCondition.editorCases.allSatisfy { !$0.title.hasPrefix("相对位置") })
        var values=["svvvSelected":"1","selectedConditionVersionID":"svip10-frozen-160",
            "svip10Enabled":"0","svvvHighPass40Enabled":"0","svvvHighPass100Enabled":"0",
            "svvvHighPass50Enabled":"1","svvvHighPass50DoubleEnabled":"1","OC_DSEG":"0-3","OCON_DSEG":"1"]
        values=SVVVConditionPackage.addingHighPass98Conditions(to:values)
        values=SVVVConditionPackage.addingHighPass98FiftyConditions(to:values)
        values["svvvHighPass100Enabled"]="0"
        let cleaned=SVVVConditionPackage.removingRelativePositionConditions(from:values)
        let removedKeys=Set(removed.flatMap { ["OC_"+$0.rawValue,"OCON_"+$0.rawValue] })
        for (key,value) in values where !removedKeys.contains(key) && key != "enteredConditionIDs" {
            XCTAssertEqual(cleaned[key],value)
        }
        for key in removedKeys { XCTAssertNil(cleaned[key]) }
        XCTAssertEqual(SVVVConditionPackage.removingRelativePositionConditions(from:cleaned),cleaned)
        let ranges=FilterInputDefaults.enabledEditorOutcomeRanges(values:values)
        XCTAssertTrue(ranges.keys.allSatisfy { !$0.isRelativePositionCondition })
        XCTAssertEqual(ranges[.h98R001],"0-2")
        XCTAssertEqual(ranges[.h98R002],"0-1")
        let restored=SVVVConditionPackage.restoring(SVVVConditionPackage.snapshot(from:values),onto:values)
        for key in removedKeys { XCTAssertNil(restored[key]) }
        XCTAssertEqual(restored["svvvHighPass50DoubleEnabled"],"1")
        let ids=Set((cleaned["enteredConditionIDs"] ?? "").split(separator:",").map(String.init))
        XCTAssertTrue(ids.isDisjoint(with:Set(removed.map { "OC_"+$0.rawValue })))
    }

    func testRemovingRelativePositionChangesCurrentGenerationButKeepsOldArchiveMeaning() throws {
        var archived=try calibratedDoubleConfig()
        archived.svip10AdditionalFilters=SVIP10AdditionalFilters()
        archived.conditionPackageEnabled=false;archived.highPass93GroupEnabled=false
        archived.highPass98GroupEnabled=true;archived.highPass98FiftyGroupEnabled=false
        let rule=OutcomeCondition.highPass98Additions[2]
        XCTAssertTrue(rule.condition.isRelativePositionCondition)
        archived.outcomeConditions=[rule.condition:rule.range]
        let encoded=archived.normalizedInput
        let originalResult=SequenceFilterEngine.calculate(archived,previousContext:nil)
        XCTAssertLessThan(originalResult.finalBetCount,729)
        let parsed=try FilterConfig.parse(encoded)
        XCTAssertEqual(SequenceFilterEngine.calculate(parsed,previousContext:nil).finalBetCount,originalResult.finalBetCount)
        let old=FilterInputDefaults.values(from:parsed)
        var current=parsed
        let cleaned=SVVVConditionPackage.removingRelativePositionConditions(from:old)
        let ranges=FilterInputDefaults.enabledEditorOutcomeRanges(values:cleaned)
        current.outcomeConditions=Dictionary(uniqueKeysWithValues:ranges.map { condition,text in
            let v=text.split(separator:"-").compactMap { Int($0) }
            return (condition,v[0]...v[1])
        })
        XCTAssertEqual(SequenceFilterEngine.calculate(current,previousContext:nil).finalBetCount,729)
        XCTAssertEqual(archived.normalizedInput,encoded)
    }

    func testFourthFiftyAnnualCountsAre98AndDisjointFromPrevious140() throws {
        let additions = OutcomeCondition.highPass98FiftyAdditions
        XCTAssertEqual(additions.count, 50)
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let masks = additions.map { a in patterns.map { a.range.contains(a.condition.value(in:$0)) } }
        let previous = Set((OutcomeCondition.highPass93Additions + OutcomeCondition.highPass98Additions).map { a in
            patterns.map { a.range.contains(a.condition.value(in:$0)) }
        })
        XCTAssertEqual(Set(masks).count,50)
        XCTAssertTrue(Set(masks).isDisjoint(with:previous))
        XCTAssertTrue(masks.allSatisfy { $0.contains(true) && $0.contains(false) })
        XCTAssertEqual(patterns.filter { o in additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) } }.count,279)
        let url = try XCTUnwrap(Bundle.main.url(forResource:"ConditionEffectHistory",withExtension:"json"))
        let data = try JSONDecoder().decode(ConditionEffectDataset.self,from:Data(contentsOf:url))
        for year in [2025,2026] {
            let groups = data.groups.filter { $0.year == year }
            for a in additions {
                let hits = groups.filter { a.range.contains(a.condition.value(in:$0.outcomes)) }.count
                let definition = try XCTUnwrap(HighPass98FiftyCatalog.byCondition[a.condition])
                XCTAssertEqual(hits,year == 2025 ? definition.hits2025 : definition.hits2026)
                XCTAssertGreaterThanOrEqual(Double(hits)/Double(groups.count),0.98)
                XCTAssertNotNil(a.condition.highPassHistoricalReference(rangeText:"0-\(a.range.upperBound)"))
                XCTAssertNil(a.condition.highPassHistoricalReference(rangeText:"0-\(a.range.upperBound+1)"))
            }
            XCTAssertEqual(groups.filter { g in additions.allSatisfy { $0.range.contains($0.condition.value(in:g.outcomes)) } }.count,year == 2025 ? 990:760)
        }
    }

    func testFourMastersControlSixteenDistinctGenerationIntersectionsAndArchives() throws {
        var c = try calibratedDoubleConfig()
        c.svip10AdditionalFilters = SVIP10AdditionalFilters()
        let all = OutcomeCondition.highPass93Additions + OutcomeCondition.highPass98Additions + OutcomeCondition.highPass98FiftyAdditions
        c.outcomeConditions = Dictionary(uniqueKeysWithValues:all.map { ($0.condition,$0.range) })
        c.outcomeConditions[.draws] = 0...1
        let saved = c.outcomeConditions
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        for bits in 0..<16 {
            let old = bits&1 != 0, forty = bits&2 != 0, hundred = bits&4 != 0, fifty = bits&8 != 0
            c.conditionPackageEnabled=old;c.highPass93GroupEnabled=forty
            c.highPass98GroupEnabled=hundred;c.highPass98FiftyGroupEnabled=fifty
            let parsed=try FilterConfig.parse(c.normalizedInput)
            XCTAssertEqual(parsed,c)
            let expected=Set(patterns.filter { o in
                (!old || o.filter { $0 == 1 }.count <= 1)
                && (!forty || OutcomeCondition.highPass93Additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) })
                && (!hundred || OutcomeCondition.highPass98Additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) })
                && (!fifty || OutcomeCondition.highPass98FiftyAdditions.allSatisfy { $0.range.contains($0.condition.value(in:o)) })
            })
            let result=SequenceFilterEngine.calculate(parsed,previousContext:nil)
            XCTAssertEqual(Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) }),expected,"masters \(bits)")
            XCTAssertEqual(result.config.outcomeConditions,saved)
            XCTAssertEqual(FilterInputDefaults.values(from:parsed)["svvvHighPass50Enabled"],fifty ? "1":"0")
            if !old { XCTAssertFalse(parsed.requiresSPData) }
        }
        let legacy=c.normalizedInput.components(separatedBy:"|").filter { !$0.hasPrefix("HP98FIFTYGROUP=") }.joined(separator:"|")
        XCTAssertNil(try FilterConfig.parse(legacy).highPass98FiftyGroupEnabled)
    }

    func testFourthMigrationPreservesExistingSettingsAndAddsFiftyPlusDoubleOn() {
        let old=["svvvSelected":"1","selectedConditionVersionID":"svip10-frozen-160","vipConditionsEnabled":"1",
            "svip10Enabled":"0","svvvHighPass40Enabled":"0","svvvHighPass100Enabled":"0",
            "OC_H98_001":"0-2","OCON_H98_001":"0","enteredConditionIDs":"OC_H98_001"]
        let updated=SVVVConditionPackage.addingHighPass98FiftyConditions(to:old)
        for (key,value) in old where key != "enteredConditionIDs" { XCTAssertEqual(updated[key],value) }
        XCTAssertEqual(updated["svvvHighPass50Enabled"],"1")
        XCTAssertEqual(updated["svvvHighPass50DoubleEnabled"],"1")
        for a in OutcomeCondition.highPass98FiftyAdditions {
            XCTAssertEqual(updated["OC_"+a.condition.rawValue],"0-\(a.range.upperBound)")
            XCTAssertEqual(updated["OCON_"+a.condition.rawValue],"1")
        }
        XCTAssertEqual(SVVVConditionPackage.addingHighPass98FiftyConditions(to:updated),updated)
        var other=old;other["svvvSelected"]="0"
        XCTAssertEqual(SVVVConditionPackage.addingHighPass98FiftyConditions(to:other),other)
    }

    func testFourthAutomaticSingleDoubleChoosesOneMatchAndCannotBeAddedBack() throws {
        var c=try calibratedDoubleConfig()
        c.svip10AdditionalFilters=SVIP10AdditionalFilters()
        c.highPass93GroupEnabled=false;c.highPass98GroupEnabled=false
        c.highPass98FiftyGroupEnabled=true;c.highPass50DoubleEnabled=true
        var odds=Array(repeating:[2.0,3.0,9.0],count:6)
        odds[3]=[1.1,4.0,100.0]
        let selection=try XCTUnwrap(c.highPass50DoubleSelection(in:odds))
        XCTAssertEqual(selection.position,4);XCTAssertEqual(selection.outcomes,[3,1])
        XCTAssertEqual(c.highPass50DoubleSelection(in:Array(repeating:[2,2,2],count:6))?.position,1)
        XCTAssertEqual(c.highPass50DoubleSelection(in:Array(repeating:[2,2,2],count:6))?.outcomes,[3,1])
        XCTAssertNil(c.highPass50DoubleSelection(in:Array(odds.prefix(5))))
        let patterns=(0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        for original in [false,true] { for master in [false,true] { for individual in [false,true] {
            c.conditionPackageEnabled=original;c.highPass98FiftyGroupEnabled=master;c.highPass50DoubleEnabled=individual
            c.allConditionsToleranceEnabled=true;c.allConditionsToleranceRange=0...20
            c.txtCompactEnabled=true;c.maximumTXTAdditionalBets=50
            let parsed=try FilterConfig.parse(c.normalizedInput)
            XCTAssertEqual(parsed,c)
            let result=SequenceFilterEngine.calculate(parsed,previousContext:nil,currentOutcomeSPs:odds)
            let expected=Set(patterns.filter { !master || !individual || [3,1].contains($0[3]) })
            XCTAssertEqual(Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) }),expected)
            XCTAssertEqual(parsed.requiresSPData,original || (master && individual))
            for outcome in [[3,3,3,3,3,3],[3,3,3,0,3,3]] {
                let reasons=SequenceFilterEngine.baseFilterFailureReasons(for:outcome,config:parsed,currentOutcomeSPs:odds)
                XCTAssertEqual(reasons.isEmpty,!master || !individual || outcome[3] != 0)
            }
        } } }
        c.conditionPackageEnabled=false;c.highPass98FiftyGroupEnabled=true;c.highPass50DoubleEnabled=true
        XCTAssertEqual(SequenceFilterEngine.calculate(c,previousContext:nil).finalBetCount,0)
        XCTAssertFalse(SequenceFilterEngine.baseFilterFailureReasons(for:[3,3,3,3,3,3],config:c).isEmpty)
    }

    func testFourthHomeHistoryHonorsMasterAndSingleDoubleOnAllSix() async throws {
        var c=try calibratedDoubleConfig()
        c.conditionPackageEnabled=false;c.svip10AdditionalFilters=SVIP10AdditionalFilters()
        c.highPass93GroupEnabled=false;c.highPass98GroupEnabled=false
        c.outcomeConditions=Dictionary(uniqueKeysWithValues:OutcomeCondition.highPass98FiftyAdditions.map { ($0.condition,$0.range) })
        let url=try XCTUnwrap(Bundle.main.url(forResource:"ConditionEffectHistory",withExtension:"json"))
        let data=try JSONDecoder().decode(ConditionEffectDataset.self,from:Data(contentsOf:url))
        var singleHits=[2025:0,2026:0]
        for g in data.groups {
            let s=try XCTUnwrap(c.highPass50DoubleSelection(in:g.odds))
            if s.outcomes.contains(g.outcomes[s.position-1]) { singleHits[g.year]! += 1 }
        }
        XCTAssertEqual(singleHits,[2025:1888,2026:1448])
        for master in [false,true] { for doubleOn in [false,true] {
            c.highPass98FiftyGroupEnabled=master;c.highPass50DoubleEnabled=doubleOn
            let summary=try await ConditionEffectAnalysis.passRate(input:c.normalizedInput,dataset:data)
            XCTAssertEqual(summary.years[2025]?.hits,!master ? 2439 : (doubleOn ? 786:990))
            XCTAssertEqual(summary.years[2026]?.hits,!master ? 1884 : (doubleOn ? 586:760))
        } }
    }

    func testHundred98AnnualCountsAndDistinctNontrivialPredicates() throws {
        let additions = OutcomeCondition.highPass98Additions
        XCTAssertEqual(additions.count, 100)
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let masks = additions.map { addition in patterns.map { addition.range.contains(addition.condition.value(in: $0)) } }
        let forty = Set(OutcomeCondition.highPass93Additions.map { a in patterns.map { a.range.contains(a.condition.value(in: $0)) } })
        XCTAssertEqual(Set(masks).count, 100)
        XCTAssertTrue(Set(masks).isDisjoint(with: forty))
        XCTAssertTrue(masks.allSatisfy { $0.contains(true) && $0.contains(false) })
        XCTAssertEqual(patterns.filter { o in additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) } }.count, 185)
        let expected = [2025:[2397, 2401, 2391, 2409, 2400, 2403, 2394, 2391, 2411, 2408, 2395, 2393, 2399, 2402, 2401, 2393, 2399, 2403, 2391, 2393, 2402, 2404, 2402, 2402, 2401, 2403, 2407, 2407, 2400, 2395, 2391, 2406, 2397, 2399, 2407, 2393, 2395, 2394, 2396, 2417, 2404, 2397, 2392, 2394, 2399, 2408, 2394, 2405, 2408, 2402, 2405, 2418, 2394, 2407, 2405, 2405, 2426, 2393, 2412, 2399, 2410, 2423, 2413, 2409, 2396, 2410, 2394, 2413, 2417, 2409, 2395, 2413, 2399, 2416, 2421, 2403, 2424, 2424, 2415, 2411, 2416, 2417, 2398, 2406, 2413, 2420, 2406, 2393, 2404, 2400, 2402, 2416, 2399, 2417, 2420, 2416, 2414, 2416, 2416, 2423],2026:[1857, 1864, 1854, 1861, 1852, 1854, 1856, 1861, 1854, 1847, 1850, 1859, 1847, 1860, 1847, 1853, 1857, 1849, 1853, 1856, 1848, 1857, 1850, 1856, 1861, 1860, 1854, 1851, 1848, 1848, 1856, 1847, 1850, 1848, 1855, 1850, 1849, 1852, 1865, 1867, 1861, 1856, 1847, 1847, 1858, 1847, 1849, 1860, 1872, 1866, 1853, 1863, 1847, 1861, 1859, 1857, 1880, 1857, 1868, 1847, 1870, 1866, 1865, 1862, 1854, 1855, 1851, 1855, 1868, 1856, 1857, 1867, 1855, 1860, 1866, 1864, 1865, 1871, 1870, 1866, 1872, 1854, 1854, 1854, 1862, 1864, 1856, 1853, 1862, 1849, 1864, 1862, 1856, 1863, 1871, 1866, 1862, 1861, 1858, 1868]]
        let url = try XCTUnwrap(Bundle.main.url(forResource:"ConditionEffectHistory",withExtension:"json"))
        let data = try JSONDecoder().decode(ConditionEffectDataset.self,from:Data(contentsOf:url))
        for year in [2025,2026] {
            let groups = data.groups.filter { $0.year == year }
            XCTAssertEqual(groups.count,year == 2025 ? 2439 : 1884)
            XCTAssertTrue(groups.allSatisfy { ($0.start-2)%6 == 0 && $0.outcomes.count == 6 })
            for (index,a) in additions.enumerated() {
                let hits = groups.filter { a.range.contains(a.condition.value(in:$0.outcomes)) }.count
                XCTAssertEqual(hits,expected[year]![index])
                XCTAssertGreaterThanOrEqual(Double(hits)/Double(groups.count),0.98)
                XCTAssertNotNil(a.condition.highPassHistoricalReference(rangeText:"0-\(a.range.upperBound)"))
                XCTAssertNil(a.condition.highPassHistoricalReference(rangeText:"0-\(a.range.upperBound+1)"))
            }
            XCTAssertEqual(groups.filter { g in additions.allSatisfy { $0.range.contains($0.condition.value(in:g.outcomes)) } }.count,year == 2025 ? 838 : 652)
        }
    }

    func testHundredDefaultsPreserveBothExistingGroupsAndAllTheirSettings() {
        let original = ["svvvSelected":"1","selectedConditionVersionID":"svip10-frozen-160",
            "svip10Enabled":"0","vipConditionsEnabled":"1","svvvHighPass40Enabled":"0",
            "OC_DSEG":"0-3","OCON_DSEG":"1","OC_WPAIR":"0-2","OCON_WPAIR":"0","enteredConditionIDs":"OC_DSEG,OC_WPAIR"]
        let updated = SVVVConditionPackage.addingHighPass98Conditions(to:original)
        for (k,v) in original where k != "enteredConditionIDs" { XCTAssertEqual(updated[k],v) }
        XCTAssertEqual(updated["svvvHighPass100Enabled"],"1")
        XCTAssertEqual(SVVVConditionPackage.addingHighPass98Conditions(to:updated),updated)
        for a in OutcomeCondition.highPass98Additions {
            XCTAssertEqual(updated["OC_"+a.condition.rawValue],"0-\(a.range.upperBound)")
            XCTAssertEqual(updated["OCON_"+a.condition.rawValue],"1")
        }
        var other=original;other["svvvSelected"]="0"
        XCTAssertEqual(SVVVConditionPackage.addingHighPass98Conditions(to:other),other)
    }

    func testThreeMastersIndependentlyControlEightGenerationSetsAndArchives() throws {
        var c = try calibratedDoubleConfig()
        c.svip10AdditionalFilters = SVIP10AdditionalFilters()
        c.outcomeConditions = Dictionary(uniqueKeysWithValues:(OutcomeCondition.highPass93Additions+OutcomeCondition.highPass98Additions).map { ($0.condition,$0.range) })
        c.outcomeConditions[.draws]=0...1
        let saved=c.outcomeConditions
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let hundred=OutcomeCondition.highPass98Additions[0].condition
        for old in [false,true] { for forty in [false,true] { for hundredOn in [false,true] {
            c.conditionPackageEnabled=old;c.highPass93GroupEnabled=forty;c.highPass98GroupEnabled=hundredOn
            let parsed=try FilterConfig.parse(c.normalizedInput)
            XCTAssertEqual(parsed,c)
            XCTAssertEqual(parsed.enabledOutcomeConditions.contains(.draws),old)
            XCTAssertEqual(parsed.enabledOutcomeConditions.contains(.adjacentWinPairs),forty)
            XCTAssertEqual(parsed.enabledOutcomeConditions.contains(hundred),hundredOn)
            let result=SequenceFilterEngine.calculate(parsed,previousContext:nil,captureQueryStages:true)
            let expected=Set(patterns.filter { o in
                (!old || o.filter { $0 == 1 }.count <= 1)
                && (!forty || OutcomeCondition.highPass93Additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) })
                && (!hundredOn || OutcomeCondition.highPass98Additions.allSatisfy { $0.range.contains($0.condition.value(in:o)) })
            })
            XCTAssertEqual(Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) }),expected)
            XCTAssertEqual(result.config.outcomeConditions,saved)
            XCTAssertEqual(result.config.highPass98GroupEnabled,hundredOn)
            XCTAssertEqual(FilterInputDefaults.values(from:parsed)["svvvHighPass100Enabled"],hundredOn ? "1":"0")
            if !old { XCTAssertFalse(parsed.requiresSPData) }
        } } }
        let legacy=c.normalizedInput.components(separatedBy:"|").filter { !$0.hasPrefix("HP98GROUP=") }.joined(separator:"|")
        XCTAssertNil(try FilterConfig.parse(legacy).highPass98GroupEnabled)
    }

    func testHundredGroupRemainsStrictAfterOriginalToleranceAndTXTAdditions() throws {
        var c=try calibratedDoubleConfig()
        c.svip10AdditionalFilters=SVIP10AdditionalFilters()
        let a=OutcomeCondition.highPass98Additions[0]
        c.outcomeConditions=[a.condition:a.range]
        c.highPass93GroupEnabled=false;c.highPass98GroupEnabled=true
        c.allConditionsToleranceEnabled=true;c.allConditionsToleranceRange=0...10
        c.txtCompactEnabled=true;c.maximumTXTAdditionalBets=50
        let result=SequenceFilterEngine.calculate(c,previousContext:nil)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { a.range.contains(a.condition.value(in:Array($0.prefix(6)))) })
    }

    func testHomePassRateHonorsThirdMasterAndKeepsAllSixResults() async throws {
        var c=try calibratedDoubleConfig()
        c.conditionPackageEnabled=false;c.highPass93GroupEnabled=false
        c.svip10AdditionalFilters=SVIP10AdditionalFilters()
        let a=OutcomeCondition.highPass98Additions[0]
        c.outcomeConditions=[a.condition:a.range]
        let patterns=(0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let good=try XCTUnwrap(patterns.first { a.range.contains(a.condition.value(in:$0)) })
        let bad=try XCTUnwrap(patterns.first { !a.range.contains(a.condition.value(in:$0)) })
        let groups=[2025,2026].flatMap { year in [good,bad].enumerated().map { i,o in
            ConditionEffectGroup(year:year,issue:year == 2025 ? "25011":"26011",start:2+i*6,logic:"AAAAAA",outcomes:o,odds:calibrationFixtureOdds)
        } }
        let data=ConditionEffectDataset(version:1,source:"test",groups:groups)
        for on in [false,true] {
            c.highPass98GroupEnabled=on
            let result=try await ConditionEffectAnalysis.passRate(input:c.normalizedInput,dataset:data)
            XCTAssertEqual(result.combined,ConditionPassRateYear(groups:4,hits:on ? 2:4))
        }
    }


    func testForty93RulesAreDistinctNontrivialAndHaveExactCombinedHistory() throws {
        XCTAssertEqual(OutcomeCondition.highPass93Additions.count, 40)
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let masks = OutcomeCondition.highPass93Additions.map { addition in
            patterns.map { addition.range.contains(addition.condition.value(in: $0)) }
        }
        XCTAssertEqual(Set(masks).count, 40)
        XCTAssertTrue(masks.allSatisfy { $0.contains(true) && $0.contains(false) })
        XCTAssertEqual(patterns.filter { o in OutcomeCondition.highPass93Additions.allSatisfy {
            $0.range.contains($0.condition.value(in: o))
        } }.count, 176)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json"))
        let dataset = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
        for year in [2025,2026] {
            let groups = dataset.groups.filter { $0.year == year }
            let hits = groups.filter { group in OutcomeCondition.highPass93Additions.allSatisfy {
                $0.range.contains($0.condition.value(in: group.outcomes))
            } }.count
            XCTAssertEqual(hits, year == 2025 ? 668 : 477)
        }
    }

    func testFortyAndOriginalMastersIndependentlyControlGenerationAndRetainSettings() throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters = SVIP10AdditionalFilters()
        config.outcomeConditions = Dictionary(uniqueKeysWithValues: OutcomeCondition.highPass93Additions.map { ($0.condition, $0.range) })
        config.outcomeConditions[.draws] = 0...1
        let saved = config.outcomeConditions
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        for originalOn in [false,true] {
            for fortyOn in [false,true] {
                config.conditionPackageEnabled = originalOn
                config.highPass93GroupEnabled = fortyOn
                let parsed = try FilterConfig.parse(config.normalizedInput)
                XCTAssertEqual(parsed, config)
                XCTAssertEqual(parsed.enabledOutcomeConditions.contains(.draws), originalOn)
                XCTAssertEqual(parsed.enabledOutcomeConditions.contains(.adjacentWinPairs), fortyOn)
                let result = SequenceFilterEngine.calculate(parsed, previousContext: nil, captureQueryStages: true)
                let expected = Set(patterns.filter { outcomes in
                    (!originalOn || outcomes.filter { $0 == 1 }.count <= 1)
                    && (!fortyOn || OutcomeCondition.highPass93Additions.allSatisfy {
                        $0.range.contains($0.condition.value(in: outcomes))
                    })
                })
                XCTAssertEqual(Set(result.uniqueExpandedBets.map { Array($0.prefix(6)) }), expected)
                XCTAssertEqual(result.config.outcomeConditions, saved)
                XCTAssertEqual(result.config.highPass93GroupEnabled, fortyOn)
                XCTAssertEqual(FilterInputDefaults.values(from: parsed)["svvvHighPass40Enabled"], fortyOn ? "1" : "0")
                if !originalOn { XCTAssertFalse(parsed.requiresSPData) }
            }
        }
        config.conditionPackageEnabled = false
        config.highPass93GroupEnabled = true
        XCTAssertFalse(SequenceFilterEngine.baseFilterFailureReasons(for: [0,0,0,0,0,0], config: config).isEmpty)
        config.highPass93GroupEnabled = false
        XCTAssertTrue(SequenceFilterEngine.baseFilterFailureReasons(for: [0,0,0,0,0,0], config: config).isEmpty)
        let legacy = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("HP93GROUP=") }.joined(separator: "|")
        XCTAssertNil(try FilterConfig.parse(legacy).highPass93GroupEnabled)
    }

    func testFortyGroupCannotBeBypassedByOriginalToleranceOrTXTAdditions() throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters = SVIP10AdditionalFilters()
        config.outcomeConditions = [.adjacentWinPairs:0...2]
        config.highPass93GroupEnabled = true
        config.allConditionsToleranceEnabled = true
        config.allConditionsToleranceRange = 0...10
        config.txtCompactEnabled = true
        config.maximumTXTAdditionalBets = 50
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            OutcomeCondition.adjacentWinPairs.value(in: Array($0.prefix(6))) <= 2
        })
        XCTAssertLessThanOrEqual(result.finalBetCount, 704)
    }

    func testHomePassRateHonorsTwoIndependentMasterSwitches() async throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters = SVIP10AdditionalFilters()
        config.outcomeConditions = [.draws:0...1, .adjacentWinPairs:0...2]
        let groups = [2025,2026].flatMap { year in [3,1].enumerated().map { index, outcome in
            ConditionEffectGroup(year:year, issue:year == 2025 ? "25011" : "26011", start:2 + index * 6,
                logic:"AAAAAA", outcomes:Array(repeating:outcome,count:6), odds:calibrationFixtureOdds)
        } }
        let dataset = ConditionEffectDataset(version:1, source:"test", groups:groups)
        for original in [false,true] {
            for forty in [false,true] {
                config.conditionPackageEnabled = original
                config.highPass93GroupEnabled = forty
                let result = try await ConditionEffectAnalysis.passRate(input:config.normalizedInput, dataset:dataset)
                let expected = original && forty ? 0 : (original || forty ? 2 : 4)
                XCTAssertEqual(result.combined, ConditionPassRateYear(groups:4,hits:expected))
            }
        }
    }

    func testHighPass93MetricsCountOverlapsBoundariesAndSegments() {
        XCTAssertEqual(OutcomeCondition.adjacentWinPairs.value(in: [3,3,3,1,3,3]), 3)
        XCTAssertEqual(OutcomeCondition.adjacentLossPairs.value(in: [0,0,0,1,0,0]), 3)
        XCTAssertEqual(OutcomeCondition.differentTriples.value(in: [3,1,0,3,1,0]), 4)
        XCTAssertEqual(OutcomeCondition.differentTriples.value(in: [3,1]), 0)
        XCTAssertEqual(OutcomeCondition.isolatedWins.value(in: [3,1,3,0,1,3]), 3)
        XCTAssertEqual(OutcomeCondition.isolatedWins.value(in: [3,3,1,0,3,3]), 0)
        XCTAssertEqual(OutcomeCondition.isolatedWins.value(in: [3]), 1)
        XCTAssertEqual(OutcomeCondition.lossSegments.value(in: [0,0,3,0,1,0]), 3)
        for condition in OutcomeCondition.activeCases {
            XCTAssertEqual(condition.value(in: []), 0)
        }
    }

    func testHighPass93DefaultsOnlyAddFiveSwitchesAndPreserveUserChanges() {
        let original = ["svvvSelected":"1", "selectedConditionVersionID":"svip10-frozen-160",
            "OC_DSEG":"0-3", "OCON_DSEG":"1", "svip10ScoreRangeInput":"5.5-7.5",
            "svip10AutomaticDoublePairEnabled":"0", "enteredConditionIDs":"OC_DSEG"]
        let updated = SVVVConditionPackage.addingHighPass93Conditions(to: original)
        for (key, value) in original where key != "enteredConditionIDs" { XCTAssertEqual(updated[key], value) }
        XCTAssertEqual(SVVVConditionPackage.addingHighPass93Conditions(to: updated), updated)
        for (condition, range) in OutcomeCondition.highPass93Additions {
            XCTAssertEqual(updated["OC_" + condition.rawValue], "\(range.lowerBound)-\(range.upperBound)")
            XCTAssertEqual(updated["OCON_" + condition.rawValue], "1")
            XCTAssertEqual(FilterInputDefaults.enabledEditorOutcomeRanges(values: updated)[condition], "\(range.lowerBound)-\(range.upperBound)")
            XCTAssertNotNil(condition.highPassHistoricalReference(rangeText: "\(range.lowerBound)-\(range.upperBound)"))
            XCTAssertNil(condition.highPassHistoricalReference(rangeText: "0-\(range.upperBound + 1)"))
        }
        var other = original; other["svvvSelected"] = "0"
        XCTAssertEqual(SVVVConditionPackage.addingHighPass93Conditions(to: other), other)
    }

    func testHighPass93AnnualCountsAndSixMatchGrouping() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json"))
        let dataset = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
        let expected = [2025:[2303, 2322, 2327, 2313, 2289, 2273, 2292, 2294, 2293, 2293, 2310, 2323, 2272, 2288, 2346, 2327, 2331, 2344, 2312, 2304, 2341, 2374, 2339, 2298, 2323, 2338, 2324, 2374, 2373, 2369, 2386, 2410, 2333, 2341, 2362, 2396, 2374, 2405, 2374, 2387], 2026:[1761, 1810, 1782, 1784, 1753, 1772, 1791, 1780, 1781, 1788, 1783, 1789, 1767, 1760, 1795, 1804, 1808, 1822, 1799, 1797, 1798, 1841, 1824, 1774, 1786, 1789, 1818, 1821, 1826, 1827, 1838, 1857, 1782, 1823, 1806, 1830, 1833, 1865, 1841, 1833]]
        for year in [2025,2026] {
            let groups = dataset.groups.filter { $0.year == year }
            XCTAssertEqual(groups.count, year == 2025 ? 2439 : 1884)
            XCTAssertTrue(groups.allSatisfy { ($0.start - 2) % 6 == 0 && $0.outcomes.count == 6 })
            for (index, addition) in OutcomeCondition.highPass93Additions.enumerated() {
                let hits = groups.filter { addition.range.contains(addition.condition.value(in: $0.outcomes)) }.count
                XCTAssertEqual(hits, expected[year]![index])
                XCTAssertGreaterThan(Double(hits) / Double(groups.count), 0.93)
            }
        }
    }

    func testHighPass93SwitchesAndArchivesMatchProductionBetSets() throws {
        let expected = [704, 704, 687, 697, 685, 648, 660, 665, 677, 677, 677, 677, 690, 693, 693, 693, 693, 693, 696, 701, 701, 701, 702, 704, 704, 704, 704, 704, 704, 704, 704, 704, 708, 708, 709, 713, 713, 713, 714, 720]
        for (index, addition) in OutcomeCondition.highPass93Additions.enumerated() {
            var config = try calibratedDoubleConfig()
            config.svip10AdditionalFilters = SVIP10AdditionalFilters()
            config.outcomeConditions = [addition.condition:addition.range]
            let parsed = try FilterConfig.parse(config.normalizedInput)
            XCTAssertEqual(parsed.outcomeConditions, config.outcomeConditions)
            let result = SequenceFilterEngine.calculate(parsed, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
            XCTAssertEqual(result.finalBetCount, expected[index])
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
                addition.range.contains(addition.condition.value(in: Array($0.prefix(6))))
            })
            config.outcomeConditions = [:]
            XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil,
                currentOutcomeSPs: calibrationFixtureOdds).finalBetCount, 729)
        }
    }

    func testHighPassFiveMetricsCountOverlappingPairsAndDistinctSegments() {
        XCTAssertEqual(OutcomeCondition.adjacentDrawPairs.value(in: [1, 1, 1, 3, 1, 1]), 3)
        XCTAssertEqual(OutcomeCondition.drawSegments.value(in: [1, 1, 1, 3, 1, 1]), 2)
        XCTAssertEqual(OutcomeCondition.nonDrawRun.value(in: [3, 0, 1, 0, 3, 0]), 3)
        XCTAssertEqual(OutcomeCondition.nonDrawRun.value(in: [1, 1, 1, 1, 1, 1]), 0)
        XCTAssertEqual(OutcomeCondition.winDrawSwitches.value(in: [3, 1, 3, 0, 1, 3]), 3)
        XCTAssertEqual(OutcomeCondition.drawLossSwitches.value(in: [1, 0, 1, 3, 1, 0]), 3)
        XCTAssertEqual(OutcomeCondition.drawSegments.value(in: [1, 3, 1, 0, 1, 0]), 3)
        XCTAssertEqual(OutcomeCondition.drawSegments.maximum(matchCount: 6), 3)
        XCTAssertNil(OutcomeCondition.adjacentDrawPairs.highPassHistoricalReference(rangeText: "0-2"))
    }

    func testHighPassFiveDefaultsPreserveExistingSVVVAndDoNotApplyToOtherVersions() {
        let original = ["svvvSelected": "1", "selectedConditionVersionID": "svip10-frozen-160",
            "svip10SumRangeInput": "13-20", "OC_LOSSES": "0-5", "OCON_LOSSES": "1",
            "svip10AutomaticDoublePairEnabled": "0", "enteredConditionIDs": "extra.1"]
        let updated = SVVVConditionPackage.addingHighPassConditions(to: original)
        for (key, value) in original where key != "enteredConditionIDs" { XCTAssertEqual(updated[key], value) }
        XCTAssertEqual(SVVVConditionPackage.addingHighPassConditions(to: updated), updated)
        for (metric, range) in OutcomeCondition.highPassAdditions {
            XCTAssertEqual(updated["OCON_" + metric.rawValue], "1")
            XCTAssertEqual(updated["OC_" + metric.rawValue], "\(range.lowerBound)-\(range.upperBound)")
        }
        var other = original; other["svvvSelected"] = "0"
        XCTAssertEqual(SVVVConditionPackage.addingHighPassConditions(to: other), other)
    }

    func testHighPassFiveProductionSetsAndArchivesHaveExactStandaloneBetCounts() throws {
        let expected = [636, 644, 655, 655, 685]
        for (index, addition) in OutcomeCondition.highPassAdditions.enumerated() {
            var config = try calibratedDoubleConfig()
            config.svip10AdditionalFilters = SVIP10AdditionalFilters()
            config.outcomeConditions = [addition.condition: addition.range]
            let parsed = try FilterConfig.parse(config.normalizedInput)
            XCTAssertEqual(parsed.outcomeConditions, config.outcomeConditions)
            let kept = SequenceFilterEngine.calculate(parsed, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
            XCTAssertEqual(kept.finalBetCount, expected[index])
            XCTAssertTrue(kept.uniqueExpandedBets.allSatisfy {
                addition.range.contains(addition.condition.value(in: Array($0.prefix(6))))
            })
            config.outcomeConditions = [:]
            XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil,
                currentOutcomeSPs: calibrationFixtureOdds).finalBetCount, 729)
        }
    }

    func testHighPassFiveExistingAnnualHistoryMatchesPublishedCounts() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json"))
        let dataset = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
        let expected = [2025: [2254, 2269, 2234, 2255, 2329], 2026: [1752, 1769, 1729, 1739, 1811]]
        for year in [2025, 2026] {
            let groups = dataset.groups.filter { $0.year == year }
            XCTAssertEqual(groups.count, year == 2025 ? 2439 : 1884)
            for (index, addition) in OutcomeCondition.highPassAdditions.enumerated() {
                let hits = groups.filter { addition.range.contains(addition.condition.value(in: $0.outcomes)) }.count
                XCTAssertEqual(hits, expected[year]![index])
                XCTAssertGreaterThanOrEqual(Double(hits) / Double(groups.count), 0.90)
            }
        }
    }

    func testSVVVPackageRestoresAllSwitchesWithoutReusingFixtureOrQueryInputs() throws {
        let original = ["selectedConditionVersionID": "svip10-frozen-160", "svip10Enabled": "1",
            "svip10SumRangeInput": "13-20", "svip10ScoreRangeInput": "5.5-7.5",
            "svip10AutomaticDoublePairEnabled": "0", "svip10CalibratedDoubleSelectionEnabled": "0",
            "svip10NoFourEnabled": "1", "svip10SecondDoubleLowestProbabilityEnabled": "1",
            "svip10DoubleJudgmentFactors": "euro,asianLine", "disabledBasicConditions": "score",
            "OCON_LOSSES": "1", "OC_LOSSES": "0-5", "OCON_LRUN": "0", "OC_LRUN": "1-3",
            "enteredConditionIDs": "", "overallOddsForecastGateEnabled": "0",
            "match1Input": "54", "logicInput": "BBCBDB", "singleMatchInput": "399",
            "beijingSingleIssueInput": "26111", "betMultiplierInput": "2",
            "manualQuerySixOutcomeInput": "010031", "svvvSelected": "1"]
        let package = SVVVConditionPackage.snapshot(from: original)
        let encoded = try PropertyListSerialization.data(fromPropertyList: package, format: .binary, options: 0)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: String])
        var current = original
        current["selectedConditionVersionID"] = "vip19-custom-odds-constitution-top200"
        current["svip10SumRangeInput"] = "15-18"
        current["svip10AutomaticDoublePairEnabled"] = "1"
        current["OCON_LOSSES"] = "0"
        current["OC_LOSSES"] = "1-3"
        current["match1Input"] = "100"
        current["logicInput"] = "AAAAAA"
        current["singleMatchInput"] = "106"
        current["beijingSingleIssueInput"] = "26120"
        current["betMultiplierInput"] = "5"
        current["manualQuerySixOutcomeInput"] = "333333"
        let restored = SVVVConditionPackage.restoring(decoded, onto: current)
        XCTAssertEqual(SVVVConditionPackage.snapshot(from: restored), package)
        for key in ["match1Input", "logicInput", "singleMatchInput", "beijingSingleIssueInput",
                    "betMultiplierInput", "manualQuerySixOutcomeInput"] {
            XCTAssertNil(package[key])
            XCTAssertEqual(restored[key], current[key])
        }
        XCTAssertEqual(restored["svvvSelected"], "1")
        XCTAssertEqual(FilterInputDefaults.enabledEditorOutcomeRanges(values: restored)[.losses], "0-5")
        XCTAssertNil(FilterInputDefaults.enabledEditorOutcomeRanges(values: restored)[.lossRun])
    }

    func testSVVVMasterOffSkipsRetainedSubconditionsAndRestoresSameBetsWhenOn() throws {
        var config = try calibratedDoubleConfig()
        config.outcomeConditions[.losses] = 1...3
        config.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled = true
        config.svip10AdditionalFilters.sixMatchBreakpointRange = 1...5
        let original = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertLessThan(original.finalBetCount, 729)
        config.conditionPackageEnabled = false
        let parsedOff = try FilterConfig.parse(config.normalizedInput)
        let unfiltered = SequenceFilterEngine.calculate(parsedOff, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertEqual(unfiltered.finalBetCount, 729)
        XCTAssertEqual(parsedOff.outcomeConditions[.losses], 1...3)
        XCTAssertTrue(parsedOff.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled)
        config.conditionPackageEnabled = true
        let restored = SequenceFilterEngine.calculate(try FilterConfig.parse(config.normalizedInput), previousContext: nil,
            currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertEqual(Set(original.uniqueExpandedBets), Set(restored.uniqueExpandedBets))
    }

    func testMarketRecordsKeepWilliamEuroAndMacauAsianSourcesSeparate() throws {
        let html = #"var liveOddsList = {"123":{"3":["1.30","5.50","8.50"],"293":["1.33","5.50","8.50"]},"456":{"3":["2","3","4"]}};"#
        let quotes = try MarketRecordsClient.europeanQuotes(html:html)
        XCTAssertEqual(quotes["123"],[1.33,5.5,8.5]);XCTAssertNil(quotes["456"])
        var point = MarketRecordSample(capturedAt:Date(),european:[2,3,4])
        XCTAssertTrue(point.isValid)
        point.europeanCompanyID = 3;XCTAssertFalse(point.isValid)
        point.europeanCompanyID = 293;point.asianCompanyID = 3;XCTAssertFalse(point.isValid)
        let macau = try DoubleMarketDataClient.parseQuote(data:Data(#"[[[0.9,"半球",0.9],[0.8,"半球/一球",1.0]],[[2,3,4],[1.8,3.5,4.5]]]"#.utf8),companyID:5)
        XCTAssertEqual(macau.companyID,5);XCTAssertEqual(macau.openingAsian?.line,-0.5)
        XCTAssertEqual(macau.currentAsian?.line,-0.75)
    }

    func testMarketRecordsStagesKeepTwoSourceClocksAndRejectLaterPrices() {
        let now=Date()
        let oldEuro=MarketRecordSample(capturedAt:now.addingTimeInterval(-10),european:[2,3,4])
        let asian=MarketRecordSample(capturedAt:now.addingTimeInterval(-5),european:[],
            asian:DoubleAsianPoint(homeWater:0.8,line:-0.5,awayWater:1.0))
        let laterEuro=MarketRecordSample(capturedAt:now.addingTimeInterval(1),european:[1.1,9,20])
        let row=MarketMatchRecord(issue:"26109",number:2,fixtureID:"123",league:"测试",home:"主",away:"客",
            kickoff:now.addingTimeInterval(7200),handicap:0,status:"未",homeScore:nil,awayScore:nil,
            samples:[oldEuro,asian,laterEuro])
        XCTAssertEqual(row.stage(hoursBefore:2)?.european,[2,3,4])
        XCTAssertEqual(row.stage(hoursBefore:2)?.capturedAt,oldEuro.capturedAt)
        XCTAssertEqual(row.stage(hoursBefore:2,asian:true)?.capturedAt,asian.capturedAt)
        XCTAssertNil(row.stage(hoursBefore:24))
        XCTAssertNil(row.stage(hoursBefore:24,asian:true))
        XCTAssertNil(row.stage(hoursBefore:2)?.openingEuropean)
    }

    func testMarketRecordsRegisterFirstSelectTwoAndFreezeAtCutoff() throws {
        let now=Date()
        let metadata=(2...7).map { n in MarketMatchRecord(issue:"26109",number:n,fixtureID:String(9000+n),league:"测试",
            home:"主",away:"客",kickoff:now.addingTimeInterval(10800),handicap:0,status:"未",homeScore:nil,awayScore:nil) }
        var archive=MarketRecordsArchive()
        archive.register(metadata,now:now.addingTimeInterval(-120))
        XCTAssertEqual(archive.candidates.count,1);XCTAssertFalse(archive.candidates[0].exploratory)
        var sampled=metadata
        for index in sampled.indices {
            sampled[index].samples=[MarketRecordSample(capturedAt:now.addingTimeInterval(-60),european:[1.9,3.4,4]),
                MarketRecordSample(capturedAt:now.addingTimeInterval(-10),european:[1.8,3.5,4.5]),
                MarketRecordSample(capturedAt:now.addingTimeInterval(-8),european:[],
                    asian:DoubleAsianPoint(homeWater:0.85,line:-0.75,awayWater:1),
                    openingAsian:DoubleAsianPoint(homeWater:0.9,line:-0.5,awayWater:0.9))]
        }
        archive.merge(sampled);archive.updateRecommendations(now:now)
        let prediction=try XCTUnwrap(archive.recommendations.first)
        XCTAssertEqual(prediction.kind,"prospective");XCTAssertEqual(prediction.legs.count,2)
        XCTAssertEqual(Set(prediction.legs.map(\.number)).count,2)
        XCTAssertEqual(prediction.fixtures.map(\.number),Array(2...7))
        XCTAssertTrue(prediction.legs.allSatisfy { [[2,3],[2,4],[3,4]].contains($0.mappedPair) })
        archive.records[0].samples=[]
        archive.updateRecommendations(now:now.addingTimeInterval(10))
        XCTAssertEqual(archive.recommendations.first?.madeAt,prediction.madeAt)
        archive.updateRecommendations(now:prediction.cutoff.addingTimeInterval(1))
        XCTAssertEqual(archive.recommendations.first?.madeAt,prediction.madeAt)
        XCTAssertEqual(archive.recommendations.first?.legs.map(\.retained),prediction.legs.map(\.retained))
        var scored=sampled
        for i in scored.indices { scored[i].homeScore=9;scored[i].awayScore=0;scored[i].status="下80" }
        let inPlay=try XCTUnwrap(MarketRecordSelector.recommend(scored,candidate:archive.candidates[0],now:now))
        XCTAssertEqual(inPlay.legs.map(\.retained),prediction.legs.map(\.retained))
        XCTAssertEqual(inPlay.kind,"archiveReference")
        var oldEvidence=sampled
        oldEvidence[5].samples=oldEvidence[5].samples.map { point in var p=point;p.capturedAt=now.addingTimeInterval(-200);return p }
        XCTAssertEqual(MarketRecordSelector.recommend(oldEvidence,candidate:archive.candidates[0],now:now)?.kind,"archiveReference")
        var partial=sampled
        partial[5].samples=partial[5].samples.filter { $0.asian == nil }
        XCTAssertEqual(MarketRecordSelector.recommend(partial,candidate:archive.candidates[0],now:now)?.kind,"prospective")
        XCTAssertEqual(MarketRecordSelector.recommend(partial,candidate:archive.candidates[0],now:now)?.legs.count,2)
        var inspected=MarketRecordsArchive(records:sampled)
        inspected.register(metadata,now:now)
        XCTAssertEqual(inspected.candidates.count,1)
        XCTAssertFalse(inspected.candidates[0].exploratory)
        XCTAssertEqual(inspected.candidates[0].priorObservedSamples,true)
        var invalid=archive
        invalid.recommendations[0].legs[0].number=999
        XCTAssertThrowsError(try invalid.validate())
    }

    func testMarketRecordsJointHitsUseOriginalHandicapAndKeepMissingGroups() {
        let now=Date(),kickoff=Date().addingTimeInterval(-86400)
        var rows=(2...7).map { n in MarketMatchRecord(issue:"26109",number:n,fixtureID:String(9000+n),league:"测试",
            home:"主",away:"客",kickoff:kickoff,handicap:2,status:"完",homeScore:0,awayScore:n==3 ? 1:0) }
        let identities=rows.map { r in MarketRecordIdentity(number:r.number,fixtureID:r.fixtureID,handicap:0,kickoff:kickoff) }
        let candidate=MarketRecordCandidate(issue:"26109",first:2,registeredAt:kickoff.addingTimeInterval(-15000),
            cutoff:kickoff.addingTimeInterval(-7200),fixtures:identities,exploratory:false)
        let legs=[2,3].map { n in MarketRecordLeg(number:n,handicap:0,mappedPair:[2,3],retained:[3,1],evidenceAt:kickoff.addingTimeInterval(-11000)) }
        let forecast=MarketRecordRecommendation(issue:"26109",first:2,madeAt:kickoff.addingTimeInterval(-10000),
            cutoff:candidate.cutoff,fixtures:identities,legs:legs,kind:"prospective")
        var archive=MarketRecordsArchive(records:rows,candidates:[candidate],recommendations:[forecast])
        var stats=MarketRecordStatistics.calculate(archive,year:2026)
        XCTAssertEqual(stats.registered,1);XCTAssertEqual(stats.settled,1)
        XCTAssertEqual(stats.firstHits,1);XCTAssertEqual(stats.secondHits,0);XCTAssertEqual(stats.hits,0)
        XCTAssertEqual(stats.rate,0) // One verified miss, unlike a zero-result sample.
        rows[5].status="下80";archive.records=rows
        stats=MarketRecordStatistics.calculate(archive,year:2026)
        XCTAssertNil(stats.rate);XCTAssertEqual(stats.pending,1)
        archive.recommendations=[]
        stats=MarketRecordStatistics.calculate(archive,year:2026)
        XCTAssertEqual(stats.registered,1);XCTAssertEqual(stats.unavailable,1);XCTAssertNil(stats.rate)
        _=now
    }

    private func forwardTestForecast(at now: Date, factors: Set<DoubleJudgmentFactor> = [.euro]) throws -> (DoubleForwardForecast, [BeijingSingleMatch]) {
        let matches = (1...6).map { number in
            BeijingSingleMatch(issue: "26108", matchNumber: String(number), fixtureID: "forward-\(number)",
                league: "测试", matchTime: "10-29 21:00", status: "未", homeTeam: "主", awayTeam: "客",
                handicap: 1, referenceSP: [], marketOdds: [2,3,4])
        }
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, factors: factors)?.automaticDoubleSelection)
        return (try XCTUnwrap(DoubleForwardForecast.make(selection: selection, matches: matches,
            calibrated: false, factors: factors, now: now)), matches)
    }
    private func forwardFinished(_ matches: [BeijingSingleMatch], status: String = "完", home: Int = 0,
                                 away: Int = 1, fixtureSuffix: String = "") -> [BeijingSingleMatch] {
        matches.map { match in BeijingSingleMatch(issue: match.issue, matchNumber: match.matchNumber,
            fixtureID: match.fixtureID + fixtureSuffix, league: match.league, matchTime: match.matchTime,
            status: status, homeTeam: match.homeTeam, awayTeam: match.awayTeam, handicap: -9,
            referenceSP: [], marketOdds: [], homeScore: home, awayScore: away) }
    }
    func testForwardValidationRejectsBackfillAndReopenedGroupsAndRestoresAfterRestart() async throws {
        let cutoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: "10-29 21:00"))
        let now = cutoff.addingTimeInterval(-4*3600)
        let (forecast, _) = try forwardTestForecast(at: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleForwardValidationStore(directory: directory)
        let recorded = try await store.record(forecast, now: now)
        XCTAssertTrue(recorded)
        let duplicate = try await store.record(forecast, now: now)
        XCTAssertFalse(duplicate)
        let afterStart = try await store.record(forecast, now: cutoff.addingTimeInterval(1))
        XCTAssertFalse(afterStart)
        let restored = DoubleForwardValidationStore(directory: directory)
        let report = try await restored.summary(cohort: forecast.cohortKey, now: now)
        XCTAssertEqual(report.registered, 1); XCTAssertEqual(report.settled, 0); XCTAssertEqual(report.pending, 1)
        XCTAssertNil(report.confidenceInterval)
        let (backdated, _) = try forwardTestForecast(at: now.addingTimeInterval(-600))
        let backfill = try await restored.record(backdated, now: now)
        XCTAssertFalse(backfill)
        let shifted = DoubleForwardForecast(id: UUID(), version: forecast.version, issue: forecast.issue,
            first: forecast.first, recordedAt: cutoff.addingTimeInterval(10), cutoff: cutoff.addingTimeInterval(3600),
            calibrated: forecast.calibrated, factors: forecast.factors,
            fixtures: forecast.fixtures.map { .init(number: $0.number, fixtureID: $0.fixtureID, handicap: $0.handicap,
                cutoff: cutoff.addingTimeInterval(3*3600), logic: $0.logic, odds: $0.odds, marketCapturedAt: nil) },
            selected: forecast.selected, baseline: forecast.baseline)
        XCTAssertTrue(shifted.isValid)
        let reopened = try await restored.record(shifted, now: shifted.recordedAt)
        XCTAssertFalse(reopened)
    }
    func testForwardValidationUsesFinalScoresOriginalHandicapAndPairedDenominator() async throws {
        let cutoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: "10-29 21:00"))
        let now = cutoff.addingTimeInterval(-4*3600), later = cutoff.addingTimeInterval(4*3600)
        let (forecast, matches) = try forwardTestForecast(at: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleForwardValidationStore(directory: directory)
        _ = try await store.record(forecast, now: now)
        try await store.reconcile(matches: forwardFinished(matches, status: "下80"), now: later)
        try await store.reconcile(matches: forwardFinished(matches, status: "未完赛"), now: later)
        try await store.reconcile(matches: forwardFinished(matches, fixtureSuffix: "wrong"), now: later)
        try await store.reconcile(matches: Array(forwardFinished(matches).dropLast()), now: later)
        var report = try await store.summary(cohort: forecast.cohortKey, now: later)
        XCTAssertEqual(report.settled, 0)
        let completed = forwardFinished(matches)
        let proof = try XCTUnwrap(DoubleForwardSettlement.make(forecast: forecast, matches: completed, now: later))
        // 0:1 with original +1 is a draw (1); the refreshed source's -9 must be ignored.
        XCTAssertEqual(proof.outcomes(for: forecast)?.values.sorted(), [1,1,1,1,1,1])
        try await store.reconcile(matches: completed, now: later)
        try await store.reconcile(matches: completed, now: later.addingTimeInterval(60))
        report = try await store.summary(cohort: forecast.cohortKey, now: later.addingTimeInterval(60))
        let selectedHit = forecast.selected.allSatisfy { $0.retained.contains(1) }
        let baseHit = forecast.baseline.allSatisfy { $0.retained.contains(1) }
        XCTAssertEqual(report.settled, 1); XCTAssertEqual(report.registered, 1)
        XCTAssertEqual(report.selectedHits, selectedHit ? 1 : 0); XCTAssertEqual(report.baselineHits, baseHit ? 1 : 0)
        XCTAssertLessThan(try XCTUnwrap(report.confidenceInterval).lowerBound, 0.75)
        // A source correction replaces the result used for this one group, never adds a second sample.
        try await store.reconcile(matches: forwardFinished(matches, home: 0, away: 9), now: later.addingTimeInterval(120))
        let corrected = try await store.summary(cohort: forecast.cohortKey, now: later.addingTimeInterval(120))
        XCTAssertEqual(corrected.settled, 1)
        XCTAssertEqual(corrected.selectedHits, forecast.selected.allSatisfy { $0.retained.contains(0) } ? 1 : 0)
        XCTAssertNil(DoubleForwardSettlement.make(forecast: forecast, matches: completed, now: now))
        XCTAssertNil(DoubleForwardForecast.make(selection: try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(
            firstMatchNumber: 1, matches: matches, calibrated: false)?.automaticDoubleSelection), matches: completed,
            calibrated: false, factors: [.euro], now: now))
    }
    func testForwardValidationChoosesLatestGroupBeforeCohortAndKeepsRawEvents() async throws {
        let cutoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: "10-29 21:00"))
        let now = cutoff.addingTimeInterval(-4*3600)
        let (first, matches) = try forwardTestForecast(at: now)
        let (second, _) = try forwardTestForecast(at: now.addingTimeInterval(60), factors: [.asianLine, .books])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleForwardValidationStore(directory: directory)
        _ = try await store.record(first, now: now)
        _ = try await store.record(second, now: second.recordedAt)
        let later = cutoff.addingTimeInterval(4*3600)
        try await store.reconcile(matches: forwardFinished(matches), now: later)
        let old = try await store.summary(cohort: first.cohortKey, now: later)
        let current = try await store.summary(cohort: second.cohortKey, now: later)
        XCTAssertEqual(old.registered, 0); XCTAssertEqual(old.settled, 0)
        XCTAssertEqual(current.registered, 1); XCTAssertEqual(current.settled, 1)
        XCTAssertEqual(current.rows.first?.forecast.id, second.id)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("ledger-v1.json"))) as? [String:Any]
        XCTAssertEqual((raw?["forecasts"] as? [Any])?.count, 2)
        XCTAssertEqual((raw?["settlements"] as? [Any])?.count, 1)
        let due = try await store.issuesDue(now: later)
        XCTAssertEqual(due, ["26108"])
    }
    func testForwardValidationRequiresExplicitScoreboardStatusAndPreservesCorruptLedger() async throws {
        let trade = #"<tr class="vs_lines" fid="900001" value="{index:'1',endTime:'2026-10-29 21:00',scheduleDate:'2026-10-29',rangqiuNum:'0'}"><td>1</td><td>测试</td><td>10-29 21:00</td><td>主</td><td>0:0</td><td>客</td></tr>"#
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseScoreboard(html: trade, issue: "26108", requiringExplicitStatus: true))
        let cells = ["1", "测试", "", "10-29 21:00", "下80", "主", "<a>0</a>:<a>1</a>", "客", "", ""]
        let html = "<select id=\"sel_expect\"><option value=\"26108\">26108</option></select><tr id=\"a900001\">" + cells.map { "<td>\($0)</td>" }.joined() + "</tr>"
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseScoreboard(html: html, issue: "26107", requiringExplicitStatus: true))
        let inPlay = try FiveHundredBeijingSingleClient.parseScoreboard(html: html, issue: "26108", requiringExplicitStatus: true)
        XCTAssertEqual(inPlay.first?.status, "下80"); XCTAssertFalse(QueryFinalityGate.isFinallyEnded(try XCTUnwrap(inPlay.first)))
        let ended = try FiveHundredBeijingSingleClient.parseScoreboard(html: html.replacingOccurrences(of: "下80", with: "完"),
            issue: "26108", requiringExplicitStatus: true)
        XCTAssertTrue(QueryFinalityGate.isFinallyEnded(try XCTUnwrap(ended.first)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ledger-v1.json"), damaged = Data("broken-data".utf8)
        try damaged.write(to: file)
        let store = DoubleForwardValidationStore(directory: directory)
        let cutoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: "10-29 21:00"))
        let now = cutoff.addingTimeInterval(-4*3600)
        let (forecast, _) = try forwardTestForecast(at: now)
        do { _ = try await store.record(forecast, now: now); XCTFail("Corrupt history must not be replaced") }
        catch { XCTAssertEqual(try Data(contentsOf: file), damaged) }
    }
    func testTwoHourWindowRejectsLaterQuotesRecoversEarlierArchiveAndStillSelectsTwoDoubles() async throws {
        let now = Date(), time = now.addingTimeInterval(3600)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8*3600)
        formatter.dateFormat = "yyMM"; let issue = formatter.string(from: time) + "1"
        formatter.dateFormat = "MM-dd HH:mm"; let text = formatter.string(from: time)
        let kickoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: issue, matchTime: text))
        let cutoff = kickoff.addingTimeInterval(-7200)
        let matches = (1...6).map { BeijingSingleMatch(issue: issue, matchNumber: String($0), fixtureID: String(9_000_000+$0),
            league: "测试", matchTime: text, status: "未", homeTeam: "主", awayTeam: "客", handicap: 0,
            referenceSP: [], marketOdds: [2,3,4]) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleMarketSnapshotStore(directory: directory)
        let books = marketEvidence().books
        var earlier: [DoubleMarketEvidence] = [], late: [DoubleMarketEvidence] = []
        for number in 1...6 {
            let before = DoubleMarketEvidence(issue: issue, number: number, fixtureID: String(9_000_000+number), handicap: 0,
                capturedAt: cutoff.addingTimeInterval(-300), kickoff: kickoff, books: books, bettingShares: [])
            let after = DoubleMarketEvidence(issue: issue, number: number, fixtureID: before.fixtureID, handicap: 0,
                capturedAt: now.addingTimeInterval(-60), kickoff: kickoff, books: books, bettingShares: [])
            _ = await store.store(before); _ = await store.store(after)
            earlier.append(before); late.append(after)
        }
        XCTAssertEqual(DoubleMarketDataClient.verifiedEvidence(late, matches: matches, firstMatchNumber: 1).count, 6)
        XCTAssertTrue(DoubleMarketDataClient.verifiedEvidence(late, matches: matches, firstMatchNumber: 1, leadTime: 7200).isEmpty)
        let fetched = await DoubleMarketDataClient.fetch(matches: matches, factors: [.euro], now: now, includeTrends: true,
            leadTime: 7200, store: store, quoteLoader: { _,_ in XCTFail("No network after T-2 hours"); throw GoalModelError.invalidResponse })
        XCTAssertEqual(fetched.evidence.count, 6)
        XCTAssertTrue(fetched.evidence.allSatisfy { $0.capturedAt == cutoff.addingTimeInterval(-300) })
        XCTAssertTrue(fetched.notes.values.allSatisfy { $0.contains("赛前2小时") })
        let selected = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1,
            matches: matches, calibrated: false, factors: [.euro], evidence: fetched.evidence)?.automaticDoubleSelection)
        XCTAssertEqual(selected.matches.map(\.number), [1,2,3,4,5,6]); XCTAssertEqual(selected.choices.count, 2)
        XCTAssertNil(DoubleForwardForecast.make(selection: selected, matches: matches, calibrated: false, factors: [.euro], now: now))
        let base = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1, matches: matches, calibrated: false)?.automaticDoubleSelection)
        let preWindow = try XCTUnwrap(DoubleForwardForecast.make(selection: base, matches: matches,
            calibrated: false, factors: [.euro], now: cutoff.addingTimeInterval(-600)))
        XCTAssertEqual(preWindow.cutoff, cutoff)
    }
    func testBundledConditionHistoryContainsAll4323RealGroups() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConditionEffectHistory", withExtension: "json"))
        let data = try JSONDecoder().decode(ConditionEffectDataset.self, from: Data(contentsOf: url))
        XCTAssertEqual(data.version, 1)
        XCTAssertEqual(data.groups.filter { $0.year == 2025 }.count, 2439)
        XCTAssertEqual(data.groups.filter { $0.year == 2026 }.count, 1884)
        XCTAssertEqual(Set(data.groups.map { "\($0.issue):\($0.start)" }).count, 4323)
        XCTAssertTrue(data.groups.allSatisfy { $0.start % 6 == 2 && $0.odds.count == 6 && $0.outcomes.count == 6
            && $0.odds.allSatisfy { $0.count == 3 && $0.allSatisfy { $0.isFinite && $0 > 0 } } })
    }
    func testAutomaticDoublePairsStayWithinContinuousSixAndAreDeterministic() throws {
        let pairs: [(LogicMapping, [Double], [Int])] = [(.a, [2, 3, 12], [2,3]), (.a, [2,12,3], [2,4]), (.a,[12,2,3],[3,4])]
        for (logic, odds, expected) in pairs {
            let choice = try XCTUnwrap(AutomaticDoubleSelector.choice(.init(number: 1, logic: logic, odds: odds), calibrated: false))
            XCTAssertEqual(choice.mappedPair, expected)
            XCTAssertEqual(choice.retainedOutcomes.count, 2)
        }
        let pool = (2...34).map { number in AutomaticDoubleCandidate(number: number, logic: .a,
            odds: number == 25 || number == 31 || number == 33 ? [1.1,2,100] : [2,3,4]) }
        let selected = try XCTUnwrap(AutomaticDoubleSelector.recommend(first: 2, candidates: pool, excluding: [25], calibrated: true))
        XCTAssertEqual(selected.candidateCount, 6)
        XCTAssertEqual(selected.choices.first?.number, 2)
        XCTAssertEqual(selected.matches.map(\.number), [2,3,4,5,6,7])
        XCTAssertEqual(selected, AutomaticDoubleSelector.recommend(first: 2, candidates: pool.reversed(), excluding: [25], calibrated: true))
        XCTAssertNil(AutomaticDoubleSelector.recommend(first: 2, candidates: Array(pool.dropFirst()), calibrated: true))
        XCTAssertNil(AutomaticDoubleSelector.recommend(first: 2, candidates: Array(pool.prefix(5)), calibrated: true))
        XCTAssertNil(AutomaticDoubleSelector.choice(.init(number: 1, logic: .a, odds: [0,2,3]), calibrated: true))
        XCTAssertNil(AutomaticDoubleSelector.recommend(first: 2, candidates: pool.filter { $0.number != 4 }, calibrated: true))
        XCTAssertNil(AutomaticDoubleSelector.recommend(first: 2, candidates: pool, excluding: [4], calibrated: true))

    }

    func testAutomaticLiveDoublesIgnoreResultsAndRespectSeventh() throws {
        let matches = (2...35).map { number in BeijingSingleMatch(issue: "26108", matchNumber: String(number),
            fixtureID: "test-\(number)", league: "test", matchTime: "10-29 21:00", status: "未",
            homeTeam: "主", awayTeam: "客", handicap: 0, referenceSP: [], marketOdds: number == 25 ? [1.1,2,100] : [2,3,4]) }
        let selected = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 2,
            matches: matches, excludingMatchNumbers: [25], calibrated: true))
        let completed = matches.map { match in BeijingSingleMatch(issue: match.issue, matchNumber: match.matchNumber,
            fixtureID: match.fixtureID, league: match.league, matchTime: match.matchTime, status: "已结束",
            homeTeam: match.homeTeam, awayTeam: match.awayTeam, handicap: match.handicap, referenceSP: [999,888,777],
            marketOdds: match.marketOdds, homeScore: 9, awayScore: 8, settledSP: 888) }
        XCTAssertEqual(selected, VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 2,
            matches: completed, excludingMatchNumbers: [25], calibrated: true))
        XCTAssertEqual(selected.mainMatchNumbers.count, 6)
        XCTAssertFalse(selected.mainMatchNumbers.contains(25))
        XCTAssertFalse(selected.mainMatchNumbers.contains { $0 >= 32 })
        XCTAssertEqual(selected.automaticDoubleSelection?.candidateCount, 6)
        XCTAssertEqual(selected.mainMatchNumbers, [2,3,4,5,6,7])
        XCTAssertNil(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 2, matches: matches, excludingMatchNumbers: [4], calibrated: true))
    }

    func testAutomaticContinuousDoublesMaximizeJointCoverageAcrossEveryMappedPair() throws {
        let candidates = (0..<6).map { index in AutomaticDoubleCandidate(number: index + 20,
            logic: LogicMapping.allCases[index % 4], odds: calibrationFixtureOdds[index]) }
        for calibrated in [false, true] {
            let selected = try XCTUnwrap(AutomaticDoubleSelector.recommend(first: 20, candidates: candidates, calibrated: calibrated))
            XCTAssertEqual(selected.matches.map(\.number), [20,21,22,23,24,25])
            XCTAssertEqual(Set(selected.choices.map(\.number)).count, 2)
            var bruteForceMaximum = 0.0
            for first in 0..<5 {
                for second in (first + 1)..<6 {
                    for pairA in [[2,3],[2,4],[3,4]] {
                        for pairB in [[2,3],[2,4],[3,4]] {
                            var product = 1.0
                            for (index, pair) in [(first, pairA), (second, pairB)] {
                                let match = candidates[index]
                                let probabilities = try XCTUnwrap(AutomaticDoubleSelector.probabilities(odds: match.odds, calibrated: calibrated))
                                product *= [3,1,0].enumerated().filter { pair.contains(match.logic.value(for: $0.element)) }
                                    .reduce(0.0) { $0 + probabilities[$1.offset] }
                            }
                            bruteForceMaximum = max(bruteForceMaximum, product)
                        }
                    }
                }
            }
            XCTAssertEqual(selected.estimatedJointCoverage, bruteForceMaximum, accuracy: 1e-12)
        }
    }

    func testAutomaticDoubleEngineRoundTripAndModelIndependence() throws {
        var config = try calibratedDoubleConfig(enabled: false)
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip10AutomaticDoublePairEnabled"], "1")
        let legacy = config.normalizedInput.components(separatedBy: "|").filter { !$0.hasPrefix("S10AUTOPAIR=") }.joined(separator: "|")
        XCTAssertFalse(try FilterConfig.parse(legacy).svip10AdditionalFilters.automaticDoublePairEnabled)
        let choices = config.automaticDoubleChoices(in: calibrationFixtureOdds)
        XCTAssertEqual(choices.count, 2)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeProbabilities: Array(repeating: [0.001,0.998,0.001], count: 6), currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertEqual(result.finalBetCount, 324)
        for choice in choices {
            XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { choice.choice.retainedOutcomes.contains($0[choice.position - 1]) })
        }
        let second = try XCTUnwrap(SequenceFilterEngine.svip10SecondDoubleSelection(config: config,
            currentOutcomeProbabilities: Array(repeating: [0,1,0], count: 6), customOdds: calibrationFixtureOdds))
        XCTAssertEqual(second.position, choices[1].position)
        XCTAssertEqual(second.removedOutcome, choices[1].choice.removedOutcome)
        XCTAssertFalse(second.usesModelProbability)
    }

    func testAutomaticContinuousHistoricalGroupsAndJointRateMatchEngine() async throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        let groups = [2025,2026].flatMap { year in (0..<3).map { index in
            ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: 2 + index * 6,
                logic: "AAAAAA", outcomes: Array(repeating: index == 0 ? 0 : 3, count: 6),
                odds: index == 2 ? Array(repeating: [1.1,2,100], count: 6) : calibrationFixtureOdds)
        } }
        let data = ConditionEffectDataset(version: 1, source: "test", groups: groups)
        let template = try ConditionEffectAnalysis.template(config.normalizedInput)
        let selected = try ConditionEffectAnalysis.evaluatedGroups(template: template, dataset: data)
        XCTAssertEqual(selected.candidateCounts, [6,6,6,6,6,6])
        XCTAssertEqual(selected.groups.map(\.start), groups.map(\.start))
        XCTAssertEqual(selected.groups.map(\.odds), groups.map(\.odds))
        let changed = ConditionEffectDataset(version: 1, source: "test", groups: groups.map {
            ConditionEffectGroup(year: $0.year, issue: $0.issue, start: $0.start, logic: $0.logic, outcomes: Array(repeating: 1, count: 6), odds: $0.odds)
        })
        let selectedChanged = try ConditionEffectAnalysis.evaluatedGroups(template: template, dataset: changed)
        XCTAssertEqual(selected.groups.map(\.matchNumbers), selectedChanged.groups.map(\.matchNumbers))
        let summary = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: data)
        XCTAssertTrue(summary.usesAutomaticPairs)
        XCTAssertEqual(summary.candidateCountRange, 6...6)
        var hits = 0
        for group in selected.groups {
            var fields = config.normalizedInput.components(separatedBy: "|")
            fields[0] = (group.start..<(group.start + 6)).map(String.init).joined(separator: ",")
            fields[1] = group.logic
            fields = fields.map { $0 == "7:3" ? "1:3" : $0 }
            let replay = SequenceFilterEngine.calculate(try FilterConfig.parse(fields.joined(separator: "|")), previousContext: nil, currentOutcomeSPs: group.odds)
            if replay.uniqueExpandedBets.contains(where: { Array($0.prefix(6)) == group.outcomes }) { hits += 1 }
        }
        XCTAssertEqual(summary.twoDoubleCombined, ConditionPassRateYear(groups: 6, hits: hits))
        XCTAssertEqual(summary.combined, summary.twoDoubleCombined)
        config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled = false
        let disabled = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: data)
        XCTAssertFalse(disabled.usesAutomaticPairs)
        XCTAssertEqual(disabled.twoDoubleCombined.groups, 0)
        let report = try await ConditionEffectAnalysis.analyze(input: template.normalizedInput, dataset: data)
        XCTAssertEqual(report.counts[2025]?["extra.13"]?.groups, 3)
    }

    private func marketEvidence(number: Int = 1, shares: [Double] = []) -> DoubleMarketEvidence {
        let a = DoubleAsianPoint(homeWater: 1.03, line: 0, awayWater: 0.78)
        let b = DoubleAsianPoint(homeWater: 0.78, line: -1, awayWater: 1.03)
        let books = [3,5,280].map { DoubleBookQuote(companyID: $0, openingEuropean: [7,4,1.5],
            currentEuropean: [1.8,3.8,5], openingAsian: a, currentAsian: b) }
        return DoubleMarketEvidence(issue: "24111", number: number, fixtureID: String(1_000_000 + number), handicap: 0,
            capturedAt: Date(timeIntervalSince1970: 1_730_000_000), kickoff: Date(timeIntervalSince1970: 1_730_003_600),
            books: books, bettingShares: shares)
    }

    func testDoubleMarketQuotesParseOpeningCurrentAndAsianSigns() throws {
        let data = Data(#"[[[1.03,"受一球",0.78],[0.97,"受半球/一球",0.82]],[[7.5,3.9,1.45],[5,3.6,1.7]],[[0.93,"2/2.5",0.88],[0.9,"2/2.5",0.9]]]"#.utf8)
        let q = try DoubleMarketDataClient.parseQuote(data: data, companyID: 3)
        XCTAssertEqual(q.openingEuropean, [7.5,3.9,1.45]); XCTAssertEqual(q.currentEuropean, [5,3.6,1.7])
        XCTAssertEqual(q.openingAsian?.line, 1); XCTAssertEqual(q.currentAsian?.line, 0.75)
        XCTAssertEqual(DoubleJudgmentScorer.asianLine("半球/一球"), -0.75)
        XCTAssertEqual(DoubleJudgmentScorer.asianLine("平手/半球"), -0.25)
        XCTAssertNil(DoubleJudgmentScorer.asianLine("封"))
        XCTAssertThrowsError(try DoubleMarketDataClient.parseQuote(data: Data("[[],[[true,3,4],[2,3,4]]]".utf8), companyID: 3))
    }

    func testDoubleMarketEvidenceRejectsInPlayAndUnknownFundsAreNeverInferred() throws {
        let evidence = marketEvidence()
        XCTAssertTrue(evidence.isValid)
        XCTAssertEqual(DoubleMarketEvidence.decoded(DoubleMarketEvidence.encoded([evidence])), [evidence])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as! [String: Any]
        object["capturedAt"] = object["kickoff"]
        let poisoned = try JSONDecoder().decode(DoubleMarketEvidence.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(poisoned.isValid)
        XCTAssertNil(DoubleMarketEvidence.decoded(DoubleMarketEvidence.encoded([poisoned])))
        let candidate = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [3,3,3], evidence: evidence)
        let unavailable: Set<DoubleJudgmentFactor> = [.funds,.crowd,.reverse]
        let rows = DoubleJudgmentScorer.assessments(candidate, calibrated: true, factors: unavailable)
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(rows.allSatisfy { !$0.available && $0.adjustment == [0,0,0] })
        XCTAssertNil(evidence.bettingAmounts); XCTAssertNil(evidence.publishedShares)
        let baseline = try XCTUnwrap(AutomaticDoubleSelector.probabilities(odds: candidate.odds, calibrated: true))
        let scores = try XCTUnwrap(DoubleJudgmentScorer.scores(candidate, calibrated: true, factors: unavailable))
        for index in 0..<3 { XCTAssertEqual(scores[index], baseline[index], accuracy: 1e-12) }
    }

    func testDoubleMarketFactorsSwitchOffExactlyAndChoiceSnapshotRoundTrips() throws {
        let factors: Set<DoubleJudgmentFactor> = [.euro,.asianLine,.asianWater]
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.doubleJudgmentFactors = factors
        config.svip10AdditionalFilters.doubleMarketEvidence = [marketEvidence(number: 3), marketEvidence(number: 4)]
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip10DoubleJudgmentFactors"], "euro,asianLine,asianWater")
        let odds = Array(repeating: [3.0,3,3], count: 6)
        let choices = config.automaticDoubleChoices(in: odds)
        XCTAssertEqual(Set(choices.map(\.position)), [3,4])
        let generated = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        XCTAssertEqual(generated.finalBetCount, 324)
        XCTAssertTrue(generated.queryStages.contains { $0.name.contains("多因素") })
        for row in choices {
            XCTAssertTrue(generated.uniqueExpandedBets.allSatisfy { row.choice.retainedOutcomes.contains($0[row.position - 1]) })
        }
        config.svip10AdditionalFilters.doubleJudgmentFactors = []
        let old = config.automaticDoubleChoices(in: odds)
        XCTAssertEqual(old.map(\.position), [1,2])
        XCTAssertTrue(old.allSatisfy { $0.choice.judgmentScore == nil })
        XCTAssertEqual(Set(generated.config.matchNumbers), Set(config.matchNumbers))
    }

    func testMultiFactorHistoryIsExplicitlyBaselineAndCurrentSnapshotsAreExcluded() async throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        let data = ConditionEffectDataset(version: 1, source: "test", groups: [2025,2026].map { year in
            ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: 2,
                logic: "AAAAAA", outcomes: [3,3,3,3,3,3], odds: calibrationFixtureOdds)
        })
        let baseline = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: data)
        config.svip10AdditionalFilters.doubleJudgmentFactors = Set(DoubleJudgmentFactor.allCases)
        config.svip10AdditionalFilters.doubleMarketEvidence = [marketEvidence(number: 1)]
        let template = try ConditionEffectAnalysis.template(config.normalizedInput)
        XCTAssertTrue(template.svip10AdditionalFilters.doubleMarketEvidence.isEmpty)
        let result = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: data)
        XCTAssertEqual(result.omittedJudgmentCount, 8)
        XCTAssertEqual(result.twoDoubleCombined, baseline.twoDoubleCombined)
        XCTAssertEqual(result.combined, baseline.combined)
        let report = try await ConditionEffectAnalysis.analyze(input: config.normalizedInput, dataset: data)
        XCTAssertTrue(report.notices.contains { $0.contains("不是多因素方案过关率") })
    }

    func testMarketClientDoesNotDownloadPostKickoffEvidence() async throws {
        let match = BeijingSingleMatch(issue: "24111", matchNumber: "9999", fixtureID: "9999999", league: "test",
            matchTime: "11-01 12:00", status: "完", homeTeam: "主", awayTeam: "客", handicap: 0, referenceSP: [],
            marketOdds: [2,3,4], homeScore: 2, awayScore: 1)
        let result = await DoubleMarketDataClient.fetch(matches: [match], factors: Set(DoubleJudgmentFactor.allCases))
        XCTAssertTrue(result.evidence.isEmpty)
        XCTAssertTrue(result.notes[9999]?.contains("没有赛前快照") == true)
    }

    private func sampledEvidence(_ original: DoubleMarketEvidence, after seconds: TimeInterval,
                                 books: [DoubleBookQuote]? = nil) -> DoubleMarketEvidence {
        DoubleMarketEvidence(issue: original.issue, number: original.number, fixtureID: original.fixtureID,
            handicap: original.handicap, capturedAt: original.capturedAt.addingTimeInterval(seconds), kickoff: original.kickoff,
            books: books ?? original.books, bettingShares: original.bettingShares)
    }

    private func futureMarketDay() -> (issue: String, day: String) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8*3600)
        let future = Date().addingTimeInterval(7*86400)
        formatter.dateFormat = "yy"; let issue = formatter.string(from: future) + "111"
        formatter.dateFormat = "MM-dd"; return (issue, formatter.string(from: future))
    }

    func testDoubleMarketTrajectoryIsBoundedAndRejectsUnrelatedOrFutureSamples() throws {
        let original = marketEvidence()
        var current = original
        for minute in 1...20 {
            current = sampledEvidence(original, after: Double(minute)*60).recording(previous: current)
            XCTAssertTrue(current.isValid)
        }
        XCTAssertEqual(current.observations?.count, 12)
        XCTAssertEqual(current.observations?.first?.capturedAt, original.capturedAt.addingTimeInterval(9*60))
        XCTAssertEqual(current.observations?.last, current.observation)
        XCTAssertEqual(current.recentPrimaryObservations.count, 12)
        XCTAssertEqual(DoubleMarketEvidence.decoded(DoubleMarketEvidence.encoded([current])), [current])
        let unrelated = marketEvidence(number: 2)
        XCTAssertEqual(sampledEvidence(original, after: 1260).recording(previous: unrelated).observations?.count, 1)
        let rapid = sampledEvidence(original, after: 1210).recording(previous: current)
        XCTAssertEqual(rapid.observations?.count, 12)
        XCTAssertEqual(rapid.observations?.last?.capturedAt, rapid.capturedAt)
        var bad = current
        bad.observations = [DoubleMarketObservation(capturedAt: current.capturedAt.addingTimeInterval(1), books: [], bettingShares: [])]
        XCTAssertFalse(bad.isValid)
        XCTAssertNil(DoubleMarketEvidence.decoded(DoubleMarketEvidence.encoded([bad])))
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as! [String: Any]
        old.removeValue(forKey: "observations")
        let restored = try JSONDecoder().decode(DoubleMarketEvidence.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.observations); XCTAssertTrue(restored.isValid)
    }

    func testDoubleMarketWaterOnlyComparesSameHandicapAndContinuousSamplesAffectTrend() throws {
        let original = marketEvidence()
        let candidate = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [3,3,3], evidence: original)
        let oldWater = DoubleJudgmentScorer.assessments(candidate, calibrated: true, factors: [.asianWater])
        XCTAssertFalse(oldWater[0].available)
        XCTAssertEqual(oldWater[0].adjustment, [0,0,0])
        let changed = original.books.map { DoubleBookQuote(companyID: $0.companyID, openingEuropean: $0.openingEuropean,
            currentEuropean: [2.4,3.6,3], openingAsian: $0.openingAsian,
            currentAsian: DoubleAsianPoint(homeWater: 0.95, line: -1, awayWater: 0.9)) }
        let latest = sampledEvidence(original, after: 120, books: changed).recording(previous: original)
        let fresh = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [3,3,3], evidence: latest)
        let rows = DoubleJudgmentScorer.assessments(fresh, calibrated: true, factors: [.asianWater,.euro])
        XCTAssertTrue(rows.allSatisfy(\.available))
        XCTAssertTrue(rows.first { $0.factor == .asianWater }!.note.contains("同盘口"))
        XCTAssertTrue(rows.first { $0.factor == .euro }!.note.contains("背离"))
        let unrecorded = sampledEvidence(original, after: 120, books: changed)
        let withoutHistory = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [3,3,3], evidence: unrecorded)
        XCTAssertNotEqual(DoubleJudgmentScorer.scores(fresh, calibrated: true, factors: [.euro]),
                          DoubleJudgmentScorer.scores(withoutHistory, calibrated: true, factors: [.euro]))
        XCTAssertEqual(DoubleJudgmentScorer.scores(fresh, calibrated: true, factors: []),
                       DoubleJudgmentScorer.scores(withoutHistory, calibrated: true, factors: []))
    }

    func testDoubleMarketFileStoreRestoresTimelineAndNeverOverwritesWithOlderSample() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleMarketSnapshotStore(directory: directory)
        let original = marketEvidence()
        _ = await store.store(original)
        let latest = await store.store(sampledEvidence(original, after: 120))
        let ignored = await store.store(sampledEvidence(original, after: 60))
        XCTAssertEqual(ignored, latest)
        let reopened = DoubleMarketSnapshotStore(directory: directory)
        let restored = await reopened.evidence(issue: original.issue, number: original.number, fixtureID: original.fixtureID)
        XCTAssertEqual(restored, latest); XCTAssertEqual(restored?.observations?.count, 2)
        let frozen = await reopened.evidence(issue: original.issue, number: original.number, fixtureID: original.fixtureID,
                                             before: original.capturedAt.addingTimeInterval(90))
        XCTAssertEqual(frozen?.capturedAt, original.capturedAt)
        let log = directory.appendingPathComponent("\(original.issue)-\(original.number)-\(original.fixtureID).jsonl")
        let samples = try Data(contentsOf: log).split(separator: 0x0A).map { try JSONDecoder().decode(DoubleMarketEvidence.self, from: Data($0)) }
        XCTAssertEqual(samples.map(\.capturedAt), [original.capturedAt, latest.capturedAt])
        XCTAssertTrue(samples.allSatisfy { $0.isValid && $0.observations == nil })
    }

    func testDoubleMarketFetchFailureKeepsRealTimestampAndExcludesExpiredQuotes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleMarketSnapshotStore(directory: directory)
        let now = Date()
        let future = futureMarketDay(), time = future.day + " 12:00"
        let kickoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: future.issue, matchTime: time))
        let match = BeijingSingleMatch(issue: future.issue, matchNumber: "991", fixtureID: "999999991", league: "test",
            matchTime: time, status: "未", homeTeam: "主", awayTeam: "客", handicap: 0,
            referenceSP: [], marketOdds: [2,3,4])
        let cached = DoubleMarketEvidence(issue: match.issue, number: 991, fixtureID: match.fixtureID, handicap: 0,
            capturedAt: now.addingTimeInterval(-60), kickoff: kickoff, books: marketEvidence().books, bettingShares: [])
        _ = await store.store(cached)
        let failed: @Sendable (String,Int) async throws -> DoubleBookQuote = { _,_ in throw GoalModelError.invalidResponse }
        let result = await DoubleMarketDataClient.fetch(matches: [match], factors: [.euro], now: now, store: store, quoteLoader: failed)
        XCTAssertEqual(result.evidence.first?.capturedAt, cached.capturedAt)
        XCTAssertTrue(result.notes[991]?.contains("行情未更新") == true)
        let staleStore = DoubleMarketSnapshotStore(directory: directory.appendingPathComponent("stale"))
        let stale = DoubleMarketEvidence(issue: match.issue, number: 991, fixtureID: match.fixtureID, handicap: 0,
            capturedAt: now.addingTimeInterval(-300), kickoff: kickoff, books: cached.books, bettingShares: [])
        _ = await staleStore.store(stale)
        let expired = await DoubleMarketDataClient.fetch(matches: [match], factors: [.euro], now: now, store: staleStore, quoteLoader: failed)
        XCTAssertTrue(expired.evidence.isEmpty)
        XCTAssertTrue(expired.notes[991]?.contains("过期") == true)
        XCTAssertEqual(expired.displayEvidence.first?.capturedAt, stale.capturedAt)
    }

    func testSixFullDoubleMarketTimelinesFitSnapshotProtocolAndPreserve324Bets() throws {
        let rows = (1...6).map { number -> DoubleMarketEvidence in
            let original = marketEvidence(number: number)
            var latest = original
            for minute in 1...12 { latest = sampledEvidence(original, after: Double(minute)*60).recording(previous: latest) }
            return latest
        }
        let encoded = DoubleMarketEvidence.encoded(rows)
        XCTAssertLessThan(encoded.utf8.count, 100_000)
        XCTAssertEqual(DoubleMarketEvidence.decoded(encoded), rows)
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.automaticDoublePairEnabled = true
        config.svip10AdditionalFilters.doubleJudgmentFactors = Set(DoubleJudgmentFactor.allCases)
        config.svip10AdditionalFilters.doubleMarketEvidence = rows
        let replay = try FilterConfig.parse(config.normalizedInput)
        XCTAssertEqual(replay, config)
        XCTAssertEqual(SequenceFilterEngine.calculate(replay, previousContext: nil, currentOutcomeSPs: Array(repeating: [3,3,3], count: 6)).finalBetCount, 324)
    }

    func testDoubleMarketGroupFreezesBeforeFirstKickoffAndLiveQuotesStayConsistent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleMarketSnapshotStore(directory: directory)
        let future = futureMarketDay()
        let matches = (1...6).map { number in
            BeijingSingleMatch(issue: future.issue, matchNumber: String(number), fixtureID: String(8000000+number), league: "test",
                matchTime: "\(future.day) \(String(format: "%02d", number+10)):00", status: "未", homeTeam: "主", awayTeam: "客",
                handicap: 0, referenceSP: [], marketOdds: [3,3,3], homeScore: 9, awayScore: 0)
        }
        let cutoff = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: future.issue, matchTime: matches[0].matchTime))
        let captured = Date()
        let evidence = matches.map { match in
            DoubleMarketEvidence(issue: match.issue, number: Int(match.matchNumber)!, fixtureID: match.fixtureID, handicap: 0,
                capturedAt: captured, kickoff: DoubleMarketDataClient.kickoff(issue: match.issue, matchTime: match.matchTime)!,
                books: marketEvidence().books, bettingShares: [])
        }
        let verified = DoubleMarketDataClient.verifiedEvidence(evidence, matches: matches, firstMatchNumber: 1)
        XCTAssertEqual(verified.count, 6)
        let quoted = DoubleMarketDataClient.applyingVerifiedQuotes(verified, to: matches)
        XCTAssertTrue(quoted.allSatisfy { $0.marketOdds == [1.8,3.8,5] && $0.homeScore == 9 })
        let selection = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1, matches: matches,
            calibrated: true, factors: [.euro], evidence: evidence)?.automaticDoubleSelection)
        let expected = try XCTUnwrap(HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: [1.8,3.8,5], handicap: 0))
        XCTAssertTrue(selection.matches.allSatisfy { $0.odds == expected })
        let off = try XCTUnwrap(VIP6MatchRecommender.recommendAutomaticDoubles(firstMatchNumber: 1, matches: matches,
            calibrated: true, evidence: evidence)?.automaticDoubleSelection)
        XCTAssertTrue(off.matches.allSatisfy { $0.odds == HandicapOddsComparisonTable.convertedOdds(ordinaryOdds: [3,3,3], handicap: 0)! })
        // A later fixture's own pregame quote is still too late for the six-fixture ticket.
        let late = DoubleMarketEvidence(issue: future.issue, number: 2, fixtureID: matches[1].fixtureID, handicap: 0,
            capturedAt: cutoff.addingTimeInterval(60), kickoff: evidence[1].kickoff, books: marketEvidence().books, bettingShares: [])
        // The clock guard also rejects manufactured future snapshots.
        XCTAssertTrue(DoubleMarketDataClient.verifiedEvidence([late], matches: matches, firstMatchNumber: 1).isEmpty)
        for value in evidence { _ = await store.store(value) }
        let frozen = await DoubleMarketDataClient.fetch(matches: matches, factors: [.euro], now: cutoff.addingTimeInterval(60),
            store: store, quoteLoader: { _,_ in XCTFail("Must not fetch after the group's first kickoff"); throw GoalModelError.invalidResponse })
        XCTAssertEqual(frozen.evidence.count, 6)
        XCTAssertTrue(frozen.notes.values.allSatisfy { $0.contains("首场已开赛") })
    }

    func testEveryFixtureCollectsEuropeanAndAsianTrendsEvenWithJudgmentSignalsOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DoubleMarketSnapshotStore(directory: directory)
        let future = futureMarketDay()
        let matches = (1...6).map { number in
            BeijingSingleMatch(issue: future.issue, matchNumber: String(number), fixtureID: String(7000000+number), league: "test",
                matchTime: future.day + " 12:00", status: "未", homeTeam: "主", awayTeam: "客", handicap: 0,
                referenceSP: [], marketOdds: [2,3,4])
        }
        let quote = try DoubleMarketDataClient.parseQuote(data: Data(#"[[[1.03,"受一球",0.78],[0.97,"受半球/一球",0.82]],[[7.5,3.9,1.45],[5,3.6,1.7]]]"#.utf8), companyID: 3)
        let result = await DoubleMarketDataClient.fetch(matches: matches, factors: [], includeTrends: true,
            store: store, quoteLoader: { _,_ in quote })
        XCTAssertEqual(result.evidence.map(\.number), [1,2,3,4,5,6])
        for evidence in result.evidence {
            let trend = try XCTUnwrap(DoubleMarketTrendData(evidence: evidence, companyID: 3))
            XCTAssertEqual(trend.european.count, 3)
            XCTAssertEqual(trend.asianLine.count, 1)
            XCTAssertEqual(trend.asianWater.count, 2)
            XCTAssertEqual(trend.asianLine.first?.value, 0.75)
            XCTAssertEqual(Set(trend.european.map(\.capturedAt)), [evidence.capturedAt])
        }
    }

    func testDoubleMarketChartsOnlyUseObservedTimesAndPreserveMissingAsianData() throws {
        let original = marketEvidence()
        let latest = sampledEvidence(original, after: 120).recording(previous: original)
        let data = try XCTUnwrap(DoubleMarketTrendData(evidence: latest, companyID: 3))
        XCTAssertEqual(data.european.count, 6); XCTAssertEqual(data.asianLine.count, 2); XCTAssertEqual(data.asianWater.count, 4)
        XCTAssertEqual(Set(data.european.map(\.capturedAt)), [original.capturedAt, latest.capturedAt])
        XCTAssertEqual(data.openingEuropean, original.books[0].openingEuropean)
        XCTAssertEqual(data.currentEuropean, latest.books[0].currentEuropean)
        XCTAssertNil(DoubleMarketTrendData(evidence: latest, companyID: 999))
        let noAsian = [DoubleBookQuote(companyID: 3, openingEuropean: [2,3,4], currentEuropean: [2.1,3,3.9], openingAsian: nil, currentAsian: nil)]
        let missing = try XCTUnwrap(DoubleMarketTrendData(evidence: sampledEvidence(original, after: 180, books: noAsian), companyID: 3))
        XCTAssertEqual(missing.european.count, 3)
        XCTAssertTrue(missing.asianLine.isEmpty); XCTAssertTrue(missing.asianWater.isEmpty)
        XCTAssertNil(missing.openingAsian); XCTAssertNil(missing.currentAsian)
    }

    func testTradeMarketDatesUseFullCutoffAcrossMidnightAndYearBoundary() throws {
        func row(_ number: Int, _ end: String, _ sale: String, _ clock: String) -> String {
            """
            <tr class="vs_lines" fid="\(900000+number)" value="{index:'\(number)',endTime:'\(end)',scheduleDate:'\(sale)',rangqiuNum:'0'}">
            <td><span class="chnum">\(number)</span></td><td>test</td><td>\(clock)</td><td>主</td><td>0</td><td>客</td>
            <td><span class="pjoz">2</span><span class="pjoz">3</span><span class="pjoz">4</span></td>
            <td>--</td><td></td><td></td><td></td></tr>
            """
        }
        let html = row(131, "2026-10-29 20:20", "2026-10-29", "20:20")
            + row(134, "2026-10-30 00:50", "2026-10-29", "00:50")
        let matches = FiveHundredBeijingSingleClient.parse(html: html, issue: "26108")
        XCTAssertEqual(matches.map(\.matchTime), ["10-29 20:20", "10-30 00:50"])
        let first = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: matches[0].matchTime))
        let second = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: matches[1].matchTime))
        XCTAssertEqual(second.timeIntervalSince(first), 4.5*3600, accuracy: 0.01)
        let december = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26121", matchTime: "12-31 23:50"))
        let january = try XCTUnwrap(DoubleMarketDataClient.kickoff(issue: "26121", matchTime: "01-01 00:50"))
        XCTAssertEqual(january.timeIntervalSince(december), 3600, accuracy: 0.01)
        XCTAssertEqual(DoubleMarketDataClient.kickoff(issue: "27011", matchTime: "12-31 23:50"), december)
        XCTAssertNil(DoubleMarketDataClient.kickoff(issue: "26abc", matchTime: "10-29 20:20"))
        XCTAssertNil(DoubleMarketDataClient.kickoff(issue: "26108", matchTime: "02-30 20:20"))
    }

    func testDoubleMarketCachedAssessmentsRespectSnapshotOddsFactorsAndConcurrentReaders() async throws {
        let original = marketEvidence()
        let match = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [3,3,3], evidence: original)
        let factors = Set(DoubleJudgmentFactor.allCases)
        let expected = try XCTUnwrap(DoubleJudgmentScorer.scores(match, calibrated: true, factors: factors))
        let all = await withTaskGroup(of: [Double]?.self) { group -> [[Double]?] in
            for _ in 0..<24 { group.addTask { DoubleJudgmentScorer.scores(match, calibrated: true, factors: factors) } }
            var rows: [[Double]?] = []
            for await row in group { rows.append(row) }
            return rows
        }
        XCTAssertTrue(all.allSatisfy { $0 == expected })
        let reduced = DoubleJudgmentScorer.assessments(match, calibrated: true, factors: [.euro])
        XCTAssertEqual(reduced.map(\.factor), [.euro])
        let alteredBooks = original.books.map { DoubleBookQuote(companyID: $0.companyID, openingEuropean: $0.openingEuropean,
            currentEuropean: [2.1,3.6,4], openingAsian: $0.openingAsian, currentAsian: $0.currentAsian) }
        var newer = match; newer.evidence = sampledEvidence(original, after: 120, books: alteredBooks)
        XCTAssertNotEqual(DoubleJudgmentScorer.assessments(newer, calibrated: true, factors: [.euro]).map(\.note), reduced.map(\.note))
        var otherOdds = match; otherOdds = AutomaticDoubleCandidate(number: 1, logic: .a, odds: [2,4,5], evidence: original)
        XCTAssertNotEqual(DoubleJudgmentScorer.scores(otherOdds, calibrated: true, factors: factors), expected)
        var invalid = original; invalid.observations = [DoubleMarketObservation(capturedAt: original.kickoff, books: [], bettingShares: [])]
        var untrusted = match; untrusted.evidence = invalid
        XCTAssertFalse(DoubleJudgmentScorer.assessments(untrusted, calibrated: true, factors: [.euro])[0].available)
    }

    private func calibratedDoubleConfig(enabled: Bool = true) throws -> FilterConfig {
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            FilterConfig.svip10Input(numbers: (1...6).map(String.init), logic: "AAAAAA", extras: ["7:3"],
                scoreRange: "0-100", noFourPosition: nil, sumRange: "0-24", mRange: "0-100"),
            coldEnabled: false, coldRange: "0-2", drawEnabled: false, drawRange: "0-3",
            highestDoubleProbabilityTopTwoEnabled: true, secondDoubleLowestProbabilityEnabled: true,
            calibratedDoubleSelectionEnabled: enabled)
        return try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: input, disabled: Set(BasicCondition.allCases)))
    }

    private var calibrationFixtureOdds: [[Double]] {
        [[2.557935694718695,4.18377923539443,2.702400252210463],
         [3.4290957624290956,3.471959459459459,2.378935185185185],
         [1.9958076225388752,4.513109459214347,3.6052538092624284],
         [2.7864421386064824,3.5259210138520483,2.7971592237549685],
         [3.372116689280869,3.5862193362193366,2.3551291163231465],
         [2.173818675856584,3.3838753771954715,4.090634158508449]]
    }

    func testCalibratedDoublesMatchFrozenReferenceAndRoundTrip() throws {
        let config = try calibratedDoubleConfig()
        XCTAssertTrue(config.normalizedInput.contains("S10DBLCAL=1"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip10CalibratedDoubleSelectionEnabled"], "1")
        let rows = try XCTUnwrap(config.doubleSelectionProbabilities(in: calibrationFixtureOdds))
        XCTAssertEqual(rows[0][0], 0.3743225059443532, accuracy: 1e-12)
        XCTAssertEqual(rows[2][1], 0.23384951369098642, accuracy: 1e-12)
        for row in rows { XCTAssertEqual(row.reduce(0, +), 1, accuracy: 1e-12) }
        let first = try XCTUnwrap(config.highestDoubleProbabilityTopTwoSelection(in: calibrationFixtureOdds))
        let second = try XCTUnwrap(SequenceFilterEngine.svip10SecondDoubleSelection(config: config,
            currentOutcomeProbabilities: Array(repeating: [0.01, 0.98, 0.01], count: 6), customOdds: calibrationFixtureOdds))
        XCTAssertEqual(first.position, 6); XCTAssertEqual(first.removedOutcome, 0)
        XCTAssertEqual(second.position, 3); XCTAssertEqual(second.removedOutcome, 1)
        XCTAssertFalse(second.usesModelProbability)
        XCTAssertEqual(second.doubleProbability, 1 - rows[2][1], accuracy: 1e-12)
        XCTAssertNil(config.doubleSelectionProbabilities(in: nil))
        XCTAssertNil(config.doubleSelectionProbabilities(in: [[0, 1, 2]] + calibrationFixtureOdds.dropFirst()))
    }

    func testCalibratedDoublesExportAndQueryUseTheSameSelections() throws {
        let config = try calibratedDoubleConfig()
        let result = SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeProbabilities: Array(repeating: [0.01, 0.98, 0.01], count: 6),
            currentOutcomeSPs: calibrationFixtureOdds, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 324)
        XCTAssertEqual(result.exportCompressedRecords.count, 1)
        XCTAssertEqual(result.config.resolvedHighestDoubleProbabilityNoFourPosition, 6)
        XCTAssertEqual(result.config.resolvedSecondDoublePosition, 3)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { $0[5] != 0 && $0[2] != 1 })
        XCTAssertTrue(result.queryStages.contains { $0.name.contains("校正自定义赔率概率") })
        let failures = SequenceFilterEngine.svip10AdditionalFailureReasons(outcomes: [3,3,1,3,3,0],
            config: result.config, customOdds: calibrationFixtureOdds)
        XCTAssertEqual(failures.count, 2)
        XCTAssertTrue(failures.contains { $0.contains("校正双选概率") })
    }

    func testDisablingCalibrationRestoresLegacyModelSelectionAndOldArchivesStayOff() throws {
        let config = try calibratedDoubleConfig(enabled: false)
        let model = [[0.7,0.2,0.1],[0.49,0.50,0.01]] + Array(repeating: [0.34,0.33,0.33], count: 4)
        let second = try XCTUnwrap(SequenceFilterEngine.svip10SecondDoubleSelection(config: config,
            currentOutcomeProbabilities: model, customOdds: calibrationFixtureOdds))
        XCTAssertEqual(second.position, 2); XCTAssertEqual(second.removedOutcome, 0)
        XCTAssertTrue(second.usesModelProbability)
        let legacy = try FilterConfig.parse(config.normalizedInput.replacingOccurrences(of: "|S10DBLCAL=0", with: ""))
        XCTAssertFalse(legacy.svip10AdditionalFilters.calibratedDoubleSelectionEnabled)
    }

    func testConditionEffectAnalysisCountsStandaloneRulesAndPreviewsDisabledOnes() async throws {
        let config = try calibratedDoubleConfig()
        let groups = [2025,2026].map { year in ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011",
            start: 2, logic: "AAAAAA", outcomes: [3,3,3,3,3,3], odds: calibrationFixtureOdds) }
        let report = try await ConditionEffectAnalysis.analyze(input: config.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups))
        for year in [2025,2026] {
            XCTAssertEqual(report.counts[year]?["extra.13"]?.groups, 1)
            XCTAssertEqual(report.counts[year]?["extra.13"]?.hits, 1)
            XCTAssertEqual(report.counts[year]?["extra.13"]?.retainedBets, 486)
            XCTAssertEqual(report.counts[year]?["extra.14"]?.retainedBets, 486)
            XCTAssertEqual(report.counts[year]?["core.0"]?.retainedBets, 729)
        }
        XCTAssertFalse(try XCTUnwrap(report.rules.first { $0.id == "core.0" }).enabled)
        XCTAssertEqual(report.counts[2025]?["extra.13"]?.filteredRate ?? 0, 1.0 / 3, accuracy: 1e-12)
    }

    func testHomePassRateUsesJointResultsAndWeightedYearTotals() async throws {
        let config = try calibratedDoubleConfig()
        let first = try XCTUnwrap(config.highestDoubleProbabilityTopTwoSelection(in: calibrationFixtureOdds))
        let second = try XCTUnwrap(SequenceFilterEngine.svip10SecondDoubleSelection(config: config,
            currentOutcomeProbabilities: nil, customOdds: calibrationFixtureOdds))
        var passing = Array(repeating: 3, count: 6)
        passing[first.position - 1] = [3, 1, 0].first { $0 != first.removedOutcome }!
        passing[second.position - 1] = [3, 1, 0].first { $0 != second.removedOutcome }!
        var failsFirst = passing; failsFirst[first.position - 1] = first.removedOutcome
        var failsSecond = passing; failsSecond[second.position - 1] = second.removedOutcome
        var failsBoth = failsFirst; failsBoth[second.position - 1] = second.removedOutcome
        let outcomes = [passing, failsFirst, passing, failsSecond, failsBoth]
        let groups = outcomes.enumerated().map { index, outcomes in
            ConditionEffectGroup(year: index < 2 ? 2025 : 2026, issue: index < 2 ? "25011" : "26011",
                start: index * 6 + 2, logic: "AAAAAA", outcomes: outcomes, odds: calibrationFixtureOdds)
        }
        let dataset = ConditionEffectDataset(version: 1, source: "test", groups: groups)
        let summary = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: dataset)
        XCTAssertEqual(summary.enabledRuleCount, 2)
        XCTAssertEqual(summary.years[2025], ConditionPassRateYear(groups: 2, hits: 1))
        XCTAssertEqual(summary.years[2026], ConditionPassRateYear(groups: 3, hits: 1))
        XCTAssertEqual(summary.combined, ConditionPassRateYear(groups: 5, hits: 2))
        XCTAssertEqual(summary.combined.rate, 0.4, accuracy: 1e-12)
        XCTAssertEqual(summary.twoDoubleCombined, summary.combined)
        XCTAssertEqual(summary.twoDoubleYears, summary.years)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        let fullReplayHits = outcomes.filter { actual in result.uniqueExpandedBets.contains { Array($0.prefix(6)) == actual } }.count
        XCTAssertEqual(summary.combined.hits, fullReplayHits)

        var changed = config
        changed.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled = false
        let refreshed = try await ConditionEffectAnalysis.passRate(input: changed.normalizedInput, dataset: dataset)
        XCTAssertNotEqual(refreshed.input, summary.input)
        XCTAssertEqual(refreshed.combined.hits, 3)
        changed.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled = false
        let unfiltered = try await ConditionEffectAnalysis.passRate(input: changed.normalizedInput, dataset: dataset)
        XCTAssertEqual(unfiltered.enabledRuleCount, 0)
        XCTAssertEqual(unfiltered.combined.rate, 1)
    }

    func testHomePassRateRefreshesRangesAndIgnoresUnfinishedCurrentFixtures() async throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled = false
        config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled = false
        config.outcomeConditions[.draws] = 0...1
        let groups = [2025, 2026].map { year in
            ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011", start: 2,
                logic: "AAAAAA", outcomes: [1, 1, 3, 3, 3, 3], odds: calibrationFixtureOdds)
        }
        let dataset = ConditionEffectDataset(version: 1, source: "test", groups: groups)
        let original = try await ConditionEffectAnalysis.passRate(input: config.normalizedInput, dataset: dataset)
        XCTAssertEqual(original.combined.hits, 0)
        config.outcomeConditions[.draws] = 0...2
        var fields = config.normalizedInput.components(separatedBy: "|")
        fields[0] = ""; fields[1] = ""
        let updated = try await ConditionEffectAnalysis.passRate(input: fields.joined(separator: "|"), dataset: dataset)
        XCTAssertNotEqual(original.input, updated.input)
        XCTAssertEqual(updated.combined.hits, 2)
    }

    func testSVIP10OutcomeSwitchesApplyWithoutTextEditorRegistration() throws {
        let base = try calibratedDoubleConfig().normalizedInput
        var values = ["selectedConditionVersionID": "svip10-frozen-160", "enteredConditionIDs": "",
            "OCON_WLSWITCH": "1", "OC_WLSWITCH": "0-3", "OCON_DRAWS": "1", "OC_DRAWS": "0-1"]
        let ranges = FilterInputDefaults.enabledEditorOutcomeRanges(values: values)
        let input = FilterConfig.appendingConditionSwitches(to: base, disabled: Set(BasicCondition.allCases), outcomeRanges: ranges)
        let config = try FilterConfig.parse(input)
        XCTAssertEqual(config.outcomeConditions[.winLossSwitches], 0...3)
        XCTAssertNil(config.outcomeConditions[.draws])
        XCTAssertEqual(ConditionEffectAnalysis.rules(for: config).filter { $0.id == "outcome.WLSWITCH" && $0.enabled }.count, 1)
        values["OCON_WLSWITCH"] = "0"
        XCTAssertTrue(FilterInputDefaults.enabledEditorOutcomeRanges(values: values).isEmpty)
    }

    func testEditableSixMatchBreakpointsRespectBoundsSwitchAndLegacyArchives() throws {
        var config = try calibratedDoubleConfig()
        config.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled = false
        config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled = false
        config.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled = true
        config.svip10AdditionalFilters.sixMatchBreakpointRange = 2...5
        let input = config.normalizedInput
        XCTAssertEqual(try FilterConfig.parse(input), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip10SixMatchBreakpointRangeInput"], "2-5")
        let kept = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        XCTAssertEqual(kept.finalBetCount, 696) // 729 minus the 3 B=0 and 30 B=1 combinations.
        XCTAssertTrue(kept.uniqueExpandedBets.allSatisfy { outcomes in
            let six = Array(outcomes.prefix(6))
            return (2...5).contains(zip(six, six.dropFirst()).filter { $0 != $1 }.count)
        })
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(outcomes: [3,3,1,1,0,0,3],
            config: config, customOdds: calibrationFixtureOdds, onlyRule: 12).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(outcomes: [3,3,3,0,0,0],
            config: config, customOdds: calibrationFixtureOdds, onlyRule: 12).isEmpty)
        config.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled = false
        XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeSPs: calibrationFixtureOdds).finalBetCount, 729)
        let legacyInput = input.components(separatedBy: "|").filter { !$0.hasPrefix("S10BRANGE=") }.joined(separator: "|")
        let legacy = try FilterConfig.parse(legacyInput)
        XCTAssertEqual(legacy.svip10AdditionalFilters.sixMatchBreakpointRange, 3...5)
        XCTAssertEqual(SequenceFilterEngine.calculate(legacy, previousContext: nil,
            currentOutcomeSPs: calibrationFixtureOdds).finalBetCount, 576)
        for invalid in ["2-6", "5-2", "2.5-5"] {
            XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "S10BRANGE=2-5", with: "S10BRANGE=" + invalid)))
        }
        let rules = [ConditionTextRule(id: "extra.12", title: "六场彩果断点数 B",
            aliases: ["断点数", "六场断点", "B"], format: .integerRange, maximum: 5)]
        XCTAssertEqual(try ConditionTextParser.interpret("断点数二到五", rules: rules),
            [ConditionTextCommand(id: "extra.12", value: "2-5", enabled: true)])
        XCTAssertEqual(try ConditionTextParser.interpret("关闭断点数", rules: rules).first?.enabled, false)
    }

    func testHomePassRateRejectsIncompleteOrCancelledHistory() async throws {
        let input = try calibratedDoubleConfig().normalizedInput
        let group = ConditionEffectGroup(year: 2025, issue: "25011", start: 2, logic: "AAAAAA",
            outcomes: [3, 3, 3, 3, 3, 3], odds: calibrationFixtureOdds)
        do {
            _ = try await ConditionEffectAnalysis.passRate(input: input,
                dataset: ConditionEffectDataset(version: 1, source: "test", groups: [group]))
            XCTFail("A partial year must not appear as the current pass rate")
        } catch is ConditionEffectAnalysis.AnalysisError { }
        let task = Task {
            try await ConditionEffectAnalysis.passRate(input: input,
                dataset: ConditionEffectDataset(version: 1, source: "test", groups: []))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not publish") } catch is CancellationError { }
    }

    func testConditionEffectSnapshotIgnoresCurrentFixturesButTracksRangeAndSwitchEdits() throws {
        let config = try calibratedDoubleConfig()
        let original = try ConditionEffectAnalysis.template(config.normalizedInput)
        var fields = config.normalizedInput.components(separatedBy: "|")
        fields[0] = "386,387,388,389,390,391"
        fields[1] = ""
        XCTAssertEqual(try ConditionEffectAnalysis.template(fields.joined(separator: "|")).normalizedInput, original.normalizedInput)
        let off = config.normalizedInput.replacingOccurrences(of: "S10DBLCAL=1", with: "S10DBLCAL=0")
        XCTAssertNotEqual(try ConditionEffectAnalysis.template(off).normalizedInput, original.normalizedInput)
        var changedRange = config
        changedRange.six250SumRange = 15...19
        XCTAssertNotEqual(try ConditionEffectAnalysis.template(changedRange.normalizedInput).normalizedInput, original.normalizedInput)
    }

    func testGeneratedConditionsMatchActualEngineMarginalCountsAndExcludeExistingFields() async throws {
        let config = try calibratedDoubleConfig()
        let groups = [2025, 2026].map { year in ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011",
            start: 2, logic: "AAAAAA", outcomes: [3,3,3,3,3,3], odds: calibrationFixtureOdds) }
        let report = try await ConditionEffectAnalysis.analyze(input: config.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups))
        XCTAssertFalse(report.suggestions.isEmpty)
        XCTAssertEqual(Set(report.suggestions.map(\.condition)).count, report.suggestions.count)
        let original = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
        for suggestion in report.suggestions {
            var added = config
            added.outcomeConditions[suggestion.condition] = suggestion.range
            XCTAssertEqual(try FilterConfig.parse(added.normalizedInput), added)
            let updated = SequenceFilterEngine.calculate(added, previousContext: nil, currentOutcomeSPs: calibrationFixtureOdds)
            for year in [2025, 2026] {
                let c = try XCTUnwrap(suggestion.years[year])
                XCTAssertEqual(c.base.groups, 1)
                XCTAssertEqual(c.base.retainedBets, original.finalBetCount)
                XCTAssertEqual(c.combined.retainedBets, updated.finalBetCount)
                XCTAssertEqual(c.standalone.hits, 1)
                XCTAssertEqual(c.base.hits, 1)
                XCTAssertEqual(c.combined.hits, 1)
                XCTAssertGreaterThanOrEqual(c.standalone.hitRate, 0.90)
                XCTAssertGreaterThanOrEqual(c.additionalFilteredRate, 0.02)
                XCTAssertGreaterThanOrEqual(c.hitRetention, 0.95)
                XCTAssertTrue(updated.uniqueExpandedBets.allSatisfy {
                    suggestion.range.contains(suggestion.condition.value(in: Array($0.prefix(6))))
                })
            }
        }
        let first = try XCTUnwrap(report.nextSuggestion(excluding: []))
        XCTAssertNotEqual(report.nextSuggestion(excluding: [first.editorID])?.editorID, first.editorID)
        XCTAssertNil(report.nextSuggestion(excluding: Set(report.suggestions.map(\.editorID))))

        var existing = config
        existing.outcomeConditions[first.condition] = first.range
        let refreshed = try await ConditionEffectAnalysis.analyze(input: existing.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups))
        XCTAssertFalse(refreshed.suggestions.contains { $0.condition == first.condition })
    }

    func testGeneratedConditionsDoNotRecommendWhenNoBaseHitsSurvive() async throws {
        let config = try calibratedDoubleConfig()
        let groups = [2025, 2026].map { year in ConditionEffectGroup(year: year, issue: year == 2025 ? "25011" : "26011",
            start: 2, logic: "AAAAAA", outcomes: [0,0,1,0,0,0], odds: calibrationFixtureOdds) }
        let report = try await ConditionEffectAnalysis.analyze(input: config.normalizedInput,
            dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups))
        XCTAssertTrue(report.suggestions.isEmpty)
        XCTAssertNil(report.nextSuggestion(excluding: []))
    }

    func testGeneratedConditionMustMeetQualityInBothYears() throws {
        let config = try calibratedDoubleConfig()
        let patterns = (0..<6).reduce([[]] as [[Int]]) { rows, _ in rows.flatMap { row in [3,1,0].map { row + [$0] } } }
        let values = patterns.map { outcomes in OutcomeCondition.activeCases.map { $0.value(in: outcomes) } }
        let bets = (0...6).map { value in patterns.filter { OutcomeCondition.draws.value(in: $0) == value }.count * 100 }
        var histogram = ConditionSuggestionHistogram()
        for year in [2025, 2026] {
            histogram.base[year] = ConditionEffectCounts(groups: 100, hits: 100, retainedBets: 72900)
            histogram.actual[year] = [.draws: [0,0,100,0,0,0,0]]
            histogram.baseActual[year] = histogram.actual[year]
            histogram.baseBets[year] = [.draws: bets]
        }
        XCTAssertFalse(ConditionEffectAnalysis.suggestions(template: config, histogram: histogram, patternValues: values).isEmpty)
        histogram.actual[2026] = [.draws: [15,15,14,14,14,14,14]]
        histogram.baseActual[2026] = histogram.actual[2026]
        XCTAssertTrue(ConditionEffectAnalysis.suggestions(template: config, histogram: histogram, patternValues: values).isEmpty)
    }

    func testConditionEffectAnalysisRejectsPartialInvalidAndCancelledData() async throws {
        let config = try calibratedDoubleConfig()
        let group = ConditionEffectGroup(year: 2025, issue: "25011", start: 2, logic: "AAAAAA",
            outcomes: [3,3,3,3,3,3], odds: calibrationFixtureOdds)
        for groups in [[group], [group,group]] {
            do {
                _ = try await ConditionEffectAnalysis.analyze(input: config.normalizedInput,
                    dataset: ConditionEffectDataset(version: 1, source: "test", groups: groups))
                XCTFail("Partial or duplicated data must be rejected")
            } catch is ConditionEffectAnalysis.AnalysisError { }
        }
        let second = ConditionEffectGroup(year: 2026, issue: "26011", start: 2, logic: "AAAAAA",
            outcomes: [3,3,3,3,3,3], odds: calibrationFixtureOdds)
        let task = Task {
            try await ConditionEffectAnalysis.analyze(input: config.normalizedInput,
                dataset: ConditionEffectDataset(version: 1, source: "test", groups: [group,second]))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled analysis must stop") } catch is CancellationError { }
    }

    func testDeviceMigrationImportsMergedDataPreservesOtherKeysAndRunsOnlyOnce() throws {
        let domain = "SequenceFilterMigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        defaults.set("preserved", forKey: "nonBusinessPreference")
        defaults.set("old", forKey: "sequenceFilter.inputDefaults.v1")
        defaults.set("stale", forKey: "sequenceFilter.globalFilterCountsCache.v1")
        let id = UUID().uuidString
        let values: [String: Any] = ["sequenceFilter.inputDefaults.v1": ["sumInput": "15-19"],
                                     "sequenceFilter.sharedTXTQueryHistory.v1": Data("merged-history".utf8)]
        let envelope: [String: Any] = ["version": 1, "id": id, "values": values,
            "removeKeys": ["sequenceFilter.globalFilterCountsCache.v1"]]
        let input = directory.appendingPathComponent(DeviceDataMigration.payloadFilename)
        let data = try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0)
        try data.write(to: input)
        XCTAssertTrue(try DeviceDataMigration.importIfPresent(directory: directory, defaults: defaults, domain: domain, writeDurableBackup: false))
        XCTAssertEqual(defaults.string(forKey: "nonBusinessPreference"), "preserved")
        XCTAssertEqual(defaults.dictionary(forKey: "sequenceFilter.inputDefaults.v1") as? [String: String], ["sumInput": "15-19"])
        XCTAssertNil(defaults.object(forKey: "sequenceFilter.globalFilterCountsCache.v1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(DeviceDataMigration.receiptFilename).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("device-data-migration-before-\(id).plist").path))
        // Replaying a copied payload must never overwrite subsequent user edits.
        defaults.set("new-edit", forKey: "sequenceFilter.inputDefaults.v1")
        try data.write(to: input)
        XCTAssertFalse(try DeviceDataMigration.importIfPresent(directory: directory, defaults: defaults, domain: domain, writeDurableBackup: false))
        XCTAssertEqual(defaults.string(forKey: "sequenceFilter.inputDefaults.v1"), "new-edit")
    }

    func testDeviceMigrationRejectsInvalidEnvelopeWithoutChangingExistingData() throws {
        let domain = "SequenceFilterMigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        defaults.set("original", forKey: "sequenceFilter.inputDefaults.v1")
        let input = directory.appendingPathComponent(DeviceDataMigration.payloadFilename)
        for envelope: [String: Any] in [
            ["version": 2, "id": UUID().uuidString, "values": ["sequenceFilter.example": "x"], "removeKeys": []],
            ["version": 1, "id": UUID().uuidString, "values": ["unrelated-system-key": "x"], "removeKeys": []],
            ["version": 1, "id": UUID().uuidString, "values": ["sequenceFilter.example": "x"], "removeKeys": ["unrelated-system-key"]]
        ] {
            try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0).write(to: input)
            XCTAssertThrowsError(try DeviceDataMigration.importIfPresent(directory: directory, defaults: defaults, domain: domain, writeDurableBackup: false))
            XCTAssertEqual(defaults.string(forKey: "sequenceFilter.inputDefaults.v1"), "original")
        }
    }

    func testDeviceMigrationMissingPayloadLeavesDefaultsUntouched() throws {
        let domain = "SequenceFilterMigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("kept", forKey: "sequenceFilter.inputDefaults.v1")
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(try DeviceDataMigration.importIfPresent(directory: absent, defaults: defaults, domain: domain, writeDurableBackup: false))
        XCTAssertEqual(defaults.string(forKey: "sequenceFilter.inputDefaults.v1"), "kept")
    }


    func testConditionTextInputRejectsInvalidNumbersBeforeApplyingBatch() throws {
        XCTAssertEqual(try ConditionTextParser.validateValue("15-20", format: .integerRange, maximum: 24, title: "和值"), "15-20")
        XCTAssertEqual(try ConditionTextParser.validateValue("2", format: .integerRange, maximum: 6, title: "平局"), "2-2")
        XCTAssertEqual(try ConditionTextParser.validateValue("<=2", format: .integerRange, maximum: 6, title: "平局"), "0-2")
        for input in ["20-15", "-1-2", "0.5-2", "0-7", "NaN", "infinity", "0-", ""] {
            XCTAssertThrowsError(try ConditionTextParser.validateValue(input, format: .integerRange, maximum: 6, title: "平局"), input)
        }
        XCTAssertThrowsError(try ConditionTextParser.validateValue("1-2", format: .integerMaximum, maximum: 6, title: "判定值2最多"))
    }

    func testConditionTextInputParsesRangesAndIndependentSwitchCommands() throws {
        let aliases = ["和值": "sum", "平局": "draws", "连平": "drawRun"]
        XCTAssertEqual(try ConditionTextParser.parse("和值15–20、平局0-2\n关闭连平", aliases: aliases), [
            ConditionTextCommand(id: "sum", value: "15-20", enabled: true),
            ConditionTextCommand(id: "draws", value: "0-2", enabled: true),
            ConditionTextCommand(id: "drawRun", value: nil, enabled: false)
        ])
        XCTAssertEqual(try ConditionTextParser.parse("平局关闭；开启和值", aliases: aliases), [
            ConditionTextCommand(id: "draws", value: nil, enabled: false),
            ConditionTextCommand(id: "sum", value: nil, enabled: true)
        ])
    }

    func testConditionTextInputRejectsUnknownAndDuplicateRules() {
        let aliases = ["和值": "sum", "S": "sum", "平局": "draws"]
        XCTAssertThrowsError(try ConditionTextParser.parse("和值15-20、未知条件1-2", aliases: aliases))
        XCTAssertThrowsError(try ConditionTextParser.parse("和值15-20、S16-18", aliases: aliases))
        XCTAssertThrowsError(try ConditionTextParser.parse("  、\n", aliases: aliases))
    }

    private var naturalConditionRules: [ConditionTextRule] {
        [
            ConditionTextRule(id: "sum", title: "判定值和值S", aliases: ["和值", "S"], format: .integerRange, maximum: 24),
            ConditionTextRule(id: "OC_DRAWS", title: "六场平局个数", aliases: ["平局", "平局数"], format: .integerRange, maximum: 6),
            ConditionTextRule(id: "OC_DRUN", title: "最长连续平", aliases: ["连平"], format: .integerRange, maximum: 6),
            ConditionTextRule(id: "displacement", title: "位移M", aliases: ["位移", "M"], format: .integerRange, maximum: 100),
            ConditionTextRule(id: "score", title: "综合评分", aliases: ["评分"], format: .decimalRange, maximum: 100),
            ConditionTextRule(id: "extra.14", title: "第二个双选", aliases: ["第二双选", "第二处双选"]),
            ConditionTextRule(id: "extra.10", title: "赔率乘积下限", aliases: ["赔率乘积"], format: .decimalMinimum, maximum: 1_000_000),
            ConditionTextRule(id: "extra.12", title: "六场彩果断点B=3–5", aliases: ["断点", "六场断点", "B"], format: .integerRange, maximum: 6, fixedValue: "3-5"),
            ConditionTextRule(id: "extra.5", title: "前5场同彩果最长连续≤2场", aliases: ["前5场同彩果连续"], format: .integerMaximum, maximum: 6, fixedValue: "2")
        ]
    }

    func testNaturalConditionInputUnderstandsChineseNumbersAndConversationalBatch() throws {
        XCTAssertEqual(try ConditionTextParser.interpret("请帮我把和值改成十五到二十之间，并且平局不要超过两场，关闭第二个双选", rules: naturalConditionRules), [
            ConditionTextCommand(id: "sum", value: "15-20", enabled: true),
            ConditionTextCommand(id: "OC_DRAWS", value: "0-2", enabled: true),
            ConditionTextCommand(id: "extra.14", value: nil, enabled: false)
        ])
        for input in ["和值15到20和平局两场以内", "Ｓ＝１５～２０；平局上限二场", "和值不低于15且不高于20，平局小于等于2场"] {
            XCTAssertEqual(try ConditionTextParser.interpret(input, rules: naturalConditionRules), [
                ConditionTextCommand(id: "sum", value: "15-20", enabled: true),
                ConditionTextCommand(id: "OC_DRAWS", value: "0-2", enabled: true)
            ], input)
        }
    }

    func testNaturalConditionInputSupportsAdjacentSubjectsAndIntegerComparisons() throws {
        XCTAssertEqual(try ConditionTextParser.interpret("S15-20M3-8平局少于两场", rules: naturalConditionRules), [
            ConditionTextCommand(id: "sum", value: "15-20", enabled: true),
            ConditionTextCommand(id: "displacement", value: "3-8", enabled: true),
            ConditionTextCommand(id: "OC_DRAWS", value: "0-1", enabled: true)
        ])
        XCTAssertEqual(try ConditionTextParser.interpret("平局多于一场", rules: naturalConditionRules).first?.value, "2-6")
        XCTAssertEqual(try ConditionTextParser.interpret("平局正好两场", rules: naturalConditionRules).first?.value, "2-2")
        XCTAssertEqual(try ConditionTextParser.interpret("位移至少三", rules: naturalConditionRules).first?.value, "3-100")
    }

    func testNaturalConditionInputDistinguishesNoOutcomeFromDisablingFilter() throws {
        XCTAssertEqual(try ConditionTextParser.interpret("不要平局", rules: naturalConditionRules), [ConditionTextCommand(id: "OC_DRAWS", value: "0-0", enabled: true)])
        XCTAssertEqual(try ConditionTextParser.interpret("不要连平", rules: naturalConditionRules), [ConditionTextCommand(id: "OC_DRUN", value: "0-1", enabled: true)])
        for text in ["平局关掉", "请关闭平局这个条件", "不要平局这个条件"] {
            XCTAssertEqual(try ConditionTextParser.interpret(text, rules: naturalConditionRules), [ConditionTextCommand(id: "OC_DRAWS", value: nil, enabled: false)], text)
        }
        XCTAssertThrowsError(try ConditionTextParser.interpret("不要平局0到2", rules: naturalConditionRules))
    }

    func testNaturalConditionInputPreservesFixedSwitchThresholds() throws {
        XCTAssertEqual(try ConditionTextParser.interpret("第二双选保持关闭，前五场同彩果连续不超过两场，六场断点三到五", rules: naturalConditionRules), [
            ConditionTextCommand(id: "extra.14", value: nil, enabled: false),
            ConditionTextCommand(id: "extra.5", value: nil, enabled: true),
            ConditionTextCommand(id: "extra.12", value: nil, enabled: true)
        ])
        XCTAssertEqual(try ConditionTextParser.interpret("打开六场彩果断点B=3-5", rules: naturalConditionRules).first?.id, "extra.12")
        for text in ["断点2-5", "前五场同彩果连续不超过三场", "第二双选概率大于80"] {
            XCTAssertThrowsError(try ConditionTextParser.interpret(text, rules: naturalConditionRules), text)
        }
    }

    func testNaturalConditionInputUnderstandsDecimalsAndMinimumsWithoutInventingBounds() throws {
        for text in ["评分五点八到六点八分", "评分5点8至6点8", "评分在5.8和6.8之间"] {
            XCTAssertEqual(try ConditionTextParser.interpret(text, rules: naturalConditionRules).first?.value, "5.8-6.8", text)
        }
        XCTAssertEqual(try ConditionTextParser.interpret("赔率乘积至少三百", rules: naturalConditionRules).first?.value, "300")
        for text in ["赔率乘积最多300", "评分小于6.8", "评分5.8左右", "和值少一点", "平局7以内", "和值20到15", "平局2%", "平局0.5到2"] {
            XCTAssertThrowsError(try ConditionTextParser.interpret(text, rules: naturalConditionRules), text)
        }
    }

    func testNaturalConditionInputRejectsWholeInvalidBatchAndConflictingAliases() throws {
        for text in ["和值15-20，平局9场", "和值15-20，未知条件1-2", "和值15-20，S16-18", "和值15-20，第二双选随便", String(repeating: "和值", count: 1001)] {
            XCTAssertThrowsError(try ConditionTextParser.interpret(text, rules: naturalConditionRules), text)
        }
        let ambiguous = [ConditionTextRule(id: "first", title: "M", aliases: []), ConditionTextRule(id: "second", title: "m", aliases: [])]
        XCTAssertThrowsError(try ConditionTextParser.interpret("M开启", rules: ambiguous))
    }

    func testNaturalConditionInputRejectsMutuallyExclusiveBatchBeforeApplying() throws {
        let rules = [ConditionTextRule(id: "50", title: "50行", aliases: [], exclusionGroup: "lines"),
                     ConditionTextRule(id: "60", title: "60行", aliases: [], exclusionGroup: "lines")]
        XCTAssertThrowsError(try ConditionTextParser.interpret("开启50行，开启60行", rules: rules)) { error in
            XCTAssertTrue(error.localizedDescription.contains("互斥"))
        }
        XCTAssertEqual(try ConditionTextParser.interpret("关闭50行，打开60行", rules: rules), [
            ConditionTextCommand(id: "50", value: nil, enabled: false),
            ConditionTextCommand(id: "60", value: nil, enabled: true)
        ])
    }

    func testConditionSwitchesPreserveOldInputsAndRoundTripWithoutLosingValues() throws {
        let original = try FilterConfig.parse("1,2,3,4,5|CCCCC|12-19|3-11|3|4|0.15|9|2-4|FINAL=OFF|NO4SINGLE=1|NO4=|6:310|7:3|MERGE3")
        XCTAssertTrue(original.disabledBasicConditions.isEmpty)
        let input = FilterConfig.appendingConditionSwitches(to: original.normalizedInput,
            disabled: [.sum, .variance, .breakpoints], valueThreeMaximum: 2)
        let edited = try FilterConfig.parse(input)
        XCTAssertEqual(edited.sumRange, original.sumRange)
        XCTAssertEqual(edited.varianceMaximum, original.varianceMaximum)
        XCTAssertEqual(edited.disabledBasicConditions, [.sum, .variance, .breakpoints])
        XCTAssertEqual(try FilterConfig.parse(edited.normalizedInput), edited)
        let values = FilterInputDefaults.values(from: edited)
        XCTAssertEqual(values["disabledBasicConditions"], "breakpoints,sum,variance")
        XCTAssertEqual(values["valueThreeMaximumInput"], "2")
        XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "BASEOFF=breakpoints,sum,variance", with: "BASEOFF=unknown")))
    }

    func testEachBasicConditionSwitchStopsGenerationAndQueryFiltering() throws {
        let baseline = ["1,2,3,4,5", "CCCCC", "0-24", "0-100", "100", "5", "0", "100", "0-4",
                        "FINAL=OFF", "NO4SINGLE=1", "NO4=", "6:310", "7:3", "MERGE3"]
        let cases: [(BasicCondition, Int, String)] = [
            (.sum, 2, "0-0"), (.displacement, 3, "0-0"), (.variance, 4, "0"),
            (.valueTwo, 5, "0"), (.transition, 6, "100"), (.roughness, 7, "0"), (.breakpoints, 8, "0-0")
        ]
        for (rule, index, restrictiveValue) in cases {
            var fields = baseline
            fields[index] = restrictiveValue
            let strict = try FilterConfig.parse(fields.joined(separator: "|"))
            let disabled = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(
                to: strict.normalizedInput, disabled: [rule]))
            let strictResult = SequenceFilterEngine.calculate(strict, previousContext: nil, applyPoissonRelationshipCondition: false)
            let relaxed = SequenceFilterEngine.calculate(disabled, previousContext: nil, applyPoissonRelationshipCondition: false, captureQueryStages: true)
            XCTAssertLessThan(strictResult.finalBetCount, 729, rule.rawValue)
            XCTAssertEqual(relaxed.finalBetCount, 729, rule.rawValue)
            for target in (0..<5).reduce([[]] as [[Int]], { rows, _ in rows.flatMap { row in [3, 1, 0].map { row + [$0] } } }) {
                XCTAssertTrue(SequenceFilterEngine.baseFilterFailureReasons(for: target, config: disabled).isEmpty, rule.rawValue)
            }
        }
    }

    func testDisabledBasicConditionsDoNotCountAsToleranceFailures() throws {
        let input = "1,2,3,4,5|CCCCC|0-0|0-0|0|0|100|0|0-0|FINAL=OFF|NO4SINGLE=1|NO4=|ALLTOLON=1|ALLTOL=0-0|6:310|7:3|MERGE3"
        let config = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: input,
            disabled: [.sum, .displacement, .variance, .valueTwo, .transition, .roughness, .breakpoints]))
        XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil, applyPoissonRelationshipCondition: false).finalBetCount, 729)
    }

    func testDisabledSumAlsoStopsAdaptiveAndAdditionalSumFiltering() throws {
        let input = FilterConfig.svip11Input(numbers: (1...6).map(String.init), logic: "CCCCCC", extras: ["7:3"],
            noFourPosition: nil, sumRange: "0-0", mRange: "0-100", breakpointRange: "0-4", adaptiveS: true)
        let config = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: input, disabled: [.sum]))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 729)
        XCTAssertTrue(SequenceFilterEngine.baseFilterFailureReasons(for: [3,3,3,3,3,3], config: config).isEmpty)
    }

    func testSVIP11KeepsEnteredConditionsAndSwitchesDuringIsolation() throws {
        let base = FilterConfig.svip11Input(numbers: (1...6).map(String.init), logic: "CCCCCC", extras: ["7:3"], noFourPosition: nil)
        let disabled: Set<BasicCondition> = [.sum, .displacement, .breakpoints]
        let config = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: base,
            disabled: disabled, outcomeRanges: [.draws: "0-0"]))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.config.disabledBasicConditions, disabled)
        XCTAssertEqual(result.config.outcomeConditions[.draws], 0...0)
        XCTAssertEqual(result.finalBetCount, 96) // First five exclude draws; sixth retains all three.
        XCTAssertTrue(result.records.allSatisfy { !$0.outcomes.prefix(5).contains(1) })
        XCTAssertFalse(SequenceFilterEngine.baseFilterFailureReasons(for: [1,3,3,3,3,3], config: config).isEmpty)
    }

    func testSVIP10CoreSwitchesDoNotReenableFrozenFiltersOrRequireDisabledScoreOdds() throws {
        let base = FilterConfig.svip10Input(numbers: (1...6).map(String.init), logic: "CCCCCC", extras: ["7:3"])
        let disabled = Set(BasicCondition.allCases)
        let config = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: base,
            disabled: disabled, valueThreeMaximum: 0, outcomeRanges: [.draws: "0-0"]))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 64)
        XCTAssertEqual(result.config.valueThreeMaximum, 0)
        XCTAssertEqual(result.config.disabledBasicConditions, disabled)
        XCTAssertTrue(SequenceFilterEngine.six250FailureReasons(outcomes: [3,3,3,3,3,3], config: config, customOdds: nil).isEmpty)
    }

    func testSVIP7FrozenRulesHaveIndependentSwitches() throws {
        let input = "1,2,3,4,5,6|CCCCCC|0-24|0-100|100|6|0|100|0-5|FINAL=OFF|NO4SINGLE=1|NO4=|SVIP7=1|7:3|MERGE3"
        let disabled: Set<BasicCondition> = [.oddsProduct, .oddsSum, .oddsRank]
        let config = try FilterConfig.parse(FilterConfig.appendingConditionSwitches(to: input, disabled: disabled))
        XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil, applyPoissonRelationshipCondition: false).finalBetCount, 729)
        XCTAssertTrue(SequenceFilterEngine.svip7FailureReasons(outcomes: [3,3,3,3,3,3], customOdds: nil, disabled: disabled).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: [3,3,3,3,3,3], customOdds: nil, disabled: [.oddsProduct, .oddsRank]).isEmpty)
    }


    private func archivedTXT(at date: Date, id: UUID = UUID(), text: String = "1→3，2→1，3→0，4→3，5→1，6→0，7→3") -> SharedTXTQueryRecord {
        SharedTXTQueryRecord(
            id: id, sharedAt: date, issue: "26107", filename: "saved.txt",
            txtContent: text, normalizedInput: "frozen-input",
            matchNumbers: (1...7).map(String.init), betOutcomes: [[3, 1, 0, 3, 1, 0, 3]],
            finalBetCount: 1, conditionSignature: "older-condition-signature",
            lastCheckedAt: nil, observedOutcomes: nil, observedHandicaps: nil,
            verificationMessage: nil, isFinalResult: false, isHit: nil,
            prizeAmount: nil, prizeSPValues: nil
        )
    }

    func testRecentTXTArchiveKeepsAllGenerationsAndExact48HourBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let records = (0..<8).map { archivedTXT(at: now.addingTimeInterval(Double(-$0 * 3600))) }
        let boundary = archivedTXT(at: now.addingTimeInterval(-48 * 3600))
        let expired = archivedTXT(at: boundary.sharedAt.addingTimeInterval(-1))
        let retained = RecentTXTQueryArchive.retained(records + [expired, boundary], now: now)
        XCTAssertEqual(retained.count, 9)
        XCTAssertEqual(Set(retained.map(\.id)), Set((records + [boundary]).map(\.id)))
        XCTAssertEqual(retained.first?.id, boundary.id)
        XCTAssertEqual(retained.last?.id, records.first?.id)
        // 同一期号、同场次、同文件名的多次生成均保留，不限制最新5份。
        XCTAssertEqual(Set(retained.map(\.filename)).count, 1)
    }

    func testRecentTXTArchiveRoundTripPreservesOriginalTextAndLatestVerification() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let original = archivedTXT(at: now, text: "E：1→3，2→1，3→0，4→3，5→1，6→0，7→3\n")
        var checked = original
        checked.lastCheckedAt = now.addingTimeInterval(10)
        checked.observedOutcomes = [3, 1, 0, 3, 1, 0]
        checked.isFinalResult = true
        checked.isHit = true
        let records = RecentTXTQueryArchive.retained([original, checked], now: now)
        let restored = try JSONDecoder().decode([SharedTXTQueryRecord].self, from: JSONEncoder().encode(records))
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, original.id)
        XCTAssertEqual(restored[0].sharedAt, original.sharedAt)
        XCTAssertEqual(restored[0].txtContent, original.txtContent)
        XCTAssertEqual(restored[0].betOutcomes, original.betOutcomes)
        XCTAssertEqual(restored[0].conditionSignature, "older-condition-signature")
        XCTAssertEqual(restored[0].lastCheckedAt, checked.lastCheckedAt)
        XCTAssertEqual(restored[0].isHit, true)
    }

    func testRecentTXTArchiveChecksFrozenFirstSixBetsOnlyAfterFinalResults() {
        let bets = [[3, 1, 0, 3, 1, 0, 3], [0, 1, 0, 3, 1, 0, 1]]
        XCTAssertEqual(RecentTXTQueryArchive.hit(bets: bets, outcomes: [3, 1, 0, 3, 1, 0, 0], isFinal: true), true)
        XCTAssertEqual(RecentTXTQueryArchive.hit(bets: bets, outcomes: [0, 1, 0, 3, 1, 0], isFinal: true), true)
        XCTAssertEqual(RecentTXTQueryArchive.hit(bets: bets, outcomes: [1, 1, 0, 3, 1, 0], isFinal: true), false)
        XCTAssertNil(RecentTXTQueryArchive.hit(bets: bets, outcomes: [3, 1, 0, 3, 1, 0], isFinal: false))
        XCTAssertNil(RecentTXTQueryArchive.hit(bets: bets, outcomes: [3, 1, 0, 3, 1, nil], isFinal: true))
        XCTAssertNil(RecentTXTQueryArchive.hit(bets: bets, outcomes: [3, 1, 0, 3, 1], isFinal: true))
        XCTAssertNil(RecentTXTQueryArchive.hit(bets: bets, outcomes: [3, 1, 0, 3, 1, 2], isFinal: true))
        XCTAssertEqual(RecentTXTQueryArchive.hit(bets: [[3, 1, 0]], outcomes: [3, 1, 0, 3, 1, 0], isFinal: true), false)
    }

    func testScoreMatchPaginationUsesThirtyMatchesAndKeepsFinalRemainder() {
        XCTAssertEqual(ScoreMatchPagination.pageRanges(totalCount: 0), [])
        XCTAssertEqual(ScoreMatchPagination.pageRanges(totalCount: 30), [0..<30])
        XCTAssertEqual(ScoreMatchPagination.pageRanges(totalCount: 31), [0..<30, 30..<31])
        XCTAssertEqual(ScoreMatchPagination.pageRanges(totalCount: 78), [0..<30, 30..<60, 60..<78])
    }

    func testAsianWaterUsesCurrentAsianMarketNotInitialEuropeanOrTotals() throws {
        let data = Data(#"[[[0.77,"半球",1.03],["0.92","平手/半球","0.88"]],[[9,8,7],[6,5,4]],[[1,"2.5",1],[1,"3",1]]]"#.utf8)
        let quote = try FiveHundredBeijingSingleClient.parseAsianHandicapQuote(data: data, companyName: "测试机构")
        XCTAssertEqual(quote.companyID, 3)
        XCTAssertEqual(quote.companyName, "测试机构")
        XCTAssertEqual(quote.current.homeWater, 0.92)
        XCTAssertEqual(quote.current.awayWater, 0.88)
        XCTAssertEqual(quote.current.handicap, "平手/半球")
        XCTAssertEqual(quote.initial?.homeWater, 0.77)
        XCTAssertEqual(quote.current.displayText, "主水 0.920  │  平手/半球  │  客水 0.880")
    }

    func testAsianWaterRejectsMissingCurrentAndInvalidValuesWithoutFallback() {
        let invalid = [
            #"[[[0.8,"半球",1.0],null],[[2,3,4],[2,3,4]]]"#,
            #"[null,[[2,3,4],[2,3,4]]]"#,
            #"[[null,[true,"平手",0.9]]]"#,
            #"[[null,[0,"平手",0.9]]]"#,
            #"[[null,[0.9,"-",0.9]]]"#,
            #"[[null,["nan","平手",0.9]]]"#,
            #"[[null,[0.9,"平手"]]]"#,
            #"{ "error": "unavailable" }"#
        ]
        for json in invalid {
            XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseAsianHandicapQuote(data: Data(json.utf8)))
        }
    }

    func testEFPartitionPrioritizesLineEqualityAndKeepsEveryRowExactlyOnce() {
        for count in 0...101 {
            let weights = (0..<count).map { $0 == 0 ? 729 : ($0 % 9 + 1) }
            let parts = SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: weights)
            XCTAssertEqual(parts.count, 2)
            XCTAssertEqual(parts[0].count, (count + 1) / 2)
            XCTAssertEqual(parts[1].count, count / 2)
            XCTAssertTrue(Set(parts[0]).isDisjoint(with: Set(parts[1])))
            XCTAssertEqual((parts[0] + parts[1]).sorted(), Array(0..<count))
            XCTAssertEqual(parts, SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: weights))
        }
        let weights = [100, 90, 10, 1]
        let parts = SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: weights)
        XCTAssertEqual(parts.map { $0.count }, [2,2])
        XCTAssertLessThanOrEqual(abs(parts[0].reduce(0) { $0 + weights[$1] } - parts[1].reduce(0) { $0 + weights[$1] }), 1)
    }

    func testEFCompleteRowAllocationPreservesExpandedBetsAndTotalLineCount() {
        let values = [3,1,0]
        let rows: [[[Int]]] = (0..<7).map { index in
            [[values[index / 3]], [values[index % 3]], Array(values.prefix(index % 3 + 1)), [3,1], [3], [0], [1]]
        }
        let parts = SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: rows.map { $0.reduce(1) { $0 * $1.count } })
        let all = Set(rows.flatMap(expandedOutcomes))
        let e = Set(parts[0].flatMap { expandedOutcomes(rows[$0]) })
        let f = Set(parts[1].flatMap { expandedOutcomes(rows[$0]) })
        XCTAssertEqual(parts.map(\.count), [4,3])
        XCTAssertTrue(e.isDisjoint(with: f))
        XCTAssertEqual(e.union(f), all)
        XCTAssertEqual(e.count + f.count, all.count)
    }

    func testETXTMaximum15RowsAtBoundariesAndKeepsEverySourceRow() {
        for count in [0, 1, 2, 29, 30, 31, 32, 60, 101, 729] {
            let weights = (0..<count).map { $0 == 0 ? 729 : $0 % 27 + 1 }
            let parts = SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: weights,
                maximumERows: SequenceFilterEngine.eTXTMaximumRows)
            XCTAssertEqual(parts[0].count, min(15, (count + 1) / 2))
            XCTAssertEqual(parts[1].count, count - parts[0].count)
            XCTAssertTrue(Set(parts[0]).isDisjoint(with: Set(parts[1])))
            XCTAssertEqual((parts[0] + parts[1]).sorted(), Array(weights.indices))
            XCTAssertEqual(parts.flatMap { $0 }.reduce(0) { $0 + weights[$1] }, weights.reduce(0, +))
            XCTAssertEqual(parts, SequenceFilterEngine.balancedTXTPartitionIndices(rowWeights: weights,
                maximumERows: SequenceFilterEngine.eTXTMaximumRows))
        }
    }

    func testETXT15RowCapPreservesExpandedCoverageWithoutDuplicateBets() {
        let values = [3, 1, 0]
        let rows: [[[Int]]] = (0..<45).map { index in
            [[values[index / 27]], [values[index / 9 % 3]], [values[index / 3 % 3]],
             [values[index % 3]], [3, 1], [0], [1]]
        }
        let parts = SequenceFilterEngine.balancedTXTPartitionIndices(
            rowWeights: rows.map { $0.reduce(1) { $0 * $1.count } },
            maximumERows: SequenceFilterEngine.eTXTMaximumRows)
        let all = Set(rows.flatMap(expandedOutcomes))
        let e = Set(parts[0].flatMap { expandedOutcomes(rows[$0]) })
        let f = Set(parts[1].flatMap { expandedOutcomes(rows[$0]) })
        XCTAssertEqual(parts.map(\.count), [15, 30])
        XCTAssertEqual(all.count, 90)
        XCTAssertTrue(e.isDisjoint(with: f))
        XCTAssertEqual(e.union(f), all)
        XCTAssertEqual(e.count + f.count, all.count)
    }

    private func seventhMarketHTML(line: String = "受让半球", sp: String = "<span>2.91</span><span>2.82</span><span>3.30</span>") -> String {
        let lineHTML = line.isEmpty ? "" : "<a class='fgreen' data-ao='受让平手/半球' data-pb='\(line)'>\(line)</a>"
        return """
        <script>window.live_cur_expect = "26107";</script>
        <table id='table_match'><tr id='a1450883' status='4'>
        <td><input type='checkbox' />83</td><td>测试联赛</td><td>1</td><td>10-24 20:00</td><td>完</td>
        <td><a>主队</a><span class='sp_rq'>(-1)</span></td>
        <td><div class='pk'><a>2</a>\(lineHTML)<a>1</a></div></td>
        <td><a>客队</a></td><td>-</td><td class='bf_op'>\(sp)</td>
        </tr></table>
        <script>var liveOddsList = {"1450883":{"0":["1.10","8.20","9.30"]}};</script>
        """
    }

    func testSeventhMarketDisplaysRaw500SPAndActualAsianLineSeparately() throws {
        let time = Date(timeIntervalSince1970: 123)
        let snapshot = try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(
            html: seventhMarketHTML(), issue: "26107", matchNumber: "0083", capturedAt: time)
        XCTAssertEqual(snapshot.match.matchNumber, "83")
        XCTAssertEqual(snapshot.match.handicap, -1)
        XCTAssertEqual(snapshot.asianHandicap, "受让半球")
        XCTAssertEqual(snapshot.referenceSPText, "胜 2.91  平 2.82  负 3.30")
        XCTAssertFalse(snapshot.referenceSPText.contains("8.20"))
        XCTAssertEqual(snapshot.capturedAt, time)
    }

    func testSeventhMarketMissingFieldsNeverBecomeHandicapOrOrdinaryOdds() throws {
        let snapshot = try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(
            html: seventhMarketHTML(line: "", sp: "<span>-</span>"), issue: "26107", matchNumber: "83")
        XCTAssertNil(snapshot.asianHandicap)
        XCTAssertEqual(snapshot.match.handicap, -1)
        XCTAssertEqual(snapshot.referenceSPText, "未发布完整三项SP")
        XCTAssertEqual(snapshot.match.marketOdds, [1.10, 8.20, 9.30])
    }

    func testSeventhMarketSettledOnlySPIsClearlyLabeled() throws {
        let snapshot = try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(
            html: seventhMarketHTML(line: "平手/半球", sp: "<span>2.33</span>"), issue: "26107", matchNumber: "83")
        XCTAssertEqual(snapshot.asianHandicap, "平手/半球")
        XCTAssertEqual(snapshot.referenceSPText, "开奖SP：平 2.33（三项未齐）")
    }

    func testSeventhMarketRejectsWrongIssueAndMissingMatch() {
        let html = seventhMarketHTML()
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(html: html, issue: "26106", matchNumber: "83"))
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(html: html, issue: "26107", matchNumber: "84"))
        for number in ["", "0", "-1", "+83", "83a"] {
            XCTAssertThrowsError(try FiveHundredBeijingSingleClient.parseSeventhMatchMarket(html: html, issue: "26107", matchNumber: number))
        }
    }

    func testDurableBackupCompressionRoundTripsLargeHistoryPayload() {
        let row = "26098|28,29,30,31,32,33|3,1,0,3,1,0|最终171注\n"
        let payload = Data(String(repeating: row, count: 70_000).utf8)
        XCTAssertGreaterThan(payload.count, 3_000_000)
        XCTAssertEqual(DurableAppBackup.compressedRoundTripForTesting(payload), payload)
    }

    func testInputFailureDiagnosisUsesFrozenSVIP7OddsAndActualStage() throws {
        let config = try FilterConfig.parse("1,2,3,4,5,6|ABCDAB|0-24|0-100|100|6|0|100|0-5|SVIP7=1|SIXSCOPE=1|FINAL=OFF|7:3|MERGE3")
        let generated = SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeSPs: Array(repeating: [2.0, 3.0, 4.0], count: 6), captureQueryStages: true)
        let diagnosis = generated.inputFailureDiagnosis(for: [3,3,3,3,3,3])
        XCTAssertEqual(diagnosis.isHit, false)
        XCTAssertTrue(diagnosis.text.contains("未过关"))
        XCTAssertTrue(diagnosis.text.contains("64.0000"))
        XCTAssertTrue(diagnosis.text.contains("300–800"))
        XCTAssertTrue(diagnosis.text.contains("实际淘汰阶段"))
        XCTAssertTrue(diagnosis.text.contains("本次生成时保存"))
        let pass = generated.inputFailureDiagnosis(for: [3,3,1,1,0,0])
        XCTAssertEqual(pass.isHit, true)
        XCTAssertTrue(pass.text.contains("已过关"))
        XCTAssertFalse(pass.text.contains("实际淘汰阶段"))
    }

    func testInputFailureDiagnosisDoesNotInventReasonsForMissingTraceOrInvalidOutcomes() throws {
        let config = try FilterConfig.parse("1,2,3,4,5,6|AAAAAA|0-0|0-20|100|6|0|100|0-5|FINAL=OFF|7:3|MERGE3")
        let generated = SequenceFilterEngine.calculate(config, previousContext: nil)
        let missing = generated.inputFailureDiagnosis(for: [3,3,3,3,3,3])
        XCTAssertNil(missing.isHit)
        XCTAssertTrue(missing.text.contains("请重新全局生成"))
        XCTAssertFalse(missing.text.contains("计算结果：前六场未过关"))
        for target in [[3,1], [9,3,3,3,3,3]] {
            let invalid = generated.inputFailureDiagnosis(for: target)
            XCTAssertNil(invalid.isHit)
            XCTAssertTrue(invalid.text.contains("须输入六场3/1/0赛果"))
        }
    }

    func testInputFailureDiagnosisReportsFinalEliminationAfterReintroduction() throws {
        let config = try FilterConfig.parse("1,2,3,4,5,6|AAAAAA|0-0|0-20|100|6|0|100|0-5|FINAL=OFF|7:3|MERGE3")
        var generated = SequenceFilterEngine.calculate(config, previousContext: nil)
        let target = [3,3,3,3,3,3]
        generated.queryStages = [
            FilterQueryStage(name: "输入全集", survivors: [target]),
            FilterQueryStage(name: "早期淘汰", survivors: []),
            FilterQueryStage(name: "重新加入", survivors: [target]),
            FilterQueryStage(name: "最终实际拦截条件", survivors: [])
        ]
        let diagnosis = generated.inputFailureDiagnosis(for: target)
        XCTAssertEqual(diagnosis.isHit, false)
        XCTAssertTrue(diagnosis.text.contains("最终实际拦截条件"))
        XCTAssertFalse(diagnosis.text.contains("早期淘汰"))
    }

    func testVIPInputFailureReasonsIdentifyOnlyUncoveredSelectionLegs() {
        let options = [[3], [3,1]] + Array(repeating: [3,1,0], count: 4)
        let legs = options.enumerated().map { index, choices in
            VIP1SevenLeg(number: index + 10, home: "主", away: "客", matchTime: "10-21 20:00",
                options: choices, customOdds: [2,3,4], coverageProbability: 1)
        }
        let selection = VIP1SevenSelection(issue: "26106", start: 10, end: 20, legs: legs)
        let reasons = selection.missReasons(outcomes: [0,0,0,0,0,0])
        XCTAssertEqual(reasons.count, 2)
        XCTAssertTrue(reasons[0].contains("场次10"))
        XCTAssertTrue(reasons[1].contains("场次11"))
        XCTAssertTrue(reasons.allSatisfy { $0.contains("实际让球赛果") })
        XCTAssertTrue(selection.missReasons(outcomes: [3,1,0,0,0,0]).isEmpty)
    }

    func testOverallOddsForecastBlocksLowMedianAndFindsWeakestMatch() {
        let odds = [
            [1.5, 1.5, 1.5],
            [2.0, 2.0, 2.0],
            [3.0, 3.0, 3.0],
            [3.0, 3.0, 3.0],
            [3.0, 3.0, 3.0],
            [3.0, 3.0, 3.0]
        ]
        let forecast = SequenceFilterEngine.overallOddsForecast(
            bets: [[3, 3, 3, 3, 3, 3], [0, 0, 0, 0, 0, 0]],
            customOdds: odds
        )

        XCTAssertEqual(forecast?.medianProduct ?? -1, 243, accuracy: 1e-12)
        XCTAssertTrue(forecast?.isLow == true)
        XCTAssertEqual(forecast?.weakestPosition, 1)
        XCTAssertEqual(forecast?.weakestMedianSelectedOdd ?? -1, 1.5, accuracy: 1e-12)
    }

    func testOverallOddsForecastAllowsMedianAtThreshold() {
        let row = [3.0, 3.0, 3.0]
        let forecast = SequenceFilterEngine.overallOddsForecast(
            bets: [[3, 1, 0, 3, 1, 0]],
            customOdds: Array(repeating: row, count: 6),
            threshold: 729
        )

        XCTAssertEqual(forecast?.medianProduct ?? -1, 729, accuracy: 1e-12)
        XCTAssertFalse(forecast?.isLow ?? true)
    }

    func testVIP1SingleSelectionRejectsCustomOddsBelowTwo() {
        let odds = [1.60, 2.00, 3.20]
        let inverse = odds.map { 1 / $0 }
        let total = inverse.reduce(0, +)
        let probabilities = inverse.map { $0 / total }

        let selected = VIP1SevenMatchSelector.eligibleSingleIndex(
            customOdds: odds,
            probabilities: probabilities
        )

        XCTAssertEqual(selected, 1)
        XCTAssertGreaterThanOrEqual(odds[selected!], 2.0)
        XCTAssertNotEqual(selected, 0)
    }

    func testVIP1SingleSelectionReturnsNilWhenEveryCustomOddIsBelowTwo() {
        XCTAssertNil(VIP1SevenMatchSelector.eligibleSingleIndex(
            customOdds: [1.50, 1.80, 1.99],
            probabilities: [0.5, 0.3, 0.2]
        ))
    }

    func testVIP1SingleSelectionPrefersActualHandicapMatches() {
        XCTAssertEqual(
            VIP1SevenMatchSelector.preferredSingleCandidateIndices(
                handicaps: [0, -1, 1, 0],
                hasEligibleDirection: [true, true, false, true]
            ),
            [1]
        )
        XCTAssertEqual(
            VIP1SevenMatchSelector.preferredSingleCandidateIndices(
                handicaps: [0, -1, 0],
                hasEligibleDirection: [true, false, true]
            ),
            [0, 2]
        )
    }


    func testVIP1TXTPartitionsContainBothEAndFWithoutMissingOrDuplicateBets() {
        let optionRows = [
            [3], [3, 1],
            [3, 1, 0], [3, 1, 0], [3, 1, 0], [3, 1, 0]
        ]
        let legs = optionRows.enumerated().map { index, options in
            VIP1SevenLeg(
                number: index + 1,
                home: "主\(index + 1)",
                away: "客\(index + 1)",
                matchTime: "10-20 20:00",
                options: options,
                customOdds: [2, 3, 4],
                coverageProbability: 1
            )
        }
        let selection = VIP1SevenSelection(issue: "26106", start: 1, end: 7, legs: legs)

        XCTAssertEqual(selection.betCount, 162)
        XCTAssertEqual(selection.txtPartitions.map(\.label), [Optional("E"), Optional("F")])
        XCTAssertEqual(selection.txtPartitions.map(\.betCount), [81, 81])

        let original = Set(expandedOutcomes(optionRows))
        let e = Set(expandedOutcomes(selection.txtPartitions[0].options))
        let f = Set(expandedOutcomes(selection.txtPartitions[1].options))
        XCTAssertTrue(e.isDisjoint(with: f))
        XCTAssertEqual(e.union(f), original)
    }

    func testVIP2TXTPartitionsContainBothEAndFWithoutMissingOrDuplicateBets() {
        let optionRows = [
            [3, 1], [3, 0],
            [3, 1, 0], [3, 1, 0], [3, 1, 0], [3, 1, 0]
        ]
        let legs = optionRows.enumerated().map { index, options in
            VIP1SevenLeg(
                number: index + 1,
                home: "主\(index + 1)",
                away: "客\(index + 1)",
                matchTime: "10-20 20:00",
                options: options,
                customOdds: [2, 3, 4],
                coverageProbability: 1
            )
        }
        let selection = VIP1SevenSelection(
            issue: "26106",
            start: 1,
            end: 7,
            legs: legs
        )

        XCTAssertEqual(selection.betCount, 324)
        XCTAssertEqual(selection.txtPartitions.map(\.label), [Optional("E"), Optional("F")])
        XCTAssertEqual(selection.txtPartitions.map(\.betCount), [162, 162])

        let original = Set(expandedOutcomes(optionRows))
        let e = Set(expandedOutcomes(selection.txtPartitions[0].options))
        let f = Set(expandedOutcomes(selection.txtPartitions[1].options))
        XCTAssertTrue(e.isDisjoint(with: f))
        XCTAssertEqual(e.union(f), original)
    }

    func testSVIP10AdditionalRulesAndProtocolRoundTrip() throws {
        let base = FilterConfig.svip10Input(
            numbers: ["1", "2", "3", "4", "5", "6"],
            logic: "ABCDAB",
            extras: ["7:3"],
            enabled: true,
            scoreRange: "6.2-8",
            noFourPosition: nil,
            sumRange: "14-19",
            mRange: "2-10"
        )
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            base,
            coldEnabled: true,
            coldRange: "0-2",
            drawEnabled: false,
            drawRange: "0-3",
            winLossSwitchEnabled: true,
            highestDoubleProbabilityTopTwoEnabled: true,
            secondDoubleLowestProbabilityEnabled: true,
            fiveMatchMEnabled: true,
            fiveMatchMRange: "2-5",
            frontFiveSameOutcomeRunMaximum2Enabled: true,
            frontFiveReturnMaximum2Enabled: true,
            frontFiveNoConsecutiveDrawEnabled: true,
            frontFiveValueThreeMaximum2Enabled: true,
            sixMatchFavoriteCount1To4Enabled: true,
            sixMatchMinimumOddsProductEnabled: true,
            sixMatchMinimumOddsProduct: "380",
            sixMatchBreakpoint3To5Enabled: true,
            topThreeProbabilityRecovery100Enabled: true,
            statisticalLineBudgetEnabled: true
        )
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.svip10AdditionalFilters.coldCountEnabled)
        XCTAssertEqual(config.svip10AdditionalFilters.coldCountRange, 0...2)
        XCTAssertFalse(config.svip10AdditionalFilters.drawCountEnabled)
        XCTAssertTrue(config.svip10AdditionalFilters.winLossSwitchEnabled)
        XCTAssertFalse(config.svip10AdditionalFilters.highestDoubleProbabilityNoFourEnabled)
        XCTAssertTrue(config.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled)
        XCTAssertTrue(config.svip10AdditionalFilters.secondDoubleLowestProbabilityEnabled)
        XCTAssertTrue(config.svip10AdditionalFilters.fiveMatchMEnabled)
        XCTAssertEqual(config.svip10AdditionalFilters.fiveMatchMRange, 2...5)
        XCTAssertTrue(config.svip10AdditionalFilters.frontFiveSameOutcomeRunMaximum2Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.frontFiveReturnMaximum2Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.frontFiveNoConsecutiveDrawEnabled)
        XCTAssertTrue(config.svip10AdditionalFilters.frontFiveValueThreeMaximum2Enabled)
        XCTAssertFalse(config.svip10AdditionalFilters.sixMatchFavoriteCount2To4Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.sixMatchFavoriteCount1To4Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.sixMatchMinimumOddsProductEnabled)
        XCTAssertEqual(config.svip10AdditionalFilters.sixMatchMinimumOddsProduct, 380)
        XCTAssertFalse(config.svip10AdditionalFilters.sixMatchBreakpoint2To4Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled)
        XCTAssertTrue(config.svip10AdditionalFilters.statisticalLineBudgetEnabled)
        XCTAssertFalse(config.svip10AdditionalFilters.probabilityMass60Enabled)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)

        let favoriteOdds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [1, 1, 1, 1, 1, 1], config: config, customOdds: favoriteOdds, onlyRule: 15
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 1, 1, 1, 1], config: config, customOdds: favoriteOdds, onlyRule: 15
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 3, 3, 1], config: config, customOdds: favoriteOdds, onlyRule: 15
        ).isEmpty)

        let odds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [0, 0, 3, 3, 3, 3], config: config, customOdds: odds, onlyRule: 0
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [0, 0, 0, 3, 3, 3], config: config, customOdds: odds, onlyRule: 0
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 3, 3, 3], config: config, customOdds: nil, onlyRule: 0
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 0, 3, 1, 0, 3], config: config, customOdds: odds, onlyRule: 2
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 0, 3, 0, 3, 1], config: config, customOdds: odds, onlyRule: 2
        ).isEmpty)

        let doubleOdds = [[1.10, 10.0, 10.0]] + Array(repeating: [3.0, 3.0, 3.0], count: 5)
        let selection = config.highestDoubleProbabilityNoFourSelection(in: doubleOdds)
        XCTAssertEqual(selection?.position, 1)
        XCTAssertGreaterThan(selection?.probability ?? 0, 0.9)
        XCTAssertEqual(config.highestDoubleProbabilityNoFourSelection(in: odds)?.position, 1)
        var forbidden = [3, 3, 3, 3, 3, 3]
        forbidden[0] = 0
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: forbidden, config: config, customOdds: doubleOdds, onlyRule: 13
        ).isEmpty)
        forbidden[0] = 3
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: forbidden, config: config, customOdds: doubleOdds, onlyRule: 13
        ).isEmpty)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: doubleOdds)
        XCTAssertEqual(result.config.resolvedHighestDoubleProbabilityNoFourPosition, 1)
        XCTAssertLessThanOrEqual(result.exportCompressedRecords.count, 50)
    }

    func testSVIP10SecondDoubleStaysWithinSixAndRemovesModelLowestOption() throws {
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            FilterConfig.svip10Input(
                numbers: ["101", "102", "103", "104", "105", "106"], logic: "ABCDAB",
                extras: ["107:3"], enabled: true, scoreRange: "0-100",
                noFourPosition: nil, sumRange: "0-24", mRange: "0-100"
            ),
            coldEnabled: false, coldRange: "0-2", drawEnabled: false, drawRange: "0-3",
            highestDoubleProbabilityTopTwoEnabled: true,
            secondDoubleLowestProbabilityEnabled: true
        )
        let config = try FilterConfig.parse(input)
        let odds = [[1.10, 10, 10]] + Array(repeating: [2.0, 3.0, 4.0], count: 5)
        let probabilities = [
            [0.70, 0.20, 0.10],
            [0.45, 0.44, 0.11],
            [0.40, 0.35, 0.25],
            [0.38, 0.34, 0.28],
            [0.37, 0.33, 0.30],
            [0.36, 0.33, 0.31]
        ]
        let result = SequenceFilterEngine.calculate(
            config, previousContext: nil,
            currentOutcomeProbabilities: probabilities, currentOutcomeSPs: odds,
            captureQueryStages: true
        )

        XCTAssertEqual(result.config.resolvedHighestDoubleProbabilityNoFourPosition, 1)
        XCTAssertEqual(result.config.resolvedSecondDoublePosition, 2)
        XCTAssertEqual(result.config.resolvedSecondDoubleRemovedOutcome, 0)
        XCTAssertEqual(result.config.logic[1].value(for: 0), 3)
        XCTAssertTrue(result.config.resolvedSecondDoubleUsesModelProbability)
        XCTAssertEqual(result.config.resolvedSecondDoubleProbability ?? 0, 0.89, accuracy: 1e-12)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { $0[1] != 0 })
        XCTAssertTrue(result.queryStages.contains { $0.name.contains("第二个双选第2场") && $0.name.contains("判定值3") })

        let removed = SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 0, 3, 3, 3, 3], config: result.config,
            customOdds: odds, onlyRule: 14
        )
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed[0].contains("最低概率项0／判定值3"))
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 3, 3, 3, 3], config: result.config,
            customOdds: odds, onlyRule: 14
        ).isEmpty)

        var secondOnly = config
        secondOnly.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled = false
        XCTAssertNotNil(SequenceFilterEngine.svip10SecondDoubleSelection(
            config: secondOnly, currentOutcomeProbabilities: probabilities, customOdds: odds
        ))
    }

    func testSVIP10FiveMatchMUsesSelectableRangeAndABCDValues() throws {
        let base = FilterConfig.svip10Input(
            numbers: ["1", "2", "3", "4", "5", "6"], logic: "AAAAAA",
            extras: ["7:3"], enabled: true, scoreRange: "0-100",
            noFourPosition: nil, sumRange: "0-24", mRange: "0-100"
        )
        let firstStart = try FilterConfig.parse(FilterConfig.appendingSVIP10AdditionalInput(
            base, coldEnabled: false, coldRange: "0-2", drawEnabled: false, drawRange: "0-3",
            fiveMatchMEnabled: true, fiveMatchMRange: "3-6"
        ))
        let outcomes = [3, 0, 3, 3, 3, 3] // A映射后为2,4,2,2,2,2。
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: outcomes, config: firstStart, customOdds: nil, onlyRule: 4
        ).isEmpty)

        let adjustedRange = try FilterConfig.parse(firstStart.normalizedInput
            .replacingOccurrences(of: "S10F5MRANGE=3-6", with: "S10F5MRANGE=5-6"))
        let reasons = SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: outcomes, config: adjustedRange, customOdds: nil, onlyRule: 4
        )
        XCTAssertEqual(reasons.count, 1)
        XCTAssertTrue(reasons[0].contains("实际4"))
        XCTAssertEqual(FilterInputDefaults.values(from: adjustedRange)["svip10FiveMatchMRangeInput"], "5-6")

        let legacy = try FilterConfig.parse(base)
        XCTAssertFalse(legacy.svip10AdditionalFilters.fiveMatchMEnabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.highestDoubleProbabilityTopTwoEnabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: outcomes, config: legacy, customOdds: nil, onlyRule: 4
        ).isEmpty)
    }

    func testSVIP10ConcreteFrontFiveStructureConditions() throws {
        let base = FilterConfig.svip10Input(
            numbers: ["1", "2", "3", "4", "5", "6"], logic: "AAAAAA",
            extras: ["7:3"], enabled: true, scoreRange: "0-100",
            noFourPosition: nil, sumRange: "0-24", mRange: "0-100"
        )
        let config = try FilterConfig.parse(FilterConfig.appendingSVIP10AdditionalInput(
            base, coldEnabled: false, coldRange: "0-2", drawEnabled: false, drawRange: "0-3",
            frontFiveSameOutcomeRunMaximum2Enabled: true,
            frontFiveReturnMaximum2Enabled: true,
            frontFiveNoConsecutiveDrawEnabled: true,
            frontFiveValueThreeMaximum2Enabled: true,
            sixMatchFavoriteCount2To4Enabled: true,
            sixMatchMinimumOddsProductEnabled: true,
            sixMatchMinimumOddsProduct: "380",
            sixMatchBreakpoint3To5Enabled: true
        ))

        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 0, 1, 3], config: config, customOdds: nil, onlyRule: 5
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 0, 0, 1, 3], config: config, customOdds: nil, onlyRule: 5
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 0, 3, 0, 3, 1], config: config, customOdds: nil, onlyRule: 6
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 0, 3, 0, 1, 1], config: config, customOdds: nil, onlyRule: 6
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 1, 0, 3, 1], config: config, customOdds: nil, onlyRule: 7
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 0, 1, 3, 1], config: config, customOdds: nil, onlyRule: 7
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [1, 1, 1, 3, 0, 3], config: config, customOdds: nil, onlyRule: 8
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [1, 1, 3, 3, 0, 3], config: config, customOdds: nil, onlyRule: 8
        ).isEmpty)

        let odds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 1, 1, 1, 1], config: config, customOdds: odds, onlyRule: 9
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 1, 1, 1, 1], config: config, customOdds: odds, onlyRule: 9
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 3, 3, 1], config: config, customOdds: odds, onlyRule: 9
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 3, 3, 3], config: config, customOdds: odds, onlyRule: 10
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [0, 0, 0, 0, 0, 0], config: config, customOdds: odds, onlyRule: 10
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [0, 0, 0, 0, 0, 0], config: config, customOdds: nil, onlyRule: 10
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 3, 3, 3, 3], config: config, customOdds: odds, onlyRule: 12
        ).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 1, 1, 0, 0], config: config, customOdds: odds, onlyRule: 12
        ).isEmpty)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 1, 0, 3, 1, 0], config: config, customOdds: odds, onlyRule: 12
        ).isEmpty)

        let defaults = FilterInputDefaults.values(from: config)
        XCTAssertEqual(defaults["svip10FrontFiveSameOutcomeRunMaximum2Enabled"], "1")
        XCTAssertEqual(defaults["svip10FrontFiveReturnMaximum2Enabled"], "1")
        XCTAssertEqual(defaults["svip10FrontFiveNoConsecutiveDrawEnabled"], "1")
        XCTAssertEqual(defaults["svip10FrontFiveValueThreeMaximum2Enabled"], "1")
        XCTAssertEqual(defaults["svip10SixMatchFavoriteCount2To4Enabled"], "1")
        XCTAssertEqual(defaults["svip10SixMatchMinimumOddsProductEnabled"], "1")
        XCTAssertEqual(defaults["svip10SixMatchMinimumOddsProductInput"], "380")
        XCTAssertEqual(defaults["svip10SixMatchBreakpoint2To4Enabled"], "0")
        XCTAssertEqual(defaults["svip10SixMatchBreakpoint3To5Enabled"], "1")

        let legacy = try FilterConfig.parse(base)
        XCTAssertFalse(legacy.svip10AdditionalFilters.frontFiveSameOutcomeRunMaximum2Enabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.frontFiveReturnMaximum2Enabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.frontFiveNoConsecutiveDrawEnabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.frontFiveValueThreeMaximum2Enabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.sixMatchFavoriteCount2To4Enabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.sixMatchMinimumOddsProductEnabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.sixMatchBreakpoint2To4Enabled)
        XCTAssertFalse(legacy.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled)

        let archivedB24 = try FilterConfig.parse(config.normalizedInput
            .replacingOccurrences(of: "S10B24ON=0", with: "S10B24ON=1")
            .replacingOccurrences(of: "S10B35ON=1", with: "S10B35ON=0"))
        XCTAssertTrue(archivedB24.svip10AdditionalFilters.sixMatchBreakpoint2To4Enabled)
        XCTAssertFalse(archivedB24.svip10AdditionalFilters.sixMatchBreakpoint3To5Enabled)
        XCTAssertTrue(SequenceFilterEngine.svip10AdditionalFailureReasons(
            outcomes: [3, 3, 1, 1, 0, 0], config: archivedB24, customOdds: odds, onlyRule: 11
        ).isEmpty)
    }

    func testSVIP10StatisticalLineBudgetReducesBetsWithoutAddingAny() throws {
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            FilterConfig.svip10Input(
                numbers: ["1", "2", "3", "4", "5", "6"],
                logic: "CBCCCB",
                extras: ["36:3"],
                enabled: true,
                scoreRange: "5.5-8",
                noFourPosition: nil,
                sumRange: "15-19",
                mRange: "2-8"
            ),
            coldEnabled: true,
            coldRange: "0-3",
            drawEnabled: false,
            drawRange: "0-3",
            winLossSwitchEnabled: true,
            highestDoubleProbabilityTopTwoEnabled: true,
            statisticalLineBudgetEnabled: true
        )
        let config = try FilterConfig.parse(input)
        let odds = [
            [1.72, 3.65, 4.80], [2.10, 3.25, 3.40], [1.95, 3.45, 3.85],
            [2.42, 3.10, 2.92], [1.80, 3.60, 4.35], [2.28, 3.20, 3.05]
        ]
        let withBudget = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        var withoutBudgetConfig = config
        withoutBudgetConfig.svip10AdditionalFilters.statisticalLineBudgetEnabled = false
        let withoutBudget = SequenceFilterEngine.calculate(withoutBudgetConfig, previousContext: nil, currentOutcomeSPs: odds)

        XCTAssertLessThanOrEqual(withBudget.exportCompressedRecords.count, 50)
        XCTAssertLessThan(withBudget.finalBetCount, withoutBudget.finalBetCount)
        let kept = Set(withBudget.exportCompressedRecords.flatMap { row in
            row.options.reduce([[]]) { prefixes, options in
                prefixes.flatMap { prefix in options.map { prefix + [$0] } }
            }
        })
        let baseline = Set(withoutBudget.exportCompressedRecords.flatMap { row in
            row.options.reduce([[]]) { prefixes, options in
                prefixes.flatMap { prefix in options.map { prefix + [$0] } }
            }
        })
        XCTAssertEqual(kept.count, withBudget.finalBetCount)
        XCTAssertTrue(kept.isSubset(of: baseline))
    }

    func testSVIP10ProbabilityRecoveryKeepsBaseAndAddsAtMostOneHundredEligibleBets() throws {
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            FilterConfig.svip10Input(
                numbers: ["1", "2", "3", "4", "5", "6"], logic: "AAAAAA",
                extras: ["7:3"], enabled: true, scoreRange: "0-100",
                noFourPosition: nil, sumRange: "0-24", mRange: "0-100"
            ),
            coldEnabled: false, coldRange: "0-2", drawEnabled: false, drawRange: "0-3",
            highestDoubleProbabilityTopTwoEnabled: true,
            fiveMatchMEnabled: true, fiveMatchMRange: "3-6",
            sixMatchFavoriteCount2To4Enabled: true,
            topThreeProbabilityRecovery100Enabled: true
        )
        let recoveryConfig = try FilterConfig.parse(input)
        let odds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        let probabilities = Array(repeating: [0.55, 0.30, 0.15], count: 6)
        let recoveredResult = SequenceFilterEngine.calculate(
            recoveryConfig, previousContext: nil,
            currentOutcomeProbabilities: probabilities, currentOutcomeSPs: odds
        )
        var baseConfig = recoveryConfig
        baseConfig.svip10AdditionalFilters.topThreeProbabilityRecovery100Enabled = false
        let baseResult = SequenceFilterEngine.calculate(
            baseConfig, previousContext: nil,
            currentOutcomeProbabilities: probabilities, currentOutcomeSPs: odds
        )
        let base = Set(baseResult.uniqueExpandedBets.map { Array($0.prefix(6)) })
        let recovered = Set(recoveredResult.uniqueExpandedBets.map { Array($0.prefix(6)) })
        let added = recovered.subtracting(base)

        XCTAssertTrue(base.isSubset(of: recovered))
        XCTAssertFalse(added.isEmpty)
        XCTAssertLessThanOrEqual(added.count, 100)
        for outcomes in added {
            XCTAssertTrue([0, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13].allSatisfy { rule in
                SequenceFilterEngine.svip10AdditionalFailureReasons(
                    outcomes: outcomes, config: recoveryConfig, customOdds: odds, onlyRule: rule
                ).isEmpty
            })
            XCTAssertTrue(
                !SequenceFilterEngine.svip10AdditionalFailureReasons(
                    outcomes: outcomes, config: recoveryConfig, customOdds: odds, onlyRule: 4
                ).isEmpty
                || !SequenceFilterEngine.svip10AdditionalFailureReasons(
                    outcomes: outcomes, config: recoveryConfig, customOdds: odds, onlyRule: 9
                ).isEmpty
            )
        }
    }

    func testSVIP10ProbabilityMass60KeepsOnlyOriginalBets() throws {
        let input = FilterConfig.appendingSVIP10AdditionalInput(
            FilterConfig.svip10Input(
                numbers: ["1", "2", "3", "4", "5", "6"], logic: "CBCCCB",
                extras: ["36:3"], enabled: true, scoreRange: "5.5-8",
                noFourPosition: nil, sumRange: "15-19", mRange: "2-8"
            ),
            coldEnabled: true, coldRange: "0-3", drawEnabled: false, drawRange: "0-3",
            winLossSwitchEnabled: true, highestDoubleProbabilityTopTwoEnabled: true,
            statisticalLineBudgetEnabled: false, probabilityMass60Enabled: true
        )
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.svip10AdditionalFilters.probabilityMass60Enabled)
        XCTAssertFalse(config.svip10AdditionalFilters.statisticalLineBudgetEnabled)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let odds = [
            [1.72, 3.65, 4.80], [2.10, 3.25, 3.40], [1.95, 3.45, 3.85],
            [2.42, 3.10, 2.92], [1.80, 3.60, 4.35], [2.28, 3.20, 3.05]
        ]
        let withBudget = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        var baselineConfig = config
        baselineConfig.svip10AdditionalFilters.probabilityMass60Enabled = false
        let baseline = SequenceFilterEngine.calculate(baselineConfig, previousContext: nil, currentOutcomeSPs: odds)
        let expand: ([CompressedRecord]) -> Set<[Int]> = { records in
            Set(records.flatMap { row in
                row.options.reduce([[]]) { prefixes, options in
                    prefixes.flatMap { prefix in options.map { prefix + [$0] } }
                }
            })
        }
        let kept = expand(withBudget.exportCompressedRecords)
        XCTAssertLessThanOrEqual(withBudget.exportCompressedRecords.count, 60)
        XCTAssertLessThan(withBudget.finalBetCount, baseline.finalBetCount)
        XCTAssertEqual(kept.count, withBudget.finalBetCount)
        XCTAssertTrue(kept.isSubset(of: expand(baseline.exportCompressedRecords)))
    }

    func testSVIP7ProtocolRoundTripAndStrictMissingOdds() throws {
        let input = "1,2,3,4,5,6|ABCDAB|0-24|0-100|100|6|0|100|0-5|SVIP7=1|SIXSCOPE=1|FINAL=OFF|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.svip7RankOddsEnabled)
        XCTAssertTrue(config.requiresSPData)
        XCTAssertTrue(try FilterConfig.parse(config.normalizedInput).svip7RankOddsEnabled)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["selectedConditionVersionID"], "svip7-odds-rank-280")
        XCTAssertEqual(SequenceFilterEngine.calculate(config, previousContext: nil).finalBetCount, 0)
        XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "SVIP7=1", with: "SVIP7=1|SIX250=1")))
        let legacy = try FilterConfig.parse(input.replacingOccurrences(of: "SVIP7=1|", with: ""))
        XCTAssertFalse(legacy.svip7RankOddsEnabled)
        var off = config
        off.conditionPackageEnabled = false
        XCTAssertFalse(off.requiresSPData)
        XCTAssertEqual(SequenceFilterEngine.calculate(off, previousContext: nil).finalBetCount, 729)
    }

    func testSVIP7RankingToleranceTiesAndSeventhMatchIsolation() {
        let tied = Array(repeating: [3.0, 3.0, 3.0], count: 6)
        XCTAssertTrue(SequenceFilterEngine.svip7FailureReasons(outcomes: [3,3,3,3,3,3], customOdds: tied).isEmpty)
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: [1,1,1,1,1,1], customOdds: tied).isEmpty)
        let odds = Array(repeating: [2.0, 3.0, 4.0], count: 6)
        // All middle choices fail hot>=1 and middle<=3: tolerance1 cannot save it.
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: [1,1,1,1,1,1], customOdds: odds, onlyRule: 2).isEmpty)
        // Two third choices in each half violates cold<=3 and the half-group rule.
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: [0,0,3,0,0,3], customOdds: odds, onlyRule: 2).isEmpty)
        // One half failing the group rule is one tolerated condition.
        let bet = [0,0,3,3,3,3]
        XCTAssertTrue(SequenceFilterEngine.svip7FailureReasons(outcomes: bet, customOdds: odds, onlyRule: 2).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.svip7FailureReasons(outcomes: bet, customOdds: odds),
                       SequenceFilterEngine.svip7FailureReasons(outcomes: bet + [1], customOdds: odds + [[100, 2, 1.1]]))
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: bet, customOdds: Array(odds.prefix(5))).isEmpty)
        // Product endpoints are inclusive and independent of rank tolerance.
        for endpoint in [300.0, 800.0] {
            let rows = [[endpoint, 2, 3]] + Array(repeating: [1.0, 2, 3], count: 5)
            XCTAssertTrue(SequenceFilterEngine.svip7FailureReasons(outcomes: [3,3,3,3,3,3], customOdds: rows, onlyRule: 0).isEmpty)
        }
        let above = [[800.01, 2, 3]] + Array(repeating: [1.0, 2, 3], count: 5)
        XCTAssertFalse(SequenceFilterEngine.svip7FailureReasons(outcomes: [3,3,3,3,3,3], customOdds: above, onlyRule: 0).isEmpty)
    }

    private func txtPrizeMatch(
        _ number: Int, reference: [Double] = [2,3,4], outcome: Int? = nil,
        settled: Double? = nil, status: String? = nil, issue: String = "26105"
    ) -> BeijingSingleMatch {
        BeijingSingleMatch(
            issue: issue, matchNumber: String(number), fixtureID: String(number), league: "测试",
            matchTime: "10-19 12:00", status: status ?? (outcome == nil ? "未开赛" : "完"),
            homeTeam: "主", awayTeam: "客", handicap: 0, referenceSP: reference,
            marketOdds: [9,10,11], homeScore: outcome.map { $0 == 3 ? 1 : 0 },
            awayScore: outcome.map { $0 == 0 ? 1 : 0 }, settledSP: settled
        )
    }

    func testTXTQueryPrizesPublishedSPAndMultiplierApply130PercentOnce() {
        let matches = (1...7).map { txtPrizeMatch($0, reference: [99,99,99], outcome: 3, settled: 2) }
        let saved = TXTQuerySPSnapshot.capture((1...7).map { txtPrizeMatch($0, reference: [8,8,8]) })
        let report = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [3], matches: matches, snapshots: saved, isSimulation: false, multiplier: 2
        )
        XCTAssertEqual(report.six.amount ?? -1, 166.4, accuracy: 0.00001)
        XCTAssertEqual(report.seven.first?.prize.amount ?? -1, 332.8, accuracy: 0.00001)
        XCTAssertFalse(report.six.isEstimate)
        XCTAssertFalse(report.seven[0].prize.isEstimate)
        XCTAssertTrue(report.displayText.contains("六场总奖金：¥166.40"))
        XCTAssertTrue(report.displayText.contains("七场总奖金：¥332.80"))
        XCTAssertTrue(report.six.message.contains("开奖SP"))
    }

    func testTXTQueryPrizesPreferGenerationSPForUnpublishedOutcomes() {
        var savedMatches = (1...6).map { txtPrizeMatch($0) }
        savedMatches.append(txtPrizeMatch(7, reference: [5,6,7]))
        let snapshots = TXTQuerySPSnapshot.capture(savedMatches, at: Date(timeIntervalSince1970: 100))
        let fresh = (1...7).map { txtPrizeMatch($0, reference: [20,30,40]) }
        let report = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: [3,1,0,3,1,0],
            seventhOptions: [0], matches: fresh, snapshots: snapshots, isSimulation: true
        )
        XCTAssertEqual(report.six.amount ?? -1, 748.8, accuracy: 0.00001)
        XCTAssertEqual(report.seven[0].prize.amount ?? -1, 5241.6, accuracy: 0.00001)
        XCTAssertTrue(report.six.isEstimate)
        XCTAssertTrue(report.seven[0].prize.isEstimate)
        XCTAssertTrue(report.displayText.contains("预估"))
        XCTAssertTrue(report.six.message.contains("生成时SP"))
        XCTAssertFalse(report.six.message.contains("查询时SP"))
        XCTAssertEqual(snapshots[0].capturedAt, Date(timeIntervalSince1970: 100))
    }

    func testTXTQueryPrizesMixOfficialAndEstimatedAndDoNotUseWrongOutcomeSP() {
        var matches = (1...2).map { txtPrizeMatch($0, outcome: 3, settled: 2) }
        matches += (3...7).map { txtPrizeMatch($0, reference: [9,9,9]) }
        let saved = TXTQuerySPSnapshot.capture((1...7).map { txtPrizeMatch($0, reference: [3,3,5]) })
        let report = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [3], matches: matches, snapshots: saved, isSimulation: false
        )
        XCTAssertEqual(report.six.amount ?? -1, 421.2, accuracy: 0.00001)
        XCTAssertEqual(report.seven[0].prize.amount ?? -1, 1263.6, accuracy: 0.00001)
        XCTAssertTrue(report.six.isEstimate)
        let final = (1...7).map { txtPrizeMatch($0, outcome: 3, settled: 2) }
        let simulated = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: [0,3,3,3,3,3],
            seventhOptions: [3], matches: final, snapshots: saved, isSimulation: true
        )
        XCTAssertEqual(simulated.six.amount ?? -1, 208, accuracy: 0.00001)
        XCTAssertTrue(simulated.six.isEstimate)
    }

    func testTXTQueryPrizesSeventhUsesActualSPRegardlessOfSelectionAndPendingChoicesAreSeparate() {
        let six = (1...6).map { txtPrizeMatch($0, outcome: 3, settled: 2) }
        let missed = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [3], matches: six + [txtPrizeMatch(7, reference: [], outcome: 0, settled: 9)],
            snapshots: [], isSimulation: false
        )
        XCTAssertEqual(missed.six.amount ?? -1, 83.2, accuracy: 0.00001)
        XCTAssertEqual(missed.seven[0].prize.amount ?? -1, 748.8, accuracy: 0.00001)
        XCTAssertEqual(missed.seven[0].outcome, 0)
        XCTAssertFalse(missed.seven[0].prize.isEstimate)
        let pending = txtPrizeMatch(7, reference: [3,4,5], outcome: 0, status: "进行中")
        let report = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [0,3,0], matches: six + [pending], snapshots: [], isSimulation: false
        )
        XCTAssertEqual(report.seven.count, 2)
        XCTAssertEqual(report.seven[0].outcome, 3)
        XCTAssertEqual(report.seven[0].prize.amount ?? -1, 249.6, accuracy: 0.00001)
        XCTAssertEqual(report.seven[1].prize.amount ?? -1, 416, accuracy: 0.00001)
        XCTAssertTrue(report.seven.allSatisfy { $0.prize.isEstimate })
    }

    func testTXTQueryPrizesMissingSPWrongIssueAndSixMatchOnly() {
        let noSP = (1...7).map { txtPrizeMatch($0, reference: []) }
        let wrongIssue = TXTQuerySPSnapshot.capture((1...7).map { txtPrizeMatch($0, issue: "26104") })
        let missing = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [3], matches: noSP, snapshots: wrongIssue, isSimulation: true
        )
        XCTAssertNil(missing.six.amount) // Ordinary market odds must not be used as payout SP.
        XCTAssertNil(missing.seven[0].prize.amount)
        XCTAssertTrue(missing.displayText.contains("暂无法计算"))
        let live = (1...6).map { txtPrizeMatch($0, reference: [2,3,4]) }
        let sixOnly = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...6).map(String.init), firstSixOutcomes: Array(repeating: 3, count: 6),
            seventhOptions: [], matches: live, snapshots: [], isSimulation: true
        )
        XCTAssertEqual(sixOnly.six.amount ?? -1, 83.2, accuracy: 0.00001)
        XCTAssertTrue(sixOnly.six.message.contains("查询时SP"))
        XCTAssertNil(sixOnly.seven[0].prize.amount)
        XCTAssertTrue(sixOnly.seven[0].prize.message.contains("没有第7场"))
        let invalid = TXTQueryPrizeCalculator.calculate(
            issue: "26105", matchNumbers: (1...7).map(String.init), firstSixOutcomes: [3,3,3],
            seventhOptions: [3], matches: [], snapshots: [], isSimulation: true
        )
        XCTAssertNil(invalid.six.amount)
    }


    func testActualM26AndCombinedR315CompatibilityAndFinalSubset() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F5ACTUALM36ON=1|F5ACTUALMRANGE=2-6|STRUCT3ON=1|STRUCT3R=3-15|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertEqual(config.frontFiveActualMRange, 2...6)
        XCTAssertEqual(config.combinedThreeRRange, 3...15)
        XCTAssertTrue(config.frontFiveActualMFailureReasons(for: [3,3,1,1,0,3]).isEmpty)
        XCTAssertTrue(config.combinedThreeStructureFailureReasons(for: [3,3,3,3,1,3]).isEmpty) // R=3
        XCTAssertTrue(config.combinedThreeStructureFailureReasons(for: [3,0,3,0,3,1]).isEmpty) // R=15
        let high = config.combinedThreeStructureFailureReasons(for: [3,0,3,0,3,0]) // R=16
        XCTAssertTrue(high.contains { $0.contains("R=16") && $0.contains("不在3–15") })
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["combinedThreeRRangeInput"], "3-15")
        let legacy = try FilterConfig.parse(input.replacingOccurrences(of: "|STRUCT3R=3-15", with: "").replacingOccurrences(of: "|F5ACTUALMRANGE=2-6", with: ""))
        XCTAssertEqual(legacy.combinedThreeRRange, 5...12)
        XCTAssertEqual(legacy.frontFiveActualMRange, 3...6)
        XCTAssertFalse(legacy.frontFiveActualMFailureReasons(for: [3,3,1,1,0,3]).isEmpty)
        XCTAssertFalse(legacy.combinedThreeStructureFailureReasons(for: [3,3,3,3,1,3]).isEmpty)
        let off = try FilterConfig.parse(input.replacingOccurrences(of: "F5ACTUALM36ON=1", with: "F5ACTUALM36ON=0").replacingOccurrences(of: "STRUCT3ON=1", with: "STRUCT3ON=0"))
        let all = SequenceFilterEngine.calculate(off, previousContext: nil)
        let expected = Set(all.uniqueExpandedBets.filter { bet in
            let v = bet.prefix(6).map { $0 == 3 ? 2 : ($0 == 1 ? 3 : 4) }
            let m = (0..<4).reduce(0) { $0 + abs(v[$1+1]-v[$1]) }
            let r = (0..<4).reduce(0) { $0 + abs(v[$1+2]-2*v[$1+1]+v[$1]) }
            let wins = bet.prefix(5).filter { $0 == 3 }.count
            return (2...6).contains(m) && (3...15).contains(r) && (1...4).contains(wins) && v.filter { $0 == 3 }.count <= 3
        })
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "STRUCT3R=3-15", with: "STRUCT3R=3-17")))
    }

    func testThreeIndependentExtrasPreserveCurrentBaselineAndExactQuery() throws {
        let input = "295,296,297,298,299,300|CBBBCB|15-20|1-6|1|3|0.04|11|0-5|QDROP0|STRUCT3ON=1|FINAL=OFF|SEED=1|MKTW=0|RATE=20|OC_WLSWITCH=0-2|OCTOLON=0|OCTOL=0-1|ALLTOLON=0|ALLTOL=0-1|RUNS=0|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=2-3|RUN2ON=0|RUN2RANGE=5-7|RUN2TOL=2-3|SAMERUNS=0|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=0|SPPRODON=0|SPPROD=30.0-900.0|HODDSPRODON=1|HODDSPROD=0-1800|HODDSSUMON=0|HODDSSUM=12-16|PRIZEON=0|PRIZE=26.0-1950.0|SPRISKON=0|MAXSP=10.0|HIGHSPTH=4.5|HIGHSPCOUNT=0-2|MINPROBON=0|MINPROB=15.0|JOINTPROBON=0|JOINTPROB=0.1-100.0|VIP12PROBON=0|SVIP1ODDSGUARDON=0|VIP16TOP200ON=0|VIP18TOP200ON=0|VIP19CUSTOMTOP200ON=0|GROUPON=0|GROUPMODE=BOTH|GFSUM=0-9|GBSUM=0-6|GFSP=1.0-200.0|GBSP=1.0-100.0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=0|U247TH=-0.050756|V10TOP150ON=0|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|F5LOSS13ON=1|F5LOSSRANGE=0-4|F5WINON=1|F5WINRANGE=0-4|F5NO111ON=1|F5ACTUALM36ON=1|SVIP5FOURCAPON=0|SVIP5DROP=0|MPERM=2|NO4LOWODDS=0|NO4SINGLE=1|NO4=1|342:0|MERGE3"
        let odds: [[Double]] = [[3.404184273574349, 5.087467285734541, 1.9620061091646654], [2.519888475836431, 3.876751501286817, 2.8967948717948717], [2.515792673658611, 4.1785912648321135, 2.753335329540539], [1.8987255517099464, 4.247438083882945, 4.203536915057281], [3.328706534908706, 5.227364050586618, 1.9674117769666062], [2.4111111111111114, 3.9454545454545453, 3.013888888888889]]
        let baselineConfig = try FilterConfig.parse(input)
        let baseline = SequenceFilterEngine.calculate(baselineConfig, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(baseline.finalBetCount, 206)
        XCTAssertFalse(baselineConfig.sixLossCount14Enabled)
        XCTAssertFalse(baselineConfig.frontFiveR39Enabled)
        XCTAssertFalse(baselineConfig.frontFiveNoTripleLossEnabled)
        for (token, expectedCount, title) in [("F6LOSS14ON=1",187,"六场负1–4个"), ("F5R39ON=1",195,"前5场判定值R=3–9"), ("F5NO000ON=1",197,"前5场不出现连续3场负")] {
            let config = try FilterConfig.parse(input.replacingOccurrences(of: "|FINAL=OFF", with: "|" + token + "|FINAL=OFF"))
            let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
            XCTAssertEqual(result.finalBetCount, expectedCount)
            let expected = Set(baseline.uniqueExpandedBets.filter {
                config.sixLossCount14FailureReasons(for: $0).isEmpty && config.frontFiveR39FailureReasons(for: $0).isEmpty && config.frontFiveNoTripleLossFailureReasons(for: $0).isEmpty
            })
            XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
            XCTAssertEqual(result.duplicateExpandedBetCount, 0)
            XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
            XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
            for bet in Set(baseline.uniqueExpandedBets).subtracting(expected) {
                guard case .excluded(let reason) = result.queryAttribution(for: Array(bet.prefix(6))) else { return XCTFail("新增条件必须逐注准确归因") }
                XCTAssertTrue(reason.contains(title))
            }
        }
        let all = try FilterConfig.parse(input.replacingOccurrences(of: "|FINAL=OFF", with: "|F6LOSS14ON=1|F5R39ON=1|F5NO000ON=1|FINAL=OFF"))
        XCTAssertEqual(SequenceFilterEngine.calculate(all, previousContext: nil, currentOutcomeSPs: odds).finalBetCount, 170)
        let defaults = FilterInputDefaults.values(from: all)
        for key in ["sixLossCount14Enabled","frontFiveR39Enabled","frontFiveNoTripleLossEnabled"] { XCTAssertEqual(defaults[key], "1") }
    }

    func testThreeIndependentExtrasScopeBoundariesAndTolerance() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F6LOSS14ON=1|F5R39ON=1|F5NO000ON=1|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        for count in 0...6 {
            let six = Array(repeating: 0, count: count) + Array(repeating: 3, count: 6-count)
            for seventh in [3,1,0] { XCTAssertEqual(config.sixLossCount14FailureReasons(for: six + [seventh]).isEmpty, (1...4).contains(count)) }
        }
        XCTAssertTrue(config.frontFiveNoTripleLossFailureReasons(for: [0,0,3,0,0,0,0]).isEmpty)
        XCTAssertTrue(config.frontFiveNoTripleLossFailureReasons(for: [3,1,0,1,0,0,0]).isEmpty)
        for bet in [[0,0,0,3,1],[3,0,0,0,1],[3,1,0,0,0]] { XCTAssertFalse(config.frontFiveNoTripleLossFailureReasons(for: bet).isEmpty) }
        for tolerance in ["", "|ALLTOLON=1|ALLTOL=0-1"] {
            let current = try FilterConfig.parse(input.replacingOccurrences(of: "|FINAL=OFF", with: tolerance + "|FINAL=OFF"))
            let off = try FilterConfig.parse(current.normalizedInput.replacingOccurrences(of: "F6LOSS14ON=1", with: "F6LOSS14ON=0").replacingOccurrences(of: "F5R39ON=1", with: "F5R39ON=0").replacingOccurrences(of: "F5NO000ON=1", with: "F5NO000ON=0"))
            let all = SequenceFilterEngine.calculate(off, previousContext: nil)
            let expected = Set(all.uniqueExpandedBets.filter { bet in
                let losses = bet.prefix(6).filter { $0 == 0 }.count
                let v = bet.prefix(5).map { $0 == 3 ? 2 : ($0 == 1 ? 3 : 4) }
                let r = (0..<3).reduce(0) { $0 + abs(v[$1+2] - 2*v[$1+1] + v[$1]) }
                let triple = (0..<3).contains { i in bet[i] == 0 && bet[i+1] == 0 && bet[i+2] == 0 }
                return (1...4).contains(losses) && (3...9).contains(r) && !triple
            })
            let result = SequenceFilterEngine.calculate(current, previousContext: nil)
            XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
            XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
            XCTAssertTrue(off.sixLossCount14FailureReasons(for: [3,3,3,3,3,3]).isEmpty)
            XCTAssertTrue(off.frontFiveR39FailureReasons(for: [3,3,3,3,3,3]).isEmpty)
            XCTAssertTrue(off.frontFiveNoTripleLossFailureReasons(for: [0,0,0,0,0,0]).isEmpty)
        }
    }

    func testCombinedThreeStructureCurrentTXTIsExactSubsetAndAccurateQuery() throws {
        let input = "295,296,297,298,299,300|CBBBCB|15-20|1-6|1|3|0.04|11|0-5|QDROP0|FINAL=OFF|SEED=1|MKTW=0|RATE=20|OC_WLSWITCH=0-2|OCTOLON=0|OCTOL=0-1|ALLTOLON=0|ALLTOL=0-1|RUNS=0|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=2-3|RUN2ON=0|RUN2RANGE=5-7|RUN2TOL=2-3|SAMERUNS=0|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=0|SPPRODON=0|SPPROD=30.0-900.0|HODDSPRODON=1|HODDSPROD=0-1800|HODDSSUMON=0|HODDSSUM=12-16|PRIZEON=0|PRIZE=26.0-1950.0|SPRISKON=0|MAXSP=10.0|HIGHSPTH=4.5|HIGHSPCOUNT=0-2|MINPROBON=0|MINPROB=15.0|JOINTPROBON=0|JOINTPROB=0.1-100.0|VIP12PROBON=0|SVIP1ODDSGUARDON=0|VIP16TOP200ON=0|VIP18TOP200ON=0|VIP19CUSTOMTOP200ON=0|GROUPON=0|GROUPMODE=BOTH|GFSUM=0-9|GBSUM=0-6|GFSP=1.0-200.0|GBSP=1.0-100.0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=0|U247TH=-0.050756|V10TOP150ON=0|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|F5LOSS13ON=1|F5LOSSRANGE=0-4|F5WINON=1|F5WINRANGE=0-4|F5NO111ON=1|F5ACTUALM36ON=1|SVIP5FOURCAPON=0|SVIP5DROP=0|MPERM=2|NO4LOWODDS=0|NO4SINGLE=1|NO4=1|342:0|MERGE3"
        let odds: [[Double]] = [[3.404184273574349, 5.087467285734541, 1.9620061091646654], [2.519888475836431, 3.876751501286817, 2.8967948717948717], [2.515792673658611, 4.1785912648321135, 2.753335329540539], [1.8987255517099464, 4.247438083882945, 4.203536915057281], [3.328706534908706, 5.227364050586618, 1.9674117769666062], [2.4111111111111114, 3.9454545454545453, 3.013888888888889]]
        let off = try FilterConfig.parse(input)
        XCTAssertFalse(off.combinedThreeStructureEnabled)
        let baseline = SequenceFilterEngine.calculate(off, previousContext: nil, currentOutcomeSPs: odds)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|FINAL=OFF", with: "|STRUCT3ON=1|FINAL=OFF"))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        XCTAssertEqual(baseline.finalBetCount, 275)
        XCTAssertEqual(result.finalBetCount, 206)
        XCTAssertEqual(Set(result.uniqueExpandedBets), Set(baseline.uniqueExpandedBets.filter { config.combinedThreeStructureFailureReasons(for: $0).isEmpty }))
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in Set(baseline.uniqueExpandedBets).subtracting(Set(result.uniqueExpandedBets)) {
            guard case .excluded(let reason) = result.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("每条组合淘汰都必须准确归因")
            }
            XCTAssertTrue(reason.contains("三条件组合过滤"))
            XCTAssertTrue(reason.contains("组合条件"))
        }
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["combinedThreeStructureEnabled"], "1")
        XCTAssertTrue(off.combinedThreeStructureFailureReasons(for: [0,0,0,0,0,0]).isEmpty)
    }

    func testCombinedThreeStructureAllOutcomesAndToleranceCannotBypass() throws {
        let base = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|7:0|MERGE3"
        for tolerance in ["", "|ALLTOLON=1|ALLTOL=0-1"] {
            let off = try FilterConfig.parse(base.replacingOccurrences(of: "|FINAL=OFF", with: tolerance + "|FINAL=OFF"))
            let config = try FilterConfig.parse(off.normalizedInput.replacingOccurrences(of: "STRUCT3ON=0", with: "STRUCT3ON=1"))
            let all = SequenceFilterEngine.calculate(off, previousContext: nil)
            let expected = Set(all.uniqueExpandedBets.filter { bet in
                let wins = bet.prefix(5).filter { $0 == 3 }.count
                let v = bet.prefix(6).map { $0 == 3 ? 2 : ($0 == 1 ? 3 : 4) }
                let r = (0..<4).reduce(0) { $0 + abs(v[$1+2] - 2*v[$1+1] + v[$1]) }
                return (1...4).contains(wins) && (5...12).contains(r) && v.filter { $0 == 3 }.count <= 3
            })
            let result = SequenceFilterEngine.calculate(config, previousContext: nil)
            XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
            XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
            for bet in all.uniqueExpandedBets {
                for seventh in [3,1,0] {
                    XCTAssertEqual(config.combinedThreeStructureFailureReasons(for: Array(bet.prefix(6)) + [seventh]).isEmpty, expected.contains(bet))
                }
            }
            XCTAssertFalse(config.combinedThreeStructureFailureReasons(for: [3,0,1,0,1]).isEmpty)
        }
    }

    func testFrontFiveWinAndLossRangesAreIndependentAndRoundTrip() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F5LOSS13ON=1|F5LOSSRANGE=1-5|F5WINON=1|F5WINRANGE=1-5|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertEqual(config.frontFiveLossCountRange, 1...5)
        XCTAssertEqual(config.frontFiveWinCountRange, 1...5)
        XCTAssertTrue(config.frontFiveLossCountFailureReasons(for: [0,0,0,0,0,3,3]).isEmpty)
        XCTAssertTrue(config.frontFiveWinCountFailureReasons(for: [3,3,3,3,3,0,0]).isEmpty)
        XCTAssertFalse(config.frontFiveLossCountFailureReasons(for: [3,1,3,1,3,0,0]).isEmpty)
        XCTAssertFalse(config.frontFiveWinCountFailureReasons(for: [0,1,0,1,0,3,3]).isEmpty)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let defaults = FilterInputDefaults.values(from: config)
        XCTAssertEqual(defaults["frontFiveLossCountRangeInput"], "1-5")
        XCTAssertEqual(defaults["frontFiveWinCountRangeInput"], "1-5")
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 540)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in result.uniqueExpandedBets {
            XCTAssertTrue((1...5).contains(bet.prefix(5).filter { $0 == 0 }.count))
            XCTAssertTrue((1...5).contains(bet.prefix(5).filter { $0 == 3 }.count))
        }
        guard case .excluded(let reason) = result.queryAttribution(for: [0,1,0,1,0,3]) else {
            return XCTFail("没有胜的组合应准确归因到胜个数条件")
        }
        XCTAssertTrue(reason.contains("胜（彩果3）共0个"))
        let custom = try FilterConfig.parse(input.replacingOccurrences(of: "F5LOSSRANGE=1-5", with: "F5LOSSRANGE=2-4").replacingOccurrences(of: "F5WINRANGE=1-5", with: "F5WINRANGE=0-2"))
        XCTAssertTrue(custom.frontFiveLossCountFailureReasons(for: [0,0,3,1,1,3]).isEmpty)
        XCTAssertFalse(custom.frontFiveLossCountFailureReasons(for: [0,3,3,1,1,0]).isEmpty)
        XCTAssertTrue(custom.frontFiveWinCountFailureReasons(for: [0,0,0,1,1,3]).isEmpty)
        XCTAssertFalse(custom.frontFiveWinCountFailureReasons(for: [3,3,3,1,0,0]).isEmpty)
        let lossOff = try FilterConfig.parse(input.replacingOccurrences(of: "F5LOSS13ON=1", with: "F5LOSS13ON=0"))
        XCTAssertTrue(lossOff.frontFiveLossCountFailureReasons(for: [3,3,3,3,3,0]).isEmpty)
        XCTAssertTrue(lossOff.frontFiveWinCountEnabled)
        let winOff = try FilterConfig.parse(input.replacingOccurrences(of: "F5WINON=1", with: "F5WINON=0"))
        XCTAssertTrue(winOff.frontFiveWinCountFailureReasons(for: [0,0,0,0,0,3]).isEmpty)
        XCTAssertTrue(winOff.frontFiveLossCountEnabled)
        XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "F5WINRANGE=1-5", with: "F5WINRANGE=1-6")))
    }

    func testFrontFiveLossCountIncludesBoundariesAndIgnoresSixthSeventh() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F5LOSS13ON=1|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        for count in 0...5 {
            let first = Array(repeating: 0, count: count) + Array(repeating: 3, count: 5-count)
            for sixth in [3,1,0] {
                XCTAssertEqual(config.frontFiveLossCountFailureReasons(for: first + [sixth,0]).isEmpty, (1...3).contains(count))
            }
        }
        XCTAssertFalse(config.frontFiveLossCountFailureReasons(for: [0,3,1,3]).isEmpty)
        XCTAssertFalse(config.frontFiveLossCountFailureReasons(for: [0,3,2,3,1]).isEmpty)
        XCTAssertFalse(config.requiresSPData)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["frontFiveLossCountEnabled"], "1")
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 600)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        guard case .excluded(let reason) = result.queryAttribution(for: [3,1,3,1,3,0]) else {
            return XCTFail("零个负也必须准确归因")
        }
        XCTAssertTrue(reason.contains("负（彩果0）共0个"))
        let off = try FilterConfig.parse(input.replacingOccurrences(of: "F5LOSS13ON=1", with: "F5LOSS13ON=0"))
        XCTAssertTrue(off.frontFiveLossCountFailureReasons(for: [0,0,0,0,0,0]).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.calculate(off, previousContext: nil).finalBetCount, 729)
    }

    func testFrontFiveNoTripleDrawCoversEveryWindowAndIgnoresSixthSeventh() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F5NO111ON=1|7:1|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertFalse(config.requiresSPData)
        XCTAssertEqual(config.frontFiveNoTripleDrawFailureReasons(for: [1,1,1,3,0,3]), ["前5场第1–3场连续3场平局（111）"])
        XCTAssertEqual(config.frontFiveNoTripleDrawFailureReasons(for: [3,1,1,1,0,3]), ["前5场第2–4场连续3场平局（111）"])
        XCTAssertEqual(config.frontFiveNoTripleDrawFailureReasons(for: [3,0,1,1,1,3]), ["前5场第3–5场连续3场平局（111）"])
        XCTAssertTrue(config.frontFiveNoTripleDrawFailureReasons(for: [1,3,1,0,1,1,1]).isEmpty)
        XCTAssertTrue(config.frontFiveNoTripleDrawFailureReasons(for: [3,0,3,1,1,1,1]).isEmpty)
        XCTAssertEqual(config.frontFiveNoTripleDrawFailureReasons(for: [1,1,1,1,1,3]).count, 3)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 666)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertEqual(result.queryAttribution(for: [1,3,1,0,1,1]), .hit)
        guard case .excluded(let reason) = result.queryAttribution(for: [3,1,1,1,0,3]) else {
            return XCTFail("必须定位到原始彩果111的实际窗口")
        }
        XCTAssertTrue(reason.contains("第2–4场连续3场平局（111）"))
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["frontFiveNoTripleDrawEnabled"], "1")
        let off = try FilterConfig.parse(input.replacingOccurrences(of: "F5NO111ON=1", with: "F5NO111ON=0"))
        XCTAssertTrue(off.frontFiveNoTripleDrawFailureReasons(for: [1,1,1,3,0,3]).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.calculate(off, previousContext: nil).finalBetCount, 729)
    }

    func testFrontFiveLossCountFinalExportMatchesNaturalSubset() throws {
        let input = "1,2,3,4,5,6|CAABBB|14-20|4-6|1|3|0.04|11|0-940|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=0-4750|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=4|NO4SINGLE=1|NO4=1|SVIP5FOURCAPON=1|7:3|MERGE3"
        let odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil, currentOutcomeSPs: odds)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|7:3|", with: "|F5LOSS13ON=1|7:3|"))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        let expected = Set(baseline.uniqueExpandedBets.filter { config.frontFiveLossCountFailureReasons(for: $0).isEmpty })
        XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
        XCTAssertLessThan(result.finalBetCount, baseline.finalBetCount)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in Set(baseline.uniqueExpandedBets).subtracting(expected) {
            guard case .excluded(let reason) = result.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("被负个数规则排除的每一注都必须能精确归因")
            }
            XCTAssertTrue(reason.contains("负（彩果0）"))
        }
    }

    func testFrontFiveNoTripleDrawFinalExportMatchesNaturalSubset() throws {
        let input = "1,2,3,4,5,6|CAABBB|14-20|4-6|1|3|0.04|11|0-940|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=0-4750|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=4|NO4SINGLE=1|NO4=1|SVIP5FOURCAPON=1|7:3|MERGE3"
        let odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil, currentOutcomeSPs: odds)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|7:3|", with: "|F5NO111ON=1|7:3|"))
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        let expected = Set(baseline.uniqueExpandedBets.filter { config.frontFiveNoTripleDrawFailureReasons(for: $0).isEmpty })
        XCTAssertEqual(Set(result.uniqueExpandedBets), expected)
        XCTAssertLessThan(result.finalBetCount, baseline.finalBetCount)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in Set(baseline.uniqueExpandedBets).subtracting(expected) {
            guard case .excluded(let reason) = result.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("被三连平规则排除的每一注都必须能精确归因")
            }
            XCTAssertTrue(reason.contains("连续3场平局（111）"))
        }
    }

    func testFrontFiveActualMSelectableRangeAndQueryRoundTrip() throws {
        let base = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|F5ACTUALM36ON=1|F5ACTUALMRANGE=0-0|7:0|MERGE3"
        let zero = try FilterConfig.parse(base)
        XCTAssertEqual(zero.frontFiveActualMRange, 0...0)
        XCTAssertTrue(zero.frontFiveActualMFailureReasons(for: [3,3,3,3,3,0,1]).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.calculate(zero, previousContext: nil).finalBetCount, 9)
        let full = try FilterConfig.parse(base.replacingOccurrences(of: "F5ACTUALMRANGE=0-0", with: "F5ACTUALMRANGE=0-8"))
        XCTAssertEqual(SequenceFilterEngine.calculate(full, previousContext: nil).finalBetCount, 729)
        let config = try FilterConfig.parse(base.replacingOccurrences(of: "F5ACTUALMRANGE=0-0", with: "F5ACTUALMRANGE=4-5"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["frontFiveActualMRangeInput"], "4-5")
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        guard case .excluded(let reason) = result.queryAttribution(for: [3,3,3,3,3,0]) else {
            return XCTFail("实际M范围改变后仍须准确归因")
        }
        XCTAssertTrue(reason.contains("M=0"))
        XCTAssertTrue(reason.contains("不在4–5"))
        XCTAssertThrowsError(try FilterConfig.parse(base.replacingOccurrences(of: "F5ACTUALMRANGE=0-0", with: "F5ACTUALMRANGE=0-9")))
        let legacy = try FilterConfig.parse(base.replacingOccurrences(of: "|F5ACTUALMRANGE=0-0", with: ""))
        XCTAssertEqual(legacy.frontFiveActualMRange, 3...6)
    }

    func testFrontFiveActualM36IncludesBoundariesAndIgnoresSixth() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|4-6|100|6|0|100|0-5|FINAL=OFF|MPERM=7|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|F5ACTUALM36ON=1|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.frontFiveActualMEnabled)
        XCTAssertFalse(config.requiresSPData)
        // Values 2,2,3,4,3 have M=3. Values 2,4,2,3,4 have M=6.
        XCTAssertTrue(config.frontFiveActualMFailureReasons(for: [3,3,1,0,1,3]).isEmpty)
        XCTAssertTrue(config.frontFiveActualMFailureReasons(for: [3,0,3,1,0,0]).isEmpty)
        XCTAssertTrue(config.frontFiveActualMFailureReasons(for: [3,0,3,1,0,3]).isEmpty)
        let low = [3,3,1,1,0,3] // values 2,2,3,3,4: actual M=2 but >=7 valid permutations.
        XCTAssertTrue(config.passesDisplacement(in: [2,2,3,3,4,2]))
        XCTAssertEqual(config.frontFiveActualMFailureReasons(for: low), ["前5场按实际顺序计算M=2，不在3–6（含边界）"])
        XCTAssertEqual(config.frontFiveActualMFailureReasons(for: [3,0,3,0,1,3]), ["前5场按实际顺序计算M=7，不在3–6（含边界）"])
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { config.frontFiveActualMFailureReasons(for: $0).isEmpty })
        guard case .excluded(let reason) = result.queryAttribution(for: low) else {
            return XCTFail("实际M淘汰必须准确归因，不能与排列门槛混淆")
        }
        XCTAssertTrue(reason.contains("实际顺序计算M=2"))
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["frontFiveActualMEnabled"], "1")
        let off = try FilterConfig.parse(input.replacingOccurrences(of: "F5ACTUALM36ON=1", with: "F5ACTUALM36ON=0"))
        XCTAssertTrue(off.frontFiveActualMFailureReasons(for: low).isEmpty)
    }

    func testFrontFiveActualM36IsExactSubsetAfterTXTDefensiveSupplements() throws {
        let input = "1,2,3,4,5,6|CAABBB|14-20|4-6|1|3|0.04|11|0-940|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=0-4750|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=4|NO4SINGLE=1|NO4=1|SVIP5FOURCAPON=1|7:3|MERGE3"
        let odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil, currentOutcomeSPs: odds)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|7:3|", with: "|F5ACTUALM36ON=1|7:3|"))
        let reduced = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        let expected = Set(baseline.uniqueExpandedBets.filter { config.frontFiveActualMFailureReasons(for: $0).isEmpty })
        XCTAssertEqual(Set(reduced.uniqueExpandedBets), expected)
        XCTAssertGreaterThan(baseline.finalBetCount, reduced.finalBetCount)
        XCTAssertEqual(reduced.duplicateExpandedBetCount, 0)
        XCTAssertFalse(reduced.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in Set(baseline.uniqueExpandedBets).subtracting(expected) {
            guard case .excluded(let reason) = reduced.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("每一条实际M淘汰记录都必须保留精确归因")
            }
            XCTAssertTrue(reason.contains("实际顺序计算M="))
        }
    }

    func testSVIP5FourCountRuleIsStructuralAndOnlyReadsFirstFive() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|FINAL=OFF|SVIP5FOURCAPON=1|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.svip5FourCountFilterEnabled)
        XCTAssertFalse(config.requiresSPData)
        // A maps outcome0 to value4. Sixth outcome0 never contributes to the first-five cap.
        XCTAssertTrue(config.svip5FourCountFailureReasons(for: [0,0,3,1,3,0]).isEmpty)
        XCTAssertEqual(config.svip5FourCountFailureReasons(for: [0,0,0,1,3,3]),
                       ["前5场判定值4出现3次，要求最多2次"])
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, captureQueryStages: true)
        XCTAssertEqual(result.finalBetCount, 576)
        // 153 naturally rejected here: this is not a 30/40/50-bet truncation.
        XCTAssertEqual(729 - result.finalBetCount, 153)
        XCTAssertEqual(result.duplicateExpandedBetCount, 0)
        XCTAssertEqual(result.queryAttribution(for: [0,0,3,1,3,0]), .hit)
        guard case .excluded(let reason) = result.queryAttribution(for: [0,0,0,1,3,3]) else {
            return XCTFail("必须准确归因到判定值4的个数，而不是赔率减注")
        }
        XCTAssertTrue(reason.contains("前5场判定值4出现3次"))
        XCTAssertFalse(reason.contains("冷尾"))
        XCTAssertFalse(result.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip5FourCountFilterEnabled"], "1")
        let off = try FilterConfig.parse(input.replacingOccurrences(of: "SVIP5FOURCAPON=1", with: "SVIP5FOURCAPON=0"))
        XCTAssertFalse(off.svip5FourCountFilterEnabled)
        XCTAssertTrue(off.svip5FourCountFailureReasons(for: [0,0,0,1,3,3]).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.calculate(off, previousContext: nil).finalBetCount, 729)
    }

    func testSVIP5FourCountOnCurrentBaselineNeverReintroducesRejectedBets() throws {
        let input = "1,2,3,4,5,6|CBCBCC|14-20|4-6|1|3|0.04|11|0-940|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=0-4750|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=4|NO4SINGLE=1|NO4=1|VIP12PROBON=0|7:3|MERGE3"
        let odds = Array(repeating: [3.0,3.0,3.0], count: 6)
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil, currentOutcomeSPs: odds)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|7:3|", with: "|SVIP5FOURCAPON=1|7:3|"))
        let selected = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds, captureQueryStages: true)
        let expected = Set(baseline.uniqueExpandedBets.filter { config.svip5FourCountFailureReasons(for: $0).isEmpty })
        XCTAssertEqual(Set(selected.uniqueExpandedBets), expected)
        XCTAssertGreaterThan(baseline.finalBetCount, selected.finalBetCount)
        XCTAssertEqual(selected.duplicateExpandedBetCount, 0)
        XCTAssertFalse(selected.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        for bet in Set(baseline.uniqueExpandedBets).subtracting(expected) {
            guard case .excluded(let reason) = selected.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("实际结构淘汰应有生成时的归因")
            }
            XCTAssertTrue(reason.contains("前5场判定值4出现"))
        }
    }

    func testSVIP5FinalReductionRemovesThirtyActualBetsAndNeverAddsThemBack() throws {
        let input = "1,2,3,4,5,6|CBCBCC|14-19|4-6|1|3|0.04|8|2-940|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=0-4750|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=4|NO4SINGLE=1|NO4=1|VIP12PROBON=1|7:3|MERGE3"
        let odds = Array(repeating: [2.0, 3.0, 5.0], count: 6)
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil,
            currentOutcomeProbabilities: Array(repeating: [0.5, 0.3, 0.2], count: 6), currentOutcomeSPs: odds, captureQueryStages: true)
        let config = try FilterConfig.parse(input.replacingOccurrences(of: "|7:3|", with: "|SVIP5DROP=30|7:3|"))
        let reduced = SequenceFilterEngine.calculate(config, previousContext: nil,
            currentOutcomeProbabilities: Array(repeating: [0.5, 0.3, 0.2], count: 6), currentOutcomeSPs: odds, captureQueryStages: true)
        XCTAssertGreaterThan(baseline.finalBetCount, 30)
        XCTAssertEqual(baseline.finalBetCount - reduced.finalBetCount, 30)
        XCTAssertTrue(Set(reduced.uniqueExpandedBets).isSubset(of: Set(baseline.uniqueExpandedBets)))
        XCTAssertEqual(reduced.duplicateExpandedBetCount, 0)
        let removed = Set(baseline.uniqueExpandedBets).subtracting(reduced.uniqueExpandedBets)
        XCTAssertEqual(removed.count, 30)
        for bet in removed {
            guard case .excluded(let reason) = reduced.queryAttribution(for: Array(bet.prefix(6))) else {
                return XCTFail("冷尾删除的组合必须归因到实际冷尾阶段")
            }
            XCTAssertTrue(reason.contains("SVIP5自定义赔率联合概率冷尾减30注"))
        }
        for index in 0..<729 {
            var value = index
            var target = Array(repeating: 0, count: 6)
            for slot in (0..<6).reversed() {
                target[slot] = [3, 1, 0][value % 3]
                value /= 3
            }
            let expectedHit = reduced.uniqueExpandedBets.contains { Array($0.prefix(6)) == target }
            switch reduced.queryAttribution(for: target) {
            case .hit: XCTAssertTrue(expectedHit)
            case .excluded: XCTAssertFalse(expectedHit)
            case .unavailable(let reason): XCTFail("完整生成记录必须覆盖所有729种查询：\(reason)")
            }
        }

        XCTAssertFalse(reduced.filterStageSummaries.contains { $0.contains("统计暂不可用") })
        XCTAssertTrue(reduced.filterStageSummaries.contains { $0.contains("SVIP5自定义赔率冷尾减30注：过滤30注") })
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(FilterInputDefaults.values(from: config)["svip5TailReductionEnabled"], "1")
    }

    func testTXTAttributionUsesLastActualEliminationAfterReintroduction() throws {
        let config = try FilterConfig.parse("1,2,3,4,5,6|AAAAAA|0-0|0-20|100|6|0|100|0-5|FINAL=OFF|7:3|MERGE3")
        var result = SequenceFilterEngine.calculate(config, previousContext: nil)
        let target = [3,3,3,3,3,3]
        guard case .unavailable = result.queryAttribution(for: target) else {
            return XCTFail("旧结果无逐阶段记录时不得猜测归因")
        }
        result.queryStages = [
            FilterQueryStage(name: "输入全集", survivors: [target]),
            FilterQueryStage(name: "初次淘汰", survivors: []),
            FilterQueryStage(name: "补注重新加入", survivors: [target]),
            FilterQueryStage(name: "最终冷尾淘汰", survivors: [])
        ]
        guard case .excluded(let reason) = result.queryAttribution(for: target) else {
            return XCTFail("应定位最终实际淘汰阶段")
        }
        XCTAssertTrue(reason.hasPrefix("最终冷尾淘汰"))
        XCTAssertFalse(reason.contains("初次淘汰"))
        guard case .unavailable = result.queryAttribution(for: [9,3,3,3,3,3]) else {
            return XCTFail("无效赛果不得归因为过滤条件")
        }
    }

    func testSVIP5TailRequiresCompleteCustomOddsAndKeepsOneSmallSample() throws {
        let bets = [[3,3,3,3,3,3,3], [0,0,0,0,0,0,3]]
        let odds = Array(repeating: [2.0,3.0,5.0], count: 6)
        XCTAssertEqual(SequenceFilterEngine.reduceSVIP5CustomOddsTailBets(bets,
            customOdds: odds, removalCount: 30), [bets[0]])
        XCTAssertTrue(SequenceFilterEngine.reduceSVIP5CustomOddsTailBets(bets,
            customOdds: nil, removalCount: 30).isEmpty)
        XCTAssertEqual(SequenceFilterEngine.reduceSVIP5CustomOddsTailBets(Array(bets.reversed()),
            customOdds: odds, removalCount: 30), [bets[0]])
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|1|6|0|100|0-5|SVIP5DROP=30|7:3|MERGE3"
        XCTAssertTrue(try FilterConfig.parse(input).requiresSPData)
        XCTAssertThrowsError(try FilterConfig.parse(input.replacingOccurrences(of: "SVIP5DROP=30", with: "SVIP5DROP=-1")))
    }

    func testSVIP4CountsOnlyDistinctFrontFiveOrdersAndSelectsLowestCustomOddsMatch() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|4-6|100|6|0|100|0-5|QDROP0|MCOUNT=5|CALCCOUNT=5|MPERM=7|NO4LOWODDS=1|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertEqual(config.minimumDistinctDisplacementOrders, 7)
        XCTAssertEqual(config.validDistinctDisplacementOrderCount(in: [2, 2, 3, 3, 4, 2]), 20)
        XCTAssertTrue(config.passesDisplacement(in: [2, 2, 3, 3, 4, 2]))
        XCTAssertFalse(config.passesDisplacement(in: [2, 2, 2, 2, 2, 2]))
        // 第1场最低单项赔率是1.05，但判定值4的概率最低的是第3场。
        let odds = [[1.05, 2.0, 3.0], [2.0, 3.0, 4.0], [2.0, 3.0, 20.0],
                    [2.0, 3.0, 4.0], [2.0, 3.0, 4.0], [1.1, 3.0, 4.0]]
        XCTAssertEqual(config.lowestCustomOddsNoFourPosition(in: odds), 3)
        XCTAssertEqual(config.lowestFourProbabilityNoFourSelection(in: odds)?.probability ?? -1,
                       0.05 / (0.5 + 1.0 / 3.0 + 0.05), accuracy: 1e-12)
        XCTAssertNil(config.lowestCustomOddsNoFourPosition(in: Array(odds.prefix(4))))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let attainableCounts = Set((0..<243).map { index -> Int in
            var remainder = index
            var values: [Int] = []
            for _ in 0..<5 {
                values.append([2, 3, 4][remainder % 3])
                remainder /= 3
            }
            return config.validDistinctDisplacementOrderCount(in: values + [2])
        })
        XCTAssertFalse(attainableCounts.contains(4))
        XCTAssertEqual(attainableCounts, Set([0, 1, 3, 6, 7, 14, 20]))
    }

    func testSVIP4ManualMinimumDistinctOrdersChangesFilteringAndRestoresFromSnapshot() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|4-6|100|6|0|100|0-5|QDROP0|MCOUNT=5|CALCCOUNT=5|MPERM=7|7:0|MERGE3"
        let seven = try FilterConfig.parse(input)
        let fourteen = try FilterConfig.parse(input.replacingOccurrences(of: "MPERM=7", with: "MPERM=14"))
        let sevenOrderValues = try XCTUnwrap((0..<243).compactMap { index -> [Int]? in
            var remainder = index
            let values = (0..<5).map { _ -> Int in
                defer { remainder /= 3 }
                return [2, 3, 4][remainder % 3]
            }
            return seven.validDistinctDisplacementOrderCount(in: values + [2]) == 7 ? values + [2] : nil
        }.first)
        XCTAssertTrue(seven.passesDisplacement(in: sevenOrderValues))
        XCTAssertFalse(fourteen.passesDisplacement(in: sevenOrderValues))
        XCTAssertEqual(FilterInputDefaults.values(from: fourteen)["svip4MinimumDistinctMOrdersInput"], "14")
        XCTAssertEqual(try FilterConfig.parse(fourteen.normalizedInput).minimumDistinctDisplacementOrders, 14)
    }

    func testSVIP4EngineUsesPermutationAndDynamicNoFourWithoutFixedBetCap() throws {
        let input = "1,2,3,4,5,6|CBCBCC|14-20|4-6|1|3|0.04|11|0-940|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=250-2000|HODDSPRODCOUNT=6|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|MPERM=7|NO4LOWODDS=1|NO4=|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        let odds = Array(repeating: [3.0, 3.0, 3.0], count: 6)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertEqual(result.config.resolvedLowestCustomOddsNoFourPosition, 1)
        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("不同排列≥7种") })
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bets in
            config.logic[0].value(for: bets[0]) != 4
        })
        let forbiddenOutcome = try XCTUnwrap([3, 1, 0].first { config.logic[0].value(for: $0) == 4 })
        let failures = SequenceFilterEngine.baseFilterFailureReasons(
            for: [forbiddenOutcome, 3, 3, 3, 3, 3],
            config: result.config,
            currentOutcomeSPs: nil
        )
        XCTAssertTrue(failures.contains("4概率最低的第1场判定值为4"))
        XCTAssertLessThanOrEqual(result.finalBetCount - result.preFullPackageBetCount, 12)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
            let values = zip(result.config.logic, bet).map { $0.value(for: $1) }
            return result.config.passesDisplacement(in: values)
        })
        let originalBets = result.records.map { $0.outcomes + [3] }
        let originalRows = SequenceFilterEngine.recursivelyMergedOptionRows(originalBets).count
        let finalRows = SequenceFilterEngine.recursivelyMergedOptionRows(result.uniqueExpandedBets).count
        XCTAssertTrue(Set(originalBets).isSubset(of: Set(result.uniqueExpandedBets)))
        XCTAssertEqual(result.rawExpandedBetCount, result.finalBetCount)
        XCTAssertGreaterThanOrEqual(originalRows - finalRows, 10,
                                    "原始\(originalRows)行，补注后\(finalRows)行")
        XCTAssertLessThanOrEqual(originalRows - finalRows, 20)
        XCTAssertLessThanOrEqual(result.finalBetCount - originalBets.count, 12)
        print("SVIP4 CBCBCC original=\(originalBets.count) final=\(result.finalBetCount) rows=\(originalRows)->\(finalRows)")

        let relaxedConfig = try FilterConfig.parse(input.replacingOccurrences(of: "MPERM=7", with: "MPERM=6"))
        let relaxedResult = SequenceFilterEngine.calculate(relaxedConfig, previousContext: nil, currentOutcomeSPs: odds)
        XCTAssertLessThanOrEqual(relaxedResult.finalBetCount - relaxedResult.preFullPackageBetCount, 12)
        XCTAssertTrue(relaxedResult.uniqueExpandedBets.allSatisfy { bet in
            let values = zip(relaxedResult.config.logic, bet).map { $0.value(for: $1) }
            return relaxedResult.config.passesDisplacement(in: values)
        })
    }

    func testSVIP4ManualNoFourUsesChosenPositionWithoutOdds() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|QDROP0|FINAL=OFF|MCOUNT=5|CALCCOUNT=5|MPERM=7|NO4LOWODDS=0|NO4SINGLE=1|NO4=3|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertFalse(config.lowestCustomOddsNoFourEnabled)
        XCTAssertEqual(config.noFourPositions, [3])
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
            config.logic[2].value(for: bet[2]) != 4
        })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("第3场判定值不是4") })
    }

    func testQueryFinalityGateRejectsLiveScoresAndOnlyAllowsPostponementOverTwelveHours() {
        func match(
            number: Int,
            status: String,
            homeScore: Int? = nil,
            awayScore: Int? = nil
        ) -> BeijingSingleMatch {
            BeijingSingleMatch(
                issue: "26103",
                matchNumber: String(number),
                fixtureID: "finality-\(number)",
                league: "测试",
                matchTime: "10-10 18:00",
                status: status,
                homeTeam: "主",
                awayTeam: "客",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: homeScore,
                awayScore: awayScore
            )
        }

        let finished = (1...6).map { match(number: $0, status: "完", homeScore: 1, awayScore: 0) }
        XCTAssertTrue(QueryFinalityGate.permitsResult(matches: finished, expectedCount: 6))

        var live = finished
        live[2] = match(number: 3, status: "已开赛", homeScore: 2, awayScore: 0)
        XCTAssertFalse(QueryFinalityGate.permitsResult(matches: live, expectedCount: 6))

        var postponedTwelve = finished
        postponedTwelve[2] = match(number: 3, status: "延期12小时")
        XCTAssertFalse(QueryFinalityGate.permitsResult(matches: postponedTwelve, expectedCount: 6))

        var postponedThirteen = finished
        postponedThirteen[2] = match(number: 3, status: "延期13小时")
        XCTAssertTrue(QueryFinalityGate.permitsResult(matches: postponedThirteen, expectedCount: 6))
        XCTAssertEqual(QueryFinalityGate.resolvedOutcome(postponedThirteen[2]), 1)
    }

    func testVIP12RoundTripsAndRequiresProbabilityData() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|QDROP0|FINAL=OFF|VIP12PROBON=1|7:0|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertTrue(config.vip12ProbabilityReductionEnabled)
        XCTAssertTrue(config.requiresProbabilityData)
        XCTAssertFalse(config.requiresStrictProbabilityData)
        XCTAssertTrue(config.normalizedInput.contains("VIP12PROBON=1"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
    }

    func testVIP12ProbabilityStageRemovesTenPercentBeforeControlledDefenseBets() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|QDROP0|FINAL=OFF|VIP12PROBON=1|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(result.preFullPackageBetCount, 656)
        XCTAssertGreaterThanOrEqual(1 - Double(result.preFullPackageBetCount) / 729, 0.10)
        XCTAssertLessThanOrEqual(result.finalBetCount - result.preFullPackageBetCount, 28)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, result.finalBetCount)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("VIP12") && $0.contains("剩余656注") })
    }

    func testVIP16Top200IsExactSubsetWithoutSpecialCaseOrDefenseBets() throws {
        let baselineInput = "1,2,3,4,5,6|AAAAAA|12-17|0-20|100|6|0|100|0-5|QDROP0|FINAL=OFF|7:0|MERGE3"
        let baseline = SequenceFilterEngine.calculate(try FilterConfig.parse(baselineInput), previousContext: nil)
        let vip16Config = try FilterConfig.parse(
            baselineInput.replacingOccurrences(of: "|7:0", with: "|VIP12PROBON=1|VIP16TOP200ON=1|7:0")
        )
        XCTAssertTrue(vip16Config.vip16Top200Enabled)
        XCTAssertTrue(vip16Config.requiresProbabilityData)
        XCTAssertEqual(try FilterConfig.parse(vip16Config.normalizedInput), vip16Config)

        let vip16 = SequenceFilterEngine.calculate(vip16Config, previousContext: nil)
        XCTAssertEqual(vip16.preFullPackageBetCount, 200)
        XCTAssertEqual(vip16.finalBetCount, 200)
        XCTAssertEqual(vip16.rawExpandedBetCount, 200)
        XCTAssertEqual(vip16.duplicateExpandedBetCount, 0)
        let baselineQualified = baseline.records.map { $0.outcomes + [0] }
        let expected = SequenceFilterEngine.selectHighestProbabilityBets(
            baselineQualified,
            probabilities: vip16.finalScoringRows,
            scoredMatchCount: 6,
            maximumCount: 200
        )
        XCTAssertEqual(Set(vip16.uniqueExpandedBets), Set(expected))
        XCTAssertTrue(vip16.filterStageSummaries.contains { $0.contains("VIP16") && $0.contains("剩余200注") })
        XCTAssertEqual(baseline.preFullPackageBetCount, 294)
    }

    func testVIP16NeverPadsAQualifiedPoolBelowTwoHundred() {
        let bets = [[3, 3, 3, 3, 3, 3], [1, 1, 1, 1, 1, 1]]
        let selected = SequenceFilterEngine.selectHighestProbabilityBets(
            bets,
            probabilities: Array(repeating: [0.6, 0.3, 0.1], count: 6),
            scoredMatchCount: 6,
            maximumCount: 200
        )
        XCTAssertEqual(Set(selected), Set(bets))
    }

    func testVIP18UsesFull729PoolAndFrozenProbabilityRanking() throws {
        let baselineInput = "1,2,3,4,5,6|AAAAAA|12-24|0-100|100|6|0|100|0-5|QDROP0|FINAL=OFF|MKTW=0|7:0|MERGE3"
        let baselineConfig = try FilterConfig.parse(baselineInput)
        let baseline = SequenceFilterEngine.calculate(baselineConfig, previousContext: nil)
        XCTAssertEqual(baseline.preFullPackageBetCount, 729)
        let probabilities = Array(repeating: [0.55, 0.30, 0.15], count: 6)
        let vip18Config = try FilterConfig.parse(
            baselineInput.replacingOccurrences(of: "|7:0", with: "|VIP18TOP200ON=1|7:0")
        )
        XCTAssertTrue(vip18Config.requiresStrictProbabilityData)
        XCTAssertTrue(vip18Config.noFourPositions.isEmpty)
        XCTAssertEqual(try FilterConfig.parse(vip18Config.normalizedInput), vip18Config)
        let result = SequenceFilterEngine.calculate(
            vip18Config, previousContext: nil, currentOutcomeProbabilities: probabilities
        )
        XCTAssertEqual(result.preFullPackageBetCount, 200)
        XCTAssertEqual(result.finalBetCount, 200)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 200)
        let expected = SequenceFilterEngine.selectVIP18Top200Bets(
            baseline.records.map { $0.outcomes + [0] },
            probabilities: probabilities,
            scoredMatchCount: 6
        )
        XCTAssertEqual(Set(result.uniqueExpandedBets), Set(expected))
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("VIP18") && $0.contains("剩余200注") })
    }

    func testVIP12CurrentXSCombinationRetainsVIP11Conditions() throws {
        let vip11Input = "5,6,7,8,9,10|BABABB|13-17|3-6|1|4|0.024|15|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|MAX4F3=1|17:3|MERGE3"
        let vip11 = SequenceFilterEngine.calculate(try FilterConfig.parse(vip11Input), previousContext: nil)
        let vip12 = SequenceFilterEngine.calculate(
            try FilterConfig.parse(vip11Input.replacingOccurrences(of: "|17:3", with: "|VIP12PROBON=1|17:3")),
            previousContext: nil
        )

        XCTAssertLessThanOrEqual(vip12.preFullPackageBetCount, Int((Double(vip11.preFullPackageBetCount) * 0.9).rounded(.down)))
        XCTAssertLessThanOrEqual(vip12.finalBetCount - vip12.preFullPackageBetCount, 28)
        XCTAssertLessThanOrEqual(vip12.displayResultLines.count, 45)
        let originalVIP12Bets = Set(vip12.records.map { $0.outcomes + [3] })
        XCTAssertTrue(originalVIP12Bets.isSubset(of: Set(vip12.uniqueExpandedBets)))
        print("VIP12 XS rows=\(vip12.displayResultLines.count), bets=\(vip12.finalBetCount), VIP11 exact=\(vip11.preFullPackageBetCount)")
    }

    func testVIP12CurrentDeviceCCBABBMeetsConstitutionSeven() throws {
        let input = "18,19,20,21,22,23|CCBABB|13-17|3-6|1|3|0.04|11|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=3|VIP12PROBON=1|42:0|MERGE3"
        let odds: [(Int, Int, [Double])] = [
            (18, -1, [1.64, 3.81, 4.69]),
            (19, -1, [1.71, 3.58, 4.49]),
            (20, -2, [1.14, 7.42, 13.66]),
            (21, 0, [2.45, 2.99, 3.06]),
            (22, 0, [2.40, 3.18, 2.75]),
            (23, 1, [5.20, 4.18, 1.50])
        ]
        let probabilities = try odds.map { number, handicap, values in
            try PoissonGoalModel.analyze(BeijingSingleMatch(
                issue: "26102",
                matchNumber: String(number),
                fixtureID: "current-\(number)",
                league: "测试",
                matchTime: "10-06 18:00",
                status: "未",
                homeTeam: "主",
                awayTeam: "客",
                handicap: handicap,
                referenceSP: [],
                marketOdds: values
            )).handicapProbabilities
        }
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )

        XCTAssertLessThanOrEqual(result.finalBetCount - result.preFullPackageBetCount, 28)
        XCTAssertTrue((35...45).contains(result.displayResultLines.count))
        XCTAssertEqual(result.rawExpandedBetCount, result.finalBetCount)
        print("VIP12 current CCBABB rows=\(result.displayResultLines.count), original=\(result.preFullPackageBetCount), bets=\(result.finalBetCount)")
    }

    func testVIP15S15To20HasNoFourRestrictionsFor26103() throws {
        let cases: [(name: String, logic: String, outcomes: [Int])] = [
            ("1–6", "CBCBCC", [3, 3, 3, 3, 3, 0]),
            ("9–14", "CCBBCB", [1, 3, 3, 3, 0, 3]),
            ("72–77", "BCCCAA", [1, 1, 3, 0, 0, 1]),
            ("82–87", "CBBCAD", [3, 0, 3, 1, 3, 0]),
            ("83–88", "BBCADB", [0, 3, 1, 3, 0, 3]),
            ("128–133", "BCCCCC", [1, 3, 3, 3, 0, 1]),
            ("263–268", "CAABBB", [3, 1, 1, 3, 1, 1]),
            ("254–259", "BBBBCC", [1, 1, 3, 1, 3, 0]),
            ("305–310", "CCCCBB", [3, 1, 3, 3, 0, 3]),
            ("272–277", "CBBCCC", [3, 1, 0, 0, 1, 3])
        ]
        var basePassing: [String] = []
        var finalPassing: [String] = []

        for item in cases {
            let input = "1,2,3,4,5,6|\(item.logic)|15-20|2-9|1|3|0.024|15|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|VIP12PROBON=1|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|7:3|MERGE3"
            let config = try FilterConfig.parse(input)
            XCTAssertNil(config.frontThreeMaximumFourCount)
            XCTAssertTrue(config.noFourPositions.isEmpty)
            XCTAssertFalse(config.normalizedInput.contains("NO4SINGLE=1"))
            XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
            if SequenceFilterEngine.baseFilterFailureReasons(for: item.outcomes, config: config).isEmpty {
                basePassing.append(item.name)
            }
            let result = SequenceFilterEngine.calculate(config, previousContext: nil)
            if result.uniqueExpandedBets.contains(item.outcomes + [3]) {
                finalPassing.append(item.name)
            }
        }

        XCTAssertEqual(basePassing, cases.map(\.name))
        XCTAssertEqual(finalPassing, cases.map(\.name))
        print("VIP15 no-four 26103 final passing=\(finalPassing)")
    }

    func testSVIP2BasicConditionsCoverAllSettled26103Cases() throws {
        let cases: [(logic: String, outcomes: [Int])] = [
            ("CBCBCC", [3, 3, 3, 3, 3, 0]),
            ("CCBBCB", [1, 3, 3, 3, 0, 3]),
            ("BCCCAA", [1, 1, 3, 0, 0, 1]),
            ("CBBCAD", [3, 0, 3, 1, 3, 0]),
            ("BBCADB", [0, 3, 1, 3, 0, 3]),
            ("BCCCCC", [1, 3, 3, 3, 0, 1]),
            ("CAABBB", [3, 1, 1, 3, 1, 1]),
            ("BBBBCC", [1, 1, 3, 1, 3, 0]),
            ("CCCCBB", [3, 1, 3, 3, 0, 3]),
            ("CBBCCC", [3, 1, 0, 0, 1, 3])
        ]

        for item in cases {
            let input = "1,2,3,4,5,6|\(item.logic)|14-20|2-6|1|3|0.04|11|0-940|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=250-2000|HODDSPRODCOUNT=6|VIP12PROBON=1|SVIP1ODDSGUARDON=1|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|7:3|MERGE3"
            let config = try FilterConfig.parse(input)

            XCTAssertTrue(
                SequenceFilterEngine.baseFilterFailureReasons(
                    for: item.outcomes,
                    config: config,
                    currentOutcomeSPs: Array(repeating: [3, 3, 3], count: 6)
                ).isEmpty,
                "SVIP2基础条件不应排除 \(item.logic) / \(item.outcomes)"
            )
            XCTAssertTrue(config.noFourPositions.isEmpty)
            XCTAssertEqual(config.sumRange, 14...20)
            XCTAssertEqual(config.displacementRange, 2...6)
            XCTAssertEqual(config.customHandicapOddsProductRange, 250...2000)
        }
    }

    func testSVIP2LoadsAllSixMatchesForCustomOddsProduct() throws {
        let input = "1,2,3,4,5,6|CBCBCC|14-20|2-6|1|3|0.04|11|0-940|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|HODDSPRODON=1|HODDSPROD=250-2000|HODDSPRODCOUNT=6|VIP12PROBON=0|SVIP1ODDSGUARDON=0|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|7:3|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertEqual(config.calculationMatchCount, 5)
        XCTAssertEqual(config.customHandicapOddsProductMatchCount, 6)
        XCTAssertEqual(config.requiredCustomOddsMatchCount, 6)
    }

    func testVIP15CurrentXSBetCount() throws {
        let input = "128,129,130,131,132,133|BCCCCC|15-20|2-9|1|3|0.024|15|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|VIP12PROBON=1|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|374:3|MERGE3"
        let result = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil)

        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertLessThan(result.finalBetCount, 729)
        print("VIP15 XS BCCCCC original=\(result.preFullPackageBetCount), bets=\(result.finalBetCount), rows=\(result.displayResultLines.count)")
    }

    func testVIP11FinalExportKeepsRecursiveCompression() throws {
        let input = "34,35,36,37,38,39|CCBCCA|13-17|3-6|1|4|0.024|15|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|MAX4F3=1|1:0|MERGE3"
        let result = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil)

        XCTAssertGreaterThanOrEqual(result.finalBetCount, result.preFullPackageBetCount)
        XCTAssertLessThan(result.displayResultLines.count, result.finalBetCount)
        XCTAssertLessThanOrEqual(result.displayResultLines.count, 52)
        XCTAssertLessThanOrEqual(result.finalBetCount - result.preFullPackageBetCount, 28)
        print("VIP11 export rows=\(result.displayResultLines.count), bets=\(result.finalBetCount)")
    }

    func testVIP11CurrentXSRowsAndBets() throws {
        let input = "5,6,7,8,9,10|BABABB|13-17|3-6|1|4|0.024|15|0-40|QDROP0|FINAL=OFF|OC_WLSWITCH=0-2|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|NO4=|MAX4F3=1|17:3|MERGE3"
        let result = SequenceFilterEngine.calculate(try FilterConfig.parse(input), previousContext: nil)

        XCTAssertLessThanOrEqual(result.displayResultLines.count, 49)
        XCTAssertLessThanOrEqual(result.finalBetCount - result.preFullPackageBetCount, 28)
        print("VIP11 XS BABABB rows=\(result.displayResultLines.count), original=\(result.preFullPackageBetCount), bets=\(result.finalBetCount)")
    }

    func testVIP11UsesSixMatchesForSumButFiveForMAndOtherMetrics() throws {
        let input = "1,2,3,4,5,6|AAAAAA|14-14|0-0|0|5|0|0|0-0|QDROP0|FINAL=OFF|MCOUNT=5|SUMCOUNT=6|CALCCOUNT=5|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(config.displacementMatchCount, 5)
        XCTAssertEqual(config.sumMatchCount, 6)
        XCTAssertEqual(config.calculationMatchCount, 5)
        XCTAssertFalse(config.sumUsesOutcomeSP)
        XCTAssertTrue(config.normalizedInput.contains("SUMCOUNT=6"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(result.finalBetCount, 1)
        XCTAssertEqual(result.uniqueExpandedBets.first.map { Array($0.prefix(6)) }, [3, 3, 3, 3, 3, 0])

        let passing = SequenceFilterEngine.baseFilterFailureReasons(
            for: [3, 3, 3, 3, 3, 0],
            config: config
        )
        XCTAssertTrue(passing.isEmpty, "第6场只应参与S，不能影响前5场的M/σ²/R/B：\(passing)")
        let failing = SequenceFilterEngine.baseFilterFailureReasons(
            for: [3, 3, 3, 3, 3, 3],
            config: config
        )
        XCTAssertTrue(failing.contains { $0.contains("S=12") })
        XCTAssertFalse(failing.contains { $0.contains("M=") })
    }

    func testVIP10ParsesFrontFiveRealOddsScopeAndRoundTrips() throws {
        let input = "1,2,3,4,5,6|AAAAAA|13-17|3-6|100|5|0|100|0-5|QDROP0|MCOUNT=5|CALCCOUNT=5|REALSUM=1|7:3|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertEqual(config.matchNumbers.count, 6)
        XCTAssertEqual(config.displacementMatchCount, 5)
        XCTAssertEqual(config.calculationMatchCount, 5)
        XCTAssertTrue(config.sumUsesOutcomeSP)
        XCTAssertTrue(config.normalizedInput.contains("MCOUNT=5"))
        XCTAssertTrue(config.normalizedInput.contains("CALCCOUNT=5"))
        XCTAssertTrue(config.normalizedInput.contains("REALSUM=1"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
    }

    func testVIP10UsesRealOddsSumAndKeepsAllSixthMatchOutcomes() throws {
        let input = "1,2,3,4,5,6|AAAAAA|15-15|0-20|100|5|0|100|0-5|QDROP0|MCOUNT=5|CALCCOUNT=5|REALSUM=1|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        let odds = Array(repeating: [3.0, 20.0, 20.0], count: 5)
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: odds
        )

        XCTAssertEqual(result.finalBetCount, 3)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            Array($0.prefix(5)) == [3, 3, 3, 3, 3] && $0.last == 3
        })
        XCTAssertEqual(Set(result.uniqueExpandedBets.map { $0[5] }), Set([3, 1, 0]))
        let passingReasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: [3, 3, 3, 3, 3, 0],
            config: config,
            currentOutcomeSPs: odds
        )
        XCTAssertFalse(passingReasons.contains { $0.contains("真实让球欧赔S") })
        let failingReasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: [1, 3, 3, 3, 3, 0],
            config: config,
            currentOutcomeSPs: odds
        )
        XCTAssertTrue(failingReasons.contains { $0.contains("真实让球欧赔S=32.000") })
    }

    func testVIP10HistoricalFactoryKeepsSixthAsIgnoredMainMatch() throws {
        let current = "10,11,12,13,14,15|AAAAAA|13-17|3-6|100|5|0|100|0-5|QDROP0|MCOUNT=5|CALCCOUNT=5|REALSUM=1|16:3|MERGE3"
        let config = try XCTUnwrap(CurrentConditionConfigFactory.make(
            currentInput: current,
            historicalMatchNumbers: ["21", "22", "23", "24", "25", "26", "27"],
            historicalABCD: "ABCDD"
        ))

        XCTAssertEqual(config.matchNumbers, ["21", "22", "23", "24", "25", "26"])
        XCTAssertEqual(config.logic.count, 6)
        XCTAssertEqual(config.calculationMatchCount, 5)
        XCTAssertEqual(config.extraMatches.map(\.matchNumber), ["27"])
        XCTAssertEqual(config.extraMatches.first?.outcomes, [3])
    }

    func testVIP10RunConditionsIgnoreSixthAndSeventhMatches() throws {
        var config = try FilterConfig.parse("1,2,3,4,5,6|AAAAAA|0-99|0-99|100|6|0|100|0-5|QDROP0|CALCCOUNT=5|7:3|MERGE3")
        config.consecutiveRunsEnabled = true
        config.sameResultRunsEnabled = true

        let left = [3, 1, 0, 3, 1, 3, 3]
        let right = [3, 1, 0, 3, 1, 0, 0]
        XCTAssertEqual(config.passesConsecutiveRuns(left), config.passesConsecutiveRuns(right))
        XCTAssertEqual(config.passesSameResultRuns(left), config.passesSameResultRuns(right))
    }

    func testVIP9MCountUsesOnlyFirstFiveMainMatches() throws {
        let scopedInput = "1,2,3,4,5,6|AAAAAA|0-30|0-0|100|6|0|100|0-5|QDROP0|MCOUNT=5|7:3|MERGE3"
        let scoped = try FilterConfig.parse(scopedInput)
        let outcomes = [3, 3, 3, 3, 3, 0]

        XCTAssertEqual(scoped.displacementMatchCount, 5)
        XCTAssertEqual(scoped.displacementValue(in: [2, 2, 2, 2, 2, 4]), 0)
        XCTAssertTrue(SequenceFilterEngine.baseFilterFailureReasons(
            for: outcomes,
            config: scoped
        ).isEmpty)
        XCTAssertEqual(try FilterConfig.parse(scoped.normalizedInput), scoped)

        let sixMatch = try FilterConfig.parse(
            scopedInput.replacingOccurrences(of: "|MCOUNT=5", with: "")
        )
        XCTAssertEqual(sixMatch.displacementValue(in: [2, 2, 2, 2, 2, 4]), 2)
        XCTAssertTrue(SequenceFilterEngine.baseFilterFailureReasons(
            for: outcomes,
            config: sixMatch
        ).contains { $0.contains("M=2") })
    }

    func testVIPOffLegacyCleanupNoLongerKeepsFourteenBetMixedState() throws {
        let input = "35,36,37,38,39|CBCCA|13-18|4-8|1|3|0.04|8|0-4|QDROP0|FINAL=OFF|SEED=1|MKTW=0|RATE=20|OCTOLON=0|OCTOL=0-1|ALLTOLON=0|ALLTOL=0-1|RUNS=0|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=0-1|RUN2ON=0|RUN2RANGE=5-7|RUN2TOL=2-3|SAMERUNS=0|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=0|SPPRODON=0|SPPROD=30-900|HODDSPRODON=0|HODDSPROD=50-300|HODDSSUMON=0|HODDSSUM=12-16|PRIZEON=0|PRIZE=26-1950|SPRISKON=0|MAXSP=10|HIGHSPTH=4.5|HIGHSPCOUNT=0-2|MINPROBON=0|MINPROB=15|JOINTPROBON=0|JOINTPROB=0.1-100|GROUPON=0|GROUPMODE=BOTH|GFSUM=0-9|GBSUM=0-6|GFSP=1-200|GBSP=1-100|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=0|U247TH=0|V10TOP150ON=0|NO4=|40:310|1:0|MERGE3"
        let result = SequenceFilterEngine.calculate(
            try FilterConfig.parse(input),
            previousContext: nil
        )

        XCTAssertGreaterThan(result.finalBetCount, 14)
    }

    func testHandicapOddsMatrixAlwaysUsesOrdinaryOddsThroughComparisonTable() {
        let completeOrdinaryOdds = BeijingSingleMatch(
            issue: "26101", matchNumber: "2", fixtureID: "2", league: "测试",
            matchTime: "10-01 12:00", status: "未", homeTeam: "主", awayTeam: "客",
            handicap: -1, referenceSP: [99, 98, 97], marketOdds: [1.38, 4.0, 6.7]
        )
        let missingOrdinaryOdds = BeijingSingleMatch(
            issue: "26101", matchNumber: "3", fixtureID: "3", league: "测试",
            matchTime: "10-01 13:00", status: "完", homeTeam: "主", awayTeam: "客",
            handicap: -1, referenceSP: [2.1, 3.2, 3.6], marketOdds: [2.0]
        )

        let rows = HandicapOddsComparisonTableMatrix.rows(
            matchNumbers: ["2"],
            matches: [completeOrdinaryOdds]
        )
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?[0][0] ?? 0, 2.4824, accuracy: 0.001)
        XCTAssertEqual(rows?[0][1] ?? 0, 4.1300, accuracy: 0.001)
        XCTAssertEqual(rows?[0][2] ?? 0, 2.8167, accuracy: 0.001)
        XCTAssertNotEqual(rows?[0], completeOrdinaryOdds.referenceSP)

        XCTAssertNil(HandicapOddsComparisonTableMatrix.rows(
            matchNumbers: ["2", "3"],
            matches: [completeOrdinaryOdds, missingOrdinaryOdds]
        ))
        XCTAssertEqual(HandicapOddsComparisonTableMatrix.missingMatchNumbers(
            matchNumbers: ["2", "3"],
            matches: [completeOrdinaryOdds, missingOrdinaryOdds]
        ), ["3"])
    }

    func testCustomHandicapOddsProductAndSumFiltersUseSelectedOutcomeSPs() throws {
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|HODDSPRODON=1|HODDSPROD=50-300|HODDSSUMON=1|HODDSSUM=12-16|6:3|MERGE3"
        let config = try FilterConfig.parse(input)
        let spRows = Array(repeating: [2.0, 3.0, 4.0], count: 5)
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: spRows
        )

        XCTAssertTrue(config.customHandicapOddsProductFilterEnabled)
        XCTAssertTrue(config.customHandicapOddsSumFilterEnabled)
        XCTAssertFalse(result.uniqueExpandedBets.isEmpty)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
            let selected = zip(spRows, bet.prefix(5)).map { row, outcome in
                row[outcome == 3 ? 0 : (outcome == 1 ? 1 : 2)]
            }
            return (50.0...300.0).contains(selected.reduce(1, *))
                && (12.0...16.0).contains(selected.reduce(0, +))
        })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("自定义让球赔率乘积") })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("自定义让球赔率和值") })
    }

    func testProductSumV10DefaultsToMappedQAndSWithoutV8Top150() throws {
        let input = "1,2,3,4,5|CCCBC|12-18|2-7|1|3|0.04|8|0-4|QDROP0|FINAL=OFF|RUNS=1|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=2-3|SAMERUNS=1|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=1|U150ON=0|U247ON=1|U247TH=9.510|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertTrue(SequenceFilterEngine.usesProductSumV10Model(
            threshold: config.universal247ToleranceThreshold
        ))
        XCTAssertFalse(config.productSumV10Top150Enabled)
        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertLessThan(result.finalBetCount, 543)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
            let values = zip(config.logic, bet.prefix(5)).map { $0.value(for: $1) }
            return (50...299).contains(values.reduce(1, *))
                && (12...16).contains(values.reduce(0, +))
                && config.passesConsecutiveRuns(bet)
                && config.passesSameResultRuns(bet)
        })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("V10乘积Q＋和值S") })
    }

    func testVIP2KeepsExactly150AndRequiresComparisonTableOdds() throws {
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=1|U247TH=7.150|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let comparisonTableOdds = [
            [2.10, 3.15, 3.40],
            [1.82, 3.55, 4.20],
            [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10],
            [2.72, 3.20, 2.40]
        ]

        XCTAssertTrue(config.requiresSPData)
        XCTAssertTrue(SequenceFilterEngine.usesVIP2Model(
            threshold: config.universal247ToleranceThreshold
        ))

        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: comparisonTableOdds
        )
        XCTAssertEqual(result.finalBetCount, 150)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 150)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("VIP2") })

        let missingOdds = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(missingOdds.finalBetCount, 0)
    }

    func testVIP2RankingDoesNotUseABCDMapped234Values() throws {
        let prefix = "1,2,3,4,5|"
        let suffix = "|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=7.150|6:310|7:0|MERGE3"
        let odds = [
            [2.10, 3.15, 3.40], [1.82, 3.55, 4.20], [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10], [2.72, 3.20, 2.40]
        ]
        let a = SequenceFilterEngine.calculate(
            try FilterConfig.parse(prefix + "AAAAA" + suffix),
            previousContext: nil,
            currentOutcomeSPs: odds
        )
        let d = SequenceFilterEngine.calculate(
            try FilterConfig.parse(prefix + "DDDDD" + suffix),
            previousContext: nil,
            currentOutcomeSPs: odds
        )
        XCTAssertEqual(a.uniqueExpandedBets, d.uniqueExpandedBets)
    }

    func testVIP3UsesSixComparisonTableRowsAndKeepsExactly150() throws {
        let input = "1,2,3,4,5|ABCDA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=1|U247TH=7.153|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let odds = [
            [2.10, 3.15, 3.40], [1.82, 3.55, 4.20], [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10], [2.72, 3.20, 2.40], [2.06, 3.30, 3.48]
        ]
        let context = VIP3MatchContext(
            comparisonTableOdds: odds,
            handicaps: [0, -1, 1, 0, -2, 1],
            leagues: ["英超", "德甲", "西甲", "意甲", "法甲", "芬超"],
            logic: [.a, .b, .c, .d, .a, .b]
        )

        XCTAssertTrue(config.requiresSPData)
        XCTAssertTrue(SequenceFilterEngine.usesVIP3Model(
            threshold: config.universal247ToleranceThreshold
        ))
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: Array(odds.prefix(5)),
            vip3Context: context
        )
        XCTAssertEqual(result.finalBetCount, 150)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 150)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("VIP3") })

        let missingSixth = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: Array(odds.prefix(5))
        )
        XCTAssertEqual(missingSixth.finalBetCount, 0)
    }

    func testVIP3RankingDoesNotUseABCDMapped234Values() throws {
        let odds = [
            [2.10, 3.15, 3.40], [1.82, 3.55, 4.20], [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10], [2.72, 3.20, 2.40], [2.06, 3.30, 3.48]
        ]
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=7.153|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let base = VIP3MatchContext(
            comparisonTableOdds: odds,
            handicaps: [0, -1, 1, 0, -2, 1],
            leagues: ["英超", "德甲", "西甲", "意甲", "法甲", "芬超"],
            logic: Array(repeating: .a, count: 6)
        )
        let changed = VIP3MatchContext(
            comparisonTableOdds: odds,
            handicaps: base.handicaps,
            leagues: base.leagues,
            logic: Array(repeating: .d, count: 6)
        )
        XCTAssertEqual(
            SequenceFilterEngine.calculate(config, previousContext: nil, vip3Context: base).uniqueExpandedBets,
            SequenceFilterEngine.calculate(config, previousContext: nil, vip3Context: changed).uniqueExpandedBets
        )
    }

    func testProductSumV10CanEnableV8Top150BeforeMappedQAndS() throws {
        let input = "1,2,3,4,5|CCCBC|12-18|2-7|1|3|0.04|8|0-4|QDROP0|FINAL=OFF|RUNS=1|NLRUN=5-7|NDRUN=5-7|NWRUN=5-7|RUNTOL=2-3|SAMERUNS=1|WINRUN=2-4|DRAWRUN=2-3|LOSSRUN=2-3|SAMERUNTOL=2-3|PROTECT11=1|U150ON=0|U247ON=1|U247TH=9.510|V10TOP150ON=1|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertTrue(config.productSumV10Top150Enabled)
        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertLessThanOrEqual(result.finalBetCount, 150)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy { bet in
            let values = zip(config.logic, bet.prefix(5)).map { $0.value(for: $1) }
            return (50...299).contains(values.reduce(1, *))
                && (12...16).contains(values.reduce(0, +))
        })
    }

    func testProductSumV10DoesNotBypassOtherEnabledConditions() throws {
        let input = "1,2,3,4,5|CCCBC|0-0|0-0|0|0|100|0|0-0|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.510|6:310|7:0|MERGE3"
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertTrue(result.uniqueExpandedBets.isEmpty)
        XCTAssertEqual(result.finalBetCount, 0)
    }

    func testHandicapOddsV9UsesOnlyFiveComparisonTableOddsRowsAndFixedRanges() throws {
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.509|6:310|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.requiresSPData)
        XCTAssertFalse(config.requiresProbabilityData)
        XCTAssertTrue(SequenceFilterEngine.usesHandicapOddsV9Model(
            threshold: config.universal247ToleranceThreshold
        ))

        let uniform = Array(repeating: [3.0, 3.0, 3.0], count: 5)
        XCTAssertTrue(SequenceFilterEngine.passesUniversal247Tolerance(
            fullOutcomes: [3, 1, 0, 3, 1, 0],
            threshold: config.universal247ToleranceThreshold,
            logic: config.logic,
            comparisonTableOdds: uniform
        ))
        XCTAssertFalse(SequenceFilterEngine.passesUniversal247Tolerance(
            fullOutcomes: [3, 1, 0, 3, 1, 0],
            threshold: config.universal247ToleranceThreshold,
            logic: config.logic,
            comparisonTableOdds: nil
        ))
    }

    func testHandicapOddsV9DoesNotBypassCurrentConditionTab() throws {
        let input = "1,2,3,4,5|AAAAA|0-0|0-0|0|0|100|0|0-0|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.509|6:310|MERGE3"
        let config = try FilterConfig.parse(input)
        let odds = [
            [1.72, 4.0, 5.88], [2.13, 3.33, 4.35], [2.78, 3.23, 3.03],
            [1.96, 3.57, 4.76], [2.38, 3.13, 3.85]
        ]
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: odds
        )

        XCTAssertEqual(result.finalBetCount, 0)
        XCTAssertTrue(result.uniqueExpandedBets.isEmpty)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("V9让球欧赔") })
    }

    func testHandicapOddsV9AddsOddsFilterAfterCurrentConditions() throws {
        let input = "1,2,3,4,5|AAAAA|10-20|0-8|10|3|0.04|12|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.509|6:310|MERGE3"
        let config = try FilterConfig.parse(input)
        let odds = [
            [1.72, 4.0, 5.88], [2.13, 3.33, 4.35], [2.78, 3.23, 3.03],
            [1.96, 3.57, 4.76], [2.38, 3.13, 3.85]
        ]
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeSPs: odds
        )

        XCTAssertGreaterThan(result.finalBetCount, 0)
        XCTAssertLessThan(result.finalBetCount, 729)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            SequenceFilterEngine.passesUniversal247Tolerance(
                fullOutcomes: $0,
                threshold: config.universal247ToleranceThreshold,
                logic: config.logic,
                comparisonTableOdds: odds
            )
        })
    }

    func testJoint150V8AlwaysKeepsExactly150AndIsDeterministic() throws {
        let input = FilterConfig.currentInput.replacingOccurrences(
            of: "|6:310",
            with: "|U247ON=1|U247TH=8.150|6:310"
        )
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(SequenceFilterEngine.usesJoint150V8Model(
            threshold: config.universal247ToleranceThreshold
        ))
        let probabilities = [
            [0.62, 0.23, 0.15], [0.45, 0.30, 0.25], [0.31, 0.29, 0.40],
            [0.54, 0.27, 0.19], [0.37, 0.34, 0.29]
        ]
        let first = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )
        let second = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )
        XCTAssertEqual(first.finalBetCount, 150)
        XCTAssertEqual(first.uniqueExpandedBets, second.uniqueExpandedBets)
        XCTAssertTrue(first.reportText.contains("V8联合150"))
    }

    func testJoint150V8Keeps150WithoutProbabilityDataAndWithTwoSeventhOptions() throws {
        let input = FilterConfig.currentInput
            .replacingOccurrences(
                of: "|6:310",
                with: "|U247ON=1|U247TH=8.150|6:310"
            )
            .replacingOccurrences(of: "|7:3|", with: "|7:30|")
        let config = try FilterConfig.parse(input)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(result.finalBetCount, 150)
        XCTAssertEqual(result.uniqueExpandedBets.count, 150)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 150)
    }

    func testHistoricalBatchPlannerUsesSixMatchBlocksAndFixedSeventhMatchOne() {
        XCTAssertEqual(
            HistoricalBatchPlanner.groupStarts(maximumMatchNumber: 139),
            Array(stride(from: 2, through: 134, by: 6))
        )
        XCTAssertEqual(
            HistoricalBatchPlanner.groupStarts(maximumMatchNumber: 385),
            Array(stride(from: 2, through: 380, by: 6))
        )
        XCTAssertEqual(
            HistoricalBatchPlanner.groupStarts(maximumMatchNumber: 97),
            Array(stride(from: 2, through: 92, by: 6))
        )
        XCTAssertEqual(HistoricalBatchPlanner.groupStarts(maximumMatchNumber: 6), [])
        XCTAssertEqual(
            HistoricalBatchPlanner.ticketMatchNumbers(start: 8),
            ["8", "9", "10", "11", "12", "13", "1"]
        )
    }

    func testVoiceMatchNumberParsingSupportsArabicAndChinese() {
        XCTAssertEqual(
            MatchSpeechInput.parseMatchNumbers(from: "12、18、25、31"),
            ["12", "18", "25", "31"]
        )
        XCTAssertEqual(
            MatchSpeechInput.parseMatchNumbers(from: "十二 十八 二十五 三十一"),
            ["12", "18", "25", "31"]
        )
        let fixed = MatchSpeechInput.parseFixedSelections(from: "5场选3，6场选31，7场选310")
        XCTAssertEqual(fixed?.map(\.match), ["5", "6", "7"])
        XCTAssertEqual(fixed?.map(\.outcome), ["3", "31", "310"])
    }

    func testCurrentConfigurationParsesAllFields() throws {
        let config = try FilterConfig.parse("1,2,3,4|CCCB|9-14|1-6|1.3|3|0.5|5:3|6:31|7:310|MERGE3")

        XCTAssertEqual(config.matchNumbers, ["1", "2", "3", "4"])
        XCTAssertEqual(config.logic, [.c, .c, .c, .b])
        XCTAssertEqual(config.sumRange, 9...14)
        XCTAssertEqual(config.displacementRange, 1...6)
        XCTAssertEqual(config.varianceMaximum, 1.3)
        XCTAssertEqual(config.valueTwoMaximum, 3)
        XCTAssertEqual(config.transitionMinimumPercent, 0.5)
        XCTAssertEqual(config.roughnessMaximum, 6)
        XCTAssertEqual(config.probabilityRemovalPercent, 50)
        XCTAssertEqual(config.extraMatches.map(\.matchNumber), ["5", "6", "7"])
        XCTAssertEqual(config.extraMatches.map(\.outcomes), [[3], [3, 1], [3, 1, 0]])
        XCTAssertEqual(config.extraExpansionFactor, 6)
    }

    func testHistoricalRefreshUsesOnlyCurrentTabConditions() throws {
        let currentTabInput = "1,2,3,4,5|AAAAA|13-17|3-7|1|3|0.15|11|1-6|QDROP0|RUNS=1|NLRUN=3-7|NDRUN=3-7|NWRUN=3-7|RUNTOL=0-1|SAMERUNS=0|PRIZECOUNTON=1|6:310|7:0|MERGE3"
        let config = try XCTUnwrap(CurrentConditionConfigFactory.make(
            currentInput: currentTabInput,
            historicalMatchNumbers: ["101", "102", "103", "104", "105", "106", "107"],
            historicalABCD: "CCBDD"
        ))

        XCTAssertEqual(config.matchNumbers, ["101", "102", "103", "104", "105"])
        XCTAssertEqual(config.logic, [.c, .c, .b, .d, .d])
        XCTAssertEqual(config.sumRange, 13...17)
        XCTAssertTrue(config.consecutiveRunsEnabled)
        XCTAssertEqual(config.consecutiveRunToleranceRange, 0...1)
        XCTAssertFalse(config.prizeStatisticalCountPatternEnabled)
        XCTAssertEqual(config.extraMatches.map(\.matchNumber), ["106", "107"])
        XCTAssertEqual(config.extraMatches.map(\.outcomes), [[3, 1, 0], [0]])
    }

    func testUniversalCompressionIgnoresLegacyPairWhitelistAndUsesOnlyRanges() throws {
        let config = try FilterConfig.parse(
            "75,76,77,78,79|ABCCD|0-99|0-99|99|99|0|11|80:310|MERGE3"
        )
        let outcomes = [0, 0, 1, 0, 1, 1]
        let rules = [
            ComprehensiveAnalysisRule(
                metric: .winCount,
                lowerBound: 0,
                upperBound: 0,
                sampleCount: 34,
                score: 1
            )
        ]
        let profile = ComprehensiveAnalysisProfile(
            generatedAt: Date(),
            historyRecordCount: 34,
            runSampleCount: 34,
            advancedSampleCount: 34,
            rules: rules,
            recommendedMetric: .variance,
            protectedExactSignatures: ["specific-outcome"],
            protectedAllowedPairSignatures: ["specific-position-pair"],
            protectedOutcomePositionCounts: Array(repeating: [100, 0, 0], count: 6)
        )

        XCTAssertEqual(
            SequenceFilterEngine.comprehensiveAnalysisFailureCount(
                fullOutcomes: outcomes,
                config: config,
                profile: profile,
                outcomeProbabilities: nil,
                outcomeSPs: nil
            ),
            0
        )
    }

    func testRecommendedConditionsAreGeneratedFromABCDAndPoissonProbabilities() throws {
        let recommended = try XCTUnwrap(SequenceFilterEngine.recommendedConditions(
            logic: [.c, .c, .c, .b],
            outcomeProbabilities: [
                [0.58, 0.25, 0.17],
                [0.42, 0.31, 0.27],
                [0.61, 0.23, 0.16],
                [0.36, 0.34, 0.30]
            ]
        ))

        XCTAssertTrue((8...16).contains(recommended.sumRange.lowerBound))
        XCTAssertTrue((8...16).contains(recommended.sumRange.upperBound))
        XCTAssertTrue((0...6).contains(recommended.displacementRange.lowerBound))
        XCTAssertTrue((0...6).contains(recommended.displacementRange.upperBound))
        XCTAssertTrue((0...1).contains(recommended.varianceMaximum))
        XCTAssertTrue((0...4).contains(recommended.valueTwoMaximum))
        XCTAssertGreaterThan(recommended.transitionMinimumPercent, 0)
    }

    func testRecommendedConditionsCanUseABCDWithoutLiveOdds() throws {
        let recommended = try XCTUnwrap(
            SequenceFilterEngine.recommendedConditions(logic: [.a, .a, .d, .b])
        )
        XCTAssertTrue((8...16).contains(recommended.sumRange.lowerBound))
        XCTAssertTrue((8...16).contains(recommended.sumRange.upperBound))
        XCTAssertGreaterThan(recommended.transitionMinimumPercent, 0)
    }

    func testCurrentConfigurationProducesExpectedCountsAndCompactCompression() throws {
        let config = try FilterConfig.parse(FilterConfig.currentInput)
        let result = SequenceFilterEngine.calculate(config, previousContext: previousContext)

        XCTAssertEqual(config.matchNumbers.count, 5)
        XCTAssertEqual(config.logic.count, 5)
        XCTAssertEqual(config.extraMatches.count, 2)
        XCTAssertEqual(config.extraExpansionFactor, 3)
        XCTAssertEqual(config.breakpointRange, 2...6)
        XCTAssertEqual(config.productRemovalCount, 100)
        XCTAssertEqual(result.statistics.total, 243)
        XCTAssertEqual(result.stageBetCounts, [729, 629, 626, 482, 482, 482, 398, 362, 344])
        XCTAssertEqual(result.records.count, 115)
        XCTAssertEqual(result.finalBetCount, 344)
        XCTAssertEqual(
            result.compressedRecords.reduce(0) { total, record in
                total + record.options.reduce(1) { $0 * $1.count }
            },
            result.records.count
        )
        let expanded = result.compressedRecords.flatMap { expandedOutcomes($0.options) }
        XCTAssertEqual(expanded.count, Set(expanded).count)
        XCTAssertEqual(Set(expanded), Set(result.records.map(\.outcomes)))
        XCTAssertGreaterThan(result.statistics.afterSum, 0)
        XCTAssertLessThanOrEqual(result.statistics.afterDisplacement, result.statistics.afterSum)
        XCTAssertLessThanOrEqual(result.statistics.afterVariance, result.statistics.afterDisplacement)
        XCTAssertLessThanOrEqual(result.statistics.afterValueTwo, result.statistics.afterVariance)
        XCTAssertLessThanOrEqual(result.statistics.afterTransition, result.statistics.afterValueTwo)
        XCTAssertEqual(result.statistics.afterProbabilitySelection, result.records.count)
        XCTAssertEqual(result.compressedRecords.flatMap(\.sourceRecords).count, result.records.count)
        XCTAssertEqual(Set(result.compressedRecords.flatMap(\.sourceRecords)).count, result.records.count)
        XCTAssertEqual(Set(result.records).intersection(result.removedRecords).count, 0)
        XCTAssertGreaterThanOrEqual(result.modelCoveragePercent, 95)
        XCTAssertFalse(result.usesCurrentMatchProbabilities)
        XCTAssertFalse(result.usesRelationshipCondition)
    }

    func testExpandedExportBetsUseFullBetDeduplication() throws {
        let config = try FilterConfig.parse(FilterConfig.currentInput)
        let result = SequenceFilterEngine.calculate(config, previousContext: previousContext)
        let rawExportedBets = result.exportCompressedRecords.flatMap {
            expandedOutcomes($0.options)
        }
        let uniqueExportedBets = Set(rawExportedBets)

        XCTAssertEqual(result.rawExpandedBetCount, rawExportedBets.count)
        XCTAssertEqual(result.finalBetCount, uniqueExportedBets.count)
        XCTAssertEqual(
            result.duplicateExpandedBetCount,
            rawExportedBets.count - uniqueExportedBets.count
        )
        XCTAssertEqual(Set(result.uniqueExpandedBets), uniqueExportedBets)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            $0.count == config.matchNumbers.count + config.extraMatches.count
        })
    }

    func testSumThirteenIsNoLongerProtected() throws {
        let config = try FilterConfig.parse("1,2,3,4|AABA|9-12|1-1|0|0|2|5:3|6:31|7:310|MERGE3")
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertFalse(result.records.contains { $0.compactOutcomes == "1111" })
        XCTAssertFalse(result.records.contains { $0.compactOutcomes == "0000" })
        XCTAssertFalse(
            SequenceFilterEngine.baseFilterFailureReasons(
                for: [1, 1, 1, 1],
                config: config
            ).isEmpty
        )
    }

    func testLegacyProductRangeFieldIsAcceptedButIgnored() throws {
        let config = try FilterConfig.parse("1,2,3,4|AABA|9-14|1-6|1.3|3|0.5|22-130|5:3|6:31|7:310|MERGE3")
        let allowedReasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: [1, 1, 1, 1],
            config: config
        )
        let rejectedReasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: [0, 0, 0, 0],
            config: config
        )
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertFalse(allowedReasons.contains { $0.contains("Q=") })
        XCTAssertFalse(rejectedReasons.contains { $0.contains("Q=") })
        XCTAssertTrue(result.records.contains { $0.compactOutcomes == "1111" })
    }

    func testAABAFinalSixConditionsKeepExpectedBetCountWithoutProductFilter() throws {
        let config = try FilterConfig.parse("1,2,3,4|AABA|10-13|1-6|1.3|3|0.5|6|5:3|6:31|7:310|MERGE3")
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(result.records.count, 53)
        XCTAssertEqual(result.finalBetCount, 318)
    }

    func testReportIncludesMatchNumberMappingAndTXTDetails() throws {
        let result = SequenceFilterEngine.calculate(.current, previousContext: previousContext)

        XCTAssertEqual(result.finalBetCount, result.records.count * 3 - 1)
        XCTAssertEqual(result.removedDisplayLines.count, result.removedRecords.count)
        XCTAssertTrue(result.filteredDisplayResultLines.allSatisfy { !$0.contains("6→") && !$0.contains("7→") })
        XCTAssertTrue(result.displayResultLines.contains { $0.contains("6→(10)") })
        XCTAssertTrue(result.displayResultLines.allSatisfy { $0.contains("7→3") })
        XCTAssertEqual(
            result.reportText.split(separator: "\n").count,
            result.displayResultLines.count + result.filterStageSummaries.count + 7
        )
        XCTAssertTrue(result.reportText.hasPrefix("最终：\(result.finalBetCount)注\n分析依据：上次 CCCB / 3101\n"))
        XCTAssertTrue(result.reportText.contains("上次是否命中：1"))
        XCTAssertTrue(result.reportText.contains("最终压缩：已关闭"))
        XCTAssertTrue(result.reportText.contains("乘积Q优先删除：过滤100注，剩余629注"))
        XCTAssertTrue(result.reportText.contains("最终彩果断点 B：过滤18注，剩余344注"))
        XCTAssertTrue(result.reportText.contains("1→"))
        XCTAssertTrue(result.reportText.contains("7→3"))
        for line in result.displayResultLines {
            let positions = (1...7).compactMap { line.range(of: "\($0)→")?.lowerBound }
            XCTAssertEqual(positions.count, 7)
            XCTAssertEqual(positions, positions.sorted())
        }
        XCTAssertTrue(result.reportText.contains("采用领域："))
        XCTAssertTrue(result.reportText.contains("稳定性 σ²：过滤0注，剩余482注"))
    }

    func testProductRemovalCountsExpandedBetsAndExportNeverRestoresRemovedBet() throws {
        for removal in [0, 1, 99, 100, 729, 999] {
            let config = try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "QDROP100", with: "QDROP\(removal)"))
            let all = expandedOutcomes(Array(repeating: [3, 1, 0], count: 5) + config.extraMatches.map(\.outcomes))
            var ranked: [(index: Int, outcomes: [Int], product: Int)] = []
            for (index, outcomes) in all.enumerated() {
                var product = 1
                for position in 0..<5 {
                    product *= config.logic[position].value(for: outcomes[position])
                }
                ranked.append((index: index, outcomes: outcomes, product: product))
            }
            ranked.sort { a, b in a.product == b.product ? a.index < b.index : a.product < b.product }
            let expectedAfterProduct = Set(ranked.dropFirst(removal).map(\.outcomes))
            for outcomes in all {
                let assessment = SequenceFilterEngine.productQFilterAssessment(
                    for: outcomes,
                    config: config
                )
                XCTAssertEqual(
                    assessment.passes,
                    expectedAfterProduct.contains(outcomes),
                    "Q阶段应按完整展开注精确判定：\(outcomes)"
                )
            }
            let expected = ranked.dropFirst(removal).filter {
                SequenceFilterEngine.baseFilterFailureReasons(for: Array($0.outcomes.prefix(5)), config: config).isEmpty
            }.map { $0.outcomes }
            let result = SequenceFilterEngine.calculate(config, previousContext: nil)
            let exported = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
            XCTAssertEqual(result.stageBetCounts[0] - result.stageBetCounts[1], min(removal, 729))
            XCTAssertEqual(Set(exported), Set(expected), "删除\(removal)注后精确覆盖")
            XCTAssertEqual(exported.count, Set(exported).count)
            XCTAssertEqual(result.finalBetCount, expected.count)
        }
    }

    func testNoFourPositionsAreOptionalAndRoundTrip() throws {
        XCTAssertTrue(FilterConfig.current.noFourPositions.isEmpty)
        let config = try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|NO4=1,3|6:310"))
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertFalse(result.records.isEmpty)
        XCTAssertTrue(result.records.allSatisfy { $0.values[0] != 4 && $0.values[2] != 4 })
        XCTAssertEqual(result.stageBetCounts.last, result.finalBetCount)
        XCTAssertThrowsError(try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|NO4=6|6:310")))
    }

    func testSVIP3SupportsTwoIndependentNoFourPositions() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-20|100|6|0|100|0-5|QDROP0|FINAL=OFF|CALCCOUNT=5|NO4SINGLE=1|NO4=2,4|7:3|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertEqual(config.activeNoFourPositions, [2, 4])
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertFalse(result.records.isEmpty)
        XCTAssertTrue(result.records.allSatisfy { record in
            record.values[1] != 4 && record.values[3] != 4
        })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("第2场判定值不是4") })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("第4场判定值不是4") })
    }

    func testSixMatchLegacyNoFourMigratesToFrontThreeMaximumOneFour() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-10|100|6|0|100|0-5|QDROP0|NO4=2|7:3|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertTrue(config.noFourPositions.isEmpty)
        XCTAssertEqual(config.frontThreeMaximumFourCount, 1)
        XCTAssertTrue(
            SequenceFilterEngine.baseFilterFailureReasons(
                for: [0, 3, 3, 3, 3, 3],
                config: config
            ).isEmpty
        )
        XCTAssertTrue(
            SequenceFilterEngine.baseFilterFailureReasons(
                for: [0, 0, 3, 3, 3, 3],
                config: config
            ).contains { $0.contains("前三场判定值4出现2次") }
        )
        XCTAssertEqual(
            SequenceFilterEngine.calculate(config, previousContext: nil).finalBetCount,
            540
        )
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
    }

    func testFrontThreeMaximumFourAndSpecifiedNoFourAreIndependent() throws {
        let input = "1,2,3,4,5,6|AAAAAA|0-24|0-10|100|6|0|100|0-5|QDROP0|MAX4F3=1|NO4=4|7:3|MERGE3"
        let config = try FilterConfig.parse(input)

        XCTAssertEqual(config.frontThreeMaximumFourCount, 1)
        XCTAssertEqual(config.noFourPositions, [4])
        XCTAssertTrue(
            SequenceFilterEngine.baseFilterFailureReasons(
                for: [3, 3, 3, 0, 3, 3],
                config: config
            ).contains { $0.contains("第4个主场判定值为4") }
        )
        XCTAssertTrue(
            SequenceFilterEngine.baseFilterFailureReasons(
                for: [0, 0, 3, 1, 3, 3],
                config: config
            ).contains { $0.contains("前三场判定值4出现2次") }
        )
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
    }

    func testSecondaryProbabilityFilterIsDisabledWithoutCurrentProbabilities() throws {
        let config = try FilterConfig.parse(FilterConfig.currentInput)
        let first = SequenceFilterEngine.calculate(config, previousContext: previousContext)
        let second = SequenceFilterEngine.calculate(config, previousContext: previousContext)
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.removedRecords, second.removedRecords)
        XCTAssertTrue(first.removedRecords.isEmpty)
        XCTAssertEqual(first.modelCoveragePercent, 100)
    }

    func testPreviousResultCanBeOmitted() throws {
        let result = SequenceFilterEngine.calculate(.current, previousContext: nil)

        XCTAssertEqual(result.analysisBasis, "未使用上次结果")
        XCTAssertEqual(result.previousHitFlag, 0)
        XCTAssertFalse(result.records.isEmpty)
        XCTAssertTrue(result.reportText.contains("上次是否命中：未使用"))
    }

    func testCurrentMatchProbabilitiesDoNotTriggerSecondaryFilter() throws {
        let probabilities = Array(repeating: [0.90, 0.07, 0.03], count: 5)
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )

        XCTAssertFalse(result.usesCurrentMatchProbabilities)
        XCTAssertEqual(result.modelCoveragePercent, 100)
        XCTAssertTrue(result.removedRecords.isEmpty)
        XCTAssertLessThan(result.records.count, 243)
    }

    func testDisabledRelationshipConditionDoesNotFilter() {
        let uniform = Array(repeating: [1.0 / 3, 1.0 / 3, 1.0 / 3], count: 5)
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: uniform,
            applyPoissonRelationshipCondition: false
        )

        XCTAssertFalse(result.usesCurrentMatchProbabilities)
        XCTAssertFalse(result.usesRelationshipCondition)
        XCTAssertTrue(result.removedRecords.isEmpty)
        XCTAssertEqual(result.modelCoveragePercent, 100)
    }

    func testNinetyFivePercentCoverageHasNoMinimumRemovalRate() throws {
        let probabilities = [
            [0.003, 0.403, 0.594],
            [0.847, 0.024, 0.129],
            [0.702, 0.046, 0.252],
            [0.608, 0.085, 0.307]
        ]
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )
        XCTAssertEqual(result.modelCoveragePercent, 100)
        XCTAssertEqual(result.actualFilteredPercent, 0)
    }

    func testUniformProbabilitiesKeepAtLeastNinetyFivePercentAfterMainFilters() throws {
        let uniform = Array(repeating: [1.0 / 3, 1.0 / 3, 1.0 / 3], count: 5)
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: uniform
        )
        XCTAssertTrue(result.removedRecords.isEmpty)
        XCTAssertEqual(result.modelCoveragePercent, 100)
        XCTAssertEqual(result.actualFilteredPercent, 0)
    }

    func testMainMetricsRemainHardFilters() throws {
        let drawHeavy = Array(repeating: [0.05, 0.90, 0.05], count: 5)
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: drawHeavy
        )

        XCTAssertFalse(result.records.contains { $0.outcomes == [1, 1, 1, 1, 1] })
        XCTAssertFalse(SequenceFilterEngine.baseFilterFailureReasons(
            for: [1, 1, 1, 1, 1],
            config: .current
        ).isEmpty)
    }

    func testEveryPairAndTripleRelationshipRemainsCovered() throws {
        let probabilities = [
            [0.82, 0.13, 0.05],
            [0.76, 0.18, 0.06],
            [0.71, 0.20, 0.09],
            [0.68, 0.22, 0.10]
        ]
        let result = SequenceFilterEngine.calculate(
            .current,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities
        )

        let candidates = result.records + result.removedRecords
        for positions in combinations(of: Array(0..<5), choose: 2) {
            let projections = Set(result.records.map { record in
                positions.map { record.outcomes[$0] }
            })
            let candidateProjections = Set(candidates.map { record in
                positions.map { record.outcomes[$0] }
            })
            XCTAssertEqual(projections, candidateProjections)
        }
        for positions in combinations(of: Array(0..<5), choose: 3) {
            let projections = Set(result.records.map { record in
                positions.map { record.outcomes[$0] }
            })
            let candidateProjections = Set(candidates.map { record in
                positions.map { record.outcomes[$0] }
            })
            XCTAssertEqual(projections, candidateProjections)
        }
    }

    func testPreviousResultAnalysisDoesNotProtectSumAboveThirteen() {
        let reasons = SequenceFilterEngine.baseFilterFailureReasons(
            for: [1, 1, 1, 1, 1],
            config: .current
        )

        XCTAssertFalse(reasons.isEmpty)
    }

    func testFullWidthCommaIsAccepted() throws {
        let config = try FilterConfig.parse("1，2，3，4|C,C,C,B|9-14|1-6|1.3|3|0.5|5:3|6:31|7:310|MERGE3")
        XCTAssertEqual(config.matchNumbers, ["1", "2", "3", "4"])
        XCTAssertEqual(config.logic, [.c, .c, .c, .b])
    }

    func testLogicCountMustMatchMatchCount() {
        XCTAssertThrowsError(try FilterConfig.parse("1,2,3,4|CCC|9-14|1-6|1.3|3|0.5|5:3|6:31|7:310|MERGE3"))
    }

    func testFiveHundredParserReadsBeijingSingleHandicapAndSP() throws {
        let html = """
        <table id="table_match"><tbody>
        <tr id="a1373607" status="0">
          <td><input type="checkbox" />12</td>
          <td><a>K2联赛</a></td><td>第25轮</td><td>09-08 18:30</td><td>未</td>
          <td><a>忠北清州</a><span class="sp_rq">(+1)</span></td>
          <td><div><span>-</span></div></td><td><a>首尔衣恋</a></td><td>-</td>
          <td class="bf_op"><span>2.92</span><span>2.82</span><span>3.28</span></td>
        </tr></tbody></table>
        <script>var liveOddsList = {"1373607":{"0":["2.10","3.20","3.50"],"rqsp":["2.92","2.82","3.28"]}};</script>
        """

        let matches = FiveHundredBeijingSingleClient.parse(html: html, issue: "26092")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].matchNumber, "12")
        XCTAssertEqual(matches[0].fixtureID, "1373607")
        XCTAssertEqual(matches[0].homeTeam, "忠北清州")
        XCTAssertEqual(matches[0].awayTeam, "首尔衣恋")
        XCTAssertEqual(matches[0].handicap, 1)
        XCTAssertEqual(matches[0].referenceSP, [2.92, 2.82, 3.28])
        XCTAssertEqual(matches[0].marketOdds, [2.10, 3.20, 3.50])
    }

    func testFiveHundredParserTreatsMissingHandicapBadgeAsZeroAndCalculatesResult() {
        let html = """
        <table id="table_match"><tbody>
        <tr id="a100" status="4">
          <td><input type="checkbox" />8</td><td><a>测试联赛</a></td><td>第1轮</td>
          <td>09-01 18:30</td><td><span>完</span></td><td><a>主队</a></td>
          <td><a>1</a><span>-</span><a>1</a></td><td><a>客队</a></td><td>0-0</td>
          <td><span>3.10</span></td>
        </tr></tbody></table>
        <script>var liveOddsList = {"100":{"rqsp":["2.10","3.20","3.50"]}};</script>
        """

        let match = FiveHundredBeijingSingleClient.parse(html: html, issue: "26091").first

        XCTAssertEqual(match?.handicap, 0)
        XCTAssertEqual(match?.homeScore, 1)
        XCTAssertEqual(match?.awayScore, 1)
        XCTAssertEqual(match?.handicapOutcome, 1)
        XCTAssertEqual(match?.settledSP, 3.10)
        XCTAssertEqual(match?.referenceSP, [2.10, 3.20, 3.50])
        XCTAssertEqual(match.flatMap(PrizeCalculator.handicapSP), 3.20)
        let blind = match?.resultBlindCopy
        XCTAssertNil(blind?.homeScore)
        XCTAssertNil(blind?.awayScore)
        XCTAssertNil(blind?.handicapOutcome)
        XCTAssertEqual(blind?.status, "已开赛·赛果已隔离")
    }

    func testFiveHundredTradePageParserReadsCurrentFormat() throws {
        let html = """
        <table id="vs_table"><tbody>
        <tr class="vs_lines" value="{index:'12',scheduleDate:'2026-09-08',rangqiuNum:'+1',disabled:'no'}" fid="1373607">
          <td><span class="chnum">12</span></td><td><a>K2联赛</a></td><td><span>18:30</span></td>
          <td><a>忠北清州</a></td><td><strong>+1</strong></td><td><a>首尔衣恋</a></td>
          <td><span class="pjoz">2.10</span><span class="pjoz">3.20</span><span class="pjoz">3.50</span></td>
          <td>--</td>
          <td><span class="sp_value">2.92</span></td><td><span class="sp_value">2.82</span></td><td><span class="sp_value">3.28</span></td>
        </tr></tbody></table>
        """
        let match = try XCTUnwrap(FiveHundredBeijingSingleClient.parse(html: html, issue: "26092").first)
        XCTAssertEqual(match.matchNumber, "12")
        XCTAssertEqual(match.fixtureID, "1373607")
        XCTAssertEqual(match.matchTime, "09-08 18:30")
        XCTAssertEqual(match.handicap, 1)
        XCTAssertEqual(match.referenceSP, [2.92, 2.82, 3.28])
        XCTAssertNil(match.settledSP)
        XCTAssertEqual(match.marketOdds, [2.10, 3.20, 3.50])
        XCTAssertEqual(match.status, "未")
    }

    func testFiveHundredTradePageParserReadsSettledWinningSP() throws {
        let html = """
        <table id="vs_table"><tbody>
        <tr class="vs_lines" value="{index:'1',scheduleDate:'2026-09-04',rangqiuNum:'+1',disabled:'yes'}" fid="1373607">
          <td><span class="chnum">1</span></td><td><a>K2联赛</a></td><td><span>18:20</span></td>
          <td><a>主队</a></td><td><strong>+1</strong></td><td><a>客队</a></td>
          <td><span class="pjoz">3.99</span><span class="pjoz">3.81</span><span class="pjoz">1.70</span></td>
          <td><a>0:2</a></td><td>--</td><td>--</td><td><span class="sp_value">3.45</span></td>
        </tr></tbody></table>
        """
        let match = try XCTUnwrap(FiveHundredBeijingSingleClient.parse(html: html, issue: "26092").first)
        XCTAssertEqual(match.handicapOutcome, 0)
        XCTAssertEqual(match.referenceSP, [3.45])
        XCTAssertEqual(match.settledSP, 3.45)
        XCTAssertEqual(match.status, "完")
    }

    func testPrizeCalculatorUsesActualOutcomeSPBeforeSettlement() throws {
        let matches = (1...6).map { number in
            BeijingSingleMatch(
                issue: "26092",
                matchNumber: String(number),
                fixtureID: "fixture-\(number)",
                league: "测试联赛",
                matchTime: "09-08 18:30",
                status: "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: 2,
                awayScore: 1
            )
        }

        XCTAssertFalse(PrizeCalculator.isFullySettled(matches))
        XCTAssertEqual(PrizeCalculator.selectedSP(for: matches[0]), 2.0)
        XCTAssertEqual(try XCTUnwrap(PrizeCalculator.amount(for: matches)), 83.2, accuracy: 0.000001)
    }

    func testPrizeCalculatorTreatsDelayedOverTwelveHourMatchOptionsAsOne() throws {
        let matches = (1...6).map { number in
            BeijingSingleMatch(
                issue: "26092",
                matchNumber: String(number),
                fixtureID: "fixture-\(number)",
                league: "测试联赛",
                matchTime: "09-08 18:30",
                status: number == 3 ? "延期13小时" : "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: 2,
                awayScore: 1
            )
        }

        XCTAssertEqual(matches[2].postponementHours, 13)
        XCTAssertTrue(matches[2].isPostponedOver12Hours)
        XCTAssertFalse(matches[1].isPostponedOver12Hours)
        XCTAssertEqual(
            try XCTUnwrap(PrizeCalculator.amount(for: matches, treatingMatchNumbersAsUnit: ["3"])),
            41.6,
            accuracy: 0.000001
        )
    }

    func testPrizeCalculatorUsesOfficialSPAfterSettlement() throws {
        let matches = (1...6).map { number in
            BeijingSingleMatch(
                issue: "26092",
                matchNumber: String(number),
                fixtureID: "fixture-\(number)",
                league: "测试联赛",
                matchTime: "09-08 18:30",
                status: "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [9.0],
                homeScore: 1,
                awayScore: 1,
                settledSP: Double(number)
            )
        }

        XCTAssertTrue(PrizeCalculator.isFullySettled(matches))
        XCTAssertEqual(try XCTUnwrap(PrizeCalculator.amount(for: matches)), 936.0, accuracy: 0.000001)
    }

    func testPrizeCalculatorSupportsSevenMatchesAndReplacesHighSPWithHandicapSP() throws {
        let matches = (1...7).map { number in
            BeijingSingleMatch(
                issue: "26092",
                matchNumber: String(number),
                fixtureID: "fixture-\(number)",
                league: "测试联赛",
                matchTime: "09-08 18:30",
                status: "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: 2,
                awayScore: 1,
                settledSP: number == 7 ? 6.2 : 2.0
            )
        }

        XCTAssertEqual(try XCTUnwrap(PrizeCalculator.amount(for: matches)), 515.84, accuracy: 0.000001)
        XCTAssertEqual(
            try XCTUnwrap(PrizeCalculator.amount(for: matches, replacingValuesAbove: 5)),
            166.4,
            accuracy: 0.000001
        )
        XCTAssertEqual(PrizeCalculator.handicapSP(for: matches[6]), 2.0)
    }

    func testPrizeCalculatorReportsLongestRunsInEnteredMatchOrder() throws {
        let outcomes = [3, 1, 3, 0, 1, 0, 0]
        let matches = outcomes.enumerated().map { index, outcome in
            let score = outcome == 3 ? (2, 1) : (outcome == 1 ? (1, 1) : (0, 1))
            return BeijingSingleMatch(
                issue: "26092",
                matchNumber: String(index + 1),
                fixtureID: "fixture-\(index + 1)",
                league: "测试联赛",
                matchTime: "09-08 18:30",
                status: "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: score.0,
                awayScore: score.1
            )
        }

        XCTAssertEqual(
            PrizeCalculator.runSummary(for: matches),
            PrizeRunSummary(
                nonLoss: 3, nonWin: 4, nonDraw: 2, win: 1, draw: 1, loss: 2,
                winCount: 2, drawCount: 2, lossCount: 3, diversity: 3,
                outcomeSum: 8, returns: 2, winLossSwitches: 1
            )
        )
    }

    func testPrizeCalculatorReturnsTwoSeventhOutcomeEstimates() throws {
        let firstSixOutcomes = [3, 1, 3, 0, 1, 0]
        let firstSix = firstSixOutcomes.enumerated().map { index, outcome in
            let score = outcome == 3 ? (2, 1) : (outcome == 1 ? (1, 1) : (0, 1))
            return BeijingSingleMatch(
                issue: "26095",
                matchNumber: String(index + 1),
                fixtureID: "fixture-\(index + 1)",
                league: "测试联赛",
                matchTime: "09-17 18:30",
                status: "完",
                homeTeam: "主队",
                awayTeam: "客队",
                handicap: 0,
                referenceSP: [2.0, 3.0, 4.0],
                homeScore: score.0,
                awayScore: score.1,
                settledSP: 2.0
            )
        }
        let seventh = BeijingSingleMatch(
            issue: "26095",
            matchNumber: "39",
            fixtureID: "fixture-39",
            league: "测试联赛",
            matchTime: "09-18 01:00",
            status: "未",
            homeTeam: "主队",
            awayTeam: "客队",
            handicap: -1,
            referenceSP: [2.0, 3.0, 4.0],
            marketOdds: [6.0, 3.0, 2.0]
        )

        let normal = try XCTUnwrap(
            PrizeCalculator.seventhOutcomeEstimates(
                firstSix: firstSix,
                seventh: seventh,
                useHandicapSP: false
            )
        )
        XCTAssertEqual(normal.map(\.outcome), [3, 0])
        XCTAssertEqual(normal[0].amount, 499.2, accuracy: 0.000001)
        XCTAssertEqual(normal[1].amount, 166.4, accuracy: 0.000001)
        let outcome3Summary = PrizeRunSummary(
            nonLoss: 3, nonWin: 3, nonDraw: 2, win: 1, draw: 1, loss: 1,
            winCount: 3, drawCount: 2, lossCount: 2, diversity: 3,
            outcomeSum: 11, returns: 2, winLossSwitches: 2
        )
        let outcome0Summary = PrizeRunSummary(
            nonLoss: 3, nonWin: 4, nonDraw: 2, win: 1, draw: 1, loss: 2,
            winCount: 2, drawCount: 2, lossCount: 3, diversity: 3,
            outcomeSum: 8, returns: 2, winLossSwitches: 1
        )
        XCTAssertEqual(normal[0].runSummary, outcome3Summary)
        XCTAssertEqual(normal[1].runSummary, outcome0Summary)

        let runSummaries = try XCTUnwrap(
            PrizeCalculator.seventhOutcomeRunSummaries(firstSixOutcomes: firstSixOutcomes)
        )
        XCTAssertEqual(runSummaries.map(\.outcome), [3, 0])
        XCTAssertEqual(runSummaries[0].runSummary, outcome3Summary)
        XCTAssertEqual(runSummaries[1].runSummary, outcome0Summary)
        XCTAssertEqual(
            PrizeCalculator.redLightConditionCount(for: runSummaries[0].runSummary),
            0
        )
        XCTAssertEqual(
            PrizeCalculator.redLightConditionCount(
                for: PrizeRunSummary(nonLoss: 5, nonWin: 4, nonDraw: 3)
            ),
            2
        )
        XCTAssertEqual(
            PrizeCalculator.redLightConditionCount(
                for: PrizeRunSummary(nonLoss: 4, nonWin: 4, nonDraw: 4)
            ),
            2
        )
        XCTAssertEqual(
            PrizeCalculator.redLightConditionCount(
                for: PrizeRunSummary(nonLoss: 4, nonWin: 3, nonDraw: 4)
            ),
            1
        )
        XCTAssertTrue(PrizeCalculator.shouldExplodeRed(for: [3, 3, 1, 0, 0, 3]))
        XCTAssertFalse(PrizeCalculator.shouldExplodeRed(for: [3, 3, 1, 1, 0, 0]))
        XCTAssertTrue(PrizeCalculator.hasConsecutiveDrawPair(in: [3, 1, 1, 0, 3, 0]))
        XCTAssertFalse(PrizeCalculator.hasConsecutiveDrawPair(in: [3, 1, 0, 1, 3, 0]))

        let handicap = try XCTUnwrap(
            PrizeCalculator.seventhOutcomeEstimates(
                firstSix: firstSix,
                seventh: seventh,
                useHandicapSP: true
            )
        )
        XCTAssertEqual(handicap[0].amount, 166.4, accuracy: 0.000001)
        XCTAssertEqual(handicap[1].amount, 332.8, accuracy: 0.000001)
    }

    func testGoalModelProducesNormalizedProbabilitiesAndScoreRanking() throws {
        let match = BeijingSingleMatch(
            issue: "26092",
            matchNumber: "12",
            fixtureID: "1373607",
            league: "测试联赛",
            matchTime: "09-08 18:30",
            status: "未",
            homeTeam: "主队",
            awayTeam: "客队",
            handicap: -1,
            referenceSP: [2.70, 3.20, 2.55]
        )

        let analysis = try PoissonGoalModel.analyze(match)

        XCTAssertEqual(analysis.handicapProbabilities.reduce(0, +), 1, accuracy: 0.000001)
        XCTAssertEqual(analysis.normalProbabilities.reduce(0, +), 1, accuracy: 0.000001)
        XCTAssertGreaterThan(analysis.homeExpectedGoals, 0)
        XCTAssertGreaterThan(analysis.awayExpectedGoals, 0)
        XCTAssertEqual(analysis.topScores.count, 3)
        XCTAssertTrue((0...100).contains(analysis.confidenceIndex))
        XCTAssertTrue(analysis.confidenceReason.contains("拟合误差"))
        XCTAssertGreaterThanOrEqual(analysis.topScores[0].probability, analysis.topScores[1].probability)
    }

    func testABCDRecommendationUsesOutcomeProbabilityRanks() {
        XCTAssertEqual(PoissonGoalModel.recommendedLogic(for: [0.55, 0.25, 0.20]).mapping, .a)
        XCTAssertEqual(PoissonGoalModel.recommendedLogic(for: [0.55, 0.15, 0.30]).mapping, .b)
        XCTAssertEqual(PoissonGoalModel.recommendedLogic(for: [0.30, 0.15, 0.55]).mapping, .c)
        XCTAssertEqual(PoissonGoalModel.recommendedLogic(for: [0.20, 0.25, 0.55]).mapping, .d)
        let drawFavourite = PoissonGoalModel.recommendedLogic(for: [0.30, 0.45, 0.25])
        XCTAssertEqual(drawFavourite.mapping, .a)
        XCTAssertFalse(drawFavourite.exact)
    }

    func testOddsConfidenceGateRequiresEconomicThresholdBeforeBetting() {
        func analysis(number: Int, probabilities: [Double]) -> GoalModelAnalysis {
            let match = BeijingSingleMatch(
                issue: "26102",
                matchNumber: String(number),
                fixtureID: "gate-\(number)",
                league: "测试",
                matchTime: "10-03 18:00",
                status: "未",
                homeTeam: "主",
                awayTeam: "客",
                handicap: 0,
                referenceSP: [9, 9, 9],
                marketOdds: [2.0, 3.0, 4.0]
            )
            return GoalModelAnalysis(
                match: match,
                homeExpectedGoals: 1.5,
                awayExpectedGoals: 1.0,
                handicapProbabilities: probabilities,
                normalProbabilities: probabilities,
                overTwoPointFiveProbability: 0.5,
                bothTeamsScoreProbability: 0.5,
                topScores: [],
                recommendedLogic: .a,
                exactLogicPattern: true,
                fitError: 0.0001
            )
        }

        let green = (1...5).map { number in
            analysis(number: number, probabilities: number == 3 ? [0.72, 0.18, 0.10] : [0.45, 0.30, 0.25])
        }
        let greenResult = OddsConfidenceGate.evaluate(analyses: green)
        XCTAssertEqual(greenResult?.decision, .bet)
        XCTAssertEqual(greenResult?.matchNumber, "3")
        XCTAssertEqual(greenResult?.outcome, 3)
        XCTAssertEqual(greenResult?.bettingThreshold ?? 0, 0.70, accuracy: 0.000001)
        XCTAssertEqual(
            greenResult?.breakEvenProbability ?? 0,
            (686.0 - 200.0) / (929.18 - 200.0),
            accuracy: 0.000001
        )

        let yellow = (1...5).map { number in
            analysis(number: number, probabilities: number == 2 ? [0.58, 0.24, 0.18] : [0.40, 0.33, 0.27])
        }
        XCTAssertEqual(OddsConfidenceGate.evaluate(analyses: yellow)?.decision, .observe)
    }

    func testOddsConfidenceGateRejectsStartedOrIncompleteSet() {
        let match = BeijingSingleMatch(
            issue: "26102", matchNumber: "1", fixtureID: "started", league: "测试",
            matchTime: "10-03 18:00", status: "完", homeTeam: "主", awayTeam: "客",
            handicap: 0, referenceSP: [], marketOdds: [2.0, 3.0, 4.0],
            homeScore: 1, awayScore: 0
        )
        let analysis = GoalModelAnalysis(
            match: match,
            homeExpectedGoals: 1.5,
            awayExpectedGoals: 1.0,
            handicapProbabilities: [0.70, 0.20, 0.10],
            normalProbabilities: [0.70, 0.20, 0.10],
            overTwoPointFiveProbability: 0.5,
            bothTeamsScoreProbability: 0.5,
            topScores: [],
            recommendedLogic: .a,
            exactLogicPattern: true,
            fitError: 0.0001
        )
        XCTAssertNil(OddsConfidenceGate.evaluate(analyses: Array(repeating: analysis, count: 5)))
    }

    func testTenOutcomeMetricsIncludeAbsentRunsAndOverlappingPatterns() {
        let outcomes = [3, 3, 1, 0, 3]
        let expected = [3, 1, 1, 2, 1, 1, 3, 10, 0, 1]
        XCTAssertEqual(OutcomeCondition.allCases.map { $0.value(in: outcomes) }, expected)
        XCTAssertEqual(OutcomeCondition.drawRun.value(in: [3, 3, 0]), 0)
        XCTAssertEqual(OutcomeCondition.lossRun.value(in: [0, 0, 0, 0, 0]), 5)
        XCTAssertEqual(OutcomeCondition.returns.value(in: [3, 1, 3, 1, 3]), 3)
        XCTAssertEqual(OutcomeCondition.winLossSwitches.value(in: [3, 0, 3, 0, 3]), 4)
        XCTAssertEqual(OutcomeCondition.returns.value(in: [3, 1]), 0)
    }

    func testConsecutiveRunConditionsUseAllSevenOutcomes() {
        let outcomes = [3, 1, 3, 0, 0, 1, 3]
        XCTAssertEqual(ConsecutiveRunCondition.nonLoss.longestRun(in: outcomes), 3)
        XCTAssertEqual(ConsecutiveRunCondition.nonDraw.longestRun(in: outcomes), 3)
        XCTAssertEqual(ConsecutiveRunCondition.nonWin.longestRun(in: outcomes), 3)
        XCTAssertEqual(ConsecutiveRunCondition.win.longestRun(in: outcomes), 1)
        XCTAssertEqual(ConsecutiveRunCondition.draw.longestRun(in: outcomes), 1)
        XCTAssertEqual(ConsecutiveRunCondition.loss.longestRun(in: outcomes), 2)

        var config = FilterConfig.current
        config.consecutiveRunsEnabled = true
        config.nonLossRunRange = 3...7
        config.nonDrawRunRange = 4...7
        config.nonWinRunRange = 4...7
        config.consecutiveRunToleranceRange = 1...1
        XCTAssertEqual(config.consecutiveRunFailureCount(in: outcomes), 2)
        XCTAssertFalse(config.passesConsecutiveRuns(outcomes))
        config.consecutiveRunToleranceRange = 1...2
        XCTAssertTrue(config.passesConsecutiveRuns(outcomes))

        config.secondaryConsecutiveRunsEnabled = true
        config.secondaryConsecutiveRunRange = 5...7
        config.secondaryConsecutiveRunToleranceRange = 0...0
        XCTAssertFalse(config.passesConsecutiveRuns(outcomes), "第二档应与第一档取交集")
        config.secondaryConsecutiveRunsEnabled = false
        XCTAssertTrue(config.passesConsecutiveRuns(outcomes))
    }

    func testConsecutiveRunConfigRoundTripsAndRejectsInvalidValues() throws {
        var config = FilterConfig.current
        config.consecutiveRunsEnabled = true
        config.nonLossRunRange = 3...5
        config.nonDrawRunRange = 4...6
        config.nonWinRunRange = 5...7
        config.consecutiveRunToleranceRange = 1...2
        config.secondaryConsecutiveRunsEnabled = true
        config.secondaryConsecutiveRunRange = 5...7
        config.secondaryConsecutiveRunToleranceRange = 2...3
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)

        for validTolerance in [0...0, 0...1, 0...2, 0...3, 1...3, 2...3, 3...3] {
            config.consecutiveRunToleranceRange = validTolerance
            XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        }
        for token in ["RUNS=2", "NLRUN=2-7", "NDRUN=3-8", "NWRUN=7-3", "RUNTOL=-1-3", "RUNTOL=1-4", "RUNTOL=3-1"] {
            let input = FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|\(token)|6:310")
            XCTAssertThrowsError(try FilterConfig.parse(input), token)
        }

        config.sameResultRunsEnabled = true
        config.winRunRange = 2...4
        config.drawRunRange = 3...5
        config.lossRunRange = 2...5
        config.sameResultRunToleranceRange = 2...3
        config.protectConsecutiveDrawPair = true
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        for validTolerance in [0...0, 0...1, 1...2, 1...3, 2...3, 3...3] {
            config.sameResultRunToleranceRange = validTolerance
            XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        }
        for token in ["SAMERUNS=2", "WINRUN=1-5", "DRAWRUN=2-8", "LOSSRUN=5-2", "SAMERUNTOL=0-4", "SAMERUNTOL=3-2", "PROTECT11=2"] {
            let input = FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|\(token)|6:310")
            XCTAssertThrowsError(try FilterConfig.parse(input), token)
        }
    }

    func testConsecutiveRunRangeAdvisorUsesSPAndAllThreeGeneralPresets() throws {
        let recommendation = try XCTUnwrap(
            ConsecutiveRunRangeAdvisor.recommend(
                spRows: Array(repeating: [3, 3, 3], count: 5),
                logic: [.a, .b, .c, .d, .a],
                seventhOutcome: 3
            )
        )

        XCTAssertEqual(recommendation.assessments.map(\.minimum), [3, 4, 5])
        XCTAssertEqual(recommendation.assessments.map(\.tolerance), [0...1, 0...2, 2...3])
        XCTAssertEqual(recommendation.assessments.map(\.theoreticalKeptCount), [585, 649, 688])
        XCTAssertEqual(recommendation.assessments[0].currentEstimatedCoverage, 585.0 / 729.0, accuracy: 0.000001)
        XCTAssertEqual(recommendation.assessments[1].currentEstimatedCoverage, 649.0 / 729.0, accuracy: 0.000001)
        XCTAssertEqual(recommendation.assessments[2].currentEstimatedCoverage, 688.0 / 729.0, accuracy: 0.000001)
        XCTAssertEqual(recommendation.recommendedMinimum, 3)
        XCTAssertNotNil(recommendation.marketEntropy)
        XCTAssertTrue(recommendation.source.contains("SP"))
    }

    func testConsecutiveRunRangeAdvisorFallsBackToABCDWithoutSP() throws {
        let recommendation = try XCTUnwrap(
            ConsecutiveRunRangeAdvisor.recommend(
                spRows: nil,
                logic: [.a, .b, .c, .d, .a],
                seventhOutcome: 0
            )
        )
        XCTAssertNil(recommendation.marketEntropy)
        XCTAssertTrue(recommendation.source.contains("ABCD"))
        XCTAssertEqual(recommendation.historicalSampleCount, 33)
    }

    func testSameResultRunFilterUsesAllSevenOutcomesAndTolerance() {
        let outcomes = [3, 3, 1, 1, 0, 0, 0]
        var config = FilterConfig.current
        config.sameResultRunsEnabled = true
        config.winRunRange = 2...5
        config.drawRunRange = 2...5
        config.lossRunRange = 2...5
        config.sameResultRunToleranceRange = 2...3

        XCTAssertEqual(config.sameResultRunFailureCount(in: outcomes), 0)
        XCTAssertFalse(config.passesSameResultRuns(outcomes))

        config.winRunRange = 3...5
        config.drawRunRange = 3...5
        XCTAssertEqual(config.sameResultRunFailureCount(in: outcomes), 2)
        XCTAssertTrue(config.passesSameResultRuns(outcomes))
    }

    func testSameResultRunFilterProtectsAdjacentDrawPair() {
        let outcomes = [3, 1, 1, 3, 0, 3, 0]
        var config = FilterConfig.current
        config.sameResultRunsEnabled = true
        config.winRunRange = 4...7
        config.drawRunRange = 4...7
        config.lossRunRange = 4...7
        config.sameResultRunToleranceRange = 0...0

        XCTAssertFalse(config.passesSameResultRuns(outcomes))
        config.protectConsecutiveDrawPair = true
        XCTAssertTrue(config.passesSameResultRuns(outcomes))
        XCTAssertFalse(config.passesSameResultRuns([3, 1, 3, 1, 0, 3, 0]))
    }

    func testSameResultRunFilterIncludesBothFixedMatchesAndExportsExactly() {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        let baseBets = base.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
        var config = FilterConfig.current
        config.sameResultRunsEnabled = true
        config.winRunRange = 2...5
        config.drawRunRange = 2...5
        config.lossRunRange = 2...5
        config.sameResultRunToleranceRange = 2...3

        let expected = baseBets.filter(config.passesSameResultRuns)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        let exported = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }

        XCTAssertEqual(Set(exported), Set(expected))
        XCTAssertEqual(result.finalBetCount, expected.count)
        XCTAssertTrue(exported.allSatisfy { $0.count == 7 })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
    }

    func testConsecutiveRunFilterIncludesBothFixedMatchesAndExportsExactly() {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        let baseBets = base.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
        var config = FilterConfig.current
        config.consecutiveRunsEnabled = true
        config.nonLossRunRange = 3...7
        config.nonDrawRunRange = 3...7
        config.nonWinRunRange = 3...7
        config.consecutiveRunToleranceRange = 1...1

        let expected = baseBets.filter(config.passesConsecutiveRuns)
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        let exported = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }

        XCTAssertEqual(Set(exported), Set(expected))
        XCTAssertEqual(result.finalBetCount, expected.count)
        XCTAssertLessThan(expected.count, baseBets.count)
        XCTAssertTrue(exported.allSatisfy { $0.count == 7 })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
    }

    func testOutcomeConditionParsingAndInvalidRanges() throws {
        var config = FilterConfig.current
        for condition in OutcomeCondition.activeCases {
            config.outcomeConditions[condition] = 0...condition.maximum(matchCount: 5)
        }
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        for token in ["OC_WRUN=4-2", "OC_WRUN=-1-2", "OC_WRUN=0-6", "OC_KINDS=0-4", "OC_RETURN=0-4", "OC_BAD=0-1", "OC_WINS=0-1|OC_WINS=0-2"] {
            XCTAssertThrowsError(try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|\(token)|6:310")))
        }
    }

    func testEveryOutcomeConditionMatchesIndependentFilteringAndExactExport() throws {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        for condition in OutcomeCondition.activeCases {
            for noFour in [[], [1]] {
                var config = FilterConfig.current
                config.noFourPositions = noFour
                let sampleValue = condition.value(in: try XCTUnwrap(base.records.first).outcomes)
                config.outcomeConditions[condition] = sampleValue...sampleValue
                let expected = base.records.filter {
                    condition.value(in: $0.outcomes) == sampleValue && (noFour.isEmpty || $0.values[0] != 4)
                }
                let result = SequenceFilterEngine.calculate(config, previousContext: nil)
                XCTAssertEqual(Set(result.records), Set(expected), condition.title)
                XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
                XCTAssertEqual(result.stageBetCounts.last, result.finalBetCount)
                let exported = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
                XCTAssertEqual(exported.count, Set(exported).count)
                XCTAssertEqual(Set(exported.map { Array($0.prefix(5)) }), Set(expected.map(\.outcomes)))
                XCTAssertTrue(result.records.allSatisfy { SequenceFilterEngine.baseFilterFailureReasons(for: $0.outcomes, config: config).isEmpty })
            }
        }
    }

    func testCombinedOutcomeConditionsCanProduceEmptyResult() {
        var config = FilterConfig.current
        config.outcomeConditions = [.draws: 5...5, .losses: 5...5]
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.finalBetCount, 0)
        XCTAssertEqual(result.stageBetCounts.last, 0)
        XCTAssertEqual(result.filterStageSummaries.count, 10)
    }

    func testOutcomeConditionToleranceKeepsRowsWithinAllowedFailureCount() throws {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        let sample = try XCTUnwrap(base.records.first)
        var config = FilterConfig.current
        let drawCount = OutcomeCondition.draws.value(in: sample.outcomes)
        let lossCount = OutcomeCondition.losses.value(in: sample.outcomes)
        config.outcomeConditions = [
            .draws: drawCount...drawCount,
            .losses: lossCount...lossCount,
            .diversity: 3...3
        ]
        config.outcomeConditionToleranceEnabled = true
        config.outcomeConditionToleranceRange = 0...1

        let expected = base.records.filter { config.passesOutcomeConditions($0.outcomes) }
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(Set(result.records), Set(expected))
        XCTAssertTrue(result.records.allSatisfy { config.outcomeConditionFailureCount(in: $0.outcomes) <= 1 })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("彩果条件组（容错0-1项）") })
    }

    func testAllConditionsToleranceRoundTripsAndZeroFailuresMatchesStrictFiltering() throws {
        let strict = SequenceFilterEngine.calculate(.current, previousContext: nil)
        var config = FilterConfig.current
        config.allConditionsToleranceEnabled = true
        config.allConditionsToleranceRange = 0...0

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        XCTAssertEqual(Set(result.records), Set(strict.records))
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("全部条件总容错0-0项") })
    }

    func testAllConditionsToleranceCanKeepRowsWithExactlyOneFailure() {
        let strict = SequenceFilterEngine.calculate(.current, previousContext: nil)
        var config = FilterConfig.current
        config.allConditionsToleranceEnabled = true
        config.allConditionsToleranceRange = 1...1

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)

        XCTAssertFalse(result.records.isEmpty)
        XCTAssertTrue(Set(result.records).isDisjoint(with: Set(strict.records)))
        XCTAssertEqual(result.stageBetCounts.last, result.finalBetCount)
    }

    func testGlobalToleranceCountsNestedOutcomeToleranceAsOneCondition() {
        var strictConfig = FilterConfig.current
        strictConfig.outcomeConditions = [
            .draws: 0...0,
            .losses: 0...0,
            .diversity: 1...1
        ]
        strictConfig.outcomeConditionToleranceEnabled = true
        strictConfig.outcomeConditionToleranceRange = 1...2
        let strict = SequenceFilterEngine.calculate(strictConfig, previousContext: nil)
        XCTAssertFalse(strict.records.isEmpty)

        var globalConfig = strictConfig
        globalConfig.allConditionsToleranceEnabled = true
        globalConfig.allConditionsToleranceRange = 0...0
        let global = SequenceFilterEngine.calculate(globalConfig, previousContext: nil)

        XCTAssertEqual(Set(global.records), Set(strict.records))
        XCTAssertTrue(global.records.allSatisfy {
            strictConfig.outcomeConditionToleranceRange.contains(
                strictConfig.outcomeConditionFailureCount(in: $0.outcomes)
            )
        })
    }

    func testGlobalToleranceCountsEachNestedRunGroupAsOneCondition() {
        var strictConfig = FilterConfig.current
        strictConfig.consecutiveRunsEnabled = true
        strictConfig.nonLossRunRange = 1...1
        strictConfig.nonDrawRunRange = 1...1
        strictConfig.nonWinRunRange = 1...1
        strictConfig.consecutiveRunToleranceRange = 1...3
        strictConfig.sameResultRunsEnabled = true
        strictConfig.winRunRange = 1...1
        strictConfig.drawRunRange = 1...1
        strictConfig.lossRunRange = 1...1
        strictConfig.sameResultRunToleranceRange = 1...3
        let strict = SequenceFilterEngine.calculate(strictConfig, previousContext: nil)
        XCTAssertFalse(strict.records.isEmpty)

        var globalConfig = strictConfig
        globalConfig.allConditionsToleranceEnabled = true
        globalConfig.allConditionsToleranceRange = 0...0
        let global = SequenceFilterEngine.calculate(globalConfig, previousContext: nil)

        XCTAssertEqual(global.finalBetCount, strict.finalBetCount)
        XCTAssertEqual(
            Set(global.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }),
            Set(strict.exportCompressedRecords.flatMap { expandedOutcomes($0.options) })
        )
    }

    func testOkoooParserChecksIssueAndReadsHandicapResultWithoutResultSP() throws {
        let html = """
        <select id="SelectLotteryNo"><option value="26093" selected="true">26093</option></select>
        <tr name="Match_2" id="Match_2">
        <td>2</td><td>联赛</td><td>18:30</td>
        <td><span id="MatchOrder2_HomeName">主队</span>(<span id="MatchOrder2_HandicapNumber">-1</span>)</td>
        <td><span id="MatchOrder2_AwayName">客队</span></td>
        <td>1.99</td><td>3.19</td><td>3.78</td><td>欧/析</td><td>2:1</td><td>1</td><td>999.9</td>
        </tr>
        """
        let match = try XCTUnwrap(OkoooBeijingSingleClient.parse(html: html, issue: "26093").first)
        XCTAssertEqual(match.matchNumber, "2")
        XCTAssertEqual(match.handicap, -1)
        XCTAssertEqual(match.marketOdds, [1.99, 3.19, 3.78])
        XCTAssertTrue(match.referenceSP.isEmpty)
        XCTAssertEqual(match.homeScore, 2)
        XCTAssertEqual(match.awayScore, 1)
        XCTAssertEqual(match.handicapOutcome, 1)
        XCTAssertTrue(OkoooBeijingSingleClient.parse(html: html, issue: "26092").isEmpty)
        let missing = html.replacingOccurrences(of: "<span id=\"MatchOrder2_HandicapNumber\">-1</span>", with: "")
        XCTAssertTrue(OkoooBeijingSingleClient.parse(html: missing, issue: "26093").isEmpty)
        let zero = html.replacingOccurrences(of: ">-1</span>", with: "></span>")
        XCTAssertEqual(OkoooBeijingSingleClient.parse(html: zero, issue: "26093").first?.handicap, 0)
    }

    func testABCDSourceFallbackAndRequestOrdering() async throws {
        var visited: [ABCDDataSource] = []
        let result = try await MultiSourceABCDClient.fetch(issue: "26093", matchNumbers: ["2", "1"], source: .automatic) { source, issue, numbers in
            visited.append(source)
            if source == .fiveHundred { throw GoalModelError.dataSourceUnavailable }
            return numbers.map { number in
                BeijingSingleMatch(issue: issue, matchNumber: number, fixtureID: number, league: "测试", matchTime: "12:00", status: "未", homeTeam: "主", awayTeam: "客", handicap: 0, referenceSP: [], marketOdds: [2.0, 3.5, 4.0])
            }
        }
        XCTAssertEqual(visited, [.fiveHundred, .okooo])
        XCTAssertEqual(result.source, "澳客")
        XCTAssertEqual(result.analyses.map { $0.match.matchNumber }, ["2", "1"])
    }

    func testABCDAllSourcesFailAndExplicitSourceDoesNotSwitch() async {
        for source in [ABCDDataSource.automatic, .okooo] {
            var visited: [ABCDDataSource] = []
            do {
                _ = try await MultiSourceABCDClient.fetch(issue: "26093", matchNumbers: ["1"], source: source) { provider, _, _ in
                    visited.append(provider)
                    throw GoalModelError.dataSourceUnavailable
                }
                XCTFail("失败时不能生成默认ABCD")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("澳客"))
            }
            XCTAssertEqual(visited, source == .automatic ? [.fiveHundred, .okooo] : [.okooo])
        }
    }

    func testUTF8OkoooPageDecodesWithoutFiveHundredMarkers() throws {
        let html = "<html><select id=\"SelectLotteryNo\">澳客第26093期</select></html>"
        XCTAssertEqual(FiveHundredBeijingSingleClient.decodeHTML(Data(html.utf8)), html)
    }

    func testFiveHundredSelectionRejectsMissingMatchAndIncompleteOdds() throws {
        let html = """
        <table id="vs_table"><tr class="vs_lines" value="{index:'1',scheduleDate:'2026-09-10',rangqiuNum:'0'}" fid="100">
        <td><span class="chnum">1</span></td><td>测试</td><td>12:00</td><td>主队</td><td>0</td><td>客队</td>
        <td><span class="pjoz">2.10</span><span class="pjoz">3.20</span><span class="pjoz">3.50</span></td>
        <td>--</td><td>--</td><td>--</td><td>--</td></tr></table>
        """
        XCTAssertEqual(try FiveHundredBeijingSingleClient.selectMatches(html: html, issue: "26093", matchNumbers: ["1"]).count, 1)
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.selectMatches(html: html, issue: "26093", matchNumbers: ["1", "2"]))
        let incomplete = html.replacingOccurrences(of: "<span class=\"pjoz\">3.50</span>", with: "")
        XCTAssertThrowsError(try FiveHundredBeijingSingleClient.selectMatches(html: incomplete, issue: "26093", matchNumbers: ["1"]))
    }

    func testCompactDateIsNotMistakenForIssueNumber() {
        for input in ["260910", "20260910", "2026-09-10", "09-10"] {
            XCTAssertEqual(FiveHundredBeijingSingleClient.dateInput(input)?.monthDay, "09-10")
        }
        XCTAssertEqual(FiveHundredBeijingSingleClient.dateInput("260910")?.yearPrefix, "26")
        for invalid in ["26093", "261332", "20260230", "20xx-09-10"] {
            XCTAssertNil(FiveHundredBeijingSingleClient.dateInput(invalid))
        }
        let html = "<select id=\"expect_select\"><option value=\"26093\">当前期</option><option value=\"26092\">上期</option></select>"
        XCTAssertEqual(FiveHundredBeijingSingleClient.publishedIssues(html: html), ["26093", "26092"])
    }

    func testSavedDefaultsMigrateConditionsWithoutMatchNumbersOrOldABCD() throws {
        let config = try FilterConfig.parse("38,39,40,42,43|BBCDA|12-18|3-8|0.96|4|0.054|9|2-6|QDROP50|OC_WINS=0-3|OC_KINDS=2-3|OC_OSUM=1-15|NO4=2|6:310|7:3|MERGE3")
        let values = FilterInputDefaults.values(from: config)
        XCTAssertEqual(values["sumInput"], "12-18")
        XCTAssertEqual(values["productRemovalCountInput"], "50")
        XCTAssertEqual(values["noFourPositionsInput"], "2")
        XCTAssertNil(values["OC_WINS"])
        XCTAssertEqual(values["OC_KINDS"], "2-3")
        XCTAssertEqual(values["OC_OSUM"], "1-15")
        XCTAssertEqual(values["OC_WRUN"], "")
        XCTAssertEqual(values["singleOutcomeInput"], "3")
        for key in ["match1Input", "match5Input", "fixedFullMatchInput", "singleMatchInput", "logicInput"] {
            XCTAssertNil(values[key])
        }
        XCTAssertFalse(config.enabledOutcomeConditions.contains(.wins))
        XCTAssertFalse(config.normalizedInput.contains("OC_WINS"))
    }

    func testFinalReductionRoundTripAndSeedValidation() throws {
        var config = FilterConfig.current
        config.finalReduction = .random
        config.randomSeed = UInt64.max
        config.marketWeightPercent = 20
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
        for token in ["FINAL=BAD", "SEED=-1", "SEED=18446744073709551616", "MKTW=31", "FINAL=OFF|FINAL=QHALF"] {
            XCTAssertThrowsError(try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|\(token)|6:310")))
        }
    }

    func testHalvingKeepsActualBetsAndNeverRestoresRemovedOutcomes() {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        let original = base.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
        for mode in [FinalReductionMode.product, .probability, .random] {
            var config = FilterConfig.current
            config.finalReduction = mode
            config.randomSeed = 42
            let expected = SequenceFilterEngine.reduceFinalBets(original, config: config)
            let result = SequenceFilterEngine.calculate(config, previousContext: nil)
            let actual = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
            XCTAssertEqual(actual.count, (original.count + 1) / 2)
            XCTAssertEqual(actual.count, Set(actual).count)
            XCTAssertEqual(Set(actual), Set(expected))
            XCTAssertTrue(Set(actual).isSubset(of: Set(original)))
            XCTAssertEqual(result.stageBetCounts.last, actual.count)
            XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
            XCTAssertEqual(Set(result.records.map(\.outcomes)), Set(actual.map { Array($0.prefix(5)) }))
        }
    }

    func testHalvingOddEmptyAndSingleBets() {
        var config = FilterConfig.current
        config.finalReduction = .probability
        let bets = [[3,3,3,3,3], [1,3,3,3,3], [0,3,3,3,3]]
        XCTAssertEqual(SequenceFilterEngine.reduceFinalBets(bets, config: config).count, 2)
        XCTAssertEqual(SequenceFilterEngine.reduceFinalBets([], config: config), [])
        XCTAssertEqual(SequenceFilterEngine.reduceFinalBets([bets[0]], config: config), [bets[0]])
    }

    func testModelProbabilitiesDriveRankingInsteadOfUniformRandom() {
        var config = FilterConfig.current
        config.finalReduction = .probability
        let bets = [[3,3,3,3,3], [1,3,3,3,3], [0,3,3,3,3]]
        let scores = [[0.1, 0.3, 0.6]] + Array(repeating: [0.3, 0.3, 0.4], count: 4)
        let selected = SequenceFilterEngine.reduceFinalBets(bets, config: config, scores: scores)
        XCTAssertEqual(selected, [bets[1], bets[0]])
        config.finalReduction = .random
        config.randomSeed = 2026
        let first = SequenceFilterEngine.reduceFinalBets(bets, config: config, scores: scores)
        XCTAssertEqual(first, SequenceFilterEngine.reduceFinalBets(Array(bets.reversed()), config: config, scores: scores))
        // Across deterministic seeds, high scores should be selected more often.
        var counts = [0, 0, 0]
        for seed in 0..<300 {
            config.randomSeed = UInt64(seed)
            let kept = SequenceFilterEngine.reduceFinalBets(bets, config: config, scores: scores)
            for index in bets.indices where kept.contains(bets[index]) { counts[index] += 1 }
        }
        XCTAssertGreaterThan(counts[2], counts[0])
    }

    func testMissingMarketDataIsNotFabricatedAndValidSharesBlend() {
        var config = FilterConfig.current
        config.marketWeightPercent = 20
        let model = Array(repeating: [0.6, 0.3, 0.1], count: 5)
        let without = SequenceFilterEngine.finalScoring(config: config, probabilities: model, marketShares: [])
        XCTAssertEqual(without.rows[0][0], 0.6, accuracy: 1e-12)
        XCTAssertTrue(without.basis.contains("投注占比未参与"))
        let withMarket = SequenceFilterEngine.finalScoring(config: config, probabilities: model, marketShares: [[0.1, 0.2, 0.7]])
        XCTAssertEqual(withMarket.rows[0][0], 0.5, accuracy: 1e-12)
        XCTAssertEqual(withMarket.rows[1][0], 0.6, accuracy: 1e-12)
        XCTAssertTrue(withMarket.basis.contains("1场有效投注占比"))
        XCTAssertTrue(SequenceFilterEngine.finalScoring(config: config, probabilities: nil, marketShares: []).basis.contains("ABCD映射估计"))
        XCTAssertEqual(FiveHundredBeijingSingleClient.publishedBettingShares(in: "<span class='tzbl'>--</span><span class='tzbl'>--</span><span class='tzbl'>--</span>"), [])
        XCTAssertEqual(FiveHundredBeijingSingleClient.publishedBettingShares(in: "<span class='tzbl'>50%</span><span class='tzbl'>30%</span><span class='tzbl'>20%</span>"), [0.5, 0.3, 0.2])
    }

    func testScoreReductionRatesAndRounding() throws {
        let bets = expandedOutcomes(Array(repeating: [3, 1, 0], count: 5))
        for (percent, expected) in [(50, 51), (30, 71), (20, 81)] {
            var config = FilterConfig.current
            config.finalReduction = .probability
            config.finalRemovalPercent = percent
            XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)
            XCTAssertEqual(SequenceFilterEngine.reduceFinalBets(Array(bets.prefix(101)), config: config).count, expected)
            XCTAssertEqual(SequenceFilterEngine.reduceFinalBets([], config: config).count, 0)
            XCTAssertEqual(SequenceFilterEngine.reduceFinalBets([bets[0]], config: config).count, 1)
        }
        for token in ["RATE=0", "RATE=40", "RATE=-20", "RATE=30|RATE=20"] {
            XCTAssertThrowsError(try FilterConfig.parse(FilterConfig.currentInput.replacingOccurrences(of: "|6:310", with: "|\(token)|6:310")))
        }
    }

    func testTwentyAndThirtyPercentExportsDeleteHighestScoredSelection() {
        let base = SequenceFilterEngine.calculate(.current, previousContext: nil)
        let original = base.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
        for percent in [20, 30] {
            var config = FilterConfig.current
            config.finalReduction = .probability
            config.finalRemovalPercent = percent
            let expected = SequenceFilterEngine.reduceFinalBets(original, config: config)
            let result = SequenceFilterEngine.calculate(config, previousContext: nil)
            let actual = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
            XCTAssertEqual(Set(actual), Set(expected))
            XCTAssertEqual(actual.count, original.count - original.count * percent / 100)
            XCTAssertEqual(actual.count, Set(actual).count)
            XCTAssertEqual(result.stageBetCounts.last, actual.count)
            XCTAssertTrue(result.reportText.contains("减\(percent)%"))
        }
    }

    func testMissedOutcomeAnalysisIdentifiesBaseQAndFinalStages() throws {
        let accepted = try XCTUnwrap(
            SequenceFilterEngine.calculate(.current, previousContext: nil).records.first
        ).outcomes

        var retainedConfig = FilterConfig.current
        retainedConfig.finalReduction = .probability
        retainedConfig.finalRemovalPercent = 30
        let retainedText = accepted.map(String.init).joined()
        XCTAssertTrue(
            SequenceFilterEngine.missedOutcomeAnalysis(
                outcomes: accepted,
                config: retainedConfig,
                savedKeptOutcomes: [retainedText]
            ).contains("位于当时保留范围内")
        )
        XCTAssertTrue(
            SequenceFilterEngine.missedOutcomeAnalysis(
                outcomes: accepted,
                config: retainedConfig,
                savedKeptOutcomes: []
            ).contains("可能在后续条件")
        )

        var missingSPConfig = FilterConfig.current
        missingSPConfig.spProductFilterEnabled = true
        missingSPConfig.spProductRange = 30...900
        let savedResultWinsOverIncompleteReplay = SequenceFilterEngine.missedOutcomeAnalysis(
            outcomes: accepted,
            config: missingSPConfig,
            savedKeptOutcomes: [retainedText]
        )
        XCTAssertTrue(savedResultWinsOverIncompleteReplay.contains("位于当时保留范围内"))
        XCTAssertFalse(savedResultWinsOverIncompleteReplay.contains("乘积Q优先删除阶段被删除"))

        let allProductRemoved = try FilterConfig.parse(
            FilterConfig.currentInput.replacingOccurrences(of: "QDROP100", with: "QDROP729")
        )
        XCTAssertTrue(
            SequenceFilterEngine.missedOutcomeAnalysis(
                outcomes: accepted,
                config: allProductRemoved,
                savedKeptOutcomes: []
            ).contains("乘积Q")
        )

        var baseFailure = FilterConfig.current
        baseFailure.noFourPositions = [1]
        let valueFourOutcome = [1, 3, 3, 3, 3]
        let baseFailureAnalysis = SequenceFilterEngine.missedOutcomeAnalysis(
            outcomes: valueFourOutcome,
            config: baseFailure
        )
        XCTAssertTrue(baseFailureAnalysis.contains("基础条件未通过"))
        XCTAssertTrue(baseFailureAnalysis.contains("第1个主场判定值为4"))
    }

    func testSevenFieldRowsMergeRecursivelyWhenSixPositionsMatch() {
        let outcomes = [3, 1, 0].flatMap { first in
            [3, 1].map { second in [first, second, 3, 3, 3, 3, 3] }
        }
        let merged = SequenceFilterEngine.recursivelyMergedOptionRows(outcomes)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0][0], [3, 1, 0])
        XCTAssertEqual(merged[0][1], [3, 1])
        XCTAssertEqual(Set(expandedOutcomes(merged[0])), Set(outcomes))

        let twoDifferences = [[3, 3, 3, 3, 3, 3, 3], [1, 1, 3, 3, 3, 3, 3]]
        XCTAssertEqual(
            SequenceFilterEngine.recursivelyMergedOptionRows(twoDifferences).count,
            2
        )
    }

    func testSevenFieldRowsKeepMergingUntilNoSixPositionMatchRemains() {
        let outcomes = [3, 1, 0].flatMap { first in
            [3, 1].flatMap { second in
                [3, 1, 0].map { third in
                    [first, second, third, 3, 3, 3, 3]
                }
            }
        }
        let merged = SequenceFilterEngine.recursivelyMergedOptionRows(outcomes)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0][0], [3, 1, 0])
        XCTAssertEqual(merged[0][1], [3, 1])
        XCTAssertEqual(merged[0][2], [3, 1, 0])
        XCTAssertEqual(Set(expandedOutcomes(merged[0])), Set(outcomes))
    }

    func testSevenFieldRecursiveMergeReachesFixedPointWithoutChangingBets() {
        let values = [3, 1, 0]
        let outcomes = values.flatMap { first in
            values.flatMap { second in
                values.flatMap { third in
                    values.compactMap { fourth -> [Int]? in
                        let line = [first, second, third, fourth, 3, 1, 0]
                        return (first + 2 * second + 3 * third + fourth) % 5 == 0 ? nil : line
                    }
                }
            }
        }
        let merged = SequenceFilterEngine.recursivelyMergedOptionRows(outcomes)
        let expanded = merged.flatMap(expandedOutcomes)
        XCTAssertEqual(expanded.count, outcomes.count)
        XCTAssertEqual(Set(expanded), Set(outcomes))
        for left in merged.indices {
            for right in merged.indices where right > left {
                let identicalPositions = zip(merged[left], merged[right]).filter { $0.0 == $0.1 }.count
                XCTAssertLessThan(identicalPositions, 6, "仍存在可继续合并的两行")
            }
        }
    }

    func testSharedTXTContainsOnlyFinalCountAndBetRows() {
        let result = SequenceFilterEngine.calculate(.current, previousContext: previousContext)
        let lines = result.shareText.split(separator: "\n")

        XCTAssertEqual(lines.count, result.displayResultLines.count + 1)
        XCTAssertEqual(lines.first, "最终：\(result.finalBetCount)注")
        XCTAssertFalse(result.shareText.contains("分析依据"))
        XCTAssertFalse(result.shareText.contains("筛选"))
        XCTAssertFalse(result.shareText.contains("评分"))
        XCTAssertFalse(result.shareText.contains("乘积Q"))
    }

    func testAdvancedSPProbabilityAndGroupFiltersSelectExpectedFiveMatchRow() throws {
        var config = try FilterConfig.parse(FilterConfig.currentInput)
        config.spProductFilterEnabled = true
        config.spProductRange = 32...32
        config.prizeRangeFilterEnabled = true
        config.estimatedPrizeRange = 41.59...41.61
        config.spRiskFilterEnabled = true
        config.maximumSingleSP = 2.1
        config.highSPThreshold = 4
        config.highSPCountRange = 0...0
        config.minimumProbabilityFilterEnabled = true
        config.minimumSingleProbabilityPercent = 70
        config.jointProbabilityFilterEnabled = true
        config.jointProbabilityPercentRange = 32.7...32.8
        config.groupFilterEnabled = true
        config.groupFilterMode = .both
        config.frontGroupOutcomeSumRange = 7...7
        config.backGroupOutcomeSumRange = 6...6
        config.frontGroupSPProductRange = 8...8
        config.backGroupSPProductRange = 4...4

        let target = [3, 1, 3, 3, 3]
        let probabilities = target.map { outcome in
            outcome == 3 ? [0.8, 0.1, 0.1] : [0.1, 0.8, 0.1]
        }
        let spRows = target.map { outcome in
            outcome == 3 ? [2.0, 6.0, 6.0] : [6.0, 2.0, 6.0]
        }
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            currentOutcomeProbabilities: probabilities,
            currentOutcomeSPs: spRows
        )

        XCTAssertEqual(result.records.map(\.outcomes), [target])
        XCTAssertEqual(result.finalBetCount, 3)
        XCTAssertEqual(result.filterStageSummaries.filter { $0.contains("SP") || $0.contains("概率") || $0.contains("奖金") || $0.contains("分组") }.count, 6)
        XCTAssertTrue(zip(result.stageBetCounts, result.stageBetCounts.dropFirst()).allSatisfy { $0 >= $1 })
    }

    func testAdvancedFilterConfigurationRoundTrips() throws {
        var config = try FilterConfig.parse(FilterConfig.currentInput)
        config.spProductFilterEnabled = true
        config.spProductRange = 12.5...88.8
        config.prizeRangeFilterEnabled = true
        config.estimatedPrizeRange = 20...120
        config.spRiskFilterEnabled = true
        config.maximumSingleSP = 4.8
        config.highSPThreshold = 3.6
        config.highSPCountRange = 1...2
        config.minimumProbabilityFilterEnabled = true
        config.minimumSingleProbabilityPercent = 18.5
        config.jointProbabilityFilterEnabled = true
        config.jointProbabilityPercentRange = 0.2...9.9
        config.groupFilterEnabled = true
        config.groupFilterMode = .spProduct
        config.frontGroupSPProductRange = 2...22
        config.backGroupSPProductRange = 1.5...12

        let reparsed = try FilterConfig.parse(config.normalizedInput)

        XCTAssertEqual(reparsed, config)
        XCTAssertTrue(reparsed.requiresSPData)
        XCTAssertTrue(reparsed.requiresProbabilityData)
    }

    func testSharedTXTImportParsesIssueCompressedOptionsAndBets() throws {
        let text = """
        期号：26092
        第一场（场次1）开始时间：19:30
        最终：3注
        01. 1→(31)，2→0，6→3
        02. 1→0，2→1，6→3
        """

        let imported = try SharedTXTImportParser.parse(text)

        XCTAssertEqual(imported.issue, "26092")
        XCTAssertEqual(imported.matchNumbers, ["1", "2", "6"])
        XCTAssertEqual(imported.declaredBetCount, 3)
        XCTAssertEqual(Set(imported.betOutcomes), Set([[3, 0, 3], [1, 0, 3], [0, 1, 3]]))
    }

    func testSharedTXTImportSupportsOldFileWithoutIssue() throws {
        let text = """
        最终：2注
        01. 3→3，8→(10)
        """

        let imported = try SharedTXTImportParser.parse(text)

        XCTAssertNil(imported.issue)
        XCTAssertEqual(imported.matchNumbers, ["3", "8"])
        XCTAssertEqual(imported.betOutcomes, [[3, 1], [3, 0]])
    }

    func testSharedTXTImportRejectsTruncatedBetFile() {
        let text = """
        期号：26092
        最终：3注
        01. 1→3，2→0
        """

        XCTAssertThrowsError(try SharedTXTImportParser.parse(text)) { error in
            XCTAssertEqual(error as? SharedTXTImportError, .betCountMismatch(declared: 3, parsed: 1))
        }
    }

    func testTXTQueryStatisticsDeduplicatesMatchNumberOrderAndLeadingZeros() {
        XCTAssertEqual(
            TXTQueryStatisticsCalculator.uniqueKey(issue: " 26092 ", matchNumbers: ["06", "2", "1"]),
            TXTQueryStatisticsCalculator.uniqueKey(issue: "26092", matchNumbers: ["1", "6", "02"])
        )
        XCTAssertEqual(
            TXTQueryStatisticsCalculator.ticketKey(
                issue: "26098",
                matchNumbers: ["75", "76", "77", "78", "79", "80", "146"]
            ),
            TXTQueryStatisticsCalculator.ticketKey(
                issue: " 26098 ",
                matchNumbers: ["080", "79", "78", "77", "76", "075", "999"]
            )
        )
    }

    func testTXTQueryStatisticsUsesExactlySevenOutcomesAndRequiresTwoRunsAtLeastTwo() {
        XCTAssertTrue(TXTQueryStatisticsCalculator.hasTwoSameResultRunsAtLeastTwo(
            sevenOutcomes: [3, 3, 3, 1, 1, 1, 0]
        ))
        XCTAssertTrue(TXTQueryStatisticsCalculator.hasTwoSameResultRunsAtLeastTwo(
            sevenOutcomes: [0, 0, 0, 3, 3, 3, 1]
        ))
        XCTAssertTrue(TXTQueryStatisticsCalculator.hasTwoSameResultRunsAtLeastTwo(
            sevenOutcomes: [3, 3, 3, 1, 1, 0, 0]
        ))
        XCTAssertFalse(TXTQueryStatisticsCalculator.hasTwoSameResultRunsAtLeastTwo(
            sevenOutcomes: [3, 3, 3, 1, 1, 1]
        ))
    }

    func testRemovingNoFourPositionCannotReduceBetCount() throws {
        let common = "1,2,3,4,5|CBCBB|12-18|2-7|1|3|0.14|11|1-6|QDROP40|FINAL=OFF|RUNS=1|NLRUN=5-7|NDRUN=5-7|NWRUN=4-7|RUNTOL=2-3|SAMERUNS=1|WINRUN=2-7|DRAWRUN=2-7|LOSSRUN=2-7|SAMERUNTOL=2-3|PROTECT11=1|"
        let uncapped = try FilterConfig.parse(common + "PRIZECOUNTON=0|NO4=|6:310|7:3|MERGE3")
        let uncappedResult = SequenceFilterEngine.calculate(uncapped, previousContext: nil)
        let protectedPrefixes = Set(
            uncappedResult.exportCompressedRecords
                .flatMap { expandedOutcomes($0.options) }
                .prefix(8)
                .map { Array($0.prefix(5)) }
        )
        let unrestricted = try FilterConfig.parse(common + "PRIZECOUNTON=1|NO4=|6:310|7:3|MERGE3")
        let restricted = try FilterConfig.parse(common + "PRIZECOUNTON=1|NO4=3|6:310|7:3|MERGE3")
        let unrestrictedResult = SequenceFilterEngine.calculate(
            unrestricted,
            previousContext: nil,
            protectedPrizeOutcomePrefixes: protectedPrefixes
        )
        let restrictedResult = SequenceFilterEngine.calculate(
            restricted,
            previousContext: nil,
            protectedPrizeOutcomePrefixes: protectedPrefixes
        )

        XCTAssertGreaterThanOrEqual(unrestrictedResult.finalBetCount, restrictedResult.finalBetCount)
        XCTAssertEqual(unrestrictedResult.finalBetCount, uncappedResult.finalBetCount)
    }

    func testLegacyHistoricalPairingTokenNoLongerChangesUniversalResult() throws {
        let input = "40,41,42,43,44|DBCDC|12-18|2-7|1|3|0.14|11|1-6|QDROP40|FINAL=OFF|SEED=1|MKTW=0|RATE=20|OC_WLSWITCH=0-2|OCTOLON=0|OCTOL=0-1|ALLTOLON=0|ALLTOL=0-1|RUNS=1|NLRUN=5-7|NDRUN=5-7|NWRUN=4-7|RUNTOL=2-3|SAMERUNS=1|WINRUN=2-7|DRAWRUN=2-7|LOSSRUN=2-7|SAMERUNTOL=2-3|PROTECT11=1|PRIZESTATON=0|PRIZECOUNTON=1|NO4=|45:310|51:3|MERGE3"
        let legacyOn = try FilterConfig.parse(input)
        let legacyOff = try FilterConfig.parse(
            input.replacingOccurrences(of: "PRIZECOUNTON=1", with: "PRIZECOUNTON=0")
        )
        let arbitraryHistory: Set<[Int]> = [[3, 3, 3, 3, 3], [0, 0, 0, 0, 0]]
        let enabledResult = SequenceFilterEngine.calculate(
            legacyOn,
            previousContext: nil,
            protectedPrizeOutcomePrefixes: arbitraryHistory
        )
        let disabledResult = SequenceFilterEngine.calculate(
            legacyOff,
            previousContext: nil,
            protectedPrizeOutcomePrefixes: []
        )

        XCTAssertEqual(enabledResult.uniqueExpandedBets, disabledResult.uniqueExpandedBets)
    }

    func testProtectedHistoryProfileIsZeroToleranceAndActuallyReducesBets() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|10-20|0-8|2|5|0|20|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|6:310|MERGE3"
        )
        let rule = ComprehensiveAnalysisRule(
            metric: .valueFourCount,
            lowerBound: 0,
            upperBound: 1,
            sampleCount: 38,
            score: 1
        )
        let profile = ComprehensiveAnalysisProfile(
            generatedAt: Date(timeIntervalSince1970: 0),
            historyRecordCount: 38,
            runSampleCount: 38,
            advancedSampleCount: 38,
            rules: [rule],
            recommendedMetric: .valueFourCount
        )
        let baseline = SequenceFilterEngine.calculate(config, previousContext: nil)
        let protected = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            protectedHistoryProfile: profile
        )

        XCTAssertLessThan(protected.finalBetCount, baseline.finalBetCount)
        XCTAssertEqual(protected.protectedHistoryRecordCount, 38)
        XCTAssertEqual(protected.protectedHistoryRuleCount, 1)
        let expanded = protected.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }
        XCTAssertTrue(expanded.allSatisfy { outcomes in
            SequenceFilterEngine.comprehensiveAnalysisFailureCount(
                fullOutcomes: Array(outcomes.prefix(6)),
                config: config,
                profile: profile,
                outcomeProbabilities: nil,
                outcomeSPs: nil
            ) == 0
        })
    }

    func testLatestWinLossSwitchRangeIsZeroToTwoAcrossCompressionProfile() throws {
        let config = try FilterConfig.parse(
            "11,12,13,14,15|ACCCA|11-18|0-7|1|4|0.04|11|1-6|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=1|PRIZECOUNTON=0|16:310|MERGE3"
        )
        let profile = ComprehensiveAnalysisProfile(
            generatedAt: Date(timeIntervalSince1970: 0),
            historyRecordCount: 34,
            runSampleCount: 34,
            advancedSampleCount: 34,
            rules: [
                ComprehensiveAnalysisRule(
                    metric: .winLossSwitches,
                    lowerBound: 0,
                    upperBound: 2,
                    sampleCount: 34,
                    score: 1
                ),
                ComprehensiveAnalysisRule(
                    metric: .backOutcomeSum,
                    lowerBound: 1,
                    upperBound: 6,
                    sampleCount: 34,
                    score: 1
                )
            ],
            recommendedMetric: .winLossSwitches
        )
        let elevenSeriesOutcome = [0, 3, 0, 0, 0, 3]

        XCTAssertFalse(
            SequenceFilterEngine.comprehensiveAnalysisRulePassesLatest(
                profile.rules[0],
                value: 3
            ),
            "最新条件是六串胜负切换0-2，3次必须被拦截"
        )
        XCTAssertEqual(
            SequenceFilterEngine.comprehensiveAnalysisFailureCount(
                fullOutcomes: elevenSeriesOutcome,
                config: config,
                profile: profile,
                outcomeProbabilities: nil,
                outcomeSPs: nil
            ),
            2,
            "030003的切换数和后两场和值都不符合，应计2项失败"
        )
    }

    func testPrizeStatisticalConditionRejectsThreeFirstSixWinLossSwitches() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=1|PRIZECOUNTON=0|6:310|MERGE3"
        )
        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        let bets = result.uniqueExpandedBets

        XCTAssertFalse(bets.isEmpty)
        XCTAssertTrue(bets.allSatisfy {
            OutcomeCondition.winLossSwitches.value(in: Array($0.prefix(6))) <= 2
        })
        XCTAssertTrue(bets.contains {
            OutcomeCondition.winLossSwitches.value(in: Array($0.prefix(6))) == 2
        })
        XCTAssertFalse(bets.contains([3, 0, 3, 0, 0, 0]))
    }

    func testLegacyCompressionCapIsIgnoredAndDoesNotTruncatePassingBets() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|20|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|6:310|MERGE3"
        )
        let profile = ComprehensiveAnalysisProfile(
            generatedAt: Date(timeIntervalSince1970: 0),
            historyRecordCount: 34,
            runSampleCount: 34,
            advancedSampleCount: 34,
            rules: [],
            recommendedMetric: .sum,
            protectedOutcomePositionCounts: Array(repeating: [100, 1, 1], count: 6)
        )
        let protectedOutcome = [0, 3, 0, 0, 0, 3]
        let result = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            protectedHistoryProfile: profile,
            protectedHistoryToleranceRange: 0...4,
            protectedHistoryBetCap: 1,
            protectedPrizeOutcomePrefixes: Set([protectedOutcome])
        )
        let uncapped = SequenceFilterEngine.calculate(
            config,
            previousContext: nil,
            protectedHistoryProfile: profile,
            protectedHistoryToleranceRange: 0...4,
            protectedHistoryBetCap: nil,
            protectedPrizeOutcomePrefixes: Set([protectedOutcome])
        )
        let expanded = result.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }

        XCTAssertGreaterThan(result.finalBetCount, 1)
        XCTAssertEqual(result.finalBetCount, uncapped.finalBetCount)
        XCTAssertEqual(Set(expanded), Set(uncapped.exportCompressedRecords.flatMap { expandedOutcomes($0.options) }))
        XCTAssertNil(result.protectedHistoryBetCap)
        XCTAssertTrue(expanded.contains(protectedOutcome))
    }

    func testHighMappedValuesDoNotPromoteCompressionTolerance() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|20|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|6:310|MERGE3"
        )
        let base = 0...4

        XCTAssertEqual(
            SequenceFilterEngine.effectiveProtectedHistoryToleranceRange(
                base: base,
                fullOutcomes: [0, 0, 3, 3, 3, 3],
                config: config
            ),
            base,
            "前5场有至少2个判定值4也不得提升到0-5"
        )
        XCTAssertEqual(
            SequenceFilterEngine.effectiveProtectedHistoryToleranceRange(
                base: base,
                fullOutcomes: [0, 1, 1, 3, 3, 3],
                config: config
            ),
            base,
            "前5场有1个判定值4且至少2个判定值3也不得提升到0-5"
        )
        XCTAssertEqual(
            SequenceFilterEngine.effectiveProtectedHistoryToleranceRange(
                base: base,
                fullOutcomes: [0, 1, 3, 3, 3, 0],
                config: config
            ),
            base,
            "第6场即使映射为4也不能参与前5场保护判断"
        )
    }

    private var previousContext: PreviousResultContext {
        PreviousResultContext(
            logic: [.c, .c, .c, .b],
            outcomes: [3, 1, 0, 1],
            hitFlag: 1
        )
    }

    private func configWithoutProbabilitySelection(_ config: FilterConfig) -> FilterConfig {
        FilterConfig(
            matchNumbers: config.matchNumbers,
            logic: config.logic,
            sumRange: config.sumRange,
            displacementRange: config.displacementRange,
            varianceMaximum: config.varianceMaximum,
            valueTwoMaximum: config.valueTwoMaximum,
            transitionMinimumPercent: config.transitionMinimumPercent,
            roughnessMaximum: config.roughnessMaximum,
            breakpointRange: config.breakpointRange,
            productRemovalCount: config.productRemovalCount,
            probabilityRemovalPercent: 0,
            extraMatches: config.extraMatches,
            mergeEnabled: config.mergeEnabled
        )
    }

    func testUniversal150CompressionUsesOneGeneralThresholdAndRoundTrips() throws {
        let passing = try FilterConfig.parse(
            "1,2,3,4,5|CBCBA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=1|6:310|MERGE3"
        )
        XCTAssertTrue(passing.universal150CompressionEnabled)
        XCTAssertEqual(try FilterConfig.parse(passing.normalizedInput), passing)
        XCTAssertTrue(
            SequenceFilterEngine.passesUniversal150Compression(
                fullOutcomes: [3, 3, 3, 3, 0, 3],
                config: passing
            )
        )

        let failing = try FilterConfig.parse(
            "1,2,3,4,5|BCACB|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=1|6:310|MERGE3"
        )
        XCTAssertFalse(
            SequenceFilterEngine.passesUniversal150Compression(
                fullOutcomes: [3, 0, 0, 1, 0, 1],
                config: failing
            )
        )
        XCTAssertEqual(
            SequenceFilterEngine.universal150CompressionScore(
                fullOutcomes: [3, 0, 0, 1, 0, 1],
                config: failing
            )!,
            -12.533672,
            accuracy: 0.000001
        )
    }

    func testUniversal150CompressionFiltersWithoutFixedBetCap() throws {
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=1|6:310|MERGE3"
        let enabled = try FilterConfig.parse(input)
        let disabled = try FilterConfig.parse(input.replacingOccurrences(of: "U150ON=1", with: "U150ON=0"))
        let enabledResult = SequenceFilterEngine.calculate(enabled, previousContext: nil)
        let disabledResult = SequenceFilterEngine.calculate(disabled, previousContext: nil)

        XCTAssertLessThan(enabledResult.finalBetCount, disabledResult.finalBetCount)
        XCTAssertTrue(enabledResult.filterStageSummaries.contains { $0.contains("通用150注统计压缩") })
        XCTAssertTrue(enabledResult.uniqueExpandedBets.allSatisfy {
            SequenceFilterEngine.passesUniversal150Compression(
                fullOutcomes: $0,
                config: enabled
            )
        })
        XCTAssertEqual(enabledResult.stageBetCounts.count, enabledResult.filterStageSummaries.count + 1)
    }

    func testUniversal247ToleranceKeepsExactly247GeneralCombinations() throws {
        let input = "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=1|6:310|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(config.universal247ToleranceEnabled)
        XCTAssertEqual(try FilterConfig.parse(config.normalizedInput), config)

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(result.finalBetCount, 247)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 247)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            SequenceFilterEngine.passesUniversal247Tolerance(fullOutcomes: $0)
        })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("通用247综合容错") })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
    }

    func testWholeIssue405VersionKeepsExactly405GeneralCombinations() throws {
        let input = "1,2,3,4,5|ABCDA|10-20|0-8|1|5|0|12|0-4|QDROP0|FINAL=OFF|RUNS=0|RUN2ON=0|SAMERUNS=0|PRIZESTATON=0|PRIZECOUNTON=0|U150ON=0|U247ON=1|U247TH=9.405|6:310|7:3|MERGE3"
        let config = try FilterConfig.parse(input)
        XCTAssertTrue(
            SequenceFilterEngine.usesUniversal405WholeIssueModel(
                threshold: config.universal247ToleranceThreshold
            )
        )

        let result = SequenceFilterEngine.calculate(config, previousContext: nil)
        XCTAssertEqual(result.finalBetCount, 305)
        XCTAssertEqual(Set(result.uniqueExpandedBets).count, 405)
        XCTAssertTrue(result.uniqueExpandedBets.allSatisfy {
            SequenceFilterEngine.passesUniversal247Tolerance(
                fullOutcomes: $0,
                threshold: config.universal247ToleranceThreshold,
                logic: config.logic
            )
        })
        XCTAssertTrue(result.filterStageSummaries.contains { $0.contains("V5整期留出") })
        XCTAssertEqual(result.stageBetCounts.count, result.filterStageSummaries.count + 1)
    }

    func testWholeIssue405ModelRequiresOnlyOutcomesAndLogic() throws {
        let first = try FilterConfig.parse(
            "1,2,3,4,5|BBBBB|10-20|0-8|1|5|0|12|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.405|6:310|7:3|MERGE3"
        )
        let second = try FilterConfig.parse(
            "91,92,93,94,95|BBBBB|10-20|0-8|1|5|0|12|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=9.405|96:310|97:3|MERGE3"
        )
        let outcomes = [3, 1, 0, 3, 1, 0]
        XCTAssertEqual(
            SequenceFilterEngine.universal247ActiveScore(
                fullOutcomes: outcomes,
                threshold: first.universal247ToleranceThreshold,
                logic: first.logic
            ),
            SequenceFilterEngine.universal247ActiveScore(
                fullOutcomes: outcomes,
                threshold: second.universal247ToleranceThreshold,
                logic: second.logic
            )
        )
        XCTAssertEqual(
            SequenceFilterEngine.passesUniversal247Tolerance(
                fullOutcomes: outcomes,
                threshold: first.universal247ToleranceThreshold,
                logic: first.logic
            ),
            SequenceFilterEngine.passesUniversal247Tolerance(
                fullOutcomes: outcomes,
                threshold: second.universal247ToleranceThreshold,
                logic: second.logic
            )
        )
    }

    func testVIP4KeepsExactly150AndRequiresSixCompleteComparisonRows() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=7.154|6:310|7:0|MERGE3"
        )
        let rows = [
            [2.10, 3.15, 3.40], [1.82, 3.55, 4.20], [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10], [2.72, 3.20, 2.40], [2.18, 3.30, 3.05]
        ]
        let inputs = rows.enumerated().map { index, row in
            VIP4MatchInput(
                comparisonTableOdds: row,
                ordinaryOdds: [2.1 + Double(index) * 0.03, 3.25, 3.45],
                handicap: index.isMultiple(of: 2) ? 0 : -1,
                league: "测试联赛",
                logic: .a,
                homeExpectedGoals: 1.35,
                awayExpectedGoals: 1.10,
                fitError: 0.003
            )
        }
        let context = VIP4MatchContext(matches: inputs, previousOutcomes: [3, 1, 0, 3, 1, 0])

        XCTAssertTrue(SequenceFilterEngine.usesVIP4Model(
            threshold: config.universal247ToleranceThreshold
        ))
        XCTAssertEqual(
            SequenceFilterEngine.calculate(
                config,
                previousContext: nil,
                vip4Context: context
            ).finalBetCount,
            150
        )
        XCTAssertEqual(
            SequenceFilterEngine.calculate(config, previousContext: nil).finalBetCount,
            0
        )
    }

    func testVIP4RankingDoesNotUseABCDMapped234Values() throws {
        let config = try FilterConfig.parse(
            "1,2,3,4,5|AAAAA|0-20|0-20|100|5|0|100|0-4|QDROP0|FINAL=OFF|RUNS=0|SAMERUNS=0|U150ON=0|U247ON=1|U247TH=7.154|6:310|7:0|MERGE3"
        )
        let rows = [
            [2.10, 3.15, 3.40], [1.82, 3.55, 4.20], [2.45, 3.05, 2.82],
            [1.68, 3.80, 5.10], [2.72, 3.20, 2.40], [2.18, 3.30, 3.05]
        ]
        func context(logic: LogicMapping) -> VIP4MatchContext {
            VIP4MatchContext(
                matches: rows.enumerated().map { index, row in
                    VIP4MatchInput(
                        comparisonTableOdds: row,
                        ordinaryOdds: [2.1 + Double(index) * 0.03, 3.25, 3.45],
                        handicap: index.isMultiple(of: 2) ? 0 : -1,
                        league: "测试联赛",
                        logic: logic,
                        homeExpectedGoals: 1.35,
                        awayExpectedGoals: 1.10,
                        fitError: 0.003
                    )
                },
                previousOutcomes: [3, 1, 0, 3, 1, 0]
            )
        }
        XCTAssertEqual(
            SequenceFilterEngine.calculate(config, previousContext: nil, vip4Context: context(logic: .a)).uniqueExpandedBets,
            SequenceFilterEngine.calculate(config, previousContext: nil, vip4Context: context(logic: .d)).uniqueExpandedBets
        )
    }

    func testUniversal247ToleranceReplaysTwentySevenOfThirtyFourHistoryRows() {
        let history = [
            [3, 0, 0, 1, 0, 1], [3, 3, 3, 3, 0, 3], [1, 3, 1, 0, 1, 1],
            [0, 3, 3, 3, 0, 0], [0, 0, 0, 3, 3, 3], [3, 0, 3, 0, 1, 0],
            [0, 1, 0, 3, 3, 0], [1, 1, 0, 1, 3, 1], [1, 3, 0, 1, 3, 3],
            [0, 1, 1, 3, 3, 0], [3, 3, 0, 1, 3, 3], [3, 3, 1, 0, 1, 3],
            [1, 1, 3, 3, 1, 1], [1, 3, 3, 0, 1, 0], [0, 0, 0, 0, 1, 0],
            [1, 1, 3, 0, 1, 3], [3, 1, 3, 1, 3, 0], [0, 3, 3, 3, 0, 1],
            [1, 1, 0, 3, 3, 3], [3, 1, 1, 0, 3, 3], [3, 0, 3, 3, 1, 3],
            [0, 3, 0, 0, 0, 3], [3, 0, 1, 0, 1, 1], [3, 1, 3, 0, 3, 1],
            [3, 0, 1, 1, 1, 0], [0, 1, 1, 1, 3, 0], [0, 0, 1, 0, 1, 1],
            [1, 0, 3, 3, 3, 0], [3, 3, 0, 3, 3, 1], [3, 0, 0, 3, 1, 0],
            [1, 0, 0, 1, 0, 0], [0, 1, 0, 0, 3, 1], [1, 1, 1, 1, 1, 3],
            [0, 3, 3, 1, 3, 3]
        ]
        XCTAssertEqual(history.filter {
            SequenceFilterEngine.passesUniversal247Tolerance(fullOutcomes: $0)
        }.count, 27)
    }

    func testVIP6RecommenderUsesSixMainMatchesPrefersSameDayAndChoosesNoFourPosition() {
        let matches = (1...9).map { number in
            let ordinary: [Double]
            switch number % 4 {
            case 0: ordinary = [1.46, 4.37, 5.58]
            case 1: ordinary = [2.58, 3.31, 2.74]
            case 2: ordinary = [3.92, 3.23, 1.90]
            default: ordinary = [2.12, 3.67, 3.01]
            }
            return BeijingSingleMatch(
                issue: "99999",
                matchNumber: String(number),
                fixtureID: "vip6-\(number)",
                league: "测试",
                matchTime: number <= 7 ? "10-04 20:00" : "10-05 00:30",
                status: "未",
                homeTeam: "主\(number)",
                awayTeam: "客\(number)",
                handicap: number % 3 == 0 ? 1 : 0,
                referenceSP: [],
                marketOdds: ordinary
            )
        }
        let recommendation = VIP6MatchRecommender.recommend(
            firstMatchNumber: 1,
            matches: matches
        )
        XCTAssertNotNil(recommendation)
        XCTAssertEqual(recommendation?.mainMatchNumbers.first, 1)
        XCTAssertEqual(recommendation?.mainMatchNumbers.count, 6)
        XCTAssertEqual(Set(recommendation?.mainMatchNumbers ?? []).count, 6)
        XCTAssertEqual(recommendation?.mainMatchNumbers, recommendation?.mainMatchNumbers.sorted())
        XCTAssertTrue(recommendation?.mainMatchNumbers.dropFirst().allSatisfy { $0 > 1 } == true)
        XCTAssertLessThanOrEqual(recommendation?.sixthMatchNumber ?? .max, 7)
        XCTAssertEqual(recommendation?.outsideFirstMatchDayCount, 0)
        XCTAssertEqual(recommendation?.logic.count, 6)
        XCTAssertTrue((1...6).contains(recommendation?.noFourPosition ?? 0))
        XCTAssertTrue((0...1).contains(recommendation?.noFourProbability ?? -1))
        XCTAssertTrue((0...1).contains(recommendation?.mCoverageProbability ?? -1))

        // 把每场比分故意改成不同的已完赛结果，推荐必须完全不变。
        // 这保证赛果只用于赛后核验，不能反向“美化”选场或ABCD。
        let settledMatches = matches.enumerated().map { index, match in
            BeijingSingleMatch(
                issue: match.issue,
                matchNumber: match.matchNumber,
                fixtureID: match.fixtureID,
                league: match.league,
                matchTime: match.matchTime,
                status: "完",
                homeTeam: match.homeTeam,
                awayTeam: match.awayTeam,
                handicap: match.handicap,
                referenceSP: match.referenceSP,
                marketOdds: match.marketOdds,
                homeScore: index % 3,
                awayScore: (index + 1) % 4
            )
        }
        let settledRecommendation = VIP6MatchRecommender.recommend(
            firstMatchNumber: 1,
            matches: settledMatches
        )
        XCTAssertEqual(settledRecommendation, recommendation)
        XCTAssertNil(settledMatches[0].resultBlindCopy.handicapOutcome)
        XCTAssertNotNil(settledMatches[0].handicapOutcome)
    }

    func testVIP6HomepageRecommendationUsesExactlySixConsecutiveMatches() {
        let matches = (8...16).map { number in
            BeijingSingleMatch(
                issue: "99999",
                matchNumber: String(number),
                fixtureID: "vip6-consecutive-\(number)",
                league: "测试",
                matchTime: "10-04 20:00",
                status: "未",
                homeTeam: "主\(number)",
                awayTeam: "客\(number)",
                handicap: number % 2,
                referenceSP: [],
                marketOdds: [2.35, 3.20, 2.85]
            )
        }

        let recommendation = VIP6MatchRecommender.recommendConsecutive(
            firstMatchNumber: 10,
            matches: matches
        )
        XCTAssertEqual(recommendation?.mainMatchNumbers, [10, 11, 12, 13, 14, 15])
        XCTAssertEqual(recommendation?.sixthMatchNumber, 15)
        XCTAssertEqual(recommendation?.logic.count, 6)
        XCTAssertTrue((1...6).contains(recommendation?.noFourPosition ?? 0))

        let selected = (10...15).compactMap { number in
            matches.first { Int($0.matchNumber) == number }
        }
        let mappings = recommendation?.logic.lowercased().compactMap {
            LogicMapping(rawValue: String($0))
        } ?? []
        let rankedFirstFive = zip(selected.prefix(5), mappings.prefix(5)).enumerated().compactMap {
            offset, pair -> (position: Int, probability: Double)? in
            guard let handicap = pair.0.handicap,
                  let odds = HandicapOddsComparisonTable.convertedOdds(
                    ordinaryOdds: pair.0.marketOdds,
                    handicap: handicap
                  ),
                  let valueFourIndex = pair.1.values.firstIndex(of: 4) else { return nil }
            let inverse = odds.map { 1 / $0 }
            return (offset + 1, inverse[valueFourIndex] / inverse.reduce(0, +))
        }.sorted {
            if abs($0.probability - $1.probability) > 1e-15 {
                return $0.probability < $1.probability
            }
            return $0.position < $1.position
        }
        XCTAssertEqual(recommendation?.noFourPosition, rankedFirstFive.first?.position)
        XCTAssertEqual(
            recommendation?.noFourProbability ?? -1,
            rankedFirstFive.first?.probability ?? -2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            recommendation?.secondLowestNoFourPosition,
            rankedFirstFive.dropFirst().first?.position
        )
        XCTAssertEqual(
            recommendation?.secondLowestNoFourProbability ?? -1,
            rankedFirstFive.dropFirst().first?.probability ?? -2,
            accuracy: 1e-12
        )
        XCTAssertNotEqual(
            recommendation?.noFourPosition,
            recommendation?.secondLowestNoFourPosition
        )
    }

    func testComparisonTableABCDGeneratesAllSixInRequestedOrder() {
        var matches: [BeijingSingleMatch] = []
        for number in (10...15).reversed() {
            let odds: [Double] = number % 2 == 0
                ? [1.85, 3.45, 4.20]
                : [3.70, 3.25, 1.98]
            let match = BeijingSingleMatch(
                issue: "99999",
                matchNumber: String(number),
                fixtureID: "abcd-six-\(number)",
                league: "测试",
                matchTime: "10-09 20:00",
                status: "未",
                homeTeam: "主\(number)",
                awayTeam: "客\(number)",
                handicap: number % 3 - 1,
                referenceSP: [],
                marketOdds: odds
            )
            matches.append(match)
        }
        let requested = (10...15).map(String.init)
        let logic = HandicapOddsComparisonTableMatrix.logic(
            matchNumbers: requested,
            matches: matches
        )
        XCTAssertEqual(logic?.count, 6)
        XCTAssertTrue(logic?.allSatisfy { "ABCD".contains($0) } == true)

        let missingOne = Array(matches.dropLast())
        XCTAssertNil(HandicapOddsComparisonTableMatrix.logic(
            matchNumbers: requested,
            matches: missingOne
        ))
    }

    private func adjacentValueKeys(_ records: [SequenceRecord]) -> Set<String> {
        Set(records.flatMap { record in
            (0..<(record.values.count - 1)).map { position in
                "\(position):\(record.values[position])-\(record.values[position + 1])"
            }
        })
    }

    private func expandedOutcomes(_ options: [[Int]]) -> [[Int]] {
        options.reduce([[]]) { partial, values in
            partial.flatMap { prefix in values.map { prefix + [$0] } }
        }
    }

    private func combinations<T>(of values: [T], choose: Int) -> [[T]] {
        guard choose > 0, choose <= values.count else { return [] }
        if choose == 1 { return values.map { [$0] } }
        return values.indices.flatMap { index -> [[T]] in
            guard values.count - index >= choose else { return [] }
            return combinations(of: Array(values[(index + 1)...]), choose: choose - 1)
                .map { [values[index]] + $0 }
        }
    }
}
