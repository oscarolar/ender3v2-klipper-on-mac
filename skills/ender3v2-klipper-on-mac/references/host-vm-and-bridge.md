# Phase A: the host VM and the serial bridge

Everything here happens with the printer untouched: it keeps running Marlin
and whatever host it has today. Paths are relative to the plugin root
(`files/...`).

## Architecture

```
 Mac (macOS, owns the USB)                     VM (Debian 12 arm64, UTM, headless)
 CH340 /dev/cu.usbserial-*                     socat -> /dev/printer (pty)
   | klipper-serial-bridge.py (LaunchAgent)       | klippy (mainline Klipper, own venv)
   +-- TCP 192.168.64.1:7523 -- host-only net --> | Moonraker :7125, Mainsail/nginx :80
 VM keep-alive (LaunchAgent, utmctl)            bridged NIC -> LAN IP (<vm-lan-ip>)
```

`192.168.64.1` / `192.168.64.0/24` is UTM's default shared network and
`192.168.64.250` the VM's static host-only IP. Both are defaults, overridable
with `VM_IP`, `BRIDGE_LISTEN` and `BRIDGE_ADDR`.

## Why not USB passthrough or Docker

See `docs/adr/0001-...`. Short version: UTM cannot attach USB to a headless
VM ("The device cannot be found"), and Docker on macOS has the same USB wall
plus a layer.

## Steps

1. **UTM**: `brew install --cask utm`, `utmctl` on the `PATH`.
2. **Create the VM** on the Mac: `files/mac/create-vm.sh`. Settings (env):
   `VM_NAME`, `VM_IP`, `BRIDGE_IF` (default `en0`), `LAN_MAC`, `HOST_MAC`,
   `EXTRA_PUBKEY`, `SSH_ALIAS` (default `klipper-vm`). It downloads Debian's
   genericcloud arm64 image, renders the cloud-init seed from `files/vm/`,
   builds the VM through UTM's AppleScript API and waits for cloud-init.
   - The seed ISO must be attached as a **VirtIO** drive, or genericcloud never
     sees it.
   - The genericcloud kernel has no USB or `ch341`; cloud-init installs
     `linux-image-arm64` and purges the cloud kernel. Irrelevant with the
     bridge, harmless, and it leaves passthrough possible later.
   - Give `LAN_MAC` a DHCP reservation in your router: that is `<vm-lan-ip>`.
3. **Stack**: `LAN_CIDR=<your-lan>/24 files/mac/deploy-config.sh` copies
   `files/vm/*`, the firmware config and the Klipper config into the VM, then
   in the VM: `bash ~/install/install-stack.sh`. It installs Klipper in its own
   Python 3 venv with the repo-owned `klipper.service` (Klipper's
   `scripts/install-debian.sh` is still Python 2), Moonraker with its own
   installer, Mainsail behind nginx, and `printer-pty.service` **disabled**.
   KIAUH is not used: it is an interactive TUI.
4. **Bridge and keep-alive**: `files/mac/install-agents.sh` (env:
   `LABEL_PREFIX` default `com.example`, `BIN_DIR`, `BRIDGE_VENV`, `VM_IP`,
   `BRIDGE_LISTEN`, `VM_NAME`). It creates a venv with pyserial, installs
   both LaunchAgents and turns App Nap off for UTM. Restart UTM afterwards.
   `192.168.64.1` exists only while a shared-network VM runs; until then the
   bridge exits and launchd retries every 10 s.
5. **Verify**: `launchctl list | grep klipper`, `tail /tmp/klipper-serial-bridge.log`
   shows `listening on 192.168.64.1:7523 for 192.168.64.250`; `nc -z 192.168.64.1 7523`
   from the Mac logs `rejected 192.168.64.1` (only the VM is allowed).
   `curl http://<vm-lan-ip>/server/info` answers (`klippy_state` `error` or
   `startup` is fine before the cutover).
6. **Reboot test**: with the printer idle, reboot the Mac. The VM, bridge and
   Moonraker must come back without anyone touching it. The Mac needs
   auto-login (LaunchAgents run in the user session).
7. **macOS automatic updates off** (a forced reboot kills a print):
   `sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false`.
   The human runs it (sudo).

## Timing hardening (mandatory)

Printing is not latency sensitive: Klipper queues moves seconds ahead on the
MCU. Homing and probing are. There Klipper streams steps only ~0.1–0.25 s
ahead and expects a trsync renewal every 25 ms, so a short stall anywhere on
VM → socat → TCP → bridge → USB aborts a probing move with `Timer too close`
or `Communication timeout during homing`, while prints stay clean. Apply all
four; each one was needed:

| Fix | Where | Check |
|---|---|---|
| App Nap off for UTM | `defaults write ~/Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM NSAppSleepDisabled -bool YES`, then restart UTM (done by `install-agents.sh`) | `defaults read ... NSAppSleepDisabled` prints `1` |
| Bridge at interactive priority | `ProcessType Interactive` in the bridge LaunchAgent | `plutil -p` the installed plist |
| No Nagle delay | `TCP_NODELAY` in the bridge, `nodelay` on the socat `tcp:` address | in the files |
| Wider trsync window | `TRSYNC_TIMEOUT = 0.025` → `0.050` in `~/klipper/klippy/mcu.py` (one-line `sed` in `install-stack.sh`) | `grep ^TRSYNC_TIMEOUT ~/klipper/klippy/mcu.py` shows `0.050` |

Without App Nap off and the interactive bridge, homing aborted with
`Communication timeout during homing` and 64 retransmits. A Klipper update
(`git pull`, Mainsail's update manager) reverts the `mcu.py` edit: re-run
`install-stack.sh` after every update.

## Moonraker notes

- `trusted_clients` must list your LAN and `192.168.64.0/24`;
  `deploy-config.sh` fills `@LAN_CIDR@`.
- `cors_domains` rejects a bare `*`; use patterns such as `*.local` or real
  origins.
- `[update_manager mainsail-config]` needs `is_system_service: False`: an
  update of static config files must not restart services mid-print.
- Orca uploads through `[octoprint_compat]` (see `slicer-orca.md`).

Next: `firmware-and-cutover.md`.
