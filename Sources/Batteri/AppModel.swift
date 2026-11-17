import AppKit
import BatteriCore
import ServiceManagement
import SwiftUI

enum Defaults {
    static let includeFamily = "includeFamily"
    static let showLevelInMenuBar = "showLevelInMenuBar"
    static let refreshMinutes = "refreshMinutes"
}

/// Owns the store and the background refresh, and is shared by every window.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store: BatteryStore
    let engine: EngineCommand?
    let account = Account.standard()
    private let sampleAppleID: String?

    /// The signed-in Apple Account, if any.
    var appleID: String? { sampleAppleID ?? account.appleID }
    private var timer: Task<Void, Never>?

    /// `sample` replaces the engine with fixed devices, for screenshots.
    init(sample: [Device]? = nil) {
        sampleAppleID = sample == nil ? nil : "anna@example.com"
        UserDefaults.standard.register(defaults: [
            Defaults.includeFamily: false,
            Defaults.showLevelInMenuBar: false,
            Defaults.refreshMinutes: 15,
        ])
        let command = Engine.locate()
        engine = command
        if let sample {
            store = BatteryStore { _ in sample }
        } else {
            store = BatteryStore { includeFamily in
                guard let command else { throw EngineError.notFound }
                return try await Engine(command: command).devices(includeFamily: includeFamily)
            }
        }
    }

    var includeFamily: Bool { UserDefaults.standard.bool(forKey: Defaults.includeFamily) }

    var refreshInterval: TimeInterval {
        TimeInterval(max(5, UserDefaults.standard.integer(forKey: Defaults.refreshMinutes)) * 60)
    }

    func refresh() async {
        await store.refresh(includeFamily: includeFamily)
    }

    /// Refreshes now and then on a schedule. Safe to call again when settings change.
    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }

    func signOut() {
        try? account.signOut()
        store.reset()
    }

    func showSettings() {
        SettingsWindow.shared.show(model: self)
    }

    func showSignIn() {
        guard let engine else { return }
        SignInWindow.shared.show(engine: engine) { [weak self] in
            Task { await self?.refresh() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshots"),
           CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                await Snapshots.write(to: directory)
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--check-settings") {
            // Opens Settings the way the menu does and reports whether a window came up.
            Task { @MainActor in
                AppModel.shared.showSettings()
                try? await Task.sleep(for: .seconds(1))
                let window = NSApp.windows.first { $0.title == "Batteri Settings" }
                print("visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false) "
                    + "active=\(NSApp.isActive) size=\(window?.frame.size ?? .zero)")
                NSApp.terminate(nil)
            }
            return
        }
        Task { @MainActor in
            let model = AppModel.shared
            await model.refresh()
            // A menu bar app has no window of its own, so a new user would see nothing
            // happen. Greet them with the sign-in window the first time.
            if model.store.phase == .needsLogin {
                model.showSignIn()
            }
            model.start()
        }
    }
}
