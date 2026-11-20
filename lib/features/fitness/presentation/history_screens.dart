import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fitness_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/workout_math.dart';
import '../domain/workouts.dart';
import 'cardio_screens.dart';
import 'fitness_labels.dart';
import 'gym_screens.dart';

/// Workout history and templates (approved design).
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  WorkoutKind? _kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final async = ref.watch(workoutsProvider(_kind));
    final list = async.value;
    final templates = ref.watch(templatesProvider).value ?? const <WorkoutTemplate>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.workoutHistory)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              FbToggleChip(label: l10n.filterAll, selected: _kind == null, onTap: () => setState(() => _kind = null)),
              for (final k in WorkoutKind.values)
                FbToggleChip(
                  label: workoutKindName(l10n, k),
                  selected: _kind == k,
                  onTap: () => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: FbSpace.md),
          if (list == null)
            (async.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading())
          else if (list.isEmpty)
            FbEmptyHint(l10n.noWorkoutsYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final s in list)
                  FbListRow(
                    leading: Icon(workoutIcon(s.kind)),
                    title: s.kind == WorkoutKind.gym ? s.name : workoutKindName(l10n, s.kind),
                    subtitle: '${context.dayLabel(s.localDate, today: today)} · ${workoutSummary(context, s)}',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.workout(s.id)),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.templates),
          const SizedBox(height: FbSpace.sm),
          if (templates.isEmpty)
            FbEmptyHint(l10n.templatesEmpty, boxed: true)
          else
            FbListCard(
              children: [
                for (final t in templates)
                  FbListRow(
                    title: t.name,
                    subtitle: l10n.templateSummary(t.exercises.length, t.useCount),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.deleteTemplate(t.name),
                          onPressed: () async {
                            final ok = await showFbConfirm(
                              context,
                              title: l10n.deleteTemplateTitle,
                              message: l10n.deleteTemplateMessage,
                              confirmLabel: l10n.delete,
                              cancelLabel: l10n.cancel,
                            );
                            if (ok) await ref.read(workoutRepositoryProvider).deleteTemplate(t.id);
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final id =
                                (await ref.read(workoutRepositoryProvider).startGym(name: t.name, templateId: t.id))
                                    .valueOrNull;
                            if (id != null && context.mounted) {
                              unawaited(context.push(Routes.workout(id)));
                            }
                          },
                          child: Text(l10n.start),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.historyHelp, style: context.text.caption),
        ],
      ),
    );
  }
}

/// Opens a workout: gym workouts in the workout screen, cardio as a summary.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(workoutProvider(id));
    final s = async.value;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const FbLoading() : FbErrorState(message: l10n.workoutMissing),
      );
    }
    if (s.kind == WorkoutKind.gym) return GymWorkoutScreen(id: id);
    final pace = paceSecondsPerKm(distanceM: s.distanceM ?? 0, durationS: s.durationS);
    final speed = speedMetresPerHour(distanceM: s.distanceM ?? 0, durationS: s.durationS);
    final route = ref.watch(_routeProvider(id)).value ?? const <RoutePoint>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(workoutKindName(l10n, s.kind)),
        actions: [
          IconButton(
            tooltip: l10n.edit,
            onPressed: () => context.push(Routes.editCardio(id), extra: s),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: l10n.delete,
            onPressed: () async {
              final ok = await showFbConfirm(
                context,
                title: l10n.deleteWorkoutTitle,
                message: l10n.deleteWorkoutMessage,
                confirmLabel: l10n.delete,
                cancelLabel: l10n.cancel,
              );
              if (!ok) return;
              await ref.read(workoutRepositoryProvider).deleteSession(id);
              if (context.mounted) {
                showFbSnackBar(context, l10n.deleted);
                context.pop();
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Text('${context.dayLabel(s.localDate)} · ${context.time(s.startedAt)}', style: context.text.caption),
          const SizedBox(height: FbSpace.md),
          if (route.length > 1) ...[
            FbCard(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 220,
                child: Semantics(
                  label: l10n.routeSemantics(km(context, s.distanceM ?? 0)),
                  child: CustomPaint(painter: RoutePainter(route, context.colors.primary, context.colors.outline)),
                ),
              ),
            ),
            const SizedBox(height: FbSpace.md),
          ],
          FbCard(
            child: Wrap(
              spacing: FbSpace.xl,
              runSpacing: FbSpace.md,
              children: [
                _Fact(km(context, s.distanceM ?? 0), l10n.distanceLabel),
                _Fact(clockLabel(Duration(seconds: s.durationS)), l10n.durationLabel),
                if (pace != null) _Fact(paceLabel(context, pace), l10n.averagePace),
                if (speed != null) _Fact(speedLabel(context, speed), l10n.averageSpeed),
              ],
            ),
          ),
          if (s.notes != null) ...[const SizedBox(height: FbSpace.md), Text(s.notes!, style: context.text.body)],
          const SizedBox(height: FbSpace.md),
          Text(s.entryMode == 'gps' ? l10n.gpsStoredNote : l10n.manualEntryNote, style: context.text.caption),
        ],
      ),
    );
  }
}

final _routeProvider = FutureProvider.family<List<RoutePoint>, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).route(id),
);

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

/// One exercise: progression chart and records (approved design).
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final e = (ref.watch(exercisesProvider).value ?? const <Exercise>[]).where((x) => x.id == id).firstOrNull;
    if (e == null) return Scaffold(appBar: AppBar(), body: const FbLoading());
    final progress = ref.watch(exerciseProgressProvider(e)).value;
    final series = progress?.series ?? const [];
    String value(int v) => switch (e.measurementKind) {
      MeasurementKind.weightReps => kgLabel(context, v),
      MeasurementKind.repsOnly => l10n.repsValue(v),
      MeasurementKind.duration => context.duration(Duration(seconds: v)),
      MeasurementKind.distanceDuration => km(context, v),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (e.isCustom)
            PopupMenuButton<String>(
              tooltip: l10n.moreActions(e.name),
              onSelected: (a) async {
                if (a == 'edit') {
                  await showFbSheet<Exercise>(context, ExerciseEditorSheet(existing: e));
                } else {
                  final ok = await showFbConfirm(
                    context,
                    title: l10n.archiveExerciseTitle,
                    message: l10n.archiveExerciseMessage,
                    confirmLabel: l10n.archive,
                    cancelLabel: l10n.cancel,
                  );
                  if (!ok) return;
                  await ref.read(workoutRepositoryProvider).archiveExercise(e.id);
                  if (context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                PopupMenuItem(value: 'archive', child: Text(l10n.archive)),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Text(
            '${e.muscleGroup} · ${e.equipment} · ${measurementName(l10n, e.measurementKind)}',
            style: context.text.caption,
          ),
          if (e.instructions != null) ...[
            const SizedBox(height: FbSpace.sm),
            Text(e.instructions!, style: context.text.body),
          ],
          const SizedBox(height: FbSpace.md),
          if (series.length < 2)
            FbEmptyHint(l10n.progressNeedsTwo, boxed: true)
          else
            FbChartCard(
              title: l10n.bestPerWorkout,
              summary: l10n.progressSummary(series.length, value(series.first.value), value(series.last.value)),
              chart: FbLineChart(
                points: [for (final (i, p) in series.indexed) (x: i.toDouble(), y: p.value.toDouble())],
                bottomLabel: (x) =>
                    context.shortDate(LocalDateFrom.instant(series[x.round().clamp(0, series.length - 1)].at)),
                leftLabel: (y) => value(y.round()),
              ),
            ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.records),
          const SizedBox(height: FbSpace.sm),
          if (progress == null)
            const FbLoading()
          else if (progress.records.isEmpty)
            FbEmptyHint(l10n.noRecordsYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final r in progress.records)
                  FbListRow(
                    title: recordName(l10n, r.kind, load: r.atLoadG == null ? null : kgLabel(context, r.atLoadG!)),
                    subtitle:
                        '${r.kind == RecordKind.mostRepsAtLoad ? l10n.repsValue(r.value) : value(r.value)} · ${context.shortDate(LocalDateFrom.instant(r.at))}',
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.recordRulesNote, style: context.text.caption),
        ],
      ),
    );
  }
}

/// Personal records: cardio by kind and every exercise with history.
class PersonalRecordsScreen extends ConsumerWidget {
  const PersonalRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final gym = ref.watch(workoutsProvider(WorkoutKind.gym)).value ?? const <WorkoutSession>[];
    final used = {
      for (final s in gym)
        for (final e in s.entries)
          if (e.sets.any((x) => x.done)) e.exercise.id,
    };
    String cardioValue(PersonalRecord r) => switch (r.kind) {
      RecordKind.longestDistance => km(context, r.value),
      RecordKind.longestDuration => clockLabel(Duration(seconds: r.value)),
      RecordKind.fastestPace => paceLabel(context, r.value),
      _ => '${r.value}',
    };
    final cardio = [
      for (final k in CardioKind.values) (k, ref.watch(cardioRecordsProvider(k))),
    ].where((e) => e.$2.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.personalRecords)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (cardio.isEmpty && used.isEmpty) FbEmptyHint(l10n.noRecordsYet, boxed: true),
          for (final (k, records) in cardio) ...[
            FbSectionTitle(
              workoutKindName(l10n, switch (k) {
                CardioKind.walk => WorkoutKind.walk,
                CardioKind.run => WorkoutKind.run,
                CardioKind.cycle => WorkoutKind.cycle,
              }),
            ),
            const SizedBox(height: FbSpace.sm),
            FbListCard(
              children: [
                for (final r in records)
                  FbListRow(
                    title: recordName(l10n, r.kind),
                    subtitle: '${cardioValue(r)} · ${context.shortDate(LocalDateFrom.instant(r.at))}',
                  ),
              ],
            ),
            const SizedBox(height: FbSpace.lg),
          ],
          if (used.isNotEmpty) ...[
            FbSectionTitle(l10n.gymExercises),
            const SizedBox(height: FbSpace.sm),
            FbListCard(
              children: [
                for (final e in exercises.where((e) => used.contains(e.id)))
                  FbListRow(
                    title: e.name,
                    subtitle: measurementName(l10n, e.measurementKind),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.exercise(e.id)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: FbSpace.md),
          Text(l10n.recordRulesNote, style: context.text.caption),
        ],
      ),
    );
  }
}
