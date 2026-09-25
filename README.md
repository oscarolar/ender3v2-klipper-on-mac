# Ender 3 V2: Klipper on a Mac

Run [Klipper](https://www.klipper3d.org/) on a Creality Ender 3 V2 **without a
Raspberry Pi**: the Klipper host (Klipper, Moonraker, Mainsail) lives in a
headless Debian 12 arm64 VM under [UTM](https://mac.getutm.app/) on an
always-on Apple Silicon Mac. macOS keeps the printer's USB serial and a small
bridge forwards it to the VM over TCP.

This repository is a [Claude Code](https://claude.com/claude-code) plugin: a
skill that walks an agent (and you) through the whole migration from Marlin,
a full calibration and a go/no-go test, plus the scripts and configs it uses.
Everything can also be followed by hand.

## Results on one printer

Stock Ender 3 V2 (board 4.2.2, bowden extruder, CR Touch clone, carborundum
glass bed), mainline Klipper over the bridge:

| | Before (Marlin) | After (Klipper) |
|---|---|---|
| Go/no-go print (~3 h, dense retractions) | — | 0 `Timer too close`, 0 lost communication, `bytes_invalid` 0 |
| Bed mesh range, 180 × 210 mm | 0.82 mm (UBL) | 0.205 mm |
| Probe repeatability (`PROBE_ACCURACY` std dev) | — | 0.0075 mm |
| A bust, same slicer | 4 h 05 (stock Orca process) | 1 h 51 (fast process), 2.2× faster |
| PLA first layer | — | sticks to the stock glass without glue |

The mesh gain came mostly from fixing the X gantry and tramming properly;
Klipper made that measurable.

## How it works

```
 Mac (owns the USB)                               Debian VM (UTM, headless)
 CH340 -> klipper-serial-bridge.py (LaunchAgent)  socat -> /dev/printer -> Klipper
          TCP 192.168.64.1:7523  --host-only-->   Moonraker + Mainsail on the LAN
```

Why not a Pi, Docker or UTM USB passthrough: see
[docs/adr/0001](docs/adr/0001-klipper-host-in-vm-with-tcp-serial-bridge.md).

## Install as a Claude Code plugin

```bash
claude plugin marketplace add oscarolar/ender3v2-klipper-on-mac
claude plugin install ender3v2-klipper-on-mac@ender3v2-klipper-on-mac
```

Then ask Claude something like "move my Ender 3 V2 to Klipper on this Mac".
The skill keeps your printer on Marlin until the VM is proven, asks you for
physical feedback only (paper feel, knob turns, tower heights), and reads
every result as numbers from Moonraker.

## Follow it by hand

Start at [SKILL.md](skills/ender3v2-klipper-on-mac/SKILL.md), then the
references in order:

1. [host-vm-and-bridge.md](skills/ender3v2-klipper-on-mac/references/host-vm-and-bridge.md)
2. [firmware-and-cutover.md](skills/ender3v2-klipper-on-mac/references/firmware-and-cutover.md) and [printer-config.md](skills/ender3v2-klipper-on-mac/references/printer-config.md)
3. [calibration.md](skills/ender3v2-klipper-on-mac/references/calibration.md), [print-start-and-probe.md](skills/ender3v2-klipper-on-mac/references/print-start-and-probe.md), [slicer-orca.md](skills/ender3v2-klipper-on-mac/references/slicer-orca.md)
4. [go-no-go-and-rollback.md](skills/ender3v2-klipper-on-mac/references/go-no-go-and-rollback.md)

[troubleshooting.md](skills/ender3v2-klipper-on-mac/references/troubleshooting.md) when stuck.

## What is in `files/`

| Path | What |
|---|---|
| `mac/create-vm.sh` | creates the UTM VM from Debian's genericcloud image with cloud-init |
| `mac/klipper-serial-bridge.py` | USB serial ↔ TCP bridge (pyserial) |
| `mac/install-agents.sh`, `mac/launchd/*.plist.tmpl` | bridge and VM keep-alive LaunchAgents, App Nap off for UTM |
| `mac/deploy-config.sh` | copies the installer and Klipper config into the VM |
| `vm/` | cloud-init seed, systemd units, nginx site, `install-stack.sh` (includes the `TRSYNC_TIMEOUT` patch) |
| `firmware/ender3v2-422.config` | Klipper firmware build config for the 4.2.2 board |
| `klipper/` | `printer.cfg`, `macros.cfg` (`PRINT_START`, `PRINT_END`, power-loss resume), `moonraker.conf` |
| `orca/` | OrcaSlicer printer + fast process profile generator |
| `tools/` | Moonraker API helper and a print monitor |

Hosts, IPs, labels and paths are settings with defaults (UTM's
`192.168.64.0/24` host-only network, `com.example` launchd labels); each
script documents its variables in its header.

## Tests

```bash
uvx --with pyserial pytest -q tests
```

Covers the serial bridge (with pyserial's `loop://`) and the Orca profile
generator. Klipper batch-mode tests of the macros (`scripts/test_klippy.py`)
are not included: they need a Klipper checkout and a built firmware
dictionary, i.e. the VM.

## Limitations

- Tested on one printer: Ender 3 V2, board 4.2.2, stock bowden, a CR Touch
  clone, a Mac mini M1 with UTM 4.7 and Debian 12. Other boards (4.2.7), probes
  or extruders need their own pins and numbers.
- The Mac is now part of the printer. A Mac reboot stops the print
  (heaters off); turn macOS automatic updates off. Power-loss resume
  (`PLR_RESUME`) is best effort.
- Homing and probing are sensitive to stalls on the VM → bridge path. It
  needs App Nap off, an interactive-priority bridge and a one-line Klipper
  patch (`TRSYNC_TIMEOUT` 25 → 50 ms) that every Klipper update reverts until
  `install-stack.sh` is re-run. The root cause of the rare stalls was not
  proven.
- The stock DWIN display goes dark; you control the printer from Mainsail.
- No accelerometer: input shaping is chosen from a printed ringing tower.
- A CR Touch clone can still latch at print start; the only fix is a printer
  power cycle. The start macro reduces how often it happens, it does not
  remove it.
- Nothing here is endorsed by Creality, Klipper, UTM or OrcaSlicer.

## License

MIT, see [LICENSE](LICENSE).
