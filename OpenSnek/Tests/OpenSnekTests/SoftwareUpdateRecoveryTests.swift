import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Verifies that aborted updates restore telemetry through a fresh service connection.
@MainActor final class SoftwareUpdateRecoveryTests: XCTestCase {
    func testCanceledUpdateReconnectsToReplacementService() async throws { try await checkRecovery(fails: false) }

    func testFailedUpdateReconnectsAndPreservesUpdateError() async throws { try await checkRecovery(fails: true) }

    private func checkRecovery(fails: Bool) async throws {
        let suiteName = "SoftwareUpdateRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldHost = try BackgroundServiceHost(backend: RemoteBootstrapServiceBackend(), defaults: defaults)
        try await oldHost.start()
        let coordinator = BackgroundServiceCoordinator(defaults: defaults)
        let oldConnection = try await coordinator.connectToRunningService()
        let originalBackend = try XCTUnwrap(oldConnection)
        let newBackend = RemoteBootstrapServiceBackend()
        let newHost = try BackgroundServiceHost(backend: newBackend, defaults: defaults)
        let installer = ReplacingServiceUpdateInstaller(oldHost: oldHost, newHost: newHost, fails: fails)
        let appState = AppState(launchRole: .app, backend: originalBackend, serviceCoordinator: coordinator, softwareUpdateInstaller: installer, autoStart: false)
        defer { newHost.stop() }
        appState.deviceStore.availableUpdate = ReleaseAvailability(latestVersion: "1.4.1", releaseURL: try XCTUnwrap(URL(string: "https://example.com/release")), checkMode: .newerThanCurrent)

        await appState.runtimeController.installAvailableUpdate()

        XCTAssertFalse(appState.runtimeController.isInstallingUpdate)
        XCTAssertTrue(appState.environment.usesRemoteServiceTransport)
        XCTAssertFalse(appState.environment.backend === originalBackend, "Recovery must replace the old port-bound IPC backend")
        XCTAssertEqual(appState.deviceStore.selectedDeviceID, RemoteBootstrapServiceBackend.device.id)
        XCTAssertEqual(appState.deviceStore.state?.battery_percent, 83)
        if fails { XCTAssertEqual(appState.deviceStore.updateInstallState, .failed("Simulated download failure")) } else { XCTAssertEqual(appState.deviceStore.updateInstallState, .idle) }
        XCTAssertTrue(coordinator.backgroundServiceEnabled)

        let state = makeSnapshotState(device: RemoteBootstrapServiceBackend.device, connection: "bluetooth", batteryPercent: 79, dpiValues: [1000, 2000, 3000], activeStage: 2)
        let snapshot = SharedServiceSnapshot(devices: [RemoteBootstrapServiceBackend.device], stateByDeviceID: [RemoteBootstrapServiceBackend.device.id: state], lastUpdatedByDeviceID: [RemoteBootstrapServiceBackend.device.id: Date()])
        await newBackend.emit(.snapshot(snapshot))
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while appState.deviceStore.state?.battery_percent != 79, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(appState.deviceStore.state?.battery_percent, 79, "Recovery must restore the push subscription as well as initial state")
    }
}

/// Simulates an update that stops the service, then ends with cancellation or failure.
@MainActor private final class ReplacingServiceUpdateInstaller: SoftwareUpdateInstalling {
    let oldHost: BackgroundServiceHost
    let newHost: BackgroundServiceHost
    let fails: Bool

    init(oldHost: BackgroundServiceHost, newHost: BackgroundServiceHost, fails: Bool) {
        self.oldHost = oldHost
        self.newHost = newHost
        self.fails = fails
    }

    func installLatestRelease(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) async throws {
        statusHandler(.downloading(received: 10, expected: 100))
        oldHost.stop()
        try await newHost.start()
        if fails { throw NSError(domain: "UpdateTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated download failure"]) }
    }
}
