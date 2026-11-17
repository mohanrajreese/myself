import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/labels.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/widgets/fb_format.dart';
import '../../nutrition/domain/nutrition_math.dart';
import '../../sleep/domain/sleep_math.dart';
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

class _Progress extends ConsumerWidget {
  const _Progress({required this.profile, required this.goals, required this.nutrition});

  final Profile profile;
  final DailyGoals? goals;
  final NutritionTargets? nutrition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final volumeUnit = profile.units.volume;
    String target(String? value) => value == null ? l10n.noTarget : l10n.ofTarget(value);

    final steps = goals?.dailySteps;
    final waterTarget = goals?.dailyWaterMl;
    final nutritionTarget = nutrition;
    final sleepTarget = goals?.sleepTargetMin;
    final water = ref.watch(waterTotalOnProvider(today));
    final eaten = ref.watch(nutritionOnProvider(today));
    final slept = ref.watch(sleepOnProvider(today));

    final tiles = [
      _MetricTile(
        label: l10n.cardWater,
        value: context.volume(water, volumeUnit),
        caption: target(waterTarget == null ? null : context.volume(waterTarget, volumeUnit)),
        fraction: progressFraction(eaten: water, target: waterTarget),
        barColor: context.colors.secondary,
        onTap: () => context.push(Routes.water),
      ),
      _MetricTile(
        label: l10n.cardCalories,
        value: context.kcal(eaten.energyKcalMilli),
        caption: target(
          nutritionTarget?.energyKcalMilli == null
              ? null
              : context.kcal(nutritionTarget!.energyKcalMilli!),
        ),
        fraction: progressFraction(
          eaten: eaten.energyKcalMilli,
          target: nutritionTarget?.energyKcalMilli,
        ),
        onTap: () => context.go(Routes.nutrition),
      ),
      _MetricTile(
        label: l10n.cardProtein,
        value: context.grams(eaten.proteinMg),
        caption: target(
          nutritionTarget?.proteinMg == null ? null : context.grams(nutritionTarget!.proteinMg!),
        ),
        fraction: progressFraction(eaten: eaten.proteinMg, target: nutritionTarget?.proteinMg),
        onTap: () => context.push(Routes.nutritionSummary),
      ),
      _MetricTile(
        label: l10n.cardFibre,
        value: context.grams(eaten.fibreMg),
        caption: target(
          nutritionTarget?.fibreMg == null ? null : context.grams(nutritionTarget!.fibreMg!),
        ),
        fraction: progressFraction(eaten: eaten.fibreMg, target: nutritionTarget?.fibreMg),
        onTap: () => context.push(Routes.nutritionSummary),
      ),
      _MetricTile(
        label: l10n.cardSleep,
        value: slept == null ? l10n.notLogged : context.duration(slept),
        caption: sleepTarget == null
            ? l10n.noTarget
            : l10n.sleepTargetValue(
                sleepTarget % 60 == 0
                    ? '${sleepTarget ~/ 60}'
                    : (sleepTarget / 60).toStringAsFixed(1),
              ),
        fraction: slept == null ? 0 : progressFraction(eaten: slept.inMinutes, target: sleepTarget),
        barColor: context.colors.secondary,
        onTap: () => context.push(Routes.sleep),
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
                          steps == null ? l10n.noTarget : l10n.stepsGoal(context.number(steps)),
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
    required this.onTap,
    this.fraction = 0,
    this.barColor,
  });

  final String label;
  final String value;
  final String caption;
  final double fraction;
  final VoidCallback onTap;
  final Color? barColor;

  @override
  Widget build(BuildContext context) => FbCard(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(FbRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.label),
              const SizedBox(height: 6),
              Text(value, style: context.text.metric, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: FbProgressBar(fraction: fraction, color: barColor),
              ),
              const SizedBox(height: 6),
              Text(caption, style: context.text.caption),
            ],
          ),
        ),
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
            for (final (label, route) in [
              (l10n.quickAddMeal, Routes.addMeal),
              (l10n.quickAddWater, Routes.addWater),
              (l10n.quickAddWeight, Routes.addWeight),
              (l10n.quickAddSleep, Routes.addSleep),
            ])
              OutlinedButton.icon(
                onPressed: () => context.push(route),
                icon: const Icon(Icons.add_rounded, size: FbSpace.xl),
                label: Text(label),
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
    final today = ref.watch(todayProvider);
    final units = ref.watch(unitsProvider);
    final water = ref.watch(waterOnProvider(today)).value ?? const [];
    final meals = ref.watch(mealsOnProvider(today)).value ?? const [];
    final sleep = ref.watch(sleepBetweenProvider((from: today, to: today))).value ?? const [];
    final checkins = ref.watch(wellnessBetweenProvider((from: today, to: today))).value ?? const [];

    final events = <(DateTime, String)>[
      for (final e in entries)
        (e.occurredAt, l10n.timelineWeight(context.mass(e.weightG, e.entryUnit))),
      for (final w in water)
        (w.occurredAt, l10n.timelineWater(context.volume(w.amountMl, units.volume))),
      for (final m in meals)
        (
          m.occurredAt,
          l10n.timelineMeal(mealName(l10n, m.category), context.kcal(m.total.energyKcalMilli)),
        ),
      for (final s in sleep.where(
        (s) => s.period.kind == SleepKind.night && s.period.wakeDate == today,
      ))
        (s.period.end, l10n.timelineWoke(context.duration(s.period.duration))),
      for (final c in checkins) (c.occurredAt, l10n.timelineCheckin),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbSectionTitle(l10n.todayTitle),
        const SizedBox(height: 10),
        if (events.isEmpty)
          FbEmptyHint(l10n.timelineEmpty)
        else
          for (final (at, text) in events)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: MergeSemantics(
                child: Row(
                  children: [
                    SizedBox(width: 76, child: Text(context.time(at), style: context.text.label)),
                    Expanded(child: Text(text, style: context.text.body.copyWith(fontSize: 15))),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
