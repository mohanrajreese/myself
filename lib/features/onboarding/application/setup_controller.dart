import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/unit_codes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/units/units.dart';
import '../../profile/domain/profile.dart';
import 'setup_draft.dart';

abstract final class SetupKeys {
  static const draft = 'onboarding_draft';
  static const reminderPrefs = 'reminder_prefs';

  /// Route of the onboarding step to reopen after a restart.
  static const resumePath = 'onboarding_step';
}

final setupControllerProvider = AsyncNotifierProvider<SetupController, SetupDraft>(
  SetupController.new,
);

/// Holds what the user is entering during onboarding, and what they are
/// editing later in Settings. Progress through onboarding is saved after each
/// step, so closing the app resumes where they stopped.
class SetupController extends AsyncNotifier<SetupDraft> {
  String get _accountId => ref.read(currentAccountProvider)!.id;

  @override
  Future<SetupDraft> build() async {
    final account = ref.watch(currentAccountProvider);
    if (account == null) return const SetupDraft();

    final settings = ref.read(settingsRepositoryProvider);
    final stored = await settings.read(SetupKeys.draft);
    if (stored is Map<String, Object?>) return SetupDraft.fromJson(stored);

    final profile = await ref.read(profileRepositoryProvider).current(account.id);
    if (profile == null) return SetupDraft(name: account.displayName ?? '');
    return _fromSaved(profile);
  }

  Future<SetupDraft> _fromSaved(Profile profile) async {
    final today = ref.read(todayProvider);
    final goals = await ref.read(goalsRepositoryProvider).dailyGoalsOn(today);
    final nutrition = await ref.read(goalsRepositoryProvider).nutritionGoalsOn(today);
    final weight = await ref.read(weightRepositoryProvider).latest();
    final prefs = await ref.read(settingsRepositoryProvider).read(SetupKeys.reminderPrefs);
    final reminders = prefs is Map<String, Object?> ? prefs : const <String, Object?>{};
    final units = profile.units;
    String mass(int? grams) => grams == null ? '' : formatMass(grams, units.mass);

    return SetupDraft(
      imperial: units.mass == MassUnit.lb,
      name: profile.displayName,
      dateOfBirth: profile.dateOfBirth,
      heightText: switch (profile.heightMm) {
        null => '',
        final mm => formatLength(mm, units.length),
      },
      weightText: mass(weight?.weightG),
      targetWeightText: mass(goals?.targetWeightG),
      stepsText: goals?.dailySteps?.toString() ?? '',
      kcalText: switch (nutrition?.energyKcalMilli) {
        null => '',
        final v => '${v ~/ 1000}',
      },
      proteinText: switch (nutrition?.proteinMg) {
        null => '',
        final v => '${v ~/ 1000}',
      },
      waterText: switch (goals?.dailyWaterMl) {
        null => '',
        final ml => formatVolume(ml, units.volume),
      },
      fitnessGoals: goals?.fitnessGoals ?? const [],
      wakeTime: profile.wakeTime,
      sleepHoursText: switch (goals?.sleepTargetMin) {
        null => '',
        final minutes => minutes % 60 == 0 ? '${minutes ~/ 60}' : (minutes / 60).toStringAsFixed(1),
      },
      workoutDays: profile.workoutDays,
      remindWater: reminders['water'] == true,
      remindWorkout: reminders['workout'] == true,
      remindBedtime: reminders['bedtime'] == true,
      suggestionsApplied: true,
    );
  }

  SetupDraft get _draft => state.value ?? const SetupDraft();

  void edit(SetupDraft Function(SetupDraft draft) change) => state = AsyncData(change(_draft));

  /// Saves onboarding progress so it can be resumed at [nextPath].
  Future<void> persistDraft({String? nextPath}) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.write(SetupKeys.draft, _draft.toJson());
    if (nextPath != null) await settings.write(SetupKeys.resumePath, nextPath);
  }

  /// Called when the Goals step opens: fills weight-based targets once.
  void prepareGoals() {
    final draft = _draft;
    if (draft.suggestionsApplied) return;
    final suggested = draft.withSuggestedTargets();
    state = AsyncData(
      suggested.suggestionsApplied
          ? suggested
          : draft.copyWith(
              waterText: draft.waterText.isEmpty
                  ? formatVolume(2500, draft.units.volume)
                  : draft.waterText,
            ),
    );
  }

  /// Replaces calories, protein and water with fresh weight-based estimates.
  /// Returns false when there is no weight to work from.
  bool recalculate() {
    final suggested = _draft.withSuggestedTargets();
    if (identical(suggested, _draft)) return false;
    state = AsyncData(suggested);
    return true;
  }

  /// Writes everything and marks onboarding complete.
  Future<Result<void>> finishOnboarding() async {
    final saved = await _save(recordWeight: true);
    if (!saved.isOk) return saved;
    final done = await ref.read(profileRepositoryProvider).completeOnboarding(_accountId);
    if (!done.isOk) return done;
    await ref.read(settingsRepositoryProvider).remove(SetupKeys.draft);
    await ref.read(settingsRepositoryProvider).remove(SetupKeys.resumePath);
    return const Ok(null);
  }

  /// Saves edits made from Settings. Weight is logged from Home, not here.
  Future<Result<void>> saveChanges() => _save(recordWeight: false);

  Future<Result<void>> _save({required bool recordWeight}) async {
    final draft = _draft;
    final today = ref.read(todayProvider);
    final errors = {
      ...draft.profileErrors(today: today),
      ...draft.goalErrors(),
      ...draft.dayErrors(),
    };
    if (errors.isNotEmpty) {
      final first = errors.entries.first;
      return Err(ValidationFailure(first.key, first.value));
    }

    final profile = await ref
        .read(profileRepositoryProvider)
        .save(_accountId, draft.toProfileDraft());
    if (!profile.isOk) return Err(profile.failureOrNull!);

    final weightG = draft.weightG;
    if (recordWeight && weightG != null) {
      final weight = await ref
          .read(weightRepositoryProvider)
          .add(weightG: weightG, entryUnit: MassUnitCode.parse(draft.units.mass.code));
      if (!weight.isOk) return Err(weight.failureOrNull!);
    }

    final goals = ref.read(goalsRepositoryProvider);
    final daily = await goals.saveDailyGoals(draft.toDailyGoals());
    if (!daily.isOk) return daily;
    if (draft.hasNutritionTargets || await goals.nutritionGoalsOn(today) != null) {
      final nutrition = await goals.saveNutritionGoals(draft.toNutritionTargets());
      if (!nutrition.isOk) return nutrition;
    }

    await ref.read(settingsRepositoryProvider).write(SetupKeys.reminderPrefs, {
      'water': draft.remindWater,
      'workout': draft.remindWorkout,
      'bedtime': draft.remindBedtime,
    });
    return const Ok(null);
  }
}
