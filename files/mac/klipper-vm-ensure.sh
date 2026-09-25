#!/bin/bash
# Keep the Klipper VM running. The VM LaunchAgent runs this at login and every
# 5 minutes. VM_NAME defaults to "klipper".
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
VM_NAME="${VM_NAME:-klipper}"
status="$(utmctl status "$VM_NAME" 2>/dev/null || echo missing)"
case "$status" in
    started|starting|resuming) exit 0 ;;
    paused) echo "$(date '+%F %T') VM paused, resuming"; utmctl resume "$VM_NAME" ;;
    missing) echo "$(date '+%F %T') VM $VM_NAME not found (run create-vm.sh)"; exit 1 ;;
    *) echo "$(date '+%F %T') VM is $status, starting"; utmctl start --hide "$VM_NAME" ;;
esac
