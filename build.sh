#!/bin/zsh
# Builds WisprRing.app into ~/Applications and signs it.
# Signing identity: $SIGN_ID, else the contents of .sign-id, else ad-hoc ("-").
# Ad-hoc works, but macOS forgets the app's permissions on every rebuild.
# Sign with your own "Apple Development" certificate to keep them:
#   security find-identity -p codesigning -v      # copy the 40-character hash
#   echo <hash> > .sign-id
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/WisprRing.app"
ID="${SIGN_ID:-$( [ -f .sign-id ] && cat .sign-id || echo - )}"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/WisprRing"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$ID" --identifier local.wisprring "$APP"
echo "built $APP"
