# 0001. Klipper host in a UTM VM, printer serial through a TCP bridge

- Status: accepted (2026-09-23); go/no-go print passed 2026-09-24

## Context

The goal is Klipper on a stock Ender 3 V2 (pressure advance, firmware
retraction, a readable API, faster printing) without buying or maintaining a
Raspberry Pi. Klipper's host software needs Linux. The only always-on machine
is an Apple Silicon Mac running macOS. The printer's USB serial chip is a CH340
(`1a86:7523`).

## Options

1. **Raspberry Pi (or other SBC)** — the standard, best-documented setup. Rejected:
   extra hardware to buy, power and maintain, and slower than the Mac for
   builds and the web UI.
2. **Docker on macOS (e.g. prind)** — Docker Desktop and OrbStack run containers
   inside a Linux VM that cannot see host USB devices, so a serial-over-network
   hack is still needed, with one more layer to debug.
3. **UTM VM with USB passthrough** — tested with UTM 4.7.5: a headless VM cannot
   capture the device (`utmctl usb connect` and the AppleScript `connect` both
   return "The device cannot be found", even with USB sharing on). Adding a
   display made `utmctl start` hang on a GUI prompt. Not viable unattended.
4. **UTM VM + TCP serial bridge** — macOS keeps the USB device; a small pyserial
   bridge forwards it over UTM's host-only network to `socat` in the VM, which
   exposes it as `/dev/printer`. Spike, 300 × `M105` at 250000 baud against
   Marlin:

   | Path | Median | p99 | Max | Timeouts |
   |---|---|---|---|---|
   | Direct on macOS | 7.00 ms | 10.93 ms | 12.02 ms | 0 |
   | VM through bridge | 8.66 ms | 12.41 ms | 15.57 ms | 0 |

## Decision

Option 4. Mainline Klipper, Moonraker and Mainsail in a headless Debian 12
arm64 VM (2 vCPU, 2 GB RAM, 12 GB disk) with two NICs: bridged for the LAN,
host-only for the serial path. The Marlin firmware `.bin` and its `M503`
settings are kept as the fallback.

## Consequences

- Klipper over the bridge is kept only if a long go/no-go print shows 0
  `Timer too close`, 0 `Lost communication with MCU`, `bytes_invalid` 0 and
  near-zero retransmits. Result: 2 h 45 min print, 0 / 0, `srtt` 5–6 ms,
  `bytes_invalid` 0, one isolated 185-byte retransmit burst. Kept.
- Homing and probing are the weak spot of the bridged path; it needs macOS App
  Nap off for UTM, an interactive-priority bridge and a wider trsync timeout in
  Klipper (a one-line local patch re-applied after every Klipper update).
- A Mac reboot stops a running print (heaters off): macOS automatic updates
  must be off, and power-loss recovery is best effort.
- The stock DWIN display goes dark; the printer is controlled from Mainsail.
- Only one process can own the serial port: the bridge refuses to open it
  while another program (OctoPrint, a slicer) holds it.
