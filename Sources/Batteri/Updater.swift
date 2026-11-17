import AppKit
import Sparkle
import SwiftUI

/// Automatic updates through Sparkle. The feed (appcast.xml) lives in the GitHub repository
/// and each version is a GitHub release.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// False while a check is already running.
    @Published private(set) var canCheck = false
    /// Set when a scheduled check found a new version that has not been shown yet.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var probe: ((String) -> Void)?

    /// Updates only exist for the packaged app; a bare development binary has no feed.
    var isAvailable: Bool { controller != nil }

    private override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func start() {
        controller?.startUpdater()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// Asks the feed whether there is a newer version, without showing anything.
    func probeFeed(_ report: @escaping (String) -> Void) {
        guard let controller else { return report("no feed configured") }
        probe = report
        controller.startUpdater()
        controller.updater.checkForUpdateInformation()
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.probe?("update available: \(version)") }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let reason = (error as NSError).localizedDescription
        Task { @MainActor in self.probe?("no update: \(reason)") }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let reason = (error as NSError).localizedDescription
        Task { @MainActor in self.probe?("aborted: \(reason)") }
    }

    // MARK: SPUStandardUserDriverDelegate
    //
    // Batteri has no Dock icon, so an update window that appears on its own would open
    // behind whatever the user is doing. Scheduled finds are shown as a line in the menu
    // instead; choosing it brings up Sparkle's normal window.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in
            self.availableVersion = handleShowingUpdate ? nil : version
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.availableVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.availableVersion = nil }
    }
}
