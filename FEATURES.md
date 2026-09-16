# PR Radar

A floating macOS badge that answers two questions without opening a browser:
**who is waiting on me**, and **how is my own work doing**.

It sits above every window, sized to match your Dock icons, and expands into a
drawer when clicked. Setup lives in [README.md](README.md).

---

## The badge

A rounded-square tile carrying a pull-request glyph, with **two Dock-style
count badges** — identical in size and styling, differing only in colour and
corner:

| | |
|---|---|
| **Red, top-right** | review requests waiting on you — work you owe other people |
| **Green, bottom-right** | your own PRs that are ready to merge |

They are kept separate so each number means exactly one thing. Both follow the
**repository filter**: pick a repo and the counts show only that repo's work,
because "I'm in this repo today" is a scope rather than a temporary view. The
author and state filters deliberately do *not* affect them — the badge would
otherwise flicker every time you poked at a menu. The red count is
tinted by how stale the *oldest* request is: blue under a day, amber at 1–3
days, red beyond 3 — so a queue that has gone unattended looks different from a
fresh one at a glance.

The green badge is deliberately about **merging, not breakage**. Failing checks
and conflicts colour the row inside the drawer, but they do not appear on the
tile; the tile is for "go press the button".

Other behaviour worth knowing:

- **Drag it anywhere.** The position is remembered across restarts, and is
  clamped back on-screen if you change resolution or unplug a monitor.
- **Sized to your Dock**, read from `com.apple.dock tilesize` at launch, so it
  reads as a peer of your other icons rather than an oversized sticker.
- **Adapts to appearance** — black tile with a white outline in Dark, inverted
  in Light. It follows the system setting rather than sampling the desktop
  behind it, because reading those pixels would need Screen Recording
  permission for an icon colour.
- **Hides itself** when there is nothing waiting and you have no open PRs, and
  reappears on the next request.
- **A grey `!`** means the token broke. That state is deliberately distinct
  from a count of zero, so a broken setup never looks like an empty queue.

---

## Reviews tab

PRs waiting on your review. Each row shows the title, number, repository,
author with avatar, and how long ago you were asked — colour-coded by age.

### What counts as waiting on you

Both `review-requested:@me` and `team-review-requested:` for every team you
belong to, fetched in one GraphQL request and deduplicated. Team-assigned
reviews are invisible to the simpler query, which is why `read:org` is needed.

### How a PR leaves the drawer

```
latestPing = newest review request aimed at me (directly or via a team I'm in)
myActivity = newest review or comment I authored on that PR
show       = latestPing exists AND (no activity OR myActivity < latestPing)
```

Approve and Request-changes need no special handling: GitHub clears the review
request server-side, so those PRs simply stop coming back.

A **Comment**-type review does *not* clear it, which is the whole reason the
rule above exists — leave a comment and the PR still leaves your drawer,
because your attention has demonstrably been on it.

Anchoring to the *latest* ping is what makes re-requests work. A PR you already
reviewed resurfaces the moment someone asks you again, rather than staying
dismissed forever.

Polling runs every 60 seconds, so a review you submit clears within a minute.

### Sorting and filtering

Sort by oldest first (the default, so the most overdue is on top), newest
first, or author A–Z. Filter to a single author, with a count beside each name.

While filtered, the header reads `N of M` so the drawer count never silently
disagrees with the badge. An author filter is deliberately *not* persisted, and
clears itself if that author's PRs are all reviewed — either would otherwise
leave you staring at an empty drawer next to a non-zero badge.

---

## My PRs tab

Your own open PRs, each row carrying the signals that decide whether it needs
you.

### The lead gate

The headline signal: **has a reviewer whose approval actually unblocks this
signed off?**

| Chip | Meaning |
|---|---|
| `lead: Alice` *(green, filled)* | a lead has a live approval |
| `lead needed` *(amber)* | no lead has approved yet |

Configured per team, and **empty by default** — until you set your leads the
chip always reads `lead needed`. See
[README.md](README.md#your-review-leads).

**Only live approvals count.** GitHub reports dismissed approvals in the same
place as current ones, and a dismissed approval is not an approval — it is why
a PR can look approved on GitHub yet still be blocked from merging. Counting
them would make this chip claim a PR is unblocked when it isn't.

Dismissed approvals are still *shown*, greyed, as `N dismissed`. Hiding them
would be the other way to lie: you would see `lead needed` with no explanation
of the approval that used to be there.

### Checks

`12 passed`, `2 failing`, `4 running` — from GitHub's check rollup for the head
commit, tallying both `CheckRun` and `StatusContext` entries, which report
their verdict in different fields. Cancelled and timed-out count as failures;
neutral and stale count as skipped. Hover for the failing check names.

### Branch state

Says what the branch needs rather than doing it:

| Chip | When |
|---|---|
| *(nothing)* | level with its base |
| `needs rebase · N behind` | the compare shows N commits behind |
| `needs rebase` | GitHub reports `BEHIND` but the count is unavailable |
| `conflicts · needs rebase` | the branch conflicts with its base |
| `base state unknown` | the compare request failed |

That last row matters: a failed lookup reads as *unknown*, never as "up to
date". Claiming a branch is current when it was never checked is the one
genuinely misleading answer available here.

Rebasing *from* the widget was built and then deliberately removed. Doing it
safely meant locating a local clone, parsing `git worktree list`, five safety
guards and a force-push — a lot of destructive machinery to save a command the
terminal runs better. Naming the state turned out to be the useful half.

### Everything else on the row

- **Open threads** — unresolved review threads, or a grey count when all are
  resolved.
- **Merge blocker** — `ready`, `needs review`, `draft`.
- **Changes requested**, naming who.
- **Stack position** — `stacked on #100` on a child, and `restacks #101` on its
  parent, because rebasing a parent leaves its children needing their own
  restack.
- **Diff size and age** — lines changed, files touched, how long it has been
  open.

### Sorting and filtering

Sort by newest, oldest, recently updated, or needs-attention (worst health
first, ties broken by oldest — an old broken PR outranks a fresh one). Filter
to needs-lead, changes-requested, failing-checks, open-threads, or
ready-to-merge, with a count beside each.

---

## Filtering by repository

Both tabs share one repository filter, for anyone whose work spans more than
one repo. The menu lists every repo appearing in *either* tab, with counts for
both (`acme/widgets-web — 2 review, 1 mine`), so it is obvious what
picking one will show.

It is shared rather than per-tab because "I'm in this repo today" is one
intent, not two. It is also the one filter that persists across restarts —
which is safe because it is re-validated on every refresh and dropped if it
matches nothing, rather than leaving you with two empty drawers and no obvious
cause.

While any filter is hiding rows, the tab reads `shown/total` — `My PRs 1/2` —
so a tab never claims a count the list below it isn't showing.

The author menu is also scoped by it, so it never offers you someone the repo
filter has already excluded.

---

## The drawer

**Shows every row by default**, growing to fit the whole list. Nothing is
hidden until it has to be.

- The ceiling is the **height of your screen**. Past that the list scrolls.
- **Drag the top edge** to make it shorter — that is the useful direction now
  that the default is "fit everything". Your chosen height is remembered per
  tab.
- The edge **follows your pointer smoothly** while you drag, then **settles
  onto the nearest whole row** when you let go, so the drawer never ends
  halfway through an item. Snapping during the drag was tried first and felt
  like lurching; quantising every frame stops it tracking your hand.
- The handle is **always available**, since there is always something to
  adjust. The pointer becomes **up/down arrows** over it, and a **closed fist**
  while you drag, so hovering and grabbing never look the same.

Each tab sizes to its own list, and switching between them **animates** the
difference rather than jumping.

Both tabs share one width, so switching tabs never resizes the drawer sideways.
Heights are remembered separately, since My PR rows are much taller.

**Click a row** to open that PR in your browser — the title underlines on
hover so it reads as the link it is. **Click outside** to collapse. **Drag the
header** to move the whole thing.

---

## Colour

One scale, used everywhere — checks, merge blockers, approvals, staleness — so
the signals cannot drift apart as features are added:

| | Meaning |
|---|---|
| **green** | passing, approved, ready to merge |
| **blue** | in progress, or simply waiting |
| **amber** | needs something from a human |
| **red** | failing, rejected, conflicted |
| **grey** | skipped, draft, dismissed |

Each row's left accent shows its **worst** signal, so one glance down the list
ranks what is wrong.

---

## Notifications

A native notification when a PR you have not seen appears; clicking it opens
the PR. Re-requests notify again, because the remembered key includes the
request timestamp.

On first launch the seen-list is seeded silently rather than firing a burst of
notifications for a backlog you already know about.

---

## Update notifications

When a new version is released, running copies find out two ways:

- **GitHub emails collaborators.** Anyone with access who sets
  *Watch → Custom → Releases* on the repo gets an email per release. No code
  involved; it works today.
- **The app checks itself.** It reads the repo's latest release, compares the
  tag against its own `CFBundleShortVersionString`, and shows an
  `update 1.1.0` chip in the drawer header plus a one-time notification.
  Clicking either opens the release page.

The check runs at launch, every six hours, and whenever you press **Refresh** —
so there is a way to ask on demand instead of waiting out the timer. It
deliberately does *not* ride the 60-second PR poll; releases do not appear that
often. A given version announces itself once, not every six hours.

A failed check leaves the status alone rather than reporting "up to date",
for the same reason a failed branch compare reads as unknown: claiming
you're current when nothing was checked is the one actively misleading answer.

Forks can point the check at their own releases:

```sh
defaults write com.yourname.prradar update.repo -string "you/your-fork"
```

---

## Deliberate non-features

Things left out on purpose, and why:

- **No rebasing from the widget.** A force-push behind a one-click button in a
  floating panel is a lot of risk for a command that belongs in a terminal.
- **No merging from the widget.** Same reasoning. The green badge tells you
  when to go do it.
- **The badge never counts your own PRs.** Mixing "work you owe others" with
  "your work in flight" into one number makes it mean nothing.
- **No wallpaper sampling for the icon colour.** It would need Screen Recording
  permission, which is far too much to ask for an icon that adapts perfectly
  well to the system appearance.
