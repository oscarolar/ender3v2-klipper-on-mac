---
name: ender3v2-klipper-on-mac
description: Use when moving a Creality Ender 3 V2 from Marlin to Klipper without a Raspberry Pi, running the Klipper host on a Mac or in a UTM VM, recalibrating an Ender 3 V2 on Klipper, when a CR Touch or BLTouch clone fails at print start, or when "Timer too close" or "Communication timeout during homing" appear over a serial bridge.
---

# Ender 3 V2: Klipper on a Mac

## Overview

Klipper host in a headless Debian 12 arm64 UTM VM on an always-on Apple Silicon Mac; a TCP bridge forwards the printer's USB serial. Working files: `files/` at the plugin root.

**Core rule:** the printer stays on Marlin until the host is proven, and Klipper stays only after a long print passes a gate decided in advance.

## Phases

1. **A: host, printer untouched** — VM, bridge, timing hardening, reboot test. `references/host-vm-and-bridge.md`
2. **B: cutover, human at the printer** — save Marlin state, flash, home. `references/firmware-and-cutover.md`, `references/printer-config.md`
3. **Calibration** — PID → 100 mm extrusion → `PROBE_CALIBRATE` → `SCREWS_TILT_CALCULATE` → `AXIS_TWIST_COMPENSATION_CALIBRATE` → mesh → PA tower → ringing tower → retraction tower → 5-disc adhesion. `references/calibration.md`, `references/print-start-and-probe.md`, `references/slicer-orca.md`
4. **Go/no-go print, then keep or roll back.** `references/go-no-go-and-rollback.md`

Stuck: `references/troubleshooting.md`.

## Human-at-printer protocol

- Anything that moves or heats: the human confirms presence and a clear bed first.
- Ask the human only for physical feedback: paper feel, knob turns, tower heights.
- Read every result as numbers through Moonraker: `POST /printer/gcode/script`, `GET /printer/objects/query`, `GET /server/gcode_store` (`files/tools/moonraker.sh`). Never read graphs.
- nginx cuts requests at 60 s while Klipper keeps running: poll long commands (PID, meshes).

## Quick reference

| Need | Command / file |
|---|---|
| Create VM | `files/mac/create-vm.sh` |
| Bridge + keep-alive agents | `files/mac/install-agents.sh` |
| Push installer and config | `LAN_CIDR=... files/mac/deploy-config.sh` |
| Install/re-patch stack (after Klipper updates) | `bash ~/install/install-stack.sh` in the VM |
| G-code, console, mesh | `files/tools/moonraker.sh gcode "..."`, `store`, `mesh` |
| Watch a print | `files/tools/klipper-printmon.sh` |
| Orca profiles | `files/orca/orca-klipper-profile.py` |

## Red flags / common mistakes

| Wrong belief | Reality | Ref |
|---|---|---|
| Probe `^PC14`/`PA1`, offsets -44/-8, TMC UART | `^PB1`/`PB0`, -40/-5, standalone drivers; start from upstream `printer-creality-ender3-v2-2020.cfg` | printer-config |
| Serial latency is irrelevant | Homing streams ~0.1–0.25 s ahead, trsync every 25 ms: App Nap off, `ProcessType Interactive`, TCP_NODELAY, `TRSYNC_TIMEOUT` 0.050 | host-vm-and-bridge |
| Reset/unstick/`FIRMWARE_RESTART` clears solid red | Power-cycle the printer | print-start-and-probe |
| Mesh cold; park probe low while heating | The order in `PRINT_START`; first deploy after idle sticks | print-start-and-probe |
| More samples/touch mode fix a flaky clone | `samples: 2`, mesh `SAMPLES=1`, stow each sample, no touch mode | print-start-and-probe |
| PA `FACTOR=.005`, tower at any speed | Bowden `.020`, within hotend flow | calibration |
| No accelerometer, skip ringing | Manual ringing tower | calibration |
| Twist calibration in nozzle coords | Probe coords | printer-config |
| Tram and mesh harder | X gantry first | calibration |
| Reuse the firmware file name | Never-used name; save Marlin `.bin` and `M503` first | firmware-and-cutover |
| Switch after a short test | ≥1 h (ideally ~3 h) gate | go-no-go-and-rollback |
| USB passthrough will work | Not headless; seed ISO on VirtIO | host-vm-and-bridge |
| Klipper's `install-debian.sh` | Python 2: own venv + unit | host-vm-and-bridge |
| Any Orca flavor/limits | `klipper`, limits = `max_accel`, no wipe | slicer-orca |
| CORS `*`; `FIRMWARE_RESTART` hangs | Wildcard rejected; restart pty then klipper | troubleshooting |
