import SwiftUI

struct SettingsView: View {
    @AppStorage("alertThreshold1")     private var threshold1: Int = 80
    @AppStorage("alertThreshold2")     private var threshold2: Int = 95
    @AppStorage("pollIntervalMinutes") private var pollMinutes: Int = 5
    @AppStorage("menuBarFormat")       private var menuBarFormat: String = "percentAndTime"

    var body: some View {
        Form {
            Section("Alerts") {
                Picker("Warning threshold", selection: $threshold1) {
                    ForEach([60, 70, 75, 80, 85, 90], id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
                }
                .pickerStyle(.menu)

                Picker("Critical threshold", selection: $threshold2) {
                    ForEach([80, 85, 90, 95, 99], id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
                }
                .pickerStyle(.menu)

                Text("Alerts fire when the 5-hour window crosses each threshold. Enable the bell icon in the app footer to receive them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Polling") {
                Picker("Refresh interval", selection: $pollMinutes) {
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.menu)

                Text("How often the app checks the Anthropic usage API. The interval doubles on HTTP 429 and resets on the next successful response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Display format", selection: $menuBarFormat) {
                    Text("Percent + time   73% 3:12").tag("percentAndTime")
                    Text("Percent only   73%").tag("percentOnly")
                    Text("Icon only   ⊙").tag("iconOnly")
                }
                .pickerStyle(.radioGroup)

                Text("Changes take effect immediately. Urgency color (gold ≥60%, red ≥80%) applies to all formats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding(.vertical, 8)
    }
}
