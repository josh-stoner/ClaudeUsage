import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(viewModel: viewModel)
        } label: {
            Text(viewModel.menuBarTitle)
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
