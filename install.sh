#!/bin/zsh
# Builds WisprRing and starts it now and at every login.
set -e
cd "$(dirname "$0")"
./build.sh
PLIST="$HOME/Library/LaunchAgents/local.wisprring.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.wisprring</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/Applications/WisprRing.app/Contents/MacOS/WisprRing</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/local.wisprring" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "WisprRing is running and will start at login."
echo "Now allow WisprRing in System Settings > Privacy & Security > Input Monitoring and Accessibility,"
echo "then run: launchctl kickstart -k gui/\$(id -u)/local.wisprring"
