import Foundation
import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Exercises how the standard Basilisk V3 Pro 35K's buttons are read, shown, and restored over Bluetooth.
final class Basilisk35KButtonMappingTests: XCTestCase {
    private let profile35K = DeviceProfileID.basiliskV3Pro35KStandard

    func testScrollModeToggleAndProfileButtonAreShownReadOnlyOnTheStandard35K() throws {
        let standard = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00CE, transport: .bluetooth))
        let visible = standard.buttonLayout.visibleSlots
        XCTAssertEqual(visible.map(\.slot), visible.map(\.slot).sorted())
        // The repo's own names for the Basilisk V3 family: slot 14 is the Scroll Mode Toggle and slot 106 is the Profile Button.
        XCTAssertEqual(visible.first { $0.slot == 14 }?.friendlyName, "Scroll Mode Toggle")
        XCTAssertEqual(visible.first { $0.slot == 106 }?.friendlyName, "Profile Button")
        // The app shows their mapping, but they are not remappable. The family documents that apps cannot remap slot 14 and cannot remap slot 106 stably.
        XCTAssertFalse(standard.buttonLayout.writableSlots.contains(14))
        XCTAssertFalse(standard.buttonLayout.writableSlots.contains(106))
        XCTAssertFalse(standard.buttonLayout.isEditable(14))
        XCTAssertFalse(standard.buttonLayout.isEditable(106))
        XCTAssertEqual(standard.buttonLayout.access(for: 14), .protocolReadOnly)
        XCTAssertEqual(standard.buttonLayout.access(for: 106), .protocolReadOnly)
        XCTAssertEqual(standard.buttonLayout.writableSlots, DeviceProfiles.basiliskV3FamilyButtonSlots.map(\.slot))

        for productID in [0x00AC, 0x00D8] {
            let other = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: productID, transport: .bluetooth))
            XCTAssertNil(other.buttonLayout.visibleSlots.first { $0.slot == 14 }, String(format: "0x%04X", productID))
        }
    }

    func testFactoryBlocksOfTheReadOnlyButtonsReadBackAsDefault() {
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 14, profileID: profile35K), [0x07, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 106, profileID: profile35K), [0x12, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(ButtonBindingSupport.defaultUSBFunctionBlock(for: 14, profileID: .basiliskV3Pro))
        XCTAssertNil(ButtonBindingSupport.defaultUSBFunctionBlock(for: 106, profileID: .basiliskV3Pro))

        XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: 14, functionBlock: [0x07, 0x01, 0x04, 0, 0, 0, 0], profileID: profile35K)?.kind, .default)
        XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: 106, functionBlock: [0x12, 0x01, 0x01, 0, 0, 0, 0], profileID: profile35K)?.kind, .default)
    }

    func testDefaultBindingsNameTheirRealFunction() {
        let expected: [Int: String] = [1: "Left Click", 2: "Right Click", 3: "Middle Click", 4: "Mouse Back", 5: "Mouse Forward", 9: "Scroll Up", 10: "Scroll Down", 15: "DPI Clutch", 52: "Scroll Left", 53: "Scroll Right", 96: "DPI Cycle", 14: "Scroll Mode Toggle", 106: "Profile Button"]
        for (slot, label) in expected { XCTAssertEqual(ButtonBindingSupport.defaultFunctionLabel(for: slot, profileID: profile35K), label, "slot \(slot)") }
        XCTAssertNil(ButtonBindingSupport.defaultFunctionLabel(for: 999, profileID: profile35K))
        // The two extra slots are specific to the standard 35K.
        XCTAssertNil(ButtonBindingSupport.defaultFunctionLabel(for: 14, profileID: .basiliskV3Pro))
    }

    func testStoredBindingsReadFromTheMouseDecodeToTheirRealFunctions() {
        func decode(_ bytes: [UInt8], slot: UInt8) -> ButtonBindingKind? {
            guard let block = BLEVendorProtocol.extractBluetoothFunctionBlock(payload: Data(bytes), target: 2, slot: slot, profileID: profile35K) else { return nil }
            return ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: Int(slot), functionBlock: block, profileID: profile35K)?.kind
        }
        // Readbacks taken from a stored profile on a Basilisk V3 Pro 35K (Synapse-written).
        XCTAssertEqual(decode([0x04, 0x00, 0x0A, 0x01, 0x02, 0x01, 0x00, 0x04, 0xEA, 0x00, 0, 0, 0, 0, 0, 0], slot: 4), .mediaVolumeDown)
        XCTAssertEqual(decode([0x05, 0x00, 0x0A, 0x01, 0x02, 0x01, 0x00, 0x05, 0xE9, 0x00, 0, 0, 0, 0, 0, 0], slot: 5), .mediaVolumeUp)
        XCTAssertEqual(decode([0x0F, 0x00, 0x0A, 0x06, 0x02, 0x01, 0x00, 0x05, 0xCD, 0x01, 0x00, 0x90, 0x00, 0x01, 0x00, 0x90], slot: 15), .mediaPlayPause)
        // Plain factory bindings read back as Default, and a keyboard key (F24 on the middle button) is a keyboard binding.
        XCTAssertEqual(decode([0x01, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0, 0], slot: 1), .default)
        XCTAssertEqual(decode([0x03, 0x01, 0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0x73, 0x00, 0, 0, 0, 0, 0, 0], slot: 3), .keyboardSimple)
        XCTAssertEqual(decode([0x0E, 0x00, 0x07, 0x07, 0x01, 0x01, 0x04, 0x04, 0, 0, 0, 0, 0, 0, 0, 0], slot: 14), .default)
        XCTAssertEqual(decode([0x6A, 0x00, 0x12, 0x12, 0x01, 0x01, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0, 0], slot: 106), .default)
    }

    func testMediaFunctionsGroupUnderTheKeyboardCategory() {
        let mediaKinds = ButtonBindingKind.allCases.filter(\.isMediaKey)
        XCTAssertEqual(Set(mediaKinds), [.mediaPlayPause, .mediaNextTrack, .mediaPreviousTrack, .mediaVolumeUp, .mediaVolumeDown, .mediaMute])
        XCTAssertEqual(mediaKinds.map(\.mediaLabel), ["Play/Pause", "Next Track", "Previous Track", "Volume Up", "Volume Down", "Mute"])
        XCTAssertFalse(ButtonBindingKind.keyboardSimple.isMediaKey)
        XCTAssertEqual(ButtonBindingKind.leftClick.mediaLabel, ButtonBindingKind.leftClick.label)
    }

    func testBatteryAndSleepTimeoutAreRereadOncePerMinuteOnProfileEnabledMice() {
        let now = Date()
        XCTAssertTrue(BridgeClient.bluetoothMappedPowerTelemetryIsDue(lastReadAt: nil, now: now))
        XCTAssertFalse(BridgeClient.bluetoothMappedPowerTelemetryIsDue(lastReadAt: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(BridgeClient.bluetoothMappedPowerTelemetryIsDue(lastReadAt: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(BridgeClient.bluetoothMappedPowerTelemetryIsDue(lastReadAt: now.addingTimeInterval(-300), now: now))
    }
}
