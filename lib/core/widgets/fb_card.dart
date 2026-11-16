import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Flat surface with a hairline border.
class FbCard extends StatelessWidget {
  const FbCard({
    required this.child,
    this.padding = const EdgeInsets.all(FbSpace.lg),
    this.radius = FbRadius.card,
    this.dashed = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Lighter treatment for empty states.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dashed ? c.background : c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: dashed ? c.textDisabled : c.outline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class FbSectionTitle extends StatelessWidget {
  const FbSectionTitle(this.title, {this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Expanded(
        child: Semantics(header: true, child: Text(title, style: context.text.title)),
      ),
      if (trailing != null) Text(trailing!, style: context.text.label),
    ],
  );
}

/// A tappable row inside a card: title on the left, value and chevron right.
class FbNavRow extends StatelessWidget {
  const FbNavRow({required this.title, required this.onTap, this.value, super.key});

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
        child: Row(
          children: [
            Text(title, style: context.text.body),
            const SizedBox(width: FbSpace.md),
            Expanded(
              child: Text(
                value ?? '',
                style: context.text.bodySmall,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
          ],
        ),
      ),
    ),
  );
}
