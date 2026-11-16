import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Two or three mutually exclusive options in one pill.
class FbSegmented<T> extends StatelessWidget {
  const FbSegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(FbRadius.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.all(FbSpace.xs),
          child: Row(
            children: [
              for (final entry in options.entries)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: entry.key == selected,
                    child: Material(
                      color: entry.key == selected ? c.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(FbRadius.input),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onChanged(entry.key),
                        child: SizedBox(
                          height: FbSize.touch,
                          child: Center(
                            child: Text(
                              entry.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: entry.key == selected ? c.textPrimary : c.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill that toggles on and off.
class FbToggleChip extends StatelessWidget {
  const FbToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.circular = false,
    this.onDeleted,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  /// Fixed round shape, used for weekday letters.
  final bool circular;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filled = circular && selected;
    final background = filled ? c.primary : (selected ? c.primaryContainer : c.surface);
    final foreground = filled ? c.onPrimary : (selected ? c.onPrimaryContainer : c.textPrimary);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.primary : c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: FbSize.touch,
              minWidth: circular ? FbSize.touch : 0,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: circular ? 0 : FbSpace.lg),
              child: Row(
                mainAxisSize: circular ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: context.text.bodySmall.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title, description and a switch on one row.
class FbSwitchRow extends StatelessWidget {
  const FbSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: context.text.body.copyWith(fontWeight: FontWeight.w500)),
                    if (subtitle != null) Text(subtitle!, style: context.text.caption),
                  ],
                ),
              ),
              const SizedBox(width: FbSpace.md),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    ),
  );
}
