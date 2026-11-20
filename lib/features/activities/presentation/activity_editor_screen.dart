import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/fb_scaffolds.dart';
import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/routine_actions.dart';
import '../../../app/routine_labels.dart';
import '../../../app/routine_providers.dart';
import '../../../core/errors/failure.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../reminders/domain/reminder.dart';
import '../domain/activity.dart';
import '../../../app/routine/schedule_editor.dart';

/// Activity builder (approved design "Activity builder"). Edits an existing
/// activity when [id] is given.
class ActivityEditorScreen extends ConsumerStatefulWidget {
  const ActivityEditorScreen({this.id, super.key});
  final String? id;

  @override
  ConsumerState<ActivityEditorScreen> createState() => _ActivityEditorScreenState();
}

class _ActivityEditorScreenState extends ConsumerState<ActivityEditorScreen> {
  Activity? _existing;
  bool _loaded = false;
  String _name = '';
  String _description = '';
  String _category = 'health';
  String _icon = 'check';
  TrackingType _type = TrackingType.boolean;
  ActivityPriority _priority = ActivityPriority.essential;
  String _target = '';
  String _unit = '';
  ScheduleRule? _rule;
  late ScheduleRule _initialRule;
  bool _stopwatch = false;
  bool _showOnHome = true;

  /// Decision C5: chosen once, at creation; stored in the private database.
  bool _private = false;
  bool _remind = false;
  Reminder? _linked;
  List<ChecklistItem> _checklist = [];
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _initialRule = Daily(times: [8 * 60]);
    _rule = _initialRule;
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = widget.id;
    if (id != null) {
      final a = await ref.read(activityRepositoryProvider).byId(id);
      final reminders = await ref.read(reminderRepositoryProvider).watchAll().first;
      if (a != null) {
        _existing = a;
        _name = a.name;
        _description = a.description ?? '';
        _category = a.category;
        _icon = a.iconKey;
        _type = a.trackingType;
        _priority = a.priority;
        _target = switch (a.targetMilli) {
          null => '',
          final t
              when a.trackingType == TrackingType.duration ||
                  a.trackingType == TrackingType.stopwatch =>
            '${t ~/ 60000}',
          final t => '${t ~/ 1000}',
        };
        _unit = a.targetUnit ?? '';
        _initialRule = a.schedule;
        _rule = a.schedule;
        _stopwatch = a.stopwatchEnabled;
        _showOnHome = a.showOnDashboard;
        _checklist = [...a.checklistItems];
        _linked = reminders
            .where(
              (r) => r.kind == ReminderKind.activity && r.activityId == a.id && !r.onlyIfIncomplete,
            )
            .firstOrNull;
        _remind = _linked?.enabled ?? false;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _change(VoidCallback f) => setState(() {
    f();
    _dirty = true;
  });

  bool get _hasDuration => _type == TrackingType.duration || _type == TrackingType.stopwatch;

  Future<void> _save() async {
    final l10n = context.l10n;
    final errors = <String, String>{};
    if (_name.trim().isEmpty) errors['name'] = l10n.errRequired;
    if (_private) return _savePrivate(errors);
    int? targetMilli;
    if (_target.trim().isNotEmpty) {
      final v = int.tryParse(_target.trim());
      if (v == null || v <= 0) {
        errors['target'] = l10n.errInvalidNumber;
      } else {
        targetMilli = _hasDuration ? v * 60000 : v * 1000;
      }
    }
    if (_rule == null || _rule!.problems.isNotEmpty) {
      errors['schedule'] = l10n.errScheduleIncomplete;
    }
    if (_type == TrackingType.checklist &&
        _checklist.where((i) => i.label.trim().isNotEmpty).isEmpty) {
      errors['checklist'] = l10n.errChecklistEmpty;
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);

    final draft = Activity(
      id: _existing?.id ?? '',
      name: _name,
      description: _description,
      category: _category,
      iconKey: _icon,
      trackingType: _type,
      priority: _priority,
      targetMilli: _type.hasAmount ? targetMilli : null,
      targetUnit:
          (_type == TrackingType.count || _type == TrackingType.numeric) && _unit.trim().isNotEmpty
          ? _unit.trim()
          : null,
      schedule: _rule!,
      scheduleHistory: _existing?.scheduleHistory ?? const [],
      stopwatchEnabled: _hasDuration && _stopwatch,
      showOnDashboard: _showOnHome,
      checklistItems: [
        for (final i in _checklist)
          if (i.label.trim().isNotEmpty) i,
      ],
      archived: _existing?.archived ?? false,
      sortOrder: _existing?.sortOrder ?? 0,
    );
    final repo = ref.read(activityRepositoryProvider);
    String? id;
    if (_existing == null) {
      final r = await repo.create(draft);
      id = r.valueOrNull?.id;
      if (id == null) return _failed(r.failureOrNull);
    } else {
      final r = await repo.update(draft);
      if (!r.isOk) return _failed(r.failureOrNull);
      id = _existing!.id;
    }
    await _saveReminder(id, draft);
    if (!mounted) return;
    replanReminders(ref);
    showFbSnackBar(context, l10n.activitySaved);
    _dirty = false;
    if (_existing == null) {
      context.pushReplacement(Routes.activity(id));
    } else {
      context.pop();
    }
  }

  Future<void> _savePrivate(Map<String, String> errors) async {
    final l10n = context.l10n;
    if (_type != TrackingType.boolean && _type != TrackingType.count) {
      errors['private'] = l10n.privateTypeLimit;
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final r = await ref
        .read(privateRepositoryProvider)
        .addActivity(_name.trim(), counted: _type == TrackingType.count);
    if (!mounted) return;
    final id = r.valueOrNull?.id;
    if (id == null) return _failed(r.failureOrNull);
    showFbSnackBar(context, l10n.activitySaved);
    _dirty = false;
    context.pushReplacement(Routes.privateActivity(id));
  }

  Future<void> _saveReminder(String id, Activity a) async {
    final reminders = ref.read(reminderRepositoryProvider);
    if (_remind) {
      final base =
          (_linked ??
                  Reminder(id: '', kind: ReminderKind.activity, title: a.name, rule: a.schedule))
              .copyWith(
                title: a.name.trim(),
                rule: a.schedule,
                activityId: () => id,
                enabled: true,
              );
      if (_linked == null) {
        await reminders.create(base);
      } else {
        await reminders.update(base);
      }
      if (mounted) await ensureNotificationPermission(context, ref);
    } else if (_linked != null && _linked!.enabled) {
      await reminders.setEnabled(_linked!.id, enabled: false);
    }
  }

  void _failed(Failure? f) {
    final l10n = context.l10n;
    final message = switch (f) {
      ValidationFailure(field: 'trackingType') => l10n.errTrackingTypeChange,
      ValidationFailure() => l10n.errCheckFields,
      _ => l10n.errSaveFailed,
    };
    setState(() {
      _busy = false;
      _errors = {'form': message};
    });
    // The form may be scrolled; say it where it is seen.
    showFbSnackBar(context, message);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final l10n = context.l10n;
    return showFbConfirm(
      context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discard,
      cancelLabel: l10n.keepEditing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_loaded) return const Scaffold(body: FbLoading());
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          _dirty = false;
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? l10n.newActivityTitle : l10n.editActivityTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: FbSpace.sm),
              child: FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.xl, FbSpace.sm, FbSpace.xl, FbSpace.xxl),
          children: [
            if (_errors['form'] != null) ...[
              FbNotice(_errors['form']!, isError: true),
              const SizedBox(height: FbSpace.md),
            ],
            if (_errors['private'] != null) ...[
              FbNotice(_errors['private']!, isError: true),
              const SizedBox(height: FbSpace.md),
            ],
            FbTextField(
              label: l10n.nameLabel,
              value: _name,
              onChanged: (v) => _change(() => _name = v),
              errorText: _errors['name'],
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: FbSpace.md),
            FbTextField(
              label: l10n.descriptionLabel,
              value: _description,
              onChanged: (v) => _change(() => _description = v),
              optional: true,
              optionalLabel: l10n.optional,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.categoryLabel, style: context.text.label),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              items: [
                for (final c in activityCategories)
                  DropdownMenuItem(value: c, child: Text(categoryName(l10n, c))),
              ],
              onChanged: (c) => _change(() => _category = c!),
            ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.iconLabel, style: context.text.label),
            const SizedBox(height: 6),
            Wrap(
              spacing: FbSpace.xs,
              runSpacing: FbSpace.xs,
              children: [
                for (final e in activityIcons.entries)
                  IconButton(
                    tooltip: l10n.iconChoice(e.key),
                    isSelected: _icon == e.key,
                    style: IconButton.styleFrom(
                      side: BorderSide(
                        color: _icon == e.key ? context.colors.primary : context.colors.outline,
                        width: _icon == e.key ? 2 : 1,
                      ),
                    ),
                    onPressed: () => _change(() => _icon = e.key),
                    icon: Icon(e.value),
                  ),
              ],
            ),
            const SizedBox(height: FbSpace.lg),
            Text(l10n.trackingLabel, style: context.text.label),
            const SizedBox(height: FbSpace.sm),
            Wrap(
              spacing: FbSpace.sm,
              runSpacing: FbSpace.sm,
              children: [
                for (final t in TrackingType.values)
                  FbToggleChip(
                    label: trackingTypeName(l10n, t),
                    selected: _type == t,
                    onTap: () => _change(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: FbSpace.xs),
            Text(trackingTypeHelp(l10n, _type), style: context.text.caption),
            if (_type.hasAmount) ...[
              const SizedBox(height: FbSpace.md),
              FbFieldPair(
                first: FbTextField(
                  label: l10n.targetLabel,
                  value: _target,
                  onChanged: (v) => _change(() => _target = v),
                  errorText: _errors['target'],
                  suffix: _hasDuration ? l10n.unitMin : null,
                  optional: true,
                  optionalLabel: l10n.optional,
                  keyboardType: TextInputType.number,
                ),
                second: _hasDuration
                    ? const SizedBox.shrink()
                    : FbTextField(
                        label: l10n.unitLabel,
                        value: _unit,
                        onChanged: (v) => _change(() => _unit = v),
                        hint: l10n.unitHint,
                        optional: true,
                        optionalLabel: l10n.optional,
                      ),
              ),
            ],
            if (_type == TrackingType.checklist) ...[
              const SizedBox(height: FbSpace.md),
              Text(l10n.checklistItemsLabel, style: context.text.label),
              const SizedBox(height: FbSpace.xs),
              for (final (i, item) in _checklist.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: FbSpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: FbTextField(
                          key: ValueKey(item.id),
                          label: l10n.checklistStep(i + 1),
                          value: item.label,
                          onChanged: (v) =>
                              _change(() => _checklist[i] = ChecklistItem(item.id, v)),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.removeStep(i + 1),
                        onPressed: () => _change(() => _checklist.removeAt(i)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              if (_errors['checklist'] != null) FbNotice(_errors['checklist']!, isError: true),
              OutlinedButton.icon(
                onPressed: () => _change(
                  () => _checklist.add(ChecklistItem(ref.read(idGeneratorProvider).newId(), '')),
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.addStep),
              ),
            ],
            const SizedBox(height: FbSpace.lg),
            Text(l10n.priorityLabel, style: context.text.label),
            const SizedBox(height: FbSpace.sm),
            FbSegmented<ActivityPriority>(
              options: {
                ActivityPriority.essential: l10n.essential,
                ActivityPriority.optional: l10n.optionalPriority,
              },
              selected: _priority,
              onChanged: (p) => _change(() => _priority = p),
            ),
            const SizedBox(height: FbSpace.xs),
            Text(l10n.essentialHelp, style: context.text.caption),
            const SizedBox(height: FbSpace.lg),
            ScheduleEditor(
              initial: _initialRule,
              today: ref.read(todayProvider),
              onChanged: (r) => _change(() => _rule = r),
            ),
            if (_errors['schedule'] != null) FbNotice(_errors['schedule']!, isError: true),
            if (_existing != null && _rule != _existing!.schedule) ...[
              const SizedBox(height: FbSpace.xs),
              Text(l10n.rescheduleNote, style: context.text.caption),
            ],
            const SizedBox(height: FbSpace.lg),
            FbCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (_existing == null)
                    FbSwitchRow(
                      title: l10n.privateActivitySwitch,
                      subtitle: l10n.privateActivitySwitchHelp,
                      value: _private,
                      onChanged: (v) => _change(() => _private = v),
                    ),
                  FbSwitchRow(
                    title: l10n.remindAtTimes,
                    subtitle: l10n.remindAtTimesHelp,
                    value: _remind,
                    onChanged: (v) => _change(() => _remind = v),
                  ),
                  if (_hasDuration)
                    FbSwitchRow(
                      title: l10n.offerStopwatch,
                      subtitle: l10n.offerStopwatchHelp,
                      value: _stopwatch,
                      onChanged: (v) => _change(() => _stopwatch = v),
                    ),
                  FbSwitchRow(
                    title: l10n.showOnHome,
                    subtitle: l10n.showOnHomeHelp,
                    value: _showOnHome,
                    onChanged: (v) => _change(() => _showOnHome = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.trackingChangeNote, style: context.text.caption),
          ],
        ),
      ),
    );
  }
}
