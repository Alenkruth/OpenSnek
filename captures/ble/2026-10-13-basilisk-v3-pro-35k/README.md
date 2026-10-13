# Basilisk V3 Pro 35K Phantom Green Edition Bluetooth capture (2026-10-13, live session)

Device: Razer Basilisk V3 Pro 35K Phantom Green Edition (translucent shell) over Bluetooth Low Energy.
macOS identity: vendor `0x068E`, product `0x00D8`, peripheral and HID product name `BSKV3P 35K`.
Contributor: [PLus123456](https://github.com/PLus123456), live macOS probing with `OpenSnekProbe` and the app.

## Edition identification

- The owner's unit is the translucent edition and Razer's own software only offers underglow and scroll-wheel lighting.
- OpenRazer lists the Phantom Green Edition separately (USB `0x00D6` wired, `0x00D7` receiver) with no logo methods
  and a `1x12` matrix, while the regular Basilisk V3 Pro 35K (USB `0x00CC` / `0x00CD`) has logo methods and a `1x13`
  matrix like the Basilisk V3 Pro.
- The Basilisk V3 Pro numbers wired `0x00AA`, receiver `0x00AB`, Bluetooth `0x00AC`; the same pattern gives the Phantom
  Green Edition Bluetooth PID `0x00D8`, matching this unit.
- USB was not exercised in this session, so no USB identity is claimed.

## Vendor surface (`probe-log.txt`, `probe-log-dpi.txt`)

- Same GATT vendor service, request header, and 8-byte notify header as the Basilisk V3 Pro Bluetooth path.
- Every fresh connection first delivers an unsolicited `01 00 00 00 00 00 00 03` notify (req `0x01`, status `0x03`)
  before the real response; request-ID matching ignores it.
- Battery: `05 81 00 01` -> `7b` (123, so the byte is on the 0-255 scale -> 48%), `05 80 00 01` -> `01`.
- Sleep timeout: `05 84 00 00` -> `2c 01` (300 s).
- Live DPI table `0B 84 01 00` -> `03 05 01 90 01 90 01 00 00 02 20 03 ...`: active stage 3 of 5,
  `400/800/1500/3200/6400`, stage IDs `1..5`. `0B 82 00 00` returns the same hardware-active pairs.
- Lighting zone list `10 80 00 01` -> `04 01 0a`. LED `0x04` reads brightness `0` and state `00 ...` on every target;
  there is no physical logo LED on this edition.

## Onboard profiles (`probe-log.txt`, `probe-log-metadata.txt`)

- Inventory `03 80 00 00` -> `01`; active target `03 82 00 00` -> `01`.
- Stored targets `2..5` answer DPI (`0B 81/82/83`), button (`08 84`), brightness (`10 85`), and zone-state (`10 83`) reads.
- Every metadata read `03 84 <target> 00` returns status `0x03` for targets `0`, `1`, and `2`, with the app's
  `00 00 4c 00` read request, at offset `0x4C`, and as a bare header. The Basilisk V3 Pro answers these reads, so the
  mapped profile CRUD transaction cannot run here; OpenSnek keeps Bluetooth profile CRUD off for this device.

## Button surface (`probe-log.txt`)

Factory blocks read identically from all four unassigned stored targets (`08 84 <2..5> <slot>`):

| Slot | Block | Meaning |
| --- | --- | --- |
| `1`-`5`, `9`, `10` | `01 01 <slot> ...` | native mouse buttons / wheel |
| `14` (`0x0E`) | `07 01 04` | not exposed |
| `15` (`0x0F`) | `06 01 05 01 90 01 90` | sensitivity clutch, compact form (same as wired V3 / V3 35K; the V3 Pro uses `06 05 05 ...`) |
| `52` / `53` | `0e 01 68/69 00 14 00 00` | wheel tilt, short horizontal-scroll form |
| `96` (`0x60`) | `06 01 06` | DPI cycle (same as the V3 Pro) |
| `106` (`0x6A`) | `12 01 01` | not exposed |

App remaps on slots `4` and `5` (keyboard, turbo on/off) were written through `08 04 01 <slot>` and acknowledged.

## Lighting (`probe-log-lighting.txt`, `probe-log-lighting-after-power-cycle.txt`)

- Static color `10 03 00 <led>` with `01 00 00 01 R G B 00 00 00` ACKs and reads back on `10 83 00 <led>`; the owner
  confirmed the underglow turned magenta.
- Brightness `10 05 01 <led>` ACKs; the written value reads back on both `10 85 01 <led>` and `10 85 00 <led>`.
- Hardware-active brightness (`10 85 00`) can sit below the live value (`0x0c` vs `0x33` in the first sweep, consistent
  with idle dimming); the next brightness write brings it back in line.
- After a `10 03 00 0a` write, `10 83 01 0a` kept the previous effect state while `0x01` and `0x04` followed.
- Power cycle: lighting returned to effect `03` at brightness `0xc1` and the DPI table to `400/800/1500/3200/6400`, so
  live Bluetooth writes do not persist; OpenSnek's restore-on-connect re-applies saved settings.

## App validation (debug log excerpts summarized)

- DPI stage writes `0B 04 01 00` applied 3-, 4-, and 5-stage tables; passive HID DPI reports then followed the mouse's
  DPI button through every written stage, including `12000`.
- Brightness and two-zone static color applies completed without errors once profile CRUD was off.

## Files

- `probe-log.txt`: read-only identity, battery, power, lighting, DPI, profile, and button sweep.
- `probe-log-dpi.txt`: live DPI table reads.
- `probe-log-metadata.txt`: rejected `03 84` metadata reads.
- `probe-log-lighting.txt`: color and brightness writes that re-applied the device's current values, with readback.
- `probe-log-lighting-after-power-cycle.txt`: register state after a power cycle.
