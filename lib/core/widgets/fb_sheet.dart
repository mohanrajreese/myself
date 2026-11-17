import 'package:material_ui/material_ui.dart';

import '../utils/local_date.dart';
import 'fb_card.dart';
import 'fb_fields.dart';
import 'l10n.dart';
import 'tokens.dart';

/// Opens [child] as a bottom sheet that grows with the keyboard.
Future<T?> showFbSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => child,
);

/// Standard sheet layout: title row, scrolling fields, actions at the bottom.
class FbSheetBody extends StatelessWidget {
  const FbSheetBody({required this.title, required this.children, this.trailing, super.key});

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(FbSpace.xl, 0, FbSpace.xl, FbSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(title, style: context.text.title)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          ...children,
        ],
      ),
    ),
  );
}

/// A date-and-time field that opens the system pickers.
class FbDateTimeField extends StatelessWidget {
  const FbDateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.last,
    this.first,
    this.errorText,
    super.key,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime last;
  final DateTime? first;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final text =
        '${localizations.formatMediumDate(value)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    Future<void> pick() async {
      final date = await showDatePicker(
        context: context,
        initialDate: value.isAfter(last) ? last : value,
        firstDate: first ?? DateTime(last.year - 5),
        lastDate: last,
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(value),
      );
      if (time == null) return;
      onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbPickerField(label: label, valueText: text, onTap: pick),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: FbSpace.xs, left: FbSpace.lg),
            child: Text(
              errorText!,
              style: context.text.caption.copyWith(color: context.colors.error),
            ),
          ),
      ],
    );
  }
}

/// Picks one whole number from 1 to 5 (wellness scores, sleep quality).
class FbScoreRow extends StatelessWidget {
  const FbScoreRow({required this.label, required this.value, required this.onChanged, super.key});

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.text.bodyStrong.copyWith(fontSize: 14)),
        const SizedBox(height: FbSpace.sm),
        Row(
          children: [
            for (var score = 1; score <= 5; score++) ...[
              if (score > 1) const SizedBox(width: FbSpace.sm),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == score,
                  label: context.l10n.scoreLabel(label, score),
                  excludeSemantics: true,
                  onTap: () => onChanged(value == score ? null : score),
                  child: Material(
                    color: value == score ? c.primary : c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FbRadius.chip),
                      side: BorderSide(color: value == score ? c.primary : c.outline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onChanged(value == score ? null : score),
                      child: SizedBox(
                        height: FbSize.touch,
                        child: Center(
                          child: Text(
                            '$score',
                            style: context.text.bodyStrong.copyWith(
                              color: value == score ? c.onPrimary : c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A tappable list row inside a card: main text, secondary text, trailing action.
class FbListRow extends StatelessWidget {
  const FbListRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: FbSpace.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.text.bodyStrong),
                  if (subtitle != null) Text(subtitle!, style: context.text.caption),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    return onTap == null ? MergeSemantics(child: content) : InkWell(onTap: onTap, child: content);
  }
}

/// Rows separated by hairlines inside one card.
class FbListCard extends StatelessWidget {
  const FbListCard({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FbCard(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(FbRadius.card),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: FbSpace.lg, endIndent: FbSpace.lg),
              children[i],
            ],
          ],
        ),
      ),
    ),
  );
}

/// Days from [start] to [date], for chart x positions.
double dayOffset(LocalDate start, LocalDate date) => date.daysSince(start).toDouble();
