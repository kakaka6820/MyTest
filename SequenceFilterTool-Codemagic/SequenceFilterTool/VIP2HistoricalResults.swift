import SwiftUI

enum VIP2HistoryPresentationMode {
    case query
    case prize
}

enum VIPHistoryModel: String, CaseIterable, Identifiable, Sendable {
    case vip4_2025
    case vip4
    case vip3
    case vip2

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vip4_2025: return "VIP4·2025"
        case .vip4: return "VIP4·2026"
        case .vip3: return "VIP3"
        case .vip2: return "VIP2"
        }
    }

    var resourcePrefix: String {
        switch self {
        case .vip4_2025: return "VIP4_2025_ResultsStart"
        case .vip4: return "VIP4ResultsStart"
        case .vip3: return "VIP3ResultsStart"
        case .vip2: return "VIP2ResultsStart"
        }
    }

    var dataRangeDescription: String {
        switch self {
        case .vip4_2025: return "2025全年（25011–25125）"
        case .vip4: return "26011–26098"
        case .vip3, .vip2: return "26091–26098"
        }
    }

    var calculationDescription: String {
        switch self {
        case .vip4_2025:
            return "冻结VIP4不用2025赛果调参：仍用项目让球对照表概率、通用校准和前一六场组转移修正，每期推荐前2组，每组固定150注。"
        case .vip4:
            return "VIP4使用项目让球对照表概率、通用校准和前一六场组转移修正，每期只推荐前2组，每组固定150注。"
        case .vip3:
            return "VIP3使用六场普通欧赔＋实际让球＋项目对照表统一排名，每组完整保留150注。"
        case .vip2:
            return "VIP2使用结构90%＋项目让球赔率10%统一排名，每组完整保留150注。"
        }
    }
}

private enum VIP2HistoryVersion: String, CaseIterable, Identifiable, Sendable {
    case start2
    case start3
    case start4
    case start5
    case start6
    case start7

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start2: return "第二场开始"
        case .start3: return "第三场开始"
        case .start4: return "第四场开始"
        case .start5: return "第五场开始"
        case .start6: return "第六场开始"
        case .start7: return "第七场开始"
        }
    }

    var startingMatch: Int {
        switch self {
        case .start2: return 2
        case .start3: return 3
        case .start4: return 4
        case .start5: return 5
        case .start6: return 6
        case .start7: return 7
        }
    }

    func resourceName(for model: VIPHistoryModel) -> String {
        model.resourcePrefix + String(startingMatch)
    }

    var groupingDescription: String {
        let secondStart = startingMatch + 6
        return "每期第1场固定为第7场单选1，前6场从第\(startingMatch)场开始，按\(startingMatch)–\(startingMatch + 5)、\(secondStart)–\(secondStart + 5)依次重组。"
    }
}

private struct VIP2HistoricalResult: Identifiable, Sendable {
    let issue: String
    let start: Int
    let matches: String
    let seventh: String
    let logic: String
    let actual: String
    let hit: Bool
    let betCount: Int
    let prize: Double

    var id: String { "\(issue)-\(start)" }

    var issueMonth: Int? {
        guard let value = Int(issue) else { return nil }
        let month = (value / 10) % 100
        return (1...12).contains(month) ? month : nil
    }
}

private struct VIP2HistoricalSummary {
    let total: Int
    let hits: Int
    let prizeTotal: Double

    var misses: Int { total - hits }
    var hitRate: Double { total == 0 ? 0 : Double(hits) / Double(total) * 100 }
    var averageHitPrize: Double { hits == 0 ? 0 : prizeTotal / Double(hits) }
}

private enum VIP2HistoricalLoader {
    enum LoadError: LocalizedError {
        case missingResource(String)
        case unreadableResource(String)

        var errorDescription: String? {
            switch self {
            case let .missingResource(name): return "找不到历史结果文件：\(name).csv"
            case let .unreadableResource(name): return "无法读取历史结果文件：\(name).csv"
            }
        }
    }

    static func loadAll(
        for model: VIPHistoryModel
    ) throws -> [VIP2HistoryVersion: [VIP2HistoricalResult]] {
        var loaded: [VIP2HistoryVersion: [VIP2HistoricalResult]] = [:]
        for version in VIP2HistoryVersion.allCases {
            loaded[version] = try load(version, model: model)
        }
        return loaded
    }

    private static func load(
        _ version: VIP2HistoryVersion,
        model: VIPHistoryModel
    ) throws -> [VIP2HistoricalResult] {
        let resourceName = version.resourceName(for: model)
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "csv") else {
            throw LoadError.missingResource(resourceName)
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw LoadError.unreadableResource(resourceName)
        }

        return content.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count >= 10,
                  let start = Int(values[1]),
                  let betCount = Int(values[8]),
                  let prize = Double(values[9]) else { return nil }
            return VIP2HistoricalResult(
                issue: values[0],
                start: start,
                matches: values[2],
                seventh: values[3],
                logic: values[4],
                actual: values[5],
                hit: values[7] == "1",
                betCount: betCount,
                prize: prize
            )
        }
    }
}

struct VIP2HistoricalResultsView: View {
    let mode: VIP2HistoryPresentationMode

    @State private var selectedModel: VIPHistoryModel
    @State private var selectedVersion: VIP2HistoryVersion = .start2
    @State private var recordsByModel: [VIPHistoryModel: [VIP2HistoryVersion: [VIP2HistoricalResult]]] = [:]
    @State private var loadError: String?
    @State private var isLoading = true

    init(mode: VIP2HistoryPresentationMode, initialModel: VIPHistoryModel = .vip4_2025) {
        self.mode = mode
        _selectedModel = State(initialValue: initialModel)
    }

    private var records: [VIP2HistoricalResult] {
        recordsByModel[selectedModel]?[selectedVersion] ?? []
    }

    private var summary: VIP2HistoricalSummary {
        Self.summary(for: records)
    }

    private var issueGroups: [(issue: String, records: [VIP2HistoricalResult])] {
        Dictionary(grouping: records, by: \.issue)
            .map { (issue: $0.key, records: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.issue > $1.issue }
    }

    private var monthGroups: [(month: Int, records: [VIP2HistoricalResult])] {
        Dictionary(grouping: records.compactMap { record in
            record.issueMonth.map { ($0, record) }
        }, by: \.0)
        .map { month, values in
            (month: month, records: values.map(\.1))
        }
        .sorted { $0.month < $1.month }
    }

    var body: some View {
        List {
            Section("计算版本") {
                Picker("策略版本", selection: $selectedModel) {
                    ForEach(VIPHistoryModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)

                Picker("选择开始场次", selection: $selectedVersion) {
                    ForEach(VIP2HistoryVersion.allCases) { version in
                        Text(version.title).tag(version)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedVersion.groupingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("正在载入完整结果…")
                        Spacer()
                    }
                }
            } else if let loadError {
                Section {
                    Text(loadError).foregroundStyle(.red)
                }
            } else {
                Section(mode == .query ? "查询汇总" : "奖金汇总") {
                    HStack(spacing: 8) {
                        summaryTile("总组数", value: "\(summary.total)", color: .blue)
                        summaryTile("命中", value: "\(summary.hits)", color: .green)
                        summaryTile("未命中", value: "\(summary.misses)", color: .red)
                    }
                    LabeledContent("历史命中率") {
                        Text(String(format: "%.2f%%", summary.hitRate))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(summary.hitRate >= 50 ? .green : .orange)
                    }
                    if mode == .prize {
                        LabeledContent("命中奖金合计") {
                            Text("¥\(String(format: "%.2f", summary.prizeTotal))")
                                .monospacedDigit()
                        }
                        LabeledContent("命中组平均奖金") {
                            Text("¥\(String(format: "%.2f", summary.averageHitPrize))")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    Text("范围为\(selectedModel.dataRangeDescription)；\(selectedModel.calculationDescription)不截取结果。奖金按命中组的6场对照表赔率乘积×1.3统计，未命中组不计入奖金合计。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectedModel == .vip4_2025 {
                    Section("2025按月验证") {
                        ForEach(monthGroups, id: \.month) { group in
                            let monthSummary = Self.summary(for: group.records)
                            LabeledContent("\(group.month)月") {
                                Text("\(monthSummary.hits)/\(monthSummary.total) · \(String(format: "%.2f%%", monthSummary.hitRate))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(monthSummary.hitRate >= 50 ? .green : .orange)
                            }
                        }
                        Text("这是冻结2026训练后参数对2025的独立回放；没有用2025期号、场次号或当前赛果调参。全年总命中65/113（57.52%），但月度仍有波动。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("按期号查看") {
                    ForEach(issueGroups, id: \.issue) { group in
                        let issueSummary = Self.summary(for: group.records)
                        NavigationLink {
                            VIP2HistoricalIssueView(
                                modelTitle: selectedModel.title,
                                versionTitle: selectedVersion.title,
                                issue: group.issue,
                                records: group.records,
                                mode: mode
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("第\(group.issue)期")
                                    .font(.headline)
                                HStack {
                                    Text("\(issueSummary.hits)/\(issueSummary.total)命中")
                                    Text(String(format: "%.2f%%", issueSummary.hitRate))
                                    if mode == .prize {
                                        Text("均¥\(String(format: "%.2f", issueSummary.averageHitPrize))")
                                    }
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(issueSummary.hitRate >= 50 ? .green : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(mode == .query ? "\(selectedModel.title)查询结果" : "\(selectedModel.title)奖金结果")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard recordsByModel.isEmpty else { return }
            isLoading = true
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    var all: [VIPHistoryModel: [VIP2HistoryVersion: [VIP2HistoricalResult]]] = [:]
                    for model in VIPHistoryModel.allCases {
                        all[model] = try VIP2HistoricalLoader.loadAll(for: model)
                    }
                    return all
                }.value
                recordsByModel = loaded
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func summaryTile(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    fileprivate static func summary(for records: [VIP2HistoricalResult]) -> VIP2HistoricalSummary {
        let hits = records.filter(\.hit)
        return VIP2HistoricalSummary(
            total: records.count,
            hits: hits.count,
            prizeTotal: hits.reduce(0) { $0 + $1.prize }
        )
    }
}

private struct VIP2HistoricalIssueView: View {
    let modelTitle: String
    let versionTitle: String
    let issue: String
    let records: [VIP2HistoricalResult]
    let mode: VIP2HistoryPresentationMode

    private var summary: VIP2HistoricalSummary {
        VIP2HistoricalResultsView.summary(for: records)
    }

    var body: some View {
        List {
            Section("本期汇总") {
                LabeledContent("策略", value: modelTitle)
                LabeledContent("版本", value: versionTitle)
                LabeledContent("命中") {
                    Text("\(summary.hits)/\(summary.total)（\(String(format: "%.2f", summary.hitRate))%）")
                        .monospacedDigit()
                }
                if mode == .prize {
                    LabeledContent("命中奖金合计") {
                        Text("¥\(String(format: "%.2f", summary.prizeTotal))").monospacedDigit()
                    }
                    LabeledContent("命中组平均") {
                        Text("¥\(String(format: "%.2f", summary.averageHitPrize))").monospacedDigit()
                    }
                }
            }

            Section("场次组（按起始场次排序）") {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("第\(record.start)场开始")
                                .font(.headline)
                            Spacer()
                            Label(record.hit ? "命中" : "未命中",
                                  systemImage: record.hit ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(record.hit ? .green : .red)
                        }
                        Text("前6场：\(record.matches)　固定第7场：\(record.seventh)")
                        Text("ABCD：\(record.logic)　彩果：\(record.actual)")
                        HStack {
                            Text("\(modelTitle)：\(record.betCount)注")
                            Spacer()
                            Text(record.hit ? "命中奖金 ¥\(String(format: "%.2f", record.prize))"
                                            : "赛果理论金额 ¥\(String(format: "%.2f", record.prize))")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(record.hit ? Color.green : Color.red)
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("第\(issue)期")
        .navigationBarTitleDisplayMode(.inline)
    }
}
