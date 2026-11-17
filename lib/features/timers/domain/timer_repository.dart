import '../../../core/errors/result.dart';
import 'timer_session.dart';

/// Device-only timer sessions (§5.16). Every transition is stored as an event.
abstract interface class TimerRepository {
  Future<Result<TimerSession>> create({
    required TimerKind kind,
    Duration? target,
    String? activityId,
  });

  /// Applies [type] now and stores the event with the new state.
  Future<Result<TimerSession>> transition(String id, TimerEventType type);

  /// Links a completed session to the activity log it produced.
  Future<Result<void>> linkLog(String id, String activityLogId);

  /// Sessions that are ready, running or paused.
  Stream<List<TimerSession>> watchActive();

  /// Completed and cancelled sessions, newest first.
  Stream<List<TimerSession>> watchHistory({int limit = 50});
}
