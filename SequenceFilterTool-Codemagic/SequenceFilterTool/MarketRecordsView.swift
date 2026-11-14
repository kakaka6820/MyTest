import SwiftUI
import Charts
import UniformTypeIdentifiers

@MainActor final class MarketRecordsViewModel: ObservableObject {
    @Published var archive = MarketRecordsArchive()
    @Published var loading = false
    @Published var message: String?
    private static var localURL: URL {
        FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("MarketRecords.json")
    }
    func load() async {
        loading=true; defer { loading=false }
        do {
            let local=Self.localURL
            let bundle=Bundle.main.url(forResource:"MarketRecords",withExtension:"json")
            archive=try await Task.detached(priority:.utility) {
                let url=FileManager.default.fileExists(atPath:local.path) ? local : bundle
                guard let url else { return MarketRecordsArchive() }
                let value=try JSONDecoder().decode(MarketRecordsArchive.self,from:Data(contentsOf:url))
                try value.validate();return value
            }.value
        } catch { message="记录读取失败，原文件已保留：\(error.localizedDescription)" }
    }
    func save() async throws {
        let value=archive,url=Self.localURL
        try await Task.detached(priority:.utility) {
            try value.validate();let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            try encoder.encode(value).write(to:url,options:.atomic)
        }.value
    }
    func importArchive(_ url:URL) async {
        loading=true; defer { loading=false }
        let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let incoming=try await Task.detached(priority:.utility) {
                let value=try JSONDecoder().decode(MarketRecordsArchive.self,from:Data(contentsOf:url))
                try value.validate();return value
            }.value
            // The imported archive is a separate file; no TXT, condition or home
            // preference is touched. Save only a fully validated replacement.
            let previous=archive;archive=incoming
            do { try await save() } catch { archive=previous;throw error }
            message="已导入\(incoming.records.count)场记录"
        } catch { message="导入失败，已保留现有记录：\(error.localizedDescription)" }
    }
    func refresh(issue:String) async {
        guard issue.count==5,issue.allSatisfy(\.isNumber),["25","26"].contains(String(issue.prefix(2))) else {
            message="请输入2025或2026年的五位北单期号";return
        }
        loading=true;defer { loading=false }
        do {
            message="正在更新第\(issue)期…"
            let raw=try await MarketRecordsClient.download(URL(string:"https://live.500.com/zqdc.php?e=\(issue)")!)
            guard let html=FiveHundredBeijingSingleClient.decodeHTML(raw) else { throw GoalModelError.invalidResponse }
            var rows=try MarketRecordsClient.metadata(html:html,issue:issue)
            archive.register(rows)
            try await save() // Registration reaches disk before quotes are read.
            let european=try MarketRecordsClient.europeanQuotes(html:html),time=Date()
            for i in rows.indices {
                if let quote=european[rows[i].fixtureID] { rows[i].samples=[MarketRecordSample(capturedAt:time,european:quote)] }
            }
            archive.merge(rows);try await save()
            // One phone refresh is bounded; the Mac's resumable queue handles
            // the full two-year archive without making this page block for hours.
            let candidates=rows.filter { row in
                guard let existing=archive.records.first(where: { $0.id==row.id }) else { return true }
                return existing.latestAsian==nil || (row.kickoff.map { $0>Date().addingTimeInterval(7200) } ?? false)
            }.prefix(24)
            var count=0
            for original in candidates {
                try Task.checkCancellation()
                do {
                    let quote=try await MarketRecordsClient.macau(fixtureID:original.fixtureID)
                    guard quote.currentAsian != nil else { continue }
                    var row=original
                    row.samples=[MarketRecordSample(capturedAt:Date(),european:[],asian:quote.currentAsian,openingAsian:quote.openingAsian)]
                    archive.merge([row]);count += 1
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
            archive.updateRecommendations();try await save()
            message="已更新\(rows.count)场威廉欧赔、本轮补取\(count)场澳门亚盘；缺失阶段继续保留为待补。"
        } catch { message="更新未完成，已保留采集记录：\(error.localizedDescription)" }
    }
}

struct MarketRecordsView: View {
    @StateObject private var model=MarketRecordsViewModel()
    @State private var year=2026
    @State private var search=""
    @State private var issue=""
    @State private var mode=0
    @State private var limit=40
    @State private var importing=false
    private var matches:[MarketMatchRecord] {
        model.archive.records.filter { r in
            r.year==year && (issue.isEmpty || r.issue.contains(issue))
                && (search.isEmpty || "\(r.issue) \(r.number) \(r.home) \(r.away) \(r.league)".localizedCaseInsensitiveContains(search))
        }.sorted { $0.issue == $1.issue ? $0.number<$1.number : $0.issue>$1.issue }
    }
    private var recommendations:[MarketRecordRecommendation] {
        let descriptions=Dictionary(model.archive.records.map { ($0.id,"\($0.home) \($0.away) \($0.league)") },uniquingKeysWith: { _,b in b })
        return model.archive.recommendations.filter { p in
            guard p.issue.hasPrefix(String(year%100)),issue.isEmpty || p.issue.contains(issue) else { return false }
            if search.isEmpty { return true }
            let identities=p.fixtures.map { "\(p.issue):\($0.number):\($0.fixtureID)" }
            let text=p.issue+" "+p.fixtures.map { String($0.number) }.joined(separator:" ")+" "+identities.compactMap { descriptions[$0] }.joined(separator:" ")
            return text.localizedCaseInsensitiveContains(search)
        }.sorted {
            if ($0.kind=="archiveReference") != ($1.kind=="archiveReference") { return $0.kind != "archiveReference" }
            return $0.issue == $1.issue ? $0.first<$1.first : $0.issue>$1.issue
        }
    }
    var body: some View {
        List {
            Section {
                Picker("年份",selection:$year) { Text("2025").tag(2025);Text("2026").tag(2026) }.pickerStyle(.segmented)
                HStack {
                    TextField("期号筛选／更新，例如26108",text:$issue).keyboardType(.numberPad)
                    Button("更新") {
                        let chosen=issue.isEmpty ? (model.archive.records.filter { $0.year==year }.map(\.issue).max() ?? (year==2025 ? "25011":"26108")) : issue
                        Task { await model.refresh(issue:chosen) }
                    }.disabled(model.loading)
                }
                Picker("展示",selection:$mode) { Text("全部比赛").tag(0);Text("双选推荐").tag(1) }.pickerStyle(.segmented)
                Text("欧赔：威廉希尔 · 亚盘：澳门彩票\n初盘 → 中期（赛前24小时）→ 临近（赛前2小时）")
                    .font(.caption).foregroundStyle(.secondary)
                if model.loading { ProgressView("正在读取／采集…") }
                if let message=model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            statistics
            Section {
                Text(model.archive.coverageNote).font(.caption).foregroundStyle(.secondary)
                Text("初盘时间未公开时会注明；中期、临近只用对应时点之前30分钟内的真实采样。赛后取得的报价归档展示，不能补成赛前走势。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if mode==0 {
                Section("已发现\(matches.count)场") {
                    ForEach(Array(matches.prefix(limit))) { record in
                        NavigationLink { MarketRecordDetailView(record:record) } label: { MarketMatchRecordRow(record:record) }
                    }
                    if matches.count>limit { Button("再显示40场") { limit += 40 } }
                    if matches.isEmpty && !model.loading { Text("此筛选下暂无记录，采集后会保留全部场次，包括走势待补的比赛。") }
                }
            } else {
                Section("固定连续六场内选两场 · \(recommendations.count)组") {
                    ForEach(Array(recommendations.prefix(limit))) { recommendation in
                        MarketRecommendationRow(recommendation:recommendation,records:model.archive.records)
                    }
                    if recommendations.count>limit { Button("再显示40组") { limit += 40 } }
                    if recommendations.isEmpty { Text("尚无六场完整报价；缺失组仍保留在比赛记录中。") }
                }
            }
        }
        .navigationTitle("记录").navigationBarTitleDisplayMode(.inline)
        .searchable(text:$search,prompt:"球队、赛事、期号或场次")
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("导入记录") { importing=true }.disabled(model.loading) } }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            if case .success(let url)=result { Task { await model.importArchive(url) } }
            else if case .failure(let error)=result { model.message=error.localizedDescription }
        }
        .task { await model.load() }
        .onChange(of:year) { _ in limit=40;issue="" }
        .onChange(of:issue) { _ in limit=40 }
        .onChange(of:mode) { _ in limit=40 }
        .onChange(of:search) { _ in limit=40 }
    }
    private var statistics: some View {
        let stats=MarketRecordStatistics.calculate(model.archive,year:year)
        let measured=model.archive.recommendations.filter { $0.issue.hasPrefix(String(year%100)) && $0.kind != "archiveReference" }
        let completed=measured.compactMap { MarketRecommendationRow.jointResult($0,records:model.archive.records) }
        let hits=completed.filter { $0 }.count
        return Section("\(String(year))年推荐命中率") {
            LabeledContent("两场共同命中") {
                Text(completed.isEmpty ? "暂无命中率" : String(format:"%.2f%% · %d/%d组",100*Double(hits)/Double(completed.count),hits,completed.count)).bold()
            }
            Text("赛前推荐\(measured.count)组 · 已核验\(completed.count)组 · 待赛果\(measured.count-completed.count)组；两场都中才算该组命中。")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("前瞻登记样本实测") { Text(stats.rate.map { String(format:"%.2f%% · %d/%d组",$0*100,stats.hits,stats.settled) } ?? "暂无命中率") }
            Text("前瞻登记\(stats.registered)组 · 待赛果\(stats.pending)组 · 缺预测／数据\(stats.unavailable)组。独立75%核验还需完整初盘与时间证据；探索记录和归档参考不能用于达标证明。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct MarketMatchRecordRow: View {
    let record:MarketMatchRecord
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("\(record.issue)期 · \(record.number)场").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer();Text(record.isFinal ? "\(record.homeScore!)–\(record.awayScore!)" : record.status).font(.caption.bold())
            }
            Text("\(record.home)  vs  \(record.away)").font(.subheadline.bold())
            Text("\(record.league) · 北单让球\(record.handicap.map(String.init) ?? "待补") · \(record.kickoff.map { $0.formatted(date:.abbreviated,time:.shortened) } ?? "开赛时间待补")")
                .font(.caption2).foregroundStyle(.secondary)
            MarketStagesView(record:record)
        }.padding(.vertical,6)
    }
}

private struct MarketStagesView: View {
    let record:MarketMatchRecord
    private func euro(_ p:MarketRecordSample?) -> String {
        guard let values=p?.european,values.count==3 else { return "待补" }
        return values.map { String(format:"%.2f",$0) }.joined(separator:" / ")
    }
    static func asian(_ p:DoubleAsianPoint?) -> String {
        guard let p else { return "待补" }
        return String(format:"%.2f / %@%.2f / %.2f",p.homeWater,p.line<0 ? "让":"受",abs(p.line),p.awayWater)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text("威廉希尔欧赔 · 胜 / 平 / 负").font(.caption2.bold()).foregroundStyle(.indigo)
            stageLine(initial:record.samples.compactMap(\.openingEuropean).first.map { $0.map { String(format:"%.2f",$0) }.joined(separator:" / ") } ?? "待补",
                middle:euro(record.stage(hoursBefore:24)),near:euro(record.stage(hoursBefore:2)))
            Text("澳门彩票亚盘 · 主水 / 盘口 / 客水").font(.caption2.bold()).foregroundStyle(.teal)
            stageLine(initial:Self.asian(record.samples.compactMap(\.openingAsian).first),
                middle:Self.asian(record.stage(hoursBefore:24,asian:true)?.asian),near:Self.asian(record.stage(hoursBefore:2,asian:true)?.asian))
            if record.latestEuropean != nil || record.latestAsian != nil {
                Text("已保留真实采样；点击查看报价、时间和曲线。") .font(.caption2).foregroundStyle(.secondary)
            } else if record.archivedEuropean != nil {
                Text("有历史单次欧赔，采集时点未核验，未填入走势阶段。") .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func stageLine(initial:String,middle:String,near:String) -> some View {
        HStack(alignment:.top,spacing:5) {
            stage("初盘",initial);Image(systemName:"arrow.right").font(.caption2).padding(.top,19).foregroundStyle(.tertiary)
            stage("中期",middle);Image(systemName:"arrow.right").font(.caption2).padding(.top,19).foregroundStyle(.tertiary)
            stage("临近",near)
        }
    }
    private func stage(_ title:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size:10,weight:.medium,design:.monospaced)).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct MarketRecommendationRow: View {
    let recommendation:MarketRecordRecommendation
    let records:[MarketMatchRecord]
    static func jointResult(_ prediction:MarketRecordRecommendation,records:[MarketMatchRecord]) -> Bool? {
        guard prediction.kind != "archiveReference",prediction.madeAt<prediction.cutoff,
              prediction.fixtures.count==6,prediction.legs.count==2 else { return nil }
        var outcomes:[Int:Int]=[:]
        for identity in prediction.fixtures {
            guard let row=records.first(where: { $0.issue==prediction.issue && $0.number==identity.number && $0.fixtureID==identity.fixtureID }),
                  row.isFinal,let h=row.homeScore,let a=row.awayScore else { return nil }
            let delta=h+identity.handicap-a;outcomes[identity.number]=delta>0 ? 3:delta==0 ? 1:0
        }
        return prediction.legs.allSatisfy { $0.retained.contains(outcomes[$0.number] ?? -1) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("\(recommendation.issue)期 · \(recommendation.first)–\(recommendation.first+5)场").font(.headline)
            Text(recommendation.kind=="prospective" ? "前瞻推荐" : recommendation.kind=="exploratory" ? "探索推荐（单列核验）":"归档报价参考（不计走势命中率）")
                .font(.caption).foregroundStyle(recommendation.kind=="archiveReference" ? .secondary:.primary)
            ForEach(Array(recommendation.legs.enumerated()),id:\.offset) { _,leg in
                Text("\(leg.number)场 · \(leg.mappedPair.map(String.init).joined()) · \(leg.retained.map { $0==3 ? "让球胜":$0==1 ? "让球平":"让球负" }.joined(separator:"／")) · 原让球\(leg.handicap)")
                    .font(.subheadline)
            }
            if let hit=Self.jointResult(recommendation,records:records) {
                Label(hit ? "两场同时命中":"两场未同时命中",systemImage:hit ? "checkmark.circle.fill":"xmark.circle")
                    .font(.caption.bold()).foregroundStyle(hit ? .green:.orange)
            } else { Text(recommendation.kind=="archiveReference" ? "缺少可核验赛前走势，不计成绩":"待六场最终赛果核验").font(.caption).foregroundStyle(.secondary) }
            Text("锁定：\(recommendation.cutoff.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical,6)
    }
}

private struct MarketRecordDetailView: View {
    let record:MarketMatchRecord
    var body: some View {
        List {
            Section { MarketMatchRecordRow(record:record) }
            Section("最新／归档报价") {
                if let p=record.latestEuropean {
                    Text("威廉希尔："+p.european.map { String(format:"%.2f",$0) }.joined(separator:" / "))
                    Text("采样：\(p.capturedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                } else if let values=record.archivedEuropean {
                    Text("威廉希尔归档："+values.map { String(format:"%.2f",$0) }.joined(separator:" / "))
                    Text("原采样时点未核验，不能当作赛前临近报价。") .font(.caption).foregroundStyle(.secondary)
                }
                if let p=record.latestAsian {
                    Text("澳门："+MarketStagesView.asian(p.asian))
                    Text("采样：\(p.capturedAt.formatted())；来源初盘时间未公开。").font(.caption).foregroundStyle(.secondary)
                }
                if let message=record.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("威廉希尔赛前欧赔曲线") {
                let cutoff=record.kickoff?.addingTimeInterval(-7200) ?? .distantPast
                let points=record.samples.filter { $0.european.count==3 && $0.capturedAt<cutoff }
                if points.count<2 { Text("不足两次赛前真实采样，暂不能画走势曲线；赛后归档报价不补入曲线。") .font(.caption).foregroundStyle(.secondary) }
                else {
                    Chart {
                        ForEach(points,id:\.capturedAt) { point in
                            ForEach(0..<3,id:\.self) { index in
                                LineMark(x:.value("采样时间",point.capturedAt),y:.value("欧赔",point.european[index]))
                                    .foregroundStyle(by:.value("方向",["胜","平","负"][index]))
                            }
                        }
                    }.frame(height:190)
                }
            }
            Section("澳门赛前亚盘曲线") {
                let cutoff=record.kickoff?.addingTimeInterval(-7200) ?? .distantPast
                let points=record.samples.filter { $0.asian != nil && $0.capturedAt<cutoff }
                if points.count<2 { Text("不足两次赛前真实采样，暂不能画走势曲线；赛后归档报价不补入曲线。") .font(.caption).foregroundStyle(.secondary) }
                else {
                    Chart(points,id:\.capturedAt) { point in
                        LineMark(x:.value("采样时间",point.capturedAt),y:.value("主队让球",point.asian!.line))
                    }.frame(height:160)
                    Chart(points,id:\.capturedAt) { point in
                        LineMark(x:.value("采样时间",point.capturedAt),y:.value("水位",point.asian!.homeWater)).foregroundStyle(by:.value("方向","主水"))
                        LineMark(x:.value("采样时间",point.capturedAt),y:.value("水位",point.asian!.awayWater)).foregroundStyle(by:.value("方向","客水"))
                    }.frame(height:160)
                }
            }
        }.navigationTitle("\(record.number)场走势").navigationBarTitleDisplayMode(.inline)
    }
}
