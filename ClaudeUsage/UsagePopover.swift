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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch viewModel.selectedTab {
                    case .limits: limitsView
                    case .week:   weekView
                    case .allTime: allTimeView
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            Rectangle()
                .fill(Theme.purple.opacity(0.2))
                .frame(height: 1)
            footer
        }
        .frame(width: 320, height: 420)
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

    // MARK: - All Time

    private var allTimeView: some View {
        VStack(spacing: 12) {
            if let stats = viewModel.stats {
                // Top stats
                HStack(spacing: 0) {
                    weekStat(formatNumber(stats.totalMessages), "messages", tip: "All-time total")
                    dividerDot
                    weekStat("\(stats.totalSessions)", "sessions", tip: "All-time total")
                }
                .padding(.vertical, 10)
                .background(Theme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 12)

                // Model cards
                VStack(spacing: 6) {
                    Text("TOKEN USAGE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    ForEach(Array(stats.modelUsage.sorted { $0.value.outputTokens > $1.value.outputTokens }), id: \.key) { model, usage in
                        HStack {
                            // Left accent stripe
                            RoundedRectangle(cornerRadius: 2)
                                .fill(modelColor(UsageViewModel.shortModel(model)))
                                .frame(width: 3, height: 28)

                            Text(UsageViewModel.shortModel(model))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 52, alignment: .leading)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("out")
                                        .foregroundStyle(Theme.textFaint)
                                    Text(formatNumber(usage.outputTokens))
                                        .foregroundStyle(Theme.textSecondary)
                                    infoTip("Tokens generated by Claude")
                                }
                                HStack(spacing: 4) {
                                    Text("cache")
                                        .foregroundStyle(Theme.textFaint)
                                    Text(formatNumber(usage.cacheReadInputTokens))
                                        .foregroundStyle(Theme.textSecondary)
                                    infoTip("Tokens served from prompt cache")
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Theme.cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius)
                                .stroke(Theme.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .padding(.horizontal, 12)
                    }
                }

                Text("Since \(formatISODate(stats.firstSessionDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 4)
            }
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
