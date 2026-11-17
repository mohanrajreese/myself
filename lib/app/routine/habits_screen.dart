import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/fb_format.dart';
import '../providers.dart';
import '../routes.dart';
import '../routine_actions.dart';
import '../routine_labels.dart';
import '../routine_providers.dart';
import '../../core/widgets/fb_card.dart';
import '../../core/widgets/fb_choice.dart';
import '../../core/widgets/fb_sheet.dart';
import '../../core/widgets/fb_states.dart';
import '../../core/widgets/l10n.dart';
import '../../core/widgets/tokens.dart';
import '../../features/reminders/presentation/reminder_list.dart';
import '../../features/activities/domain/activity.dart';
import '../../features/activities/domain/activity_day.dart';
import 'activity_log_sheet.dart';

enum HabitsTab { today, activities, reminders }

/// Habits tab (approved design "Habits: today / activities / reminders").
class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  HabitsTab _tab = HabitsTab.today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reminders = _tab == HabitsTab.reminders;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabHabits),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
              onPressed: () => context.push(reminders ? Routes.newReminder : Routes.newActivity),
              icon: const Icon(Icons.add_rounded),
              label: Text(reminders ? l10n.reminderShort : l10n.activityShort),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.xs, FbSpace.lg, FbSpace.md),
            child: FbSegmented<HabitsTab>(
              options: {
                HabitsTab.today: l10n.today,
                HabitsTab.activities: l10n.activitiesTitle,
                HabitsTab.reminders: l10n.remindersTitle,
              },
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              HabitsTab.today => const _TodayList(),
              HabitsTab.activities => const _ActivityList(),
              HabitsTab.reminders => const ReminderList(),
            },
          ),
        ],
      ),
    );
  }
}

class _TodayList extends ConsumerWidget {
  const _TodayList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final days = ref.watch(activityDaysProvider(today));
    if (days == null) return const FbLoading();
    if (days.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FbSpace.lg),
        children: [
          FbEmptyHint(l10n.activitiesEmpty, boxed: true),
          const SizedBox(height: FbSpace.md),
          OutlinedButton(
            onPressed: () => context.push(Routes.newActivity),
            child: Text(l10n.createActivity),
          ),
        ],
      );
    }
    final rows = [
      for (final d in days)
        for (final s in d.slots) (d, s),
    ]..sort((a, b) => a.$2.minute.compareTo(b.$2.minute));
    final unscheduled = [
      for (final d in days)
        if (!d.scheduled) d,
    ];
    final done = rows.where((r) => r.$2.state == SlotState.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
      children: [
        Row(
          children: [
            Expanded(child: Text(context.dayLabel(today), style: context.text.bodyStrong)),
            if (rows.isNotEmpty)
              Text(l10n.doneOfTotal(done, rows.length), style: context.text.caption),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        if (rows.isEmpty)
          FbEmptyHint(l10n.nothingScheduledToday, boxed: true)
        else
          FbListCard(
            children: [for (final (d, s) in rows) SlotRow(day: d, slot: s)],
          ),
        if (unscheduled.isNotEmpty) ...[
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.notScheduledToday),
          const SizedBox(height: FbSpace.sm),
          FbListCard(
            children: [
              for (final d in unscheduled)
                FbListRow(
                  title: d.activity.name,
                  subtitle: d.extraLogs.isEmpty
                      ? scheduleSummary(context, d.activity.schedule)
                      : l10n.loggedTimes(d.extraLogs.length),
                  leading: Icon(activityIcon(d.activity.iconKey)),
                  onTap: () => context.push(Routes.activity(d.activity.id)),
                  trailing: OutlinedButton(
                    onPressed: () => showActivityLogSheet(context, d.activity),
                    child: Text(l10n.logAnyway),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FbSpace.sm),
          Text(l10n.notScheduledNote, style: context.text.caption),
        ],
      ],
    );
  }
}

/// One scheduled occurrence with its state and the quickest action.
class SlotRow extends ConsumerWidget {
  const SlotRow({required this.day, required this.slot, this.showSnooze = false, super.key});
  final ActivityDay day;
  final Slot slot;
  final bool showSnooze;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final a = day.activity;
    final target = a.targetMilli;
    final progress = switch (a.trackingType) {
      TrackingType.count when target != null => l10n.countProgress(
        slot.progressMilli ~/ 1000,
        target ~/ 1000,
      ),
      TrackingType.duration || TrackingType.stopwatch when target != null => l10n.durationProgress(
        slot.progressMilli ~/ 60000,
        target ~/ 60000,
      ),
      TrackingType.checklist => l10n.checklistProgress(
        {for (final log in slot.logs) ...?log.checklistDone}.length,
        a.checklistItems.length,
      ),
      _ => a.isEssential ? l10n.essential : trackingTypeName(l10n, a.trackingType),
    };
    final open = slot.state != SlotState.done && slot.state != SlotState.skipped;
    Widget? action;
    if (open) {
      action = switch (a.trackingType) {
        TrackingType.boolean || TrackingType.eventLog => OutlinedButton(
          onPressed: () => quickLog(context, ref, a, slot: slot.minute),
          child: Text(l10n.markDone),
        ),
        TrackingType.count => OutlinedButton(
          onPressed: () => quickLog(context, ref, a, slot: slot.minute, count: 1),
          child: Text(l10n.plusOne, semanticsLabel: l10n.addOneTo(a.name)),
        ),
        TrackingType.duration || TrackingType.stopwatch when a.stopwatchEnabled => OutlinedButton(
          onPressed: () => context.push(Routes.activityTimer(a.id)),
          child: Text(l10n.start),
        ),
        _ => OutlinedButton(
          onPressed: () => showActivityLogSheet(context, a, slot: slot.minute),
          child: Text(l10n.logAction),
        ),
      };
    }
    return InkWell(
      onTap: () => context.push(Routes.activity(a.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FbSize.touch + FbSpace.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(minuteLabel(context, slot.minute), style: context.text.caption),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: context.text.bodyStrong),
                    Text(progress, style: context.text.caption),
                    const SizedBox(height: 2),
                    SlotBadge(
                      slot.state,
                      text: slot.state == SlotState.missed
                          ? l10n.notLoggedAt(minuteLabel(context, slot.minute))
                          : null,
                    ),
                  ],
                ),
              ),
              if (showSnooze && open)
                IconButton(
                  tooltip: l10n.actionSnooze,
                  onPressed: () => _snooze(context, ref, a),
                  icon: const Icon(Icons.snooze_rounded),
                ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref, Activity a) async {
    final minutes = await showFbSheet<int>(context, const SnoozeSheet());
    if (minutes != null && context.mounted) await snoozeActivity(context, ref, a, minutes);
  }
}

/// Snooze presets plus a custom number of minutes (§5.15D).
class SnoozeSheet extends StatefulWidget {
  const SnoozeSheet({super.key});

  @override
  State<SnoozeSheet> createState() => _SnoozeSheetState();
}

class _SnoozeSheetState extends State<SnoozeSheet> {
  String _custom = '';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.snoozeFor,
      children: [
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final m in const [5, 10, 15, 30])
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(m),
                child: Text(l10n.minutesShort(m)),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.lg),
        TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.customMinutes,
            suffixText: l10n.unitMin,
            errorText: _error,
          ),
          onChanged: (v) => _custom = v,
        ),
        const SizedBox(height: FbSpace.md),
        FilledButton(
          onPressed: () {
            final m = int.tryParse(_custom.trim());
            if (m == null || m < 1 || m > 720) {
              setState(() => _error = l10n.errOutOfRange);
              return;
            }
            Navigator.of(context).pop(m);
          },
          child: Text(l10n.actionSnooze),
        ),
      ],
    );
  }
}

class _ActivityList extends ConsumerStatefulWidget {
  const _ActivityList();

  @override
  ConsumerState<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends ConsumerState<_ActivityList> {
  bool _archived = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = ref.watch(activitiesProvider);
    final list = all.value;
    if (list == null) {
      return all.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading();
    }
    final active = [
      for (final a in list)
        if (!a.archived) a,
    ];
    final archived = [
      for (final a in list)
        if (a.archived) a,
    ];
    final shown = _archived ? archived : active;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg),
          child: Row(
            children: [
              FbToggleChip(
                label: l10n.activeCount(active.length),
                selected: !_archived,
                onTap: () => setState(() => _archived = false),
              ),
              const SizedBox(width: FbSpace.sm),
              FbToggleChip(
                label: l10n.archivedCount(archived.length),
                selected: _archived,
                onTap: () => setState(() => _archived = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: FbSpace.md),
        Expanded(
          child: shown.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg),
                  children: [
                    FbEmptyHint(_archived ? l10n.archivedEmpty : l10n.activitiesEmpty, boxed: true),
                  ],
                )
              : ReorderableListView(
                  padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => _reorder(shown, from, to),
                  footer: Padding(
                    padding: const EdgeInsets.only(top: FbSpace.sm),
                    child: Text(l10n.activityListHelp, style: context.text.caption),
                  ),
                  children: [
                    for (final (i, a) in shown.indexed)
                      Card(
                        key: ValueKey(a.id),
                        margin: const EdgeInsets.only(bottom: FbSpace.sm),
                        child: FbListRow(
                          title: a.name,
                          subtitle:
                              '${scheduleSummary(context, a.schedule)} · ${trackingTypeName(l10n, a.trackingType)}'
                              '${a.isEssential ? ' · ${l10n.essential}' : ''}',
                          leading: _archived
                              ? Icon(activityIcon(a.iconKey))
                              : ReorderableDragStartListener(
                                  index: i,
                                  child: Semantics(
                                    label: l10n.reorderHandle(a.name),
                                    child: const SizedBox(
                                      width: FbSize.touch,
                                      height: FbSize.touch,
                                      child: Icon(Icons.drag_indicator_rounded),
                                    ),
                                  ),
                                ),
                          onTap: () => context.push(Routes.activity(a.id)),
                          trailing: _Menu(activity: a),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _reorder(List<Activity> shown, int from, int to) async {
    final ids = [for (final a in shown) a.id];
    final moved = ids.removeAt(from);
    ids.insert(to, moved);
    await ref.read(activityRepositoryProvider).reorder(ids);
  }
}

enum _Action { edit, duplicate, reschedule, priority, archive, restore, delete }

class _Menu extends ConsumerWidget {
  const _Menu({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final a = activity;
    return PopupMenuButton<_Action>(
      tooltip: l10n.moreActions(a.name),
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (_) => [
        PopupMenuItem(value: _Action.edit, child: Text(l10n.edit)),
        PopupMenuItem(value: _Action.duplicate, child: Text(l10n.duplicateMeal)),
        if (!a.archived) PopupMenuItem(value: _Action.reschedule, child: Text(l10n.reschedule)),
        if (!a.archived)
          PopupMenuItem(
            value: _Action.priority,
            child: Text(a.isEssential ? l10n.makeOptional : l10n.makeEssential),
          ),
        PopupMenuItem(
          value: a.archived ? _Action.restore : _Action.archive,
          child: Text(a.archived ? l10n.restore : l10n.archive),
        ),
        PopupMenuItem(value: _Action.delete, child: Text(l10n.delete)),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, _Action action) async {
    final l10n = context.l10n;
    final repo = ref.read(activityRepositoryProvider);
    final a = activity;
    switch (action) {
      case _Action.edit || _Action.reschedule:
        unawaited(context.push(Routes.editActivity(a.id)));
      case _Action.duplicate:
        final r = await repo.duplicate(a.id, name: l10n.copyName(a.name));
        if (context.mounted) showFbSnackBar(context, r.isOk ? l10n.duplicated : l10n.errSaveFailed);
      case _Action.priority:
        await repo.update(
          a.copyWith(
            priority: a.isEssential ? ActivityPriority.optional : ActivityPriority.essential,
          ),
        );
      case _Action.archive || _Action.restore:
        await repo.setArchived(a.id, archived: action == _Action.archive);
        replanReminders(ref);
        if (context.mounted) {
          showFbSnackBar(context, action == _Action.archive ? l10n.archived : l10n.restored);
        }
      case _Action.delete:
        final ok = await showFbConfirm(
          context,
          title: l10n.deleteActivityTitle,
          message: l10n.deleteActivityMessage,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
        );
        if (!ok) return;
        await repo.delete(a.id);
        replanReminders(ref);
        if (context.mounted) showFbSnackBar(context, l10n.deleted);
    }
  }
}
