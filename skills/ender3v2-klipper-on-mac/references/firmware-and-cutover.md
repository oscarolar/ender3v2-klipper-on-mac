# Phase B: firmware and cutover

Start only when Phase A passed (VM, bridge, reboot test). From here every
physical step needs the human at the printer (see SKILL.md protocol).

## 1. Save the Marlin state (rollback material)

Before anything else, through the current host (OctoPrint, Pronterface, a
serial terminal):

- `M503` output saved to a file: `M92` (E steps), `M851` (probe offsets and Z),
  PID (`M301`/`M304`).
- The mesh: `M420 V` (or `G29 T` on some builds).
- The exact Marlin firmware `.bin` currently on the printer (download it again
  if you no longer have it, and record its name and version).

These go into `go-no-go-and-rollback.md` if you ever roll back.

## 2. Release the port

The bridge refuses to open the port while another process holds it. Disconnect
the old host and turn its autoconnect off.

## 3. Build Klipper for the 4.2.2 board

Board facts: STM32F103 (some units ship a GD32F303; the same build works),
28 KiB bootloader, serial on USART1 (PA10/PA9). The 250000 baud setting stops
mattering once the MCU talks to Klipper over the bridge.

In the VM:

```bash
cp ~/install/ender3v2-422.config ~/klipper/.config
cd ~/klipper && make olddefconfig && make -j2
grep -E '^CONFIG_(MACH_STM32F103|STM32_FLASH_START_7000|STM32_SERIAL_USART1|SERIAL_BAUD)=' .config
ls -la out/klipper.bin     # ~25-35 KB
```

If `ender3v2-422.config` is missing, run `make menuconfig` instead: enable
"low-level configuration options", micro-controller **STMicroelectronics STM32**,
processor model **STM32F103**, bootloader offset **28KiB bootloader**,
communication interface **Serial (on USART1 PA10/PA9)**; leave the rest at
the defaults. Either way, `.config` must contain `CONFIG_MACH_STM32F103=y`,
`CONFIG_STM32_FLASH_START_7000=y` and `CONFIG_STM32_SERIAL_USART1=y`
(the `grep` above).

Copy `out/klipper.bin` to the Mac (`scp klipper-vm:klipper/out/klipper.bin .`).

## 4. Flash (human)

- Rename the file to a name the board has **never seen**, e.g. `K<MMDD>.bin`.
  The 4.2.2 bootloader silently skips a `.bin` whose name it has flashed before.
- Printer off → the file alone at the root of a FAT32 SD card → insert → power
  on → wait ~30 s.
- The DWIN display stays on the logo or goes dark. That is expected: Klipper
  does not drive it.

## 5. Connect

```bash
ssh klipper-vm 'sudo systemctl enable --now printer-pty; sleep 3; ls -l /dev/printer'
tail -3 /tmp/klipper-serial-bridge.log      # "client 192.168.64.250 connected"
files/tools/moonraker.sh gcode FIRMWARE_RESTART
curl -s http://<vm-lan-ip>/printer/info     # state "ready"
```

`error` with "Unable to connect": the board did not flash. Check whether the
card still has the file (the bootloader renames a flashed one to `.CUR`) and
retry with another new name.

## 6. Directions, endstops, probe, homing

1. `QUERY_ENDSTOPS`: all `open`.
2. `G28 X`, then `G28 Y`: the human confirms each axis moves toward its switch
   (left, front) and stops. Wrong way: invert that `dir_pin`, `FIRMWARE_RESTART`.
3. Probe self-test: `BLTOUCH_DEBUG COMMAND=pin_down`, `pin_up`, `QUERY_PROBE`
   (must say `open`).
4. 20 × `G28` in a row; count failures from the console. The threshold is
   **20/20**: any failure means stop and fix it before calibrating. Tell probe
   failures from link failures with the table in `troubleshooting.md`, then
   fix the probe (`print-start-and-probe.md`) or the link and App Nap
   ("Timing hardening" in `host-vm-and-bridge.md`).

Next: `calibration.md`.
