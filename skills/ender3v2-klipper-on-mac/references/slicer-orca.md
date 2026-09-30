# OrcaSlicer for the Klipper Ender 3 V2

## Generate the profiles

With Orca **closed** (it rewrites profiles on exit), on the machine running Orca:

```bash
files/orca/orca-klipper-profile.py <vm-lan-ip> --source "<your Marlin printer profile>" \
    [--name "Ender-3 V2 Klipper CR Touch"] [--process "0.20mm Klipper fast"]
```

It copies your existing user printer profile (left untouched as the Marlin
fallback) and sets what Klipper needs. `files/orca/0.20mm Klipper fast.json`
is the process it writes, for reference or manual import.

## What the printer profile must have, and why

| Setting | Value | Why |
|---|---|---|
| G-code flavor | `klipper` | every other flavor emits `M190`/`M104` before the start G-code, so the printer heats before `PRINT_START` homes and probes |
| Host type / host | Octo/Klipper, `<vm-lan-ip>` | Moonraker's `[octoprint_compat]` accepts Orca's upload |
| Start G-code | `PRINT_START BED=[bed_temperature_initial_layer_single] EXTRUDER=[nozzle_temperature_initial_layer]` | all heating, homing and probing live in the macro |
| End G-code | `PRINT_END` | |
| Layer change G-code | `G92 E0` then `PLR_SAVE LAYER=[layer_num] Z=[layer_z]` | power-loss resume point; with relative E, Orca refuses to slice without `G92 E0` in the layer G-code |
| Use firmware retraction | on | retraction length comes from `[firmware_retraction]` |
| Relative E | on | matches `M83` in `PRINT_START` |
| Machine limits accel X/Y/extruding/travel | = Klipper `max_accel` (3000) | Orca silently clamps process accelerations to these limits |
| Machine max speed X/Y | = `max_velocity` (200) | same clamping |

Orca refuses "wipe while retracting" together with firmware retraction: leave
wipe off.

## Fast process

Orca's stock Ender 3 V2 process (accel 500, outer wall 25 mm/s) leaves most of
the machine unused. The fast process: accel 3000 (outer wall and top 2000,
first layer 500, bridges 1000), outer wall 60, inner wall 90, sparse infill
110, solid infill 90, travel 180 mm/s, first layer 25. Sparse infill at 110
mm/s is 0.45 × 0.2 × 110 = 9.9 mm³/s, inside a stock hotend's ~12 mm³/s.
Example: a bust went from 4 h 05 to 1 h 51 (2.2×) with no visible loss.

## Slicing from the Orca command line

When an agent slices with the `OrcaSlicer` binary instead of the GUI, the
filament's bed temperature can come out wrong (35 °C instead of the preset
value), both in `PRINT_START BED=` and in the `M140` after the first layer.
Before uploading, check every bed temperature in the file
(`grep -nE '^(PRINT_START|M140|M190)' file.gcode`) and fix all of them, not
just the start line: 35 °C on glass lets PLA lift and marks the layer lines.
