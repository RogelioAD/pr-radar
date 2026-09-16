# PR Radar — Setup

A floating macOS badge that shows how many pull requests are waiting on your
review, and expands into a drawer covering both those and your own open PRs.

**→ [FEATURES.md](FEATURES.md) for what it actually does.** This file is just
how to get it running.

---

## Requirements

| | |
|---|---|
| macOS | 14 or later (built and run on 26) |
| Swift | 5.9+ — Xcode or the Command Line Tools (`xcode-select --install`) |
| [`gh`](https://cli.github.com) | installed and authenticated |

Check all three:

```sh
sw_vers -productVersion     # 14.0 or higher
swift --version             # 5.9 or higher
gh auth status              # must show a logged-in account
```

No other dependencies — no CocoaPods, no SPM packages, no Homebrew formulae
beyond `gh` itself.

---

## 1. Get the code

```sh
git clone <your-fork-url> pr-radar
cd pr-radar
make test          # 142 tests, ~17s. If these pass, your toolchain is fine.
```

Running the tests first is the fastest way to find out whether Swift and the
SDK are set up, before any of the app-bundle machinery gets involved.

## 2. Authenticate GitHub

PR Radar reuses your existing `gh` login — there is no token to paste.

```sh
gh auth login                       # if you haven't already
gh auth status                      # confirm the scopes
```

It needs **`repo`** and **`read:org`**. `read:org` is what lets it discover
your teams, which is how team-assigned review requests are found. Without it
the app still works, but only shows reviews requested from you personally.

If you would rather not depend on `gh`, store a token in the Keychain instead
and the app will fall back to it:

```sh
security add-generic-password -s PRRadar -a token -w ghp_yourtoken
```

## 3. Make it yours

Two things are specific to whoever built this. Change both before installing.

### The bundle identifier

It appears in three files. Replace it with your own reverse-DNS id:

```sh
grep -rl com.rogelioacosta.prradar Makefile Scripts/bundle.sh Sources/ \
  | xargs sed -i '' 's/com\.rogelioacosta\.prradar/com.yourname.prradar/g'
```

This matters more than it looks: the identifier is the key macOS uses for
notification permission, saved preferences, and the login item. Leaving someone
else's id in place means colliding with their settings if you ever run both.

### Your review leads

The **My PRs** tab highlights whether a *lead* has approved — the reviewers
whose sign-off actually unblocks a merge on your team. **No leads ship by
default**, so until you set yours the lead chip always reads `lead needed`.

Set them at runtime, no rebuild needed:

```sh
defaults write com.yourname.prradar leads.logins -array alice bob carol
```

Or bake your team in as the default, in `Sources/PRRadarCore/MyPR/Leads.swift`:

```swift
public static let defaultLogins: [String] = ["alice", "bob"]
public static let displayNames: [String: String] = ["alice": "Alice"]
```

`displayNames` only shortens what a chip shows; any login without an entry is
displayed as-is. If your team has no lead concept, leave it empty — nothing
else depends on it.

## 4. Install

```sh
make install
```

That builds in release mode, assembles `PRRadar.app`, ad-hoc signs it, stops
any copy already running, copies it to `/Applications`, registers a LaunchAgent
so it starts at login, and launches it.

Only one copy runs at a time: a second exits at launch rather than placing a
panel. Two would restore the same badge position at the same window level, so
whichever landed in front would hide the other's count badges.

**The badge appears in the bottom-right of your screen within about a minute** —
it stays hidden until the first fetch returns, so an empty screen for a few
seconds is normal.

There is **no Dock icon and no menu bar item**. Right-click the badge for the
menu: refresh, toggle start-at-login, and quit. That menu is the only way to
quit it.

## 5. Confirm it works

```sh
make print
```

This does one fetch and prints what the drawer would show — token source,
your login, your teams, the review queue, and your own PRs. It is the fastest
way to tell an auth problem from a UI problem.

Cross-check the count against GitHub directly:

```sh
gh api "search/issues?q=is:open+is:pr+review-requested:@me" --jq '.total_count'
```

The two should agree.

---

## Troubleshooting

**No badge at all.** It hides itself when there is nothing waiting *and* you
have no open PRs. Confirm with `make print`; if that lists items but no badge
appears, check the process is alive: `pgrep -fl PRRadar`.

**A grey `!` on the badge.** The token broke. This state is deliberately
distinct from a count of zero, so a broken setup never looks like an empty
queue. Run `make print` for the actual error — usually an expired `gh` login.

**Badge shows `!` only after a reboot.** A GUI-launched app inherits no shell
`PATH`, so `gh` cannot be found by name. The app looks in
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` and `/opt/local/bin`. If your
`gh` is somewhere else, add the path to `ghCandidates` in
`Sources/PRRadarCore/GitHub/Token.swift`.

**No notifications.** They need a real app bundle, so `make run` (unbundled)
falls back to `osascript` banners. From the installed app, check System
Settings → Notifications. An ad-hoc-signed app can be refused, in which case
it degrades to badge-only rather than nagging you.

**Nothing on the My PRs tab.** Only *open* PRs authored by you appear. Check
with `gh pr list --author @me`.

**Lead chip always says `lead needed`.** Either you have not set any lead
logins (there are none by default — see above), or no lead has a *live*
approval. Note that a **dismissed** approval
does not count — see [FEATURES.md](FEATURES.md#the-lead-gate).

---

## Development

```sh
make build    # debug build
make test     # 89 unit tests
make run      # run unbundled — fast iteration, notifications degrade
make print    # one fetch, printed to stdout
make bundle   # assemble PRRadar.app without installing it
make install  # bundle + /Applications + login item
make uninstall
make clean
```

### Releasing

```sh
make release VERSION=1.1.0
```

Stamps the version into `Scripts/bundle.sh`, runs the tests, commits, tags,
pushes, and publishes a GitHub release. It refuses on a dirty working tree.

The notes are the generated changelog with the upgrade command prepended —
see `RELEASE_NOTES` in the Makefile. That preamble is not decoration: the
update chip links to the release page, so it is what someone reads the moment
they act on the chip.

That release is what notifies everyone: GitHub emails collaborators who watch
the repo for releases, and running copies show an `update 1.1.0` chip within
six hours.

Tell collaborators to enable it once, on the repo page:
**Watch → Custom → Releases**.

### Debug flags

Several bits of state are hard to reproduce on demand — you cannot conjure a
failing check or a branch that is behind. These force them:

```sh
PRRADAR_DEBUG=1           # trace refreshes, layout, notification auth to stderr,
                          # and dump a hit-test zone map each time the drawer opens
PRRADAR_EXPAND=1          # open the drawer on launch, to inspect it without clicking
PRRADAR_APPEARANCE=light  # force Light or Dark, to check the other colour scheme
PRRADAR_FAKE_BEHIND=3     # make your PRs look N commits behind, to see the
                          # "needs rebase" chip
PRRADAR_FAKE_READY=1      # make your PRs look mergeable, to see the green badge
```

### Working on this with Claude Code

The useful thing to know is that **this project is verifiable without clicking
anything**, which is what makes it pleasant to hand to an agent:

- `make print` proves the whole data path — auth, fetch, parse, derived state —
  with no GUI involved.
- `make test` covers every rule worth arguing about (see below).
- `PRRADAR_DEBUG=1` prints a hit-test zone map of the real laid-out drawer, so
  drag and click regions can be checked without a mouse.
- `screencapture -x -o -l <windowid>` grabs just this app's window. **But it
  excludes the backdrop**, so translucent materials render dark and can look
  fine when they are actually unreadable. Use `screencapture -RX,Y,W,H` (no
  space after `-R`) to capture composited pixels when judging contrast.

### Project layout

```
Sources/PRRadarCore/   fetching, parsing, and every rule worth testing:
                       the dismiss rule, the lead gate, branch state, drawer
                       sizing, hit-test zones, click-vs-drag
Sources/PRRadar/       the app: panel, badge, tabs, drawer, notifications
Tests/                 142 tests
Scripts/bundle.sh      assembles and ad-hoc signs PRRadar.app
```

The split is deliberate: anything with a rule in it lives in `PRRadarCore` as a
pure function so it can be tested, and the app target is left as thin wiring.

### Implementation notes

Four things in here cost real debugging time and are worth knowing before you
change the relevant code.

**`NSHostingView.isFlipped` is `true`** — its coordinates run top-left origin,
unlike a plain `NSView`. Hit-testing written as `point.y >= bounds.height -
inset` therefore selects the *bottom* of the view. That inverted every drag
zone once: the footer became the drag handle, so clicking Refresh registered as
a click on the header and collapsed the drawer, while the real header and
resize edge did nothing. The rules now live in `DrawerZones`, keyed off a
distance-from-top the view computes using its own `isFlipped`.

**`performDrag(with:)` returns immediately** rather than blocking until
mouse-up, so comparing pointer positions around it reports every drag as a
click. Drag tracking is explicit in `DraggableHostingView`, and the decision
itself is in `PressTracker` so it can be tested.

**The app bundle is not cosmetic.** An unbundled SwiftPM binary has no bundle
identifier, and `UNUserNotificationCenter.current()` traps in that state.
Notifications only work from a real bundle.

**Start-at-login uses a LaunchAgent**, not `SMAppService`, which expects a
properly signed bundle and is unreliable for an ad-hoc-signed local build.

---

## Uninstall

```sh
make uninstall
```

Removes the app, the LaunchAgent, and stops the running process. Your saved
preferences remain; clear them with:

```sh
defaults delete com.yourname.prradar
```
