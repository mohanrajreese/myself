import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routine_actions.dart';
import '../../../app/routine_providers.dart';
import '../../../core/notifications/local_notification_gateway.dart';
import '../../../core/scheduling/occurrence_calculator.dart';
import '../../../core/scheduling/reminder_planner.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../../app/routine/schedule_editor.dart';
import '../../activities/domain/activity.dart';
import '../domain/reminder.dart';
import 'reminder_names.dart';

/// Reminder editor (approved design "Reminder editor").
class ReminderEditorScreen extends ConsumerStatefulWidget {
  const ReminderEditorScreen({this.id, super.key});
  final String? id;

  @override
  ConsumerState<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends ConsumerState<ReminderEditorScreen> {
  Reminder? _existing;
  late Reminder _r;
  bool _loaded = false;
  int _editorKey = 0;
  ScheduleRule? _rule;
  String? _error;
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final today = ref.read(todayProvider);
    final existing = widget.id == null
        ? null
        : await ref.read(reminderRepositoryProvider).byId(widget.id!);
    if (!mounted) return;
    final l10n = context.l10n;
    setState(() {
      _existing = existing;
      _r =
          existing ??
          reminderPreset(
            ReminderKind.custom,
            title: '',
            today: today,
          ).copyWith(rule: Daily(times: [9 * 60]));
      if (existing == null) _r = _r.copyWith(title: l10n.reminderDefaultTitle);
      _rule = _r.rule;
      _loaded = true;
    });
  }

  void _change(Reminder Function(Reminder) f) => setState(() {
    _r = f(_r);
    _dirty = true;
  });

  void _pickKind(ReminderKind kind) {
    final l10n = context.l10n;
    final title = switch (kind) {
      ReminderKind.water => l10n.presetWater,
      ReminderKind.workout => l10n.presetWorkout,
      ReminderKind.sleep => l10n.presetSleep,
      ReminderKind.posture => l10n.presetPosture,
      _ => _r.title,
    };
    final preset = reminderPreset(kind, title: title, today: ref.read(todayProvider));
    setState(() {
      _r = _r.copyWith(
        kind: kind,
        title: _existing == null ? title : _r.title,
        rule: _existing == null ? preset.rule : _r.rule,
        onlyIfIncomplete: kind == ReminderKind.activity && _r.onlyIfIncomplete,
      );
      _rule = _r.rule;
      _editorKey++;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_rule == null || _rule!.problems.isNotEmpty) {
      return setState(() => _error = l10n.errScheduleIncomplete);
    }
    final r = _r.copyWith(rule: _rule);
    final problems = r.problems;
    if (problems.isNotEmpty) {
      return setState(
        () => _error = switch (problems.first) {
          'title_required' => l10n.errTitleRequired,
          'activity_required' => l10n.errActivityRequired,
          _ => l10n.errCheckFields,
        },
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(reminderRepositoryProvider);
    final result = _existing == null ? (await repo.create(r)).map((_) {}) : await repo.update(r);
    if (!mounted) return;
    if (!result.isOk) {
      setState(() {
        _busy = false;
        _error = l10n.errSaveFailed;
      });
      return;
    }
    _dirty = false;
    await ensureNotificationPermission(context, ref);
    if (!mounted) return;
    if (r.alarm && !await ref.read(alarmCapabilitiesProvider).canScheduleExactAlarms() && mounted) {
      await askForExactAlarms(context, ref);
    }
    replanReminders(ref);
    if (!mounted) return;
    showFbSnackBar(context, l10n.reminderSaved);
    context.pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.deleteReminderTitle,
      message: l10n.deleteReminderMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    await ref.read(reminderRepositoryProvider).delete(_existing!.id);
    replanReminders(ref);
    if (!mounted) return;
    _dirty = false;
    showFbSnackBar(context, l10n.deleted);
    context.pop();
  }

  Future<void> _pickSnooze() async {
    final l10n = context.l10n;
    final m = await showFbSheet<int>(
      context,
      FbSheetBody(
        title: l10n.snoozeDefault,
        children: [
          for (final m in const [5, 10, 15, 30, 60])
            ListTile(title: Text(l10n.minutesShort(m)), onTap: () => Navigator.of(context).pop(m)),
        ],
      ),
    );
    if (m != null) _change((r) => r.copyWith(snoozeMinutes: m));
  }

  Future<void> _pickQuiet() async {
    final l10n = context.l10n;
    final b = await showFbSheet<QuietBehaviour>(
      context,
      FbSheetBody(
        title: l10n.duringQuietHours,
        children: [
          for (final b in QuietBehaviour.values)
            ListTile(
              title: Text(quietBehaviourName(l10n, b)),
              trailing: _r.quietBehaviour == b ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(b),
            ),
        ],
      ),
    );
    if (b != null) _change((r) => r.copyWith(quietBehaviour: b));
  }

  Future<void> _pickActivity() async {
    final l10n = context.l10n;
    final activities = [
      for (final a in ref.read(activitiesProvider).value ?? const <Activity>[])
        if (!a.archived) a,
    ];
    final picked = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.linkedActivity,
        children: [
          if (activities.isEmpty) FbEmptyHint(l10n.activitiesEmpty),
          ListTile(title: Text(l10n.noActivity), onTap: () => Navigator.of(context).pop('')),
          for (final a in activities)
            ListTile(title: Text(a.name), onTap: () => Navigator.of(context).pop(a.id)),
        ],
      ),
    );
    if (picked == null) return;
    _change(
      (r) => r.copyWith(
        activityId: () => picked.isEmpty ? null : picked,
        onlyIfIncomplete: picked.isEmpty ? false : r.onlyIfIncomplete,
        kind: picked.isEmpty && r.kind == ReminderKind.activity ? ReminderKind.custom : r.kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_loaded) return const Scaffold(body: FbLoading());
    final activities = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final linked = activities.where((a) => a.id == _r.activityId).firstOrNull;
    final next = _rule == null
        ? const <DateTime>[]
        : const ReminderPlanner()
              .plan(
                [_r.copyWith(rule: _rule, id: 'preview').toPlanner()],
                now: ref.read(clockProvider).now(),
                zone: const _LocalZone(),
                days: 7,
              )
              .take(3)
              .map((o) => o.fireAt.toLocal())
              .toList();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showFbConfirm(
          context,
          title: l10n.discardChangesTitle,
          message: l10n.discardChangesMessage,
          confirmLabel: l10n.discard,
          cancelLabel: l10n.keepEditing,
        );
        if (leave && context.mounted) {
          _dirty = false;
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? l10n.newReminderTitle : l10n.editReminderTitle),
          actions: [
            if (_existing != null)
              IconButton(
                tooltip: l10n.delete,
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            Padding(
              padding: const EdgeInsets.only(right: FbSpace.sm),
              child: FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.xl, FbSpace.sm, FbSpace.xl, FbSpace.xxl),
          children: [
            if (_error != null) ...[
              FbNotice(_error!, isError: true),
              const SizedBox(height: FbSpace.md),
            ],
            Text(l10n.reminderTypeLabel, style: context.text.label),
            const SizedBox(height: FbSpace.sm),
            Wrap(
              spacing: FbSpace.sm,
              runSpacing: FbSpace.sm,
              children: [
                for (final k in ReminderKind.values)
                  FbToggleChip(
                    label: reminderKindName(l10n, k),
                    selected: _r.kind == k,
                    onTap: () => _pickKind(k),
                  ),
              ],
            ),
            const SizedBox(height: FbSpace.md),
            FbTextField(
              key: ValueKey('title$_editorKey'),
              label: l10n.titleLabel,
              value: _r.title,
              onChanged: (v) => _change((r) => r.copyWith(title: v)),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: FbSpace.md),
            FbTextField(
              label: l10n.descriptionLabel,
              value: _r.description ?? '',
              onChanged: (v) => _change((r) => r.copyWith(description: () => v)),
              optional: true,
              optionalLabel: l10n.optional,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: FbSpace.lg),
            ScheduleEditor(
              key: ValueKey(_editorKey),
              initial: _r.rule,
              today: ref.read(todayProvider),
              label: l10n.repeatLabel,
              onChanged: (rule) => setState(() {
                _rule = rule;
                _dirty = true;
              }),
            ),
            if (next.isNotEmpty) ...[
              const SizedBox(height: FbSpace.sm),
              Text(
                l10n.nextTimes(
                  next
                      .map(
                        (t) =>
                            '${context.dayLabel(LocalDate.fromDateTime(t), today: ref.read(todayProvider))} ${context.time(t)}',
                      )
                      .join(', '),
                ),
                style: context.text.caption,
              ),
            ],
            const SizedBox(height: FbSpace.lg),
            Text(l10n.priorityLabel, style: context.text.label),
            const SizedBox(height: FbSpace.sm),
            FbSegmented<bool>(
              options: {false: l10n.priorityNormal, true: l10n.priorityAlarm},
              selected: _r.alarm,
              onChanged: (v) => _change(
                (r) => r.copyWith(
                  alarm: v,
                  quietBehaviour: v ? QuietBehaviour.bypass : QuietBehaviour.defer,
                ),
              ),
            ),
            const SizedBox(height: FbSpace.xs),
            Text(l10n.priorityAlarmHelp, style: context.text.caption),
            const SizedBox(height: FbSpace.lg),
            FbCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  FbListRow(
                    title: l10n.soundLabel,
                    subtitle: l10n.soundValue(channelName(l10n, _r.channel)),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(alarmCapabilitiesProvider)
                          .playTestSound(channelIdFor(_r.channel.code)),
                      child: Text(l10n.testAction),
                    ),
                    onTap: () => ref
                        .read(alarmCapabilitiesProvider)
                        .openChannelSettings(channelIdFor(_r.channel.code)),
                  ),
                  FbSwitchRow(
                    title: l10n.vibrationLabel,
                    value: _r.vibrate,
                    onChanged: (v) => _change((r) => r.copyWith(vibrate: v)),
                  ),
                  FbListRow(
                    title: l10n.snoozeLabel,
                    subtitle: l10n.snoozeValue(_r.snoozeMinutes),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickSnooze,
                  ),
                  FbListRow(
                    title: l10n.duringQuietHours,
                    subtitle: quietBehaviourName(l10n, _r.quietBehaviour),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickQuiet,
                  ),
                  FbListRow(
                    title: l10n.linkedActivity,
                    subtitle: linked?.name ?? l10n.noActivity,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickActivity,
                  ),
                  if (_r.activityId != null)
                    FbSwitchRow(
                      title: l10n.onlyIfNotDone,
                      subtitle: l10n.onlyIfNotDoneHelp,
                      value: _r.onlyIfIncomplete,
                      onChanged: (v) => _change((r) => r.copyWith(onlyIfIncomplete: v)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.reminderLimitsNote, style: context.text.caption),
          ],
        ),
      ),
    );
  }
}

/// The device's own offsets, for the "next times" preview only.
class _LocalZone implements TimeZoneRules {
  const _LocalZone();
  @override
  Duration offsetAt(DateTime instant) => instant.toLocal().timeZoneOffset;
}
