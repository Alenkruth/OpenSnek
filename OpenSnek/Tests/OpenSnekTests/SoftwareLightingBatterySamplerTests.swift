import Foundation
import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Exercises battery sampling across continuous lighting, sleep, and recovery.
final class SoftwareLightingBatterySamplerTests: XCTestCase {
    func testContinuousLightingGetsFreshBatteryAtBoundedIntervals() async throws {
        let sampler = SoftwareLightingBatterySampler()
        let reader = BatteryReaderStub()
        let device = makeDevice()
        let start = Date()
        let first = try await sampler.sample(device: device, connectionGeneration: 0, now: start, read: { await reader.read($0) })
        XCTAssertEqual(first?.percent, 80)
        for second in 1..<30 {
            let suppressed = try await sampler.sample(device: device, connectionGeneration: 0, now: start.addingTimeInterval(Double(second)), read: { await reader.read($0) })
            XCTAssertNil(suppressed)
        }
        let fresh = try await sampler.sample(device: device, connectionGeneration: 0, now: start.addingTimeInterval(30), read: { await reader.read($0) })
        XCTAssertEqual(fresh?.percent, 79)
        let count = await reader.count
        XCTAssertEqual(count, 2)
    }

    func testWakeForcesFreshBatteryBeforeNormalInterval() async throws {
        let sampler = SoftwareLightingBatterySampler()
        let reader = BatteryReaderStub()
        let device = makeDevice()
        let start = Date()
        _ = try await sampler.sample(device: device, connectionGeneration: 0, now: start, read: { await reader.read($0) })
        let recovered = try await sampler.sample(device: device, connectionGeneration: 2, now: start.addingTimeInterval(2), read: { await reader.read($0) })
        XCTAssertEqual(recovered?.percent, 79)
        let count = await reader.count
        XCTAssertEqual(count, 2)
    }

    func testFailureIsNotRetriedAndReconnectCanRecover() async throws {
        let sampler = SoftwareLightingBatterySampler()
        let device = makeDevice()
        let start = Date()
        do {
            _ = try await sampler.sample(device: device, connectionGeneration: 0, now: start) { _ in throw BatteryReadFailure.asleep }
            XCTFail("Sleeping read must surface its error")
        } catch BatteryReadFailure.asleep {}
        let reader = BatteryReaderStub()
        let suppressed = try await sampler.sample(device: device, connectionGeneration: 0, now: start.addingTimeInterval(1), read: { await reader.read($0) })
        XCTAssertNil(suppressed)
        let recovered = try await sampler.sample(device: device, connectionGeneration: 1, now: start.addingTimeInterval(2), read: { await reader.read($0) })
        XCTAssertEqual(recovered?.percent, 80)
        let count = await reader.count
        XCTAssertEqual(count, 1)
    }

    func testMissingBatteryDoesNotRetryUntilNextScheduledSample() async throws {
        let sampler = SoftwareLightingBatterySampler()
        let device = makeDevice()
        let start = Date()
        let missing = try await sampler.sample(device: device, connectionGeneration: 0, now: start) { _ in nil }
        XCTAssertNil(missing)
        let reader = BatteryReaderStub()
        let suppressed = try await sampler.sample(device: device, connectionGeneration: 0, now: start.addingTimeInterval(2)) { await reader.read($0) }
        XCTAssertNil(suppressed)
        let fresh = try await sampler.sample(device: device, connectionGeneration: 0, now: start.addingTimeInterval(30)) { await reader.read($0) }
        XCTAssertEqual(fresh?.percent, 80)
        let count = await reader.count
        XCTAssertEqual(count, 1)
    }

    func testBatteryRefreshPreservesLatestSettingsAndClearsUnknownCharging() {
        let device = makeDevice()
        let state = makeSnapshotState(device: device, connection: "USB", batteryPercent: 80, dpiValues: [800, 3200], activeStage: 1)
        let updated = BatteryTelemetry(percent: 79, charging: nil).applying(to: state)
        XCTAssertEqual(updated.battery_percent, 79)
        XCTAssertNil(updated.charging)
        XCTAssertEqual(updated.dpi, state.dpi)
        XCTAssertEqual(updated.dpi_stages, state.dpi_stages)
        XCTAssertEqual(updated.led_value, state.led_value)
        XCTAssertEqual(updated.poll_rate, state.poll_rate)
    }

    private func makeDevice() -> MouseDevice { makeSnapshotDevice(id: "battery-sampling", productName: "V3 Pro", identity: SnapshotDeviceIdentity(transport: .usb, serial: "SAMPLING", locationID: 1), profile: .basiliskV3Pro) }
}

/// Simulates a changing hardware battery reading.
private actor BatteryReaderStub {
    private(set) var count = 0
    func read(_: MouseDevice) -> BatteryTelemetry? {
        defer { count += 1 }
        return BatteryTelemetry(percent: 80 - count, charging: false)
    }
}

/// Simulates a sleeping receiver-backed mouse.
private enum BatteryReadFailure: Error { case asleep }
