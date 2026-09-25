#!/bin/bash
# Install Klipper, Moonraker, Mainsail (nginx) and mainsail-config in the VM.
# Runs IN the VM as user klipper, from ~/install (files/mac/deploy-config.sh
# copies it there). Idempotent: re-run it after every Klipper update, because
# `git pull` reverts the TRSYNC_TIMEOUT edit below.
# Uses each project's own installer: KIAUH is an interactive TUI.
#
#   BRIDGE_ADDR=192.168.64.1:7523 bash ~/install/install-stack.sh
set -euo pipefail
BRIDGE_ADDR="${BRIDGE_ADDR:-192.168.64.1:7523}"
cd ~
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx unzip git >/dev/null
[ -d klipper ] || git clone -q https://github.com/Klipper3d/klipper.git
[ -d moonraker ] || git clone -q https://github.com/Arksine/moonraker.git
[ -d mainsail-config ] || git clone -q https://github.com/mainsail-crew/mainsail-config.git
mkdir -p ~/printer_data/{config,logs,gcodes,comms,systemd}

# Homing/probing trsync margin 25 -> 50 ms for the VM + TCP bridge path
# (docs/adr/0001): short stalls abort probing moves with "Timer too close" /
# "Communication timeout during homing" at the stock 25 ms.
sed -i 's/^TRSYNC_TIMEOUT = 0.025$/TRSYNC_TIMEOUT = 0.050  # VM + TCP serial bridge path/' \
    ~/klipper/klippy/mcu.py
grep -q '^TRSYNC_TIMEOUT = 0.050' ~/klipper/klippy/mcu.py \
    || { echo "TRSYNC_TIMEOUT line not found in klippy/mcu.py: upstream changed it, patch by hand" >&2; exit 1; }

# Klipper host: own venv + unit (upstream install-debian.sh is Python 2).
# The ARM toolchain is for building the board firmware in the VM.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-venv python3-dev \
    libffi-dev build-essential libncurses-dev pkg-config libusb-1.0-0-dev \
    gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi stm32flash >/dev/null
[ -x ~/klippy-env/bin/python ] || python3 -m venv ~/klippy-env
~/klippy-env/bin/pip install -q -r ~/klipper/scripts/klippy-requirements.txt
sudo cp ~/install/klipper.service /etc/systemd/system/klipper.service
sudo systemctl daemon-reload
sudo systemctl enable -q klipper
sudo systemctl restart klipper

[ -x ~/moonraker-env/bin/python ] || ~/moonraker/scripts/install-moonraker.sh

if [ ! -f ~/mainsail/index.html ]; then
    mkdir -p ~/mainsail
    curl -fsSL -o /tmp/mainsail.zip https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
    unzip -qo /tmp/mainsail.zip -d ~/mainsail && rm /tmp/mainsail.zip
fi
sudo cp ~/install/mainsail.nginx /etc/nginx/sites-available/mainsail
sudo ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t -q && sudo systemctl reload nginx
ln -sf ~/mainsail-config/client.cfg ~/printer_data/config/mainsail.cfg

sed "s#tcp:192.168.64.1:7523#tcp:$BRIDGE_ADDR#" ~/install/printer-pty.service \
    | sudo tee /etc/systemd/system/printer-pty.service >/dev/null
sudo systemctl daemon-reload   # installed, NOT enabled: enabled at the cutover
echo "stack installed (TRSYNC_TIMEOUT 0.050, printer-pty -> $BRIDGE_ADDR, disabled)"
