import XCTest
@testable import OpenSnek

/// Exercises update preparation, cancellation recovery, and the relaunch handoff.
@MainActor final class SoftwareUpdateSessionTests: XCTestCase {
    func testUpdaterWaitsForServiceAndOtherUIToActuallyExit() async throws {
        let session = SoftwareUpdateSession()
        var pids: [Int32] = [101, 102]
        var terminationRequested = false
        var updaterStarted = false
        let processes = SoftwareUpdateSession.Processes(otherRunningPIDs: { pids }, terminateOthers: { terminationRequested = true })
        let update = Task {
            try await session.run(processes: processes) {
                XCTAssertTrue(pids.isEmpty)
                updaterStarted = true
                session.finish()
            }
        }
        while !terminationRequested { await Task.yield() }
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(updaterStarted)
        pids = [102]
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(updaterStarted, "Sending termination is not proof that all other instances exited")
        pids = []
        try await update.value
        XCTAssertTrue(updaterStarted)
        XCTAssertFalse(session.isActive)
    }

    func testTimeoutPreventsUpdaterStartingAndReleasesSession() async {
        let session = SoftwareUpdateSession(terminationTimeout: .zero)
        var updaterStarted = false
        do {
            try await session.run(processes: .init(otherRunningPIDs: { [101] }, terminateOthers: {})) { updaterStarted = true }
            XCTFail("A still-running service must prevent installation")
        } catch {
            guard case SoftwareUpdateSession.PreparationError.otherApplicationsStillRunning(let pids) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(pids, [101])
        }
        XCTAssertFalse(updaterStarted)
        XCTAssertFalse(session.isActive)
    }

    func testCanceledPreparationDoesNotStartUpdaterAndReleasesSession() async throws {
        let session = SoftwareUpdateSession()
        var terminationRequested = false
        let update = Task { try await session.run(processes: .init(otherRunningPIDs: { [101] }, terminateOthers: { terminationRequested = true })) { XCTFail("Canceled preparation must not launch Sparkle") } }
        while !terminationRequested { await Task.yield() }
        update.cancel()
        do {
            try await update.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { XCTAssertFalse(session.isActive) }
    }

    func testCanceledCycleAllowsAnotherUpdateAndDuplicateCompletionIsHarmless() async throws {
        let session = SoftwareUpdateSession()
        for _ in 0..<2 {
            try await session.run(processes: .init(otherRunningPIDs: { [] }, terminateOthers: {})) {
                XCTAssertTrue(session.isActive)
                session.finish()
                session.finish()
            }
            XCTAssertFalse(session.isActive)
        }
    }

    func testRelaunchKeepsServiceLaunchBlockedUntilAbort() async throws {
        let session = SoftwareUpdateSession()
        var updaterStarted = false
        let update = Task {
            try await session.run(processes: .init(otherRunningPIDs: { [] }, terminateOthers: {})) {
                updaterStarted = true
                session.willRelaunch()
                session.finish()
            }
        }
        while !updaterStarted { await Task.yield() }
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isRelaunching)
        let failure = NSError(domain: "UpdateTest", code: 1)
        session.finish(error: failure)
        session.finish()
        do {
            try await update.value
            XCTFail("Expected update failure")
        } catch { XCTAssertEqual(error as NSError, failure) }
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isRelaunching)
    }

    func testConcurrentUpdateCannotReleaseFirstSession() async throws {
        let session = SoftwareUpdateSession()
        var updaterStarted = false
        let processes = SoftwareUpdateSession.Processes(otherRunningPIDs: { [] }, terminateOthers: {})
        let firstUpdate = Task { try await session.run(processes: processes) { updaterStarted = true } }
        while !updaterStarted { await Task.yield() }
        do {
            try await session.run(processes: processes) { XCTFail("Second updater must not start") }
            XCTFail("Expected already updating error")
        } catch { guard case SoftwareUpdateSession.PreparationError.alreadyUpdating = error else { return XCTFail("Unexpected error: \(error)") } }
        XCTAssertTrue(session.isActive)
        session.finish()
        try await firstUpdate.value
    }

    func testCoordinatorPreventsServiceLaunchDuringUpdate() async throws {
        let suiteName = "SoftwareUpdateSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = BackgroundServiceCoordinator(defaults: defaults)
        let session = coordinator.softwareUpdateSession
        try await session.run(processes: .init(otherRunningPIDs: { [] }, terminateOthers: {})) {
            do {
                try coordinator.launchServiceProcess()
                XCTFail("Service must not launch during an update")
            } catch { guard case SoftwareUpdateSession.PreparationError.alreadyUpdating = error else { return XCTFail("Unexpected error: \(error)") } }
            session.finish()
        }
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(coordinator.backgroundServiceEnabled, "Update suspension must preserve service preferences")
    }
}
