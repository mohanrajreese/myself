import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/routine_labels.dart';
import '../../../app/routine_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/activity.dart';
import '../domain/activity_day.dart';
import '../../../app/routine/activity_log_sheet.dart';

/// History and logging for one activity (approved design "Activity detail").
/// Shows consistency without streaks (04 §7).
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final all = ref.watch(activitiesProvider);
    final a = ref.watch(activityProvider(id));
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: all.isLoading ? const FbLoading() : FbErrorState(message: l10n.activityMissing),
      );
    }
    final today = ref.watch(todayProvider);
    final from = today.addDays(-27);
    final logs = ref.watch(activityLogsBetweenProvider((from: from, to: today))).value;
    final history = ref.watch(activityHistoryProvider(id)).value;
    final t = ref.read(clockProvider).now().toLocal();
    final now = (date: LocalDate.fromDateTime(t), minute: t.hour * 60 + t.minute);
    final days = logs == null
        ? null
        : [
            for (var d = from; !d.isAfter(today); d = d.addDays(1))
              ActivityDay.of(a, d, [
                for (final l in logs)
                  if (l.activityId == id) l,
              ], now: now),
          ];
    final scheduled = days?.where((d) => d.scheduled && d.date != today).toList() ?? const [];
    final doneDays = scheduled.where((d) => d.summary == DayState.done).length;
    final todaySlot = days?.last.slots
        .where((s) => s.state == SlotState.due || s.state == SlotState.missed)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          TextButton(
            onPressed: () => context.push(Routes.editActivity(id)),
            child: Text(l10n.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    scheduleSummary(context, a.schedule),
                    trackingTypeName(l10n, a.trackingType),
                    if (a.targetMilli != null) _target(context, a),
                    a.isEssential ? l10n.essential : l10n.optionalPriority,
                    if (a.archived) l10n.archived,
                  ].join(' · '),
                  style: context.text.caption,
                ),
                if (!a.archived) ...[
                  const SizedBox(height: FbSpace.md),
                  Wrap(
                    spacing: FbSpace.sm,
                    runSpacing: FbSpace.sm,
                    children: [
                      if (a.stopwatchEnabled)
                        FilledButton(
                          onPressed: () => context.push(Routes.activityTimer(id)),
                          child: Text(l10n.startStopwatch),
                        ),
                      OutlinedButton(
                        onPressed: () => showActivityLogSheet(context, a, slot: todaySlot?.minute),
                        child: Text(l10n.logAction),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: FbSectionTitle(l10n.last4Weeks)),
                    if (scheduled.isNotEmpty)
                      Text(
                        l10n.doneOfScheduledDays(doneDays, scheduled.length),
                        style: context.text.caption,
                      ),
                  ],
                ),
                const SizedBox(height: FbSpace.md),
                if (days == null) const FbLoading() else _Calendar(days: days),
                const SizedBox(height: FbSpace.md),
                const Wrap(
                  spacing: FbSpace.md,
                  runSpacing: FbSpace.xs,
                  children: [
                    SlotBadge(SlotState.done),
                    SlotBadge(SlotState.missed),
                    SlotBadge(SlotState.skipped),
                    SlotBadge(null),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.historyTitle),
          const SizedBox(height: FbSpace.sm),
          if (history == null)
            const FbLoading()
          else if (history.isEmpty)
            FbEmptyHint(l10n.noHistoryYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final log in history)
                  FbListRow(
                    title:
                        '${context.dayLabel(log.localDate, today: today)} · ${context.time(log.occurredAt)}',
                    subtitle: _logSummary(context, a, log),
                    trailing: IconButton(
                      tooltip: l10n.editEntryLabel(context.shortDate(log.localDate)),
                      onPressed: () => showActivityLogSheet(context, a, existing: log),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _target(BuildContext context, Activity a) {
    final l10n = context.l10n;
    final t = a.targetMilli!;
    return switch (a.trackingType) {
      TrackingType.duration || TrackingType.stopwatch => l10n.targetMinutes(t ~/ 60000),
      _ => l10n.targetValue('${t ~/ 1000}${a.targetUnit == null ? '' : ' ${a.targetUnit}'}'),
    };
  }

  static String _logSummary(BuildContext context, Activity a, ActivityLog log) {
    final l10n = context.l10n;
    if (log.status == ActivityLogStatus.skipped) {
      return log.notes == null ? l10n.stateSkipped : '${l10n.stateSkipped} · ${log.notes}';
    }
    final value = switch (a.trackingType) {
      TrackingType.count =>
        log.countValue == null
            ? null
            : '${log.countValue}${a.targetUnit == null ? '' : ' ${a.targetUnit}'}',
      TrackingType.numeric =>
        log.numericValueMilli == null
            ? null
            : '${log.numericValueMilli! / 1000} ${log.unit ?? ''}'.trim(),
      TrackingType.duration || TrackingType.stopwatch =>
        log.durationS == null ? null : context.duration(Duration(seconds: log.durationS!)),
      TrackingType.checklist => l10n.checklistProgress(
        log.checklistDone?.length ?? 0,
        a.checklistItems.length,
      ),
      _ => null,
    };
    final source = log.source == LogSource.timer
        ? l10n.sourceTimer
        : (log.source == LogSource.notification ? l10n.sourceNotification : null);
    return [value ?? l10n.stateDone, ?source, ?log.notes].join(' · ');
  }
}

/// 28 days, oldest first, Monday-aligned rows of seven.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.days});
  final List<ActivityDay> days;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final counts = {for (final s in DayState.values) s: days.where((d) => d.summary == s).length};
    return Semantics(
      label: l10n.calendarSummary(
        counts[DayState.done]!,
        counts[DayState.missed]!,
        counts[DayState.skipped]!,
        counts[DayState.notScheduled]!,
      ),
      excludeSemantics: true,
      child: GridView.count(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final d in days)
            switch (d.summary) {
              DayState.done => _cell(
                c.success,
                c.success,
                Icon(Icons.check_rounded, size: 14, color: c.onPrimary),
              ),
              DayState.skipped => _cell(
                c.surfaceVariant,
                c.textSecondary,
                Icon(Icons.redo_rounded, size: 14, color: c.textSecondary),
              ),
              DayState.notScheduled => _cell(Colors.transparent, c.outline, null, dashed: true),
              DayState.missed => _cell(c.surface, c.textSecondary, null, dashed: true),
              DayState.inProgress || DayState.due => _cell(
                c.surface,
                c.primary,
                Icon(Icons.schedule_rounded, size: 14, color: c.primary),
              ),
            },
        ],
      ),
    );
  }

  Widget _cell(Color fill, Color border, Widget? child, {bool dashed = false}) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border, width: dashed ? 1 : 1.5),
    ),
    child: Center(child: child),
  );
}
