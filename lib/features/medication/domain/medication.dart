import '../../../core/errors/result.dart';
import '../../../core/scheduling/occurrence_calculator.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/local_date.dart';

/// A medicine or supplement (§5.18). The dosage is the user's own words; the
/// app never reads or changes it.
final class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.dosageText,
    required this.rule,
    this.remind = true,
    this.notes,
    this.active = true,
  });
  final String id;
  final String name;
  final String dosageText;
  final ScheduleRule rule;
  final bool remind;
  final String? notes;
  final bool active;

  List<String> get problems => [
    if (name.trim().isEmpty) 'name_required',
    if (dosageText.trim().isEmpty) 'dosage_required',
    ...rule.problems,
  ];
}

enum DoseStatus {
  taken('taken'),
  missed('missed'),
  skipped('skipped');

  const DoseStatus(this.code);
  final String code;
  static DoseStatus fromCode(String c) => values.firstWhere((s) => s.code == c);
}

final class DoseLog {
  const DoseLog({
    required this.id,
    required this.medicationId,
    required this.localDate,
    required this.status,
    required this.actedAt,
    this.slot,
    this.notes,
  });
  final String id;
  final String medicationId;
  final LocalDate localDate;
  final int? slot;
  final DoseStatus status;
  final DateTime actedAt;
  final String? notes;
}

/// A scheduled dose on a day and what happened to it.
enum DoseState { taken, notTaken, skipped, due }

typedef Dose = ({Medication medication, int minute, DoseState state, DoseLog? log});

/// Today's (or any day's) doses from the schedules and logs. Pure.
List<Dose> dosesOn(
  LocalDate day,
  List<Medication> meds,
  List<DoseLog> logs, {
  required LocalDate today,
  required int nowMinute,
}) {
  const calc = OccurrenceCalculator();
  final out = <Dose>[];
  for (final m in meds.where((m) => m.active)) {
    for (final minute in calc.timesOn(m.rule, day)) {
      final log = logs.where((l) => l.medicationId == m.id && l.localDate == day && l.slot == minute).firstOrNull;
      final passed = day.isBefore(today) || (day == today && minute < nowMinute);
      final state = switch (log?.status) {
        DoseStatus.taken => DoseState.taken,
        DoseStatus.skipped => DoseState.skipped,
        DoseStatus.missed => DoseState.notTaken,
        null => passed ? DoseState.notTaken : DoseState.due,
      };
      out.add((medication: m, minute: minute, state: state, log: log));
    }
  }
  out.sort((a, b) => a.minute.compareTo(b.minute));
  return out;
}

abstract interface class MedicationRepository {
  Future<Result<Medication>> create(Medication draft);
  Future<Result<void>> update(Medication medication);
  Future<Result<void>> delete(String id);
  Stream<List<Medication>> watchAll();
  Future<List<Medication>> all();

  /// Records a dose; replaces an earlier record for the same day and time.
  Future<Result<void>> record(
    String medicationId, {
    required LocalDate day,
    required int slot,
    required DoseStatus status,
  });
  Stream<List<DoseLog>> watchLogs({required LocalDate from, required LocalDate to});
}
