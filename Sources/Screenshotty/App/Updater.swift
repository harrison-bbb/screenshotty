import AppKit
@preconcurrency import Sparkle
@preconcurrency import UserNotifications

/// Checks GitHub for new releases with Sparkle and offers to install them.
///
/// Updates are signed with Screenshotty's own EdDSA key (its public half is `SUPublicEDKey` in Info.plist),
/// so Sparkle refuses anything that wasn't built by the release workflow. No paid Apple account involved.
///
/// Screenshotty lives in the menu bar, so a scheduled check that finds an update doesn't throw a window in
/// your face mid-task: it posts a notification and adds an "Update to …" item to the menu bar menu instead
/// (Sparkle calls these gentle reminders). Clicking either shows the update.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// The version waiting to be installed, if a background check found one.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController?

    /// False when running outside an app bundle (`swift run`), where there's nothing to update.
    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do {
            try controller.updater.start()
            self.controller = controller
            UNUserNotificationCenter.current().delegate = self
        } catch {
            Log.write("updater failed to start: \(error.localizedDescription)")
        }
    }

    @objc func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private func notify(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Screenshotty \(version) is available"
            content.body = "Click to see what's new and update."
            center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil))
        }
    }

    private func clearReminder() {
        availableVersion = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["update"])
    }
}

extension Updater: SPUUpdaterDelegate {
    /// `SCREENSHOTTY_FEED_URL` points a build at a local test feed. Updates still need a valid signature.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["SCREENSHOTTY_FEED_URL"]
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Show Sparkle's window right away only if it found the update as Screenshotty launched.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            Log.write("update found: \(version) shownNow=\(handleShowingUpdate)")
            guard !handleShowingUpdate, !userInitiated else { return }
            availableVersion = version
            notify(version: version)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { clearReminder() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { clearReminder() }
    }
}

extension Updater: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { Updater.shared.checkForUpdates() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Screenshotty is usually "active" while you work in an editor; show the banner anyway.
        completionHandler([.banner, .sound])
    }
}
