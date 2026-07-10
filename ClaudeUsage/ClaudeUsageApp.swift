import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("menuBarFormat") private var menuBarFormat = "percentAndTime"

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(viewModel: viewModel)
        } label: {
            menuBarLabel
                .foregroundStyle(menuBarForeground)
        }
        .menuBarExtraStyle(.window)

        // ⌘, opens the settings window
        Settings {
            SettingsView()
        }
    }

    // MARK: - Adaptive menu bar label

    @ViewBuilder
    private var menuBarLabel: some View {
        switch menuBarFormat {
        case "percentOnly":
            if let pct = viewModel.fiveHourPercent {
                Text("\(pct)%")
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(.caption, design: .monospaced))
            }
        case "iconOnly":
            Image(systemName: "gauge.medium")
                .font(.system(size: 14))
        default:  // percentAndTime
            if let pct = viewModel.fiveHourPercent {
                let label = viewModel.fiveHourCountdown.map { "\(pct)% \($0)" } ?? "\(pct)%"
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    // Map the ViewModel's urgency enum to a concrete color.
    // .primary lets macOS choose the appropriate label color in both light/dark menu bar.
    private var menuBarForeground: Color {
        switch viewModel.menuBarColor {
        case .normal:   return .primary
        case .warning:  return Theme.gold
        case .critical: return Theme.coral
        }
    }
}
