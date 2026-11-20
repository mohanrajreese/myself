import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

/// A private habit type (§5.12). Seeded types have a [systemKey]; their names
/// are shown from the app's text, so nothing personal is stored for them.
final class PrivateHabitType {
  const PrivateHabitType({required this.id, required this.name, this.systemKey, this.archived = false});
  final String id;
  final String name;
  final String? systemKey;
  final bool archived;
}

final class PrivateHabitLog {
  const PrivateHabitLog({
    required this.id,
    required this.typeId,
    required this.count,
    required this.occurredAt,
    required this.localDate,
    this.note,
  });
  final String id;
  final String typeId;
  final int count;
  final DateTime occurredAt;
  final LocalDate localDate;
  final String? note;
}

enum Consistency {
  hard('hard'),
  normal('normal'),
  loose('loose');

  const Consistency(this.code);
  final String code;
  static Consistency fromCode(String c) => values.firstWhere((v) => v.code == c);
}

/// A bowel movement record (§5.11).
final class BowelLog {
  const BowelLog({
    required this.id,
    required this.occurredAt,
    required this.localDate,
    required this.consistency,
    this.count = 1,
    this.straining = false,
    this.pain,
    this.bleeding,
    this.notes,
  });
  final String id;
  final DateTime occurredAt;
  final LocalDate localDate;
  final int count;
  final Consistency consistency;
  final bool straining;
  final bool? pain;
  final bool? bleeding;
  final String? notes;
}

typedef BowelDraft = ({
  DateTime at,
  Consistency consistency,
  int count,
  bool straining,
  bool? pain,
  bool? bleeding,
  String? notes,
});

/// A private activity: done or counted, optionally at set times (C5).
final class PrivateActivity {
  const PrivateActivity({required this.id, required this.name, required this.counted, this.archived = false});
  final String id;
  final String name;

  /// Counted (each log has a number) rather than done once.
  final bool counted;
  final bool archived;
}

final class PrivateActivityLog {
  const PrivateActivityLog({
    required this.id,
    required this.activityId,
    required this.occurredAt,
    required this.localDate,
    this.count,
    this.notes,
  });
  final String id;
  final String activityId;
  final DateTime occurredAt;
  final LocalDate localDate;
  final int? count;
  final String? notes;
}

final class ProgressPhoto {
  const ProgressPhoto({required this.id, required this.takenAt, required this.localDate, this.note});
  final String id;
  final DateTime takenAt;
  final LocalDate localDate;
  final String? note;
}

/// Everything in the private space (§7.1). Stored only in `PrivateDatabase`.
abstract interface class PrivateRepository {
  Future<void> seedHabitTypes();
  Stream<List<PrivateHabitType>> watchHabitTypes();
  Future<Result<PrivateHabitType>> addHabitType(String name);
  Future<Result<void>> archiveHabitType(String id);
  Future<Result<void>> recordHabit(String typeId, {required DateTime at, int count = 1, String? note});
  Future<Result<void>> deleteHabitLog(String id);
  Stream<List<PrivateHabitLog>> watchHabitLogs(String typeId, {required LocalDate from, required LocalDate to});

  Future<Result<void>> addBowel(BowelDraft draft);
  Future<Result<void>> updateBowel(String id, BowelDraft draft);
  Future<Result<void>> deleteBowel(String id);
  Stream<List<BowelLog>> watchBowel({required LocalDate from, required LocalDate to});

  Future<Result<PrivateActivity>> addActivity(String name, {required bool counted});
  Future<Result<void>> archiveActivity(String id);
  Stream<List<PrivateActivity>> watchActivities();
  Future<Result<void>> logActivity(String id, {required DateTime at, int? count, String? notes});
  Future<Result<void>> deleteActivityLog(String id);
  Stream<List<PrivateActivityLog>> watchActivityLogs(String id);

  Future<Result<ProgressPhoto>> addPhoto(List<int> bytes, {required DateTime takenAt, String? note});
  Future<List<int>?> readPhoto(String id);
  Future<Result<void>> deletePhoto(String id);
  Stream<List<ProgressPhoto>> watchPhotos();
}

/// A reminder whose text stays in the private database; the notification
/// shows only a generic title (§3.4 rule 14).
final class SensitiveReminder {
  const SensitiveReminder({
    required this.id,
    required this.ownerType,
    required this.title,
    required this.ruleJson,
    this.ownerId,
    this.enabled = true,
  });
  final String id;

  /// `bowel`, `medication`, `private_activity` or `custom`.
  final String ownerType;
  final String? ownerId;
  final String title;
  final String ruleJson;
  final bool enabled;
}

abstract interface class SensitiveReminderRepository {
  Future<Result<void>> save(SensitiveReminder reminder);
  Future<Result<void>> delete(String id);
  Stream<List<SensitiveReminder>> watchAll();
  Future<List<SensitiveReminder>> enabled();
}
