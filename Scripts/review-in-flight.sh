#!/bin/sh
# Refuses an install that would kill a review in progress.
#
# `make install` pkills the running copy, and until it did so silently that was
# the commonest way to lose a review: a Claude Code session with ten minutes and
# real money in it, taken out mid-sentence. The app recovers — anything it finds
# `running` at launch goes back in the queue — but recovering means paying for
# the whole run a second time, so it is worth one question first.
#
# Set FORCE=1 to install anyway.

if [ "${FORCE:-0}" = "1" ]; then
    exit 0
fi

# Nothing can be in flight if nothing is running. Checked first, and this is
# also what stops a stale record left by an older build from wedging `install`
# shut with no way to get the fix for it onto the machine.
if ! pgrep -f 'PRRadar\.app/Contents/MacOS/PRRadar' >/dev/null 2>&1; then
    exit 0
fi

running=$(defaults export com.rogelioacosta.prradar - 2>/dev/null | python3 -c '
import sys, plistlib, json
try:
    blob = plistlib.loads(sys.stdin.buffer.read()).get("review.log")
    records = json.loads(blob).get("records", {}) if blob else {}
except Exception:
    # A prefs file we cannot read is not a reason to block an install.
    raise SystemExit(0)
for key, record in sorted(records.items()):
    if record.get("status") == "running":
        print(key)
' 2>/dev/null)

if [ -z "$running" ]; then
    exit 0
fi

echo "==> a review is still running:"
echo "$running" | sed 's/^/      /'
echo
echo "    Installing now kills it mid-review. It will be re-queued at the next"
echo "    launch, but the run so far — and what it cost — is lost."
echo
echo "    Wait for it to finish, or install anyway with:  FORCE=1 make install"
exit 1
