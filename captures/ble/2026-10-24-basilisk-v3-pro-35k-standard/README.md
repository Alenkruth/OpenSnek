# Basilisk V3 Pro 35K (standard edition) Bluetooth validation (2026-10-24, live session)

Device: Razer Basilisk V3 Pro 35K, standard (opaque) edition with a logo LED, over Bluetooth Low Energy.
macOS identity: vendor `0x068E`, product `0x00CE`, HID product name `BasiliskV3Pro`.
Software: macOS 27.0.1. OpenSnek development build from the `basiliskv3pro35k` branch on `origin/main` at `b4e0f66`.
Contributor: https://github.com/alenkruth and Claude. The contributor owns the hardware and made all physical observations.

## Scope

- `probe-log.txt` contains read-only readbacks. The OpenSnek app and service were stopped for each readback.
- The log contains no device serial number and no profile name.

## Results

| Area | Result | Evidence |
|---|---|---|
| DPI stages and DPI button | Pass | The active stage in the app followed each press through all five stages. `0B 81 00 00` and `0B 83 00 00` followed each press. The stored table `0B 84 02 00` reads `400/800/1600/5000/6400` after the contributor restored it. |
| Battery and sleep timeout | Pass | Battery raw `a1` (0-255 scale) and sleep timeout `58 02` (600 s) show in the app. The timeout is one global setting (`05 84 00 00`). |
| Static color and brightness | Pass | `10 83 02 <LED>` reads static green on LEDs `01`, `04` and `0A`. The stored brightness `10 85 02 <LED>` reads `4c`. The edits persisted after a power cycle with the app closed. |
| Spectrum and Pulse | Pass, live only | Both effects render on the mouse. They reset on sleep, a power cycle or a profile change (see Findings). |
| Buttons | Pass | Each button shows its mapping. A middle-click remap persisted. Media functions work. Slots `14` and `106` are read-only. |
| Onboard profiles | Pass. Rename failed. | Profile switching and edits to DPI, buttons and lighting persisted after a power cycle with the app closed. |
| Disconnect and reconnect | Pass | The app showed the mouse as offline. After reconnect, the app showed battery, DPI and lighting again. |

## Findings

- The mouse cannot store built-in effects in a profile. Razer staff state that effects need Razer Synapse to run. In the contributor's tests, a power cycle and a profile change cleared Spectrum and Wave. OpenSnek applies effects to the live lighting (`10 03 00 <LED>`) only. It stores static colors in the profile.
- The app does not offer Wave. A Wave write to all LEDs (`10 03 00 00`) caused the logo and scroll wheel to change color after the underglow. The animation was coarse and fast.
- The live DPI table `0B 84 01 00` does not follow the DPI button when a stored profile is active. It stays on the table and stage of the base profile. The hardware-active DPI `0B 81 00 00` follows each press. The app reads that value and finds it in the table of the selected profile.
- Stored readbacks in `probe-log.txt`: the base profile (target 1) holds DPI `1000/2000/4000/6000/10000` and an effect-shaped Spectrum on all three LEDs. Stored target 2 holds the values that the contributor set in the tests.
- Slots `4` and `5` (volume) and `15` (play/pause) hold media blocks that Synapse wrote.
- The live brightness `10 85 01 <LED>` reads `4d` on all three LEDs. The same key is also the stored brightness read for target 1, so the stored brightness of target 1 is not read separately.

## Limits

- OpenSnek pairs the HID entry and the Bluetooth link by name. The names match when one contains the other, ignoring case, spaces and punctuation. The HID product name does not change when the contributor renames the mouse in the macOS Bluetooth settings. The mouse connected with the Bluetooth name `BasiliskV3Pro35K`, which contains `BasiliskV3Pro`. It did not connect with the name `jerry`, which has no overlap.
- These items were not tested: the `OPEN_SNEK_HW` hardware-gated tests, USB identities, independent X/Y DPI, and profile create and delete.
- Profile rename failed.
