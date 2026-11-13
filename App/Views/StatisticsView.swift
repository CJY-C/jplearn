import SwiftUI
import LearningCore

struct StatisticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var statistics: LearningStatistics?
    @State private var failure: String?
    @State private var dayCount = 7
    @State private var skill = Skill.reading

    var body: some View {
        List {
            if let stats = statistics {
                overview(stats)
                timeSection(stats)
                progressSection(stats)
                retentionSection(stats)
            } else if let failure = failure {
                Text(failure).foregroundColor(.secondary)
            } else {
                ProgressView("整理学习记录…")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("学习统计").navigationBarTitleDisplayMode(.inline)
        .task(id: model.events.count) {
            let pack = model.pack, events = model.events
            let result = await Task.detached(priority: .userInitiated) {
                Result { try LearningStatistics.make(pack: pack, events: events) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let value): statistics = value; failure = nil
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }

    private func overview(_ stats: LearningStatistics) -> some View {
        Section {
            HStack {
                statistic(StudyTime.clock(stats.totalSeconds), "累计学习")
                Spacer()
                statistic("\(stats.activeDays)", "学习天数")
                Spacer()
                statistic("\(stats.dueCount)", "待复习")
            }.padding(.vertical, 6).accessibilityIdentifier("statistics.overview")
            HStack {
                Text("自评回想率")
                Spacer()
                Text(stats.recallRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "暂无记录")
                    .monospacedDigit().foregroundColor(.secondary)
            }
        } footer: {
            Text("累计时间只计实际学习。回想率含首次练习，以独立想起（含“费力”）的次数计算；提示后作答不计入想起。")
        }
    }

    private func statistic(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundColor(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func timeSection(_ stats: LearningStatistics) -> some View {
        Section {
            Picker("时间范围", selection: $dayCount) {
                Text("近 7 天").tag(7)
                Text("近 30 天").tag(30)
            }.pickerStyle(.segmented)
            let days = Array(stats.days.suffix(dayCount))
            StudyTimeBars(days: days)
            Text("这 \(dayCount) 天学习了 \(StudyTime.clock(days.reduce(0) { $0 + $1.seconds }))")
                .font(.subheadline).foregroundColor(.secondary)
        } header: { Text("学习时间") }
    }

    private func progressSection(_ stats: LearningStatistics) -> some View {
        Section {
            ForEach(stats.levels) { level in
                DisclosureGroup {
                    progressRow("词义", level.meaning)
                    progressRow("读音", level.reading)
                    progressRow("表达理解", level.grammar)
                    progressRow("阅读理解", level.passages, reading: true)
                    Text("字音义都记得：\(level.linkedWords) 个词义目标")
                        .font(.caption).foregroundColor(.secondary)
                } label: {
                    HStack {
                        Text(level.id).font(.headline)
                        Spacer()
                        Text(level.meaning.total == 0 ? "内容待补充" : "词义 \(level.meaning.remembered) / \(level.meaning.total)")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }.accessibilityIdentifier("statistics.level.\(level.id)")
            }
        } header: { Text("内容进度") } footer: {
            Text("按当前内容包统计，词义和读音分别计算。“记得”指最近一次独立选择“记得”或“熟悉”；遗忘后会回落。一个词的不同义项分别计数，共用的读音只计一次。")
        }
    }

    private func progressRow(_ title: String, _ progress: LearningProgress, reading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(progress.total == 0 ? "内容待补充" : "\(progress.remembered) / \(progress.total)")
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                Text(reading ? "已读 \(progress.practiced) 篇 · 最近独立答对 \(progress.remembered) 篇" :
                        "练过 \(progress.practiced) 项 · 最近独立记得 \(progress.remembered) 项")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    private func retentionSection(_ stats: LearningStatistics) -> some View {
        Section {
            Picker("复习能力", selection: $skill) {
                Text("词义").tag(Skill.meaning)
                Text("读音").tag(Skill.reading)
                Text("表达").tag(Skill.grammar)
            }.pickerStyle(.segmented).accessibilityIdentifier("statistics.skill")
            if let forecast = stats.forecasts.first(where: { $0.skill == skill }), !forecast.points.isEmpty {
                RetentionChart(points: forecast.points)
                Text("依据 \(forecast.cardCount) 项已练内容的复习记录")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("完成这类练习后，会显示记忆保持的估计趋势。")
                    .font(.callout).foregroundColor(.secondary).padding(.vertical, 14)
                    .accessibilityIdentifier("statistics.emptyForecast")
            }
        } header: { Text("遗忘趋势") } footer: {
            Text("FSRS 模型估计 · 假设从现在起不再复习。纵轴为预计回想概率，横轴为经过天数。曲线不是实际测得的成绩，复习后会随记录更新。")
        }
    }
}

private struct StudyTimeBars: View {
    let days: [DailyStudy]
    private var peak: Double { max(60, days.map(\.seconds).max() ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最高 \(Int(ceil(peak / 60))) 分钟 / 天").font(.caption).foregroundColor(.secondary)
            HStack(alignment: .bottom, spacing: days.count > 7 ? 3 : 10) {
                ForEach(days) { day in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(height: CGFloat(day.seconds / peak) * 100)
                    }.frame(maxWidth: .infinity).frame(height: 100)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(day.date, style: .date) + Text("，学习 \(StudyTime.clock(day.seconds))，练习 \(day.reviews) 次"))
                }
            }.overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1) }
            HStack {
                if let first = days.first { Text(first.date, format: .dateTime.month().day()) }
                Spacer()
                Text("今天")
            }.font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 6).accessibilityIdentifier("statistics.timeBars")
    }
}

private struct RetentionChart: View {
    let points: [RetentionPoint]
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack { Text("100%"); Spacer(); Text("0%") }
                    .font(.caption2).foregroundColor(.secondary).frame(height: 120)
                GeometryReader { proxy in
                    let width = proxy.size.width, height = proxy.size.height
                    Path { path in
                        for fraction in [0.0, 0.5, 1.0] {
                            let y = height * fraction
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                        }
                    }.stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let position = CGPoint(x: width * Double(point.day) / 30,
                                                   y: height * (1 - point.probability))
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                    }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }.frame(height: 120)
            }
            HStack { Text("现在"); Spacer(); Text("15 天"); Spacer(); Text("30 天") }
                .font(.caption).foregroundColor(.secondary).padding(.leading, 36)
        }.padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("预计记忆保持")
            .accessibilityValue(points.map { "\($0.day) 天：\(Int(($0.probability * 100).rounded()))%" }.joined(separator: "，"))
            .accessibilityIdentifier("statistics.retentionChart")
    }
}
