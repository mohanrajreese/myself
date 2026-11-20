import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fitness_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_progress.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/workouts.dart';
import 'fitness_labels.dart';

/// Fitness tab overview (approved design "Fitness overview").
class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  Future<void> _startGym(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final active = ref.read(activeGymProvider);
    if (active != null) {
      unawaited(context.push(Routes.workout(active.id)));
      return;
    }
    final templates = ref.read(templatesProvider).value ?? const <WorkoutTemplate>[];
    String? templateId;
    var name = l10n.defaultWorkoutName;
    if (templates.isNotEmpty) {
      final picked = await showFbSheet<WorkoutTemplate?>(
        context,
        FbSheetBody(
          title: l10n.startWorkout,
          children: [
            ListTile(title: Text(l10n.emptyWorkout), onTap: () => Navigator.of(context).pop(null)),
            for (final t in templates)
              ListTile(
                title: Text(t.name),
                subtitle: Text(l10n.exercisesCount(t.exercises.length)),
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      );
      if (!context.mounted) return;
      templateId = picked?.id;
      name = picked?.name ?? name;
    }
    final id = (await ref.read(workoutRepositoryProvider).startGym(name: name, templateId: templateId)).valueOrNull;
    if (id != null && context.mounted) unawaited(context.push(Routes.workout(id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final goal = ref.watch(currentDailyGoalsProvider).value?.dailySteps;
    final steps = ref.watch(stepDayProvider(today)).value;
    final status = ref.watch(stepStatusProvider).value;
    final week = ref.watch(workoutsBetweenProvider((from: today.addDays(-6), to: today))).value ?? const [];
    final active = ref.watch(activeGymProvider);
    final distance = week.fold(0, (n, s) => n + (s.kind == WorkoutKind.gym ? 0 : s.distanceM ?? 0));
    final time = week.fold(0, (n, s) => n + s.durationS);
    final total = steps?.total ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabFitness)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => context.push(Routes.steps),
              child: Padding(
                padding: const EdgeInsets.all(FbSpace.lg),
                child: Row(
                  children: [
                    FbProgressRing(
                      fraction: goal == null || goal == 0 || status?.permission != true
                          ? null
                          : (total / goal).clamp(0, 1),
                      semanticLabel: l10n.stepsTodayLabel(context.number(total)),
                      size: 84,
                    ),
                    const SizedBox(width: FbSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.stepsTodayTitle, style: context.text.label),
                          Text(
                            status == null || status.permission ? context.number(total) : l10n.stepsNotSetUp,
                            style: context.text.title,
                          ),
                          Text(
                            status != null && !status.supported
                                ? l10n.stepsUnsupportedShort
                                : status != null && !status.permission
                                ? l10n.stepsTapToSetUp
                                : goal == null
                                ? l10n.noTarget
                                : l10n.stepsToGoOf(context.number((goal - total).clamp(0, goal)), context.number(goal)),
                            style: context.text.caption,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: FbSectionTitle(l10n.thisWeek)),
                    TextButton(onPressed: () => context.push(Routes.workoutHistory), child: Text(l10n.historyTitle)),
                  ],
                ),
                Row(
                  children: [
                    _Stat('${week.where((s) => !s.inProgress).length}', l10n.workoutsLabel),
                    _Stat(km(context, distance), l10n.distanceLabel),
                    _Stat(context.duration(Duration(seconds: time)), l10n.activeTime),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.startOrLog),
          const SizedBox(height: FbSpace.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => _startGym(context, ref),
            icon: const Icon(Icons.fitness_center_rounded),
            label: Text(active == null ? l10n.gymWorkout : l10n.continueWorkout(active.name)),
          ),
          const SizedBox(height: FbSpace.sm),
          Row(
            children: [
              for (final k in const [WorkoutKind.walk, WorkoutKind.run, WorkoutKind.cycle]) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () => context.push(Routes.logCardio(k.code)),
                    icon: Icon(workoutIcon(k)),
                    label: Text(workoutKindName(l10n, k)),
                  ),
                ),
                if (k != WorkoutKind.cycle) const SizedBox(width: FbSpace.sm),
              ],
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          FbListCard(
            children: [
              FbListRow(
                title: l10n.personalRecords,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.records),
              ),
              FbListRow(
                title: l10n.exerciseLibrary,
                subtitle: l10n.exercisesCount(ref.watch(exercisesProvider).value?.length ?? 0),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.exerciseLibrary),
              ),
              FbListRow(
                title: l10n.templates,
                subtitle: (ref.watch(templatesProvider).value ?? const []).map((t) => t.name).join(' · '),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.workoutHistory),
              ),
            ],
          ),
          if (status != null && !status.supported) ...[
            const SizedBox(height: FbSpace.md),
            FbNotice(l10n.stepsUnsupportedBody),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.text.bodyStrong.copyWith(fontSize: 17)),
          Text(label, style: context.text.caption),
        ],
      ),
    ),
  );
}
