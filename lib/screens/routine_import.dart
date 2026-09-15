import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../export.dart';
import '../library.dart';
import '../theme.dart';

/// Bring routines in from a file, showing what is in it first.
///
/// Lives on its own rather than inside a screen because two places offer it:
/// the routine list, where you would go to add one, and the import screen,
/// where you would go to bring anything in.
///
/// Returns how many were added, or null if nothing happened.
Future<int?> importRoutinesFlow(BuildContext context) async {
  final files = await Exporter.availableRoutineFiles();
  if (!context.mounted) return null;

  if (files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'No routine files in the export folder. Any file declaring itself '
          'as routines counts, whatever it is named.'),
    ));
    return null;
  }

  // Choosing from a list of one is a wasted tap.
  final ref = files.length == 1
      ? files.first.ref
      : await showModalBottomSheet<String>(
          context: context,
          builder: (c) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s2),
                  child: Text('Which file?'),
                ),
                ...files.map((f) => ListTile(
                      leading: const Icon(Icons.file_open_outlined),
                      title: Text(f.name),
                      onTap: () => Navigator.pop(c, f.ref),
                    )),
              ],
            ),
          ),
        );
  if (ref == null || !context.mounted) return null;

  Map<String, dynamic> data;
  try {
    data = await Exporter.readRoutineFile(ref);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return null;
  }

  final incoming = (data['routines'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  if (incoming.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That file holds no routines.')));
    }
    return null;
  }

  final existing = (await Db.routines()).map((r) => r['name'] as String).toSet();
  final archived =
      (await Db.routines(archived: true)).map((r) => r['name'] as String);
  existing.addAll(archived);

  final chosen = {for (var i = 0; i < incoming.length; i++) i};
  if (!context.mounted) return null;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, 0),
              child: Text(
                  '${incoming.length} routine'
                  '${incoming.length == 1 ? '' : 's'} in this file',
                  style: BvType.headlineSm),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < incoming.length; i++)
                    Builder(builder: (_) {
                      final name = (incoming[i]['name'] as String?) ?? '';
                      final n =
                          (incoming[i]['exercises'] as List? ?? const []).length;
                      final clash = existing.contains(name);
                      return CheckboxListTile(
                        value: chosen.contains(i),
                        title: Text(name),
                        subtitle: Text(
                          // Said before importing rather than after, since
                          // the suffix is otherwise a surprise.
                          clash
                              ? '$n exercises \u00b7 already here, arrives as '
                                  '"$name (imported)"'
                              : '$n exercises',
                          style: BvType.bodySm,
                        ),
                        onChanged: (v) => setSheet(
                            () => v == true ? chosen.add(i) : chosen.remove(i)),
                      );
                    }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Bv.s3),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setSheet(() {
                      if (chosen.length == incoming.length) {
                        chosen.clear();
                      } else {
                        chosen.addAll(
                            [for (var i = 0; i < incoming.length; i++) i]);
                      }
                    }),
                    child: Text(
                        chosen.length == incoming.length ? 'None' : 'All'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        chosen.isEmpty ? null : () => Navigator.pop(c, true),
                    child: Text('Import ${chosen.length}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true || chosen.isEmpty) return null;

  try {
    final n = await Db.importRoutines({
      ...data,
      'routines': [for (final i in chosen) incoming[i]],
    });
    await ExerciseLibrary.load();
    notifyDataChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n routine${n == 1 ? '' : 's'} added.')));
    }
    return n;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
    return null;
  }
}
