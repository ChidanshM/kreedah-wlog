import 'package:flutter/material.dart';

import '../db.dart';
import '../theme.dart';
import '../util.dart';

/// What to export, and over what span.
///
/// Filters apply to the spreadsheet only. The backup is always complete: a
/// partial backup would restore silently and leave you missing sessions with
/// nothing to say so, which is worse than no backup at all.
typedef ExportOptions = ({
  bool csv,
  bool backup,
  DateTime? from,
  DateTime? to,
  List<int>? routineIds,
});

Future<ExportOptions?> pickExportOptions(BuildContext context) {
  return showModalBottomSheet<ExportOptions>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ExportSheet(),
  );
}

enum _Span { all, days30, days90, year, custom }

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _csv = true;
  bool _backup = true;
  _Span _span = _Span.all;
  DateTime? _from;
  DateTime? _to;

  bool _allRoutines = true;
  List<Map<String, dynamic>> _routines = const [];
  final _chosen = <int>{};

  @override
  void initState() {
    super.initState();
    Db.routines().then((r) {
      if (mounted) setState(() => _routines = r);
    });
  }

  ({DateTime? from, DateTime? to}) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_span) {
      case _Span.all:
        return (from: null, to: null);
      case _Span.days30:
        return (from: today.subtract(const Duration(days: 30)), to: null);
      case _Span.days90:
        return (from: today.subtract(const Duration(days: 90)), to: null);
      case _Span.year:
        return (from: DateTime(now.year), to: null);
      case _Span.custom:
        return (
          from: _from,
          // Inclusive of the end date, so the boundary is the following day.
          to: _to == null
              ? null
              : DateTime(_to!.year, _to!.month, _to!.day + 1),
        );
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _span != _Span.all || !_allRoutines;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          Bv.s4, Bv.s4, Bv.s4, MediaQuery.of(context).viewInsets.bottom + Bv.s4),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export', style: BvType.headlineSm),
            const SizedBox(height: Bv.s3),

            Text('FILES', style: BvType.label),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _csv,
              onChanged: (v) => setState(() => _csv = v),
              title: const Text('Spreadsheet'),
              subtitle: const Text('One row per set, for analysis'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _backup,
              onChanged: (v) => setState(() => _backup = v),
              title: const Text('Backup'),
              subtitle: const Text('Everything, for restoring. Never filtered.'),
            ),

            const Divider(height: Bv.s5),
            Text('SPREADSHEET COVERS', style: BvType.label),
            const SizedBox(height: Bv.s2),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                (_Span.all, 'All time'),
                (_Span.days30, 'Last 30 days'),
                (_Span.days90, 'Last 90 days'),
                (_Span.year, 'This year'),
                (_Span.custom, 'Between dates'),
              ]
                  .map((o) => ChoiceChip(
                        label: Text(o.$2),
                        selected: _span == o.$1,
                        onSelected: _csv ? (_) => setState(() => _span = o.$1) : null,
                      ))
                  .toList(),
            ),
            if (_span == _Span.custom) ...[
              const SizedBox(height: Bv.s2),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isFrom: true),
                      child: Text(_from == null ? 'From' : prettyDate(_from!)),
                    ),
                  ),
                  const SizedBox(width: Bv.s2),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isFrom: false),
                      child: Text(_to == null ? 'To' : prettyDate(_to!)),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: Bv.s3),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allRoutines,
              onChanged: _csv ? (v) => setState(() => _allRoutines = v) : null,
              title: const Text('All routines'),
              subtitle: const Text('Off to pick which ones'),
            ),
            if (!_allRoutines)
              ..._routines.map((r) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _chosen.contains(r['id'] as int),
                    title: Text(r['name'] as String),
                    onChanged: (v) => setState(() => v == true
                        ? _chosen.add(r['id'] as int)
                        : _chosen.remove(r['id'] as int)),
                  )),
            if (!_allRoutines)
              Padding(
                padding: const EdgeInsets.only(top: Bv.s1),
                child: Text(
                  'Sessions logged without a routine are left out when you '
                  'pick specific ones.',
                  style: BvType.bodySm,
                ),
              ),

            const SizedBox(height: Bv.s4),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: (!_csv && !_backup)
                      ? null
                      : () {
                          final r = _range();
                          Navigator.pop(context, (
                            csv: _csv,
                            backup: _backup,
                            from: _csv ? r.from : null,
                            to: _csv ? r.to : null,
                            routineIds: _csv && !_allRoutines
                                ? _chosen.toList()
                                : null,
                          ));
                        },
                  child: Text(filtered ? 'Export selection' : 'Export'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
