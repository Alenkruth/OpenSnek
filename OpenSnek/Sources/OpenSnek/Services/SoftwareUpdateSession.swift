import Foundation

/// Keeps Sparkle's host process alive and exclusive until the update cycle ends.
@MainActor final class SoftwareUpdateSession {
    /// Provides process discovery and shutdown without coupling tests to real applications.
    struct Processes {
        let otherRunningPIDs: () -> [Int32]
        let terminateOthers: () -> Void
    }

    /// Describes failures before Sparkle can safely start an update.
    enum PreparationError: LocalizedError {
        case alreadyUpdating
        case otherApplicationsStillRunning([Int32])

        var errorDescription: String? {
            switch self {
            case .alreadyUpdating: return "An OpenSnek update is already in progress."
            case .otherApplicationsStillRunning(let pids): return "Other OpenSnek processes did not quit (\(pids.map(String.init).joined(separator: ", "))). Quit them before trying the update again."
            }
        }
    }

    private(set) var isActive = false
    private(set) var isRelaunching = false
    private var completion: CheckedContinuation<Void, any Error>?
    private let terminationTimeout: Duration
    private let pollInterval: Duration = .milliseconds(50)

    init(terminationTimeout: Duration = .seconds(5)) { self.terminationTimeout = terminationTimeout }

    func run(processes: Processes, startUpdater: () -> Void) async throws {
        guard !isActive else { throw PreparationError.alreadyUpdating }
        isActive = true
        isRelaunching = false
        defer {
            isActive = false
            isRelaunching = false
        }

        // Sparkle 2.9.3 watches the first process for the bundle, which may be the
        // service. Wait for every other instance to exit BEFORE it registers its host.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: terminationTimeout)
        processes.terminateOthers()
        while true {
            try Task.checkCancellation()
            let remainingPIDs = processes.otherRunningPIDs()
            guard !remainingPIDs.isEmpty else { break }
            guard clock.now < deadline else { throw PreparationError.otherApplicationsStillRunning(remainingPIDs) }
            try await clock.sleep(for: pollInterval)
        }
        AppLog.info("Update", "other processes exited; starting Sparkle pid=\(ProcessInfo.processInfo.processIdentifier)")
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            startUpdater()
        }
    }

    func willRelaunch() {
        isRelaunching = true
        AppLog.info("Update", "Sparkle requested relaunch")
    }

    func finish(error: (any Error)? = nil) {
        // Sparkle can finish its cycle while the old UI is still terminating.
        // Do not let service recovery race with installation or relaunch.
        guard error != nil || !isRelaunching else { return }
        guard let completion else { return }
        self.completion = nil
        if let error {
            AppLog.error("Update", "update cycle failed: \(error.localizedDescription)")
            completion.resume(throwing: error)
        } else {
            AppLog.info("Update", "update cycle ended without relaunch")
            completion.resume()
        }
    }
}
