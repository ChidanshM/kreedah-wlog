/// Unit conversion, date formatting and small shared helpers.
///
/// Unit rule for this app:
///   * kg is the canonical stored value, kept at full precision.
///   * The screen always shows the unit you actually typed.
///   * Every summary statistic (session volume, set volume, tonnage, PRs)
///     is kg only, and rounds only when displayed.
library;

const double kLbToKg = 0.45359237;
const double kKgToLb = 1 / kLbToKg;

/// Convert an entered weight to canonical kg, at full precision.
///
/// Deliberately not rounded. Rounding here and then multiplying by the rep
/// count multiplies the rounding error too: 17.5 lb kept as 7.94 gives a
/// twelve rep set a volume of 95.28 kg, where converting the whole set at
/// once gives 95.25. Keeping the full value makes those agree, and keeps
/// volume divided by reps equal to the stored weight, which is what makes
/// the figures check out against each other.
double toKg(double value, String unit) =>
    unit == 'lb' ? value * kLbToKg : value;

/// Convert canonical kg back into a display unit, rounded for reading.
///
/// Safe to round here because the value it starts from is exact: 17.5 lb
/// stored precisely comes back as 17.5, not 17.49.
double fromKg(double kg, String unit) {
  final v = unit == 'lb' ? kg * kKgToLb : kg;
  return double.parse(v.toStringAsFixed(2));
}

/// Convert a displayed weight between units, rounding exactly once.
///
/// Going lb -> kg -> lb round-trips through a value already rounded to two
/// decimals, which turns 15 lb into 14.99 lb. Rounding only at the end, and
/// short-circuiting when the units already match, keeps entered numbers
/// intact.
double convertWeight(double value, String from, String to) {
  if (from == to) return double.parse(value.toStringAsFixed(2));
  final kg = from == 'lb' ? value * kLbToKg : value;
  final out = to == 'lb' ? kg * kKgToLb : kg;
  return double.parse(out.toStringAsFixed(2));
}

/// Drop trailing zeros: 20.00 -> "20", 20.41 -> "20.41", 2.50 -> "2.5"
String num2(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// ISO-8601 timestamp including the local UTC offset, e.g.
/// 2026-09-07T18:31:05.123+05:30
String isoLocal(DateTime dt) {
  final local = dt.toLocal();
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes.remainder(60)).toString().padLeft(2, '0');
  return '${local.toIso8601String()}$sign$hh:$mm';
}

DateTime? parseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

/// 2026-09-07
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Mon 7 Sep
String prettyDate(DateTime d) =>
    '${weekdayShort(d)} ${d.day} ${_months[d.month - 1]}';

/// 18:31
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// ISO-8601 week number: weeks start on Monday, and week one is the one
/// holding the first Thursday of the year. That definition is why the first
/// days of January sometimes belong to week 52 or 53 of the year before.
int isoWeekNumber(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstOfYear = DateTime(thursday.year, 1, 1);
  return 1 + thursday.difference(firstOfYear).inDays ~/ 7;
}

/// "today" / "yesterday" / "12d ago"
String agoLabel(DateTime then) {
  final now = DateTime.now();
  final a = DateTime(then.year, then.month, then.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '${days}d ago';
}

String mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Human label for the machine-readable muscle / equipment codes in the
/// Garmin database (ANKLE_WEIGHT -> Ankle weight).
String pretty(String code) {
  if (code.isEmpty) return code;
  final words = code.toLowerCase().split('_');
  final first = words.first;
  final rest = words.skip(1).join(' ');
  final head = first[0].toUpperCase() + first.substring(1);
  return rest.isEmpty ? head : '$head $rest';
}

/// Set types supported by the logger.
class SetType {
  static const reps = 'reps'; // weight x reps
  static const time = 'time'; // duration, optional weight
  static const distance = 'distance'; // steps, optional weight

  static const all = [reps, time, distance];

  static String label(String t) {
    switch (t) {
      case time:
        return 'Time';
      case distance:
        return 'Steps / distance';
      default:
        return 'Reps x weight';
    }
  }
}

/// The library key a stopwatch session is recorded against. A single shared
/// entry rather than one per distance, since the distance lives on each set.
const trackExerciseKey = 'CUSTOM/TRACK_INTERVAL';

const rpeChoices = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0];

/// Renders a prescribed target as one line, or null when nothing is set.
///
/// A missing upper bound means a single value rather than a range, so "8"
/// and "8 to 12" both read naturally without needing a separate flag.
///
/// Weights arrive already in [unit] and are printed as given. A target is
/// stored as it was written rather than converted, so nothing here rounds.
String? targetLabel({
  int? repsMin,
  int? repsMax,
  double? rpeMin,
  double? rpeMax,
  double? weightMin,
  double? weightMax,
  String unit = 'kg',
  String setTypeCode = 'reps',
}) {
  String? span(num? a, num? b, String Function(num) fmt) {
    if (a == null) return null;
    if (b == null || b == a) return fmt(a);
    return '${fmt(a)}\u2013${fmt(b)}';
  }

  final countWord = switch (setTypeCode) {
    'time' => 's',
    'distance' => ' steps',
    _ => ' reps',
  };

  final parts = <String>[];

  final w = span(weightMin, weightMax, (v) => num2(v.toDouble()));
  if (w != null) parts.add('$w $unit');

  final reps = span(repsMin, repsMax, (v) => '${v.toInt()}');
  if (reps != null) parts.add('$reps$countWord');

  final rpe = span(rpeMin, rpeMax, (v) => num2(v.toDouble()));
  if (rpe != null) parts.add('RPE $rpe');

  if (parts.isEmpty) return null;
  return 'Target ${parts.join(', ')}';
}

/// The seventeen muscle codes the exercise data actually uses, ordered head
/// to toe.
///
/// Counted from the data rather than assumed: there is no neck and no middle
/// back, so nothing can ever colour them. The list is the full set, which is
/// also the ceiling on how finely a body map can be drawn — shoulders is one
/// code, not three deltoid heads.
const muscleOrder = <String>[
  'TRAPS',
  'SHOULDERS',
  'CHEST',
  'LATS',
  'LOWER_BACK',
  'BICEPS',
  'TRICEPS',
  'FOREARM',
  'ABS',
  'OBLIQUES',
  'HIPS',
  'GLUTES',
  'ABDUCTORS',
  'ADDUCTORS',
  'QUADS',
  'HAMSTRINGS',
  'CALVES',
];

/// Readable names. The data's own codes are terse and inconsistent in number
/// (FOREARM singular, CALVES plural), so labels are given rather than
/// derived.
const muscleLabels = <String, String>{
  'TRAPS': 'Trapezius',
  'SHOULDERS': 'Shoulders',
  'CHEST': 'Chest',
  'LATS': 'Lats',
  'LOWER_BACK': 'Lower back',
  'BICEPS': 'Biceps',
  'TRICEPS': 'Triceps',
  'FOREARM': 'Forearms',
  'ABS': 'Abs',
  'OBLIQUES': 'Obliques',
  'HIPS': 'Hip flexors',
  'GLUTES': 'Glutes',
  'ABDUCTORS': 'Abductors',
  'ADDUCTORS': 'Adductors',
  'QUADS': 'Quads',
  'HAMSTRINGS': 'Hamstrings',
  'CALVES': 'Calves',
};

String muscleLabel(String code) => muscleLabels[code] ?? pretty(code);

/// Where an unlisted code sorts: after everything known, alphabetically
/// among themselves, so a code added to the data later is never lost.
int muscleRank(String code) {
  final i = muscleOrder.indexOf(code);
  return i == -1 ? muscleOrder.length : i;
}

List<String> sortMuscles(Iterable<String> codes) {
  final list = codes.toList()
    ..sort((a, b) {
      final r = muscleRank(a).compareTo(muscleRank(b));
      return r != 0 ? r : a.compareTo(b);
    });
  return list;
}

/// The part of the body a muscle belongs to.
///
/// A coarser grouping than the muscle codes, because "show me arm work" is a
/// more natural question than "show me biceps or triceps or forearm work".
/// Listed head to toe like the muscles themselves.
class BodyPart {
  static const shoulders = 'Shoulders';
  static const chest = 'Chest';
  static const back = 'Back';
  static const arms = 'Arms';
  static const core = 'Core';
  static const hips = 'Hips and glutes';
  static const legs = 'Legs';

  /// In the order they appear down the body.
  static const all = [shoulders, chest, back, arms, core, hips, legs];

  static const muscles = <String, List<String>>{
    shoulders: ['SHOULDERS', 'TRAPS'],
    chest: ['CHEST'],
    back: ['LATS', 'LOWER_BACK'],
    arms: ['BICEPS', 'TRICEPS', 'FOREARM'],
    core: ['ABS', 'OBLIQUES'],
    hips: ['HIPS', 'GLUTES', 'ABDUCTORS', 'ADDUCTORS'],
    legs: ['QUADS', 'HAMSTRINGS', 'CALVES'],
  };

  /// Trapezius sits with the shoulders and the lower back with the back,
  /// which is arguable either way; both are placed where someone looking for
  /// them would look first.
  static String? forMuscle(String code) {
    for (final e in muscles.entries) {
      if (e.value.contains(code)) return e.key;
    }
    return null;
  }

  /// Every muscle code covered by a set of parts.
  static Set<String> musclesFor(Iterable<String> parts) {
    final out = <String>{};
    for (final p in parts) {
      out.addAll(muscles[p] ?? const []);
    }
    return out;
  }
}

/// The categories you add weights under on the Equipment page. Each one maps
/// to the Garmin equipment codes it can satisfy, so the weight quick-pick
/// chips know which of your weights are relevant to the exercise in front of
/// you.
class EquipKind {
  static const kettlebell = 'Kettlebell';
  static const dumbbell = 'Dumbbell';
  static const barbell = 'Barbell / plates';
  static const machine = 'Machine / cable';
  static const other = 'Other';

  static const all = [kettlebell, dumbbell, barbell, machine, other];

  static const tags = <String, List<String>>{
    kettlebell: ['KETTLEBELL'],
    dumbbell: ['DUMBBELL'],
    barbell: ['BARBELL', 'PLATE', 'EZ_BAR', 'SQUAT_RACK', 'SMITH_MACHINE'],
    machine: ['MACHINE', 'CABLE_MACHINE'],
    other: [],
  };

  /// Which kinds could plausibly supply the load for this exercise.
  static List<String> kindsFor(List<String> equipmentCodes) {
    final out = <String>[];
    for (final entry in tags.entries) {
      if (entry.value.any(equipmentCodes.contains)) out.add(entry.key);
    }
    return out;
  }
}

/// Gear you own that has no weight value attached (bench, pull-up bar, bands).
/// Stored as a comma separated list of Garmin equipment codes in settings.
const gearSettingKey = 'gear';
