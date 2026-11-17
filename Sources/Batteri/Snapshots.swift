import AppKit
import BatteriCore
import SwiftUI

/// Renders the app's views to PNG files with made-up devices: `Batteri --snapshots <dir>`.
/// Used for the README and to check the layout without clicking through the app.
@MainActor
enum Snapshots {
    static let sampleDevices: [Device] = [
        Device(name: "Magic Mouse", percent: 14, deviceClass: "Mouse", source: .bluetooth),
        Device(name: "Anna’s iPhone", model: "iPhone 16 Pro", percent: 61, lowPower: true, deviceClass: "iPhone"),
        Device(name: "Anna’s MacBook Pro", model: "MacBook Pro", percent: 78, deviceClass: "MacBookPro"),
        Device(name: "Anna’s Apple Watch", model: "Apple Watch", percent: 93, charging: true, deviceClass: "Watch"),
        Device(name: "Anna’s AirPods Pro", model: "AirPods Pro", percent: 70, online: false,
               deviceClass: "Accessory", source: .bluetoothLastKnown, left: 70, right: 85, caseLevel: 100),
        Device(name: "Old iPad", model: "iPad", percent: nil, online: false, deviceClass: "iPad"),
        Device(name: "Max’s iPhone", model: "iPhone 15", percent: 45, family: true, deviceClass: "iPhone"),
    ]

    static func write(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if CommandLine.arguments.contains("--live") {
            // The real engine and the real account: a check that the bundle works end to end.
            let live = AppModel()
            await live.refresh()
            save(PanelView(model: live, store: live.store), "panel-live", in: directory)
            return
        }

        let model = AppModel(sample: sampleDevices)
        await model.refresh()
        save(PanelView(model: model, store: model.store), "panel", in: directory)

        let signedOut = AppModel(sample: [])
        signedOut.store.reset()
        save(PanelView(model: signedOut, store: signedOut.store), "panel-signed-out", in: directory)

        let engine = EngineCommand(executable: URL(fileURLWithPath: "/usr/bin/false"))
        let signIn = SignInModel(engine: engine, appleID: nil) {}
        save(SignInView(model: signIn) {}, "sign-in", in: directory)
        let code = SignInModel(engine: engine, appleID: "anna@example.com") {}
        code.step = .code
        code.errorMessage = "That code didn’t work. A new code has been sent."
        save(SignInView(model: code) {}, "sign-in-code", in: directory)

        save(SettingsView(model: model, store: model.store), "settings", in: directory)
    }

    private static func save<Content: View>(_ view: Content, _ name: String, in directory: URL) {
        for (suffix, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            let hosting = NSHostingView(rootView: view.background(.background))
            hosting.appearance = NSAppearance(named: appearance)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let url = directory.appendingPathComponent("\(name)\(suffix).png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
