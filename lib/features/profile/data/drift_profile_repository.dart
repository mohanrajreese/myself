import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/database/unit_codes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';

final class DriftProfileRepository implements ProfileRepository {
  DriftProfileRepository(this._db, {required Clock clock, required TimeZoneSource timeZone})
    : _clock = clock,
      _timeZone = timeZone;

  final AppDatabase _db;
  final Clock _clock;
  final TimeZoneSource _timeZone;

  SimpleSelectStatement<$ProfilesTable, ProfileRow> _query(String accountId) =>
      _db.select(_db.profiles)..where((t) => t.id.equals(accountId) & t.deletedAt.isNull());

  @override
  Future<Profile?> current(String accountId) async {
    final row = await _query(accountId).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<Profile?> watch(String accountId) =>
      _query(accountId).watchSingleOrNull().map((row) => row == null ? null : _toDomain(row));

  @override
  Future<Result<Profile>> save(String accountId, ProfileDraft draft) async {
    final wallNow = _clock.now();
    final failure = draft.validate(today: LocalDate.fromDateTime(wallNow));
    if (failure != null) return Err(failure);

    return Result.guard(() async {
      final now = wallNow.toUtc();
      final timezone = await _timeZone.currentTimeZoneId();
      await _db.transaction(() async {
        final existing = await (_db.select(
          _db.profiles,
        )..where((t) => t.id.equals(accountId))).getSingleOrNull();
        await _db
            .into(_db.profiles)
            .insertOnConflictUpdate(
              ProfilesCompanion.insert(
                id: accountId,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                deletedAt: const Value(null),
                displayName: draft.displayName.trim(),
                dateOfBirth: Value(draft.dateOfBirth),
                heightMm: Value(draft.heightMm),
                weightUnit: draft.units.mass.code,
                lengthUnit: draft.units.length.code,
                volumeUnit: draft.units.volume.code,
                distanceUnit: draft.units.distance.code,
                timezone: timezone,
                wakeTime: Value(draft.wakeTime),
                workoutDays: Value(jsonEncode(draft.workoutDays.toList()..sort())),
                onboardingCompletedAt: Value(existing?.onboardingCompletedAt),
              ),
            );
        await _db.enqueueForSync('profiles', accountId, now);
      });
      return (await current(accountId))!;
    }, onError: (_) => const StorageFailure('profile_write'));
  }

  @override
  Future<Result<void>> completeOnboarding(String accountId) => Result.guard(() async {
    final now = _clock.now().toUtc();
    await _db.transaction(() async {
      final changed =
          await (_db.update(_db.profiles)
                ..where((t) => t.id.equals(accountId) & t.onboardingCompletedAt.isNull()))
              .write(ProfilesCompanion(onboardingCompletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync('profiles', accountId, now);
    });
  }, onError: (_) => const StorageFailure('profile_write'));

  Profile _toDomain(ProfileRow row) => Profile(
    id: row.id,
    displayName: row.displayName,
    dateOfBirth: row.dateOfBirth,
    heightMm: row.heightMm,
    units: UnitPreferences(
      mass: MassUnitCode.parse(row.weightUnit),
      length: LengthUnitCode.parse(row.lengthUnit),
      volume: VolumeUnitCode.parse(row.volumeUnit),
      distance: DistanceUnitCode.parse(row.distanceUnit),
    ),
    timezone: row.timezone,
    wakeTime: row.wakeTime,
    workoutDays: (jsonDecode(row.workoutDays) as List<Object?>).cast<int>().toSet(),
    onboardingCompleted: row.onboardingCompletedAt != null,
  );
}
