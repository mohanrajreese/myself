import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_labels.dart';
import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routine/schedule_editor.dart';
import '../../../app/routine_labels.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/units/rupees.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Rent, bills and subscriptions with a reminder (board P8Recurring).
class RecurringExpensesScreen extends ConsumerWidget {
  const RecurringExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(recurringProvider);
    final cats = ref.watch(moneyCategoryMapProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moneyRecurringTitle),
        actions: [
          TextButton.icon(
            onPressed: () => showFbSheet<void>(context, const _RecurringSheet()),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.moneyAdd),
          ),
        ],
      ),
      body: switch (async) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
          children: [
            if (value.isEmpty)
              FbEmptyHint(l10n.moneyNoRecurring, boxed: true)
            else
              FbListCard(
                children: [
                  for (final r in value)
                    FbListRow(
                      title: [
                        r.name,
                        formatRupees(r.amountPaise),
                        if (r.isIncome) l10n.moneyKindIncome,
                      ].join(' · '),
                      subtitle: [
                        l10n.moneyRecurringRow(
                          categoryLabel(l10n, cats[r.categoryId]),
                          paymentMethodLabel(l10n, r.method),
                          scheduleSummary(context, r.rule),
                        ),
                        if (!r.active) l10n.moneyPaused else if (r.remind) l10n.moneyReminderOn,
                      ].join(' · '),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showFbSheet<void>(context, _RecurringSheet(existing: r)),
                    ),
                ],
              ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.moneyRecurringNote, style: context.text.caption),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }
}

class _RecurringSheet extends ConsumerStatefulWidget {
  const _RecurringSheet({this.existing});
  final RecurringExpense? existing;

  @override
  ConsumerState<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends ConsumerState<_RecurringSheet> {
  late String _name = widget.existing?.name ?? '';
  late String _amount = widget.existing == null ? '' : rupeesInput(widget.existing!.amountPaise);
  late String _categoryId = widget.existing?.categoryId ?? seededCategoryId('rent');
  late PaymentMethod _method = widget.existing?.method ?? PaymentMethod.upi;
  late ScheduleRule? _rule = widget.existing?.rule ?? Monthly.dayOfMonth(1, times: const [9 * 60]);
  late bool _remind = widget.existing?.remind ?? true;
  late bool _active = widget.existing?.active ?? true;
  late bool _income = widget.existing?.isIncome ?? false;
  String? _nameError;
  String? _amountError;
  String? _error;
  bool _busy = false;

  Future<void> _pickCategory() async {
    final l10n = context.l10n;
    final cats = [
      for (final c
          in ref.read(_income ? incomeSourcesProvider : moneyCategoriesProvider).value ??
              const <FinanceCategory>[])
        if (!c.archived || c.id == _categoryId) c,
    ];
    final id = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyCategory,
        children: [
          for (final c in cats)
            FbListRow(
              title: categoryLabel(l10n, c),
              trailing: c.id == _categoryId
                  ? Icon(Icons.check_rounded, semanticLabel: l10n.selected)
                  : null,
              onTap: () => Navigator.of(context).pop(c.id),
            ),
        ],
      ),
    );
    if (id != null) setState(() => _categoryId = id);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    setState(() {
      _nameError = _name.trim().isEmpty ? l10n.errRequired : null;
      _amountError = paise == null || paise <= 0 ? l10n.errAmountInvalid : null;
      _error = _rule == null ? l10n.errSaveFailed : null;
    });
    if (_nameError != null || _amountError != null || _rule == null) return;
    setState(() => _busy = true);
    final r = await ref
        .read(moneyActionsProvider)
        .saveRecurring(
          RecurringExpense(
            id: widget.existing?.id ?? '',
            name: _name,
            amountPaise: paise!,
            categoryId: _categoryId,
            method: _method,
            rule: _rule!,
            remind: _remind,
            active: _active,
            isIncome: _income,
          ),
        );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyRecurringSaved);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.moneyDeleteRecurringTitle,
      message: l10n.moneyDeleteRecurringMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(moneyActionsProvider).deleteRecurring(widget.existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cats = ref.watch(moneyCategoryMapProvider);
    return FbSheetBody(
      title: l10n.moneyRecurringSheet,
      children: [
        FbSegmented<bool>(
          options: {false: l10n.moneyKindExpense, true: l10n.moneyKindIncome},
          selected: _income,
          onChanged: (v) => setState(() {
            _income = v;
            _categoryId = v ? seededCategoryId('salary') : seededCategoryId('rent');
          }),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.moneyDebtName,
          value: _name,
          errorText: _nameError,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _name = v,
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.moneyAmount,
          value: _amount,
          suffix: '₹',
          errorText: _amountError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: rupeeInputFormatters,
          onChanged: (v) => _amount = v,
        ),
        const SizedBox(height: FbSpace.lg),
        FbPickerField(
          label: _income ? l10n.moneySource : l10n.moneyCategory,
          valueText: categoryLabel(l10n, cats[_categoryId]),
          onTap: _pickCategory,
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneyPaidWith, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final m in PaymentMethod.values)
              FbToggleChip(
                label: paymentMethodLabel(l10n, m),
                selected: m == _method,
                onTap: () => setState(() => _method = m),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.lg),
        ScheduleEditor(
          initial: widget.existing?.rule ?? Monthly.dayOfMonth(1, times: const [9 * 60]),
          today: ref.read(todayProvider),
          label: l10n.moneyRepeats,
          onChanged: (r) => setState(() => _rule = r),
        ),
        FbSwitchRow(
          title: l10n.moneyRemindMe,
          value: _remind,
          onChanged: (v) => setState(() => _remind = v),
        ),
        FbSwitchRow(
          title: l10n.moneyActive,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: FbSpace.sm),
          FbNotice(_error!, isError: true),
        ],
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
        if (widget.existing != null) ...[
          const SizedBox(height: FbSpace.sm),
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: Text(l10n.delete),
          ),
        ],
      ],
    );
  }
}
