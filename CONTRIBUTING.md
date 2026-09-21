# Contributing

PR Radar is built to be forked. The README's third step is *make it yours*,
and most people who use it will change something — a chip, a threshold, a rule
about what counts as waiting on you.

Almost all of those changes stay on the machine they were made on. Not because
anyone minds sharing, but because opening a pull request against somebody
else's repository for a two-line fix is more ceremony than a two-line fix
deserves. This is an attempt to make that one keypress instead.

## What happens

Turn it on once, in your fork:

```sh
make hooks
```

After that, when you commit something to your fork that the original might
want, you are asked once:

```
  This fork has changes the original might want:

      Sources/PRRadarCore/TimeAgo.swift

  Proposing them opens a *draft* pull request on RogelioAD/pr-radar, as you.

  Propose these 1 file(s) upstream? [y/N]
```

Say yes and it pushes a branch to **your** fork and opens a **draft** pull
request upstream. Say nothing and nothing happens.

Not on a hook, or not a fork? `make contribute` does the same thing on demand.

## What it will not do

**It never acts without being asked.** It runs as you, with your `gh`
credentials, and it opens a public pull request. That is not a thing anybody
should discover after the fact. If there is no terminal to ask at — which is
exactly the case when a coding CLI is driving the commit — it prints
`make contribute` and stops.

**It never sends your team.** `Sources/PRRadarCore/MyPR/Leads.swift` is
excluded unconditionally. The README asks you to put your colleagues' GitHub
logins in it; those are other people's names and they are nobody upstream's
business.

**It never sends your bundle identifier.** Every occurrence in a contributed
file is rewritten back to the original's before the branch is built, so a file
whose *only* change was the rename produces no diff at all and is dropped.

**It never sends work you did not write.** Only commits authored by your own
`user.email` are considered. Pulling a branch from upstream and then committing
one line of your own proposes the one line, not the branch.

**It never touches your checkout.** The branch is assembled in a throwaway
`git worktree`. Whatever you were in the middle of stays exactly as it was.

## Turning it off

```sh
git config prradar.contribute false     # stop asking
git config --unset core.hooksPath       # remove the hook entirely
```

The hook is opt-in for a reason. Git deliberately refuses to run hooks straight
out of a clone, and a repository that started running its own scripts the
moment you cloned it would have earned the suspicion that gets.

## If you would rather do it by hand

Nothing here is required. The ordinary way works fine:

```sh
git remote add upstream https://github.com/RogelioAD/pr-radar.git
git fetch upstream main
git push origin your-branch
gh pr create --repo RogelioAD/pr-radar --base main
```

Check `Sources/PRRadarCore/MyPR/Leads.swift` and your bundle identifier before
you do — those are the two things the script would have taken out for you.

## What happens to it upstream

It arrives as a draft, labelled `from-a-fork`. A draft on purpose: saying yes
to sending something is not the same as proposing it for merge, and the label
is there so these can be read as a batch rather than mixed in with work that
is asking for attention.

If it is something everyone should have, it gets picked up. If it is specific
to how you work, it stays where it is and no harm done — which is the point of
the low bar.

## The usual things

- `make test` before proposing anything. Every rule worth arguing about lives
  in `PRRadarCore` as a pure function, so there is somewhere to put a test.
- Anything with a rule in it belongs in `PRRadarCore`, not in the app target.
  The split is what makes this project testable without clicking anything.
- Commit messages in this repo explain *why*. The diff already says what.
