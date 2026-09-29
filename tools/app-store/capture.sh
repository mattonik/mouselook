#!/bin/bash
# Captures raw App Store screens from the iPad simulator into store/raw/.
# The 13-inch iPad simulator's screenshots are exactly the App Store's
# 2752 x 2064, so they need no scaling. Debug build (it has the screenshot
# scenes, see Apps/PointerLocker/ScreenshotScene.swift).
#
#   tools/app-store/capture.sh                      # every scene below
#   tools/app-store/capture.sh get-ready settings   # just these
#
# Scenes:
#   welcome    onboarding's first page
#   get-ready  Get ready for Figma, mouse and keyboard connected
#   settings   Settings over Figma, service checks passed
#   menu       Figma with the ⋯ menu open (you open it; the script waits)
#
# Before running: the simulator is in landscape and not in Stage Manager
# (Stage Manager puts a resize handle in the corner). SIM=<udid> picks a
# simulator other than the booted 13-inch iPad.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

sim=${SIM:-$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
booted = [d for l in json.load(sys.stdin)['devices'].values() for d in l if 'iPad Pro 13' in d['name']]
print(booted[0]['udid'] if booted else '')")}
[ -n "$sim" ] || { echo "Boot an iPad Pro 13-inch simulator first (or set SIM)."; exit 1; }
bundle=sk.icebear.mouselook
out=store/raw
mkdir -p "$out" build

echo "Building for $sim…"
xcodegen -q
xcodebuild build -project PointerLocker.xcodeproj -scheme PointerLocker -configuration Debug \
    -destination "id=$sim" -derivedDataPath build CODE_SIGNING_ALLOWED=NO > build/capture.log 2>&1 \
    || { echo "Build failed (build/capture.log)"; exit 1; }
xcrun simctl install "$sim" build/Build/Products/Debug-iphonesimulator/PointerLocker.app

# Apple's usual status bar: 9:41, full battery, full Wi-Fi.
xcrun simctl status_bar "$sim" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode notSupported

launch() {
    xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
    # Launching before the old process is gone brings that one back instead,
    # without the new arguments.
    for _ in $(seq 20); do
        xcrun simctl spawn "$sim" launchctl list | awk -v b="UIKitApplication:$bundle" \
            'index($3, b) == 1 && $1 != "-" { found = 1 } END { exit !found }' || break
        sleep 0.5
    done
    sleep 1
    xcrun simctl launch "$sim" "$bundle" "$@" >/dev/null
}

shoot() {
    local file="$out/$1.png"
    xcrun simctl io "$sim" screenshot --type=png "$file" >/dev/null 2>&1
    # The simulator saves the screen in portrait; turn it to landscape.
    local w h
    w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')
    [ "$w" -lt "$h" ] && sips -r "${ROTATE:-270}" "$file" >/dev/null
    echo "  $file ($(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/ {printf "%s ", $2}'))"
}

scenes=${*:-welcome get-ready settings menu}
for scene in $scenes; do
    echo "$scene"
    case $scene in
        welcome)   launch -serviceID none; sleep 4 ;;
        get-ready) launch -serviceID figma -screenshotScene getReady; sleep 4 ;;
        settings)  launch -serviceID figma -screenshotScene settings; sleep 8 ;;
        menu)      launch -serviceID figma
                   read -r -p "  Open the ⋯ menu in the simulator, then press Return. " ;;
        *)         echo "  unknown scene"; continue ;;
    esac
    shoot "$scene"
done

xcrun simctl status_bar "$sim" clear
