import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct SharedTXTQueryRecord: Codable, Identifiable {
    let id: UUID
    let sharedAt: Date
    var issue: String
    let filename: String
    let txtContent: String?
    let normalizedInput: String
    let matchNumbers: [String]
    let betOutcomes: [[Int]]
    let finalBetCount: Int
    /// 当前条件回算使用的签名；最近TXT存档只按保存的投注核对。
    let conditionSignature: String?
    var lastCheckedAt: Date?
    var observedOutcomes: [Int?]?
    var observedHandicaps: [Int?]?
    var verificationMessage: String?
    var isFinalResult: Bool
    var isHit: Bool?
    var prizeAmount: Double?
    var prizeSPValues: [Double]?
    /// Optional for older/imported TXT. Never substitute current odds for this snapshot.
    var generationCustomOdds: [[Double]]? = nil
    /// A manual revision freezes its own bets instead of rerunning today's conditions.
    var manualTXTExclusions: [TXTOutcomeExclusion]? = nil
    var displayedMatchNumbers: [String]? = nil
    /// Written only when the user initiates the system share sheet. sharedAt
    /// alone is not evidence: older versions also set it during generation.
    var explicitShareInitiatedAt: Date? = nil
}

enum ExplicitTXTShareArchive {
    static let storageKey = "sequenceFilter.explicitTXTShareHistory.v1"
    static let legacyBackupKey = "sequenceFilter.preExplicitShareHistory.v1"
    static let legacyKeys = ["sequenceFilter.sharedTXTQueryHistory.v1", "sequenceFilter.recentTXTQueryHistory.v1",
                             "sequenceFilter.prizeQueryHistory.v1"]

    static func preserveLegacyHistoryOnce(defaults: UserDefaults) {
        guard defaults.dictionary(forKey: legacyBackupKey) == nil else { return }
        let payload = Dictionary(uniqueKeysWithValues: legacyKeys.compactMap { key in defaults.data(forKey: key).map { (key, $0) } })
        defaults.set(payload, forKey: legacyBackupKey)
        defaults.synchronize()
    }

    static func confirmed(_ records: [SharedTXTQueryRecord]) -> [SharedTXTQueryRecord] {
        var seen = Set<String>()
        return records.sorted { ($0.explicitShareInitiatedAt ?? .distantPast) > ($1.explicitShareInitiatedAt ?? .distantPast) }
            .filter { $0.explicitShareInitiatedAt != nil && $0.txtContent != nil && seen.insert(contentKey($0)).inserted }
            .sorted { ($0.explicitShareInitiatedAt ?? .distantPast) < ($1.explicitShareInitiatedAt ?? .distantPast) }
    }

    static func contentKey(_ record: SharedTXTQueryRecord) -> String {
        let identity = record.issue + "|" + record.matchNumbers.joined(separator: ",") + "|"
            + record.betOutcomes.map { $0.map(String.init).joined() }.sorted().joined(separator: ",") + "|" + (record.txtContent ?? "")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func admitting(_ snapshot: SharedTXTQueryRecord, into records: [SharedTXTQueryRecord]) -> [SharedTXTQueryRecord] {
        guard snapshot.explicitShareInitiatedAt != nil else { return confirmed(records) }
        let key = contentKey(snapshot)
        return confirmed(records.filter { contentKey($0) != key } + [snapshot])
    }

    /// Freeze the actual part being shared, retaining hidden seventh-column
    /// metadata only for source bets whose visible projection is in this TXT.
    static func snapshot(source: SharedTXTQueryRecord, text: String, filename: String,
                         now: Date = Date()) throws -> SharedTXTQueryRecord {
        let rows = text.components(separatedBy: .newlines).filter { $0.contains("→") || $0.contains("->") }.joined(separator: "\n")
        let parsed = rows.isEmpty ? nil : try SharedTXTImportParser.parse(rows)
        if parsed == nil && !text.contains("最终：0注") { throw SharedTXTImportError.noBetRows }
        let visible = parsed?.matchNumbers ?? source.displayedMatchNumbers ?? source.matchNumbers
        let positions = try visible.map { number -> Int in
            guard let index = source.matchNumbers.firstIndex(where: { Int($0) == Int(number) }) else {
                throw SharedTXTImportError.inconsistentMatches
            }
            return index
        }
        let visibleBets = Set(parsed?.betOutcomes ?? [])
        var seen = Set<[Int]>()
        let bets = source.betOutcomes.filter { bet in
            bet.count == source.matchNumbers.count && visibleBets.contains(positions.map { bet[$0] }) && seen.insert(bet).inserted
        }
        guard Set(bets.map { bet in positions.map { bet[$0] } }) == visibleBets else { throw SharedTXTImportError.inconsistentMatches }
        return SharedTXTQueryRecord(id: UUID(), sharedAt: now, issue: source.issue, filename: filename,
            txtContent: text, normalizedInput: source.normalizedInput, matchNumbers: source.matchNumbers,
            betOutcomes: bets, finalBetCount: bets.count, conditionSignature: source.conditionSignature,
            lastCheckedAt: source.lastCheckedAt, observedOutcomes: source.observedOutcomes,
            observedHandicaps: source.observedHandicaps, verificationMessage: nil, isFinalResult: source.isFinalResult,
            isHit: RecentTXTQueryArchive.hit(bets: bets, outcomes: source.observedOutcomes ?? [], isFinal: source.isFinalResult),
            prizeAmount: nil, prizeSPValues: source.prizeSPValues, generationCustomOdds: source.generationCustomOdds,
            manualTXTExclusions: source.manualTXTExclusions, displayedMatchNumbers: visible, explicitShareInitiatedAt: now)
    }
}

enum RecentTXTQueryArchive {
    static let retentionInterval: TimeInterval = 48 * 60 * 60

    /// 按存档ID保留每次生成，不能按期号和场次覆盖同组的不同TXT。
    static func retained(_ records: [SharedTXTQueryRecord], now: Date = Date()) -> [SharedTXTQueryRecord] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        var seen = Set<UUID>()
        return records.reversed().filter {
            $0.sharedAt >= cutoff
                && $0.txtContent?.isEmpty == false
                && seen.insert($0.id).inserted
        }.sorted { $0.sharedAt < $1.sharedAt }
    }

    static func hit(bets: [[Int]], outcomes: [Int?], isFinal: Bool) -> Bool? {
        guard isFinal, outcomes.count >= 6 else { return nil }
        let target = Array(outcomes.prefix(6))
        guard target.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return nil }
        return bets.contains { bet in
            bet.count >= 6 && zip(bet.prefix(6), target).allSatisfy { $0 == $1 }
        }
    }
}

struct ImportedTXTSelection: Equatable {
    let issue: String?
    let matchNumbers: [String]
    let betOutcomes: [[Int]]
    let declaredBetCount: Int?
}

enum SharedTXTImportError: LocalizedError, Equatable {
    case noBetRows
    case inconsistentMatches
    case invalidOutcome
    case betCountMismatch(declared: Int, parsed: Int)
    case tooManyBets

    var errorDescription: String? {
        switch self {
        case .noBetRows:
            return "TXT中没有找到“场次→投注”格式的投注行。"
        case .inconsistentMatches:
            return "TXT各投注行的场次不一致或有重复场次。"
        case .invalidOutcome:
            return "TXT中的投注值无效，只支持3、1、0及其组合。"
        case let .betCountMismatch(declared, parsed):
            return "TXT声明为\(declared)注，但实际解析出\(parsed)注，请检查文件是否完整。"
        case .tooManyBets:
            return "TXT展开后超过20万注，为避免卡顿已停止导入。"
        }
    }
}

enum SharedTXTImportParser {
    private static let betPattern = #"([0-9]+)\s*(?:→|->)\s*(\([310\s、,，/]+\)|[310])"#
    private static let issuePattern = #"(?:期号\s*[:：]?|第\s*)([0-9]{5})(?:\s*期)?"#
    private static let countPattern = #"最终\s*[:：]\s*([0-9]+)\s*注"#

    static func parse(_ text: String) throws -> ImportedTXTSelection {
        let issue = firstCapture(pattern: issuePattern, in: text)
        let declaredBetCount = firstCapture(pattern: countPattern, in: text).flatMap(Int.init)
        let regex = try NSRegularExpression(pattern: betPattern)
        var canonicalMatches: [String]?
        var expandedBets: [[Int]] = []

        for line in text.components(separatedBy: .newlines) where line.contains("→") || line.contains("->") {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            var rowMatches: [String] = []
            var optionsByMatch: [String: [Int]] = [:]
            for match in matches {
                guard let matchRange = Range(match.range(at: 1), in: line),
                      let outcomeRange = Range(match.range(at: 2), in: line) else { continue }
                let matchNumber = String(line[matchRange])
                let outcomes = line[outcomeRange].compactMap { character -> Int? in
                    switch character {
                    case "3": return 3
                    case "1": return 1
                    case "0": return 0
                    default: return nil
                    }
                }
                let uniqueOutcomes = outcomes.reduce(into: [Int]()) { values, value in
                    if !values.contains(value) { values.append(value) }
                }
                guard !uniqueOutcomes.isEmpty else { throw SharedTXTImportError.invalidOutcome }
                guard optionsByMatch[matchNumber] == nil else { throw SharedTXTImportError.inconsistentMatches }
                rowMatches.append(matchNumber)
                optionsByMatch[matchNumber] = uniqueOutcomes
            }
            guard !rowMatches.isEmpty else { continue }
            if canonicalMatches == nil { canonicalMatches = rowMatches }
            guard let canonicalMatches,
                  Set(rowMatches) == Set(canonicalMatches),
                  rowMatches.count == canonicalMatches.count else {
                throw SharedTXTImportError.inconsistentMatches
            }
            let orderedOptions = canonicalMatches.compactMap { optionsByMatch[$0] }
            guard orderedOptions.count == canonicalMatches.count else {
                throw SharedTXTImportError.inconsistentMatches
            }
            let rowBetCount = orderedOptions.reduce(1) { $0 * $1.count }
            guard expandedBets.count + rowBetCount <= 200_000 else {
                throw SharedTXTImportError.tooManyBets
            }
            expandedBets += orderedOptions.reduce([[Int]]([[]])) { prefixes, options in
                prefixes.flatMap { prefix in options.map { prefix + [$0] } }
            }
        }

        guard let matchNumbers = canonicalMatches, !expandedBets.isEmpty else {
            throw SharedTXTImportError.noBetRows
        }
        var seen = Set<[Int]>()
        let uniqueBets = expandedBets.filter { seen.insert($0).inserted }
        if let declaredBetCount, declaredBetCount != uniqueBets.count {
            throw SharedTXTImportError.betCountMismatch(declared: declaredBetCount, parsed: uniqueBets.count)
        }
        return ImportedTXTSelection(
            issue: issue,
            matchNumbers: matchNumbers,
            betOutcomes: uniqueBets,
            declaredBetCount: declaredBetCount
        )
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}

enum TXTQueryStatisticsCalculator {
    static func uniqueKey(issue: String, matchNumbers: [String]) -> String {
        let normalizedIssue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMatches = matchNumbers.map { value -> String in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed).map(String.init) ?? trimmed
        }.sorted { left, right in
            if let leftNumber = Int(left), let rightNumber = Int(right) {
                return leftNumber < rightNumber
            }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return normalizedIssue + "|" + normalizedMatches.joined(separator: ",")
    }

    /// 一张6串票在查询模块中的唯一键。第7场只用于奖金扩展，不能让同一份
    /// 前6场TXT在查询页产生两条记录或让条件判定命中另一条TXT。
    static func ticketKey(issue: String, matchNumbers: [String]) -> String {
        uniqueKey(issue: issue, matchNumbers: Array(matchNumbers.prefix(6)))
    }

    /// 严格使用7场彩果；连续胜、平、负中至少两项最长连续数大于等于2。
    static func hasTwoSameResultRunsAtLeastTwo(sevenOutcomes: [Int]) -> Bool {
        guard sevenOutcomes.count == 7,
              sevenOutcomes.allSatisfy({ $0 == 3 || $0 == 1 || $0 == 0 }) else { return false }
        let longestRuns = [3, 1, 0].map { target in
            var longest = 0
            var current = 0
            for outcome in sevenOutcomes {
                if outcome == target {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            return longest
        }
        return longestRuns.filter { $0 >= 2 }.count >= 2
    }
}

struct TextReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
