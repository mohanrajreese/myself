import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

class FbProgressBar extends StatelessWidget {
  const FbProgressBar({required this.fraction, this.color, super.key});

  /// 0 to 1; values outside are clamped.
  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: fraction.clamp(0, 1).toDouble(),
      minHeight: 6,
      backgroundColor: context.colors.surfaceVariant,
      color: color ?? context.colors.primary,
    ),
  );
}

/// Ring with an optional percentage in the middle. With a null [fraction]
/// only the empty track is drawn.
class FbProgressRing extends StatelessWidget {
  const FbProgressRing({
    required this.fraction,
    required this.semanticLabel,
    this.size = 76,
    super.key,
  });

  final double? fraction;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = fraction?.clamp(0, 1).toDouble();
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(value: value ?? 0, track: c.surfaceVariant, color: c.primary),
          child: value == null
              ? null
              : Center(
                  child: ExcludeSemantics(
                    child: Text(
                      '${(value * 100).round()}%',
                      style: context.text.bodySmall.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, 2 * math.pi, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(arc, -math.pi / 2, 2 * math.pi * value, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.color != color;
}
