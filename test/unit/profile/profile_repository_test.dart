import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/units/units.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/profile/data/drift_profile_repository.dart';
import 'package:fitbuddy/features/profile/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftProfileRepository profiles;

  const draft = ProfileDraft(displayName: 'Asha');

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 9));
    profiles = DriftProfileRepository(db, clock: time.clock, timeZone: const FixedTimeZone());
  });
  tearDown(() => db.close());

  test('there is no profile before one is saved', () async {
    expect(await profiles.current('user-1'), isNull);
  });

  test('saves the profile under the account id with units and timezone', () async {
    await profiles.save(
      'user-1',
      ProfileDraft(
        displayName: '  Asha  ',
        dateOfBirth: LocalDate(1995, 4, 2),
        heightMm: 1725,
        units: const UnitPreferences(mass: MassUnit.lb, length: LengthUnit.inch),
        wakeTime: '07:00',
        workoutDays: const {1, 3, 5},
      ),
    );
    final saved = (await profiles.current('user-1'))!;
    expect(saved.displayName, 'Asha');
    expect(saved.dateOfBirth, LocalDate(1995, 4, 2));
    expect(saved.heightMm, 1725);
    expect(saved.units.mass, MassUnit.lb);
    expect(saved.units.volume, VolumeUnit.ml);
    expect(saved.timezone, 'Asia/Kolkata');
    expect(saved.workoutDays, {1, 3, 5});
    expect(saved.onboardingCompleted, isFalse);
  });

  test('a name is required; nothing is written without one', () async {
    final result = await profiles.save('user-1', const ProfileDraft(displayName: '   '));
    expect(result.failureOrNull?.code, 'required');
    expect(await profiles.current('user-1'), isNull);
    expect(await outboxEntries(db), isEmpty);
  });

  test('rejects impossible values', () async {
    for (final bad in [
      const ProfileDraft(displayName: 'A', heightMm: 20),
      ProfileDraft(displayName: 'A', dateOfBirth: LocalDate(2030, 1, 1)),
      const ProfileDraft(displayName: 'A', wakeTime: '25:00'),
      const ProfileDraft(displayName: 'A', workoutDays: {0, 8}),
    ]) {
      expect((await profiles.save('user-1', bad)).isOk, isFalse);
    }
    expect(await outboxEntries(db), isEmpty);
  });

  test('editing keeps created time, moves updated time and queues one sync entry', () async {
    await profiles.save('user-1', draft);
    time.now = DateTime(2026, 11, 17, 9);
    await profiles.save('user-1', const ProfileDraft(displayName: 'Asha R'));

    final row = await db.select(db.profiles).getSingle();
    expect(row.displayName, 'Asha R');
    expect(row.createdAt.isBefore(row.updatedAt), isTrue);
    expect(await outboxEntries(db), [(table: 'profiles', id: 'user-1')]);
  });

  test('completing onboarding is recorded once and survives later edits', () async {
    await profiles.save('user-1', draft);
    await profiles.completeOnboarding('user-1');
    await profiles.save('user-1', const ProfileDraft(displayName: 'Asha R'));
    expect((await profiles.current('user-1'))!.onboardingCompleted, isTrue);
  });

  test('watch emits the profile when it changes', () async {
    final expectation = expectLater(
      profiles.watch('user-1'),
      emitsInOrder([isNull, predicate<Profile?>((p) => p?.displayName == 'Asha')]),
    );
    await Future<void>.delayed(Duration.zero);
    await profiles.save('user-1', draft);
    await expectation;
  });
}
