# kreedah-wlog

Krīḍā · Wlog — an offline Android app for logging strength training. Part of the Krīḍā platform.

Part of the **Krīḍā** (क्रीडा, "play, sport") platform.

## What it does

Routines are laid out in advance, then each set records weight, reps, RPE and side. Opening a session pre-fills every set from the last time you trained it, so a typical set is one tap. Data lives in a local SQLite file and exports to CSV.

This is the first Krīḍā sub-app that ships as a mobile binary rather than a web service, and the first written in Dart. That stack choice overrides the platform TypeScript/Python default; the reasoning is recorded in the sub-app skill files.

## Getting the APK

### Download a build

**[Latest build](../../releases/latest)** — always the newest commit on `main`. Take `wlog-<version>-arm64-v8a.apk` unless you know your phone needs another architecture, then open it and allow installation from an unknown source when prompted.

That link works from a phone and needs no GitHub account. Tagged releases under [Releases](../../releases) are permanent; the `latest` one is replaced on every build.

Builds are signed with a fixed project key, so a new one installs over the previous version and keeps your data. If an install is ever refused, the key has changed — see [`docs/SIGNING-SETUP.md`](./docs/SIGNING-SETUP.md). The same files are attached to each workflow run as an artifact, but those need a login and expire after 90 days, so the release is the better link.

### Local build

```bash
flutter create --org com.chidansh --project-name workout_log --platforms=android /tmp/app
rm -rf /tmp/app/lib /tmp/app/test
cp -r lib assets docs pubspec.yaml /tmp/app/
cd /tmp/app
flutter pub get
flutter build apk --release --split-per-abi
```

`android/` is generated rather than committed, so it always matches the installed Flutter version instead of fighting it.

## How it behaves

**Routines.** Unlimited, one per training day. Each exercise carries its own set type, default unit, unilateral flag and target set count.

**Autofill.** Sets pre-fill from the last time you trained that exercise *in that routine* — set 1 from last set 1, and so on. With no history in that routine it falls back to the last time you did the exercise anywhere and says so. Carried-over numbers render lighter than confirmed ones so the two are never confused.

**Units.** Kilograms are canonical, stored to 2 decimals. The screen keeps whatever unit you typed. Every summary figure is kg only. Conversion rounds exactly once, so 15 lb stays 15 lb.

**Set types.** Reps × weight, time in seconds, or steps — so carries and planks are logged properly rather than forced into a reps field.

**Unilateral.** Flagged exercises split each set into right then left, sharing one RPE. Both sides count toward volume.

**Equipment.** Weights you own, added individually or as a range, become one-tap chips in the set editor, filtered to the equipment the current exercise actually uses.

**Library.** All 1,531 exercises from the Garmin database, searchable and filterable by equipment and muscle, pinnable. Garmin's category and exercise codes travel through to the CSV.

## Export

Settings → Export writes a long-format CSV (one row per confirmed set) and a JSON backup that Restore reads back.

```
workout_id, workout_start, workout_date, weekday, routine_name, routine_id,
workout_notes, exercise_order, exercise_name, garmin_category, garmin_name,
equipment, primary_muscles, exercise_notes, set_number, set_type, side,
entry_unit, weight_entered, weight_lb, weight_kg, reps, duration_sec,
distance_steps, rpe, set_volume_kg, set_timestamp
```

`weight_lb` is populated only for sets actually entered in lb. Timestamps are ISO-8601 with the local UTC offset.

**Known limitation:** exports currently land in `Android/data/…`, which scoped storage makes unreachable from file managers on Android 11+. Being fixed.

## Layout

```
lib/
  main.dart        app entry, theme, bottom navigation
  db.dart          SQLite schema and every query
  library.dart     exercise catalogue, search and filtering
  theme.dart       Botanical Vitality tokens and Flutter theme
  util.dart        unit conversion, dates, equipment mapping
  export.dart      CSV and JSON export, restore
  screens/         one file per screen
assets/
  exercises.json   1531 exercises with muscle and equipment tags
```

Typefaces are not bundled — see [`FONTS.md`](./FONTS.md).

## Architecture and conventions

Sub-app skill files (`SKILL-core.md` and `SKILL-state.md`) are maintained locally and deliberately not published to this repo. See the umbrella `kreedah` repo for platform-wide conventions: the 10 platform principles, the 3-message commit format, naming, and licensing.

Commits go through `./scripts/kc.sh`, never `git commit` directly.

## License

PolyForm Noncommercial 1.0.0 — see [`LICENSE`](./LICENSE). Free for personal, educational, research, and non-commercial use; commercial use requires a separate license.
