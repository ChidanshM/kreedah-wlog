# Using Wlog

A walkthrough of everything the app does, with worked examples. Written
because the interface does not explain itself — that is a real shortcoming
and this document is a stopgap, not a substitute for fixing it.

---

## Before anything else: Equipment

**More → Equipment.** Do this first. It is the single thing that makes
logging fast, and until it is filled in the app feels worse than it is.

Every weight you add here becomes a one-tap chip while logging. Tap **Weights**
and you get four boxes:

| Box | Meaning |
|---|---|
| Weight | a single weight, or the start of a range |
| up to | the end of a range — leave empty for one weight |
| step | the gap between weights in the range |

**Example — a dumbbell rack.** Kind: Dumbbell. Unit: kg. Weight `2.5`,
up to `30`, step `2.5`. One tap adds twelve weights.

**Example — three kettlebells.** Kind: Kettlebell. Add `16`, then `24`,
then `32`, each on its own, leaving the other two boxes empty.

**Example — a cable stack in pounds.** Kind: Machine / cable. Unit: lb.
Weight `10`, up to `200`, step `10`.

The kind matters. When you log a lat pulldown, the app offers only your
machine weights; a kettlebell swing offers only kettlebells. If an exercise
uses equipment you have not added, you get no chips and type the number
instead — that is working correctly, not a bug.

**Other gear** lower down is a set of toggles for things without a weight:
bench, pull-up bar, bands, box. These feed the "only what I can do" filter
when searching exercises.

---

## Building a routine

**Train → the + Routine button.** Name it after the day or the session —
`Push`, `Monday`, `Lower body`. Make as many as you like; there is no limit.

Inside, **+ Exercise** opens the library. Search, tap to select as many as
you want, then the **Add** button. They arrive in the order you selected them.

Tap any exercise in the routine to configure it:

**Set type** — three options, and picking the right one matters because it
changes what gets recorded.

- *Reps × weight* — the default. Bench press, curls, squats.
- *Time* — logs seconds. Planks, dead hangs, loaded carries held in place.
- *Steps / distance* — logs a count. Farmer's carries, sled pushes.

**Default unit** — kg or lb, remembered per exercise. If your dumbbells are
metric and the cable stack is imperial, set each accordingly and stop
converting in your head.

**Unilateral** — turn on for anything done one side at a time. Each set then
records right and left separately, in that order, sharing one RPE. Both sides
count toward volume. The app guesses this from the exercise name — anything
called "single-arm" or "alternating" defaults to on — but check it.

**Sets** — how many appear pre-filled when you start. Change it mid-session
freely; this is a starting point, not a commitment.

Drag the handle at the right of each row to reorder. Long-press and drag.

---

## Doing a session

**Train → Start** on a routine.

Every set arrives already filled in with what you did last time, so the
common case is: look at the number, tap **Log**, move on.

### Where the numbers come from

The line under each exercise name says, for example:

> Last Friday, 12 days ago, three sets at 20

That is the last time you did *this exercise in this routine*. Set 1 copies
last set 1, set 2 copies set 2, and any set beyond what you did last time
copies the final one.

If you have never done that exercise in that routine, it falls back to the
last time you did it anywhere and says so — the line will read `other routine`.
That matters: bench on Monday and bench on Friday sit in different fatigue,
so a Friday number appearing on Monday deserves a second look.

No history at all means empty fields and no line.

### Logging a set

Carried-over numbers are **lighter** than confirmed ones. That is deliberate:
a pale number has not happened yet.

- Numbers right → tap **Log**. Row turns sage green, number goes solid.
- Numbers wrong → tap anywhere on the row to open the editor.
- Logged something by mistake → tap the green tick to undo it.

### The set editor

Opens when you tap a row.

**Weight** — type it, or tap one of your equipment chips underneath.

**Reps** — type it, or spin the rotating counter. They are the same number
shown two ways; changing one moves the other. Spinning is quicker for eight
to nine, typing is better for twenty-three.

**RPE** — tap a chip from 6 to 10 in halves. Optional; skip it and the column
shows a dash. Roughly: 10 is nothing left, 9 is one more rep available, 8 is
two or three.

**Save draft** keeps the numbers without marking the set done — useful for
setting up a set before you do it. **Log set** records it as completed.

For a unilateral exercise the editor shows Right and Left separately, and
the rotating counter drives whichever side you last tapped; the label reads
`REPS R` or `REPS L`.

### When the equipment is busy

Tap **···** on the exercise you want to move.

**Do this next** brings it forward to just after whatever you have already
started — the single tap for "the squat rack is taken, do rows instead".
**Move up** and **Move down** nudge one place at a time.

Your routine is untouched. Only this session's order changes, and the
finished session records what you actually did.

### Other mid-session actions

Also under **···**:

- **Switch to lb / kg** — converts what is already entered, so the numbers on
  screen keep meaning the same load.
- **Log right and left separately** — turn unilateral on or off. Applies to
  sets you add from here on, not ones already logged.
- **Exercise note** — "left shoulder tight", "belt from set 3".
- **Remove from this session**.

**+ Add exercise** at the bottom adds something not in the routine, with its
own history pre-filled if you have done it before.

### Finishing

**Finish** shows the count and total volume, then closes the session.
Anything left unconfirmed is discarded, and exercises you never touched
disappear from the record — a session shows what happened, not what was
planned.

**··· → Discard session** deletes the whole thing.

Close the app mid-session and nothing is lost. Reopening shows a banner on
the Train screen to continue where you left off.

---

## History

Every finished session, newest first, with its date and total volume. The
strip at the bottom shows session count and all-time tonnage.

Tap one for the detail: start and finish time, volume, set count, total reps,
heaviest lift, then every exercise and set with its RPE and per-set volume.
The bin icon deletes it.

**All summary figures are in kilograms**, always, whatever unit you typed.
That is what makes them comparable — you cannot add pounds to kilos and get
a meaningful number.

---

## Library

All 1,531 exercises from the Garmin database, searchable by name and
filterable by equipment and muscle.

**Pin** the ones you use often with the pin icon and they float to the top
everywhere, including when building routines. Pin fifteen and you will rarely
search again.

Tap an exercise for its primary and secondary muscles, its equipment, its
Garmin code, and the heaviest you have ever logged on it.

**+** in the corner adds a custom exercise if something is missing.

In the picker, the filter icon also offers **Only what I can do**, which hides
anything needing equipment you have not listed.

---

## Export and backup

**More → Export** writes two files:

**`workout_sets_<date>.csv`** — one row per confirmed set, in long format,
with workout fields repeated on every row so it pivots cleanly in a
spreadsheet. Columns include the date, weekday, routine, exercise, Garmin
codes, muscles, set number, side, the unit you typed, the weight in that
unit, the weight in kg, reps, seconds, steps, RPE, set volume, and a
timestamp for every individual set.

`weight_lb` is filled in only for sets you actually entered in pounds.
`weight_kg` is on every row.

**`backup_<date>.json`** — a complete copy that **Restore from backup** reads
back. Restoring replaces everything currently in the app.

Both land in `Android/data/com.chidansh.workout_log/files/exports`.

> **Known problem.** Android restricts that folder, so most file managers
> cannot open it. Being fixed. Until then the export exists but is hard to
> get at, so do not treat it as a working backup yet.

---

## Settings worth knowing

**Show session timer** — off by default, since your watch already times the
session. The start time and a timestamp for every set are recorded either
way, so rest intervals can be reconstructed later even with the timer hidden.

---

## Updating the app

Builds are signed with a fixed key, so a new version installs over the old
one and keeps your data. Download the artifact from the Actions tab, take
`app-arm64-v8a-release.apk`, and install it.

If an install is ever refused, the signing key has changed. Do not force it —
the only way through is to uninstall, and that deletes the database.

---

## Things it deliberately does not do

- **Supersets.** No A1/A2 pairing. Log them as separate exercises.
- **Warm-up flags.** Every logged set counts toward volume. Leave warm-ups
  unlogged, or accept them in the total.
- **Rest timer.** The watch does it.

Each was considered and cut. Any of them can be added later.
