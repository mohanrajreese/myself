import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../insights/domain/report.dart';
import '../../medication/domain/medication.dart';
import '../domain/private_records.dart';
import 'private_space_screens.dart' show habitName;

/// Private history, worked out on the phone after unlock (R-04, approved
/// design). Counts only; nothing here is synced or shown elsewhere.
class PrivateReportScreen extends ConsumerStatefulWidget {
  const PrivateReportScreen({super.key});

  @override
  ConsumerState<PrivateReportScreen> createState() => _PrivateReportScreenState();
}

class _PrivateReportScreenState extends ConsumerState<PrivateReportScreen> {
  ReportPeriod _period = ReportPeriod.month;
  DateRange? _custom;

  DateRange _range(LocalDate today) => switch (_period) {
    ReportPeriod.week => (from: today.addDays(-6), to: today),
    ReportPeriod.custom => _custom ?? (from: today.addDays(-29), to: today),
    _ => (from: today.addDays(-29), to: today),
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final today = ref.watch(todayProvider);
    final r = _range(today);
    final p = r.previous;
    final wide = (from: p.from, to: r.to);

    final types = ref.watch(habitTypesProvider).value ?? const <PrivateHabitType>[];
    final bowel = ref.watch(bowelLogsProvider(wide)).value ?? const <BowelLog>[];
    final meds = ref.watch(medicationsProvider).value ?? const <Medication>[];
    final doses = ref.watch(doseLogsProvider(r)).value ?? const <DoseLog>[];
    final activities = ref.watch(privateActivitiesProvider).value ?? const <PrivateActivity>[];

    int bowelIn(DateRange x) =>
        bowel.where((b) => x.contains(b.localDate)).fold(0, (n, b) => n + b.count);
    String perDay(int n, int days) => (n / days).toStringAsFixed(1);
    final nowMinute = ref.watch(clockProvider).now();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.privateHistory),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(lockControllerProvider.notifier).lockNow();
                context.pop();
              },
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(l.lockAction),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSegmented<ReportPeriod>(
            options: {
              ReportPeriod.week: l.week,
              ReportPeriod.month: l.month,
              ReportPeriod.custom: l.periodCustom,
            },
            selected: _period,
            onChanged: (v) async {
              if (v == ReportPeriod.custom) {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(today.year, today.month, today.day),
                );
                if (picked == null) return;
                setState(() {
                  _custom = (
                    from: LocalDate.fromDateTime(picked.start),
                    to: LocalDate.fromDateTime(picked.end),
                  );
                  _period = v;
                });
                return;
              }
              setState(() => _period = v);
            },
          ),
          const SizedBox(height: FbSpace.sm),
          Text(
            '${context.shortDate(r.from)} – ${context.shortDate(r.to)} · ${l.comparedWithDays(r.days)}',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: FbSpace.md),
          _Section(
            title: l.privateHabits,
            rows: [
              for (final t in types)
                _HabitRow(name: habitName(l, t), typeId: t.id, range: r, previous: p),
            ],
            footer: l.countsOnly,
          ),
          _Section(
            title: l.bowelLog,
            rows: [
              _Line(
                l.perDayLabel,
                l.valueWithPrevious(perDay(bowelIn(r), r.days), perDay(bowelIn(p), p.days)),
              ),
              _Line(
                l.normalHardLoose,
                [
                  for (final c in [Consistency.normal, Consistency.hard, Consistency.loose])
                    bowel.where((b) => r.contains(b.localDate) && b.consistency == c).length,
                ].join(' / '),
              ),
            ],
          ),
          _Section(
            title: l.medicationTitle,
            rows: [
              for (final m in meds)
                () {
                  var scheduled = 0;
                  for (final d in r.dates) {
                    if (d.isAfter(today)) break;
                    scheduled += dosesOn(
                      d,
                      [m],
                      doses,
                      today: today,
                      nowMinute: nowMinute.hour * 60 + nowMinute.minute,
                    ).where((x) => x.state != DoseState.due).length;
                  }
                  final mine = doses.where((x) => x.medicationId == m.id);
                  final taken = mine.where((x) => x.status == DoseStatus.taken).length;
                  final skipped = mine.where((x) => x.status == DoseStatus.skipped).length;
                  return _Line(m.name, l.takenOfScheduled(taken, scheduled, skipped));
                }(),
            ],
          ),
          _Section(
            title: l.privateActivities,
            rows: [for (final a in activities) _ActivityRow(activity: a, range: r, previous: p)],
          ),
          Text(l.privateReportNote, style: context.text.caption),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.footer});
  final String title;
  final List<Widget> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FbSpace.md),
    child: FbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.bodyStrong),
          const SizedBox(height: FbSpace.sm),
          if (rows.isEmpty)
            Text(context.l10n.nothingRecorded, style: context.text.bodySmall)
          else
            ...rows,
          if (footer != null) ...[
            const SizedBox(height: FbSpace.xs),
            Text(footer!, style: context.text.caption),
          ],
        ],
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: FbSpace.md,
        children: [
          Text(label, style: context.text.body),
          Text(value, style: context.text.bodyStrong),
        ],
      ),
    ),
  );
}

class _HabitRow extends ConsumerWidget {
  const _HabitRow({
    required this.name,
    required this.typeId,
    required this.range,
    required this.previous,
  });
  final String name;
  final String typeId;
  final DateRange range;
  final DateRange previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs =
        ref.watch(habitLogsProvider((type: typeId, from: previous.from, to: range.to))).value ??
        const <PrivateHabitLog>[];
    int sum(DateRange r) =>
        logs.where((x) => r.contains(x.localDate)).fold(0, (n, x) => n + x.count);
    return _Line(name, context.l10n.timesWithPrevious(sum(range), sum(previous)));
  }
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.activity, required this.range, required this.previous});
  final PrivateActivity activity;
  final DateRange range;
  final DateRange previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs =
        ref.watch(privateActivityLogsProvider(activity.id)).value ?? const <PrivateActivityLog>[];
    int n(DateRange r) => logs.where((x) => r.contains(x.localDate)).length;
    return _Line(activity.name, context.l10n.logsWithPrevious(n(range), n(previous)));
  }
}
