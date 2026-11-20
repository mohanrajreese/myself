import 'package:material_ui/material_ui.dart';

import 'l10n.dart';
import 'tokens.dart';

/// Praxis mark: a geometric 'P' habit loop on a rounded squircle.
typedef FbLogo = PraxisLogo;

class PraxisLogo extends StatelessWidget {
  const PraxisLogo({this.size = 72, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.appName,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LogoPainter(background: context.colors.primary, line: context.colors.onPrimary),
      ),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.background, required this.line});
  final Color background;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 72;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(20 * s)),
      Paint()..color = background,
    );

    final strokePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Stem of 'P'
    final stem = Path()
      ..moveTo(24 * s, 18 * s)
      ..lineTo(24 * s, 54 * s);
    canvas.drawPath(stem, strokePaint);

    // Dynamic habit loop of 'P'
    final loop = Path()
      ..moveTo(24 * s, 18 * s)
      ..cubicTo(40 * s, 17 * s, 48 * s, 21 * s, 48 * s, 28 * s)
      ..cubicTo(48 * s, 35 * s, 40 * s, 38 * s, 24 * s, 38 * s);
    canvas.drawPath(loop, strokePaint);

    // Accent focus dot inside loop (representing daily core / intention)
    final dotPaint = Paint()
      ..color = line
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(35 * s, 28 * s), 2.5 * s, dotPaint);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.background != background || old.line != line;
}

/// One step of a multi-step flow: back, progress, title, scrolling body and
/// a primary button pinned to the bottom.
class FbStepScaffold extends StatelessWidget {
  const FbStepScaffold({
    required this.current,
    required this.total,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.busy = false,
    this.notice,
    super.key,
  });

  final int current;
  final int total;
  final String title;
  final String subtitle;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final bool busy;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(FbSpace.sm, FbSpace.sm, FbSpace.xxl, 0),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: FbSize.touch,
                    child: onBack == null
                        ? null
                        : IconButton(
                            onPressed: onBack,
                            tooltip: l10n.back,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                  ),
                  const SizedBox(width: FbSpace.sm),
                  Expanded(
                    child: Semantics(
                      label: l10n.stepSemantics(current, total),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: current / total,
                          minHeight: 6,
                          backgroundColor: c.outline,
                          color: c.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: FbSpace.md),
                  ExcludeSemantics(
                    child: Text(l10n.stepOf(current, total), style: context.text.label),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  FbSpace.xxl,
                  FbSpace.lg,
                  FbSpace.xxl,
                  FbSpace.xxl,
                ),
                children: [
                  Semantics(header: true, child: Text(title, style: context.text.headline)),
                  const SizedBox(height: FbSpace.sm),
                  Text(subtitle, style: context.text.bodySmall),
                  const SizedBox(height: FbSpace.xl),
                  child,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(FbSpace.xxl, 0, FbSpace.xxl, FbSpace.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null) ...[notice!, const SizedBox(height: FbSpace.md)],
                  FbPrimaryButton(label: primaryLabel, onPressed: onPrimary, busy: busy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width main action. Shows a spinner and ignores taps while [busy].
class FbPrimaryButton extends StatelessWidget {
  const FbPrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? SizedBox.square(
            dimension: FbSpace.xxl,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: context.colors.textDisabled,
              semanticsLabel: context.l10n.loading,
            ),
          )
        : Text(label),
  );
}

/// Lays two fields side by side when there is room, otherwise stacks them
/// (small screens and large text sizes).
class FbFieldPair extends StatelessWidget {
  const FbFieldPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth < 300 || scale > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            const SizedBox(height: FbSpace.lg),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: FbSpace.md),
          Expanded(child: second),
        ],
      );
    },
  );
}

/// Shown on tabs whose feature has not been built yet. No controls, so there
/// is nothing that could fail to work.
class FbNotBuiltYet extends StatelessWidget {
  const FbNotBuiltYet({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Padding(
      padding: const EdgeInsets.all(FbSpace.xxl),
      child: Text(context.l10n.notBuiltBody(title), style: context.text.bodySmall),
    ),
  );
}
