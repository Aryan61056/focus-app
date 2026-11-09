import AppKit
import Sparkle
import FocusUI

/// Updates for an installed copy of Hushd, with Sparkle doing the network, the signature check and the swap, and Hushd drawing all of it
/// (this is Sparkle's user driver, so there are no Sparkle windows). Once a day it asks the feed for a newer version, downloads it quietly,
/// and offers "Restart to update" on Today, in the menu bar and in Settings, never during a session. An update is only accepted when it is
/// signed with the key whose public half is in Info.plist (SUPublicEDKey); a changed or unsigned download is thrown away.
///
/// Only builds made for handing out run it (they carry SUFeedURL, and no FocusBuildSource): a dev build still updates from its own folder
/// through Updater.swift.
@MainActor final class SparkleUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    private let controller: SessionController
    let model = ReleaseUpdates()
    private var updater: SPUUpdater?
    /// Set once an update is downloaded and checked: calling it installs and reopens Hushd.
    private var installNow: (() -> Void)?
    private var postponed: (() -> Void)?
    private var postponeTimer: Timer?
    private var version = ""
    private var expected: UInt64 = 0, received: UInt64 = 0

    init(controller: SessionController) { self.controller = controller }

    /// Whether this build is meant to update from a feed.
    static var applies: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["SUFeedURL"] as? String)?.isEmpty == false && info["FocusBuildSource"] == nil && info["SUPublicEDKey"] != nil
    }

    func start() {
        guard updater == nil else { return }
        let u = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        updater = u
        do { try u.start() } catch { model.set(.failed("Updates aren\u{2019}t available in this copy.")); controller.releaseUpdates = model; return }
        u.automaticallyDownloadsUpdates = true
        model.setAutomaticQuietly(u.automaticallyChecksForUpdates)
        model.onCheck = { [weak self] in self?.updater?.checkForUpdates() }
        model.onInstall = { [weak self] in self?.restart() }
        model.onSetAutomatic = { [weak self] on in self?.updater?.automaticallyChecksForUpdates = on }
        controller.releaseUpdates = model
        controller.onInstallUpdate = { [weak self] _ in self?.restart() }
        controller.onCheckUpdates = { [weak self] in self?.updater?.checkForUpdates() }
    }

    func check() { updater?.checkForUpdates() }

    /// "Restart to update": only between sessions.
    func restart() {
        guard !controller.isActive else { return }
        installNow?()
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Daily checks are on in Info.plist; nothing about this Mac is ever sent with them.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { model.set(.checking) }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        version = appcastItem.displayVersionString
        model.set(.found(version))
        reply(.install)   // downloads now, installs when the person restarts
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        model.checked(); model.set(.upToDate); acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        model.set(.failed(Self.words(for: error))); acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { expected = 0; received = 0; model.set(.downloading(version, nil)) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        if expected > 0 { model.set(.downloading(version, min(1, Double(received) / Double(expected)))) }
    }
    func showDownloadDidStartExtractingUpdate() { model.set(.preparing(version)) }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installNow = { reply(.install) }
        ready()
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { model.set(.installing) }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {
        switch model.state { case .checking, .found, .downloading, .preparing: model.set(.idle); default: break }
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        // FOCUS_FEED_URL points a test copy at a local server; it must be an http(s) address. Otherwise the Info.plist feed is used.
        if let s = ProcessInfo.processInfo.environment["FOCUS_FEED_URL"], let u = URL(string: s), ["http", "https"].contains(u.scheme) { return s }
        return nil
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesFor updateItem: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { if error == nil { model.checked() } }
    /// A quiet download finished: Sparkle would install it when Hushd quits; the button installs it now.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        version = item.displayVersionString
        installNow = immediateInstallHandler
        ready()
        return true
    }
    /// Sparkle is about to relaunch into the new version. Not while a session runs: it waits, then goes.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard controller.isActive else { return false }
        postponed = installHandler
        postponeTimer?.invalidate()
        postponeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.controller.isActive, let go = self.postponed else { return }
                self.postponed = nil; self.postponeTimer?.invalidate(); go()
            }
        }
        return true
    }

    // MARK: private

    private func ready() {
        model.checked(); model.set(.ready(version))
        // The same offer the Today notice, the menu bar row and Settings already know how to show (only between sessions).
        controller.setUpdateOffer(UpdateOffer(buildID: version, sourcePath: ""))
    }

    static func words(for error: Error) -> String {
        let e = error as NSError
        if e.domain == NSURLErrorDomain { return "Couldn\u{2019}t reach the update server. Hushd will try again." }
        if e.domain == SUSparkleErrorDomain, e.code == Int(SUError.insufficientSigningError.rawValue) || e.code == Int(SUError.installationError.rawValue) {
            return "An update was found but couldn\u{2019}t be checked, so it was not installed."
        }
        return "Couldn\u{2019}t check for updates. Hushd will try again."
    }
}
