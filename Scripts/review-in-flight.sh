#!/bin/sh
# Refuses an install that would kill a review or a resolve in progress.
#
# `make install` pkills the running copy, and until it did so silently that was
# the commonest way to lose a review: a Claude Code session with ten minutes and
# real money in it, taken out mid-sentence. The app recovers — anything it finds
# `running` at launch goes back in the queue — but recovering means paying for
# the whole run a second time, so it is worth one question first.
#
# **A resolve run is the worse case and was not checked at all**, which was an
# oversight this nearly paid for: a resolve edits the developer's own checkout,
# commits and pushes, and is deliberately *never* re-queued, because nothing can
# tell from outside how far it got. Killing one does not cost a repeated run, it
# costs knowing what happened to a branch. So both logs are read, and a resolve
# in flight says so in stronger terms.
#
# Set FORCE=1 to install anyway.

if [ "${FORCE:-0}" = "1" ]; then
    exit 0
fi

root=$(cd "$(dirname "$0")/.." && pwd)

# Read from bundle.sh rather than written down again here. The README tells a
# fork to rename the bundle identifier and lists the files to do it in; this
# script is not one of them, so a second copy of the string would have gone
# stale on every fork and quietly stopped matching any domain at all — leaving
# a guard that never fires and never says why.
bundle_id=$(sed -n 's/^BUNDLE_ID="\(.*\)"$/\1/p' "$root/Scripts/bundle.sh")
app_name=$(sed -n 's|^APP="\$ROOT/\(.*\)"$|\1|p' "$root/Scripts/bundle.sh")
: "${app_name:=PRRadar.app}"

if [ -z "$bundle_id" ]; then
    echo "==> note: could not read BUNDLE_ID from Scripts/bundle.sh;"
    echo "    installing without checking for a review in progress."
    exit 0
fi

# Nothing can be in flight if nothing is running. Checked first, and this is
# also what stops a stale record wedging `install` shut with no way to get the
# fix for it onto the machine.
if ! pgrep -f "$app_name/Contents/MacOS/" >/dev/null 2>&1; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "==> note: python3 not found, so a review in progress cannot be"
    echo "    detected. Installing anyway — check the drawer first."
    exit 0
fi

running=$(defaults export "$bundle_id" - 2>/dev/null | python3 -c '
import sys, plistlib, json
try:
    prefs = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    # A prefs file we cannot read is not a reason to block an install.
    raise SystemExit(0)
for key_name, label in (("review.log", "review"), ("resolve.log", "resolve")):
    try:
        blob = prefs.get(key_name)
        records = json.loads(blob).get("records", {}) if blob else {}
    except Exception:
        continue
    for key, record in sorted(records.items()):
        if record.get("status") == "running":
            print(label, key)
' 2>/dev/null)

if [ -z "$running" ]; then
    exit 0
fi

echo "==> something is still running:"
echo "$running" | sed 's/^/      /'
echo

if echo "$running" | grep -q "^resolve "; then
    echo "    A RESOLVE run is writing to one of your own checkouts. Installing"
    echo "    now kills it part-way through — possibly between committing and"
    echo "    pushing — and unlike a review it is never retried, because nothing"
    echo "    can tell afterwards how far it got."
    echo
    echo "    Use the Stop button on the row instead: it asks the run to finish"
    echo "    what it is doing rather than killing it."
else
    echo "    Installing now kills it mid-review. It will be re-queued at the next"
    echo "    launch, but the run so far — and what it cost — is lost."
fi

echo
echo "    Wait for it to finish, or install anyway with:  FORCE=1 make install"
exit 1
