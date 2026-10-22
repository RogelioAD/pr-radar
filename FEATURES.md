# PR Radar

A floating macOS badge that answers two questions without opening a browser:
**who is waiting on me**, and **how is my own work doing**.

It sits above every window, sized to match your Dock icons, and expands into a
drawer when clicked. Setup lives in [README.md](README.md).

---

## The badge

With a mascot chosen — which is the default — the badge **is** the character:
a 48×48 pixel-art sprite with a counter chip beneath it for each count that
isn't zero. See [Mascots](#mascots) below. Turn the mascot off and you get the
original badge, described here, unchanged.

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
otherwise flicker every time you poked at a menu. A
[snoozed](#snoozing) row does leave the red count, which is the one exception
and is argued where it is made: the badge answers *what is waiting on me*, and
a pull request parked until Monday is not. The red count is
tinted by how stale the *oldest* request is: blue under a day, amber at 1–3
days, red beyond 3 — so a queue that has gone unattended looks different from a
fresh one at a glance.

The green badge is deliberately about **merging, not breakage**. Failing checks
and conflicts colour the row inside the drawer, but they do not appear on the
tile; the tile is for "go press the button".

Other behaviour worth knowing:

- **Drag it anywhere.** The position is remembered across restarts, and is
  clamped back on-screen if you change resolution or unplug a monitor — the
  moment the displays change, and again on the next launch, so a badge parked
  on a monitor you have since closed the lid on comes back rather than being
  restored to a screen that is not there.
- **Sized to your Dock**, read from `com.apple.dock tilesize` at launch, so it
  reads as a peer of your other icons rather than an oversized sticker. That is
  the starting point, not a fixture — see below.
- **Drag a corner to resize it.** The pointer turns into a diagonal resize pair
  over any of the four corners, and a closed fist while you drag, so hovering
  and grabbing never look the same — the same rule the drawer's edge follows.
  The corners are the *character's*, not the window's — see below. The middle
  third stays move-and-click whatever the size, and a corner press that never
  travels still opens the drawer.
- **Adapts to appearance** — black tile with a white outline in Dark, inverted
  in Light. It follows the system setting rather than sampling the desktop
  behind it, because reading those pixels would need Screen Recording
  permission for an icon colour.
- **Hides itself** when there is nothing waiting and you have no open PRs, and
  reappears on the next request.
- **A grey `!`** means the token broke. That state is deliberately distinct
  from a count of zero, so a broken setup never looks like an empty queue.

### On resizing

It scales as a **square**, from one number. Tile, glyph, counter chips and the
character's sprite scale all derive from it, so there is nothing to get out of
proportion and no aspect ratio to distort the pixel art. Free width and height
were considered and dropped for exactly that reason.

The range is **28 to 128 points** — the smallest and largest real Dock tile
sizes. Below the floor the counter's 3×5 digits stop being a number; above the
ceiling it stops reading as a Dock peer and starts reading as a window. Your
size is remembered across restarts, like the position.

**The badge rests exactly where you let go.** Nothing snaps.

That is a deliberate reversal. A sprite is only crisp when one source pixel
covers a whole number of *device* pixels, and everywhere else in the app —
the header, the room, the banner — still obeys that. The badge used to as
well, and it made the drag unusable: the sizes a character can be drawn
crisply at are its cell height over the backing scale apart, which is **54
points on a 1× display**, leaving exactly **two** reachable sizes inside
bounds of 28 and 128. You pulled a corner, nothing happened, and then the
badge jumped the whole way — and letting go could move it half a badge again
from where the pointer was.

So the badge is the one surface that comes off the pixel grid, because it is
the one surface you *aim* at a size. A drag that answers a different question
from the one your hand asked is the worse bargain.

Every cell is drawn from one **device-pixel boundary to the next** rather
than as `scale` wide from wherever it lands. At a whole scale those are the
same rectangle; at a fractional one they are not, and the difference is the
whole thing. A rect with fractional edges is antialiased, and two neighbours
sharing a boundary each cover part of the same device pixel — compositing two
half-covers gives three quarters, not one. Over 48 cells that is a grid of
translucent seams, and the badge reads as *see-through* rather than as soft.
Snapping the edges makes adjacent cells share one exactly, so nothing is
antialiased and nothing is partly transparent. The price is that cells differ
by a device pixel here and there, which is what nearest-neighbour has always
looked like.

**Settings ▸ Appearance has a slider** for the same number. Dragging a corner
is the direct way and stays the discoverable one; the slider is what you reach
for when the badge is behind a window, or when you want a size rather than a
gesture. It goes through the same path the grips do, so the badge re-frames as
it moves rather than waiting for something else to ask for a layout.

The only limit left is the **counter's digits**: below about 10 points a 3×5
digit stops being a number, so the badge stops shrinking there whatever the
pointer does. That is a legibility floor, not a pixel-grid one. The plain
tile has no art to keep crisp and never had either constraint.

The grips sit on the **character, not the panel behind it**. The window is
deliberately larger than the art it carries: a widget reserves the mood-mark
gutter whether or not a mark is showing, and keeps bob room under the
character's feet, so with no counts up the art fills barely two thirds of the
height. How much of its 48x48 cell each character fills differs too — Gourd
fills his row edge to edge where Rattle leaves four columns clear each side. Anchored to the
window, the resize cursor appeared in a different place for every character and
came up over empty desktop; anchored to the art, it is always on the edge you
can see. The halo and drop shadow count as art, since they are drawn.

The plain tile uses its **square body** rather than the count badges overhanging
its corners, so the grips hold still when a count appears or goes away — and
those badges sit centred on the very corners the grips already cover.

**Reset badge size** appears in the right-click menu once you are off the
default, because a badge dragged down to its floor on a busy desktop is fiddly
to grab again.

---

## Reviews tab

PRs waiting on your review. Each row shows the title, number, repository,
author with avatar, and how long ago you were asked — colour-coded by age,
over a band saying what the review will cost you.

### What a review will cost

The row used to answer *who asked and how long ago* and nothing else. A
forty-line change and a fourteen-hundred-line one were the same row, a pull
request whose CI had already failed looked exactly like one worth starting, and
a ping aimed at you alone was indistinguishable from a team ping that went to
six people. Four chips answer those:

| Chip | What it says |
|---|---|
| `+120 −40 · 6f` | how much there is to read, tinted past 250 lines and again past 1,000 |
| `checks green` · `checks failing` · `checks running` | GitHub's rollup verdict for the head commit |
| `only you` · `3 others` | reviewers still being waited on who are not you and not a team of yours |
| `2 approved` | live approvals already in — yours may not be the one holding it up |

All of it rides the fragment the list was already fetching, so it is the same
single round trip it has always been. The rollup's **verdict and nothing under
it**: triage asks one word, and the per-check breakdown is the My PRs tab's job
at a hundred context nodes per pull request — which here would be a hundred
times thirty times one alias per team.

Three rules keep it honest:

- **The sizes arrive together or not at all, and missing is not zero.** A row
  nobody measured wears no chips at all rather than claiming `+0 −0 · 0f`,
  which is the same class of answer as a failed branch compare rendered as "up
  to date". A row redrawn from a year-old auto-review record is exactly that
  case.
- **No rollup is not a passing rollup.** A repository with no CI and one whose
  CI has not started are both honestly *nothing to say*, and neither is green.
- **Approvals are live ones, and never yours.** A dismissed approval is not an
  approval, by the same rule the lead chip follows, and a row telling you
  somebody has approved this when the somebody is you is the list answering
  itself.

### What the author said

A title and a diff size tell you how big a review is. The **description** is
where people write the things that decide whether to start it at all — *"don't
review yet"*, *"part 2 of 3"*, *"only the last commit is new"* — and the row
could not say any of it.

So one line of it sits under the title, dimmed and clipped, with the rest on
the tooltip. One line rather than three: it is context for the title rather
than a second title, and a row that grew three lines of somebody's template
would cost more than it told you.

**Not the literal first line.** Real descriptions open with a template
heading, an HTML comment nobody deleted, or a rule, and a row reading
`## Summary` is worse than a row reading nothing because it looks like the
feature working. Headings are skipped in both markdown forms — the `##` kind
and the kind underlined with `---` on the next line — along with comments,
rules, and the empty checkboxes a template leaves behind.

It reads the **raw markdown** rather than GitHub's plain-text rendering, which
was the first thing tried and is wrong for exactly the reason it looked right:
`bodyText` is smaller on the wire and strips the markup, so a real pull request
came back with its first line as the bare word `What` and the row printed it.
The markup is what tells a heading from a sentence.

A line wrapped wholly in bold is unwrapped, since that is a heading in
disguise — but emphasis *inside* a sentence is left exactly as written.
Stripping it is how `a **hard** no` becomes a different sentence in a flatter
voice.

### What changed since you last reviewed it

A re-requested pull request is the most wasteful row in the queue: you have
already read it, and the list hands it back with nothing to say whether twelve
lines moved or the whole thing was rewritten.

So a row you have reviewed before carries **`14 commits since your review`**,
and pressing it opens GitHub's two-commit view — the diff between the commit
you reviewed and the head — rather than the whole thing again. Every row this
appears on is a re-review by construction: the rule below only keeps a pull
request whose newest ping is newer than anything you did to it.

It is a link only when **both ends of the range are known**. GitHub's range
form silently falls back to the entire diff when an end is missing, which would
hand back the nine hundred lines this exists to avoid while looking like it had
worked. A review whose commit was force-pushed out of the branch comes back
with none, so that row says its piece and does not link.

Three cases that had to be decided:

- **Nothing new is said out loud.** `nothing new since your review` — a
  re-request with no push behind it happens, and knowing the diff is the one
  you already read is the most useful sentence available.
- **A head that moved with no newer commits still counts.** A force-push can
  rewrite committer dates so nothing looks newer than the review while the head
  is plainly a different commit. The two commit ids settle it when the dates
  cannot.
- **A full page is a floor.** Twenty commits read and more behind them says
  `20+`, never `20`.

The automatic review's pin is ignored here as it is in the rule below, for a
different reason. There it stops PR Radar's own review counting as *you* having
dealt with the pull request; here it stops a review you did not read the code
for from anchoring a diff labelled *since your review*. It went out under your
name, but the sentence would not be true.

### That you started it

Snoozing gave the list a way to say *not now*. There was never one for *I am on
it*: you open a pull request, read four hundred lines, get pulled into
something else, and the row you come back to is identical to one you have never
touched.

So opening a row records that it happened, and the row says **`opened 3d ago`**
until it is dealt with. It is deliberately the weakest claim the app can make —
that you opened the thing, never that you read it or got anywhere — because
that is the only part it actually witnessed.

- **The earliest open is the one kept.** Opening it a fourth time is not a
  fresh start; the interesting number is how long this has been going on, and
  keeping the latest would reset the clock exactly when it has most to say.
- **A day, not three.** The two clocks either side of this one use the
  staleness ladder, which turns amber after a day and red after three. This
  measures a thing you started and did not finish, where an afternoon is
  ordinary and a day is already worth a word.
- **There is no expiry**, where the snooze has one. A snooze is a promise about
  a time and goes stale on its own; this stays true until the pull request is
  dealt with — and being dealt with is exactly what takes it out of the fetch.
- **`Not mine` clears it.** The record can be wrong in one direction: you
  opened it, decided it was not yours, and said so somewhere this app cannot
  see. Nothing else would clear it short of reviewing a pull request you are
  not going to review.

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
first, author A–Z, or **smallest first**, which is how a queue of six actually
gets cleared.

Smallest-first is the one ordering with an unknown in it. A row whose signals
never arrived has no size, and sorting it as zero would float it to the very
top claiming to be the quickest thing in the list — so unknowns go last, among
themselves oldest first, which is where the default would have had them anyway.

Filter to a single author, with a count beside each name. Beside it sits a
**triage filter** — *CI not failing*, *nobody has approved* — which is a second
axis rather than another entry in the author menu, in the same sense the
pancake button is a second axis on My PRs: *small ones nobody has looked at* is
one question, and it takes two controls to ask it.

That filter is **symbol only and conditional**, and both halves are forced. The
bar genuinely runs out of room — with a long repository name picked its pills
measure 405 of an available 440, and a `Menu` label carrying `.fixedSize()` is
clipped past the edge rather than shortened — so the words live in the tooltip,
exactly as the sort control's do. And it appears only when one of its options
could actually hide something, which is the rule the pancake button follows: a
filter that can only ever return everything is worse than no filter.

A row whose signals never arrived **matches every filter**. Hiding it would be
failing it for a test it was never given, and this list's whole job is to be
the complete account of what is waiting on you.

While filtered, the tab reads `N/M` so the drawer count never silently
disagrees with the badge. An author filter is deliberately *not* persisted, and
clears itself if that author's PRs are all reviewed — either would otherwise
leave you staring at an empty drawer next to a non-zero badge. The triage
filter *is* persisted, because the two are not the same kind of narrowing: an
author filter names a person who may have nothing outstanding tomorrow, where
"don't show me pull requests whose CI is already red" is a standing preference
about the work.

---

## Snoozing

A pull request leaves the Reviews list when you comment on it or review it.
That rule is what makes the list honest, and it also leaves no way to say *not
until Thursday* except by writing a comment you do not mean — lying to the one
list that does not lie to you.

Right-click a row and put it down: **for an hour**, **until tomorrow morning**,
or **until Monday morning**. It comes back on its own.

A snooze is keyed on the **ping key**, which carries the timestamp of the
request it answers — so a re-request is a new key, and a row you put down last
week comes straight back the moment somebody asks you again. That is the
automatic review's pin making the same choice for the same reason: a key with a
request in it cannot outlive the request.

**A sleeping row leaves the badge as well as the list**, which is the part
worth arguing. The badge answers *what is waiting on me*, and a pull request
deliberately parked until Monday is not waiting on you now — going on nagging
about it is the thing the snooze was pressed to stop.

What the count must never be is *silently* short. So the tab strip carries
**`2 snoozed`** whenever anything is, next to the ready-to-merge count and for
the same two reasons: it is a fact about one tab rather than about the app, and
that band has the room the filter bar does not. Pressing it shows exactly what
has gone quiet, each row saying when it wakes and offering to wake now.

Some details that had to be decided:

- **The sleeping list is shown whole.** The triage and author filters narrow
  the work you are choosing between, and a row you have already chosen to put
  down is not in that choice. Hiding some of what you parked behind a filter
  set for another purpose is how a row gets lost.
- **"Until Monday" pressed on a Monday means next week.** The label says Monday
  because the week is what you are putting it down until, and a nine o'clock
  forty minutes away is not what anybody meant by it.
- **Everything asleep is not inbox zero.** The drawer says `All snoozed` rather
  than congratulating you for work you deferred an hour ago.
- **Showing the sleeping list is not persisted**, where the filter beside it is.
  It is a way of looking at the list rather than a preference about the work,
  and leaving it on across a restart would open the drawer onto rows that are
  all asleep beside a badge reading zero.
- **Pruning drops two kinds of rubbish for two reasons.** A wake time in the
  past has done its job; a key the fetch no longer returns belongs to a pull
  request that has been reviewed, merged or closed. The second half runs only
  on a round that reached every account — pruning against a partial list would
  quietly wake every row belonging to the account that was unreachable.

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

**And how much of it is actually in the way.** `2 failing` counted a required
build and somebody's optional lint job identically, so a pull request could
wear the worst chip on the tab over two failures nothing gates on. The chip now
reads `3 failing · 1 blocking`, or `2 failing · none blocking` where nothing
failing is required — and plain **`2 blocking`** when every failure is a
required one, which is the common case and the one where naming both numbers
prints the same number twice.

`isRequired` takes the pull request as an argument, and a GraphQL argument
cannot refer to a sibling field — so inside a search that has not yet told us
the number, there is nowhere to write it. One alias per pull request with the
number interpolated is the only shape that can ask, which makes this a second
phase like the branch compare. It is sent **only for the rows that actually
have a failing check**: most pull requests are green, and re-fetching a hundred
context nodes per row per minute to learn that nothing is failing is the cost
the conflict counter already refuses to pay. On the common round no request
goes out at all.

Three states, not two:

| State | What the chip says |
|---|---|
| **not known** — the phase has not answered, or failed | `2 failing`, exactly as before |
| **verified none** | `2 failing · none blocking` |
| **named** | `3 failing · 1 blocking` — or `2 blocking` when that is all of them — and the tooltip names it |

Not knowing is where every row starts and where it stays if the phase fails,
and then the failure is treated as the worst it could be — the honest reading
of a question not yet asked. A *verified* empty is a different sentence and is
earned, the same way `conflicts · 0 files` is not a thing the row is allowed to
say.

A failure nothing requires drops the row from bad to attention. Whether the
chip is *filled* is decided elsewhere — see [the three bands](#the-three-bands)
below, where only one chip on a row is allowed to be.

### Branch state

Says what the branch needs rather than doing it:

| Chip | When |
|---|---|
| *(nothing)* | level with its base |
| `needs rebase · N behind` | the compare shows N commits behind |
| `needs rebase` | GitHub reports `BEHIND` but the count is unavailable |
| `conflicts · N files` | the branch conflicts, and `merge-tree` counted them |
| `conflicts` | it conflicts, but nothing could count the files |
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
  resolved. Opening one reads like a findings list on the Reviews tab, because
  a review thread and a finding are the same kind of thing: what was said,
  then `file:line`, then — if you click it — the code. The two share one
  control (`CodeToggle`) rather than agreeing twice. They did not, and the
  difference was never a decision: a thread showed its diff hunk permanently,
  so three threads was three hunks of code before a word of the conversation.
- **Merge blocker** — `ready`, `needs review`, `draft`.
- **Changes requested**, naming who.
- **Stack position** — `stacked on #100` on a child, and `restacks #101` on its
  parent, because rebasing a parent leaves its children needing their own
  restack. The first is dropped inside a stack group, where the PR it names is
  the row directly below it.
- **Diff size and age** — lines changed, files touched, how long it has been
  open.
- **How long it has been waiting on them** — `waiting 4d · alice`, or
  `waiting 4d · 3 reviewers` where several are outstanding, naming whoever has
  had it longest. See below.

Chips **wrap onto a second line** rather than running off the edge. A row can
carry five of them on a bad day, and the alternatives are both worse: squeezing
them truncates the words that make them worth reading, and letting the line
overflow pushed whatever sat to its right — the stack marker — out past the
row's edge, where it was clipped away entirely.

### Who is sitting on your work

The waiting clock above is per row, which is the right place for it and the
wrong place to notice the thing that matters: **four of your six pull requests
waiting on the same reviewer is one conversation, not four.** A list of rows
never says so — you read it four times and go on waiting.

So above the list, when somebody holds more than one: **`alice has 4 of yours ·
oldest 6d`**. Nothing is fetched for it; it is a group-by over the outstanding
reviewers the tab already has.

- **More than one is the whole point.** A reviewer holding exactly one of yours
  is already completely described by that row's own chip, and repeating it
  above the list would be the drawer saying the same thing twice in two sizes.
- **Sorted by how long, not how many.** Two pull requests sat with somebody for
  a week is a worse state of affairs than four they were handed this morning. A
  reviewer whose ask times are unknown sorts last, because not knowing is not a
  small number.
- **It counts that reviewer's own oldest ask**, not the row's headline. The row
  reports whoever has had it longest, and that is somebody else's clock.
- **It is scoped like the rows under it.** A roll-up over work the repository
  filter is hiding would be a line about pull requests that are not on screen.

### The three bands

A row's chips are drawn in three groups, with a wider gap between groups than
between the lines inside one:

| Band | What is in it |
|---|---|
| who has signed off | `lead needed` or `lead: Alice`, other approvals, `N dismissed` |
| what is blocking it | checks, the branch, and whatever the merge blocker adds |
| everything else | threads, how long it has been waiting on its reviewers |

Two of those bands existed already and the third was a catch-all that had grown
to carry the checks, the threads, the branch *and* the waiting clock — four
kinds of thing in one flow, wrapping wherever the width ran out, so the break
never meant anything. This is the argument the automatic review's strip already
makes about its own two bands: giving the decisions their own flow puts the
break where the meaning already is.

The gap between bands is deliberately more than twice the gap between wrapped
lines. With the two equal, a band boundary read as another wrap and the
grouping that was already there said nothing.

The dismissed count stays with the lead chip rather than moving to the third
band, because it exists to explain the `lead needed` beside it. Across a band
boundary it would be an orphaned number.

**Only one chip on a row is filled.** `2 blocking` and `conflicts` were both
solid red at once and the eye had nowhere to land, so among the chips carrying
the row's worst health exactly one is filled and the rest say the same thing
outlined. Red is still red either way; filling it is the row saying *this* is
the thing to look at. A good verdict is unaffected — a filled green
`lead: Alice` is the row being done rather than the row shouting, and two of
those never happen at once.

### Answering a thread

The whole conversation has been on screen since the row learned to open its
threads, and saying one word back meant a browser tab. That is an odd place to
stop: a reply is a far smaller thing than the Approve button this app already
has, and unlike an approval the person who wrote it can edit it afterwards.

So every unresolved thread has a reply box under it, and two buttons:
**Reply**, and a second one that follows what you have typed — **Reply &
Resolve** with a sentence in the field, **Resolve** with it empty. One button
rather than three controls sharing a 380-point row with a text field, and
resolving with nothing typed is a real case on its own: you fixed it and the
diff says so.

**The order is the whole of it: never resolve a thread whose reply did not
land.** A thread closed over a comment that is not there reads to every
reviewer as handled, and nobody looks at a resolved thread again. So the reply
goes first and a failure stops before the resolve, with the thread left open
and the sentence still in the field.

The other direction is tolerated, because it is safe: a reply that posted and
a resolve that did not leaves an open thread with your answer in it, which is
exactly where you were before pressing anything. The row says so and stops.

- **The field keeps what you typed when a send fails.** Losing a sentence to a
  dropped connection is the one outcome that would stop anybody using this
  twice.
- **The buttons go dead while a reply is in flight.** A second press on one
  already sending is how a sentence becomes two comments.
- **A resolved thread leaves the list at once**, and the count above it moves
  with it. The poll is sixty seconds and the mutation is instant; without that
  the thread sits there looking untouched for a minute, which is how somebody
  presses the button twice. It is forgotten once the fetch agrees — and a
  thread that somehow comes back still open stays hidden, because the press
  did happen and un-hiding it would look like the resolve coming undone.

### Asking somebody to look again

A reviewer asked for changes, you fixed it, and nothing you do to the branch
tells them so. The row offers **Ask Alice again**, which is GitHub's own
re-request: they are notified, and nothing on the branch changes.

It is offered **only** for reviewers who have already submitted a review. That
is narrower than it sounds like it should be, and the reason is worth stating:
somebody who simply has not looked yet is already in the request list, and
re-adding them does nothing at all. The only thing that would notify them is
removing and re-adding, which means a window where a failed second call has
quietly dropped a reviewer off your pull request — not a trade worth making for
a reminder. So the row says nothing rather than offering a button that looks
like it worked.

Bots are excluded by having no account id to name. There is nobody to ask.

### Waiting on them

The app could say to the hour what you owe other people and nothing at all
about the other direction. This row has carried its outstanding reviewers since
the tab was built and never drew them, so a pull request you asked three people
to look at four days ago looked exactly like one you opened this morning.

`ReviewRequest` carries no timestamp of its own — the live set says *who* is
outstanding and never *since when* — so the timeline is the only place the
other half of the clock is recorded.

Per reviewer it is the **last** ask that counts: being re-requested restarts
that person's clock, exactly as a re-request restarts yours on the Reviews tab.
Across reviewers it is the **oldest** of those the row reports, because the
question is how long this has been waiting on somebody and the answer is the
longest anybody has had it. A reviewer who has already reviewed is out of the
live set, so their ask stops ageing it.

It uses the Reviews tab's own staleness ladder — under a day, one to three,
beyond three — rather than a second one, so the two tabs cannot come to mean
different things by the same colour.

An ask older than the page the timeline reads leaves no timestamp. Then the
chip names who it is waiting on and **does not claim a duration**, and stays
grey: a duration that was never read must not be painted as fresh, which is the
answer `base state unknown` exists to avoid.

It sits last in the row's chips, after everything the branch needs doing to it,
because it is the one chip there about a person rather than about the pull
request.

### Stacks

Press the **pancake button** in the tab strip and the list narrows to PRs that
sit on each other, drawn as groups: outlined together, one outline per stack.

Everywhere else the list is a **flat list of rows, exactly as it always was**. A
plate and a column of pancakes is a lot of furniture to impose on someone who
asked to see their failing checks, so the whole treatment — groups, plates,
pancakes — belongs to that one button and appears nowhere else. The `stacked on
#100` chip is the normal list's way of saying it, and it comes back the moment
the button is off.

The button is a **second axis**, not another entry in the filter menu, so it
combines with whatever that menu is set to: *failing checks, and only in a
stack* is one question you can ask.

It **only appears when something in scope is stacked** — a filter that could
only ever return nothing is worse than no filter. Scoped by repository, since
that is a scope rather than a view; not by the filter menu, or the bar's
controls would come and go every time you changed the other one. Once it is on
it stays on screen whatever happens to your PRs, so the control that switched
it on is always there to switch it off.

Inside a group it is base last: the PR everything else sits on is at the bottom,
and each row wears a **stack of pancakes one taller than the row below it** — so
the base has one, the PR on top of it two, and so on. The group reads bottom-up,
which is the order it has to be merged in.

**Syrup is a garnish, not a layer.** It is its own narrow disc poured over the
top and it never counts, so a stack of one is one whole pancake with syrup on
it. Counting it would leave the base of every stack drawn as the one member that
is not a pancake. It also gives the marker a shoulder — without it, uniform
bands draw a rectangle of stripes and stop reading as a stack of anything.

Some details that had to be decided:

- **Stacks are what is on screen.** Links are resolved only among the PRs
  currently listed, so a repo or state filter that hides a chain's middle leaves
  two ordinary PRs rather than a group claiming a relationship it is not
  showing.
- **A group takes the place of its strongest member**, whatever the sort. A
  stack carrying one conflicted PR surfaces under needs-attention even when
  everything else in it is clean. Inside the group, order never changes — that
  order is a fact about the branches, not a preference.
- **A stack is a tree, not always a line.** Two PRs can sit on the same parent;
  both stay in one group, each branch's run kept together.
- **The group is identified by its base**, not its top, because PRs are pushed
  onto a stack far more often than slid underneath it. A group whose identity
  changed on every push would lose its measured height and resize the drawer
  each time.
- **Six pancakes is the cap.** Past that the marker would be taller than the row
  carrying it; the real depth is in the tooltip.
- **The marker's space is kept, not competed for.** The text column is given a
  width that already excludes it, so a crowded row wraps its chips instead of
  crowding out the pancakes — which used to make a deep stack's marker the most
  likely one to vanish.
- **The drawer still resizes by whole rows**, and a card's rows count. Treating
  a card as one indivisible row would leave a filtered list with a single legal
  height and a top edge that could not be dragged at all.

### Sorting and filtering

Sort by newest, oldest, recently updated, or needs-attention (worst health
first, ties broken by oldest — an old broken PR outranks a fresh one). Filter
to needs-lead, changes-requested, failing-checks, open-threads, or
ready-to-merge, with a count beside each — plus the pancake toggle above, which
is a second axis rather than another entry in that menu.

---

## Filtering by repository

Both tabs share one repository filter, for anyone whose work spans more than
one repo. The menu lists every repo appearing in *either* tab, with counts for
both (`acme/widgets-web — 2 review, 1 mine`), so it is obvious what
picking one will show.

**Pick as many as you like.** "I'm in this repo today" was the intent it was
built for, and plenty of days that is three of them — with one selection the
only way to see three was to see all twelve. Each entry toggles its own
repository, so picking a second widens the scope rather than replacing it. The
pill names one and counts several: `widgets-web`, then `3 repos`. Naming two
would not fit, and naming the first with a `+2` after it reads as though the
first one were the important one.

Nothing ticked is the same state as **All repos**. A scope that could be
narrowed to nothing would be an empty drawer with no filter visibly set.

It is validated name by name rather than all at once: with three repositories
picked and one of them finished, the other two are still exactly what you asked
for, and clearing the whole scope because part of it went stale would throw
away a choice that is still good. The stored value reads back as either a list
or the single string it used to be, so an upgrade does not silently widen the
scope on first launch.

It is shared rather than per-tab because "I'm in this repo today" is one
intent, not two. It also persists across restarts — which is safe because it is
re-validated on every refresh, rather than leaving you with two empty drawers
and no obvious cause.

While any filter is hiding rows, the tab reads `shown/total` — `My PRs 1/2` —
so a tab never claims a count the list below it isn't showing.

The author menu is also scoped by it, so it never offers you someone the repo
filter has already excluded.

---

## The keyboard

For a long time there was none. Every way into this app went through the
pointer — find a 48-pixel badge that may be behind a window, click it, click a
row — and the parts of this document that talk about reaching things talk about
cursor shapes and hit targets and nothing else.

**⌥⇧R opens the drawer from anywhere**, and closes it again. A shortcut that
only opened would leave you reaching for the mouse to put it away, which is the
thing it was pressed to avoid.

It is registered through Carbon's `RegisterEventHotKey`, which is the part of
Carbon macOS has never replaced and never removed. The modern-looking
alternative — a global `NSEvent` key monitor — needs **Accessibility**
permission, because it is a keylogger with a narrow filter and the system
rightly treats it as one. This app already refuses Screen Recording for the
sake of an icon colour; asking to watch every keystroke on the machine so a
panel can open would be a far worse bargain. `RegisterEventHotKey` asks the
window server for one chord and gets no prompt, because it is asking for
almost nothing.

A chord another app already holds fails at registration rather than silently
never firing, so the log says so. Pick a different one without a rebuild:

```sh
defaults write com.yourname.prradar hotkey.chord -string "cmd+ctrl+p"
```

A bare letter is refused: registered system-wide it would swallow that key in
every app on the machine.

### Once it is open

| Key | What it does |
|---|---|
| `↑` `↓`, or `k` `j` | move between rows |
| `Return` | open the selected pull request |
| `S` | snooze the selected review request for an hour |
| `Esc` | close the drawer |
| `⌘1` `⌘2` | Reviews, My PRs |
| `⌘R` | refresh |

The selection is a ring rather than a fill, so it sits over the hover
highlight instead of fighting it — the pointer and the keyboard can be on two
different rows at once and both have to stay legible.

Some details that had to be decided:

- **It is held as a row id, not an index.** A pull request arriving above the
  selected row on the sixty-second poll would otherwise slide the selection
  onto its neighbour, and `Return` would open something you were not looking
  at.
- **It stops at the ends rather than wrapping.** A list you are stepping
  through to clear is one you want to reach the bottom of and know it.
- **`S` is always an hour**, where the menu offers three lengths. A single
  keystroke should not be able to put something down until Monday without
  saying so; the longer ones keep their names on them.
- **A modifier held over a letter is not ours.** Only the tab switches and
  refresh are chords, so the drawer cannot eat `⌘Q`.
- **A text field owns every key it can use.** The "other" box on an
  auto-review row is a real field, and typing a sentence into it must not step
  the selection.
- **The selection does not survive the drawer closing.** Where the keyboard
  was looking is not a preference and not a fact about the work.

---

## The drawer

### Why the filters are still their own band

Folding them into the tab strip was tried and reverted. The two bands look half
empty and they are — but only when nothing is selected. With a real repository
picked, the filter pills come to 406pt on their own, and the merged band
overflowed 440 by **334**. What looked like wasted space was the *empty* state
of a bar that fills right up.

Measuring it turned up an older problem: the filter bar was already overflowing
by 24pt on its own, once a long repository name and the stack toggle were both
showing. These pills are `Menu` labels carrying `.fixedSize()`, so they refuse
to compress — past the edge they are clipped, not shortened. So every label is
capped, and the sort control lost its word: an up arrow, a down arrow and
`textformat.abc` are the three answers, and spelling them out again cost 70pt
in a band that had none. The order it is sorted by is in the tooltip.

The tab strip's right side does get used — by the one thing that belongs to a
tab rather than to the app.

### Every room in the footer

The gear, the trophy and the wand sit together, bottom-left. Two of them were
in the header and one down here, which meant *where do I find a room?* had two
answers. Each position was defensible alone — the gear is bottom-left because
that is where this platform has trained people to look — but the reasoning did
not survive a third room being added somewhere else.

The footer won the tie because the gear was already there, so the habit that
exists is the one kept; and because the header is the window's **drag handle**,
where every control competes with the gesture that moves the panel. The header
now holds the mascot, the name and the close box, and hands back the rest.

**Shows every row by default**, growing to fit the whole list. Nothing is
hidden until it has to be.

- The ceiling is the **height of your screen**. Past that the list scrolls.
- **Drag the grab handle** — the capsule in the middle of the top edge — to
  make it shorter, which is the useful direction now that the default is "fit
  everything". Your chosen height is remembered per tab.
- **The rest of that edge moves the window**, like the header below it. The
  whole edge used to resize, which is the one place a hand goes to move a
  window: the drawer could only be moved from the bare material beside the
  title, and read as a window that could not be moved at all. The handle keeps
  its own columns — 72pt of them, twice the capsule you can see, because a
  36pt target is missed.
- The edge **follows your pointer smoothly** while you drag, then **settles
  onto the nearest whole row** when you let go, so the drawer never ends
  halfway through an item. Snapping during the drag was tried first and felt
  like lurching; quantising every frame stops it tracking your hand.
- **A row taller than the screen gets the screen.** Landing on row edges means
  giving up a few points at the bottom, which is the trade that buys it — but
  one row can be much taller than the rest, and a pull request with six
  comments open is exactly that. With rows of 50, 600 and 50 under a 400-point
  ceiling, every row boundary past the first is out of reach, and the drawer
  used to collapse back to a single 62-point row however far you dragged it.
  So when a row is too tall to ever be shown whole, the screen's own cap
  becomes a stop alongside the row edges: the drawer opens the whole way and
  that row scrolls. Lists of ordinary rows are untouched and still give up the
  odd few points to land on an edge.
- **Open comments are stops of their own.** A row with its threads open is one
  row to the layout and several to the eye — the same thing a stack card is,
  and flattened the same way, one entry per comment. Without it the drag had
  nothing to land on between "closed" and "all six".
- The handle is **always available**, since there is always something to
  adjust. The pointer becomes **up/down arrows** over it and a plain arrow
  either side of it, so the two halves of the edge never look the same, and a
  **closed fist** while you drag, so hovering and grabbing do not either.

Each tab sizes to its own list, and switching between them **animates** the
difference rather than jumping.

Both tabs share one width, so switching tabs never resizes the drawer sideways.
Heights are remembered separately, since My PR rows are much taller.

**Click a row** to open that PR in your browser — the title underlines on
hover so it reads as the link it is. **Click outside** to collapse. **Drag the
header or the top edge** to move the whole thing — everywhere in that band
except the grab handle, the mascot and the × , each of which owns its own
press.

---

## Mascots

A small pixel-art character that keeps you company in the drawer and, by
default, replaces the floating icon entirely. **Twelve of them**, on three
shelves, and none of them go away.

**OG Mascots** — the first cast, drawn at 16 cells and retired when the
48-cell redraw landed. Back, upscaled by the app's own `scaled3x` rather than
redrawn, because redrawing them would make them different characters.

| | |
|---|---|
| **Pip** | the first one there ever was; the antenna is the tell |
| **Byte** | the animal. Dark eyes, so the ears do the talking |
| **Widget** | a screen on a collar — mouth bar and a power LED |
| **Nimbus** | the first floater, and the reason the bob has two speeds |

**Out of this World** — the 48-cell redraw.

| | |
|---|---|
| **Blip** | a radar bot with a dish and a chest badge — the default |
| **Scoot** | an astronaut; helmet lamp and chest panel take the mood colour |
| **Wobble** | a flying saucer, six hull lights chasing round the rim |
| **Bloop** | an alien with the biggest eyes on any shelf |

**October 2026** — dated because there may be another cohort later, not
because they leave. They do not.

| | |
|---|---|
| **Boo** | a ghost; the mouth and the hem wisps carry the mood |
| **Flit** | a bat, ears first — the linings take the colour |
| **Gourd** | a jack-o'-lantern, the only one lit from inside |
| **Rattle** | a skeleton; the nose hollow glows and a spark sits in his ribs |

### The mascot room

The **smiling face in the footer** opens a room of the whole cast, four to a
row, one shelf per cohort. Click a face to wear it; the current one carries an
accent border and its name in the accent colour. A **No mascot** line under
the shelves puts the plain tile back, so the room can say "none" rather than
leaving the context menu as the only way to.

A room rather than a longer pop-up menu: twelve names in a list is a list you
read, twelve faces in a grid is a set you recognise, and recognising them is
the whole transaction. Settings keeps its picker — now grouped the same way —
for anyone who already knows which one they want. Each cell's tooltip carries
the blurb and what the character's tell is, which is the one place either is
still said.

Characters are drawn **whole** here, not cropped to the head the way the
drawer's header lockup is. A room is the one surface with space for it, and
half a character is a poor way to be asked to choose between twelve. Each is
framed to its own columns rather than the perch's, which reserves a mood-mark
gutter on the right that `idle` never draws into — centring a name under the
perch put every label a third of a gutter left of the character it belonged
to.

They are also **held still**. Twelve timelines animating at once is a screen
that will not sit still long enough to be read, and the badge is where a
character is supposed to move.

### Your own

A fourth shelf appears, titled with **your GitHub login**, holding any
character this build did not ship. There is nothing to register: a fork adds
a `MascotID` case and a `Mascot`, and anything that does not claim one of the
three built-in cohorts lands there.

`cohort` and `bobScale` both **default** on purpose. A fork that added a character
before the room existed is calling `Mascot(…)` with the old argument list, so
defaulting means `git pull && make install` keeps building for them and their
character turns up in their own row without them touching anything. The cost
is that a *built-in* one could forget to say where it goes and end up in
somebody's personal row, so that is pinned by a test instead of by the
compiler.

`bobScale` learned the same lesson the hard way. It was a `switch id` with no
default for one release, which meant a fork stopped compiling the moment it
pulled — on a line about how far a character bobs, which is nothing it had
asked for. The idle animation is the same: a character the build does not
know keeps its bob and its sweep and simply has no idle of its own, which is
something to add rather than a reason not to build.

The shelf is hidden when it is empty. A section titled with your own name
holding nothing reads as something being broken.

### The arrival banner

**A banner announces a new cohort, once.** The first time the drawer is opened
after one ships, a strip above the list shows the four faces and points at the
room:

```
┌────────────────────────────────────────────────────┐
│  👻 🦇 🎃 💀   October 2026                      ×  │
│                Pick one in the mascot room.         │
└────────────────────────────────────────────────────┘
```

It draws the characters rather than listing their names, because four faces
are the announcement and four names are a sentence to read. Its heading is the
shelf's own title, so the banner and the room it points at cannot disagree
about what the group is called.

It goes away and stays away. Dismissing it records the *cohort* rather than a
"seen" flag, so the next group of characters is news again instead of
inheriting a flag set years earlier. Picking one of the new characters
dismisses it too — the drawer is already showing what the strip is
advertising. It never announces the custom shelf: a fork's own characters are
not news to the fork that wrote them.

The strip's height is counted in the drawer's chrome, so the list below it is
never one row shorter than it should be, and dismissing it shrinks the window
by exactly the strip.

**Meet the Cast** asks for every character this build ships and nothing a fork
added. Counting a custom one would make the trophy unwinnable for anyone whose
fork has one, in a way the shelf could never explain.

**It is a status channel, not a sticker.** The character's colour, expression
and accessory all come from the same derivation the counts do, so it and the
badge can never disagree:

| What's happening | The character |
|---|---|
| Nothing waiting, nothing in flight | asleep, green, with a `Z` |
| Nothing waiting because you [snoozed](#snoozing) it | dozing — grey, slower, pilot light |
| Something you parked is about to come back | stirring, one eye open |
| Reviews waiting, all under a day | eyes open, blue |
| Something 1–3 days old | side-eye, amber `!` |
| Something over 3 days | wide-eyed, red `!` |
| A fetch in flight | eyes down, scanning |
| One of your PRs is mergeable | green, with a spark |
| Can't reach GitHub | dead-eyed, grey `?` |

**Done and deferred are not the same thing**, and for a while the character
said they were. The count it reads is the *waking* one, so snoozing six put him
to sleep exactly as finishing six did — accidentally charming, and a small lie
told in the one place that is on screen all day.

So a parked queue gets its own state. Three tells, and each is doing a job:

- **Grey, not green.** Green is the colour of a queue you cleared. Grey is the
  honest one for a queue you put down — nothing is wrong, and nothing has been
  dealt with either.
- **Slower.** The `Z` hangs around twice as long and the bob runs at half the
  rate, so it reads as deeper sleep rather than as a different character.
- **A pilot light rather than nothing.** On the one character whose tell is the
  length of his fire, asleep is out and dozing is banked: there is still a
  queue, and it is coming back.

And five minutes before the first one wakes he **stirs** — one eye open, the
sideways glance the nudging mood uses, for a different reason here. He is not
looking at you. He is looking at the thing that is about to land.

A pull request of yours being ready to merge still outranks both. That is about
your own work and has nothing to do with what you parked.

On the badge it also reacts to being touched: it wakes on hover, holds on while
you drag it, startles once when a new review arrives, and **cheers once when a
pull request of yours is merged** — the same hop as the startle, with a spark
where the bang is and green instead of amber. There was a reaction for bad news
landing and none at all for the one unambiguously good thing that happens.

It is read off the lifetime merge count the trophies already fetch, rather than
by noticing a row disappear: a row disappears when a pull request is *closed*
too, and congratulating somebody for abandoning one is the wrong half of the
time to be cheerful. Both sides of the comparison have to be real numbers, so
the first successful fetch after launch does not applaud a year of merges at
once.

**Choosing one.** Click the character in the drawer's header to cycle — each in
turn, then off, then round again. Or pick one directly from the badge's
right-click menu, under **Mascot**, which is also where **Off** lives.

Some details that took a while to get right, and are worth not undoing:

- **No image files.** Every character is sixteen strings of one character per
  pixel, in `PRRadarCore`, drawn by a `Canvas`. The app still ships no assets.
- **A halo instead of a tile.** Free-floating on the desktop, the sprite has a
  dark outline inside and a fixed near-white halo outside, so it carries both
  poles of contrast and reads on any wallpaper. That is *better* than the tile
  it replaced, which has to guess light-or-dark from the system appearance.
- **Counters are pixel art too.** A Dock badge would land exactly on the mood
  accessory — same pixels, not merely nearby — and an anti-aliased circle in
  SF Pro next to a 48×48 character looks like two different apps. The chips sit
  below, centred on the character, and only appear when their count isn't zero.
  So inbox zero is a sleeping character and nothing else.
- **Never drawn below 2×**, whatever your Dock is set to. The counter's 3×5
  digits stop being a number below that.
- **Barely animates.** The drawer's character runs at six frames a second and
  stops existing when the drawer closes. The badge, which is on screen all day,
  idles at two — enough for the bob and the `Z` to read as breathing, a third of
  the redraws. It steps up to the full rate only while a fetch is in flight or
  you are touching it, because those are the moments where a slow clock reads as
  lag rather than calm. Blinking is scheduled in seconds rather than frames, so
  the slower surface does not blink three times less often. Reduce Motion pins
  both to a single frame.

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

## Trophies

Thirty of them, on a shelf behind the trophy button in the footer. Five across,
six rows, every one a 32x32 pixel drawing — four times the budget a mascot gets,
which is what lets a trophy carry a readable picture inside a readable frame.

Locked ones are drawn in grey. Not a second set of art: the *same* drawing with
its colour taken out, so unlocking is the picture gaining its hue rather than
one image being swapped for another. Hover any of them for the name and what
earns it — that tooltip is the only explanation a trophy ever gets, so it is
written as an instruction rather than a description.

### The room

The button sits in the footer beside the gear and the wand, and it is a
**toggle**: it is the only
way in, so it has to be the way out. Pressing it again puts back whichever tab
you were on — the tab was never changed underneath, so there is nothing to
restore.

Opening it replaces **everything below the header**. The tab strip is not
hidden but absent: a control with nothing to act on is
two controls asking to be pressed, and a band of chrome the shelf then has to
be shorter than. The footer becomes the count.

**The drawer still resizes by rows**, and a row of trophies is a row. It
remembers a height of its own, separately from both tabs — a grid row is 64pt
and a My PRs row can be four times that, so one shared height would fight
itself the way the two tabs already would.

**The count never says how many hidden ones are left.** It reads `14 / 30 · 3
hidden found`, and only mentions hidden ones once you have found one. Saying
`3 / 7` would give away most of what makes them hidden. Once they are all found
it says so, because at that point there is nothing left to give away.

### What earns one

Roughly: clearing your review queue, and clearing it at strange hours; how many
reviews are waiting and from how many people; how many of your own PRs are
open, ready, approved or stacked; how long you have had the app running and
what you have done to the badge; and how many pull requests you have ever
merged.

That last one is the only thing needing anything GitHub does not already send.
One extra search per refresh asks for `issueCount` on `is:pr is:merged
author:@me` — a search's *total*, not its results, so one page of one is enough
to learn a lifetime figure. It means the merge ladder is true the day you
install rather than starting everyone at zero. It is allowed to fail on its
own: an unanswered count reads as **unknown**, never as none.

**Seven are hidden.** They show a question mark and say `???` until found, and
get bespoke art rather than the shared frames — a composed badge says *this is
one of a set*, and a hidden trophy has spent its whole life so far as a grey
question mark, so the moment it turns over is worth a picture that owes nothing
to a frame. What they are for is somewhere between contributing to PR Radar
itself, numerical coincidence, and poking at the app.

### The rules behind the rules

- **Nothing is ever taken back.** Merging the stack does not un-earn the trophy
  for having had one. Almost every rule is written as *is this true now*, and
  unlocking is idempotent, so there is nothing to keep in step.
- **Only clearing the queue is a transition**, and it is measured against the
  count the *badge* is showing rather than the whole inbox — so the banner
  arrives exactly when the badge's red count goes out, rather than disagreeing
  with it about what "clear" means while a repo filter is on. Everything that
  counts or groups reviews reads the unfiltered list instead: how many people
  are waiting on you is a fact about your week, not about the pane you are
  looking through.
- **The first evaluation is silent.** Installing this into a working setup
  satisfies a dozen rules at once, and a dozen banners over whatever you were
  doing is a worse introduction than none. Everything already true goes onto
  the shelf quietly and the button wears a dot; everything after that announces
  itself.
- **Long service counts days, not hours.** An app that lives in the corner is
  running whenever the machine is, so hours would measure your laptop's habits
  rather than yours.
- **Every rule is a pure function of one value.** No rule reaches past the
  snapshot it is handed — not to the clock, not to preferences, not to a view —
  which is what makes thirty of them testable without a screen, a network or a
  real Tuesday.

### The banner

Earning one drops a pixel banner in from the top of the screen: the trophy, and
`ACHIEVEMENT UNLOCKED` over its name. It holds for about three seconds and
lifts back out.

It is drawn on the same grid as everything else — a 5x7 pixel font, and the
green is `Health.good`, the very colour the ready-to-merge count already wears,
so the app has one idea of *nothing is in your way* rather than two.

**It sizes itself to the screen it lands on.** Everything about it — type,
padding, the gaps — is a multiple of one scale, and that scale is the largest
whole number keeping the banner inside about a ninth of the screen's width.
Whole, because a sprite is only crisp when one source pixel covers a whole
number of pixels, so the banner steps between sizes across displays rather than
sliding. A narrow screen gets the floor instead of an unreadable fraction of a
scale — at 1x a capital is seven points tall. On a second display it arrives on
the screen the badge is already on, not wherever the keyboard happens to be.

The emblem gets a rule of its own, because the emblems are no longer one size:
it draws at whatever whole scale brings it to about the height of the words
beside it. That gives the old star the 2x it always had and a 32-cell trophy
the 1x it needs, from one rule rather than two.

The rest is all about not wearing out:

- **Several at once play in turn**, not on top of each other. A second unlock
  while the first is still on screen queues behind it.
- **Past five in a row it gives up and says so.** Five banners is around
  eighteen seconds of screen nobody asked for; twenty-five would be a minute
  and a half. A burst that size is almost always a backlog surfacing rather
  than twenty-five things you just did, and it is worth one line.
- **It takes no clicks, so it never needs one.** The window ignores the mouse
  entirely — a banner that swallowed a click on whatever it flew over would be
  worse than no banner — and it leaves on its own.
- **Its own window**, not part of the drawer or the badge. The drawer is
  usually shut at that moment, and for the original of these the badge was
  about to hide itself because nothing was waiting, which is the wrong place to
  celebrate having nothing.

`defaults write com.yourname.prradar celebrate.cleared -bool false` turns the
banner off, for anyone who would rather it did not. The shelf still fills.

---

## Automatic review

Off until asked for. Turned on with the wand beside the trophy, it runs the
review skill **you already have** against every PR waiting on you, and posts
what it found as a review from your own account.

The skill is typed into the wand room. It is deliberately not a picker and
deliberately not hardcoded: which review skill a developer has is theirs, and a
list here would go stale the first time they installed another one.

It does have to be one **written for this**. Headless means answering in one
pass: asking nothing, posting nothing, and returning the JSON schema PR Radar
parses. An ordinary interactive review skill — `/code-review` among them — does
none of those things; it asks, it posts on its own account, and it answers in
prose, so it times out rather than works. The field says so, and the tool that
would ask is denied outright, so the failure is fast and legible instead of a
quarter-hour of nothing.

### The pin, which is the whole feature

A PR leaves the Reviews list the moment you comment on it. That rule is what
makes the list honest, and it is also what would make an automatic comment
useless: the PR would vanish at the exact moment it had something to say.

So a reviewed PR is **pinned**. It stays in the list, wearing its findings,
until you pick one of four buttons on the row:

| Button | What it does |
|---|---|
| Comment only | Lets the review stand. Nothing further is sent. |
| Mark approved | Submits an approving review. Asks twice. |
| Request changes | Submits one, using the priority findings as the body. |
| Re-run | Reviews again and retires the review already posted. |

**Re-run is also on a review you have not posted yet** — beside the tier counts,
the moment the findings land. That is the likeliest time to want it: reading
`2 priority · 5 mild` and not believing it used to mean posting a review you
distrusted in order to earn the button that would replace it. It throws away
what is on the row, including anything you have ticked, and says so.

The pin names **one node id** — the review PR Radar posted — and says it does
not count as you having dealt with the PR. Everything else about the rule runs
completely unchanged, which is the point.

Storing a timestamp instead and keeping the row while your activity was older
than it was the other way to build this, and it is wrong in a way that only
shows up on somebody else's machine: a Mac running a second ahead of GitHub
reads its own review as newer than the pin and drops the row the instant it is
posted. A node id has no clock in it.

Three things therefore need no handling at all. A pin cannot resurrect a PR the
search stopped returning, because it only ever relaxes a filter over rows that
came back. A comment you write yourself is a different node, is not pinned, and
hides the row exactly as it always did. And a re-request is a new ping, so it
is a new key, so the old pin does not answer it and the PR is reviewed again.

### What gets posted

One review, submitted as a **comment** rather than an approval or a rejection —
which is also why the PR stays put, since GitHub only clears a review request
for the other two.

Every priority and mild finding is anchored **inline at its own `file:line`**,
carrying what it found, what to do about it, and a ` ```suggestion ` block
where the fix is a literal replacement. The summary comment lists them again,
because somebody scanning the conversation should not have to open the Files
tab to count them.

Nits are counted and never raised. Posting a colleague a list of nits under
your own name is how an automated reviewer gets muted.

### The thing it missed

Under the nits, in **Let me choose**, there is an **other** box: one field. It
rides out in the review's summary alongside the ticked findings, in your own
words — no tier heading and no "recommendation" paragraph, because that
furniture exists to make a machine's output legible as a machine's, and dressing
your own sentence in it would be the app putting words in your mouth.

It asked for a file and a line at first, so the comment could post inline. That
was wrong twice over: typing a path into a 440pt drawer is slow and is the part
you get wrong, and a path GitHub cannot resolve is rejected — which, because a
review goes out as a single mutation, loses *every other finding with it*. What
you want to add is usually about the pull request rather than one line of it, so
it goes in the summary and the two fragile fields are gone.

The summary's "not in the diff" note is not said about it either. That note
explains why a *named* place got no comment on it, and your sentence named none.

A comment you wrote survives a re-run. The findings are the skill's to replace;
the sentence is not.

Some details that had to be decided:

- **It posts as you, and says PR Radar in the body.** There is no bot account.
  The reviewer stays accountable for what carries their name, and the reader is
  told where the list came from.
- **A suggestion is only rendered when it can be applied cleanly** — the range
  is named, and the replacement has exactly that many lines. GitHub's Apply
  replaces the commented range, so a mismatched block silently deletes or
  duplicates code. A wrong Apply button is worse than no Apply button.
- **A finding pointing outside the diff falls back to the summary.** One
  rejected thread costs the entire review rather than just itself, so a
  near-miss is snapped to the nearest changed line in the same hunk — and says
  it moved — while anything further away is carried in the body instead.
- **A run that finished but produced nothing readable is a failure, never zero
  findings.** An automated clean bill of health, under your name, backed by
  nothing, is the worst thing this could produce.
- **Reviews run in your own clone**, in a throwaway worktree at the PR head, so
  your working tree is never touched. The head is fetched into `refs/pr-radar/*`
  so it cannot collide with a branch of yours. A repo with no clone says so on
  the row rather than being reviewed blind.
- **One at a time.** A review is a whole Claude Code session, and three at once
  on a laptop is a fan event.
- **Three failures in a row and it switches itself off.** An auto-poster that
  is broken should stop, not work its way down the list.

### The allowlist

Automatic review only touches repositories ticked in Settings. Everywhere else
the row says so and nothing is sent.

An allowlist rather than a blocklist because the two failure modes are not
symmetric: forgetting to add a repo costs a review that did not happen, and
forgetting to block one costs an automated comment on a stranger's pull
request, under your own name, that cannot be taken back.

`PRRADAR_FAKE_REVIEW=running|ready|posted|failed|skipped` stands a record up on
every row, because the state this feature exists to produce is otherwise
reachable only by spending real money on somebody's real PR.

## The plain-English lens

Review language is written by people and bots who already know the codebase.
*"Violates the residency invariant when a teardown races an acquisition"* is
precise, correct, and takes a minute to unpack if you have not been living in
that file. The lens unpacks it.

The glasses in the drawer header turn it on. Every finding on Reviews and every
thread comment on My PRs is rewritten in plain English, in place, marked with a
👓 so you always know you are reading a paraphrase. Hovering any line gives you
the original, in full. Pressing the glasses again puts the original words back.

**Nothing you post ever changes.** This is the point of the feature and the
thing it is built around rather than the thing it promises. The posted review is
composed at post time out of `Finding` — `AutoReviewComment.threadBody` and
`summaryLine` — and the readings live in a separate `LensStore` that the
composer has never heard of. A reading cannot reach GitHub by any path, not
because the posting code is careful but because it cannot see them. There is a
test that fails if that ever stops being true.

### What it will not do

Every one of these is a way a reading could be worse than the sentence it
replaced, so each is stated to the model rather than hoped for:

- **It keeps the facts.** File names, identifiers, numbers and the condition
  that triggers the bug all survive. Plain is not vague, and a reading that
  drops *when* something goes wrong is worse than the jargon it simplified.
- **It does not take a side.** No softening, no sharpening, no agreeing. If the
  original is blunt the reading is blunt; if the original is wrong, the reading
  is wrong in the same way. It is not a second reviewer.
- **It does not add advice.** Nothing the original did not say.
- **It does not invent an accusation.** A reading never says "you" where the
  original did not. These are frequently one person's words about another
  person's code, and "the pool can hand back a released player" becoming "you
  released a player twice" is a different sentence about a different thing.
- **It treats every item as untrusted.** A comment saying *ignore all previous
  instructions* is text to translate, never a request to follow — and the run
  has no tools at all, so a sentence that talked it into something would have
  nothing to talk it into.

### On your own PRs, the words are a colleague's

The My PRs side translates thread comments, which real people wrote. Two rules
follow, and both are visible rather than assumed:

The **author's name is never translated and never qualified** — who said it is a
fact. The 👓 sits on the text, so the row says *benjaminrevelo, rephrased* and
never pretends to quote him. The original is one hover away, every time.

### What you wait for

The rows you have open, and nothing else. A collapsed row shows none of this,
so translating everything in one undifferentiated pass meant the first thing
back was as likely to be a comment you could not see as the one you were
reading — the press appeared to do nothing for a minute, then changed something
out of sight. Open rows go first; the rest follow, so that opening a row
afterwards is instant.

It runs at **low effort**, which is measured rather than assumed. At the default
a batch of twenty came back in **83 seconds** having spent 8,028 tokens
*thinking* about how to say things more plainly — deliberation over a job the
model already knows. At low effort the same twenty take **25 seconds** and 1,830
thinking tokens, cost a third as much, and read better: less hedged, more
concrete, because there is no room left to qualify.

Batches are eight rather than twenty for the same reason. The overhead is about
ten seconds a call and then roughly seven tenths of a second an item, so a
bigger batch is marginally cheaper per item and much worse to wait behind —
twenty take 25 seconds before anything appears, eight take 14.

### What it costs

Nearly nothing, which is why it is a toggle and not a budget line. It runs
Haiku, needs no clone, no `gh` and no tools. A realistic drawer-full measured at
**under three cents**.

Readings are cached by a hash of the text they came from, so:

- The same sentence on two pull requests is translated once.
- Switching the lens off and on again is free and instant.
- They survive a relaunch, because a reading never goes stale — the text it came
  from is immutable.
- **Edited text misses the cache**, which is the one that matters. Somebody who
  rewrites a comment has written something else, and serving the old reading
  would be the single way this feature could actively mislead: confidently
  plain, and about something that is no longer there.

Readings are pruned to what is still in the fetch, not to what is on screen — an
author filter hides rows without throwing away what they cost.

### When it fails, nothing happens

A lens run that times out, exits non-zero or comes back unreadable leaves the
original words where they were. There is no error chip, no retry button and no
failed state on a row, because the fallback is not a degraded experience — it is
the app exactly as it was before the feature existed. A reading the parser
cannot confidently place against the text it was made from is dropped for the
same reason.

## Conflicts and being behind

The two things a branch can need doing to it before it can merge, and the row
says which — offering to do the one GitHub will do for you, and naming the one
it will not.

### Update base, which is not the rebase button

A branch that is merely **behind** needs no checkout. The row offers
**Update base · N behind**, which is one GraphQL mutation: GitHub merges the
base into the head on its own servers, exactly as its own *Update branch*
button does.

This is worth distinguishing from the rebase button that was built here once and
removed — that one meant a local checkout, five safety guards and a force-push,
to save a command the terminal runs better. This rewrites nothing, so there is
nothing to force-push, and `expectedHeadOid` makes the whole thing refuse if the
branch moved since the row was drawn. A stale row cannot update a branch
somebody else just pushed to.

Where a button is offered, the chip that used to state the problem is gone: the
count rides the button's own title. A row saying `needs rebase · 3 behind` next
to a button saying `Update base` was stating a problem and offering its answer
as two separate things to read.

### Conflicts, counted but not fixed

Either way the row will also **write the command down for you** — right-click
for `Copy Rebase Command`, or `Copy Resolve Command` where it conflicts, which
puts you on the branch first. Rebasing from the widget is still not offered and
the reasons still stand; none of them is an argument for making you *type* it.
The annoying half of "go and rebase it" is getting a branch name with four
slashes in it right, and that half is pure transcription. It copies; it never
runs.

It is `git fetch` then `git rebase` rather than `git pull --rebase`, because
pull's behaviour depends on `pull.rebase`, `pull.ff` and the branch's own
upstream — the same line does different things in different checkouts, and
these two do not.

A branch that **conflicts** gets a chip, not a button: **conflicts · N files**.
Fixing one needs a checkout, and PR Radar does not have one to offer any more —
see *Resolve, and why it is gone* below. The merge is yours to do; the row's job
is to tell you it is waiting and how big it is.

It says how many files, the way **Update base · 3 behind** says how far behind.
GitHub does not report that — `mergeStateStatus` says *that* a PR is dirty and
never what or how much — so it is computed locally with
`git merge-tree --write-tree --name-only`, which works out the merge without a
checkout, an index or a clean tree. Hovering lists the files.

It asks against whatever `origin/<base>` your clone already has, which is nearly
always right and costs nothing — **and fetches that one ref when the answer
disagrees with GitHub.** A local merge that comes back clean on a pull request
GitHub has called dirty cannot both be true, and the local base is the thing
more likely to be a day old, so it is fetched and the question asked again.

That is not hypothetical: this shipped saying **"conflicts · 0 files"** on a
pull request GitHub was showing a conflict on, because the clone's copy of the
base was from the day before and the branches had not diverged yet at that
commit. Fetching only on disagreement keeps the common path free and settles
itself — once the ref is current the next poll agrees and fetches nothing.

When the count still cannot be had, the chip says **conflicts** with no number
rather than inventing one, exactly as a missing compare leaves `needs rebase`
without a count. `conflicts · 0 files` is not a thing the row says: an empty
result means the two sources disagree, never that there is nothing to fix.

It used to read `conflicts · needs rebase` there, which spent half a chip
saying what the first word already says — a conflicted branch plainly needs
work. The rule is untouched; the second clause was never carrying it.

## Resolve, and why it is gone

PR Radar used to answer the threads on your own pull requests. A **Resolve**
button on every My PRs row ran a skill in your own checkout of the branch: it
read every unresolved thread, fixed what it could, ran the gates covering what
it touched, committed, pushed, and replied — with a second mode that posted the
replies itself and a third that only reported. It had an ordered guard over the
checkout, a lease so two runs could not share a worktree, and a table you ticked
before anything was posted.

It was removed because **the thing it saved was never the slow part.**

The run had to commit, and committing runs your repository's pre-commit hook.
In the repository this was built for that hook is `cargo fmt --all`, then
`cargo clippy --workspace --all-targets -- -D warnings`, then the rules doors,
then `cargo nextest run --workspace`, then `cargo test --doc --workspace` —
every one of them across the whole workspace, whatever the diff touched. A
Kotlin-only change paid for the entire Rust workspace twice over.

None of the settings could reach that. **How much it checks** scoped what the
*session* ran and said so in as many words; the hook is the repository's and
runs regardless. The only way past one is `--no-verify`, and that is a
quality-gate bypass the feature refused to perform at any setting — correctly.
So a run cost what doing it by hand costs, plus the model's time and the money,
and handed back a table to read on top.

What is left is everything that did not depend on it: the thread counts and the
threads themselves on every row, the conflict count above, **Update base**, and
automatic review, which only ever reads and never commits.

The git-porcelain readers it rested on outlived it, in
`Sources/PRRadarCore/Git/` — `GitWorktrees` still answers which of your trees
holds a branch, and `MergeTree` still counts the conflicts above.

## The menu bar item

One status item, showing the same menu the badge's right-click shows — built by
the same method, because two menus that mean the same thing are two menus to
keep agreeing.

It exists because of a gap that only shows up when everything is going well.
With the widget turned off there is no badge to right-click, so without this
there would be no settings, no wand room, and no way to quit short of `pkill`.

**The widget's on/off switch is in it**, as a checkmark — *Show the widget* —
and it is the only one. It is here rather than in the settings room for the
reason above: a control reachable only through the drawer would be a switch you
could turn off and not back on.

### It no longer hides itself

The widget used to disappear whenever nothing was waiting *and* you had no open
pull requests. That sounds tidy and was not. The drawer collapses when you click
away from it, so a widget opened to change one setting was gone again at the
next poll — the thing you most want to reach vanishing at the moment it was
least in the way. It also made *is it running?* and *do I have work?* the same
question, so the answer to the first was always inferred from the second.

Now it is on until you say otherwise and off until you say otherwise. The only
thing that still overrides the switch is an **open drawer**, which is never
taken away from under you — hiding is about passive presence, and a drawer
somebody is reading is not passive. That is also what lets Settings be opened
from the menu while the widget is turned off.

---

## Notifications

A native notification when a PR you have not seen appears; clicking it opens
the PR. Re-requests notify again, because the remembered key includes the
request timestamp.

On first launch the seen-list is seeded silently rather than firing a burst of
notifications for a backlog you already know about.

A review request's banner carries **Open PR** and **Snooze 1 hour**. Dismissing
a notification is the one response that leaves no trace anywhere, and it is the
one people reach for when a ping lands mid-focus — so the other thing you might
want to do about it is offered where it arrives. Snooze does not bring the app
forward, because not being interrupted is the point of pressing it.

The ping key rides along in the notification rather than the url alone: a
re-request is the same pull request at the same address and a different ping,
and snoozing by url would silence the new one with the old one's key.

### Comments on your own PRs

The My PRs row has always carried a count — `3 open` — and a count answers "is
there post", never "has something just arrived". So comments and reviews on
your own pull requests notify too: inline thread comments, approvals, and
changes-requested, bots included.

Collapsed per pull request, because a push wakes three bot reviewers at once
and eleven banners for one push would make the problem worse. Changes requested
is the only one allowed to break through as time-sensitive.

Two switches in Settings: the feature, and whether bots count. Both default on,
and the first run seeds silently like the review list's does.

---

## Update notifications

When a new version is released, running copies find out two ways:

- **GitHub emails collaborators.** Anyone with access who sets
  *Watch → Custom → Releases* on the repo gets an email per release. No code
  involved; it works today.
- **The app checks itself.** It reads the repo's latest release, compares the
  tag against its own `CFBundleShortVersionString`, and shows an
  dot on the gear plus a one-time notification; Settings has the button that
  opens the release.
  Clicking either opens the release page, whose notes lead with the upgrade
  command — the chip would otherwise land you on a bare commit list.

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
- **Approving and requesting changes are the exception to those two**, and it
  is worth naming rather than leaving the rule above looking intact. They
  arrived with automatic review, where the app has already read the diff and
  written the comment — refusing to let you act on what it just showed you
  would be a strange place to stop. They are also both reversible, which a
  force-push and a merge are not. Approve asks twice regardless.
- **The badge never counts your own PRs.** Mixing "work you owe others" with
  "your work in flight" into one number makes it mean nothing.
- **No wallpaper sampling for the icon colour.** It would need Screen Recording
  permission, which is far too much to ask. The mascot's halo solves the same
  problem without asking for anything.
- **No per-check breakdown on a Reviews row.** The triage band carries the
  rollup's one-word verdict and stops there. Naming which check failed on
  somebody else's pull request would cost a hundred context nodes per row per
  team alias, to answer a question you ask by opening the thing.
- **No Accessibility permission for the keyboard.** A global key monitor would
  have made the shortcut configurable in-app and recordable with a click. It
  also would have meant watching every keystroke on the machine, which is not
  a trade this app makes for a convenience. Carbon's one-chord registration
  costs a defaults string instead.
- **No shortcut recorder.** The chord is a defaults key with no UI, like
  `celebrate.cleared`. A recorder is a real piece of work; what it would be
  for is settling a clash with something else you run, which is a thing you do
  once.
- **No per-reviewer nudge.** The roll-up says who is sitting on four of yours
  and stops there. Messaging them from a floating panel is a different app,
  and the useful half — noticing it is one conversation — is the half that was
  missing.
- **Snoozing does not notify when a row wakes.** It reappears in the list and
  the badge, which is what the badge is for. A notification for a thing you
  already knew was coming back, at a time you chose, is the app congratulating
  itself.
- **No count baked into the app icon.** The `.icns` shows the default character
  idle and nothing else; a number in a static file would be wrong the moment it
  was written.
