import 'package:flutter/material.dart';

import '../body_shapes.dart';
import '../theme.dart';

/// Front and back views with each muscle shaded by how much it was worked.
///
/// The outlines come from [frontShapes] and [backShapes]; everything here is
/// scaling, colour and the figures. Regions the exercise data has no code for
/// — head, neck, knees, ankles — are drawn and never shaded, so the figure
/// reads as a body rather than as floating muscles.
class BodyHeatmap extends StatelessWidget {
  const BodyHeatmap({super.key, required this.counts});

  /// Sets per muscle code over whatever window the caller chose.
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final max = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Bv.s4) / 2;
        final h = w * 2.2;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _view(w, h, frontShapes, 'Front', max),
                const SizedBox(width: Bv.s4),
                _view(w, h, backShapes, 'Back', max),
              ],
            ),
            const SizedBox(height: Bv.s3),
            _legend(max),
          ],
        );
      },
    );
  }

  Widget _view(double w, double h, List<BodyShape> shapes, String label,
      int max) {
    return Column(
      children: [
        SizedBox(
          width: w,
          height: h,
          child: CustomPaint(
            painter: _BodyPainter(
              shapes: shapes,
              counts: counts,
              max: max,
              textScale: w / 100,
            ),
          ),
        ),
        const SizedBox(height: Bv.s1),
        Text(label, style: BvType.label),
      ],
    );
  }

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

/// Nothing logged stays grey. Everything else runs yellow through orange to
/// red across the range actually present, so the scale always uses its full
/// span.
///
/// A single hue would only vary in lightness, which the eye reads as depth
/// rather than as quantity. Yellow to red is the ramp used for heat and for
/// height, and it reads in one direction without needing the legend.
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

/// "x y x y ..." to a closed path, scaled into the canvas.
Path _pathFrom(String points, double sx, double sy) {
  final n = points.trim().split(RegExp(r'\s+'));
  final path = Path();
  for (var i = 0; i + 1 < n.length; i += 2) {
    final x = double.parse(n[i]) * sx;
    final y = double.parse(n[i + 1]) * sy;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.shapes,
    required this.counts,
    required this.max,
    required this.textScale,
  });

  final List<BodyShape> shapes;
  final Map<String, int> counts;
  final int max;

  /// Figures scale with the drawing, but stop shrinking below legibility.
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 100;
    final sy = size.height / 220;

    final outline = Paint()
      ..color = Bv.sand500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Where each muscle's figure goes: the largest polygon on each side of
    // the body. A paired muscle gets one figure per side; a single one gets
    // one. Drawing on every polygon would put six numbers across the quads.
    final labelSpots = <String, Map<bool, Rect>>{};

    for (final shape in shapes) {
      final count = shape.muscle == null ? 0 : (counts[shape.muscle] ?? 0);
      final fill = Paint()
        ..color = shape.muscle == null ? Bv.sand400 : _colourFor(count, max)
        ..style = PaintingStyle.fill;

      for (final poly in shape.polygons) {
        final path = _pathFrom(poly, sx, sy);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, outline);

        if (shape.muscle == null || count <= 0) continue;
        final b = path.getBounds();
        final leftSide = b.center.dx < size.width / 2;
        final best = labelSpots[shape.muscle!]?[leftSide];
        if (best == null || b.width * b.height > best.width * best.height) {
          (labelSpots[shape.muscle!] ??= {})[leftSide] = b;
        }
      }
    }

    // Drawn after every shape, so a neighbouring polygon cannot cover a
    // figure that was painted before it.
    labelSpots.forEach((muscle, sides) {
      final count = counts[muscle] ?? 0;
      for (final b in sides.values) {
        _drawCount(canvas, b, count);
      }
    });
  }

  void _drawCount(Canvas canvas, Rect box, int count) {
    final size = (9.0 * textScale).clamp(9.0, 13.0);
    if (box.width < size * 1.4 || box.height < size * 1.2) return;

    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w600,
          // Dark throughout: the ramp runs yellow to red, so a light figure
          // would disappear at the yellow end.
          color: const Color(0xFF3A2A08),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(box.center.dx - tp.width / 2, box.center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.counts != counts ||
      old.max != max ||
      old.shapes != shapes ||
      old.textScale != textScale;
}
