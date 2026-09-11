# Using Wlog

A walkthrough of everything the app does, with worked examples. Written
because the interface does not explain itself — that is a real shortcoming
and this document is a stopgap, not a substitute for fixing it.

---

## Getting around

Five tabs along the bottom.

**Train** — your routines, and where a session starts.
**Calendar** — planned days against logged ones.
**Home** — the middle tab, and where the app opens. What is happening now.
**Logbook** — every finished session.
**More** — equipment, library, scheduling, export, settings, this guide.

**Home** answers "what do I do next" rather than showing statistics. A
session left running sits at the top, since forgetting one is the failure
that costs you data. Then what the schedule asks for today, with a Start
button, or a tick if it is already done. Then your last few sessions, then
the way in to the stopwatch, the library, scheduling and equipment, and
finally the next three days — one line each, naming what is planned or
saying the day is a rest.

---

## Equipment first

**More → Equipment.** Do this first. It is the single thing that makes
logging fast, and until it is filled in the app feels worse than it is.
(Also reachable from Home.)

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
bench, pull-up bar, bands, box.

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
records right and left separately, in that order, each with its own weight,
reps and RPE. Both sides count toward volume. The app guesses this from the
exercise name — anything called "single-arm" or "alternating" defaults to on
— but check it.

**Sets** — how many appear pre-filled when you start. Change it mid-session
freely; this is a starting point, not a commitment.

**Rest** — seconds to count down after each set is logged. Leave it empty for
no timer.

### When one set differs from the others

**Different values per set** turns the single target above into a table, one
row per set, with its own count, weight, RPE and rest.

Anything left blank falls back to the target above, so a drop set means
filling in one row rather than four. Turning the switch back off deletes
those rows rather than hiding them, so nothing reappears unexpectedly later.

What you actually lifted last time still takes precedence over both. A target
is an intention; history is evidence.

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

If the exercise is set to pounds, the kilogram figure appears beside it in
brackets. Every summary in the app is in kilograms, and this is the one place
the two can be compared directly.

Where the routine asked for a rest, logging a set starts a countdown banner
at the top with a **Skip** button, and buzzes when it ends. It never blocks
anything — you can keep logging straight through it.

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

For a unilateral exercise the editor shows Right and Left separately, each
with its own weight, count and RPE. The rotating counter and the RPE chips
both act on whichever side you last tapped — the labels read `REPS R` and
`RPE R` so you can see which. Each side's current rating stays visible beside
its name, so you can tell them apart without switching back and forth.

That asymmetry is the whole reason for logging sides apart. Same load, harder
on one side, is exactly the signal worth watching over weeks.

### When the equipment is busy

Drag the grip in an exercise's header to move it up or down the session.
Dragging starts from the grip only, so a slow tap on **Log** can never
rearrange things by accident.

For bigger jumps, tap **···** on the exercise:

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

Close the app mid-session and nothing is lost. Reopening shows it at the top
of Home, and a banner on the Train screen, either of which continues where
you left off.

---

## Missed sessions and fixes

Trained without the phone, or logged something wrong? Both are the same
screen.

### Adding a session that already happened

Two ways in: **Train → ··· on a routine → Log a past session**, or
**Logbook → + Past session**, which asks which routine first.

Then it asks when. The **date** is all that is required. Add a **start time**
if you remember it, and an **end time** only after that. A session with no
time recorded says exactly that in the logbook rather than pretending it
began at midnight.

The sets arrive already filled in and already confirmed, because filling in
last Tuesday is transcription rather than logging. Correct the numbers that
are wrong and save.

The numbers come from what you did *before* that date, not from your most
recent session. Entering something from three weeks ago shows you three-week
old numbers, which is the only thing that makes sense.

### Fixing a session already logged

**Logbook → tap a session → the pencil.** It opens exactly like a live
session: change any weight, rep count or RPE, drag exercises into a different
order, add or remove them, edit the note.

Tap the date under the title to change when it happened.

**Save** keeps the changes without restamping the session as happening now.
Anything you added but never confirmed is dropped, same as finishing.

---

## Calendar

A month or a week at a time, showing what was planned against what actually
happened.

The bar across the top: the **calendar icon** jumps to any month or year, the
**left switch** moves between month and week, **Today** returns you to now,
and the **right switch** chooses how the calendar moves.

*Flow* scrolls continuously — down the screen held upright, across it turned
sideways. *Page* shows one period at a time; drag left-to-right or
top-to-bottom to go back, the other way to go forward.

Each day carries up to two dots. **Green** means something was planned,
**lavender** means something was logged. A day where everything planned
actually happened fills green; a planned day gone by without one gets a sand
outline. Today keeps a dark border.

The two marks are separate on purpose: a session done off plan still shows,
so the calendar records what you did rather than only what you were told to.

Tap a day to see what was planned and what happened. A planned day that has
not been done offers **Start** if it is today, or **Log it** if it has
passed, which fills it in backdated with no time of day.

Week numbers run down the left in the international convention, which is why
early January sometimes belongs to the previous year. In week view the first
of a month names itself, since the cells otherwise show bare numbers.

---

## Scheduling

**More → Scheduling.** Place a routine on a date and let it repeat.

**Repeats** — once, weekly on chosen weekdays, or monthly on chosen dates. A
date a month does not have is skipped rather than moved, so the 31st simply
does not happen in February.

**Until** — you pause it, a date, or a number of cycles.

A cycle is the unit throughout. Twelve times with Monday and Friday chosen
means twelve **weeks** and twenty-four sessions, not twelve sessions. The
sheet shows both figures as you set it.

Each entry shows when it next runs, how much is left, and how much you kept
to — something like *Next Wed 11 Sep, 9 of 12 left, 2.5 of 3 kept*.

That last figure divides each cycle's single unit across the days it asked
for, so a week wanting Monday and Friday where only Monday happened counts as
a half. Only cycles that have already come due are judged; weeks still ahead
would otherwise drag the number down while it matters most.

Whether a day was kept is read from what you logged, not recorded separately.
Filling in a missed session later closes the gap by itself.

**Pause** stops a placement producing days without losing its record.
**Cancel** removes the plan; sessions already logged are kept.

Missing a day does nothing. Nothing marks it, nothing chases you. The
schedule says what was planned, the logbook says what happened, and they are
allowed to disagree.

---

## Logbook

Every finished session, newest first, with its date and total volume. The
strip at the bottom shows session count and all-time tonnage.

The filter icon narrows it: a span of dates, a set of routines, or both. With
a filter on, the strip counts the selection rather than everything.

Tap one for the detail: start and finish time, volume, set count, total reps,
heaviest lift, then every exercise and set with its RPE and per-set volume.
The pencil opens it for editing, the bin deletes it, and the rename icon
changes its name.

Renaming changes the label only. The session still counts as the routine it
followed, so it keeps feeding the pre-filled numbers and still appears when
you filter by that routine.

**+ Past session** adds one you did but never recorded.

**All summary figures are in kilograms**, always, whatever unit you typed.
That is what makes them comparable — you cannot add pounds to kilos and get
a meaningful number.

---

## Library

All 1,531 exercises from the Garmin database, searchable by name and
filterable by equipment, muscle, and whether you added it yourself.

The search box says how many it is actually searching — with filters on that
figure drops, and a line underneath shows how many the current search leaves.

**Pin** the ones you use often with the pin icon and they float to the top
everywhere, including when building routines. Pin fifteen and you will rarely
search again.

Tap an exercise for its primary and secondary muscles, its equipment, its
Garmin code, and the heaviest you have ever logged on it.

**+** in the corner adds one of your own. Give it muscles and equipment at
the same time — without them it cannot be reached by any filter and only
exists if you remember its name.

Your own exercises can be changed or removed from that same detail view.
Renaming keeps the underlying identity, so routines follow the new name while
sessions already logged keep the one they were recorded under. Deleting tells
you first how many routines and sessions refer to it.

The same search and filters appear when adding an exercise to a routine or a
session.

---

## Track sessions

**Home → Track session.** A stopwatch for interval running, drawn black with
one very large figure because it is read at arm's length, outdoors, and often
in the dark.

The phone times and nothing else. It does not measure distance and does not
pretend to — the distance is whichever button you press.

**400 m** and **200 m** start the clock on the first tap, and record a rep on
every tap after. The big figure shows the rep you are running; when you
finish one it turns lavender and counts the recovery down instead. Splits
stack above the buttons, newest first.

**Recovery** adjusts in thirty second steps at the bottom. **Skip recovery**
ends it early.

### Cues

You should not have to look at the screen.

- Three short tones at three, two and one second of recovery remaining
- A longer tone at zero, which is the moment the next rep starts
- A short tone when a lap registers, so you know the tap took
- A longer tone when the session starts

The speaker icon mutes them. They play on the alarm channel rather than the
media one, which is what makes them audible outdoors. The vibration happens
whether they are muted or not.

### What it records

Saving writes an ordinary session: one set per rep, each with its time and
distance, so it appears in the logbook and the calendar like anything else.

The screen stays awake while it runs and releases when you leave.

> **Not finished yet.** Distance is stored but not yet shown — a saved track
> session currently reads `0 kg` in the logbook with the distance not
> displayed anywhere. The cues also stop if you switch the screen off, since
> the timer pauses when Android puts the app to sleep. Leave the screen on.

---

## Export and backup

**More → Export** opens a sheet: choose which files, then how much of your
history to cover.

The span can be all time, the last 30 or 90 days, this year, or between two
dates. You can also narrow it to particular routines — sessions logged
without a routine fall outside that, since they belong to none of them.

**Narrowing applies to the spreadsheet only. The backup is written whole or
not at all.** A shortened backup would restore without complaint and leave
gaps with nothing to announce them, which is worse than no backup. You can
skip the backup, but never truncate it.

A narrowed spreadsheet is named `..._selection.csv` so it cannot be mistaken
later for the full record, and the confirmation says how many sets came out
— including when the answer is none.

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

Both land in the folder you choose under **More → Export folder**. Pick it
once and Android remembers — Downloads, a Documents subfolder, wherever you
like. Set it before you rely on exports.

Without one, files go to the app's own directory, which Android hides from
file managers on version 11 and later. They exist, but retrieving them means
a USB cable. The export dialog tells you which happened.

**Restore from backup** reads `.json` files from the same folder, so a backup
copied back from a computer appears in the list.

### Routines on their own

A full backup carries everything and replaces everything on the way back in,
which is too heavy for moving a single routine.

**Train → ⋮ → Export routines** opens a checklist — pick any combination, or
Select all. A single routine can also go out from its own **··· → Export this
routine**. Either way you get one `wlog-routines_<date>.json`.

**Train → ⋮ → Import routines** reads one back. It *adds*: nothing already in
the app is touched, and a clashing name gains `(imported)` rather than
overwriting. Import the same file twice and you get two copies.

That is deliberately unlike **Restore**, which wipes and replaces. Two things
that look similar and must not behave the same.

Custom exercises a routine uses travel inside the file, so a routine never
arrives somewhere pointing at an exercise that does not exist there.

Import only sees files already sitting in your export folder. Getting one
from elsewhere means putting it there first.

---

## Settings

**Show session timer** — off by default, since your watch already times the
session. The start time and a timestamp for every set are recorded either
way, so rest intervals can be reconstructed later even with the timer hidden.

**Installed version** shows which build you are on. **Check for updates**
opens the releases page so you can compare it against the current one. The
app makes no network requests of its own — it hands the link to your browser.

---

## Updating the app

Every build is published at **Releases → Latest**, which opens on a phone and
needs no account. Take the file ending `-arm64-v8a.apk` unless you know your
phone needs another architecture.

Each build carries its own number, so `wlog-1.1.0-b47-arm64-v8a.apk` is build
47 of version 1.1.0. That number rises on its own and is how you tell one
download from another. Every build keeps its own permanent entry under
Releases, so an older one can still be found.

Builds are signed with a fixed key, so a new one installs over the old and
keeps your data. If an install is ever refused, the signing key has changed.
Do not force it — the only way through is to uninstall, and that deletes the
database.

---

## Deliberate omissions

- **Supersets.** No A1/A2 pairing. Log them as separate exercises.
- **Warm-up flags.** Every logged set counts toward volume. Leave warm-ups
  unlogged, or accept them in the total.
- **Reminders.** The schedule shows what is due; nothing notifies you. That
  keeps the app free of any Android permission, which it currently asks for
  none of.

Each was considered and cut. Any of them can be added later.

The rest timer was on this list and is not any more — a routine can now carry
a rest and count it down after each set.
