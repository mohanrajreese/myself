import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/private_database.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/medication.dart';

/// Medication lives in the private database only (§5.18, §7.1).
final class DriftMedicationRepository implements MedicationRepository {
  DriftMedicationRepository(this._db, {required this.clock, required this.ids});
  final PrivateDatabase _db;
  final Clock clock;
  final IdGenerator ids;

  DateTime get _now => clock.now().toUtc();
  static const _write = StorageFailure('medication_write');

  static Medication _toMed(MedicationRow r) => Medication(
    id: r.id,
    name: r.name,
    dosageText: r.dosageText,
    rule: ScheduleRule.fromJson((jsonDecode(r.schedule) as Map).cast<String, Object?>()),
    remind: r.remind,
    notes: r.notes,
    active: r.active,
  );

  LocalMedicationsCompanion _fields(Medication m) => LocalMedicationsCompanion(
    updatedAt: Value(_now),
    name: Value(m.name.trim()),
    dosageText: Value(m.dosageText.trim()),
    schedule: Value(jsonEncode(m.rule.toJson())),
    remind: Value(m.remind),
    notes: Value(m.notes?.trim().isEmpty ?? true ? null : m.notes!.trim()),
    active: Value(m.active),
  );

  @override
  Future<Result<Medication>> create(Medication draft) async {
    if (draft.problems.isNotEmpty) {
      return Err(ValidationFailure('medication', draft.problems.first));
    }
    return Result.guard(() async {
      final id = ids.newId();
      await _db
          .into(_db.localMedications)
          .insert(_fields(draft).copyWith(id: Value(id), createdAt: Value(_now)));
      return Medication(
        id: id,
        name: draft.name.trim(),
        dosageText: draft.dosageText.trim(),
        rule: draft.rule,
        remind: draft.remind,
        notes: draft.notes,
      );
    }, onError: (_) => _write);
  }

  @override
  Future<Result<void>> update(Medication m) async {
    if (m.problems.isNotEmpty) return Err(ValidationFailure('medication', m.problems.first));
    return Result.guard(
      () => (_db.update(_db.localMedications)..where((t) => t.id.equals(m.id))).write(_fields(m)),
      onError: (_) => _write,
    );
  }

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => (_db.delete(_db.localMedications)..where((t) => t.id.equals(id))).go(),
    onError: (_) => _write,
  );

  @override
  Stream<List<Medication>> watchAll() =>
      (_db.select(_db.localMedications)..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch()
          .map((rows) => [for (final r in rows) _toMed(r)]);

  @override
  Future<List<Medication>> all() async => [
    for (final r in await _db.select(_db.localMedications).get()) _toMed(r),
  ];

  @override
  Future<Result<void>> record(
    String medicationId, {
    required LocalDate day,
    required int slot,
    required DoseStatus status,
  }) => Result.guard(
    () => _db.transaction(() async {
      await (_db.delete(_db.localMedicationLogs)..where(
            (t) =>
                t.medicationId.equals(medicationId) &
                t.localDate.equalsValue(day) &
                t.scheduledSlot.equals(slot),
          ))
          .go();
      await _db
          .into(_db.localMedicationLogs)
          .insert(
            LocalMedicationLogsCompanion.insert(
              id: ids.newId(),
              createdAt: _now,
              updatedAt: _now,
              medicationId: medicationId,
              scheduledSlot: Value(slot),
              localDate: day,
              status: status.code,
              actedAt: _now,
            ),
          );
    }),
    onError: (_) => _write,
  );

  @override
  Stream<List<DoseLog>> watchLogs({required LocalDate from, required LocalDate to}) =>
      (_db.select(
        _db.localMedicationLogs,
      )..where((t) => t.localDate.isBetweenValues(from.toString(), to.toString()))).watch().map(
        (rows) => [
          for (final r in rows)
            DoseLog(
              id: r.id,
              medicationId: r.medicationId,
              localDate: r.localDate,
              slot: r.scheduledSlot,
              status: DoseStatus.fromCode(r.status),
              actedAt: r.actedAt.toUtc(),
              notes: r.notes,
            ),
        ],
      );
}
