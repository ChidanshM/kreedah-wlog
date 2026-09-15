import 'package:flutter/material.dart';
import 'package:muscle_mapper/muscle_mapper.dart';

import '../theme.dart';

/// Front and back views with each muscle shaded by how much it was worked.
///
/// This branch draws them with the muscle_mapper package, which ships the
/// anatomical drawings and does its own hit testing. Colour and intensity are
/// still this app's: the package takes a colour and an opacity per muscle
/// rather than imposing a scale.
class BodyHeatmap extends StatelessWidget {
  const BodyHeatmap({super.key, required this.counts, this.onMuscleTapped});

  /// Sets per muscle code over whatever window the caller chose.
  final Map<String, int> counts;

  /// Called with one of this app's muscle codes, not the package's.
  final void Function(String muscleCode)? onMuscleTapped;

  /// This app records against seventeen codes; the package draws thirty-five
  /// sub-muscles grouped into twenty. Mapping is to the group, since a set is
  /// never recorded against one head of a muscle.
  ///
  /// Two have no home. Hip flexors are drawn here as the groin group, which
  /// is where they sit anatomically whatever the name suggests. Abductors
  /// have nothing: the muscle that does the work is inside the glutes group,
  /// so counting it there would overstate glute work.
  static const _groups = <String, MuscleGroup>{
    'TRAPS': MuscleGroup.traps,
    'SHOULDERS': MuscleGroup.deltoids,
    'CHEST': MuscleGroup.chest,
    'LATS': MuscleGroup.lats,
    'LOWER_BACK': MuscleGroup.lowerBack,
    'BICEPS': MuscleGroup.biceps,
    'TRICEPS': MuscleGroup.triceps,
    'FOREARM': MuscleGroup.forearms,
    'ABS': MuscleGroup.abs,
    'OBLIQUES': MuscleGroup.obliques,
    'HIPS': MuscleGroup.groin,
    'GLUTES': MuscleGroup.glutes,
    'ADDUCTORS': MuscleGroup.innerThigh,
    'QUADS': MuscleGroup.quads,
    'HAMSTRINGS': MuscleGroup.hamstrings,
    'CALVES': MuscleGroup.calves,
  };

  /// The reverse, for turning a tap back into something this app knows.
  static String? _codeFor(Muscle m) {
    final group = m.group;
    for (final e in _groups.entries) {
      if (e.value == group) return e.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final max = counts.values.fold<int>(0, (a, b) => a > b ? a : b);

    final active = <Muscle>{};
    final colours = <Muscle, Color>{};
    final intensities = <Muscle, double>{};

    counts.forEach((code, count) {
      final group = _groups[code];
      if (group == null || count <= 0) return;
      final colour = _colourFor(count, max);
      // Opacity carries the same information as hue here. Kept near the top
      // of its range so a lightly worked muscle is still clearly coloured
      // rather than washed out against the base drawing.
      final t = max <= 1 ? 1.0 : (count - 1) / (max - 1);
      for (final m in group.subMuscles) {
        active.add(m);
        colours[m] = colour;
        intensities[m] = 0.55 + 0.45 * t;
      }
    });

    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Bv.s4) / 2;
        final h = w * 2.2;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _view(w, h, AnatomyView.front, 'Front', active, colours,
                    intensities),
                const SizedBox(width: Bv.s4),
                _view(w, h, AnatomyView.back, 'Back', active, colours,
                    intensities),
              ],
            ),
            const SizedBox(height: Bv.s3),
            _legend(max),
          ],
        );
      },
    );
  }

  Widget _view(
    double w,
    double h,
    AnatomyView view,
    String label,
    Set<Muscle> active,
    Map<Muscle, Color> colours,
    Map<Muscle, double> intensities,
  ) {
    return Column(
      children: [
        SizedBox(
          width: w,
          height: h,
          child: MuscleMapper(
            gender: AnatomyGender.male,
            view: view,
            assetProvider:
                const DefaultAnatomyProvider(style: AnatomyStyle.minimal),
            activeMuscles: active,
            muscleColors: colours,
            muscleIntensities: intensities,
            baseColor: Bv.sand400,
            onMuscleTapped: onMuscleTapped == null
                ? null
                : (m) {
                    final code = _codeFor(m);
                    if (code != null) onMuscleTapped!(code);
                  },
          ),
        ),
        const SizedBox(height: Bv.s1),
        Text(label, style: BvType.label),
      ],
    );
  }

  /// With nothing logged there is no scale to describe, so the legend says
  /// that rather than inventing endpoints: at a maximum of zero the least and
  /// the most are the same figure, and colouring them anyway put red under
  /// "least" and grey under "most".
  Widget _legend(int max) {
    if (max == 0) {
      return Text('Nothing logged in this span', style: BvType.label);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _swatch(Bv.sand400, 'None'),
        const SizedBox(width: Bv.s3),
        _swatch(_colourFor(1, max), max == 1 ? 'Worked' : 'Least'),
        if (max > 1) ...[
          const SizedBox(width: Bv.s3),
          _swatch(_colourFor(max, max), 'Most'),
        ],
        const SizedBox(width: Bv.s3),
        Text('$max sets', style: BvType.label),
      ],
    );
  }

  Widget _swatch(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: BvType.label),
        ],
      );
}

/// Yellow through orange to red across the range actually present, so the
/// scale always uses its full span. Nothing logged is left to the base
/// drawing rather than given a colour of its own.
Color _colourFor(int count, int max) {
  if (count <= 0) return Bv.sand400;
  if (max <= 1) return const Color(0xFFD7342A);

  const low = Color(0xFFF7D154);
  const mid = Color(0xFFE88A1F);
  const high = Color(0xFFD7342A);

  final t = ((count - 1) / (max - 1)).clamp(0.0, 1.0);
  return t < 0.5
      ? Color.lerp(low, mid, t * 2)!
      : Color.lerp(mid, high, (t - 0.5) * 2)!;
}
