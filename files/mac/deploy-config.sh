#!/bin/bash
# Copy the stack installer into the VM and push printer.cfg, macros.cfg and
# moonraker.conf. First install and restores only: day-to-day changes happen in
# the VM (Mainsail editor, SAVE_CONFIG), so once deployed this refuses to
# overwrite a VM file that differs from the repo copy unless --force.
#
#   LAN_CIDR=192.168.1.0/24 files/mac/deploy-config.sh [--force]
#
# LAN_CIDR (required): your LAN, trusted by Moonraker. SSH_ALIAS defaults to klipper-vm.
set -euo pipefail
FILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_ALIAS="${SSH_ALIAS:-klipper-vm}"
: "${LAN_CIDR:?set LAN_CIDR to your LAN, e.g. 192.168.1.0/24}"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
VMCFG=printer_data/config
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$FILES_DIR/klipper/printer.cfg" "$FILES_DIR/klipper/macros.cfg" "$TMP/"
sed "s#@LAN_CIDR@#$LAN_CIDR#" "$FILES_DIR/klipper/moonraker.conf" > "$TMP/moonraker.conf"

ssh "$SSH_ALIAS" "mkdir -p install $VMCFG"
scp -q "$FILES_DIR"/vm/{install-stack.sh,klipper.service,printer-pty.service,mainsail.nginx} "$SSH_ALIAS:install/"
scp -q "$FILES_DIR/firmware/ender3v2-422.config" "$SSH_ALIAS:install/"

if ssh "$SSH_ALIAS" "test -f $VMCFG/.deployed-from-repo" && [ "$FORCE" = 0 ]; then
    for f in printer.cfg macros.cfg moonraker.conf; do
        if ! ssh "$SSH_ALIAS" "cat $VMCFG/$f 2>/dev/null" | cmp -s - "$TMP/$f"; then
            echo "VM $f differs from the repo copy: pull it first, or --force to overwrite" >&2
            exit 1
        fi
    done
    echo "VM already matches the repo"; exit 0
fi
for f in printer.cfg macros.cfg moonraker.conf; do scp -q "$TMP/$f" "$SSH_ALIAS:$VMCFG/$f"; done
ssh "$SSH_ALIAS" "touch $VMCFG/.deployed-from-repo; systemctl list-unit-files klipper.service >/dev/null 2>&1 && sudo systemctl restart moonraker klipper || true"
echo "deployed installer to ~/install and config to ~/$VMCFG"
