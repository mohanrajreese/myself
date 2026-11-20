import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_labels.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_progress.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';

/// Seeded categories follow the app language; custom ones keep their name.
String categoryLabel(AppLocalizations l10n, FinanceCategory? c) {
  if (c == null) return l10n.moneyCatOther;
  return categoryNames(l10n)[c.systemKey] ?? c.name;
}

String monthLabel(LocalDate month) => DateFormat.yMMMM().format(DateTime(month.year, month.month));
String monthName(LocalDate month) => DateFormat.MMMM().format(DateTime(month.year, month.month));

/// A labelled bar: the percentage is spoken, never shown by colour alone.
class MoneyBar extends StatelessWidget {
  const MoneyBar({
    required this.fraction,
    required this.semanticLabel,
    this.over = false,
    super.key,
  });
  final double fraction;
  final String semanticLabel;
  final bool over;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: ExcludeSemantics(
      child: FbProgressBar(
        fraction: fraction.clamp(0, 1),
        color: over ? context.colors.error : null,
      ),
    ),
  );
}

/// One expense in a list.
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    required this.expense,
    required this.category,
    this.showDay = false,
    this.onTap,
    super.key,
  });
  final Expense expense;
  final FinanceCategory? category;
  final bool showDay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cat = categoryLabel(l10n, category);
    final note = expense.note;
    return FbListRow(
      title: note == null ? cat : '$note · $cat',
      subtitle: [
        if (showDay) context.shortDate(expense.localDate),
        context.time(expense.occurredAt),
        paymentMethodLabel(l10n, expense.method),
        if (expense.mealLogId != null) l10n.moneyLinkedMeal,
        if (expense.hasReceipt) l10n.moneyReceipt,
      ].join(' · '),
      trailing: Text(formatRupees(expense.amountPaise), style: context.text.bodyStrong),
      onTap: onTap,
    );
  }
}

/// Rupees with up to 2 decimals, at most 8 digits before the point.
final rupeeInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,8}([.,]\d{0,2})?')),
];

/// A section heading with an optional action on the right.
class MoneySectionHeader extends StatelessWidget {
  const MoneySectionHeader(this.title, {this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: FbSpace.xl, bottom: FbSpace.sm),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: context.text.title)),
        ),
        ?action,
      ],
    ),
  );
}

/// A label and a value that wrap onto two lines when text is large.
class MoneyValueRow extends StatelessWidget {
  const MoneyValueRow({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FbSpace.md,
            children: [
              Text(label, style: context.text.body),
              Text(value, style: context.text.bodyStrong),
            ],
          ),
        ),
      ),
    ),
  );
}
