import '../../../core/errors/result.dart';
import 'reminder.dart';

/// Ordinary reminders. Every change should be followed by a re-plan.
abstract interface class ReminderRepository {
  Future<Result<Reminder>> create(Reminder draft);
  Future<Result<void>> update(Reminder reminder);
  Future<Result<void>> setEnabled(String id, {required bool enabled});
  Future<Result<void>> delete(String id);
  Stream<List<Reminder>> watchAll();
  Future<List<Reminder>> enabled();
  Future<Reminder?> byId(String id);
}
