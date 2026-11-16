import 'package:meta/meta.dart';

import '../../../core/units/decimal_text.dart';
import '../../../core/units/units.dart';
import '../../../core/utils/local_date.dart';
import '../../profile/domain/goal_suggestions.dart';
import '../../profile/domain/goals.dart';
import '../../profile/domain/profile.dart';

/// Preset fitness goals. Stored by key; anything else is the user's own text.
abstract final class FitnessGoalKeys {
  static const loseWeight = 'lose_weight';
  static const buildStrength = 'build_strength';
  static const improveStamina = 'improve_stamina';
  static const stayActive = 'stay_active';
  static const presets = [loseWeight, buildStrength, improveStamina, stayActive];
}

/// Everything the setup screens edit, as the user typed it. Text fields stay
/// text so half-typed input survives; parsing happens on validation and save.
@immutable
final class SetupDraft {
  const SetupDraft({
    this.imperial = false,
    this.name = '',
    this.dateOfBirth,
    this.heightText = '',
    this.weightText = '',
    this.targetWeightText = '',
    this.stepsText = '8000',
    this.kcalText = '',
    this.proteinText = '',
    this.waterText = '',
    this.fitnessGoals = const [],
    this.wakeTime,
    this.sleepHoursText = '8',
    this.workoutDays = const {},
    this.remindWater = false,
    this.remindWorkout = false,
    this.remindBedtime = false,
    this.suggestionsApplied = false,
  });

  factory SetupDraft.fromJson(Map<String, Object?> json) => SetupDraft(
        imperial: json['imperial'] == true,
        name: json['name'] as String? ?? '',
        dateOfBirth: switch (json['dob']) { final String s => LocalDate.parse(s), _ => null },
        heightText: json['height'] as String? ?? '',
        weightText: json['weight'] as String? ?? '',
        targetWeightText: json['target'] as String? ?? '',
        stepsText: json['steps'] as String? ?? '',
        kcalText: json['kcal'] as String? ?? '',
        proteinText: json['protein'] as String? ?? '',
        waterText: json['water'] as String? ?? '',
        fitnessGoals: (json['fitness'] as List<Object?>? ?? const []).cast<String>(),
        wakeTime: json['wake'] as String?,
        sleepHoursText: json['sleep'] as String? ?? '',
        workoutDays: (json['days'] as List<Object?>? ?? const []).cast<int>().toSet(),
        remindWater: json['r_water'] == true,
        remindWorkout: json['r_workout'] == true,
        remindBedtime: json['r_bed'] == true,
        suggestionsApplied: json['suggested'] == true,
      );

  final bool imperial;
  final String name;
  final LocalDate? dateOfBirth;
  final String heightText;
  final String weightText;
  final String targetWeightText;
  final String stepsText;
  final String kcalText;
  final String proteinText;
  final String waterText;
  final List<String> fitnessGoals;
  final String? wakeTime;
  final String sleepHoursText;
  final Set<int> workoutDays;
  final bool remindWater;
  final bool remindWorkout;
  final bool remindBedtime;

  /// True once weight-based targets have been filled in automatically, so
  /// they are not overwritten each time the Goals step is opened.
  final bool suggestionsApplied;

  UnitPreferences get units => imperial ? UnitPreferences.imperial : UnitPreferences.metric;

  int? get weightG => gramsFromText(weightText, units.mass);
  int? get targetWeightG => gramsFromText(targetWeightText, units.mass);
  int? get heightMm => millimetresFromText(heightText, units.length);
  int? get waterMl => millilitresFromText(waterText, units.volume);
  int? get steps => int.tryParse(stepsText);
  int? get kcal => int.tryParse(kcalText);
  int? get proteinG => int.tryParse(proteinText);

  /// Tenths of an hour, so `7.5` hours is 450 minutes.
  int? get sleepMinutes => switch (parseScaled(sleepHoursText, 1)) {
        null => null,
        final tenths => tenths * 6,
      };

  Map<String, Object?> toJson() => {
        'imperial': imperial,
        'name': name,
        'dob': dateOfBirth?.toString(),
        'height': heightText,
        'weight': weightText,
        'target': targetWeightText,
        'steps': stepsText,
        'kcal': kcalText,
        'protein': proteinText,
        'water': waterText,
        'fitness': fitnessGoals,
        'wake': wakeTime,
        'sleep': sleepHoursText,
        'days': workoutDays.toList()..sort(),
        'r_water': remindWater,
        'r_workout': remindWorkout,
        'r_bed': remindBedtime,
        'suggested': suggestionsApplied,
      };

  SetupDraft copyWith({
    bool? imperial,
    String? name,
    LocalDate? Function()? dateOfBirth,
    String? heightText,
    String? weightText,
    String? targetWeightText,
    String? stepsText,
    String? kcalText,
    String? proteinText,
    String? waterText,
    List<String>? fitnessGoals,
    String? Function()? wakeTime,
    String? sleepHoursText,
    Set<int>? workoutDays,
    bool? remindWater,
    bool? remindWorkout,
    bool? remindBedtime,
    bool? suggestionsApplied,
  }) =>
      SetupDraft(
        imperial: imperial ?? this.imperial,
        name: name ?? this.name,
        dateOfBirth: dateOfBirth == null ? this.dateOfBirth : dateOfBirth(),
        heightText: heightText ?? this.heightText,
        weightText: weightText ?? this.weightText,
        targetWeightText: targetWeightText ?? this.targetWeightText,
        stepsText: stepsText ?? this.stepsText,
        kcalText: kcalText ?? this.kcalText,
        proteinText: proteinText ?? this.proteinText,
        waterText: waterText ?? this.waterText,
        fitnessGoals: fitnessGoals ?? this.fitnessGoals,
        wakeTime: wakeTime == null ? this.wakeTime : wakeTime(),
        sleepHoursText: sleepHoursText ?? this.sleepHoursText,
        workoutDays: workoutDays ?? this.workoutDays,
        remindWater: remindWater ?? this.remindWater,
        remindWorkout: remindWorkout ?? this.remindWorkout,
        remindBedtime: remindBedtime ?? this.remindBedtime,
        suggestionsApplied: suggestionsApplied ?? this.suggestionsApplied,
      );

  /// Switches between metric and imperial, converting what is already typed.
  SetupDraft withImperial(bool value) {
    if (value == imperial) return this;
    final next = value ? UnitPreferences.imperial : UnitPreferences.metric;
    String mass(int? grams, String original) => grams == null ? original : formatMass(grams, next.mass);
    return copyWith(
      imperial: value,
      weightText: mass(weightG, weightText),
      targetWeightText: mass(targetWeightG, targetWeightText),
      heightText: switch (heightMm) { null => heightText, final mm => formatLength(mm, next.length) },
      waterText: switch (waterMl) { null => waterText, final ml => formatVolume(ml, next.volume) },
    );
  }

  /// Fills calories, protein and water from body weight (decision D7).
  /// Returns this draft unchanged when no weight is known.
  SetupDraft withSuggestedTargets() {
    final suggestion = suggestGoals(
      weightG: weightG,
      targetWeightG: targetWeightG,
      buildStrength: fitnessGoals.contains(FitnessGoalKeys.buildStrength),
    );
    if (suggestion == null) return this;
    return copyWith(
      kcalText: '${suggestion.energyKcalMilli ~/ 1000}',
      proteinText: '${suggestion.proteinMg ~/ 1000}',
      waterText: formatVolume(suggestion.dailyWaterMl, units.volume),
      suggestionsApplied: true,
    );
  }

  ProfileDraft toProfileDraft() => ProfileDraft(
        displayName: name,
        dateOfBirth: dateOfBirth,
        heightMm: heightText.trim().isEmpty ? null : heightMm,
        units: units,
        wakeTime: wakeTime,
        workoutDays: workoutDays,
      );

  DailyGoals toDailyGoals() => DailyGoals(
        targetWeightG: targetWeightG,
        dailySteps: steps,
        dailyWaterMl: waterMl,
        sleepTargetMin: sleepMinutes,
        fitnessGoals: fitnessGoals,
      );

  NutritionTargets toNutritionTargets() => NutritionTargets(
        energyKcalMilli: switch (kcal) { null => null, final v => v * 1000 },
        proteinMg: switch (proteinG) { null => null, final v => v * 1000 },
      );

  bool get hasNutritionTargets => kcalText.trim().isNotEmpty || proteinText.trim().isNotEmpty;

  /// Field name to error code for the profile step.
  Map<String, String> profileErrors({required LocalDate today}) {
    final errors = <String, String>{};
    if (heightText.trim().isNotEmpty && heightMm == null) errors['heightMm'] = 'invalid';
    final weight = weightText.trim().isEmpty ? null : weightG;
    if (weightText.trim().isNotEmpty && (weight == null || weight < 1000 || weight > 700000)) {
      errors['weightG'] = 'out_of_range';
    }
    final failure = toProfileDraft().validate(today: today);
    if (failure != null) errors.putIfAbsent(failure.field, () => failure.code);
    return errors;
  }

  Map<String, String> goalErrors() {
    final errors = <String, String>{};
    void number(String field, String text, Object? parsed) {
      if (text.trim().isNotEmpty && parsed == null) errors[field] = 'invalid';
    }

    number('targetWeightG', targetWeightText, targetWeightG);
    number('dailySteps', stepsText, steps);
    number('energyKcalMilli', kcalText, kcal);
    number('proteinMg', proteinText, proteinG);
    number('dailyWaterMl', waterText, waterMl);
    for (final failure in [toDailyGoals().validate(), toNutritionTargets().validate()]) {
      if (failure != null) errors.putIfAbsent(failure.field, () => failure.code);
    }
    return errors;
  }

  Map<String, String> dayErrors() {
    final errors = <String, String>{};
    final minutes = sleepMinutes;
    if (sleepHoursText.trim().isNotEmpty && (minutes == null || minutes > 1440)) {
      errors['sleepTargetMin'] = 'out_of_range';
    }
    return errors;
  }
}
