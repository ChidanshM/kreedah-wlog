import 'package:flutter/material.dart';

import '../library.dart';
import '../theme.dart';
import '../util.dart';

/// Equipment, muscle and "can I actually do this" filters.
///
/// Shared so the library and the exercise picker offer the same controls
/// rather than drifting into two similar sheets.
typedef ExerciseFilter = ({
  Set<String> equipment,
  Set<String> muscles,
  bool onlyCustom,
});

const ExerciseFilter emptyExerciseFilter = (
  equipment: <String>{},
  muscles: <String>{},
  onlyCustom: false,
);

bool filterIsActive(ExerciseFilter f) =>
    f.equipment.isNotEmpty || f.muscles.isNotEmpty || f.onlyCustom;

Future<ExerciseFilter?> pickExerciseFilter(
  BuildContext context,
  ExerciseFilter current,
) {
  final equipment = {...current.equipment};
  final muscles = {...current.muscles};
  var onlyCustom = current.onlyCustom;

  return showModalBottomSheet<ExerciseFilter>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, scroll) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, 0),
                children: [
                  Text('Narrow the list', style: BvType.headlineSm),
                  const SizedBox(height: Bv.s2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: onlyCustom,
                    title: const Text('Custom exercises'),
                    subtitle: const Text('Only the ones you added yourself'),
                    onChanged: (v) => setSheet(() => onlyCustom = v),
                  ),
                  const Divider(),
                  Text('EQUIPMENT', style: BvType.label),
                  const SizedBox(height: Bv.s2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ExerciseLibrary.equipmentCodes
                        .map((code) => FilterChip(
                              label: Text(pretty(code)),
                              selected: equipment.contains(code),
                              onSelected: (v) => setSheet(() => v
                                  ? equipment.add(code)
                                  : equipment.remove(code)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: Bv.s4),
                  Text('MUSCLE', style: BvType.label),
                  const SizedBox(height: Bv.s2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ExerciseLibrary.muscleCodes
                        .map((code) => FilterChip(
                              label: Text(pretty(code)),
                              selected: muscles.contains(code),
                              onSelected: (v) => setSheet(() => v
                                  ? muscles.add(code)
                                  : muscles.remove(code)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: Bv.s2),
                  Text(
                    'Picking several of one kind widens the list; picking '
                    'across both narrows it.',
                    style: BvType.bodySm,
                  ),
                  const SizedBox(height: Bv.s5),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, Bv.s3),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(() {
                        equipment.clear();
                        muscles.clear();
                        onlyCustom = false;
                      }),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        c,
                        (
                          equipment: equipment,
                          muscles: muscles,
                          onlyCustom: onlyCustom,
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
