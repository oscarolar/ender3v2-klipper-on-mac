# Troubleshooting

Check from the outside in. `<vm>` = the SSH alias (`klipper-vm`),
`<vm-lan-ip>` = the VM's LAN address, `<prefix>` = the LaunchAgent
`LABEL_PREFIX`.

| # | Check | Command | Fix |
|---|---|---|---|
| 1 | VM running | `utmctl status klipper` → `started` | `launchctl kickstart gui/$(id -u)/<prefix>.klipper-vm`; read `/tmp/klipper-vm.log`. After a Mac reboot the VM starts only once the auto-login session is up |
| 2 | Bridge running | `launchctl list \| grep klipper-serial-bridge`; `tail -5 /tmp/klipper-serial-bridge.log` | "in use by another process": another program holds the port, disconnect it and turn its autoconnect off. "no /dev/cu.usbserial-*": printer off or unplugged |
| 3 | socat in the VM | `ssh <vm> 'systemctl status printer-pty --no-pager; ls -l /dev/printer'` | `sudo systemctl enable --now printer-pty` (disabled until the cutover) |
| 4 | Klippy state | `curl -s http://<vm-lan-ip>/printer/info` | `error`/`shutdown`: read `~/printer_data/logs/klippy.log`, then `FIRMWARE_RESTART` |
| 5 | `FIRMWARE_RESTART` hangs, or klippy logs `Got EOF` / `Timeout with MCU` | — | `ssh <vm> 'sudo systemctl restart printer-pty; sleep 3; sudo systemctl restart klipper'`, then `FIRMWARE_RESTART` |

## Failure at print start: probe or bridge?

| Signature | Cause | Next |
|---|---|---|
| `Failed to verify BLTouch probe is raised`, `Probe triggered prior to movement`, probe LED blinking or solid red | probe pin | `print-start-and-probe.md` |
| `Timer too close` or `Communication timeout during homing` in `klippy.log`, the dumped trapq shows a probe/homing move, printer state `shutdown` | bridge timing | "Timing hardening" in `host-vm-and-bridge.md` |

After a power cycle for a solid red LED: `BLTOUCH_DEBUG COMMAND=reset`,
`QUERY_PROBE` must answer `open`, then relaunch the print. Symptoms do not
tell a clone from a genuine CR Touch; the settings in
`print-start-and-probe.md` are safe for both.

## Symptoms

| Symptom | Where the answer is |
|---|---|
| `Timer too close` or `Communication timeout during homing` while homing/probing, prints fine | "Timing hardening" in `host-vm-and-bridge.md`; first check App Nap (`defaults read ~/Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM NSAppSleepDisabled` = `1`) and that `TRSYNC_TIMEOUT` is still `0.050` after the last Klipper update |
| `Timer too close` / `Lost communication with MCU` while printing | the bridged path does not hold: `go-no-go-and-rollback.md` |
| Probe fails at print start, LED normal or solid red | `print-start-and-probe.md` |
| "Move out of range" in `AXIS_TWIST_COMPENSATION_CALIBRATE` | probe vs nozzle coordinates, `printer-config.md` |
| Mesh differs day to day, tramming never converges | X gantry check at the top of `calibration.md` |
| Printer heats before homing, or Orca ignores the tuned accelerations | `slicer-orca.md` |
| Moonraker refuses to start after a `cors_domains` edit | `host-vm-and-bridge.md`, Moonraker notes |
| Board does not answer after flashing | `firmware-and-cutover.md` step 4–5 |

## Timing statistics

`files/tools/moonraker.sh stats`, or in `klippy.log` the `Stats` lines:
`srtt`, `bytes_retransmit`, `bytes_invalid`. Thresholds are in
`go-no-go-and-rollback.md`.

## Obico

Setup and relinking after a VM rebuild: "Remote access" in
`host-vm-and-bridge.md`.
