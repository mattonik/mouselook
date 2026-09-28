#!/bin/bash
# Runs everything CI runs, on this Mac: the Swift unit tests on an iPad
# simulator and the polyfill tests in Playwright. Builds are incremental
# (derived data in build/), so repeat runs take seconds, not minutes.
#
#   tools/test.sh          # both suites
#   tools/test.sh swift    # Swift only
#   tools/test.sh js       # polyfill only
#   tools/test.sh swift -only-testing:PointerLockerTests/ServiceCategoryTests
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

what=${1:-all}
[ $# -gt 0 ] && shift
status=0
log=build/last-test.log
mkdir -p build

if [ "$what" = all ] || [ "$what" = swift ]; then
    xcodegen -q
    # An iPad on the newest iOS runtime installed (same choice as CI).
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, re, sys
devices = json.load(sys.stdin)['devices']
version = lambda runtime: [int(n) for n in re.findall(r'\d+', runtime.rsplit('iOS', 1)[-1])]
ipads = [(version(r), x['udid']) for r, l in devices.items() if 'iOS' in r for x in l if x['name'].startswith('iPad')]
print(max(ipads)[1])")
    xcodebuild test -project PointerLocker.xcodeproj -scheme PointerLocker \
        -destination "id=$udid" -derivedDataPath build CODE_SIGNING_ALLOWED=NO "$@" > "$log" 2>&1
    swift_status=$?
    grep -E "\.swift:[0-9]+:[0-9]*:? error:|failed \(" "$log" | sort -u | head -20
    grep -E "Executed [0-9]+ tests" "$log" | tail -1
    grep -E "TEST (SUCCEEDED|FAILED)|BUILD FAILED" "$log" | tail -1
    [ $swift_status -ne 0 ] && echo "Swift: failed (full log: $log)" && status=1
fi

if [ "$what" = all ] || [ "$what" = js ]; then
    npm test 2>&1 | grep -E "^FAIL|^     |failed|passed"
    [ "${PIPESTATUS[0]}" -ne 0 ] && echo "Polyfill tests: failed" && status=1
fi

exit $status
