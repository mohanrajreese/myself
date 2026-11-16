import 'package:fitbuddy/app/providers.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/units/units.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:fitbuddy/features/onboarding/application/setup_controller.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';
import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late ProviderContainer container;

  ProviderContainer build() => ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          initialSessionProvider.overrideWithValue(
            const SessionState(account: testAccount, signedIn: true),
          ),
          clockProvider.overrideWithValue(time.clock),
          idGeneratorProvider.overrideWithValue(SequentialIds()),
          timeZoneSourceProvider.overrideWithValue(const FixedTimeZone()),
        ],
      );

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 9));
    container = build();
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<SetupController> ready() async {
    await container.read(setupControllerProvider.future);
    return container.read(setupControllerProvider.notifier);
  }

  SetupDraft draft() => container.read(setupControllerProvider).value!;

  test('starts with the Google account name and a default step goal', () async {
    await ready();
    expect(draft().name, 'Asha Rao');
    expect(draft().stepsText, '8000');
    expect(draft().kcalText, isEmpty);
  });

  group('weight-based targets (decision D7)', () {
    test('opening Goals fills calories, protein and water from weight, once', () async {
      final controller = await ready();
      controller.edit((d) => d.copyWith(weightText: '91.8'));
      controller.prepareGoals();
      expect(draft().kcalText, '2750');
      expect(draft().proteinText, '110');
      expect(draft().waterText, '3200');

      controller.edit((d) => d.copyWith(kcalText: '2400'));
      controller.prepareGoals();
      expect(draft().kcalText, '2400', reason: 'user edits are not overwritten');
    });

    test('without a weight, calories and protein stay empty and water gets a default', () async {
      final controller = await ready();
      controller.prepareGoals();
      expect(draft().kcalText, isEmpty);
      expect(draft().proteinText, isEmpty);
      expect(draft().waterText, '2500');
      expect(controller.recalculate(), isFalse);
    });

    test('recalculate follows the target weight and the strength goal', () async {
      final controller = await ready();
      controller.edit((d) => d.copyWith(weightText: '91.8', targetWeightText: '80'));
      expect(controller.recalculate(), isTrue);
      expect(draft().kcalText, '2300');
      expect(draft().proteinText, '145');

      controller.edit(
        (d) => d.copyWith(targetWeightText: '', fitnessGoals: [FitnessGoalKeys.buildStrength]),
      );
      controller.recalculate();
      expect(draft().kcalText, '2750');
      expect(draft().proteinText, '145');
    });

    test('imperial weight gives the same targets, with water in fluid ounces', () async {
      final controller = await ready();
      controller.edit((d) => d.copyWith(imperial: true, weightText: '202.4'));
      controller.prepareGoals();
      expect(draft().kcalText, '2750');
      expect(draft().waterText, '108.2');
    });
  });

  test('switching units converts what is already typed', () async {
    final controller = await ready();
    controller.edit((d) => d.copyWith(weightText: '91.8', heightText: '172.5', waterText: '2500'));
    controller.edit((d) => d.withImperial(true));
    expect(draft().weightText, '202.4');
    expect(draft().heightText, '67.9');
    expect(draft().waterText, '84.5');
    controller.edit((d) => d.withImperial(false));
    expect(draft().weightText, '91.8');
  });

  test('progress is saved and restored after a restart', () async {
    final controller = await ready();
    controller.edit((d) => d.copyWith(name: 'Asha', weightText: '91.8', workoutDays: {1, 3, 5}));
    await controller.persistDraft();

    container.dispose();
    container = build();
    await ready();
    expect(draft().name, 'Asha');
    expect(draft().weightText, '91.8');
    expect(draft().workoutDays, {1, 3, 5});
  });

  test('finishing writes profile, first weight, goals and reminder choices', () async {
    final controller = await ready();
    controller.edit(
      (d) => d.copyWith(
        name: 'Asha',
        dateOfBirth: () => LocalDate(1995, 4, 2),
        heightText: '172.5',
        weightText: '91.8',
        targetWeightText: '80',
        wakeTime: () => '07:00',
        sleepHoursText: '7.5',
        workoutDays: {1, 3, 5},
        remindWater: true,
        fitnessGoals: [FitnessGoalKeys.loseWeight, 'Run 5 km'],
      ),
    );
    controller.prepareGoals();
    expect((await controller.finishOnboarding()).isOk, isTrue);

    final profile = (await container.read(profileRepositoryProvider).current('user-1'))!;
    expect(profile.displayName, 'Asha');
    expect(profile.heightMm, 1725);
    expect(profile.wakeTime, '07:00');
    expect(profile.onboardingCompleted, isTrue);

    final weight = (await container.read(weightRepositoryProvider).latest())!;
    expect(weight.weightG, 91800);
    expect(weight.entryUnit, MassUnit.kg);

    final today = LocalDate(2026, 11, 16);
    final goals = (await container.read(goalsRepositoryProvider).dailyGoalsOn(today))!;
    expect(goals.targetWeightG, 80000);
    expect(goals.dailySteps, 8000);
    expect(goals.dailyWaterMl, 3200);
    expect(goals.sleepTargetMin, 450);
    expect(goals.fitnessGoals, [FitnessGoalKeys.loseWeight, 'Run 5 km']);

    final nutrition = (await container.read(goalsRepositoryProvider).nutritionGoalsOn(today))!;
    expect(nutrition.energyKcalMilli, 2300000);
    expect(nutrition.proteinMg, 145000);

    final settings = container.read(settingsRepositoryProvider);
    expect(await settings.read(SetupKeys.reminderPrefs), {
      'water': true,
      'workout': false,
      'bedtime': false,
    });
    expect(await settings.read(SetupKeys.draft), isNull);
  });

  test('only a name is needed to finish; no weight is logged and no nutrition goal is made', () async {
    final controller = await ready();
    controller.edit((d) => d.copyWith(name: 'Asha'));
    controller.prepareGoals();
    expect((await controller.finishOnboarding()).isOk, isTrue);
    expect(await container.read(weightRepositoryProvider).latest(), isNull);
    expect(await db.select(db.nutritionGoals).get(), isEmpty);
  });

  test('invalid input stops the save and reports the field', () async {
    final controller = await ready();
    controller.edit((d) => d.copyWith(name: ''));
    expect((await controller.finishOnboarding()).failureOrNull?.code, 'required');

    controller.edit((d) => d.copyWith(name: 'Asha', weightText: '0.2'));
    expect((await controller.finishOnboarding()).failureOrNull?.code, 'out_of_range');
    expect(await db.select(db.profiles).get(), isEmpty);
  });

  test('after onboarding the draft is loaded from what was saved, for editing', () async {
    var controller = await ready();
    controller.edit((d) => d.copyWith(name: 'Asha', weightText: '91.8', sleepHoursText: '8'));
    controller.prepareGoals();
    await controller.finishOnboarding();

    container.dispose();
    container = build();
    controller = await ready();
    expect(draft().name, 'Asha');
    expect(draft().kcalText, '2750');
    expect(draft().waterText, '3200');
    expect(draft().sleepHoursText, '8');

    time.now = DateTime(2026, 11, 20, 9);
    controller.edit((d) => d.copyWith(stepsText: '10000'));
    expect((await controller.saveChanges()).isOk, isTrue);
    final goals = container.read(goalsRepositoryProvider);
    expect((await goals.dailyGoalsOn(LocalDate(2026, 11, 18)))!.dailySteps, 8000);
    expect((await goals.dailyGoalsOn(LocalDate(2026, 11, 20)))!.dailySteps, 10000);
    expect(await db.select(db.weightLogs).get(), hasLength(1), reason: 'editing logs no weight');
  });
}
