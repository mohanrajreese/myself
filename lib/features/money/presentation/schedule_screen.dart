import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import 'money_common.dart';

/// Interest, principal and balance per instalment (board P9Schedule, §5.22G).
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({required this.id, super.key});
  final String id;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  bool _paid = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(debtStatusesProvider);
    final s = async.value?.where((s) => s.debt.id == widget.id).firstOrNull;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.moneyScheduleTitle)),
        body: async.hasError ? FbErrorState(message: l10n.moneyLoadFailed) : const FbLoading(),
      );
    }
    final today = ref.watch(todayProvider);
    final hasRate = s.schedule.any((r) => r.interestPaise != null);
    final rows = [
      for (final r in s.schedule)
        if (s.paidInstalments.contains(r.n) == _paid) r,
    ];
    final upcoming = [
      for (final r in s.schedule)
        if (!s.paidInstalments.contains(r.n)) r,
    ];
    final interestLeft = upcoming.fold(0, (n, r) => n + (r.interestPaise ?? 0));
    final principalLeft = upcoming.fold(0, (n, r) => n + (r.principalPaise ?? 0));
    final style = context.text.bodySmall;
    final head = context.text.caption.copyWith(fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneyScheduleTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
        children: [
          Text(
            [
              s.debt.name,
              s.debt.counterparty,
              if (s.debt.interestRateBp != null)
                l10n.moneyRateSummary(
                  rateLabel(s.debt.interestRateBp!),
                  formatRupees(s.debt.emi!.emiPaise),
                ),
            ].join(' · '),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: FbSpace.md),
          if (hasRate)
            Row(
              children: [
                Expanded(
                  child: _Box(label: l10n.moneyInterestLeft, value: formatRupees(interestLeft)),
                ),
                const SizedBox(width: FbSpace.sm),
                Expanded(
                  child: _Box(label: l10n.moneyPrincipalLeft, value: formatRupees(principalLeft)),
                ),
              ],
            )
          else
            FbNotice(l10n.moneyScheduleNoRate),
          const SizedBox(height: FbSpace.md),
          FbSegmented<bool>(
            options: {false: l10n.moneyUpcoming, true: l10n.moneyPaidTab},
            selected: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            padding: const EdgeInsets.symmetric(horizontal: FbSpace.sm, vertical: FbSpace.xs),
            child: Column(
              children: [
                _Row(
                  cells: [
                    l10n.moneyColNo,
                    l10n.moneyColDue,
                    if (hasRate) ...[
                      l10n.moneyColInterest,
                      l10n.moneyColPrincipal,
                      l10n.moneyColBalance,
                    ] else
                      l10n.moneyColEmi,
                  ],
                  style: head,
                ),
                for (final r in rows)
                  _Row(
                    cells: [
                      '${r.n}',
                      context.shortDate(r.due),
                      if (hasRate) ...[
                        formatRupees(r.interestPaise!, wholeOnly: true),
                        formatRupees(r.principalPaise!, wholeOnly: true),
                        formatRupees(r.balancePaise!, wholeOnly: true),
                      ] else
                        formatRupees(r.emiPaise),
                    ],
                    style: style,
                    overdue: !_paid && r.due.isBefore(today) && !s.skippedInstalments.contains(r.n),
                    skipped: s.skippedInstalments.contains(r.n),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.sm),
          Text(l10n.moneyScheduleNote, style: context.text.caption),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => FbCard(
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.caption),
          Text(value, style: context.text.title),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    required this.style,
    this.overdue = false,
    this.skipped = false,
  });
  final List<String> cells;
  final TextStyle style;
  final bool overdue;
  final bool skipped;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              flex: i == 0 ? 2 : 3,
              child: Column(
                crossAxisAlignment: i < 2 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(c, style: style, textAlign: i < 2 ? TextAlign.start : TextAlign.end),
                  if (i == 0 && overdue)
                    Text(
                      '! ${context.l10n.moneyOverdue}',
                      style: context.text.caption.copyWith(color: context.colors.error),
                    ),
                  if (i == 0 && skipped)
                    Text(context.l10n.moneySkipped, style: context.text.caption),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
