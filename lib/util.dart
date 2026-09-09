/// Unit conversion, date formatting and small shared helpers.
///
/// Unit rule for this app:
///   * kg is the canonical stored value, always rounded to 2 decimals.
///   * The screen always shows the unit you actually typed.
///   * Every summary statistic (session volume, set volume, tonnage, PRs)
///     is kg only.
library;

const double kLbToKg = 0.45359237;
const double kKgToLb = 1 / kLbToKg;

/// Convert an entered weight to canonical kg, rounded to 2 decimals.
double toKg(double value, String unit) {
  final kg = unit == 'lb' ? value * kLbToKg : value;
  return double.parse(kg.toStringAsFixed(2));
}

/// Convert canonical kg back into a display unit (used for quick-pick chips).
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
