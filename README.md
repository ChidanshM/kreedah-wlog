# Workout Log

A single-user Android strength log. Routines are laid out in advance, and
each set records weight, reps, RPE and side. Data lives in a local SQLite
file and exports to CSV.

## Getting the APK

### Option A — GitHub Actions (no Android Studio needed)

1. Create a new GitHub repo and push this folder to the `main` branch.
2. Go to the **Actions** tab. The **Build APK** workflow runs automatically.
3. When it finishes, open the run and download the `workout-log-apk`
   artifact. Unzip it and copy `app-release.apk` to your phone.
4. Open the file on the phone and allow installation from unknown sources
   when prompted.

The APK is signed with the standard debug key, which is fine for installing
on your own device. It is not suitable for the Play Store.

### Option B — local build

```bash
flutter create --org com.chidansh --project-name workout_log --platforms=android /tmp/app
rm -rf /tmp/app/lib /tmp/app/test
cp -r lib assets pubspec.yaml /tmp/app/
cd /tmp/app
flutter pub get
flutter build apk --release
```

The `android/` folder is generated rather than checked in, so it always
matches your installed Flutter version instead of fighting it.

## How it behaves

**Routines.** Unlimited. One per training day is the intended shape. Each
exercise in a routine carries its own set type, default unit, unilateral
flag and target set count.

**Autofill.** Opening a session pre-fills every set from the last time you
trained *that exercise in that routine* — set 1 from last set 1, set 2 from
set 2, extra sets from the last one that existed. If the exercise has never
appeared in that routine, it falls back to the last time you did it
anywhere and says so. Values arrive editable, not as placeholders; tap the
circle to confirm a set as-is, or tap the row to change the numbers.

**Units.** kg is the canonical stored value, rounded to 2 decimals. The
screen always shows the unit you typed. Every summary figure — set volume,
session volume, all-time tonnage, heaviest lift — is kg only. The CSV has a
`weight_kg` column on every row and a `weight_lb` column filled in only for
sets actually entered in lb.

**Set types.** Reps × weight, time in seconds, or steps. Carries and planks
get logged properly rather than being forced into a reps field.

**Unilateral.** Flagged exercises split each set into right then left, in
that order, sharing one RPE. Both sides count toward volume.

**Equipment.** The Equipment page holds the weights you own, added
individually or as a range (`5` up to `30` step `2.5` adds the whole rack).
Those become one-tap chips in the set editor, filtered to the kind of
equipment the current exercise uses — kettlebell weights for kettlebell
work, dumbbells for dumbbell work. The gear toggles feed the "only what I
can do" filter in the exercise picker.

**Library.** All 1531 exercises from the Garmin database, searchable and
filterable by equipment and muscle. Pin the ones you use often and they
float to the top. Custom exercises can be added by hand. Garmin's own
category and exercise codes travel through to the CSV, so the data can be
matched up with Garmin Connect later.

**Timing.** The session start timestamp is always recorded, and every
confirmed set carries its own timestamp, so rest intervals and session
length can be reconstructed afterwards. The visible running timer is off by
default and lives in Settings.

## Export

Settings → Export writes two files:

- `workout_sets_<date>.csv` — one row per confirmed set, long format, every
  workout-level field repeated on each row so it pivots cleanly.
- `backup_<date>.json` — a full database dump that Restore reads back.

Both land in `Android/data/com.chidansh.workout_log/files/exports`, which
any file manager can open without granting storage permissions. Restore
lists the `.json` files it finds in that same folder, so a backup copied
back from a computer shows up there.

### CSV columns

```
workout_id, workout_start, workout_date, weekday, routine_name, routine_id,
workout_notes, exercise_order, exercise_name, garmin_category, garmin_name,
equipment, primary_muscles, exercise_notes, set_number, set_type, side,
entry_unit, weight_entered, weight_lb, weight_kg, reps, duration_sec,
distance_steps, rpe, set_volume_kg, set_timestamp
```

`workout_start` and `set_timestamp` are ISO-8601 with the local UTC offset.

## Layout

```
lib/
  main.dart        app entry, theme, bottom navigation
  db.dart          SQLite schema and every query
  library.dart     exercise catalogue, search and filtering
  util.dart        unit conversion, dates, equipment mapping
  export.dart      CSV and JSON export, restore
  screens/         one file per screen
assets/
  exercises.json   1531 exercises with muscle and equipment tags
```

## Visual design

The app follows the Botanical Vitality system: Deep Forest as the primary
action colour, Sage as the success and confirmed-set state, Soft Lavender
reserved for RPE (a subjective number, so it is category-coded away from
the measured ones), on Cream and Sand surfaces. Cards are 24px radius with
a hairline tan border; buttons and inputs are 8px. Depth comes from tonal
layering rather than shadow.

Two deliberate departures from the brand document, both about this being a
tool used mid-set rather than a page being read:

- **Density inside the set table** is tighter than the brand's airy 24px
  gutter, down to 8-12px. Everywhere else keeps the specified spacing.
- **Playfair Display never touches a number.** It sets exercise names and
  screen titles only. All numerals are Inter with tabular figures so the
  weight column lines up across sets. The brand document already routes
  data to Inter, so this follows it rather than breaking it.

Typefaces are not bundled — see FONTS.md.

## Not included, deliberately

Supersets, warm-up set flags and a rest timer were all considered and cut.
Adding any of them later means one column and one widget, not a rewrite.
