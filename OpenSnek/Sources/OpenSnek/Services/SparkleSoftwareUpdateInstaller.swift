import Foundation
import OpenSnekAppSupport
@preconcurrency import Sparkle

/// Installs release updates through Sparkle.
@MainActor final class SparkleSoftwareUpdateInstaller: NSObject, SoftwareUpdateInstalling {
    static let shared = SparkleSoftwareUpdateInstaller()

    private let serviceCoordinator: BackgroundServiceCoordinator
    private var updaterController: SPUStandardUpdaterController?
    private var updaterDelegate: OpenSnekSparkleUpdaterDelegate?

    init(serviceCoordinator: BackgroundServiceCoordinator = .shared) {
        self.serviceCoordinator = serviceCoordinator
        super.init()
    }

    func installLatestRelease(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) async throws {
        guard Self.isConfigured() else { throw NSError(domain: "OpenSnek.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Automatic update installation is not configured for this build."]) }

        guard !OpenSnekProcessRole.current.isService else { throw NSError(domain: "OpenSnek.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "Open the OpenSnek window to install updates."]) }
        statusHandler(.checking)
        let processes = SoftwareUpdateSession.Processes(otherRunningPIDs: { self.serviceCoordinator.otherRunningApplicationPIDs }, terminateOthers: { self.serviceCoordinator.terminateOtherRunningApplicationInstances() })
        try await serviceCoordinator.softwareUpdateSession.run(processes: processes) {
            let updaterController = self.makeUpdaterControllerIfNeeded(statusHandler: statusHandler)
            self.updaterDelegate?.statusHandler = statusHandler
            updaterController.checkForUpdates(nil)
        }
    }

    private static func isConfigured(bundle: Bundle = .main) -> Bool {
        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }

    private func makeUpdaterControllerIfNeeded(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) -> SPUStandardUpdaterController {
        if let updaterController { return updaterController }

        let updaterDelegate = OpenSnekSparkleUpdaterDelegate(serviceCoordinator: serviceCoordinator, statusHandler: statusHandler)
        let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
        self.updaterDelegate = updaterDelegate
        self.updaterController = updaterController
        return updaterController
    }
}

/// Coordinates Sparkle lifecycle callbacks with OpenSnek runtime state.
@MainActor private final class OpenSnekSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let serviceCoordinator: BackgroundServiceCoordinator
    var statusHandler: @MainActor (SoftwareUpdateInstallState) -> Void

    init(serviceCoordinator: BackgroundServiceCoordinator, statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) {
        self.serviceCoordinator = serviceCoordinator
        self.statusHandler = statusHandler
    }

    func bestValidUpdate(in appcast: SUAppcast, for _: SPUUpdater) -> SUAppcastItem? {
        guard Self.shouldForceLatestUpdateForDryRun else { return nil }
        return appcast.items.first
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        guard Self.shouldForceLatestUpdateForDryRun else { return nil }
        return ReleaseUpdateChecker.dryRunAppcastURL().absoluteString
    }

    func updater(_: SPUUpdater, willDownloadUpdate _: SUAppcastItem, with _: NSMutableURLRequest) { statusHandler(.downloading(received: 0, expected: nil)) }

    func updater(_: SPUUpdater, didDownloadUpdate _: SUAppcastItem) { statusHandler(.extracting(progress: nil)) }

    func updater(_: SPUUpdater, willExtractUpdate _: SUAppcastItem) { statusHandler(.extracting(progress: nil)) }

    func updater(_: SPUUpdater, didExtractUpdate _: SUAppcastItem) { statusHandler(.readyToInstall) }

    func updater(_: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate _: SUAppcastItem, state _: SPUUserUpdateState) { if choice == .install { statusHandler(.installing) } }

    func updater(_: SPUUpdater, willInstallUpdate _: SUAppcastItem) {
        AppLog.info("Update", "Sparkle will install update")
        statusHandler(.installing)
    }

    func updaterWillRelaunchApplication(_: SPUUpdater) { serviceCoordinator.softwareUpdateSession.willRelaunch() }

    func updater(_: SPUUpdater, didAbortWithError error: any Error) {
        statusHandler(.failed(error.localizedDescription))
        serviceCoordinator.softwareUpdateSession.finish(error: error)
    }

    func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: (any Error)?) { serviceCoordinator.softwareUpdateSession.finish(error: error) }

    private static var shouldForceLatestUpdateForDryRun: Bool { ReleaseUpdateChecker.currentBuildChannel() == .dev && DeveloperRuntimeOptions.releaseUpdateDryRunEnabled() }
}
