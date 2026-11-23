import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Records a card statement (board P9CreditCard, §5.22I).
class StatementSheet extends ConsumerStatefulWidget {
  const StatementSheet({required this.card, super.key});
  final Debt card;

  @override
  ConsumerState<StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends ConsumerState<StatementSheet> {
  late LocalDate _statement = _lastStatementDay();
  late LocalDate _due = _dueAfter(_statement);
  String _total = '';
  String _min = '';
  bool _remind = true;
  final Map<String, String> _errors = {};
  bool _busy = false;

  LocalDate _lastStatementDay() {
    final today = ref.read(todayProvider);
    final day = widget.card.statementDay ?? today.day.clamp(1, 28);
    final thisMonth = LocalDate(today.year, today.month, day);
    return thisMonth.isAfter(today)
        ? LocalDate.fromDateTime(DateTime.utc(today.year, today.month - 1, day))
        : thisMonth;
  }

  LocalDate _dueAfter(LocalDate st) {
    final day = widget.card.cardDueDay;
    if (day == null) return st.addDays(20);
    final same = LocalDate(st.year, st.month, day);
    return same.isAfter(st)
        ? same
        : LocalDate.fromDateTime(DateTime.utc(st.year, st.month + 1, day));
  }

  Future<LocalDate?> _pick(LocalDate initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(initial.year + 1, 12, 31),
    );
    return d == null ? null : LocalDate(d.year, d.month, d.day);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final total = parseRupees(_total.replaceAll(',', '.'));
    final min = _min.trim().isEmpty ? 0 : parseRupees(_min.replaceAll(',', '.'));
    final errors = <String, String>{};
    if (total == null || total < 0) errors['total'] = l10n.errAmountInvalid;
    if (min == null || min < 0) errors['min'] = l10n.errAmountInvalid;
    if (errors.isEmpty && min! > total!) errors['min'] = l10n.errMinOverTotal;
    if (_due.isBefore(_statement)) errors['due'] = l10n.errDueBeforeStatement;
    setState(
      () => _errors
        ..clear()
        ..addAll(errors),
    );
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final r = await ref
        .read(moneyActionsProvider)
        .saveStatement(
          CardStatement(
            id: '',
            debtId: widget.card.id,
            statementDate: _statement,
            dueDate: _due,
            totalDuePaise: total!,
            minDuePaise: min!,
            remind: _remind,
          ),
        );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _errors['total'] = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyStatementSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.moneyNewStatement,
      children: [
        FbFieldPair(
          first: FbPickerField(
            label: l10n.moneyStatementDate,
            valueText: longDate(_statement),
            onTap: () async {
              final d = await _pick(_statement);
              if (d != null) setState(() => (_statement = d, _due = _dueAfter(d)));
            },
          ),
          second: FbPickerField(
            label: l10n.moneyDueDate,
            valueText: longDate(_due),
            onTap: () async {
              final d = await _pick(_due);
              if (d != null) setState(() => _due = d);
            },
          ),
        ),
        if (_errors['due'] != null)
          Text(_errors['due']!, style: context.text.caption.copyWith(color: context.colors.error)),
        const SizedBox(height: FbSpace.lg),
        FbFieldPair(
          first: FbTextField(
            label: l10n.moneyTotalDue,
            value: _total,
            suffix: '₹',
            errorText: _errors['total'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: rupeeInputFormatters,
            onChanged: (v) => _total = v,
          ),
          second: FbTextField(
            label: l10n.moneyMinimumDue,
            value: _min,
            suffix: '₹',
            errorText: _errors['min'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: rupeeInputFormatters,
            onChanged: (v) => _min = v,
          ),
        ),
        FbSwitchRow(
          title: l10n.moneyRemindMe,
          subtitle: l10n.moneyRemindDueLine,
          value: _remind,
          onChanged: (v) => setState(() => _remind = v),
        ),
        const SizedBox(height: FbSpace.md),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}
