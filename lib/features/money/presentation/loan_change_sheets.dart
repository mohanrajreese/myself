import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/loans.dart';
import '../domain/money.dart';
import 'money_common.dart';

Future<LocalDate?> _pickDate(BuildContext context, LocalDate initial, LocalDate last) async {
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime(initial.year, initial.month, initial.day),
    firstDate: DateTime(1990),
    lastDate: DateTime(last.year, last.month, last.day),
  );
  return d == null ? null : LocalDate(d.year, d.month, d.day);
}

Widget _dateField(BuildContext context, String label, LocalDate value, VoidCallback onTap) =>
    FbPickerField(label: label, valueText: longDate(value), onTap: onTap);

Widget _moneyField(String label, String value, String? error, ValueChanged<String> onChanged) =>
    FbTextField(
      label: label,
      value: value,
      suffix: '₹',
      errorText: error,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: rupeeInputFormatters,
      onChanged: onChanged,
    );

/// Part-payment: fewer EMIs or a lower EMI (board P9LoanChanges, §5.22H).
class PartPaymentSheet extends ConsumerStatefulWidget {
  const PartPaymentSheet({required this.status, super.key});
  final DebtStatus status;

  @override
  ConsumerState<PartPaymentSheet> createState() => _PartPaymentSheetState();
}

class _PartPaymentSheetState extends ConsumerState<PartPaymentSheet> {
  String _amount = '';
  late LocalDate _on = ref.read(todayProvider);
  PrepayMode _mode = PrepayMode.reduceTenure;
  String? _error;
  bool _busy = false;

  LoanChange? _draft() {
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise <= 0) return null;
    return LoanChange(
      id: 'preview',
      debtId: widget.status.debt.id,
      kind: LoanChangeKind.prepayment,
      effectiveDate: _on,
      amountPaise: paise,
      mode: _mode,
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final c = _draft();
    if (c == null) {
      setState(() => _error = l10n.errAmountInvalid);
      return;
    }
    setState(() => _busy = true);
    final r = await ref.read(moneyActionsProvider).addLoanChange(c);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyChangeSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = widget.status;
    final c = _draft();
    String? preview;
    if (c != null && s.schedule.isNotEmpty) {
      final after = loanSchedule(s.debt, [...s.changes, c]);
      if (after.isNotEmpty) {
        if (_mode == PrepayMode.reduceTenure) {
          final fewer = s.schedule.length - after.length;
          if (fewer > 0) {
            preview = l10n.moneyPreviewFewer(
              monthYear(after.last.due),
              monthYear(s.schedule.last.due),
              fewer,
            );
          }
        } else {
          final next = after.where((r) => r.due.isAfter(_on)).firstOrNull;
          final was = s.schedule.where((r) => r.due.isAfter(_on)).firstOrNull;
          if (next != null && was != null && next.emiPaise < was.emiPaise) {
            preview = l10n.moneyPreviewLower(
              formatRupees(next.emiPaise),
              formatRupees(was.emiPaise),
            );
          }
        }
      }
    }
    return FbSheetBody(
      title: l10n.moneyPartPayment,
      children: [
        _moneyField(
          l10n.moneyAmount,
          _amount,
          _error,
          (v) => setState(() => (_amount = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        _dateField(context, l10n.moneyPaidOn, _on, () async {
          final d = await _pickDate(context, _on, ref.read(todayProvider));
          if (d != null) setState(() => _on = d);
        }),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneyAfterwards, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        FbSegmented<PrepayMode>(
          semanticLabel: l10n.moneyAfterwards,
          options: {
            PrepayMode.reduceTenure: l10n.moneyFewerEmis,
            PrepayMode.reduceEmi: l10n.moneyLowerEmi,
          },
          selected: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        if (preview != null) ...[
          const SizedBox(height: FbSpace.md),
          FbCard(child: Text(preview, style: context.text.body)),
        ],
        const SizedBox(height: FbSpace.sm),
        Text(l10n.moneyPartPaymentNote2, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}

/// A new rate and/or EMI from an instalment onward (§5.22H).
class RateChangeSheet extends ConsumerStatefulWidget {
  const RateChangeSheet({required this.status, super.key});
  final DebtStatus status;

  @override
  ConsumerState<RateChangeSheet> createState() => _RateChangeSheetState();
}

class _RateChangeSheetState extends ConsumerState<RateChangeSheet> {
  late String _from = '${widget.status.nextInstalment ?? 1}';
  String _rate = '';
  String _emi = '';
  String _left = '';
  final Map<String, String> _errors = {};
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final max = widget.status.instalmentCount;
    final from = int.tryParse(_from);
    final rate = _rate.trim().isEmpty ? null : double.tryParse(_rate.replaceAll(',', '.'));
    final emi = _emi.trim().isEmpty ? null : parseRupees(_emi.replaceAll(',', '.'));
    final left = _left.trim().isEmpty ? null : int.tryParse(_left);
    final errors = <String, String>{};
    if (from == null || from < 1 || from > max) errors['from'] = l10n.errInstalmentRange(max);
    if (_rate.trim().isNotEmpty && (rate == null || rate < 0 || rate > 100)) {
      errors['rate'] = l10n.errRate;
    }
    if (_emi.trim().isNotEmpty && (emi == null || emi <= 0)) errors['emi'] = l10n.errAmountInvalid;
    if (_left.trim().isNotEmpty && (left == null || left < 1 || left > 600)) {
      errors['left'] = l10n.errEmiCount;
    }
    if (rate == null && emi == null && errors.isEmpty) errors['rate'] = l10n.errRateOrEmi;
    setState(
      () => _errors
        ..clear()
        ..addAll(errors),
    );
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final LocalDate due = widget.status.rowFor(from!)?.due ?? ref.read(todayProvider);
    final r = await ref
        .read(moneyActionsProvider)
        .addLoanChange(
          LoanChange(
            id: '',
            debtId: widget.status.debt.id,
            kind: LoanChangeKind.rateChange,
            effectiveDate: due,
            fromInstalment: from,
            rateBp: rate == null ? null : (rate * 100).round(),
            emiPaise: emi,
            instalmentsLeft: left,
          ),
        );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _errors['rate'] = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyChangeSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.moneyChangeRate,
      children: [
        FbTextField(
          label: l10n.moneyFromInstalment,
          value: _from,
          errorText: _errors['from'],
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: (v) => _from = v,
        ),
        const SizedBox(height: FbSpace.lg),
        FbFieldPair(
          first: FbTextField(
            label: l10n.moneyNewRate,
            value: _rate,
            suffix: '%',
            errorText: _errors['rate'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,2})?'))],
            onChanged: (v) => _rate = v,
          ),
          second: _moneyField(l10n.moneyNewEmi, _emi, _errors['emi'], (v) => _emi = v),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.moneyInstalmentsLeft,
          value: _left,
          hint: l10n.moneyInstalmentsLeftHint,
          optional: true,
          optionalLabel: l10n.optional,
          errorText: _errors['left'],
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: (v) => _left = v,
        ),
        const SizedBox(height: FbSpace.sm),
        Text(l10n.moneyRateChangeNote, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}

/// The outstanding balance from a bank statement (§5.22H).
class CorrectionSheet extends ConsumerStatefulWidget {
  const CorrectionSheet({required this.status, super.key});
  final DebtStatus status;

  @override
  ConsumerState<CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends ConsumerState<CorrectionSheet> {
  String _amount = '';
  late LocalDate _on = ref.read(todayProvider);
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise < 0) {
      setState(() => _error = l10n.errAmountInvalid);
      return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(moneyActionsProvider)
        .addLoanChange(
          LoanChange(
            id: '',
            debtId: widget.status.debt.id,
            kind: LoanChangeKind.balanceCorrection,
            effectiveDate: _on,
            amountPaise: paise,
          ),
        );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyChangeSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.moneyCorrectOutstanding,
      children: [
        _moneyField(
          l10n.moneyStatementOutstanding,
          _amount,
          _error,
          (v) => setState(() => (_amount = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        _dateField(context, l10n.moneyStatementDate, _on, () async {
          final d = await _pickDate(context, _on, ref.read(todayProvider));
          if (d != null) setState(() => _on = d);
        }),
        const SizedBox(height: FbSpace.sm),
        Text(l10n.moneyCorrectionNote, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}
