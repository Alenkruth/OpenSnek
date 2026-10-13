import Foundation
import OpenSnekCore

/// Battery telemetry read independently of settings and lighting state.
struct BatteryTelemetry: Equatable, Sendable {
    let percent: Int
    let charging: Bool?

    func applying(to state: MouseState) -> MouseState {
        MouseState(
            device: state.device, connection: state.connection, battery_percent: percent, charging: charging, dpi: state.dpi, dpi_stages: state.dpi_stages, poll_rate: state.poll_rate, sleep_timeout: state.sleep_timeout, device_mode: state.device_mode,
            low_battery_threshold_raw: state.low_battery_threshold_raw, scroll_mode: state.scroll_mode, scroll_acceleration: state.scroll_acceleration, scroll_smart_reel: state.scroll_smart_reel, active_onboard_profile: state.active_onboard_profile,
            onboard_profile_count: state.onboard_profile_count, led_value: state.led_value, capabilities: state.capabilities)
    }
}

/// Bounds battery traffic during effects without letting cached telemetry live indefinitely.
actor SoftwareLightingBatterySampler {
    static let refreshInterval: TimeInterval = 30

    /// Tracks the last attempt independently of DPI events or presentation timestamps.
    private struct Attempt {
        let startedAt: Date
        let connectionGeneration: UInt64
    }

    private var attempts: [String: Attempt] = [:]
    private var inFlight: Set<String> = []

    func sample(device: MouseDevice, connectionGeneration: UInt64, now: Date = Date(), read: @Sendable (MouseDevice) async throws -> BatteryTelemetry?) async throws -> BatteryTelemetry? {
        guard !inFlight.contains(device.id) else { return nil }
        if let attempt = attempts[device.id], attempt.connectionGeneration == connectionGeneration, now.timeIntervalSince(attempt.startedAt) < Self.refreshInterval { return nil }
        attempts[device.id] = Attempt(startedAt: now, connectionGeneration: connectionGeneration)
        inFlight.insert(device.id)
        defer { inFlight.remove(device.id) }
        // A failed command is not retried. A later scheduled poll or new connection
        // generation provides the next opportunity to read the battery.
        return try await read(device)
    }
}
