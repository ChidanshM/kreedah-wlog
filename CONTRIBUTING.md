# Contributing to Krīḍā · Wlog

> Sub-app of the **Krīḍā** platform. Active development, Phase 0a — the app builds and installs but is not yet a settled daily driver. Expect churn in the UI layer.

## Status

Active phase: 0a — local build, sideloaded.

The app works end to end: routines, pre-filled set logging, unilateral sets, RPE, equipment-driven weight chips, a 1,531-exercise library, CSV and JSON export. Phase 0b is blocked on a persistent signing key; until that lands, updates can force an uninstall and take the database with them.

## Before contributing

Read in order:

1. [`../kreedah/CONTRIBUTING.md`](https://github.com/<owner>/kreedah/blob/main/CONTRIBUTING.md) — platform-wide contribution flow: per-repo git identity, commit format via `kc`, license.
2. The 10 platform principles, in the umbrella `kreedah` repo.
3. This file, for the sub-app principles that matter most in review.

Sub-app skill files are maintained locally and not published here, so this document carries what a contributor needs.

## Setup

```bash
git clone https://github.com/<owner>/kreedah-wlog
cd kreedah-wlog

# Per-repo git identity (never --global):
git config user.name  "Your Name"
git config user.email "you@example.com"

flutter pub get
flutter analyze
```

Building an APK requires generating the platform folder first — `android/` is not committed. See [`README.md`](./README.md) for the exact sequence, or just push and let CI build it.

## Committing

Never `git commit` directly. Use the helper:

```bash
git add -A
./scripts/kc.sh <major_type> "<explanation>"
```

Allowed `major_type`: `feat`, `fix`, `refactor`, `docs`, `pitfall`, `phase`, `chore`. The helper builds the 3-message format and auto-increments the checkpoint number.

## Sub-app rules that get enforced in review

- **Kilograms are canonical, stored to 2 decimals.** The entered unit and value are preserved alongside. Every summary statistic is kg only — never mix units in an aggregate.
- **Convert weights exactly once.** Use `convertWeight` from the original entry. Never round-trip through the stored kg value; that is what turned 15 lb into 14.99 lb.
- **No network calls.** The app is offline by design and the release manifest requests no Android permissions. A PR adding a dependency that opens a socket needs a very good argument.
- **Never mutate a list returned straight from `sqflite`.** Results are read-only and `removeAt` throws — silently, inside a reorder callback. Copy first.
- **Never pass unvalidated keys as column names.** They land in the SQL text rather than a bound parameter. Filter against `PRAGMA table_info`.
- **Garmin exercise codes travel end to end.** `CATEGORY_GARMIN` and `NAME_GARMIN` reach the CSV even though nothing reads them yet; they are the precondition for `.fit` export.
- **Carried-over values must look different from confirmed ones.** A number that has not happened yet must never render like one that has.
- **Restyling preserves affordances.** A visual pass once replaced a tappable checkbox with a static icon and removed the only way to unlog a set.
- **Playfair Display never sets a number.** Headings only; Inter with tabular figures for all data.

## Dependencies

Currently `sqflite`, `path`, `path_provider`. Kept deliberately small — every package is another way for a build to fail on a machine nobody can inspect. New dependencies need a reason beyond convenience, and PRs adding one should say what was considered instead.

## Testing

No automated tests yet. CI runs `flutter analyze` before building, which is the only gate. The first tests worth writing cover unit conversion and autofill selection — the two places a silent wrong answer is both plausible and consequential.

## License of contributions

By submitting a PR, you license your contribution under [PolyForm Noncommercial 1.0.0](./LICENSE), matching the platform license.
