import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/scheduling/schedule_rule.dart';
import '../../core/utils/local_date.dart';
import '../../core/widgets/fb_sheet.dart';
import '../../core/widgets/fb_states.dart';
import '../../core/widgets/l10n.dart';
import '../../core/widgets/tokens.dart';
import '../../features/activities/domain/activity.dart';
import '../../features/activities/domain/activity_day.dart';
import '../../features/activities/domain/activity_repository.dart';
import '../providers.dart';
import '../routine_providers.dart';
import 'habits_screen.dart';

/// The standard hygiene routines (§5.10), created only when the user asks.
List<Activity> hygieneRoutines(AppLocalizations l, LocalDate today) {
  Activity make(String key, String name, String icon, ScheduleRule rule, [List<ChecklistItem> steps = const []]) =>
      Activity(
        id: '',
        name: name,
        category: 'hygiene',
        iconKey: icon,
        trackingType: steps.isEmpty ? TrackingType.boolean : TrackingType.checklist,
        priority: ActivityPriority.optional,
        schedule: rule,
        scheduleHistory: [ScheduleChange(from: today, rule: rule)],
        checklistItems: steps,
        systemKey: 'hygiene.$key',
      );
  return [
    make('bath', l.hygieneBath, 'brush', Daily(times: const [7 * 60])),
    make('head_wash', l.hygieneHeadWash, 'brush', Weekdays(weekdays: const {3, 6}, times: const [7 * 60])),
    make('brush_morning', l.hygieneBrushMorning, 'brush', Daily(times: const [7 * 60 + 30])),
    make('brush_night', l.hygieneBrushNight, 'brush', Daily(times: const [22 * 60])),
    make('floss', l.hygieneFloss, 'brush', Daily(times: const [22 * 60])),
    make('mouthwash', l.hygieneMouthwash, 'brush', Daily(times: const [22 * 60])),
    make('skin_morning', l.hygieneSkinMorning, 'skin', Daily(times: const [7 * 60 + 45]), [
      ChecklistItem('cleanse', l.stepCleanse),
      ChecklistItem('moisturise', l.stepMoisturise),
      ChecklistItem('sunscreen', l.stepSunscreen),
    ]),
    make('skin_evening', l.hygieneSkinEvening, 'skin', Daily(times: const [21 * 60 + 45]), [
      ChecklistItem('cleanse', l.stepCleanse),
      ChecklistItem('moisturise', l.stepMoisturise),
    ]),
  ];
}

bool _isHygiene(Activity a) =>
    !a.archived && (a.category == 'hygiene' || (a.systemKey?.startsWith('hygiene.') ?? false));

/// Hygiene routines for today (approved design).
class HygieneScreen extends ConsumerWidget {
  const HygieneScreen({super.key});

  Future<void> _seed(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(activityRepositoryProvider);
    final existing = {for (final a in await repo.watchAll().first) ?a.systemKey};
    for (final a in hygieneRoutines(l10n, ref.read(todayProvider))) {
      if (!existing.contains(a.systemKey)) await repo.create(a);
    }
    replanReminders(ref);
    if (context.mounted) showFbSnackBar(context, l10n.routinesAdded);
  }

  Future<void> _allDone(BuildContext context, WidgetRef ref, List<(ActivityDay, Slot)> open) async {
    final l10n = context.l10n;
    final repo = ref.read(activityRepositoryProvider);
    final now = ref.read(clockProvider).now();
    for (final (d, s) in open) {
      await repo.addLog(
        d.activity.id,
        LogDraft(
          status: ActivityLogStatus.completed,
          occurredAt: now,
          scheduledSlot: s.minute,
          checklistDone: d.activity.trackingType == TrackingType.checklist
              ? {for (final i in d.activity.checklistItems) i.id}
              : null,
        ),
      );
    }
    replanReminders(ref);
    if (context.mounted) showFbSnackBar(context, l10n.allMarkedDone);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final all = ref.watch(activityDaysProvider(today));
    if (all == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.hygiene)),
        body: const FbLoading(),
      );
    }
    final days = all.where((d) => _isHygiene(d.activity)).toList();
    final rows = [
      for (final d in days)
        for (final s in d.slots) (d, s),
    ]..sort((a, b) => a.$2.minute.compareTo(b.$2.minute));
    final open = [
      for (final r in rows)
        if (r.$2.state != SlotState.done && r.$2.state != SlotState.skipped) r,
    ];
    final hasStandard = days.any((d) => d.activity.systemKey?.startsWith('hygiene.') ?? false);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.hygiene)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (days.isEmpty) ...[
            FbEmptyHint(l10n.hygieneEmpty, boxed: true),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(l10n.doneOfTotal(rows.length - open.length, rows.length), style: context.text.bodyStrong),
                ),
                if (open.isNotEmpty)
                  TextButton(onPressed: () => _allDone(context, ref, open), child: Text(l10n.markAllDone)),
              ],
            ),
            const SizedBox(height: FbSpace.sm),
            if (rows.isEmpty)
              FbEmptyHint(l10n.nothingScheduledToday, boxed: true)
            else
              FbListCard(
                children: [for (final (d, s) in rows) SlotRow(day: d, slot: s)],
              ),
          ],
          if (!hasStandard) ...[
            const SizedBox(height: FbSpace.md),
            OutlinedButton(onPressed: () => _seed(context, ref), child: Text(l10n.addStandardRoutines)),
          ],
          const SizedBox(height: FbSpace.md),
          Text(l10n.hygieneNote, style: context.text.caption),
        ],
      ),
    );
  }
}
