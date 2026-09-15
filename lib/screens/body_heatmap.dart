import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';

/// Front and back views with each muscle shaded by how much it was worked.
///
/// The shapes are schematic — recognisable regions in roughly the right
/// places, not anatomy. They are drawn in code against a fixed 100 x 220
/// coordinate space per body and scaled to fit, so replacing them later with
/// a properly drawn asset means swapping [_frontRegions] and [_backRegions]
/// and nothing else.
///
/// Seventeen regions, matching the seventeen muscle codes the exercise data
/// uses. Anything finer would imply a distinction the data cannot fill.
class BodyHeatmap extends StatelessWidget {
  const BodyHeatmap({super.key, required this.counts});

  /// Sets per muscle code over whatever window the caller chose.
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final max = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, box) {
        // Two bodies side by side, each keeping its 100:220 proportion.
        final w = (box.maxWidth - Bv.s4) / 2;
        final h = w * 2.2;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _view(w, h, _frontRegions, 'Front', max),
                const SizedBox(width: Bv.s4),
                _view(w, h, _backRegions, 'Back', max),
              ],
            ),
            const SizedBox(height: Bv.s3),
            _legend(max),
          ],
        );
      },
    );
  }

  Widget _view(double w, double h, Map<String, List<Rect>> regions,
      String label, int max) {
    return Column(
      children: [
        SizedBox(
          width: w,
          height: h,
          child: CustomPaint(
            painter: _BodyPainter(
              regions: regions,
              counts: counts,
              max: max,
            ),
          ),
        ),
        const SizedBox(height: Bv.s1),
        Text(label, style: BvType.label),
      ],
    );
  }

  /// Grey means nothing logged, which is different from a little logged.
  /// Blue to red spans least to most, anchored to your own hardest-worked
  /// muscle rather than to a fixed number, since what counts as a lot depends
  /// entirely on the routine.
  Widget _legend(int max) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _swatch(_colourFor(0, max), 'None'),
        const SizedBox(width: Bv.s3),
        _swatch(_colourFor(1, max == 0 ? 1 : max), 'Least'),
        const SizedBox(width: Bv.s3),
        _swatch(_colourFor(max, max == 0 ? 1 : max), 'Most'),
        if (max > 0) ...[
          const SizedBox(width: Bv.s3),
          Text('$max sets', style: BvType.label),
        ],
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

/// Nothing logged stays grey. Everything else runs blue to red across the
/// range actually present, so the scale always uses its full span.
Color _colourFor(int count, int max) {
  if (count <= 0) return Bv.sand400;
  if (max <= 1) return const Color(0xFFD24B3E);
  final t = ((count - 1) / (max - 1)).clamp(0.0, 1.0);
  return Color.lerp(
    const Color(0xFF3B8BD4),
    const Color(0xFFD24B3E),
    t,
  )!;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.regions,
    required this.counts,
    required this.max,
  });

  final Map<String, List<Rect>> regions;
  final Map<String, int> counts;
  final int max;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 100;
    final sy = size.height / 220;

    final outline = Paint()
      ..color = Bv.sand500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    // Head and neck are drawn but never shaded: no muscle code reaches them.
    final head = Paint()..color = Bv.sand400;
    canvas.drawOval(
      Rect.fromLTWH(38 * sx, 4 * sy, 24 * sx, 26 * sy),
      head,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(44 * sx, 27 * sy, 12 * sx, 8 * sy),
        Radius.circular(3 * sx),
      ),
      head,
    );

    for (final entry in regions.entries) {
      final fill = Paint()
        ..color = _colourFor(counts[entry.key] ?? 0, max)
        ..style = PaintingStyle.fill;

      for (final r in entry.value) {
        final scaled = Rect.fromLTRB(
          r.left * sx,
          r.top * sy,
          r.right * sx,
          r.bottom * sy,
        );
        // Radii proportional to the shape keep a long muscle looking like a
        // band and a compact one looking round, without any shape being a
        // plain rectangle.
        final radius = Radius.elliptical(
          scaled.width * 0.42,
          scaled.height * 0.30,
        );
        final rr = RRect.fromRectAndRadius(scaled, radius);
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, outline);
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.counts != counts || old.max != max || old.regions != regions;
}

/// Each muscle is one or two rects in a 100 x 220 space, mirrored left and
/// right where the muscle is paired. Sides are not tracked separately, so
/// both sides of a pair always take the same colour.
const _frontRegions = <String, List<Rect>>{
  'TRAPS': [
    Rect.fromLTRB(33, 33, 47, 43),
    Rect.fromLTRB(53, 33, 67, 43),
  ],
  'SHOULDERS': [
    Rect.fromLTRB(20, 38, 34, 57),
    Rect.fromLTRB(66, 38, 80, 57),
  ],
  'CHEST': [
    Rect.fromLTRB(35, 43, 49, 64),
    Rect.fromLTRB(51, 43, 65, 64),
  ],
  'BICEPS': [
    Rect.fromLTRB(20, 59, 32, 84),
    Rect.fromLTRB(68, 59, 80, 84),
  ],
  'FOREARM': [
    Rect.fromLTRB(16, 86, 29, 114),
    Rect.fromLTRB(71, 86, 84, 114),
  ],
  'ABS': [
    Rect.fromLTRB(41, 66, 59, 106),
  ],
  'OBLIQUES': [
    Rect.fromLTRB(33, 68, 40, 102),
    Rect.fromLTRB(60, 68, 67, 102),
  ],
  'HIPS': [
    Rect.fromLTRB(35, 108, 48, 120),
    Rect.fromLTRB(52, 108, 65, 120),
  ],
  'ABDUCTORS': [
    Rect.fromLTRB(27, 110, 35, 138),
    Rect.fromLTRB(65, 110, 73, 138),
  ],
  'QUADS': [
    Rect.fromLTRB(34, 122, 47, 164),
    Rect.fromLTRB(53, 122, 66, 164),
  ],
  'ADDUCTORS': [
    Rect.fromLTRB(44, 122, 49, 152),
    Rect.fromLTRB(51, 122, 56, 152),
  ],
  'CALVES': [
    Rect.fromLTRB(35, 172, 46, 206),
    Rect.fromLTRB(54, 172, 65, 206),
  ],
};

const _backRegions = <String, List<Rect>>{
  'TRAPS': [
    Rect.fromLTRB(36, 32, 64, 64),
  ],
  'SHOULDERS': [
    Rect.fromLTRB(20, 38, 34, 57),
    Rect.fromLTRB(66, 38, 80, 57),
  ],
  'LATS': [
    Rect.fromLTRB(30, 58, 47, 94),
    Rect.fromLTRB(53, 58, 70, 94),
  ],
  'TRICEPS': [
    Rect.fromLTRB(19, 59, 31, 84),
    Rect.fromLTRB(69, 59, 81, 84),
  ],
  'FOREARM': [
    Rect.fromLTRB(16, 86, 29, 114),
    Rect.fromLTRB(71, 86, 84, 114),
  ],
  'LOWER_BACK': [
    Rect.fromLTRB(40, 96, 60, 112),
  ],
  'GLUTES': [
    Rect.fromLTRB(33, 114, 49, 136),
    Rect.fromLTRB(51, 114, 67, 136),
  ],
  'HAMSTRINGS': [
    Rect.fromLTRB(34, 138, 47, 168),
    Rect.fromLTRB(53, 138, 66, 168),
  ],
  'CALVES': [
    Rect.fromLTRB(35, 172, 46, 206),
    Rect.fromLTRB(54, 172, 65, 206),
  ],
};
