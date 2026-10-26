import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Exercises built-in lighting effects applied to the live lights alongside onboard profiles (Basilisk V3 Pro 35K over Bluetooth).
final class OnboardLightingEffectTests: XCTestCase {
    func testEffectPayloadsMatchHardwareTestedBodies() {
        // Spectrum restores the factory zone state exactly (`03` plus padding), as verified against the mouse.
        XCTAssertEqual(Array(BLEVendorProtocol.buildBluetoothZoneEffectPayload(effect: LightingEffectPatch(kind: .spectrum))), [0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(BLEVendorProtocol.buildBluetoothZoneEffectPayload(effect: LightingEffectPatch(kind: .pulseRandom))), [0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(BLEVendorProtocol.buildBluetoothZoneEffectPayload(effect: LightingEffectPatch(kind: .pulseSingle, primary: RGBPatch(r: 0, g: 0, b: 255)))), [0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0, 0, 0])
    }

    func testStoredZoneStatesDecodeIntoEffects() {
        // The unedited stored default read from the mouse is an effect-shaped Spectrum.
        XCTAssertEqual(BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x03, 0x01, 0x28, 0x01, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00]))?.kind, .spectrum)
        XCTAssertEqual(BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0]))?.kind, .spectrum)
        XCTAssertEqual(BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0]))?.kind, .pulseRandom)
        let single = BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x02, 0x01, 0x00, 0x01, 0xFF, 0x00, 0x00, 0, 0, 0]))
        XCTAssertEqual(single?.kind, .pulseSingle)
        XCTAssertEqual(single?.primary, RGBPatch(r: 255, g: 0, b: 0))

        // Static colors belong to the color parser; unknown or short payloads are not effects.
        XCTAssertNil(BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x01, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x00, 0, 0, 0])))
        XCTAssertNil(BLEVendorProtocol.parseBluetoothZoneEffect(Data([0x03, 0x00])))
        XCTAssertNil(BLEVendorProtocol.parseBluetoothZoneEffect(Data()))
    }

    func testNewerStaticColorReplacesPendingEffectAndTheReverse() {
        let spectrum = [1: LightingEffectPatch(kind: .spectrum)]
        let red = [1: RGBPatch(r: 255, g: 0, b: 0)]

        let effectThenColor = OnboardProfileMutation(effectByLEDID: spectrum).merged(with: OnboardProfileMutation(staticColorByLEDID: red))
        XCTAssertEqual(effectThenColor.staticColorByLEDID, red)
        XCTAssertNil(effectThenColor.effectByLEDID)

        let colorThenEffect = OnboardProfileMutation(staticColorByLEDID: red).merged(with: OnboardProfileMutation(effectByLEDID: spectrum))
        XCTAssertEqual(colorThenEffect.effectByLEDID, spectrum)
        XCTAssertNil(colorThenEffect.staticColorByLEDID)

        // Unrelated newer edits keep the pending lighting form.
        let unrelated = OnboardProfileMutation(effectByLEDID: spectrum).merged(with: OnboardProfileMutation(brightnessByLEDID: [1: 200]))
        XCTAssertEqual(unrelated.effectByLEDID, spectrum)
        XCTAssertEqual(unrelated.brightnessByLEDID, [1: 200])
        XCTAssertFalse(OnboardProfileMutation(effectByLEDID: spectrum).isEmpty)
    }

    func testSnapshotsSavedWithoutEffectsStillDecode() throws {
        let snapshot = OnboardProfileSnapshot(profileID: 2, metadata: OnboardProfileMetadata(name: "Stored"), staticColorByLEDID: [1: RGBPatch(r: 1, g: 2, b: 3)])
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertFalse((String(bytes: data, encoding: .utf8) ?? "").contains("effectByLEDID"), "nil effects are omitted, matching snapshots saved before effects existed")
        let decoded = try JSONDecoder().decode(OnboardProfileSnapshot.self, from: data)
        XCTAssertNil(decoded.effectByLEDID)
        XCTAssertEqual(decoded.staticColorByLEDID, snapshot.staticColorByLEDID)

        let withEffects = OnboardProfileSnapshot(profileID: 2, metadata: OnboardProfileMetadata(name: "Stored"), effectByLEDID: [4: LightingEffectPatch(kind: .spectrum)])
        XCTAssertEqual(try JSONDecoder().decode(OnboardProfileSnapshot.self, from: try JSONEncoder().encode(withEffects)).effectByLEDID?[4]?.kind, .spectrum)
    }

    func testOnlyTheStandard35KOffersLiveEffectsWithProfiles() throws {
        let standard = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00CE, transport: .bluetooth))
        XCTAssertTrue(standard.appliesLightingEffectsLiveWithOnboardProfiles)
        XCTAssertTrue(standard.supportsAdvancedLightingEffects)
        XCTAssertEqual(standard.supportedLightingEffects, [.staticColor, .spectrum, .pulseRandom, .pulseSingle])
        XCTAssertTrue(standard.supportsMappedOnboardProfileCRUD)

        for (vendor, product, transport) in [(0x068E, 0x00AC, DeviceTransportKind.bluetooth), (0x068E, 0x00D8, .bluetooth), (0x068E, 0x00E9, .bluetooth), (0x1532, 0x00AB, .usb)] {
            let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: vendor, productID: product, transport: transport), String(format: "0x%04X", product))
            XCTAssertFalse(profile.appliesLightingEffectsLiveWithOnboardProfiles, String(format: "0x%04X", product))
        }
        // The V3 Pro and Phantom Green Bluetooth profiles keep their static-color-only lighting.
        XCTAssertEqual(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00AC, transport: .bluetooth)?.supportedLightingEffects, [.staticColor])
        XCTAssertEqual(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00D8, transport: .bluetooth)?.supportedLightingEffects, [.staticColor])
    }

    func testOnlyTheStandard35KPollsTheLiveDPIStageWithProfilesOn() throws {
        XCTAssertEqual(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00CE, transport: .bluetooth)?.pollsLiveDPIStageWithOnboardProfiles, true)
        // Mice that send passive DPI reports keep trusting them instead of polling.
        for (vendor, product, transport) in [(0x068E, 0x00AC, DeviceTransportKind.bluetooth), (0x068E, 0x00D8, .bluetooth), (0x068E, 0x00E9, .bluetooth), (0x1532, 0x00AB, .usb)] {
            XCTAssertEqual(DeviceProfiles.resolve(vendorID: vendor, productID: product, transport: transport)?.pollsLiveDPIStageWithOnboardProfiles, false, String(format: "0x%04X", product))
        }
    }

    func testOnlyTheStandard35KUsesExtendedProfileSessionHandling() throws {
        XCTAssertEqual(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00CE, transport: .bluetooth)?.usesExtendedProfileSessionHandling, true)
        for (vendor, product, transport) in [(0x068E, 0x00AC, DeviceTransportKind.bluetooth), (0x068E, 0x00D8, .bluetooth), (0x068E, 0x00E9, .bluetooth), (0x1532, 0x00AB, .usb)] {
            XCTAssertEqual(DeviceProfiles.resolve(vendorID: vendor, productID: product, transport: transport)?.usesExtendedProfileSessionHandling, false, String(format: "0x%04X", product))
        }
    }

    func testTheHardwareActiveDPIFindsItsStageInTheSelectedProfilesTable() throws {
        // Read from a 35K with a stored profile active (`0B 81 00 00`) while the DPI button cycled; the profile's own table is 400/800/1600/5000/6400.
        let table = [400, 800, 1600, 5000, 6400].map { DpiPair(x: $0, y: $0) }
        let readings: [([UInt8], Int)] = [([0x90, 0x01, 0x90, 0x01, 0, 0], 0), ([0x20, 0x03, 0x20, 0x03, 0, 0], 1), ([0x40, 0x06, 0x40, 0x06, 0, 0], 2), ([0x88, 0x13, 0x88, 0x13, 0, 0], 3), ([0x00, 0x19, 0x00, 0x19, 0, 0], 4)]
        for (bytes, stage) in readings {
            let live = try XCTUnwrap(BLEVendorProtocol.parseDpiScalarPair(blob: Data(bytes)))
            XCTAssertEqual(AppStateEditorController.uniqueDPIStageIndex(matching: live, in: table), stage)
        }
        // Two stages with the same DPI cannot be told apart by value, so the cached stage is kept.
        XCTAssertNil(AppStateEditorController.uniqueDPIStageIndex(matching: DpiPair(x: 800, y: 800), in: [400, 800, 800].map { DpiPair(x: $0, y: $0) }))
    }

    func testPickingAnEffectOnThe35KGoesThroughTheProfileMutationPath() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-35k-effect-device", transport: .bluetooth, serial: "ONBOARD-BT-35K-EFFECT-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro35KStandard)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1600, 5000, 6400], activeStage: 2), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [400, 800, 1600, 5000, 6400], brightnessByLEDID: [1: 51, 4: 51, 10: 51], staticColorByLEDID: [1: RGBPatch(r: 0, g: 255, b: 0), 4: RGBPatch(r: 0, g: 255, b: 0), 10: RGBPatch(r: 0, g: 255, b: 0)]),
            forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await MainActor.run {
            appState.editorStore.editableLightingEffect = .spectrum
            appState.editorStore.scheduleAutoApplyLightingEffect()
        }
        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { $0.mutation.effectByLEDID?[1]?.kind == .spectrum }
        }

        let updates = await backend.recordedOnboardUpdates()
        let patches = await backend.recordedPatches()
        XCTAssertEqual(patches.count, 0, "effects go through the profile mutation path, not the generic live patch")
        let spectrumUpdate = try XCTUnwrap(updates.first { $0.mutation.effectByLEDID?[1]?.kind == .spectrum })
        XCTAssertEqual(spectrumUpdate.profileID, 2)
        XCTAssertEqual(Set(try XCTUnwrap(spectrumUpdate.mutation.effectByLEDID).keys), [1, 4, 10], "effects apply to every LED of the profile")
        XCTAssertNil(spectrumUpdate.mutation.staticColorByLEDID)
    }
}
