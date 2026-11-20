import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/database/log_stamp.dart';
import '../../../core/database/private_database.dart';
import '../../../core/encryption/file_cipher.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/private_records.dart';

/// Private records. Never touches the sync outbox; text never reaches logs.
final class DriftPrivateRepository implements PrivateRepository {
  DriftPrivateRepository(
    this._db, {
    required this.clock,
    required this.ids,
    required this.timeZone,
    required this.photoDir,
    required this.cipher,
  });

  final PrivateDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  /// Encrypted photo files live here (app-private storage, no backup).
  final Directory? photoDir;
  final FileCipher? cipher;

  static const habitKeys = ['habit.porn', 'habit.masturbation'];

  DateTime get _now => clock.now().toUtc();
  static String? _clean(String? t) => t == null || t.trim().isEmpty ? null : t.trim();
  static const _write = StorageFailure('private_write');

  // ------------------------------------------------------------ habits

  @override
  Future<void> seedHabitTypes() => _db.transaction(() async {
    for (final key in habitKeys) {
      final existing = await (_db.select(
        _db.localPrivateActivityDefinitions,
      )..where((t) => t.systemKey.equals(key))).getSingleOrNull();
      if (existing != null) continue;
      await _db
          .into(_db.localPrivateActivityDefinitions)
          .insert(
            LocalPrivateActivityDefinitionsCompanion.insert(
              id: ids.newId(),
              createdAt: _now,
              updatedAt: _now,
              kind: 'habit',
              name: '',
              trackingType: 'count',
              systemKey: Value(key),
            ),
          );
    }
  });

  @override
  Stream<List<PrivateHabitType>> watchHabitTypes() =>
      (_db.select(_db.localPrivateActivityDefinitions)
            ..where((t) => t.kind.equals('habit') & t.archived.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                PrivateHabitType(id: r.id, name: r.name, systemKey: r.systemKey, archived: r.archived),
            ],
          );

  @override
  Future<Result<PrivateHabitType>> addHabitType(String name) async {
    if (name.trim().isEmpty || name.trim().length > 60) {
      return const Err(ValidationFailure('name', 'required'));
    }
    return Result.guard(() async {
      final id = ids.newId();
      await _db
          .into(_db.localPrivateActivityDefinitions)
          .insert(
            LocalPrivateActivityDefinitionsCompanion.insert(
              id: id,
              createdAt: _now,
              updatedAt: _now,
              kind: 'habit',
              name: name.trim(),
              trackingType: 'count',
            ),
          );
      return PrivateHabitType(id: id, name: name.trim());
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> archiveHabitType(String id) => Result.guard(
    () => (_db.update(_db.localPrivateActivityDefinitions)..where((t) => t.id.equals(id))).write(
      LocalPrivateActivityDefinitionsCompanion(archived: const Value(true), updatedAt: Value(_now)),
    ),
    onError: (_) => _write,
  );

  Failure? _future(DateTime at) =>
      at.isAfter(clock.now().add(const Duration(minutes: 1))) ? const ValidationFailure('at', 'in_future') : null;

  @override
  Future<Result<void>> recordHabit(String typeId, {required DateTime at, int count = 1, String? note}) async {
    final f = _future(at) ?? (count < 1 || count > 100 ? const ValidationFailure('count', 'out_of_range') : null);
    if (f != null) return Err(f);
    return Result.guard(() async {
      final s = await stampFor(clock, timeZone, at: at);
      await _db
          .into(_db.localPrivateHabitLogs)
          .insert(
            LocalPrivateHabitLogsCompanion.insert(
              id: ids.newId(),
              createdAt: s.nowUtc,
              updatedAt: s.nowUtc,
              definitionId: typeId,
              count: count,
              occurredAt: s.occurredAt,
              localDate: s.localDate,
              tz: s.tz,
              note: Value(_clean(note)),
            ),
          );
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> deleteHabitLog(String id) => Result.guard(
    () => (_db.delete(_db.localPrivateHabitLogs)..where((t) => t.id.equals(id))).go(),
    onError: (_) => _write,
  );

  @override
  Stream<List<PrivateHabitLog>> watchHabitLogs(String typeId, {required LocalDate from, required LocalDate to}) =>
      (_db.select(_db.localPrivateHabitLogs)
            ..where((t) => t.definitionId.equals(typeId) & t.localDate.isBetweenValues(from.toString(), to.toString()))
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                PrivateHabitLog(
                  id: r.id,
                  typeId: r.definitionId,
                  count: r.count,
                  occurredAt: r.occurredAt.toUtc(),
                  localDate: r.localDate,
                  note: r.note,
                ),
            ],
          );

  // ------------------------------------------------------------ bowel

  Failure? _bowelProblem(BowelDraft d) =>
      _future(d.at) ?? (d.count < 1 || d.count > 20 ? const ValidationFailure('count', 'out_of_range') : null);

  @override
  Future<Result<void>> addBowel(BowelDraft d) async {
    final f = _bowelProblem(d);
    if (f != null) return Err(f);
    return Result.guard(() async {
      final s = await stampFor(clock, timeZone, at: d.at);
      await _db
          .into(_db.localBowelLogs)
          .insert(
            LocalBowelLogsCompanion.insert(
              id: ids.newId(),
              createdAt: s.nowUtc,
              updatedAt: s.nowUtc,
              occurredAt: s.occurredAt,
              localDate: s.localDate,
              tz: s.tz,
              count: Value(d.count),
              consistency: d.consistency.code,
              straining: Value(d.straining),
              pain: Value(d.pain),
              bleeding: Value(d.bleeding),
              notes: Value(_clean(d.notes)),
            ),
          );
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> updateBowel(String id, BowelDraft d) async {
    final f = _bowelProblem(d);
    if (f != null) return Err(f);
    return Result.guard(() async {
      final s = await stampFor(clock, timeZone, at: d.at);
      await (_db.update(_db.localBowelLogs)..where((t) => t.id.equals(id))).write(
        LocalBowelLogsCompanion(
          updatedAt: Value(s.nowUtc),
          occurredAt: Value(s.occurredAt),
          localDate: Value(s.localDate),
          count: Value(d.count),
          consistency: Value(d.consistency.code),
          straining: Value(d.straining),
          pain: Value(d.pain),
          bleeding: Value(d.bleeding),
          notes: Value(_clean(d.notes)),
        ),
      );
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> deleteBowel(String id) =>
      Result.guard(() => (_db.delete(_db.localBowelLogs)..where((t) => t.id.equals(id))).go(), onError: (_) => _write);

  @override
  Stream<List<BowelLog>> watchBowel({required LocalDate from, required LocalDate to}) =>
      (_db.select(_db.localBowelLogs)
            ..where((t) => t.localDate.isBetweenValues(from.toString(), to.toString()))
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                BowelLog(
                  id: r.id,
                  occurredAt: r.occurredAt.toUtc(),
                  localDate: r.localDate,
                  count: r.count,
                  consistency: Consistency.fromCode(r.consistency),
                  straining: r.straining,
                  pain: r.pain,
                  bleeding: r.bleeding,
                  notes: r.notes,
                ),
            ],
          );

  // ------------------------------------------------------------ private activities

  @override
  Future<Result<PrivateActivity>> addActivity(String name, {required bool counted}) async {
    if (name.trim().isEmpty || name.trim().length > 80) {
      return const Err(ValidationFailure('name', 'required'));
    }
    return Result.guard(() async {
      final id = ids.newId();
      await _db
          .into(_db.localPrivateActivityDefinitions)
          .insert(
            LocalPrivateActivityDefinitionsCompanion.insert(
              id: id,
              createdAt: _now,
              updatedAt: _now,
              kind: 'activity',
              name: name.trim(),
              trackingType: counted ? 'count' : 'boolean',
            ),
          );
      return PrivateActivity(id: id, name: name.trim(), counted: counted);
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> archiveActivity(String id) => archiveHabitType(id);

  @override
  Stream<List<PrivateActivity>> watchActivities() =>
      (_db.select(_db.localPrivateActivityDefinitions)
            ..where((t) => t.kind.equals('activity') & t.archived.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows) PrivateActivity(id: r.id, name: r.name, counted: r.trackingType == 'count'),
            ],
          );

  @override
  Future<Result<void>> logActivity(String id, {required DateTime at, int? count, String? notes}) async {
    final f =
        _future(at) ??
        (count != null && (count < 1 || count > 999) ? const ValidationFailure('count', 'out_of_range') : null);
    if (f != null) return Err(f);
    return Result.guard(() async {
      final s = await stampFor(clock, timeZone, at: at);
      await _db
          .into(_db.localPrivateActivityLogs)
          .insert(
            LocalPrivateActivityLogsCompanion.insert(
              id: ids.newId(),
              createdAt: s.nowUtc,
              updatedAt: s.nowUtc,
              definitionId: id,
              status: 'completed',
              occurredAt: s.occurredAt,
              localDate: s.localDate,
              tz: s.tz,
              countValue: Value(count),
              notes: Value(_clean(notes)),
            ),
          );
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> deleteActivityLog(String id) => Result.guard(
    () => (_db.delete(_db.localPrivateActivityLogs)..where((t) => t.id.equals(id))).go(),
    onError: (_) => _write,
  );

  @override
  Stream<List<PrivateActivityLog>> watchActivityLogs(String id) =>
      (_db.select(_db.localPrivateActivityLogs)
            ..where((t) => t.definitionId.equals(id))
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)])
            ..limit(100))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                PrivateActivityLog(
                  id: r.id,
                  activityId: r.definitionId,
                  occurredAt: r.occurredAt.toUtc(),
                  localDate: r.localDate,
                  count: r.countValue,
                  notes: r.notes,
                ),
            ],
          );

  // ------------------------------------------------------------ photos

  File _file(String id) => File('${photoDir!.path}/$id.bin');

  @override
  Future<Result<ProgressPhoto>> addPhoto(List<int> bytes, {required DateTime takenAt, String? note}) async {
    if (photoDir == null || cipher == null) {
      return const Err(StorageFailure('photo_store_unavailable'));
    }
    if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) {
      return const Err(ValidationFailure('photo', 'out_of_range'));
    }
    return Result.guard(() async {
      final s = await stampFor(clock, timeZone, at: takenAt);
      final id = ids.newId();
      await photoDir!.create(recursive: true);
      await _file(id).writeAsBytes(await cipher!.encrypt(bytes), flush: true);
      await _db
          .into(_db.localProgressPhotos)
          .insert(
            LocalProgressPhotosCompanion.insert(
              id: id,
              createdAt: s.nowUtc,
              updatedAt: s.nowUtc,
              takenAt: s.occurredAt,
              localDate: s.localDate,
              fileName: '$id.bin',
              note: Value(_clean(note)),
            ),
          );
      return ProgressPhoto(id: id, takenAt: s.occurredAt, localDate: s.localDate, note: _clean(note));
    }, onError: (_) => const StorageFailure('photo_write'));
  }

  @override
  Future<List<int>?> readPhoto(String id) async {
    if (photoDir == null || cipher == null) return null;
    try {
      final f = _file(id);
      return await f.exists() ? await cipher!.decrypt(await f.readAsBytes()) : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<Result<void>> deletePhoto(String id) => Result.guard(() async {
    await (_db.delete(_db.localProgressPhotos)..where((t) => t.id.equals(id))).go();
    if (photoDir != null) {
      final f = _file(id);
      if (await f.exists()) await f.delete();
    }
  }, onError: (_) => _write);

  @override
  Stream<List<ProgressPhoto>> watchPhotos() =>
      (_db.select(
        _db.localProgressPhotos,
      )..orderBy([(t) => OrderingTerm(expression: t.takenAt, mode: OrderingMode.desc)])).watch().map(
        (rows) => [
          for (final r in rows)
            ProgressPhoto(id: r.id, takenAt: r.takenAt.toUtc(), localDate: r.localDate, note: r.note),
        ],
      );
}
