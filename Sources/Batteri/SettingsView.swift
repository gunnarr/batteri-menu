import BatteriCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: BatteryStore
    @ObservedObject var updater = Updater.shared

    @AppStorage(Defaults.includeFamily) private var includeFamily = false
    @AppStorage(Defaults.showLevelInMenuBar) private var showLevel = false
    @AppStorage(Defaults.refreshMinutes) private var refreshMinutes = 15
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Show lowest level in menu bar", isOn: $showLevel)
                Picker("Refresh", selection: $refreshMinutes) {
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                }
                .onChange(of: refreshMinutes) { _, _ in model.start() }
            }

            Section {
                Toggle("Include family members’ devices", isOn: $includeFamily)
                    .onChange(of: includeFamily) { _, _ in Task { await model.refresh() } }
            } footer: {
                Text("Shows the devices of people in your Family Sharing group who share their location with you.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("iCloud") {
                if store.phase == .needsLogin || model.appleID == nil {
                    LabeledContent("Account") {
                        Button("Sign In…") { model.showSignIn() }
                            .disabled(model.engine == nil)
                    }
                } else {
                    LabeledContent("Account") {
                        Text(model.appleID ?? "").textSelection(.enabled)
                    }
                    Button("Sign Out…", role: .destructive) { confirmSignOut = true }
                }
            }

            Section {
                LabeledContent("Version", value: version)
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }
                    ))
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
                Link("Batteri on GitHub", destination: URL(string: "https://github.com/gunnarr/batteri-menu")!)
            } footer: {
                Text("Batteri is an independent project and is not affiliated with Apple. It relies on an unofficial iCloud interface that may stop working.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Sign out of iCloud in Batteri?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved session is removed from this Mac. If you use the batteri command-line tool, it is signed out too.")
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Couldn’t change the login item. Move Batteri to the Applications folder and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// The Settings window. A menu bar app has no main menu and is not the active app when its
/// menu is clicked, so SwiftUI's own Settings scene does not reliably come to the front.
/// Owning the window makes sure it opens, and opens in front.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = SettingsView(model: model, store: model.store)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Batteri Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.bringToFront()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
