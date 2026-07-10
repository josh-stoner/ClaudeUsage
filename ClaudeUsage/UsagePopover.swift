import SwiftUI

struct UsagePopover: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("appearance") private var isDark = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            header

            // Chroma-header stripe — gradient + glow for R4 richness
            Rectangle()
                .fill(LinearGradient(
                    colors: [chromaAccent, chromaAccent.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 2)
                .shadow(color: chromaAccent.opacity(0.65), radius: 4, x: 0, y: 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)

            tabPicker

            VStack(spacing: 0) {
                switch viewModel.selectedTab {
                case .limits:   limitsView
                case .week:     weekView
                case .cost:     costView
                case .patterns: patternsView
                case .trends:   trendsView
                }
            }
            .id(viewModel.selectedTab)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: viewModel.selectedTab)
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
        .background {
            ZStack(alignment: .top) {
                Theme.bg
                Theme.accentWash(chromaAccent)
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.selectedTab)
            .ignoresSafeArea()
        }
    }

    // Tab → accent color (design charter: per-tab chroma wayfinding)
    private var chromaAccent: Color {
        switch viewModel.selectedTab {
        case .limits:   return Theme.purple
        case .week:     return Theme.steel
        case .cost:     return Theme.green
        case .patterns: return Theme.coral
        case .trends:   return Theme.rose
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Claude")
                    .foregroundStyle(Theme.textPrimary)
                Text("Usage")
                    .foregroundStyle(Theme.purple)
            }
            .font(.system(size: 14, weight: .heavy))
            .tracking(-0.4)

            Spacer()

            // Error indicator — subtle; full-text banner appears inline in each tab
            if viewModel.apiError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.gold)
            }

            Button(action: { isDark.toggle() }) {
                Image(systemName: isDark ? "sun.max" : "moon")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            refreshButton
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.2), value: viewModel.refreshState)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var refreshButton: some View {
        switch viewModel.refreshState {
        case .idle:
            Button(action: { viewModel.fetchUsage(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

        case .refreshing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.green)
                .transition(.opacity)

        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.coral)
                .transition(.opacity)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(UsageViewModel.Tab.allCases, id: \.self) { tab in
                let isSelected = viewModel.selectedTab == tab
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? chromaAccent : Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.tagRadius)
                                .fill(chromaAccent.opacity(0.16))
                                .matchedGeometryEffect(id: "selectedPill", in: tabNamespace)
                                .shadow(color: chromaAccent.opacity(0.35), radius: 4)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.tagRadius)
                                .fill(Theme.hoverBg)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            viewModel.selectedTab = tab
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Inline error banner (replaces full-page error placeholder)

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.gold)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Plan Limits

    private var limitsView: some View {
        VStack(spacing: 6) {
            // Inline error banner — shown above meters, doesn't replace them
            if let error = viewModel.apiError {
                errorBanner(error)
            }

            if viewModel.usage != nil {
                // Sort meters by utilization descending — most urgent first
                ForEach(sortedUsageBuckets) { bucket in
                    usageMeter(bucket)
                }
                // Overage billing card — only shown when the feature is active on the account
                if let extra = viewModel.usage?.extraUsage, extra.isEnabled {
                    extraUsageCard(extra)
                }
            } else {
                skeletonMeters
            }
        }
    }

    // Sorted usage meters (descending utilization = most urgent first)
    private var sortedUsageBuckets: [MeterBucket] {
        guard let usage = viewModel.usage else { return [] }
        var buckets: [MeterBucket] = []
        if let b = usage.fiveHour          { buckets.append(.init("fiveHour",           "Current session", b.timeUntilReset,    b.utilization, Theme.purple,   "Rolling 5-hour burst window")) }
        if let b = usage.sevenDay          { buckets.append(.init("sevenDay",            "All models",      b.resetTimeFormatted, b.utilization, Theme.steel,    "Combined usage, rolling 7 days")) }
        if let b = usage.sevenDaySonnet    { buckets.append(.init("sevenDaySonnet",     "Sonnet only",     b.resetTimeFormatted, b.utilization, Theme.green,    "Separate Sonnet-specific quota")) }
        if let b = usage.sevenDayOpus      { buckets.append(.init("sevenDayOpus",       "Opus only",       b.resetTimeFormatted, b.utilization, Theme.gold,     "Separate Opus-specific quota")) }
        if let b = usage.sevenDayCowork    { buckets.append(.init("sevenDayCowork",     "Cowork",          b.resetTimeFormatted, b.utilization, Theme.coral,    "Cowork mode, rolling 7 days")) }
        if let b = usage.sevenDayOauthApps { buckets.append(.init("sevenDayOauthApps",  "OAuth apps",     b.resetTimeFormatted, b.utilization, Theme.lavender, "Third-party OAuth app usage, rolling 7 days")) }
        return buckets.sorted { $0.utilization > $1.utilization }
    }

    private struct MeterBucket: Identifiable {
        let key: String
        let title: String; let subtitle: String; let utilization: Double
        let tint: Color; let tip: String
        var id: String { title }
        init(_ key: String, _ title: String, _ subtitle: String, _ utilization: Double, _ tint: Color, _ tip: String) {
            self.key = key; self.title = title; self.subtitle = subtitle; self.utilization = utilization
            self.tint = tint; self.tip = tip
        }
    }

    // Skeleton cards shown while loading (No spinner — charter Never-Again rule #4)
    private var skeletonMeters: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.textFaint.opacity(0.25))
                            .frame(width: CGFloat([90, 70, 80][i % 3]), height: 11)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.textFaint.opacity(0.2))
                            .frame(width: 42, height: 22)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.textFaint.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.textFaint.opacity(0.15))
                        .frame(width: 100, height: 9)
                }
                .padding(12)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 12)
            }
        }
    }

    private func usageMeter(_ bucket: MeterBucket) -> some View {
        let sparkValues = viewModel.usageHistory.compactMap { $0.buckets[bucket.key] }
        let burnRate: BurnRate? = bucket.key == "fiveHour" ? viewModel.burnRate(for: "fiveHour") : nil
        let resetDate = viewModel.usage?.fiveHour?.resetDate

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(bucket.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                infoTip(bucket.tip)
                Spacer()
                // Mini sparkline — shown once we have enough history points
                if sparkValues.count >= 3 {
                    Sparkline(values: sparkValues, tint: bucket.tint)
                        .padding(.trailing, 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                }
                Text("\(Int(bucket.utilization))")
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(pctColor(bucket.utilization))
                    .contentTransition(.numericText(value: bucket.utilization))
                    .animation(.snappy, value: bucket.utilization)
                Text("%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pctColor(bucket.utilization).opacity(0.5))
            }

            // Progress bar — gradient fill + accent glow (R4)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    let barTint  = bucket.utilization >= 80 ? Theme.coral : bucket.tint
                    let fillW    = max(3, geo.size.width * bucket.utilization / 100)
                    Capsule()
                        .fill(Theme.meterFill(barTint))
                        .frame(width: fillW)
                        .shadow(color: barTint.opacity(bucket.utilization > 50 ? 0.55 : 0),
                                radius: 5, x: 0, y: 0)
                        .animation(.snappy, value: bucket.utilization)
                }
            }
            .frame(height: 6)

            // Burn-rate caption (5h only) or standard reset-time subtitle
            if let br = burnRate {
                Text(br.caption(resetDate: resetDate))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            } else {
                Text(bucket.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .cardDepth()
        .hoverLift()
        .padding(.horizontal, 12)
    }

    // Overage billing card — gold accent, billing framing (not a rate limit)
    private func extraUsageCard(_ extra: ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("OVERAGE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .tracking(0.8)
                infoTip("Billed overage credits beyond your plan quota. Monthly balance, not a rate limit.")
                Spacer()
                if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                    Text("$\(formatCost(used)) / $\(formatCost(limit))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if let pct = extra.utilization {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(Theme.gold)
                            .frame(width: max(3, geo.size.width * pct / 100))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .background(Theme.gold.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .cardDepth()
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
                // Stats row
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
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .cardDepth()
                .padding(.horizontal, 12)

                // Bar chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY MESSAGES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    ForEach(Array(week.days.enumerated()), id: \.element.id) { _, day in
                        let dayHours = viewModel.dailyHoursMap[day.date] ?? 0
                        DayBarRow(
                            day: day,
                            dayHours: dayHours,
                            maxMessages: week.maxDailyMessages,
                            formatNumber: formatNumber
                        )
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
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.2)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
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
                // ROI — demoted from hero to data row (informational, not marketing)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(cost.roi))×")
                                .font(.system(size: 22, weight: .semibold))
                                .monospacedDigit()
                                .tracking(-0.4)
                                .foregroundStyle(Theme.green)
                                .contentTransition(.numericText(value: cost.roi))
                                .animation(.snappy, value: cost.roi)
                            Text("value vs API rates")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                        }
                        HStack(spacing: 2) {
                            Text("ceiling estimate — you'd optimize prompts if paying per-token")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textFaint)
                            infoTip("Real API usage would likely be lower. Cache reads are ~63% of cost — on Max they're unlimited.")
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .cardDepth()
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
                            tip: "Total ÷ \(cost.daysTracked) calendar days (first session to today)")
                    costRow("Monthly proj", "$\(formatCost(cost.monthlyProjection))",
                            tip: "Daily avg × 30. Based on calendar span, not just active days.")
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
                        infoTip("Priced by model family (Opus/Sonnet/Haiku) at published API rates.")
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
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                emptyPlaceholder("No cost data yet")
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
                .monospacedDigit()
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
                    .monospacedDigit()
                    .foregroundStyle(Theme.coral)
            } else {
                Text("save $\(formatCost(savings))")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.green)
            }
        }
        .padding(.horizontal, 16)
    }

    private func formatCost(_ n: Double) -> String {
        if n >= 1000 { return String(format: "%.0f", n) }
        if n >= 100  { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }

    // MARK: - Patterns

    private var patternsView: some View {
        VStack(spacing: 12) {
            if let stats = viewModel.stats {
                let historyFirst = viewModel.dailyHoursMap.keys.min()
                let statsFirst   = stats.dailyActivity.first?.date
                let displayFirst = [historyFirst, statsFirst].compactMap { $0 }.min()
                let statsLast    = stats.dailyActivity.last?.date

                if let first = displayFirst, let last = statsLast {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.steel)
                        Text("\(formatShortDate(first)) – \(formatShortDate(last))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("(\(calendarSpan(from: first)) days)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 16)
                }

                if let uh = viewModel.usageHours {
                    HStack(spacing: 0) {
                        weekStat(String(format: "%.1f", uh.todayHours), "today",     tip: "Active hours today")
                        dividerDot
                        weekStat(String(format: "%.1f", uh.thisWeekHours), "this wk", tip: "Active hours Mon–now")
                        dividerDot
                        weekStat(String(format: "%.0f", uh.totalHours), "all time",   tip: "\(uh.daysActive) active days")
                    }
                    .padding(.vertical, 10)
                    .background(Theme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .cardDepth()
                    .padding(.horizontal, 12)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.steel)
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

                    let hours  = stats.hourCounts ?? [:]
                    let maxH   = hours.values.max() ?? 1

                    VStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { row in
                            HStack(spacing: 3) {
                                ForEach(0..<6, id: \.self) { col in
                                    let h         = row * 6 + col
                                    let count     = hours[String(h)] ?? 0
                                    let intensity = maxH > 0 ? Double(count) / Double(maxH) : 0
                                    HeatmapCell(label: hourLabel(h), count: count, intensity: intensity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .cardDepth()
                    .padding(.horizontal, 12)

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
                    let maxAvg  = dowData.map(\.avg).max() ?? 1

                    ForEach(dowData, id: \.day) { d in
                        HStack(spacing: 8) {
                            Text(d.day)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 32, alignment: .leading)

                            GeometryReader { geo in
                                let ratio = maxAvg > 0 ? CGFloat(d.avg) / CGFloat(maxAvg) : 0
                                RoundedRectangle(cornerRadius: Theme.barRadius)
                                    .fill(Theme.meterFill(Theme.coral))
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                            .frame(height: 14)

                            Text("\(d.avg)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
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
                emptyPlaceholder("No pattern data yet")
            }
        }
    }

    private func calendarSpan(from firstDateStr: String) -> Int {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        guard let first = df.date(from: firstDateStr),
              let today = df.date(from: df.string(from: Date())) else { return 1 }
        return max((Calendar.current.dateComponents([.day], from: first, to: today).day ?? 0) + 1, 1)
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0  { return "12a" }
        if h < 12  { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }

    private struct DayAvg { let day: String; let avg: Int }

    private func dayOfWeekAverages(from activity: [DailyActivity]) -> [DayAvg] {
        let formatter    = DateFormatter(); formatter.dateFormat    = "yyyy-MM-dd"

        var buckets: [Int: [Int]] = [:]
        for a in activity {
            guard let date = formatter.date(from: a.date) else { continue }
            let wd = Calendar.current.component(.weekday, from: date)
            buckets[wd, default: []].append(a.messageCount)
        }

        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        return order.map { wd in
            let vals = buckets[wd] ?? [0]
            return DayAvg(day: names[wd] ?? "?", avg: vals.reduce(0, +) / max(vals.count, 1))
        }
    }

    // MARK: - Trends

    // Ordered master list matching sortedUsageBuckets keys
    private var trendBuckets: [(key: String, title: String, tint: Color)] {
        [
            ("fiveHour",          "Current session", Theme.purple),
            ("sevenDay",          "All models",      Theme.steel),
            ("sevenDaySonnet",    "Sonnet only",     Theme.green),
            ("sevenDayOpus",      "Opus only",       Theme.gold),
            ("sevenDayCowork",    "Cowork",          Theme.coral),
            ("sevenDayOauthApps", "OAuth apps",      Theme.lavender),
        ]
    }

    private var trendsView: some View {
        let active = trendBuckets.filter { viewModel.utilizationSeries(for: $0.key).count >= 2 }
        return VStack(spacing: 8) {
            if active.isEmpty {
                emptyPlaceholder("Trends build as the app polls.\nCheck back after a few refreshes.")
            } else {
                ForEach(active, id: \.key) { b in
                    trendCard(key: b.key, title: b.title, tint: b.tint)
                }
            }
        }
    }

    private func currentUtilization(for key: String) -> Double? {
        guard let u = viewModel.usage else { return nil }
        switch key {
        case "fiveHour":          return u.fiveHour?.utilization
        case "sevenDay":          return u.sevenDay?.utilization
        case "sevenDaySonnet":    return u.sevenDaySonnet?.utilization
        case "sevenDayOpus":      return u.sevenDayOpus?.utilization
        case "sevenDayCowork":    return u.sevenDayCowork?.utilization
        case "sevenDayOauthApps": return u.sevenDayOauthApps?.utilization
        default:                  return nil
        }
    }

    private func trendCard(key: String, title: String, tint: Color) -> some View {
        let series    = viewModel.utilizationSeries(for: key)
        let current   = currentUtilization(for: key)
        let peak      = series.max() ?? 0
        let avg       = series.isEmpty ? 0.0 : series.reduce(0, +) / Double(series.count)
        let burnRate: BurnRate? = key == "fiveHour" ? viewModel.burnRate(for: "fiveHour") : nil
        let resetDate = viewModel.usage?.fiveHour?.resetDate

        return VStack(alignment: .leading, spacing: 6) {
            // Header: color chip · title · current %
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let pct = current {
                    Text("\(Int(pct))%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(pctColor(pct))
                }
            }

            // Full-size chart
            TrendChart(values: series, tint: tint)

            // Stats caption row
            HStack(spacing: 4) {
                Text("peak \(Int(peak))%")
                separatorDot
                Text("avg \(Int(avg))%")
                separatorDot
                Text("\(series.count) pts")
                if let br = burnRate {
                    separatorDot
                    Text(br.caption(resetDate: resetDate))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.textFaint)
        }
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .cardDepth()
        .hoverLift()
        .padding(.horizontal, 12)
    }

    private var separatorDot: some View {
        Text("·").foregroundStyle(Theme.textFaint.opacity(0.5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let t = viewModel.lastAPIRefresh {
                let isStale = Date.now.timeIntervalSince(t) > 600  // >10 min = stale
                HStack(spacing: 3) {
                    if isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.gold)
                    }
                    Text(t.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(isStale ? Theme.gold : Theme.textFaint)
                }
            }

            Spacer()

            // Notification toggle — opt-in, 80% / 95% alerts for 5h window
            Button(action: {
                notificationsEnabled.toggle()
                if notificationsEnabled { viewModel.requestNotificationPermission() }
            }) {
                Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(notificationsEnabled ? Theme.purple : Theme.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(notificationsEnabled ? "Alerts on (80% / 95%)" : "Usage alerts off")

            Button(action: { viewModel.exportData() }) {
                exportButtonIcon
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.exportState != .idle)
            .animation(.easeInOut(duration: 0.2), value: viewModel.exportState)
            .help("Export data")

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

    @ViewBuilder
    private var exportButtonIcon: some View {
        switch viewModel.exportState {
        case .idle:
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Theme.textMuted)
        case .exporting:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.8)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.green)
                .transition(.opacity)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.coral)
                .transition(.opacity)
        }
    }

    // MARK: - Shared components

    private func infoTip(_ text: String) -> some View {
        InfoTipView(text: text)
    }

    private func modelColor(_ name: String) -> Color {
        switch name {
        case "Opus":   return Theme.purple
        case "Sonnet": return Theme.steel
        case "Haiku":  return Theme.green
        default:       return Theme.textMuted
        }
    }

    private func emptyPlaceholder(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 50)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1e9) }
        if n >= 1_000_000     { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000         { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }

    private func formatShortDate(_ dateStr: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateStr) else { return dateStr }
        let display = DateFormatter(); display.dateFormat = "MMM d"
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

// MARK: - Heatmap Cell

struct HeatmapCell: View {
    let label: String
    let count: Int
    let intensity: Double
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.coral.opacity(intensity * 0.7 + 0.05))
                    .shadow(color: Theme.coral.opacity(intensity > 0.85 ? 0.45 : 0), radius: 4)
                    .frame(height: 22)
                if isHovering && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Day Bar Row

struct DayBarRow: View {
    let day: DailyActivity
    let dayHours: Double
    let maxMessages: Int
    let formatNumber: (Int) -> String
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(day.weekday)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geo in
                    let ratio = maxMessages > 0
                        ? CGFloat(day.messageCount) / CGFloat(maxMessages) : 0
                    RoundedRectangle(cornerRadius: Theme.barRadius)
                        .fill(Theme.meterFill(Theme.steel))
                        .frame(width: max(4, geo.size.width * ratio))
                        .shadow(color: Theme.steel.opacity(day.messageCount > 0 ? 0.35 : 0), radius: 3)
                }
                .frame(height: 14)

                Text(formatNumber(day.messageCount))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            if isHovering {
                HStack(spacing: 8) {
                    Text("\(day.sessionCount) sessions")
                    Text("\(day.toolCallCount) tools")
                    if dayHours > 0 {
                        Text(String(format: "%.1fh", dayHours))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
