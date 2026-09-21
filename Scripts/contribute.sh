#!/bin/bash
#
# Offers a fork's changes back to the repo it came from, as a draft PR.
#
# The point of this existing at all: PR Radar is meant to be forked and made
# yours, so most improvements to it happen on somebody else's machine and stop
# there. Nobody is going to read CONTRIBUTING.md to decide whether a two-line
# fix is worth the ceremony. This makes the answer one keypress.
#
# It is deliberately *not* silent. It runs as you, with your `gh` credentials,
# and opening a public pull request is the kind of thing that should never be
# a surprise — so it shows what it would send and waits for a yes.
#
#   Scripts/contribute.sh            propose now
#   Scripts/contribute.sh --offer    what the git hook calls: quiet unless
#                                    there is something worth offering
#   Scripts/contribute.sh --check    exit 0 if there is, 1 if not; says nothing
#
# Turn the offer off for good:  git config prradar.contribute false
set -euo pipefail

# Where a fork's changes are offered back to, and the identifier this project
# is published under. Both travel with the clone, which is the point — a fork
# inherits them and so knows where it came from.
UPSTREAM="RogelioAD/pr-radar"
CANONICAL_ID="com.rogelioacosta.prradar"

# Never offered, whatever else is in the commit.
#
# The README asks a fork to put its team's real GitHub logins in here. Those
# are other people's names, they are nobody upstream's business, and a script
# that published them to a public pull request because somebody typed `git
# commit` would be doing real harm on their behalf.
NEVER_SHARE="Sources/PRRadarCore/MyPR/Leads.swift"

MODE="${1:---run}"

say() { [ "$MODE" = "--check" ] || printf '%s\n' "$*"; }
quiet_fail() { [ "$MODE" = "--run" ] && printf '%s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- where we are

origin_url=$(git remote get-url origin 2>/dev/null || true)
[ -n "$origin_url" ] || quiet_fail "no 'origin' remote to propose from."

# owner/name out of either URL form, with any .git suffix dropped.
origin_slug=$(printf '%s' "$origin_url" \
    | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
owner=${origin_slug%%/*}

# The upstream repo has nothing to propose to itself.
[ "$origin_slug" != "$UPSTREAM" ] || exit 1
# Nor does anyone who has pointed their fork somewhere else entirely.
case "$origin_slug" in */*) ;; *) exit 1 ;; esac

[ "$(git config --get prradar.contribute || echo true)" != "false" ] || exit 1

# --------------------------------------------------- what is worth proposing

# Against the fork's own main, not upstream's: this has to be cheap enough to
# run on every commit, and reaching the network to answer "is there anything
# here" would make every commit wait on GitHub. The real comparison happens
# once you have said yes.
base_ref=""
for candidate in origin/main origin/master main master; do
    if git rev-parse --verify -q "$candidate" >/dev/null; then
        base_ref="$candidate"
        break
    fi
done
[ -n "$base_ref" ] || exit 1

base=$(git merge-base HEAD "$base_ref" 2>/dev/null) || exit 1
[ "$base" != "$(git rev-parse HEAD)" ] || exit 1

# Only commits this person wrote.
#
# Without this, a fork that pulls a branch from upstream and then commits one
# line of its own offers the whole branch back — every commit it merely
# received, attributed to somebody who did not write them. Authorship is the
# cheapest honest answer to "which of this is yours", and it needs no network.
me=$(git config user.email 2>/dev/null || true)
[ -n "$me" ] || exit 1
mine=$(git rev-list "$base..HEAD" --author="$me" 2>/dev/null || true)
[ -n "$mine" ] || exit 1

# A file whose only changed lines mention a bundle identifier is somebody
# making the app theirs, not improving it. `grep -c` rather than a diff of
# diffs because this runs on every commit.
has_real_change() {
    git diff "$base" HEAD -- "$1" \
        | grep -E '^[+-]' \
        | grep -vE '^(\+\+\+|---)' \
        | grep -vqE 'com\.[A-Za-z0-9_-]+\.prradar'
}

# Files touched by *those* commits, rather than by everything since the base.
touched=$(printf '%s\n' "$mine" \
    | while IFS= read -r sha; do
        [ -n "$sha" ] || continue
        git show --pretty=format: --name-only "$sha"
    done | sed '/^$/d' | sort -u)

files=""
while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ "$file" != "$NEVER_SHARE" ] || continue
    has_real_change "$file" || continue
    files="$files$file"$'\n'
done <<< "$touched"

files=$(printf '%s' "$files" | sed '/^$/d')
[ -n "$files" ] || exit 1

count=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
[ "$MODE" != "--check" ] || exit 0

# ------------------------------------------------------------------ the offer

say ""
say "  This fork has changes the original might want:"
say ""
# Ten is enough to recognise the work by. A wall of sixty filenames is not
# a summary, it is a reason to stop reading and say yes to anything.
printf '%s\n' "$files" | head -10 | sed 's/^/      /'
[ "$count" -le 10 ] || say "      … and $((count - 10)) more"
say ""
say "  Proposing them opens a *draft* pull request on $UPSTREAM, as you."
say "  Your bundle identifier is rewritten back to the original's and"
say "  $NEVER_SHARE is never included."
say ""

# Opened rather than tested. `[ -r /dev/tty ]` is true in plenty of places
# where reading it then fails with "Device not configured" — a detached
# process has the node but no terminal behind it.
answer=""
if { exec 3<>/dev/tty; } 2>/dev/null; then
    printf '  Propose these %s file(s) upstream? [y/N] ' "$count" >&3
    read -r answer <&3 || answer=""
    exec 3>&-
else
    # No terminal to ask at — which is exactly the case when a coding CLI is
    # driving the commit. Saying nothing and doing it anyway is the one
    # behaviour this script exists to avoid, so it leaves a note instead.
    say "  No terminal to ask at. When you want to:"
    say ""
    say "      make contribute"
    say ""
    exit 0
fi

case "$answer" in
    y|Y|yes|Yes|YES) ;;
    *) say ""; say "  Left alone. \`make contribute\` whenever you like."; exit 0 ;;
esac

# ------------------------------------------------------------------- doing it

command -v gh >/dev/null 2>&1 \
    || quiet_fail "needs the GitHub CLI: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 \
    || quiet_fail "gh is not signed in: gh auth login"

say ""
say "  Fetching ${UPSTREAM}…"
git fetch -q "https://github.com/$UPSTREAM.git" main
upstream_main=$(git rev-parse FETCH_HEAD)

branch="from-$owner/$(git rev-parse --short HEAD)"
source_ref=$(git rev-parse HEAD)

# Built in a worktree so the checkout you are standing in is never touched.
# This runs off the back of a commit you just made; moving you onto another
# branch to do it would be an unforgivable thing for a git hook to do.
work=$(mktemp -d)
cleanup() {
    git worktree remove --force "$work" >/dev/null 2>&1 || true
    rm -f "$work.body"
}
trap cleanup EXIT

git worktree add -q --detach "$work" "$upstream_main"
git -C "$work" checkout -q -b "$branch"

while IFS= read -r file; do
    [ -n "$file" ] || continue
    if git cat-file -e "$source_ref:$file" 2>/dev/null; then
        mkdir -p "$work/$(dirname "$file")"
        git show "$source_ref:$file" > "$work/$file"
        # Keep the executable bit, which `git show` does not carry.
        case "$(git ls-tree "$source_ref" -- "$file" | cut -d' ' -f1)" in
            100755) chmod +x "$work/$file" ;;
        esac
    else
        rm -f "$work/$file"
    fi
done <<< "$files"

# Put the original's identifier back, in the contributed files only.
#
# A fork is told to sed its own identifier through the tree, so almost every
# file it touches carries one — and upstream wants the change, not the
# rename.
#
# Scoped to the file list rather than the worktree, which is the whole
# difference between a rewrite and a rampage: run over everything, it also
# edits `com.yourname.prradar` in the README, which is upstream's own
# placeholder in the instructions telling forks to replace it. That
# placeholder is protected here too, in case a contributed file quotes it.
placeholder_guard="__PRRADAR_DOC_PLACEHOLDER__"
while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$work/$file" ] || continue
    grep -qE 'com\.[A-Za-z0-9_-]+\.prradar' "$work/$file" || continue
    /usr/bin/sed -i '' \
        -e "s/com\.yourname\.prradar/$placeholder_guard/g" \
        -e "s/com\.[A-Za-z0-9_-]\{1,\}\.prradar/$CANONICAL_ID/g" \
        -e "s/$placeholder_guard/com.yourname.prradar/g" \
        "$work/$file"
done <<< "$files"

git -C "$work" add -A
if git -C "$work" diff --cached --quiet; then
    say ""
    say "  Nothing left once your own settings were taken out. Nothing sent."
    exit 0
fi

subject=$(git log -1 --format=%s "$source_ref")
git -C "$work" commit -q -m "$subject" -m "Proposed from $origin_slug."
git -C "$work" push -q -u origin "$branch"

# Written to a file rather than captured into a variable. A heredoc inside
# `$( )` that contains an apostrophe is mis-parsed by bash 3.2, which is what
# /bin/bash still is on macOS — and `--body-file` was the better shape anyway.
body_file="$work.body"
cat > "$body_file" <<EOF
Opened by \`Scripts/contribute.sh\` from a fork.

**From:** \`$origin_slug\` · **Commit:** \`$(git rev-parse --short "$source_ref")\`

A draft, on purpose. The author said yes to sending it, which is not the same
as proposing it for merge — read it as *here is what I changed on my copy*
rather than as a request.

Left out automatically: \`$NEVER_SHARE\`, and any change that was only a
bundle identifier. Both are how a fork makes the app its own, and neither
belongs in somebody else's repository.
EOF

say "  Opening a draft pull request…"
url=$(gh pr create \
    --repo "$UPSTREAM" \
    --head "$owner:$branch" \
    --base main \
    --draft \
    --title "From a fork: $subject" \
    --body-file "$body_file" 2>&1 | tail -1)

say ""
say "  $url"
say ""
