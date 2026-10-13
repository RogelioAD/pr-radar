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
otherwise flicker every time you poked at a menu. The red count is
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
| `conflicts · N files` | the branch conflicts, and `merge-tree` counted them |
| `conflicts · needs rebase` | it conflicts, but nothing could count the files |
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
  restack. The first is dropped inside a stack group, where the PR it names is
  the row directly below it.
- **Diff size and age** — lines changed, files touched, how long it has been
  open.

Chips **wrap onto a second line** rather than running off the edge. A row can
carry five of them on a bad day, and the alternatives are both worse: squeezing
them truncates the words that make them worth reading, and letting the line
overflow pushed whatever sat to its right — the stack marker — out past the
row's edge, where it was clipped away entirely.

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
| Nothing waiting, nothing in flight | asleep, with a `Z` |
| Reviews waiting, all under a day | eyes open, blue |
| Something 1–3 days old | side-eye, amber `!` |
| Something over 3 days | wide-eyed, red `!` |
| A fetch in flight | eyes down, scanning |
| One of your PRs is mergeable | green, with a spark |
| Can't reach GitHub | dead-eyed, grey `?` |

On the badge it also reacts to being touched: it wakes on hover, holds on while
you drag it, and startles once when a new review arrives.

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

## Resolving your own threads

The other half of the job. Automatic review answers the PRs waiting on *you*;
this answers the threads waiting on everybody else — the ones on your own pull
requests.

Every My PRs row with open threads grows a **Resolve** button. It runs the
resolve skill you name in the wand room against that PR: reads every unresolved
thread, decides what to do about each, and replies.

**It is never automatic, and that is deliberate.** Review bots comment again
after every push, so a resolver on a timer would spend its life answering its
own fixes. There is no switch; there is a button.

### Two jobs, one feature

The Resolve button answers review threads. A second button, **Resolve
conflicts**, appears instead when the branch conflicts with its base — and it is
the *same run*: same skill, same checkout, same guards, same lease, with one
sentence different in its prompt. Making it a second feature would have meant a
second coordinator, a second set of guards and a second lease — three copies of
the dangerous part, to express a difference that is really one instruction.

While there are conflicts, the threads button is hidden. That is the skill's own
ordering, and the reason it gives for it: a fix applied to a branch that cannot
merge gets re-resolved by hand later, and an *already done* verdict proved
against a pre-merge head is simply wrong. One button at a time, and it is the
one to press first.

The button is **Rebase & resolve · N files**, and it does the whole sequence in
order: brings the checkout up to the pull request if it has fallen behind,
merges the base in, resolves what conflicts, and pushes. One press.

(It says *rebase* because that is the word the row has always used for bringing
a branch up to its base — the `needs rebase` chip predates all of this. The
mechanism is a merge: base **into** the branch, never a rebase of a branch that
is already pushed, which is the one thing the run is forbidden to do.)

It says how many files, the way **Update base · 3 behind** says how far behind. GitHub does not report that — `mergeStateStatus` says *that* a PR is
dirty and never what or how much — so it is computed locally with
`git merge-tree --write-tree --name-only`, which works out the merge without a
checkout, an index or a clean tree. Hovering lists the files.

It asks against whatever `origin/<base>` your clone already has, which is nearly
always right and costs nothing — **and fetches that one ref when the answer
disagrees with GitHub.** A local merge that comes back clean on a pull request
GitHub has called dirty cannot both be true, and the local base is the thing
more likely to be a day old, so it is fetched and the question asked again.

That is not hypothetical: this shipped saying **"Resolve conflicts · 0 files"**
on a pull request GitHub was showing a conflict on, because the clone's copy of
the base was from the day before and the branches had not diverged yet at that
commit. Fetching only on disagreement keeps the common path free and settles
itself — once the ref is current the next poll agrees and fetches nothing.

When the count still cannot be had, the button says **Resolve conflicts** with
no number rather than inventing one, exactly as a missing compare leaves
`needs rebase` without a count. `conflicts · 0 files` is not a thing the row
says: an empty result means the two sources disagree, never that there is
nothing to fix.

A conflicts run merges base **into** the branch, never the reverse and never a
rebase of a branch that is already pushed. Conflicts in generated output, lock
files and goldens are regenerated rather than resolved by picking a side. If
both sides changed the same logic incompatibly it stops and says so rather than
guessing — the same bar as *needs you*.

### Update base, which is not the rebase button

A branch that is merely **behind** needs no skill and no checkout. The row
offers **Update base · N behind**, which is one GraphQL mutation: GitHub merges
the base into the head on its own servers, exactly as its own *Update branch*
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

### Where it runs, and what it refuses

In **your own checkout of the PR's branch** — not a throwaway worktree, because
the fixes have to be pushed from somewhere you can push from. Which means every
run starts by proving the tree is safe to work in, and refuses with a sentence
rather than tidying up on your behalf:

| It says | Because |
|---|---|
| `feat/x is not checked out anywhere` | it will not `gh pr checkout` into your clone |
| `4 uncommitted changes in app-feat` | that is somebody's work in progress |
| `that checkout is at a1b2c3d; the PR is at e4f5a6b` | it could not be fast-forwarded there — the branch has commits of its own |
| `a merge is in progress` | a half-finished rebase is not a base to build on |
| `feat/x has no upstream to push to` | a reply citing a commit is false until it is pushed |
| `the branch is on their fork` | it cannot push there |

### It catches up on its own

A branch that has moved — usually a bot pushing after a review — leaves your
checkout a commit or two behind the pull request, and a run started there would
merge into code older than the pull request and then write replies citing it.

That was a second button for about an hour. It is now the first thing every run
does, because two buttons to press in a fixed order is a worse answer than one
that knows the order — and this step has no decision in it: a checkout that is
simply behind is a fetch and a pointer move.

**Only ever a fast-forward.** If the branch turns out to have commits of its own
the run stops and says how many, because a reset would make it work and would
throw those away — whether to rebase, push or discard them is yours to decide,
not something to settle at a button press. The tree is re-checked for
uncommitted work at that moment too, rather than trusted from a poll.

Untracked files do **not** block it. Generated bindings, `target/`, `build/` —
every real checkout has them, and none of them is work a run could destroy.

### Three modes

| | |
|---|---|
| **Just tell me** | Reads and reports. Nothing is edited, committed, pushed or posted. |
| **Fix it, then let me post** | Applies fixes, runs the gates, commits and pushes — then stops. You tick the replies and PR Radar sends them. |
| **Fix it and post it** | The whole thing, as your skill runs it from a terminal. |

The middle one is the default, and its label is careful on purpose. Curated
*review* promises nothing has happened yet. Curated *resolve* cannot: a reply
saying "fixed in `a1b2c3d`" is false until that commit is pushed, so the code
has already landed by the time you read the table.

### What it will not be talked out of

The pull request's own comments reach the model, so these are denials rather
than instructions:

- A thread needing a product or design call is **never resolved**.
- A thread is **never resolved without a reply**, and never over a reply that
  did not actually land — a draft review of your own silently swallows replies,
  and that is checked.
- A reply citing a commit is **held back until that commit is on the remote**.
- **Nothing is ever written to Asana.** A ticket nobody approved is worse than
  a gap, so gaps are reported instead.
- The session cannot `checkout`, `switch`, `rebase`, `reset`, `stash` or
  force-push. It works in the tree it was given.

### The gates, answered in advance

A skill with interactive menus does not fail headlessly — it *waits*, and then
times out having done nothing. So the wand room has a **Resolve answers**
section holding the answers to the questions your skill would stop at: what to
do with out-of-scope work, and what to do about an unsubmitted draft review.
They are passed into the session so it never reaches the menu.

### How much it checks, and stopping it

A conflict in a single Kotlin test fixture took **sixteen minutes**. Almost all
of it was `./gradlew testDevelopmentDebugUnitTest lintDevelopmentDebug`, then a
pre-commit hook running the whole Rust workspace again. Both were correct — the
skill says to run the whole suite, and that is right when nobody is watching.
Somebody *was* watching, and in a terminal they would have said "it is a
fixture, build the test module".

**Checking** is how you say that without being there:

| | |
|---|---|
| Run the full suite | Thorough and slow. Minutes, not seconds. |
| Only what it touched | The crate or module the change is in. Much faster, blind to what it broke elsewhere. |
| Leave it to CI | Runs nothing. The pull request's own checks are the only judge. |

It scopes what the **session** runs and nothing else. Your repository's own
commit hooks still run at every setting, because the way to skip one is
`--no-verify` and that is a quality-gate bypass this will not perform however it
is configured. Running fewer checks is your choice; defeating one that runs is
not, and the framing says so at every level.

And there is a **Stop** button on a running row, which there was not at first —
the only ways out of a quarter-hour you had changed your mind about were
quitting the app or finding the pid. It asks the session to stop rather than
killing it, so a commit in flight finishes instead of leaving `index.lock` in
your repository. That makes stopping not instant, and the row says *Stopping…*
while it waits. A run stopped after it had already pushed is reported as having
landed unreported, not as stopped: there are commits on the branch either way.

### When it is interrupted

A resolve run is **never restarted**. An interrupted review had only read, so
asking again is safe. This one may have edited, committed and pushed, and
nothing can tell from outside which — so the row becomes evidence instead:

- *interrupted* — nothing had landed. Press it again.
- *N commits landed unreported* — code reached the branch and nobody read the
  table. The row hands you the `git log` that shows what. **Never pruned**, and
  never offered a retry.
- *still running elsewhere* — a run from a previous launch is still going.

Quitting while one is in flight asks first, which is the only place this app
interrupts a quit.

---

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
- **No count baked into the app icon.** The `.icns` shows the default character
  idle and nothing else; a number in a static file would be wrong the moment it
  was written.
