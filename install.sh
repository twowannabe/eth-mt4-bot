#!/bin/bash
set -e

echo "=== 1. System update ==="
apt update && apt upgrade -y

echo "=== 2. Install Wine ==="
dpkg --add-architecture i386
apt update
apt install -y wine64 wine32 xvfb wget x11vnc git

echo "=== 3. Install MT4 ==="
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x16 &
sleep 2

wget -O /tmp/mt4setup.exe "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt4/mt4oldsetup.exe"
wine /tmp/mt4setup.exe

echo ""
echo ">>> MT4 installer launched. Use VNC to complete installation:"
echo ">>> Run: x11vnc -display :99 -forever -nopw &"
echo ">>> Then connect VNC client to server_ip:5900"
echo ""

echo "=== 4. Install ZeroMQ for MT4 ==="
MT4_DIR="/root/.wine/drive_c/Program Files (x86)/MetaTrader 4"

cd /tmp
if [ ! -d mql-zmq ]; then
    git clone https://github.com/dingmaotu/mql-zmq.git
fi

mkdir -p "$MT4_DIR/MQL4/Include/Zmq"
mkdir -p "$MT4_DIR/MQL4/Libraries"
mkdir -p "$MT4_DIR/MQL4/Experts"

cp /tmp/mql-zmq/Include/Zmq/*.mqh "$MT4_DIR/MQL4/Include/Zmq/"
cp /tmp/mql-zmq/Include/*.mqh "$MT4_DIR/MQL4/Include/" 2>/dev/null || true
cp /tmp/mql-zmq/Library/MT4/*.dll "$MT4_DIR/MQL4/Libraries/" 2>/dev/null || true

echo "=== 5. Copy EA ==="
cp /root/repos/eth-mt4-bot/mt4_ea/ZMQ_Bridge.mq4 "$MT4_DIR/MQL4/Experts/"

echo "=== 6. Clone bot repo ==="
mkdir -p /root/repos
cd /root/repos
if [ ! -d eth-mt4-bot ]; then
    git clone https://github.com/twowannabe/eth-mt4-bot.git
fi

echo "=== 7. Install Python deps ==="
/root/bots/bin/pip install pyzmq

echo "=== 8. Install services ==="
cp /root/repos/eth-mt4-bot/mt4.service /etc/systemd/system/
cp /root/repos/eth-mt4-bot/eth-bot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable mt4 eth-bot

echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Start VNC:  x11vnc -display :99 -forever -nopw &"
echo "  2. Connect VNC client to $(hostname -I | awk '{print $1}'):5900"
echo "  3. In MT4:"
echo "     - Log into your broker account"
echo "     - Open ETHUSD chart"
echo "     - Compile ZMQ_Bridge EA in MetaEditor"
echo "     - Attach ZMQ_Bridge EA to ETHUSD chart"
echo "     - Enable AutoTrading"
echo "     - Allow DLL imports"
echo "  4. Start services:"
echo "     systemctl start mt4"
echo "     sleep 30"
echo "     systemctl start eth-bot"
echo "  5. Check logs:"
echo "     journalctl -u eth-bot -f"
echo ""
