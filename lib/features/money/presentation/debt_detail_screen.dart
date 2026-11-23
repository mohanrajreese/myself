import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/loans.dart';
import '../domain/money.dart';
import 'card_sheets.dart';
import 'debt_screens.dart';
import 'loan_change_sheets.dart';
import 'money_common.dart';

/// "! Overdue": an icon and the word, never colour alone (§5.22F).
class OverdueLabel extends StatelessWidget {
  const OverdueLabel({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.error.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(FbRadius.chip),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: FbSpace.sm, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: context.colors.error),
          const SizedBox(width: FbSpace.xs),
          Text(
            context.l10n.moneyOverdue,
            style: context.text.caption.copyWith(
              color: context.colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One debt with its payments and changes (boards P8DebtDetail, P9LoanDetail,
/// P9CreditCard).
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(debtStatusesProvider);
    final status = async.value?.where((s) => s.debt.id == id).firstOrNull;
    if (async.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: FbErrorState(message: l10n.moneyLoadFailed),
      );
    }
    if (status == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const FbLoading() : FbEmptyHint(l10n.moneyNoDebts),
      );
    }
    final d = status.debt;
    final today = ref.watch(todayProvider);
    final actions = ref.read(moneyActionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          TextButton(
            onPressed: () => context.push(Routes.moneyEditDebt(id)),
            child: Text(l10n.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
        children: [
          if (d.isCard)
            ..._cardBody(context, ref, status)
          else
            ..._loanBody(context, ref, status, today),
          MoneySectionHeader(
            l10n.moneyPaymentsAndChanges,
            action: OutlinedButton.icon(
              onPressed: () => showFbSheet<void>(context, PaymentSheet(debtId: id)),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.moneyOtherPayment),
            ),
          ),
          _History(status: status),
          if (d.emi != null) ...[
            const SizedBox(height: FbSpace.sm),
            Text(l10n.moneyOverdueNote, style: context.text.caption),
          ],
          const SizedBox(height: FbSpace.lg),
          OutlinedButton(
            onPressed: () => actions.setSettled(id, settled: !d.settled),
            child: Text(d.settled ? l10n.moneyReopen : l10n.moneyMarkSettled),
          ),
        ],
      ),
    );
  }

  List<Widget> _loanBody(BuildContext context, WidgetRef ref, DebtStatus status, LocalDate today) {
    final l10n = context.l10n;
    final d = status.debt;
    final emi = d.emi;
    final iOwe = d.direction == DebtDirection.iOwe;
    final actions = ref.read(moneyActionsProvider);
    final correction = status.changes
        .where((c) => c.kind == LoanChangeKind.balanceCorrection)
        .fold<LoanChange?>(
          null,
          (a, c) => a == null || c.effectiveDate.isAfter(a.effectiveDate) ? c : a,
        );
    final overdue = emi != null && status.overdueOn(today);
    final n = status.nextInstalment;
    final paidCount = status.paidInstalments.length;
    final count = status.instalmentCount;
    return [
      Text(
        [
          iOwe ? l10n.moneyIOwe : l10n.moneyOwedToMe,
          if (d.counterparty != d.name) d.counterparty,
          kindLabel(l10n, d.kind),
          l10n.moneyStartedOn(longDate(d.startDate)),
          if (d.interestRateBp != null) l10n.moneyRateReference(rateLabel(d.interestRateBp!)),
        ].join(' · '),
        style: context.text.bodySmall,
      ),
      const SizedBox(height: FbSpace.md),
      if (overdue && n != null && !d.settled) ...[
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(FbRadius.card),
            border: Border.all(color: context.colors.error, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(FbSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: OverdueLabel()),
                const SizedBox(height: FbSpace.xs),
                Text(
                  l10n.moneyInstalmentAmount(n, formatRupees(status.nextEmiPaise ?? 0)),
                  style: context.text.bodyStrong,
                ),
                Text(
                  l10n.moneyOverdueLine(
                    context.shortDate(status.nextDue!),
                    today.daysSince(status.nextDue!),
                  ),
                  style: context.text.caption,
                ),
                const SizedBox(height: FbSpace.sm),
                Wrap(
                  spacing: FbSpace.sm,
                  runSpacing: FbSpace.sm,
                  children: [
                    FilledButton(
                      onPressed: () => _markPaid(context, ref, status),
                      child: Text(l10n.moneyMarkPaid),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await showFbConfirm(
                          context,
                          title: l10n.moneySkipTitle(n),
                          message: l10n.moneySkipMessage,
                          confirmLabel: l10n.moneySkip,
                          cancelLabel: l10n.cancel,
                        );
                        if (ok) await actions.skipInstalment(d.id, n);
                      },
                      child: Text(l10n.moneySkip),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FbSpace.md),
      ],
      FbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              correction != null
                  ? l10n.moneyOutstandingFrom(context.shortDate(correction.effectiveDate))
                  : emi != null
                  ? l10n.moneyRemainingEmi
                  : l10n.moneyOutstanding,
              style: context.text.caption,
            ),
            Text(
              formatRupees(correction != null ? status.outstandingPaise : status.remainingPaise),
              style: context.text.displayMetric,
            ),
            if (emi != null && count > 0) ...[
              const SizedBox(height: FbSpace.sm),
              MoneyBar(
                fraction: paidCount / count,
                semanticLabel: l10n.moneyInstalmentsA11y(paidCount, count),
              ),
              const SizedBox(height: FbSpace.sm),
              Text(
                [
                  l10n.moneyEmiProgress2(
                    paidCount,
                    count,
                    status.instalmentsLeft,
                    monthYear(status.endsOn!),
                  ),
                  if (status.overdueCount(today) > 0)
                    l10n.moneyOverdueCount(status.overdueCount(today)),
                ].join(' · '),
                style: context.text.bodySmall,
              ),
              Text(
                l10n.moneyEmiPaidSoFar(
                  formatRupees(d.principalPaise),
                  formatRupees(status.paidPaise),
                ),
                style: context.text.caption,
              ),
            ] else if (emi == null)
              Text(
                [
                  iOwe
                      ? l10n.moneyOriginalRepaid(
                          formatRupees(d.principalPaise),
                          formatRupees(status.paidPaise),
                        )
                      : l10n.moneyOriginalReceived(
                          formatRupees(d.principalPaise),
                          formatRupees(status.paidPaise),
                        ),
                  if (d.dueDate != null) l10n.moneyDueOn(longDate(d.dueDate!)),
                ].join(' · '),
                style: context.text.bodySmall,
              ),
          ],
        ),
      ),
      if (emi != null && n != null && !overdue && !d.settled) ...[
        const SizedBox(height: FbSpace.md),
        FbCard(
          child: Row(
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.moneyNextEmi(formatRupees(status.nextEmiPaise ?? emi.emiPaise)),
                        style: context.text.bodyStrong,
                      ),
                      Text(
                        l10n.moneyNextEmiLine(context.shortDate(status.nextDue!), n),
                        style: context.text.caption,
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => _markPaid(context, ref, status),
                child: Text(l10n.moneyMarkPaid),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: FbSpace.md),
      _ActionGrid(
        items: [
          if (emi != null) (l10n.moneySchedule, () => context.push(Routes.moneySchedule(d.id))),
          if (emi != null && !d.settled)
            (
              l10n.moneyPartPayment,
              () => showFbSheet<void>(context, PartPaymentSheet(status: status)),
            ),
          if (emi != null && !d.settled)
            (
              l10n.moneyChangeRate,
              () => showFbSheet<void>(context, RateChangeSheet(status: status)),
            ),
          if (!d.settled)
            (
              l10n.moneyCorrectOutstanding,
              () => showFbSheet<void>(context, CorrectionSheet(status: status)),
            ),
        ],
      ),
      if (emi != null || iOwe) ...[
        const SizedBox(height: FbSpace.md),
        FbListCard(
          children: [
            if (emi != null && iOwe)
              FbSwitchRow(
                title: l10n.moneyEmiReminder,
                subtitle: l10n.moneyEmiReminderLine(d.remindDaysBefore, emi.day),
                value: d.remind,
                onChanged: (v) => actions.saveDebt(d.copyWith(remind: v)),
              ),
            if (iOwe)
              FbSwitchRow(
                title: l10n.moneyRecordAsExpense,
                subtitle: l10n.moneyRecordAsExpenseLine,
                value: d.recordAsExpense,
                onChanged: (v) => actions.saveDebt(d.copyWith(recordAsExpense: v)),
              ),
          ],
        ),
      ],
    ];
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref, DebtStatus status) async {
    final l10n = context.l10n;
    final r = await ref
        .read(moneyActionsProvider)
        .addPayment(
          status.debt.id,
          amountPaise: status.nextEmiPaise ?? status.debt.emi!.emiPaise,
          at: ref.read(clockProvider).now(),
          instalmentNo: status.nextInstalment,
        );
    if (context.mounted) {
      showFbSnackBar(context, r.isOk ? l10n.moneyPaymentSaved : l10n.errSaveFailed);
    }
  }

  List<Widget> _cardBody(BuildContext context, WidgetRef ref, DebtStatus status) {
    final l10n = context.l10n;
    final d = status.debt;
    final card = CardStatus(
      d,
      ref.watch(cardStatementsProvider).value ?? const [],
      ref.watch(debtPaymentsProvider).value ?? const [],
      ref.watch(cardExpensesProvider).value ?? const [],
    );
    final s = card.latest;
    final limit = d.creditLimitPaise;
    return [
      Text(
        limit == null
            ? l10n.moneyCardLineNoLimit(d.statementDay ?? 1, d.cardDueDay ?? 1)
            : l10n.moneyCardLine(formatRupees(limit), d.statementDay ?? 1, d.cardDueDay ?? 1),
        style: context.text.bodySmall,
      ),
      const SizedBox(height: FbSpace.md),
      if (s == null)
        FbCard(
          dashed: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.moneyNoStatement, style: context.text.body),
              const SizedBox(height: FbSpace.sm),
              FilledButton(
                onPressed: () => showFbSheet<void>(context, StatementSheet(card: d)),
                child: Text(l10n.moneyNewStatement),
              ),
            ],
          ),
        )
      else
        FbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.moneyStatementOf(
                  context.shortDate(s.statementDate),
                  context.shortDate(s.dueDate),
                ),
                style: context.text.caption,
              ),
              const SizedBox(height: FbSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: _Figure(label: l10n.moneyTotalDue, value: formatRupees(s.totalDuePaise)),
                  ),
                  Expanded(
                    child: _Figure(label: l10n.moneyMinimumDue, value: formatRupees(s.minDuePaise)),
                  ),
                ],
              ),
              const SizedBox(height: FbSpace.sm),
              MoneyBar(
                fraction: s.totalDuePaise == 0 ? 1 : card.paidPaise / s.totalDuePaise,
                semanticLabel: l10n.moneyCardPaidA11y(
                  formatRupees(card.paidPaise),
                  formatRupees(s.totalDuePaise),
                ),
              ),
              const SizedBox(height: FbSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.moneyCardPaidLine(formatRupees(card.paidPaise), formatRupees(card.leftPaise))} · '
                      '${card.minimumMet ? l10n.moneyMinimumMet : l10n.moneyMinimumNotMet}',
                      style: context.text.bodySmall,
                    ),
                  ),
                  Icon(
                    card.minimumMet
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: card.minimumMet ? context.colors.primary : context.colors.error,
                  ),
                ],
              ),
              const SizedBox(height: FbSpace.sm),
              Wrap(
                spacing: FbSpace.sm,
                runSpacing: FbSpace.sm,
                children: [
                  FilledButton(
                    onPressed: () => showFbSheet<void>(
                      context,
                      PaymentSheet(
                        debtId: d.id,
                        initialPaise: card.leftPaise > 0 ? card.leftPaise : null,
                      ),
                    ),
                    child: Text(l10n.moneyRecordPayment),
                  ),
                  OutlinedButton(
                    onPressed: () => showFbSheet<void>(context, StatementSheet(card: d)),
                    child: Text(l10n.moneyNewStatement),
                  ),
                ],
              ),
            ],
          ),
        ),
      const SizedBox(height: FbSpace.md),
      FbCard(
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s == null
                    ? l10n.moneySpentOnCardEver
                    : l10n.moneySpentOnCard(context.shortDate(s.statementDate)),
                style: context.text.caption,
              ),
              Text(formatRupees(card.spentSincePaise), style: context.text.title),
              Text(
                [
                  l10n.moneyCardSpendLine(card.spentSinceCount),
                  if (card.unusedLimitPaise != null)
                    l10n.moneyUnusedLimit(formatRupees(card.unusedLimitPaise!)),
                ].join(' · '),
                style: context.text.caption,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.caption),
        Text(value, style: context.text.title),
      ],
    ),
  );
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.items});
  final List<(String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final half = (c.maxWidth - FbSpace.sm) / 2;
      final wide = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      return Wrap(
        spacing: FbSpace.sm,
        runSpacing: FbSpace.sm,
        children: [
          for (final (label, onTap) in items)
            SizedBox(
              width: wide ? c.maxWidth : half,
              child: OutlinedButton(
                onPressed: onTap,
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
        ],
      );
    },
  );
}

/// Payments, loan changes and skipped instalments, newest first.
class _History extends ConsumerWidget {
  const _History({required this.status});
  final DebtStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final id = status.debt.id;
    final actions = ref.read(moneyActionsProvider);
    final payments = [
      for (final p in ref.watch(debtPaymentsProvider).value ?? const <DebtPayment>[])
        if (p.debtId == id) p,
    ];
    final skips = [
      for (final s in ref.watch(instalmentSkipsProvider).value ?? const <InstalmentSkip>[])
        if (s.debtId == id) s,
    ];
    final linked = {for (final c in status.changes) ?c.paymentId};
    final rows = <(LocalDate, Widget)>[
      for (final p in payments)
        if (!linked.contains(p.id))
          (
            p.localDate,
            FbListRow(
              title: p.instalmentNo == null
                  ? l10n.moneyPayment
                  : l10n.moneyInstalmentN(p.instalmentNo!),
              subtitle: [longDate(p.localDate), ?p.note].join(' · '),
              trailing: Text(formatRupees(p.amountPaise), style: context.text.bodyStrong),
              onTap: () async {
                final ok = await showFbConfirm(
                  context,
                  title: l10n.moneyDeletePaymentTitle,
                  message: l10n.moneyDeletePaymentMessage,
                  confirmLabel: l10n.delete,
                  cancelLabel: l10n.cancel,
                  destructive: true,
                );
                if (ok) await actions.deletePayment(p.id);
              },
            ),
          ),
      for (final c in status.changes)
        (
          c.effectiveDate,
          FbListRow(
            title: switch (c.kind) {
              LoanChangeKind.balanceCorrection => l10n.moneyBalanceCorrected,
              LoanChangeKind.rateChange => l10n.moneyRateChanged,
              LoanChangeKind.prepayment =>
                c.mode == PrepayMode.reduceEmi
                    ? l10n.moneyPartPaymentLower
                    : l10n.moneyPartPaymentFewer,
            },
            subtitle: switch (c.kind) {
              LoanChangeKind.balanceCorrection => l10n.moneyCorrectionLine(
                longDate(c.effectiveDate),
                formatRupees(c.amountPaise ?? 0),
              ),
              LoanChangeKind.rateChange => l10n.moneyRateChangeLine(
                c.fromInstalment ?? 1,
                [
                  if (c.rateBp != null) '${rateLabel(c.rateBp!)}%',
                  if (c.emiPaise != null) 'EMI ${formatRupees(c.emiPaise!)}',
                ].join(' · '),
              ),
              LoanChangeKind.prepayment => longDate(c.effectiveDate),
            },
            trailing: c.kind == LoanChangeKind.prepayment
                ? Text(formatRupees(c.amountPaise ?? 0), style: context.text.bodyStrong)
                : Text(
                    c.kind == LoanChangeKind.balanceCorrection
                        ? l10n.moneyCorrection
                        : l10n.moneyChange,
                    style: context.text.caption,
                  ),
            onTap: () async {
              final ok = await showFbConfirm(
                context,
                title: l10n.moneyDeleteChangeTitle,
                message: l10n.moneyDeleteChangeMessage,
                confirmLabel: l10n.delete,
                cancelLabel: l10n.cancel,
                destructive: true,
              );
              if (ok) await actions.deleteLoanChange(c.id);
            },
          ),
        ),
      for (final s in skips)
        (
          s.skippedOn,
          FbListRow(
            title: l10n.moneyInstalmentN(s.instalmentNo),
            subtitle: '${l10n.moneySkipped} · ${longDate(s.skippedOn)}',
            trailing: TextButton(
              onPressed: () => actions.unskipInstalment(s.id),
              child: Text(l10n.moneyUndoSkip),
            ),
          ),
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    if (rows.isEmpty) return FbEmptyHint(l10n.moneyNoPayments, boxed: true);
    return FbListCard(children: [for (final r in rows) r.$2]);
  }
}
