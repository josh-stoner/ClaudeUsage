import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(viewModel: viewModel)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                Text(viewModel.menuBarTitle)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
