import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/labels.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_progress.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/meals.dart';
import '../domain/nutrition_math.dart';

/// The day shown in the diary; Today unless the user steps back.
final diaryDayProvider = NotifierProvider<DiaryDay, LocalDate?>(DiaryDay.new);

class DiaryDay extends Notifier<LocalDate?> {
  @override
  LocalDate? build() => null;

  void set(LocalDate? day) => state = day;
}

/// Food diary: the Nutrition tab (PRD §4.4).
class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final day = ref.watch(diaryDayProvider) ?? today;
    final meals = ref.watch(mealsOnProvider(day));
    final eaten = ref.watch(nutritionOnProvider(day));
    final targets = ref.watch(currentNutritionGoalsProvider).value;
    final kcalTarget = targets?.energyKcalMilli;
    final left = remainingKcalMilli(targetKcalMilli: kcalTarget, eatenKcalMilli: eaten.energyKcalMilli);
    void go(LocalDate d) => ref.read(diaryDayProvider.notifier).set(d == today ? null : d);

    Future<void> pickDay() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(day.year, day.month, day.day),
        firstDate: DateTime(today.year - 5),
        lastDate: DateTime(today.year, today.month, today.day),
      );
      if (picked != null) go(LocalDate.fromDateTime(picked));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nutritionTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
              onPressed: () => context.push(Routes.addMeal),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addMeal),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.previousDay,
                  onPressed: () => go(day.addDays(-1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: pickDay,
                    child: Text(
                      day == today ? '${l10n.today}, ${context.dayLabel(day)}' : context.dayLabel(day, today: today),
                      semanticsLabel: '${l10n.chooseDay}: ${context.dayLabel(day, today: today)}',
                    ),
                  ),
                ),
                if (day.isBefore(today))
                  IconButton(
                    tooltip: l10n.nextDay,
                    onPressed: () => go(day.addDays(1)),
                    icon: const Icon(Icons.chevron_right_rounded),
                  )
                else
                  const SizedBox(width: FbSize.touch),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            radius: FbRadius.hero,
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                container: true,
                button: true,
                label: l10n.summaryNutritionTitle,
                child: InkWell(
                  borderRadius: BorderRadius.circular(FbRadius.hero),
                  onTap: () => context.push(Routes.nutritionSummary),
                  child: Padding(
                    padding: const EdgeInsets.all(FbSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                left == null ? l10n.caloriesEaten : (left >= 0 ? l10n.caloriesLeft : l10n.caloriesOver),
                                style: context.text.label,
                              ),
                              Text(
                                context.number(((left ?? eaten.energyKcalMilli).abs() + 500) ~/ 1000),
                                style: context.text.displayMetric,
                              ),
                              Text(
                                kcalTarget == null
                                    ? context.kcal(eaten.energyKcalMilli)
                                    : l10n.eatenOf(
                                        context.number((eaten.energyKcalMilli + 500) ~/ 1000),
                                        context.kcal(kcalTarget),
                                      ),
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: FbSpace.md),
                        FbProgressBar(
                          fraction: progressFraction(eaten: eaten.energyKcalMilli, target: kcalTarget),
                        ),
                        const SizedBox(height: FbSpace.md),
                        Row(
                          children: [
                            for (final (label, mg) in [
                              (l10n.macroProtein, eaten.proteinMg),
                              (l10n.macroCarbs, eaten.carbsMg),
                              (l10n.macroFat, eaten.fatMg),
                              (l10n.macroFibre, eaten.fibreMg),
                            ])
                              Expanded(
                                child: MergeSemantics(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(context.grams(mg), style: context.text.bodyStrong.copyWith(fontSize: 15)),
                                      Text(label, style: context.text.caption),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: FbSpace.md),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              OutlinedButton(onPressed: () => context.push(Routes.water), child: Text(l10n.waterTitle)),
              OutlinedButton(onPressed: () => context.push(Routes.foods), child: Text(l10n.myFoods)),
              OutlinedButton(onPressed: () => context.push(Routes.savedMeals), child: Text(l10n.savedMeals)),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          meals.when(
            loading: () => FbLoading(semanticLabel: l10n.loading),
            error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
            data: (list) => list.isEmpty
                ? FbEmptyHint(l10n.mealsEmpty, boxed: true)
                : Column(children: [for (final m in list) _MealCard(meal: m)]),
          ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.diaryHelp, style: context.text.caption),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});
  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = mealName(l10n, meal.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: FbSpace.md),
      child: FbCard(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(FbRadius.card),
            onTap: () => context.push(Routes.editMeal(meal.id), extra: meal),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.md, FbSpace.lg, FbSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: name,
                            style: context.text.bodyStrong,
                            children: [
                              TextSpan(text: '  ${context.time(meal.occurredAt)}', style: context.text.caption),
                            ],
                          ),
                          semanticsLabel: l10n.mealCardLabel(
                            name,
                            context.time(meal.occurredAt),
                            context.kcal(meal.total.energyKcalMilli),
                          ),
                        ),
                      ),
                      if (meal.hasPhoto)
                        Icon(
                          Icons.photo_outlined,
                          size: FbSpace.xl,
                          color: context.colors.textSecondary,
                          semanticLabel: l10n.mealPhoto,
                        ),
                      const SizedBox(width: FbSpace.sm),
                      Text(
                        context.kcal(meal.total.energyKcalMilli),
                        style: context.text.bodyStrong.copyWith(color: context.colors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: FbSpace.xs),
                  for (final item in meal.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              [item.foodName, if (item.junk != null) junkLabel(l10n, item.junk)].join(' · '),
                              style: context.text.bodySmall.copyWith(color: context.colors.textPrimary),
                            ),
                          ),
                          Text(context.kcal(item.values.energyKcalMilli), style: context.text.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saved meals: log one again in a tap.
class SavedMealsScreen extends ConsumerWidget {
  const SavedMealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(savedMealsProvider);

    Future<void> log(SavedMeal meal) async {
      final result = await ref.read(mealRepositoryProvider).logSaved(meal.id);
      if (!context.mounted) return;
      showFbSnackBar(context, result.isOk ? l10n.savedMealLogged(meal.name) : l10n.errSaveFailed);
    }

    Future<void> delete(SavedMeal meal) async {
      final agreed = await showFbConfirm(
        context,
        title: l10n.deleteSavedTitle,
        message: l10n.deleteSavedMessage,
        confirmLabel: l10n.delete,
        cancelLabel: l10n.cancel,
        destructive: true,
      );
      if (agreed) await ref.read(mealRepositoryProvider).deleteSaved(meal.id);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savedMeals)),
      body: saved.when(
        loading: () => FbLoading(semanticLabel: l10n.loading),
        error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
          children: [
            if (list.isEmpty)
              FbEmptyHint(l10n.savedMealsEmpty, boxed: true)
            else
              FbListCard(
                children: [
                  for (final m in list)
                    FbListRow(
                      title: m.name,
                      subtitle: [
                        if (m.category != null) mealName(l10n, m.category!),
                        l10n.savedMealItems(
                          m.items.length,
                          context.kcal(sumNutrition(m.items.map((i) => i.values)).energyKcalMilli),
                        ),
                      ].join(' · '),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.delete,
                            onPressed: () => delete(m),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
                            onPressed: () => log(m),
                            child: Text(l10n.logSavedMeal),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Nutrition summary: today against targets, meal shares, weekly averages,
/// junk-food history (PRD §5.4).
class NutritionSummaryScreen extends ConsumerWidget {
  const NutritionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final eaten = ref.watch(nutritionOnProvider(today));
    final meals = ref.watch(mealsOnProvider(today)).value ?? const <Meal>[];
    final targets = ref.watch(currentNutritionGoalsProvider).value;
    final week = (from: today.addDays(-6), to: today);
    final totals = ref.watch(nutritionTotalsProvider(week)).value ?? const {};
    final junk = ref.watch(junkBetweenProvider(week)).value ?? const <JunkEntry>[];
    final average = dailyAverage(totals);
    final byMeal = <MealCategory, int>{};
    for (final m in meals) {
      byMeal.update(m.category, (v) => v + m.total.energyKcalMilli, ifAbsent: () => m.total.energyKcalMilli);
    }
    final shares = caloriesByMeal(byMeal);
    final palette = [context.colors.primary, context.colors.secondary, context.colors.warning, context.colors.success];

    Widget targetRow(String label, int value, int? target, String Function(int) fmt) => Padding(
      padding: const EdgeInsets.only(bottom: FbSpace.md),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: context.text.body)),
                const SizedBox(width: FbSpace.sm),
                Flexible(
                  child: Text(
                    target == null ? l10n.noTargetSuffix(fmt(value)) : l10n.ofTargetValue(fmt(value), fmt(target)),
                    style: context.text.bodySmall,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            if (target != null) ...[
              const SizedBox(height: FbSpace.xs),
              FbProgressBar(
                fraction: progressFraction(eaten: value, target: target),
              ),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.summaryNutritionTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FbSectionTitle(l10n.todayVsTargets),
                const SizedBox(height: FbSpace.md),
                targetRow(l10n.energyLabel, eaten.energyKcalMilli, targets?.energyKcalMilli, context.kcal),
                targetRow(l10n.proteinLabel, eaten.proteinMg, targets?.proteinMg, context.grams),
                targetRow(l10n.fibreLabel, eaten.fibreMg, targets?.fibreMg, context.grams),
                targetRow(l10n.carbsLabel, eaten.carbsMg, targets?.carbsMg, context.grams),
                targetRow(l10n.fatLabel, eaten.fatMg, targets?.fatMg, context.grams),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FbSectionTitle(l10n.caloriesFromMeals),
                const SizedBox(height: FbSpace.md),
                if (shares.isEmpty)
                  FbEmptyHint(l10n.mealsEmpty)
                else ...[
                  Semantics(
                    label: shares.map((s) => l10n.mealShareSummary(mealName(l10n, s.category), s.percent)).join(', '),
                    image: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(FbRadius.input),
                      child: SizedBox(
                        height: 16,
                        child: Row(
                          children: [
                            for (var i = 0; i < shares.length; i++)
                              Expanded(
                                flex: shares[i].percent.clamp(1, 100),
                                child: ColoredBox(color: palette[i % palette.length]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: FbSpace.sm),
                  Wrap(
                    spacing: FbSpace.lg,
                    runSpacing: FbSpace.xs,
                    children: [
                      for (var i = 0; i < shares.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(dimension: 10, child: ColoredBox(color: palette[i % palette.length])),
                            const SizedBox(width: 6),
                            Text(
                              l10n.mealShare(mealName(l10n, shares[i].category), context.kcal(shares[i].kcalMilli)),
                              style: context.text.caption,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FbSectionTitle(l10n.average7),
                const SizedBox(height: FbSpace.md),
                Row(
                  children: [
                    for (final (label, text) in [
                      (l10n.unitKcal, context.number((average.values.energyKcalMilli + 500) ~/ 1000)),
                      (l10n.macroProtein, context.grams(average.values.proteinMg)),
                      (l10n.macroCarbs, context.grams(average.values.carbsMg)),
                      (l10n.macroFat, context.grams(average.values.fatMg)),
                      (l10n.macroFibre, context.grams(average.values.fibreMg)),
                    ])
                      Expanded(
                        child: MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(text, style: context.text.bodyStrong.copyWith(fontSize: 15)),
                              Text(label, style: context.text.caption),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.averagedOver(average.days), style: context.text.caption),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FbSectionTitle(
                  l10n.junk7,
                  trailing: junk.isEmpty
                      ? null
                      : l10n.junkCount(
                          junk.length,
                          context.kcal(sumNutrition(junk.map((j) => j.values)).energyKcalMilli),
                        ),
                ),
                const SizedBox(height: FbSpace.sm),
                if (junk.isEmpty)
                  FbEmptyHint(l10n.junkNoneLogged)
                else
                  for (final j in junk)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: MergeSemantics(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${j.foodName} · ${junkLabel(l10n, j.category)} · ${context.dayLabel(j.date, today: today)}',
                                style: context.text.bodySmall.copyWith(color: context.colors.textPrimary),
                              ),
                            ),
                            Text(context.kcal(j.values.energyKcalMilli), style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.junkNote, style: context.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Used by the router to show a meal that could not be found.
class MealMissingScreen extends StatelessWidget {
  const MealMissingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: FbErrorState(message: context.l10n.errSaveFailed),
  );
}
