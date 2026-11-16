import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/units/units.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_progress.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../profile/domain/goals.dart';
import '../../profile/domain/profile.dart';
import '../../weight/domain/weight_entry.dart';
import '../application/home_layout.dart';

/// The dashboard (PRD §4.2). In Phase 1 it shows goals and what the user can
/// already record; each card starts working when its feature is built.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final profile = account == null ? null : ref.watch(profileProvider(account.id)).value;
    final layout = ref.watch(homeLayoutProvider).value;
    final goals = ref.watch(currentDailyGoalsProvider).value;
    final nutrition = ref.watch(currentNutritionGoalsProvider).value;
    final entries = ref.watch(todayWeightEntriesProvider).value ?? const <WeightEntry>[];

    if (profile == null || layout == null) {
      return Scaffold(body: FbLoading(semanticLabel: context.l10n.loading));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.xl, FbSpace.lg, FbSpace.xxl),
          children: [
            _Header(profile: profile),
            for (final item in layout.where((item) => item.visible)) ...[
              const SizedBox(height: FbSpace.xl),
              switch (item.section) {
                HomeSection.progress => _Progress(
                  profile: profile,
                  goals: goals,
                  nutrition: nutrition,
                ),
                HomeSection.quickAdd => const _QuickAdd(),
                HomeSection.essentials => const _Essentials(),
                HomeSection.timeline => _Timeline(entries: entries),
              },
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final now = ref.watch(clockProvider).now();
    final name = profile.displayName.trim().split(RegExp(r'\s+')).first;
    final greeting = switch (now.hour) {
      < 12 => name.isEmpty ? l10n.greetingMorningNoName : l10n.greetingMorning(name),
      < 17 => name.isEmpty ? l10n.greetingAfternoonNoName : l10n.greetingAfternoon(name),
      _ => name.isEmpty ? l10n.greetingEveningNoName : l10n.greetingEvening(name),
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(greeting, style: context.text.headline)),
              const SizedBox(height: 2),
              Text(DateFormat('EEEE, d MMMM').format(now), style: context.text.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: FbSpace.md),
        IconButton(
          onPressed: () => context.push(Routes.settings),
          tooltip: l10n.profileAndSettings,
          style: IconButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.onPrimary,
            fixedSize: const Size.square(FbSize.touch),
          ),
          icon: ExcludeSemantics(
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: context.text.bodyStrong.copyWith(color: c.onPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.profile, required this.goals, required this.nutrition});

  final Profile profile;
  final DailyGoals? goals;
  final NutritionTargets? nutrition;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final number = NumberFormat.decimalPattern();
    final metric = profile.units.volume == VolumeUnit.ml;
    String volume(int ml) => metric
        ? l10n.valueMl(number.format(ml))
        : l10n.valueFlOz(formatVolume(ml, VolumeUnit.flOz));
    String target(String? value) => value == null ? l10n.noTarget : l10n.ofTarget(value);

    final steps = goals?.dailySteps;
    final water = goals?.dailyWaterMl;
    final kcal = nutrition?.energyKcalMilli;
    final protein = nutrition?.proteinMg;
    final sleep = goals?.sleepTargetMin;

    final tiles = [
      _MetricTile(
        label: l10n.cardWater,
        value: volume(0),
        caption: target(water == null ? null : volume(water)),
        barColor: context.colors.secondary,
      ),
      _MetricTile(
        label: l10n.cardCalories,
        value: l10n.valueKcal('0'),
        caption: target(kcal == null ? null : l10n.valueKcal(number.format(kcal ~/ 1000))),
      ),
      _MetricTile(
        label: l10n.cardProtein,
        value: l10n.valueG('0'),
        caption: target(protein == null ? null : l10n.valueG(number.format(protein ~/ 1000))),
      ),
      _MetricTile(
        label: l10n.cardSleep,
        value: l10n.notLogged,
        caption: sleep == null
            ? l10n.noTarget
            : l10n.sleepTargetValue(
                sleep % 60 == 0 ? '${sleep ~/ 60}' : (sleep / 60).toStringAsFixed(1),
              ),
        barColor: context.colors.secondary,
      ),
    ];

    return Semantics(
      container: true,
      label: l10n.progressLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FbCard(
            radius: FbRadius.hero,
            padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl, vertical: FbSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.cardSteps, style: context.text.label),
                        const SizedBox(height: FbSpace.xs),
                        Text(l10n.stepsNotSetUp, style: context.text.title),
                        const SizedBox(height: FbSpace.xs),
                        Text(
                          steps == null ? l10n.noTarget : l10n.stepsGoal(number.format(steps)),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: FbSpace.lg),
                FbProgressRing(fraction: null, semanticLabel: l10n.stepsRingLabel, size: 72),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = constraints.maxWidth < 300 || scale > 1.3 ? 1 : 2;
              final width = (constraints.maxWidth - FbSpace.md * (columns - 1)) / columns;
              return Wrap(
                spacing: FbSpace.md,
                runSpacing: FbSpace.md,
                children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
              );
            },
          ),
          const SizedBox(height: FbSpace.md),
          _WorkoutRow(workoutDays: profile.workoutDays),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.caption,
    this.barColor,
  });

  final String label;
  final String value;
  final String caption;
  final Color? barColor;

  @override
  Widget build(BuildContext context) => FbCard(
    padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: 14),
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.label),
          const SizedBox(height: 6),
          Text(value, style: context.text.metric, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ExcludeSemantics(child: FbProgressBar(fraction: 0, color: barColor)),
          const SizedBox(height: 6),
          Text(caption, style: context.text.caption),
        ],
      ),
    ),
  );
}

class _WorkoutRow extends ConsumerWidget {
  const _WorkoutRow({required this.workoutDays});

  final Set<int> workoutDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider).weekday;
    final names = MaterialLocalizations.of(context).narrowWeekdays;
    final days = [...workoutDays]..sort();
    final status = workoutDays.isEmpty
        ? l10n.workoutNoDays
        : (workoutDays.contains(today) ? l10n.workoutPlanned : l10n.workoutRest);

    return FbCard(
      padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: 14),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.cardWorkout, style: context.text.label),
                  const SizedBox(height: 2),
                  Text(status, style: context.text.bodyStrong),
                ],
              ),
            ),
            if (days.isNotEmpty)
              ExcludeSemantics(
                child: Text(days.map((d) => names[d % 7]).join(' · '), style: context.text.caption),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickAdd extends StatelessWidget {
  const _QuickAdd();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbSectionTitle(l10n.quickAdd),
        const SizedBox(height: 10),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.addWeight),
              icon: const Icon(Icons.add_rounded, size: FbSpace.xl),
              label: Text(l10n.quickAddWeight),
            ),
          ],
        ),
      ],
    );
  }
}

class _Essentials extends StatelessWidget {
  const _Essentials();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FbSectionTitle(context.l10n.essentialToday),
      const SizedBox(height: 10),
      FbEmptyHint(context.l10n.essentialsEmpty, boxed: true),
    ],
  );
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.entries});
  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final time = DateFormat.jm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbSectionTitle(l10n.todayTitle),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          FbEmptyHint(l10n.timelineEmpty)
        else
          for (final entry in entries)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: MergeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        time.format(entry.occurredAt.toLocal()),
                        style: context.text.label,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.timelineWeight(
                          entry.entryUnit == MassUnit.kg
                              ? l10n.valueKg(formatMass(entry.weightG, MassUnit.kg))
                              : l10n.valueLb(formatMass(entry.weightG, MassUnit.lb)),
                        ),
                        style: context.text.body.copyWith(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
