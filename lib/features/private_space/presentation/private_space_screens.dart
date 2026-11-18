import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/routine_providers.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/private_records.dart';

String habitName(AppLocalizations l, PrivateHabitType t) => switch (t.systemKey) {
  'habit.porn' => l.habitPorn,
  'habit.masturbation' => l.habitMasturbation,
  _ => t.name,
};

/// Text fields here never learn from what is typed (privacy rules).
Widget _privateField(
  BuildContext context,
  String label,
  String value,
  ValueChanged<String> onChanged,
) => TextFormField(
  initialValue: value,
  enableSuggestions: false,
  autocorrect: false,
  enableIMEPersonalizedLearning: false,
  decoration: InputDecoration(labelText: label),
  onChanged: onChanged,
);

/// Private space hub (approved design).
class PrivateSpaceScreen extends ConsumerWidget {
  const PrivateSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final types = ref.watch(habitTypesProvider).value ?? const <PrivateHabitType>[];
    final activities = ref.watch(privateActivitiesProvider).value ?? const <PrivateActivity>[];
    final photos = ref.watch(progressPhotosProvider).value ?? const <ProgressPhoto>[];
    final today = ref.watch(todayProvider);
    final bowel =
        ref.watch(bowelLogsProvider((from: today, to: today))).value ?? const <BowelLog>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privateSpace),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(lockControllerProvider.notifier).lockNow();
                context.pop();
              },
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(l10n.lockAction),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSectionTitle(l10n.privateHabits),
          const SizedBox(height: FbSpace.sm),
          FbListCard(
            children: [
              for (final t in types)
                FbListRow(
                  title: habitName(l10n, t),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.privateHabit(t.id)),
                ),
              FbListRow(
                title: l10n.addHabitType,
                leading: const Icon(Icons.add_rounded),
                onTap: () async {
                  var name = '';
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.addHabitType),
                      content: _privateField(context, l10n.nameLabel, '', (v) => name = v),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(l10n.add),
                        ),
                      ],
                    ),
                  );
                  if (ok ?? false) await ref.read(privateRepositoryProvider).addHabitType(name);
                },
              ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          FbListCard(
            children: [
              FbListRow(
                title: l10n.bowelLog,
                subtitle: bowel.isEmpty
                    ? l10n.nothingToday
                    : l10n.loggedAt(context.time(bowel.first.occurredAt)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.bowel),
              ),
              FbListRow(
                title: l10n.privateActivities,
                subtitle: l10n.activitiesCount(activities.length),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.privateActivities),
              ),
              FbListRow(
                title: l10n.progressPhotos,
                subtitle: photos.isEmpty ? l10n.noPhotosYet : l10n.photosCount(photos.length),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.progressPhotos),
              ),
              FbListRow(
                title: l10n.privateReminders,
                subtitle: l10n.privateRemindersHelp,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.privateReminders),
              ),
            ],
          ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.privateNote, style: context.text.caption),
        ],
      ),
    );
  }
}

/// One private habit: record, trend, history (approved design).
class PrivateHabitScreen extends ConsumerStatefulWidget {
  const PrivateHabitScreen({required this.id, super.key});
  final String id;

  @override
  ConsumerState<PrivateHabitScreen> createState() => _PrivateHabitScreenState();
}

class _PrivateHabitScreenState extends ConsumerState<PrivateHabitScreen> {
  bool _monthly = false;

  Future<void> _record({bool details = false}) async {
    final l10n = context.l10n;
    final repo = ref.read(privateRepositoryProvider);
    if (!details) {
      await repo.recordHabit(widget.id, at: ref.read(clockProvider).now());
      if (mounted) showFbSnackBar(context, l10n.recorded);
      return;
    }
    await showFbSheet<void>(context, _HabitRecordSheet(typeId: widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = (ref.watch(habitTypesProvider).value ?? const [])
        .where((t) => t.id == widget.id)
        .firstOrNull;
    final today = ref.watch(todayProvider);
    final from = _monthly ? today.addDays(-364) : today.addDays(-55);
    final logs =
        ref.watch(habitLogsProvider((type: widget.id, from: from, to: today))).value ??
        const <PrivateHabitLog>[];
    final mondayThis = today.addDays(1 - today.weekday);
    final thisWeek = logs
        .where((l) => !l.localDate.isBefore(mondayThis))
        .fold(0, (n, l) => n + l.count);
    final buckets = <double>[];
    if (_monthly) {
      for (var i = 11; i >= 0; i--) {
        final m = DateTime(today.year, today.month - i);
        buckets.add(
          logs
              .where((l) => l.localDate.year == m.year && l.localDate.month == m.month)
              .fold(0, (n, l) => n + l.count)
              .toDouble(),
        );
      }
    } else {
      for (var i = 7; i >= 0; i--) {
        final start = mondayThis.addDays(-7 * i);
        buckets.add(
          logs
              .where((l) => !l.localDate.isBefore(start) && l.localDate.isBefore(start.addDays(7)))
              .fold(0, (n, l) => n + l.count)
              .toDouble(),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(type == null ? '' : habitName(l10n, type)),
        actions: [
          if (type != null && type.systemKey == null)
            IconButton(
              tooltip: l10n.archive,
              onPressed: () async {
                final ok = await showFbConfirm(
                  context,
                  title: l10n.archiveHabitTitle,
                  message: l10n.archiveHabitMessage,
                  confirmLabel: l10n.archive,
                  cancelLabel: l10n.cancel,
                );
                if (!ok) return;
                await ref.read(privateRepositoryProvider).archiveHabitType(widget.id);
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.archive_outlined),
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
                Row(
                  children: [
                    Expanded(child: Text(l10n.thisWeek, style: context.text.bodySmall)),
                    Text(l10n.timesCount(thisWeek), style: context.text.title),
                  ],
                ),
                const SizedBox(height: FbSpace.md),
                Wrap(
                  spacing: FbSpace.sm,
                  runSpacing: FbSpace.sm,
                  children: [
                    FilledButton(onPressed: _record, child: Text(l10n.recordNow)),
                    OutlinedButton(
                      onPressed: () => _record(details: true),
                      child: Text(l10n.recordWithDetails),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSegmented<bool>(
            options: {false: l10n.weekly, true: l10n.monthly},
            selected: _monthly,
            onChanged: (v) => setState(() => _monthly = v),
          ),
          const SizedBox(height: FbSpace.sm),
          FbChartCard(
            summary: l10n.habitTrendSummary(buckets.length),
            footer: Text(l10n.countsOnly, style: context.text.caption),
            chart: FbBarChart(
              values: buckets,
              bottomLabel: (i) => '${i + 1}',
              leftLabel: (y) => '${y.round()}',
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.historyTitle),
          const SizedBox(height: FbSpace.sm),
          if (logs.isEmpty)
            FbEmptyHint(l10n.noHistoryYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final log in logs.take(50))
                  FbListRow(
                    title:
                        '${context.dayLabel(log.localDate, today: today)} ${context.time(log.occurredAt)}',
                    subtitle: [l10n.timesCount(log.count), ?log.note].join(' · '),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      onPressed: () async {
                        final ok = await showFbConfirm(
                          context,
                          title: l10n.deleteEntryTitle,
                          message: l10n.deleteEntryMessage,
                          confirmLabel: l10n.delete,
                          cancelLabel: l10n.cancel,
                        );
                        if (ok) await ref.read(privateRepositoryProvider).deleteHabitLog(log.id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HabitRecordSheet extends ConsumerStatefulWidget {
  const _HabitRecordSheet({required this.typeId});
  final String typeId;

  @override
  ConsumerState<_HabitRecordSheet> createState() => _HabitRecordSheetState();
}

class _HabitRecordSheetState extends ConsumerState<_HabitRecordSheet> {
  late DateTime _at = ref.read(clockProvider).now();
  int _count = 1;
  String _note = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.recordWithDetails,
      children: [
        FbDateTimeField(
          label: l10n.timeLabel,
          value: _at,
          last: ref.read(clockProvider).now(),
          onChanged: (v) => setState(() => _at = v),
        ),
        const SizedBox(height: FbSpace.md),
        Row(
          children: [
            Expanded(child: Text(l10n.countLabel, style: context.text.body)),
            IconButton.outlined(
              tooltip: l10n.decrease,
              onPressed: _count > 1 ? () => setState(() => _count--) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FbSpace.md),
              child: Text('$_count', style: context.text.title),
            ),
            IconButton.outlined(
              tooltip: l10n.increase,
              onPressed: () => setState(() => _count++),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        _privateField(context, l10n.note, '', (v) => _note = v),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(
          label: l10n.save,
          onPressed: () async {
            final r = await ref
                .read(privateRepositoryProvider)
                .recordHabit(widget.typeId, at: _at, count: _count, note: _note);
            if (!context.mounted) return;
            showFbSnackBar(context, r.isOk ? l10n.recorded : l10n.errSaveFailed);
            if (r.isOk) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

/// Bowel log: quick log, frequency, history (approved design, §5.11).
class BowelScreen extends ConsumerStatefulWidget {
  const BowelScreen({super.key});

  @override
  ConsumerState<BowelScreen> createState() => _BowelScreenState();
}

class _BowelScreenState extends ConsumerState<BowelScreen> {
  Consistency _consistency = Consistency.normal;
  bool _straining = false;
  bool _pain = false;
  bool _bleeding = false;
  late DateTime _at = ref.read(clockProvider).now();

  Future<void> _save() async {
    final l10n = context.l10n;
    final r = await ref.read(privateRepositoryProvider).addBowel((
      at: _at,
      consistency: _consistency,
      count: 1,
      straining: _straining,
      pain: _pain,
      bleeding: _bleeding,
      notes: null,
    ));
    if (!mounted) return;
    showFbSnackBar(context, r.isOk ? l10n.recorded : l10n.errInFuture);
    if (r.isOk) {
      setState(() {
        _straining = _pain = _bleeding = false;
        _at = ref.read(clockProvider).now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final logs =
        ref.watch(bowelLogsProvider((from: today.addDays(-29), to: today))).value ??
        const <BowelLog>[];
    final week = logs
        .where((l) => l.localDate.isAfter(today.addDays(-7)))
        .fold(0, (n, l) => n + l.count);
    final perDay = logs.fold(0, (n, l) => n + l.count) / 30;
    int of(Consistency c) => logs.where((l) => l.consistency == c).length;
    String label(Consistency c) => switch (c) {
      Consistency.hard => l10n.consistencyHard,
      Consistency.normal => l10n.consistencyNormal,
      Consistency.loose => l10n.consistencyLoose,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bowelLog)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.quickLog, style: context.text.bodyStrong),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.consistencyLabel, style: context.text.label),
                const SizedBox(height: FbSpace.xs),
                FbSegmented<Consistency>(
                  options: {for (final c in Consistency.values) c: label(c)},
                  selected: _consistency,
                  onChanged: (c) => setState(() => _consistency = c),
                ),
                const SizedBox(height: FbSpace.md),
                Wrap(
                  spacing: FbSpace.sm,
                  runSpacing: FbSpace.sm,
                  children: [
                    FbToggleChip(
                      label: l10n.straining,
                      selected: _straining,
                      onTap: () => setState(() => _straining = !_straining),
                    ),
                    FbToggleChip(
                      label: l10n.pain,
                      selected: _pain,
                      onTap: () => setState(() => _pain = !_pain),
                    ),
                    FbToggleChip(
                      label: l10n.bleeding,
                      selected: _bleeding,
                      onTap: () => setState(() => _bleeding = !_bleeding),
                    ),
                  ],
                ),
                const SizedBox(height: FbSpace.md),
                FbDateTimeField(
                  label: l10n.timeLabel,
                  value: _at,
                  last: ref.read(clockProvider).now(),
                  onChanged: (v) => setState(() => _at = v),
                ),
                const SizedBox(height: FbSpace.md),
                FbPrimaryButton(label: l10n.save, onPressed: _save),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbCard(
            child: Wrap(
              spacing: FbSpace.xl,
              runSpacing: FbSpace.md,
              children: [
                _Fact('$week', l10n.last7Days),
                _Fact(perDay.toStringAsFixed(1), l10n.perDay30),
                _Fact(
                  '${of(Consistency.normal)} / ${of(Consistency.hard)} / ${of(Consistency.loose)}',
                  l10n.normalHardLoose,
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          if (logs.isEmpty)
            FbEmptyHint(l10n.noHistoryYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final log in logs.take(30))
                  FbListRow(
                    title:
                        '${context.dayLabel(log.localDate, today: today)} ${context.time(log.occurredAt)}',
                    subtitle: [
                      label(log.consistency),
                      if (log.straining) l10n.straining,
                      if (log.pain ?? false) l10n.pain,
                      if (log.bleeding ?? false) l10n.bleeding,
                    ].join(' · '),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      onPressed: () async {
                        final ok = await showFbConfirm(
                          context,
                          title: l10n.deleteEntryTitle,
                          message: l10n.deleteEntryMessage,
                          confirmLabel: l10n.delete,
                          cancelLabel: l10n.cancel,
                        );
                        if (ok) await ref.read(privateRepositoryProvider).deleteBowel(log.id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.bowelNote, style: context.text.caption),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.text.bodyStrong.copyWith(fontSize: 18)),
        Text(label, style: context.text.caption),
      ],
    ),
  );
}

/// Private activities (decision C5).
class PrivateActivitiesScreen extends ConsumerWidget {
  const PrivateActivitiesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    var name = '';
    var counted = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.newPrivateActivity),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _privateField(context, l10n.nameLabel, '', (v) => name = v),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.countEachTime),
                value: counted,
                onChanged: (v) => setState(() => counted = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.add)),
          ],
        ),
      ),
    );
    if (ok ?? false) await ref.read(privateRepositoryProvider).addActivity(name, counted: counted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final list = ref.watch(privateActivitiesProvider).value ?? const <PrivateActivity>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privateActivities),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.add),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (list.isEmpty)
            FbEmptyHint(l10n.privateActivitiesEmpty, boxed: true)
          else
            FbListCard(
              children: [
                for (final a in list)
                  FbListRow(
                    title: a.name,
                    subtitle: a.counted ? l10n.trackCount : l10n.trackBoolean,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.privateActivity(a.id)),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.privateActivitiesNote, style: context.text.caption),
        ],
      ),
    );
  }
}

class PrivateActivityScreen extends ConsumerWidget {
  const PrivateActivityScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final a = (ref.watch(privateActivitiesProvider).value ?? const <PrivateActivity>[])
        .where((x) => x.id == id)
        .firstOrNull;
    final logs = ref.watch(privateActivityLogsProvider(id)).value ?? const <PrivateActivityLog>[];
    final today = ref.watch(todayProvider);
    if (a == null) return Scaffold(appBar: AppBar(), body: const FbLoading());
    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            tooltip: l10n.archive,
            onPressed: () async {
              await ref.read(privateRepositoryProvider).archiveActivity(id);
              if (context.mounted) context.pop();
            },
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final r = await ref
                  .read(privateRepositoryProvider)
                  .logActivity(id, at: ref.read(clockProvider).now(), count: a.counted ? 1 : null);
              if (context.mounted) {
                showFbSnackBar(context, r.isOk ? l10n.recorded : l10n.errSaveFailed);
              }
            },
            child: Text(a.counted ? l10n.plusOne : l10n.markDone),
          ),
          const SizedBox(height: FbSpace.lg),
          if (logs.isEmpty)
            FbEmptyHint(l10n.noHistoryYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final log in logs)
                  FbListRow(
                    title:
                        '${context.dayLabel(log.localDate, today: today)} ${context.time(log.occurredAt)}',
                    subtitle: log.count == null ? l10n.stateDone : l10n.timesCount(log.count!),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      onPressed: () =>
                          ref.read(privateRepositoryProvider).deleteActivityLog(log.id),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Encrypted progress photos (approved design, §5.3, C2).
class ProgressPhotosScreen extends ConsumerWidget {
  const ProgressPhotosScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final source = await showFbSheet<PhotoSource>(
      context,
      FbSheetBody(
        title: l10n.addPhoto,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.takePhoto),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.choosePhoto),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
        ],
      ),
    );
    if (source == null) return;
    final bytes = await ref.read(photoPickerProvider).pick(source);
    if (bytes == null) return;
    final r = await ref
        .read(privateRepositoryProvider)
        .addPhoto(bytes, takenAt: ref.read(clockProvider).now());
    if (context.mounted) showFbSnackBar(context, r.isOk ? l10n.photoSaved : l10n.errSaveFailed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final photos = ref.watch(progressPhotosProvider).value ?? const <ProgressPhoto>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.progressPhotos),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.add),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (photos.isEmpty)
            FbEmptyHint(l10n.noPhotosYet, boxed: true)
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: FbSpace.sm,
              crossAxisSpacing: FbSpace.sm,
              childAspectRatio: 3 / 4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final p in photos)
                  Semantics(
                    button: true,
                    label: l10n.photoOf(context.shortDate(p.localDate)),
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _PhotoDialog(photo: p),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(FbRadius.input),
                        child: _PhotoThumb(id: p.id),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.photosNote, style: context.text.caption),
        ],
      ),
    );
  }
}

final _photoBytesProvider = FutureProvider.family<List<int>?, String>(
  (ref, id) => ref.watch(privateRepositoryProvider).readPhoto(id),
);

class _PhotoThumb extends ConsumerWidget {
  const _PhotoThumb({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(_photoBytesProvider(id)).value;
    return bytes == null
        ? ColoredBox(color: context.colors.surfaceVariant)
        : Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: context.colors.surfaceVariant),
          );
  }
}

class _PhotoDialog extends ConsumerWidget {
  const _PhotoDialog({required this.photo});
  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(context.shortDate(photo.localDate)),
      content: SizedBox(width: 300, height: 400, child: _PhotoThumb(id: photo.id)),
      actions: [
        TextButton(
          onPressed: () async {
            final ok = await showFbConfirm(
              context,
              title: l10n.deletePhotoTitle,
              message: l10n.deletePhotoMessage,
              confirmLabel: l10n.delete,
              cancelLabel: l10n.cancel,
            );
            if (!ok) return;
            await ref.read(privateRepositoryProvider).deletePhoto(photo.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l10n.delete),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.close)),
      ],
    );
  }
}

/// Private reminders: generic on the lock screen (§3.4 rule 14).
class PrivateRemindersScreen extends ConsumerWidget {
  const PrivateRemindersScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    SensitiveReminder? existing,
    String ownerType = 'custom',
  }) async {
    final l10n = context.l10n;
    var title = existing?.title ?? (ownerType == 'bowel' ? l10n.routineCheckIn : '');
    var minute = 8 * 60;
    if (existing != null) {
      final rule = ScheduleRule.fromJson(
        (jsonDecode(existing.ruleJson) as Map).cast<String, Object?>(),
      );
      if (rule is Daily && rule.times.isNotEmpty) minute = rule.times.first;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? l10n.newPrivateReminder : l10n.editReminderTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _privateField(context, l10n.titleLabel, title, (v) => title = v),
              const SizedBox(height: FbSpace.md),
              FbPickerField(
                label: l10n.timeLabel,
                valueText: MaterialLocalizations.of(context)
                    .formatTimeOfDay(TimeOfDay(hour: minute ~/ 60, minute: minute % 60)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
                  );
                  if (t != null) setState(() => minute = t.hour * 60 + t.minute);
                },
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await ref.read(sensitiveReminderRepositoryProvider).delete(existing.id);
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                child: Text(l10n.delete),
              ),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(title.trim().isNotEmpty),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (title.trim().isNotEmpty) {
      await ref
          .read(sensitiveReminderRepositoryProvider)
          .save(
            SensitiveReminder(
              id: existing?.id ?? '',
              ownerType: existing?.ownerType ?? ownerType,
              title: title.trim(),
              ruleJson: jsonEncode(Daily(times: [minute]).toJson()),
              enabled: existing?.enabled ?? true,
            ),
          );
    }
    replanReminders(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final list = ref.watch(sensitiveRemindersProvider).value ?? const <SensitiveReminder>[];
    final hasBowel = list.any((r) => r.ownerType == 'bowel');
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privateReminders)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (list.isEmpty)
            FbEmptyHint(l10n.privateRemindersEmpty, boxed: true)
          else
            FbListCard(
              children: [
                for (final r in list)
                  FbListRow(
                    title: r.title,
                    subtitle: () {
                      final rule = ScheduleRule.fromJson(
                        (jsonDecode(r.ruleJson) as Map).cast<String, Object?>(),
                      );
                      final m = rule is Daily && rule.times.isNotEmpty ? rule.times.first : 0;
                      return MaterialLocalizations.of(context)
                          .formatTimeOfDay(TimeOfDay(hour: m ~/ 60, minute: m % 60));
                    }(),
                    onTap: () => _edit(context, ref, existing: r),
                    trailing: Switch(
                      value: r.enabled,
                      onChanged: (v) async {
                        await ref
                            .read(sensitiveReminderRepositoryProvider)
                            .save(
                              SensitiveReminder(
                                id: r.id,
                                ownerType: r.ownerType,
                                ownerId: r.ownerId,
                                title: r.title,
                                ruleJson: r.ruleJson,
                                enabled: v,
                              ),
                            );
                        replanReminders(ref);
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              if (!hasBowel)
                OutlinedButton(
                  onPressed: () => _edit(context, ref, ownerType: 'bowel'),
                  child: Text(l10n.addBowelReminder),
                ),
              OutlinedButton(
                onPressed: () => _edit(context, ref),
                child: Text(l10n.newPrivateReminder),
              ),
            ],
          ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.privateRemindersNote, style: context.text.caption),
        ],
      ),
    );
  }
}
