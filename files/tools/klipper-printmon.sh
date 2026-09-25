#!/bin/bash
# Print one line per notable event of a Klipper print: console errors, link
# retransmits, every 25 % of progress, and the end. Run it from a machine with
# a stable connection to the VM (the Mac itself is best).
#
#   klipper-printmon.sh [host]        host defaults to $KLIPPER_HOST
# host = the VM's LAN IP or name (Mainsail's nginx on port 80 proxies Moonraker).
HOST="${1:-${KLIPPER_HOST:-}}"
[ -n "$HOST" ] || { echo "usage: $0 <vm-lan-ip>   (or set KLIPPER_HOST)" >&2; exit 2; }
K="http://$HOST"; last=$(date +%s); lastq=-1; retx0=""
while true; do
  line=$(curl -s -m 5 "$K/printer/objects/query?print_stats&virtual_sdcard=progress&mcu&save_variables" | python3 -c '
import json,sys
st=json.load(sys.stdin)["result"]["status"]; p=st["print_stats"]; m=st["mcu"]["last_stats"]
v=st.get("save_variables",{}).get("variables",{})
print(p["state"], round(st["virtual_sdcard"]["progress"]*100,1), m["bytes_retransmit"], round(m["srtt"]*1000,1), v.get("plr_layer"))' 2>/dev/null)
  if [ -z "$line" ]; then echo "WARN moonraker unreachable"; sleep 20; continue; fi
  read -r state prog retx srtt layer <<<"$line"
  [ -z "$retx0" ] && retx0=$retx
  curl -s -m 5 "$K/server/gcode_store?count=40" | python3 -c '
import json,sys
last=float(sys.argv[1])
for x in json.load(sys.stdin)["result"]["gcode_store"]:
    t=x["message"]
    if x["time"]>last and (t.startswith("!!") or "Timer too close" in t or "Lost communication" in t or "Failed" in t or "rror" in t): print("CONSOLE", t[:160])' "$last" 2>/dev/null
  last=$(date +%s)
  if [ "$retx" != "$retx0" ]; then echo "LINK retransmits $retx0 -> $retx (srtt ${srtt} ms, layer $layer)"; retx0=$retx; fi
  q=$(python3 -c "print(int(float('$prog')//25))")
  if [ "$q" != "$lastq" ]; then [ "$lastq" != "-1" ] && echo "PROGRESS $prog% layer $layer srtt ${srtt} ms retx $retx"; lastq=$q; fi
  case "$state" in complete|cancelled|error|standby) echo "END state=$state progress=$prog% layer=$layer retx=$retx"; exit 0;; esac
  sleep 20
done
