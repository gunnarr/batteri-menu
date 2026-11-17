import BatteriCore
import SwiftUI

@main
struct BatteriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model, store: model.store)
        } label: {
            MenuBarLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, store: model.store)
        }
    }
}

/// The item in the menu bar: a battery glyph, and optionally the lowest level.
struct MenuBarLabel: View {
    @ObservedObject var store: BatteryStore
    @AppStorage(Defaults.showLevelInMenuBar) private var showLevel = false

    var body: some View {
        let lowest = Presentation.lowest(in: store.devices)
        let attention = store.phase == .needsLogin || (lowest.map(Presentation.isLow) ?? false)
        HStack(spacing: 3) {
            Image(systemName: attention ? "minus.plus.batteryblock.exclamationmark" : "minus.plus.batteryblock")
            if showLevel, let lowest {
                Text(Presentation.percentText(lowest))
            }
        }
        .accessibilityLabel(accessibilityText(lowest: lowest))
    }

    private func accessibilityText(lowest: Device?) -> String {
        guard let lowest, let percent = lowest.percent else { return "Batteri" }
        return "Batteri, lowest is \(lowest.name) at \(percent) percent"
    }
}
