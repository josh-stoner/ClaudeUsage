import SwiftUI

struct UsagePopover: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            // Purple accent stripe (color-as-wayfinding)
            Rectangle()
                .fill(Theme.purple.opacity(0.4))
                .frame(height: 1)

            tabPicker

            VStack(spacing: 0) {
                switch viewModel.selectedTab {
                case .limits: limitsView
                case .week:   weekView
                case .cost: costView
                case .patterns: patternsView
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            Spacer(minLength: 0)

            Rectangle()
                .fill(Theme.purple.opacity(0.2))
                .frame(height: 1)
            footer
        }
        .frame(width: 320)
        .frame(maxHeight: 700)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.purple)
            Text("Claude Code")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if viewModel.apiError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.gold)
            }
            Button(action: { viewModel.fetchUsage(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(UsageViewModel.Tab.allCases, id: \.self) { tab in
                let isSelected = viewModel.selectedTab == tab
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.purple : Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(isSelected ? Theme.purple.opacity(0.12) : Theme.hoverBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tagRadius))
                    .onTapGesture { viewModel.selectedTab = tab }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Plan Limits

    private var limitsView: some View {
        VStack(spacing: 6) {
            if let usage = viewModel.usage {
                if let session = usage.fiveHour {
                    usageMeter("Current session", session.timeUntilReset, session.utilization, Theme.purple,
                               tip: "Rolling 5-hour burst window")
                }
                if let weekly = usage.sevenDay {
                    usageMeter("All models", weekly.resetTimeFormatted, weekly.utilization, Theme.slate,
                               tip: "Combined usage, rolling 7 days")
                }
                if let sonnet = usage.sevenDaySonnet {
                    usageMeter("Sonnet only", sonnet.resetTimeFormatted, sonnet.utilization, Theme.green,
                               tip: "Separate Sonnet-specific quota")
                }
                if let opus = usage.sevenDayOpus {
                    usageMeter("Opus only", opus.resetTimeFormatted, opus.utilization, Theme.gold,
                               tip: "Separate Opus-specific quota")
                }
                if let cowork = usage.sevenDayCowork {
                    usageMeter("Cowork", cowork.resetTimeFormatted, cowork.utilization, Theme.coral,
                               tip: "Cowork mode, rolling 7 days")
                }
            } else if let error = viewModel.apiError {
                errorPlaceholder(error)
            } else {
                ProgressView()
                    .tint(Theme.purple)
                    .scaleEffect(0.8)
                    .padding(.top, 50)
            }
        }
    }

    private func usageMeter(_ title: String, _ subtitle: String, _ pct: Double, _ tint: Color, tip: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                infoTip(tip)
                Spacer()
                Text("\(Int(pct))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(pctColor(pct))
                Text("%")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(pctColor(pct).opacity(0.5))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.barRadius)
                        .fill(Theme.cardBg)
                    RoundedRectangle(cornerRadius: Theme.barRadius)
                        .fill(pct >= 80 ? Theme.coral : tint)
                        .frame(width: max(3, geo.size.width * pct / 100))
                }
            }
            .frame(height: 6)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(12)
        .background(Theme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .padding(.horizontal, 12)
    }

    private func pctColor(_ pct: Double) -> Color {
        if pct >= 80 { return Theme.coral }
        if pct >= 60 { return Theme.gold }
        return Theme.textPrimary
    }

    // MARK: - Week

    private var weekView: some View {
        VStack(spacing: 10) {
            if let week = viewModel.currentWeek {
                // Stats row in a card
                HStack(spacing: 0) {
                    weekStat(formatNumber(week.totalMessages), "msgs",
                             tip: "User + assistant messages")
                    dividerDot
                    weekStat("\(week.totalSessions)", "sessions",
                             tip: "Claude Code sessions started")
                    dividerDot
                    weekStat(formatNumber(week.totalToolCalls), "tools",
                             tip: "Read, Edit, Bash, Grep, etc.")
                    dividerDot
                    weekStat(formatNumber(week.totalTokens), "tokens",
                             tip: "All models combined")
                }
                .padding(.vertical, 10)
                .background(Theme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 12)

                // Bar chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY MESSAGES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    ForEach(Array(week.days.enumerated()), id: \.element.id) { _, day in
                        HStack(spacing: 8) {
                            Text(day.weekday)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 32, alignment: .leading)

                            GeometryReader { geo in
                                let ratio = week.maxDailyMessages > 0
                                    ? CGFloat(day.messageCount) / CGFloat(week.maxDailyMessages) : 0
                                RoundedRectangle(cornerRadius: Theme.barRadius)
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.purple.opacity(0.5), Theme.purple.opacity(0.7)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                            .frame(height: 14)

                            Text(formatNumber(day.messageCount))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                emptyPlaceholder("No data this week")
            }
        }
    }

    private var dividerDot: some View {
        Circle()
            .fill(Theme.textFaint)
            .frame(width: 2, height: 2)
    }

    private func weekStat(_ value: String, _ label: String, tip: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                infoTip(tip)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cost

    private var costView: some View {
        VStack(spacing: 12) {
            if let cost = viewModel.costAnalysis {
                // Big ROI number
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int(cost.roi))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.green)
                        Text("x")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.green.opacity(0.6))
                    }
                    HStack(spacing: 2) {
                        Text("ROI on $100/mo Max")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                        infoTip("Ceiling estimate. Real API usage would likely be lower — you'd optimize prompts and context if paying per-token.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 12)

                // Cost comparison
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Text("IF YOU PAID API RATES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                            .tracking(0.8)
                        infoTip("Based on published anthropic.com/pricing. Cache reads are ~63% of cost — on API you pay per read, on Max it's unlimited.")
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    costRow("Total spent", "$\(formatCost(cost.totalAPICost))",
                            tip: "Token counts from stats-cache.json (last updated by Claude Code)")
                    costRow("Daily avg", "$\(formatCost(cost.dailyAvgCost))",
                            tip: "Total ÷ \(cost.daysTracked) active days")
                    costRow("Monthly proj", "$\(formatCost(cost.monthlyProjection))",
                            tip: "Daily avg × 30. Assumes consistent usage.")
                }

                // Plan comparison
                VStack(spacing: 6) {
                    Text("PLAN COMPARISON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    planRow("API", cost.monthlyProjection, isCurrent: false)
                    planRow("Pro $20", 20, isCurrent: false)
                    planRow("Max 5x $100", 100, isCurrent: true)
                    planRow("Max 20x $200", 200, isCurrent: false)
                }

                // Per-model breakdown
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("COST BY MODEL")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                            .tracking(0.8)
                        infoTip("Includes input, output, cache read, and cache creation tokens at published API rates.")
                        Spacer()
                    }
                        .padding(.horizontal, 16)

                    ForEach(cost.modelCosts, id: \.model) { mc in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(modelColor(mc.model))
                                .frame(width: 3, height: 16)
                            Text(mc.model)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("$\(formatCost(mc.cost))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                emptyPlaceholder("No cost data")
            }
        }
    }

    private func costRow(_ label: String, _ value: String, tip: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            infoTip(tip)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
    }

    private func planRow(_ name: String, _ price: Double, isCurrent: Bool) -> some View {
        let monthly = viewModel.costAnalysis?.monthlyProjection ?? 0
        let savings = monthly - price
        return HStack {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.green)
            }
            Text(name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
            if price > 500 {
                Text("$\(formatCost(price))/mo")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.coral)
            } else {
                Text("save $\(formatCost(savings))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.green)
            }
        }
        .padding(.horizontal, 16)
    }

    private func formatCost(_ n: Double) -> String {
        if n >= 1000 { return String(format: "%.0f", n) }
        if n >= 100 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }

    // MARK: - Patterns

    private var patternsView: some View {
        VStack(spacing: 12) {
            if let stats = viewModel.stats {
                // Usage hours summary
                if let uh = viewModel.usageHours {
                    HStack(spacing: 0) {
                        weekStat(String(format: "%.1f", uh.todayHours), "today",
                                 tip: "Active hours today")
                        dividerDot
                        weekStat(String(format: "%.1f", uh.thisWeekHours), "this week",
                                 tip: "Active hours Mon–now")
                        dividerDot
                        weekStat(String(format: "%.0f", uh.totalHours), "all time",
                                 tip: "\(uh.daysActive) active days")
                    }
                    .padding(.vertical, 10)
                    .background(Theme.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 12)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.slate)
                        Text("Avg \(String(format: "%.1f", uh.avgDailyHours))h/day")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Text("across \(uh.daysActive) days")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 16)
                }

                // Hour of day heatmap
                VStack(alignment: .leading, spacing: 6) {
                    Text("PEAK HOURS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    let hours = stats.hourCounts ?? [:]
                    let maxH = hours.values.max() ?? 1

                    // Grid: 6 columns x 4 rows (0-23)
                    VStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { row in
                            HStack(spacing: 3) {
                                ForEach(0..<6, id: \.self) { col in
                                    let h = row * 6 + col
                                    let count = hours[String(h)] ?? 0
                                    let intensity = maxH > 0 ? Double(count) / Double(maxH) : 0

                                    VStack(spacing: 1) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Theme.purple.opacity(intensity * 0.8 + 0.05))
                                            .frame(height: 22)
                                        Text(hourLabel(h))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundStyle(Theme.textFaint)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 12)

                    // Peak hour callout
                    if let peak = hours.max(by: { $0.value < $1.value }) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.coral)
                            Text("Most active: \(hourLabel(Int(peak.key) ?? 0))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                            Text("(\(peak.value) sessions)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Day of week breakdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("BUSIEST DAYS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    let dowData = dayOfWeekAverages(from: stats.dailyActivity)
                    let maxAvg = dowData.map(\.avg).max() ?? 1

                    ForEach(dowData, id: \.day) { d in
                        HStack(spacing: 8) {
                            Text(d.day)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 32, alignment: .leading)

                            GeometryReader { geo in
                                let ratio = maxAvg > 0 ? CGFloat(d.avg) / CGFloat(maxAvg) : 0
                                RoundedRectangle(cornerRadius: Theme.barRadius)
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.slate.opacity(0.4), Theme.purple.opacity(0.6)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                            .frame(height: 14)

                            Text("\(d.avg)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                    }

                    Text("avg messages/day")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }
            } else {
                emptyPlaceholder("No pattern data")
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }

    private struct DayAvg {
        let day: String
        let avg: Int
    }

    private func dayOfWeekAverages(from activity: [DailyActivity]) -> [DayAvg] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var buckets: [Int: [Int]] = [:]  // weekday number -> message counts
        for a in activity {
            guard let date = formatter.date(from: a.date) else { continue }
            let wd = Calendar.current.component(.weekday, from: date) // 1=Sun
            buckets[wd, default: []].append(a.messageCount)
        }

        let order = [2, 3, 4, 5, 6, 7, 1] // Mon-Sun
        let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]

        return order.map { wd in
            let vals = buckets[wd] ?? [0]
            return DayAvg(day: names[wd]!, avg: vals.reduce(0, +) / max(vals.count, 1))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let t = viewModel.lastAPIRefresh {
                Text(t.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Components

    private func infoTip(_ text: String) -> some View {
        InfoTipView(text: text)
    }

    private func modelColor(_ name: String) -> Color {
        switch name {
        case "Opus":   Theme.purple
        case "Sonnet": Theme.slate
        case "Haiku":  Theme.green
        default:       Theme.textMuted
        }
    }

    private func errorPlaceholder(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(Theme.gold)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func emptyPlaceholder(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 50)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1e9) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }

    private func formatISODate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"
        return display.string(from: date)
    }
}

// MARK: - Info Tip (hover popover)

struct InfoTipView: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 9))
            .foregroundStyle(Theme.textFaint)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Theme.bg)
            }
    }
}
