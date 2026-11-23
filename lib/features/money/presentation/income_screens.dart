import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Add or edit income (board P9Income, §5.22L).
Future<void> showIncomeSheet(BuildContext context, {Income? existing}) =>
    showFbSheet<void>(context, _IncomeSheet(existing: existing));

class _IncomeSheet extends ConsumerStatefulWidget {
  const _IncomeSheet({this.existing});
  final Income? existing;

  @override
  ConsumerState<_IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends ConsumerState<_IncomeSheet> {
  late String _amount = widget.existing == null ? '' : rupeesInput(widget.existing!.amountPaise);
  late String? _sourceId = widget.existing?.categoryId;
  late DateTime _at = (widget.existing?.occurredAt ?? ref.read(clockProvider).now()).toLocal();
  late String _note = widget.existing?.note ?? '';
  String? _amountError;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise <= 0) {
      setState(() => _amountError = l10n.errAmountInvalid);
      return;
    }
    if (_at.isAfter(ref.read(clockProvider).now())) {
      setState(() => _error = l10n.errInFuture);
      return;
    }
    final sources = ref.read(incomeSourcesProvider).value ?? const <FinanceCategory>[];
    final sourceId = _sourceId ?? sources.firstOrNull?.id ?? seededCategoryId('salary');
    setState(() => _busy = true);
    final money = ref.read(moneyRepositoryProvider);
    final draft = (amountPaise: paise, categoryId: sourceId, at: _at, note: _note);
    final ok = widget.existing == null
        ? (await money.addIncome(draft)).isOk
        : (await money.updateIncome(widget.existing!.id, draft)).isOk;
    if (!mounted) return;
    if (!ok) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyIncomeSaved);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.moneyDeleteIncomeTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(moneyRepositoryProvider).deleteIncome(widget.existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sources = [
      for (final c in ref.watch(incomeSourcesProvider).value ?? const <FinanceCategory>[])
        if (!c.archived || c.id == _sourceId) c,
    ];
    final selected = _sourceId ?? sources.firstOrNull?.id;
    return FbSheetBody(
      title: widget.existing == null ? l10n.moneyAddIncomeLabel : l10n.moneyEditIncome,
      trailing: widget.existing == null
          ? null
          : IconButton(
              tooltip: l10n.delete,
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
            ),
      children: [
        FbTextField(
          label: l10n.moneyAmount,
          value: _amount,
          suffix: '₹',
          errorText: _amountError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: rupeeInputFormatters,
          onChanged: (v) => setState(() => (_amount = v, _amountError = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneySource, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final c in sources)
              FbToggleChip(
                label: categoryLabel(l10n, c),
                selected: c.id == selected,
                onTap: () => setState(() => _sourceId = c.id),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.moneyReceivedOn,
          value: _at,
          last: ref.read(clockProvider).now(),
          onChanged: (v) => setState(() => (_at = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.note,
          value: _note,
          optional: true,
          optionalLabel: l10n.optional,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _note = v,
        ),
        if (_error != null) ...[
          const SizedBox(height: FbSpace.md),
          FbNotice(_error!, isError: true),
        ],
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}

/// This month's income (board P9Income).
class IncomeScreen extends ConsumerWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final month = ref.watch(moneyMonthProvider);
    final range = monthRange(month, today);
    final async = ref.watch(incomesProvider(range));
    final cats = ref.watch(moneyCategoryMapProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneyIncome)),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.moneyAddIncomeLabel,
        onPressed: () => showIncomeSheet(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: switch (async) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, 96),
          children: [
            Text(monthLabel(month), style: context.text.bodyStrong),
            const SizedBox(height: FbSpace.md),
            if (value.isEmpty)
              FbEmptyHint(l10n.moneyNoIncome, boxed: true)
            else
              FbListCard(
                children: [
                  for (final i in value)
                    FbListRow(
                      title: categoryLabel(l10n, cats[i.categoryId]),
                      subtitle: [context.dayLabel(i.localDate, today: today), ?i.note].join(' · '),
                      trailing: Text(formatRupees(i.amountPaise), style: context.text.bodyStrong),
                      onTap: () => showIncomeSheet(context, existing: i),
                    ),
                ],
              ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.moneyIncomeNote, style: context.text.caption),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }
}
