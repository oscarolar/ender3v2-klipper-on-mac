#!/bin/bash
# Install the serial bridge and the VM keep-alive as LaunchAgents of the logged-in
# user, and turn App Nap off for UTM. Runs ON the Mac that owns the printer's USB.
#
#   files/mac/install-agents.sh
#
# Settings (environment, with defaults):
#   LABEL_PREFIX   com.example            launchd label prefix
#   BIN_DIR        $HOME/bin              where the scripts are copied
#   BRIDGE_VENV    $HOME/.venvs/klipper-bridge   venv with pyserial for the bridge
#   BRIDGE_LISTEN  192.168.64.1:7523      UTM shared-network host address : port
#   VM_IP          192.168.64.250         the VM's host-only IP (only peer allowed)
#   VM_NAME        klipper                UTM VM name
#   SERIAL_PORT    auto                   auto = the single /dev/cu.usbserial-* (CH340)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL_PREFIX="${LABEL_PREFIX:-com.example}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
BRIDGE_VENV="${BRIDGE_VENV:-$HOME/.venvs/klipper-bridge}"
BRIDGE_LISTEN="${BRIDGE_LISTEN:-192.168.64.1:7523}"
VM_IP="${VM_IP:-192.168.64.250}"
VM_NAME="${VM_NAME:-klipper}"
SERIAL_PORT="${SERIAL_PORT:-auto}"

mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents"
[ -x "$BRIDGE_VENV/bin/python" ] || python3 -m venv "$BRIDGE_VENV"
"$BRIDGE_VENV/bin/pip" install -q pyserial
cp "$HERE/klipper-serial-bridge.py" "$HERE/klipper-vm-ensure.sh" "$BIN_DIR/"
chmod +x "$BIN_DIR/klipper-serial-bridge.py" "$BIN_DIR/klipper-vm-ensure.sh"

# App Nap throttles UTM when no window is visible: homing then aborts with
# "Communication timeout during homing". Takes effect after UTM restarts.
defaults write "$HOME/Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM" \
    NSAppSleepDisabled -bool YES

for name in klipper-serial-bridge klipper-vm; do
    label="$LABEL_PREFIX.$name"
    dst="$HOME/Library/LaunchAgents/$label.plist"
    sed -e "s#@LABEL_PREFIX@#$LABEL_PREFIX#g" -e "s#@BIN_DIR@#$BIN_DIR#g" \
        -e "s#@PYTHON@#$BRIDGE_VENV/bin/python#g" -e "s#@BRIDGE_LISTEN@#$BRIDGE_LISTEN#g" \
        -e "s#@VM_IP@#$VM_IP#g" -e "s#@VM_NAME@#$VM_NAME#g" -e "s#@SERIAL_PORT@#$SERIAL_PORT#g" \
        "$HERE/launchd/$name.plist.tmpl" > "$dst"
    plutil -lint -s "$dst"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$dst"
    echo "loaded $label"
done
echo "Restart UTM once so App Nap stays off. Logs: /tmp/klipper-serial-bridge.log, /tmp/klipper-vm.log"
