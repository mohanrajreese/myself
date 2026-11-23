import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
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

String kindLabel(AppLocalizations l10n, DebtKind k) => switch (k) {
  DebtKind.personal => l10n.moneyKindPersonal,
  DebtKind.bankLoan => l10n.moneyKindBankLoan,
  DebtKind.creditCard => l10n.moneyKindCreditCard,
  DebtKind.other => l10n.moneyKindOther,
};

enum _DebtTab { iOwe, owedToMe, settled }

/// Debts both ways (board P8Debts).
class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  _DebtTab _tab = _DebtTab.iOwe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(debtStatusesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moneyDebtsTitle),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.moneyNewDebt),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.moneyAdd, semanticsLabel: l10n.moneyAddDebtLabel),
          ),
        ],
      ),
      body: switch (async) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => () {
          final open = [
            for (final s in value)
              if (!s.debt.settled) s,
          ];
          final owe = [
            for (final s in open)
              if (s.debt.direction == DebtDirection.iOwe) s,
          ];
          final owed = [
            for (final s in open)
              if (s.debt.direction == DebtDirection.owedToMe) s,
          ];
          final shown = switch (_tab) {
            _DebtTab.iOwe => owe,
            _DebtTab.owedToMe => owed,
            _DebtTab.settled => [
              for (final s in value)
                if (s.debt.settled) s,
            ],
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Total(label: l10n.moneyYouOwe, list: owe),
                  ),
                  const SizedBox(width: FbSpace.sm),
                  Expanded(
                    child: _Total(label: l10n.moneyOwedToYou, list: owed),
                  ),
                ],
              ),
              const SizedBox(height: FbSpace.md),
              FbSegmented<_DebtTab>(
                options: {
                  _DebtTab.iOwe: l10n.moneyIOwe,
                  _DebtTab.owedToMe: l10n.moneyOwedToMe,
                  _DebtTab.settled: l10n.moneySettled,
                },
                selected: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: FbSpace.md),
              if (shown.isEmpty)
                FbEmptyHint(l10n.moneyNoDebts, boxed: true)
              else
                FbListCard(children: [for (final s in shown) _DebtRow(status: s)]),
              const SizedBox(height: FbSpace.md),
              Text(l10n.moneyDebtsNote, style: context.text.caption),
            ],
          );
        }(),
        _ => const FbLoading(),
      },
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.list});
  final String label;
  final List<DebtStatus> list;

  @override
  Widget build(BuildContext context) => FbCard(
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.caption),
          Text(
            formatRupees(list.fold(0, (s, d) => s + d.remainingPaise)),
            style: context.text.title,
          ),
          Text(context.l10n.moneyOpenCount(list.length), style: context.text.caption),
        ],
      ),
    ),
  );
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.status});
  final DebtStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = status.debt;
    final emi = d.emi;
    final parts = <String>[
      kindLabel(l10n, d.kind),
      if (emi != null) ...[
        l10n.moneyEmiOnDay(formatRupees(emi.emiPaise), emi.day),
        l10n.moneyPaidOf(status.paidInstalments.length, emi.count),
        if (status.nextDue != null) l10n.moneyNextOn(context.shortDate(status.nextDue!)),
      ] else ...[
        d.direction == DebtDirection.iOwe
            ? l10n.moneyBorrowedOn(formatRupees(d.principalPaise), context.shortDate(d.startDate))
            : l10n.moneyLentOn(formatRupees(d.principalPaise), context.shortDate(d.startDate)),
        if (status.paidPaise > 0)
          d.direction == DebtDirection.iOwe
              ? l10n.moneyRepaid(formatRupees(status.paidPaise))
              : l10n.moneyReceived(formatRupees(status.paidPaise)),
        if (d.dueDate != null) l10n.moneyDueOn(context.shortDate(d.dueDate!)),
      ],
    ];
    final title = d.name == d.counterparty ? d.name : '${d.name} · ${d.counterparty}';
    return InkWell(
      onTap: () => context.push(Routes.moneyDebt(d.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: context.text.bodyStrong)),
                Text(formatRupees(status.remainingPaise), style: context.text.bodyStrong),
              ],
            ),
            Text(parts.join(' · '), style: context.text.caption),
            if (emi != null) ...[
              const SizedBox(height: FbSpace.xs),
              MoneyBar(
                fraction: status.paidInstalments.length / emi.count,
                semanticLabel: l10n.moneyInstalmentsA11y(status.paidInstalments.length, emi.count),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Records a payment against a debt (any amount, date and note).
class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({required this.debtId, this.initialPaise, super.key});
  final String debtId;
  final int? initialPaise;

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  late String _amount = widget.initialPaise == null ? '' : rupeesInput(widget.initialPaise!);
  String _note = '';
  late DateTime _at = ref.read(clockProvider).now().toLocal();
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise <= 0) {
      setState(() => _error = l10n.errAmountInvalid);
      return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(moneyActionsProvider)
        .addPayment(widget.debtId, amountPaise: paise, at: _at, note: _note);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyPaymentSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.moneyOtherPayment,
      children: [
        FbTextField(
          label: l10n.moneyAmount,
          value: _amount,
          suffix: '₹',
          errorText: _error,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: rupeeInputFormatters,
          onChanged: (v) => setState(() => (_amount = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.moneyWhen,
          value: _at,
          last: ref.read(clockProvider).now(),
          onChanged: (v) => setState(() => _at = v),
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
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}

/// Add or edit a debt or loan (board P8AddDebt).
class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({this.id, super.key});
  final String? id;

  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  bool _loaded = false;
  Debt? _existing;
  DebtDirection _direction = DebtDirection.iOwe;
  DebtKind _kind = DebtKind.personal;
  String _name = '';
  String _counterparty = '';
  String _amount = '';
  late LocalDate _start = ref.read(todayProvider);
  String _rate = '';
  bool _emiOn = false;
  String _emiAmount = '';
  String _emiDay = '';
  String _emiCount = '';
  LocalDate? _firstEmi;
  bool _markPast = true;
  bool _remind = true;
  int _lead = 7;
  LocalDate? _due;
  String _notes = '';
  bool _recordAsExpense = true;
  final Map<String, String> _errors = {};
  bool _busy = false;

  static const _leadOptions = [7, 10, 14, 30];

  void _load(Debt d) {
    _existing = d;
    _direction = d.direction;
    _kind = d.kind;
    _name = d.name;
    _counterparty = d.counterparty;
    _amount = rupeesInput(d.principalPaise);
    _start = d.startDate;
    _rate = d.interestRateBp == null ? '' : rateLabel(d.interestRateBp!);
    final emi = d.emi;
    _emiOn = emi != null;
    if (emi != null) {
      _emiAmount = rupeesInput(emi.emiPaise);
      _emiDay = '${emi.day}';
      _emiCount = '${emi.count}';
      _firstEmi = emi.first;
    }
    _remind = d.remind;
    _lead = d.remindDaysBefore;
    _due = d.dueDate;
    _notes = d.notes ?? '';
    _recordAsExpense = d.recordAsExpense;
    _markPast = false;
  }

  EmiPlan? get _plan {
    final paise = parseRupees(_emiAmount.replaceAll(',', '.'));
    final day = int.tryParse(_emiDay);
    final count = int.tryParse(_emiCount);
    final first = _firstEmi;
    if (!_emiOn || paise == null || day == null || count == null || first == null) return null;
    return EmiPlan(emiPaise: paise, day: day, count: count, first: first);
  }

  int get _pastCount {
    final plan = _plan;
    if (plan == null || plan.day < 1 || plan.day > 28 || plan.count < 1) return 0;
    return plan.dueBy(ref.read(todayProvider).addDays(-1)).clamp(0, plan.count);
  }

  Future<LocalDate?> _pickDate(LocalDate? initial) async {
    final today = ref.read(todayProvider);
    final i = initial ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(i.year, i.month, i.day),
      firstDate: DateTime(1990),
      lastDate: DateTime(today.year + 50),
    );
    return picked == null ? null : LocalDate(picked.year, picked.month, picked.day);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final errors = <String, String>{};
    final principal = parseRupees(_amount.replaceAll(',', '.'));
    if (_name.trim().isEmpty) errors['name'] = l10n.errRequired;
    if (_counterparty.trim().isEmpty) errors['counterparty'] = l10n.errRequired;
    if (principal == null || principal <= 0) errors['amount'] = l10n.errAmountInvalid;
    final rate = _rate.trim().isEmpty ? null : double.tryParse(_rate.replaceAll(',', '.'));
    if (_rate.trim().isNotEmpty && (rate == null || rate < 0 || rate > 100)) {
      errors['rate'] = l10n.errRate;
    }
    final emiEnabled = _emiOn && _kind != DebtKind.personal;
    EmiPlan? plan;
    if (emiEnabled) {
      final paise = parseRupees(_emiAmount.replaceAll(',', '.'));
      final day = int.tryParse(_emiDay);
      final count = int.tryParse(_emiCount);
      if (paise == null || paise <= 0) errors['emi'] = l10n.errAmountInvalid;
      if (day == null || day < 1 || day > 28) errors['day'] = l10n.errDueDay;
      if (count == null || count < 1 || count > 600) errors['count'] = l10n.errEmiCount;
      if (_firstEmi == null) errors['first'] = l10n.errRequired;
      if (errors.isEmpty) {
        plan = EmiPlan(emiPaise: paise!, day: day!, count: count!, first: _firstEmi!);
      }
    }
    setState(
      () => _errors
        ..clear()
        ..addAll(errors),
    );
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final debt = Debt(
      id: _existing?.id ?? '',
      direction: _direction,
      name: _name,
      counterparty: _counterparty,
      kind: _kind,
      principalPaise: principal!,
      startDate: _start,
      // Basis points: an integer, never a stored double.
      interestRateBp: rate == null ? null : (rate * 100).round(),
      dueDate: emiEnabled ? null : _due,
      emi: plan,
      remind: _remind,
      remindDaysBefore: _lead,
      recordAsExpense: _recordAsExpense,
      settled: _existing?.settled ?? false,
      notes: _notes,
    );
    final r = await ref
        .read(moneyActionsProvider)
        .saveDebt(debt, markPastInstalmentsPaid: plan != null && _existing == null && _markPast);
    if (!mounted) return;
    final saved = r.valueOrNull;
    if (saved == null) {
      setState(() => _busy = false);
      final code = r.failureOrNull;
      showFbSnackBar(
        context,
        code is ValidationFailure ? l10n.errAmountInvalid : l10n.errSaveFailed,
      );
      return;
    }
    showFbSnackBar(context, l10n.moneyDebtSaved);
    context.pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.moneyDeleteDebtTitle,
      message: l10n.moneyDeleteDebtMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(moneyActionsProvider).deleteDebt(_existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    context.go(Routes.moneyDebts);
  }

  Widget _money(String label, String value, String? error, ValueChanged<String> onChanged) =>
      FbTextField(
        label: label,
        value: value,
        suffix: '₹',
        errorText: error,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: rupeeInputFormatters,
        onChanged: onChanged,
      );

  Widget _date(
    String label,
    LocalDate? value,
    ValueChanged<LocalDate> onPicked, {
    String? error,
    VoidCallback? onClear,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FbPickerField(
        label: label,
        valueText: value == null ? null : longDate(value),
        hint: context.l10n.moneyChooseDate,
        optionalLabel: onClear == null ? null : context.l10n.optional,
        onClear: value == null ? null : onClear,
        clearLabel: context.l10n.moneyClear,
        onTap: () async {
          final d = await _pickDate(value);
          if (d != null) setState(() => onPicked(d));
        },
      ),
      if (error != null)
        Text(error, style: context.text.caption.copyWith(color: context.colors.error)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.id != null && !_loaded) {
      final found = ref.watch(debtsProvider).value?.where((d) => d.id == widget.id).firstOrNull;
      if (found == null) return Scaffold(appBar: AppBar(), body: const FbLoading());
      _load(found);
      _loaded = true;
    }
    final emiAllowed = _kind != DebtKind.personal;
    final past = _existing == null && emiAllowed && _emiOn ? _pastCount : 0;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: () => context.pop()),
        title: Text(_existing == null ? l10n.moneyNewDebt : l10n.moneyEditDebt),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: l10n.delete,
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSegmented<DebtDirection>(
            semanticLabel: l10n.moneyDirection,
            options: {
              DebtDirection.iOwe: l10n.moneyIOwe,
              DebtDirection.owedToMe: l10n.moneyOwedToMe,
            },
            selected: _direction,
            onChanged: (v) => setState(() => _direction = v),
          ),
          const SizedBox(height: FbSpace.lg),
          Text(l10n.moneyKind, style: context.text.label),
          const SizedBox(height: FbSpace.xs),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              for (final k in DebtKind.values)
                FbToggleChip(
                  label: kindLabel(l10n, k),
                  selected: k == _kind,
                  onTap: () => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          FbTextField(
            label: l10n.moneyDebtName,
            value: _name,
            errorText: _errors['name'],
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => _name = v,
          ),
          const SizedBox(height: FbSpace.lg),
          FbTextField(
            label: l10n.moneyCounterparty,
            value: _counterparty,
            errorText: _errors['counterparty'],
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => _counterparty = v,
          ),
          const SizedBox(height: FbSpace.lg),
          FbFieldPair(
            first: _money(l10n.moneyOriginalAmount, _amount, _errors['amount'], (v) => _amount = v),
            second: _date(l10n.moneyStartDate, _start, (d) => _start = d),
          ),
          const SizedBox(height: FbSpace.lg),
          FbTextField(
            label: l10n.moneyInterestRate,
            value: _rate,
            optional: true,
            optionalLabel: l10n.optional,
            suffix: '%',
            errorText: _errors['rate'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,2})?'))],
            onChanged: (v) => _rate = v,
          ),
          const SizedBox(height: FbSpace.lg),
          if (emiAllowed)
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FbSwitchRow(
                    title: l10n.moneyPaidInEmis,
                    value: _emiOn,
                    onChanged: (v) => setState(() => _emiOn = v),
                  ),
                  if (_emiOn) ...[
                    FbFieldPair(
                      first: _money(
                        l10n.moneyEmiAmount,
                        _emiAmount,
                        _errors['emi'],
                        (v) => setState(() => _emiAmount = v),
                      ),
                      second: FbTextField(
                        label: l10n.moneyDueDay,
                        value: _emiDay,
                        errorText: _errors['day'],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        onChanged: (v) => setState(() => _emiDay = v),
                      ),
                    ),
                    const SizedBox(height: FbSpace.md),
                    FbFieldPair(
                      first: FbTextField(
                        label: l10n.moneyEmiCount,
                        value: _emiCount,
                        errorText: _errors['count'],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (v) => setState(() => _emiCount = v),
                      ),
                      second: _date(
                        l10n.moneyFirstEmi,
                        _firstEmi,
                        (d) => _firstEmi = d,
                        error: _errors['first'],
                      ),
                    ),
                    if (past > 0) ...[
                      const SizedBox(height: FbSpace.md),
                      Text(l10n.moneyPastEmis(past), style: context.text.body),
                      const SizedBox(height: FbSpace.sm),
                      FbSegmented<bool>(
                        options: {true: l10n.moneyYesAll(past), false: l10n.moneyNoAddThem},
                        selected: _markPast,
                        onChanged: (v) => setState(() => _markPast = v),
                      ),
                    ],
                    if (_direction == DebtDirection.iOwe) ...[
                      FbSwitchRow(
                        title: l10n.moneyRemindMe,
                        subtitle: l10n.moneyEmiReminderLine(_lead, int.tryParse(_emiDay) ?? 1),
                        value: _remind,
                        onChanged: (v) => setState(() => _remind = v),
                      ),
                      if (_remind) ...[
                        Text(l10n.moneyFirstReminder, style: context.text.label),
                        const SizedBox(height: FbSpace.xs),
                        Wrap(
                          spacing: FbSpace.sm,
                          runSpacing: FbSpace.sm,
                          children: [
                            for (final d in _leadOptions)
                              FbToggleChip(
                                label: l10n.moneyDaysBefore(d),
                                selected: d == _lead,
                                onTap: () => setState(() => _lead = d),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          if (!emiAllowed || !_emiOn) ...[
            const SizedBox(height: FbSpace.lg),
            _date(
              l10n.moneyDueDateOptional,
              _due,
              (d) => _due = d,
              onClear: () => setState(() => _due = null),
            ),
          ],
          const SizedBox(height: FbSpace.lg),
          FbTextField(
            label: l10n.note,
            value: _notes,
            optional: true,
            optionalLabel: l10n.optional,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => _notes = v,
          ),
          const SizedBox(height: FbSpace.xl),
          FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
        ],
      ),
    );
  }
}
