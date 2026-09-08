import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';

/// What a session's timestamp can be: a date always, times only if they are
/// remembered. Filling in last Tuesday, you rarely know you started at 18:12.
typedef SessionTime = ({DateTime date, TimeOfDay? start, TimeOfDay? end});

Future<SessionTime?> pickSessionTime(
  BuildContext context, {
  DateTime? date,
  TimeOfDay? start,
  TimeOfDay? end,
  String title = 'When was this?',
}) {
  return showModalBottomSheet<SessionTime>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SessionTimeSheet(
      title: title,
      initialDate: date ?? DateTime.now(),
      initialStart: start,
      initialEnd: end,
    ),
  );
}

class _SessionTimeSheet extends StatefulWidget {
  const _SessionTimeSheet({
    required this.title,
    required this.initialDate,
    this.initialStart,
    this.initialEnd,
  });

  final String title;
  final DateTime initialDate;
  final TimeOfDay? initialStart;
  final TimeOfDay? initialEnd;

  @override
  State<_SessionTimeSheet> createState() => _SessionTimeSheetState();
}

class _SessionTimeSheetState extends State<_SessionTimeSheet> {
  late DateTime _date = widget.initialDate;
  late TimeOfDay? _start = widget.initialStart;
  late TimeOfDay? _end = widget.initialEnd;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Date of the session',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _start : _end) ??
          (isStart ? const TimeOfDay(hour: 18, minute: 0) : _start) ??
          const TimeOfDay(hour: 18, minute: 0),
      helpText: isStart ? 'Start time' : 'End time',
    );
    if (picked == null) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Bv.s4, Bv.s4, Bv.s4, MediaQuery.of(context).viewInsets.bottom + Bv.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: BvType.headlineSm),
          const SizedBox(height: Bv.s1),
          Text(
            'The date is all that is needed. Add times if you remember them.',
            style: BvType.bodySm,
          ),
          const SizedBox(height: Bv.s3),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Date'),
            subtitle: Text('${weekdayName(_date)}, ${prettyDate(_date)}'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Start time'),
            subtitle: Text(_start == null
                ? 'Not recorded'
                : _start!.format(context)),
            trailing: _start == null
                ? const Icon(Icons.add, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() {
                      _start = null;
                      _end = null;
                    }),
                  ),
            onTap: () => _pickTime(isStart: true),
          ),
          // An end time without a start would say nothing, so it only opens
          // once a start exists.
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: _start != null,
            leading: const Icon(Icons.schedule),
            title: const Text('End time'),
            subtitle: Text(_start == null
                ? 'Needs a start time first'
                : _end == null
                    ? 'Not recorded'
                    : _end!.format(context)),
            trailing: _end == null
                ? const Icon(Icons.add, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _end = null),
                  ),
            onTap: _start == null ? null : () => _pickTime(isStart: false),
          ),
          const SizedBox(height: Bv.s3),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(
                    context, (date: _date, start: _start, end: _end)),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Combine the pieces into the timestamps the database stores.
({DateTime start, DateTime? end, bool timeKnown}) resolveSessionTime(
    SessionTime t) {
  final d = t.date;
  if (t.start == null) {
    // Midday rather than midnight, so a date-only session sorts sensibly
    // among sessions that do carry times.
    return (start: DateTime(d.year, d.month, d.day, 12), end: null, timeKnown: false);
  }
  final start =
      DateTime(d.year, d.month, d.day, t.start!.hour, t.start!.minute);
  DateTime? end;
  if (t.end != null) {
    end = DateTime(d.year, d.month, d.day, t.end!.hour, t.end!.minute);
    // A session that ends before it starts ran past midnight.
    if (end.isBefore(start)) end = end.add(const Duration(days: 1));
  }
  return (start: start, end: end, timeKnown: true);
}
