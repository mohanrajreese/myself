import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/timer_repository.dart';
import '../domain/timer_session.dart';

/// Local-only storage; timers are never synced (03 §3).
final class DriftTimerRepository implements TimerRepository {
  DriftTimerRepository(this._db, {required this.clock, required this.ids});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;

  static TimerSession _toSession(TimerSessionRow r) => TimerSession(
    id: r.id,
    kind: TimerKind.fromCode(r.kind),
    state: TimerState.fromCode(r.state),
    targetDuration: r.targetDurationS == null ? null : Duration(seconds: r.targetDurationS!),
    activityId: r.activityDefinitionId,
    accumulated: Duration(milliseconds: r.accumulatedMs),
    lastResumedAt: r.lastResumedAt?.toUtc(),
    startedAt: r.startedAt?.toUtc(),
    endedAt: r.endedAt?.toUtc(),
  );

  @override
  Future<Result<TimerSession>> create({required TimerKind kind, Duration? target, String? activityId}) async {
    if (target != null && (target.inSeconds < 1 || target.inSeconds > 86400)) {
      return const Err(ValidationFailure('target', 'out_of_range'));
    }
    return Result.guard(() async {
      final session = TimerSession.ready(id: ids.newId(), kind: kind, targetDuration: target, activityId: activityId);
      await _db
          .into(_db.localTimerSessions)
          .insert(
            LocalTimerSessionsCompanion.insert(
              id: session.id,
              kind: kind.code,
              state: session.state.code,
              activityDefinitionId: Value(activityId),
              targetDurationS: Value(target?.inSeconds),
            ),
          );
      return session;
    }, onError: (_) => const StorageFailure('timer_write'));
  }

  @override
  Future<Result<TimerSession>> transition(String id, TimerEventType type) async {
    final row = await (_db.select(_db.localTimerSessions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return const Err(ValidationFailure('timer', 'not_found'));
    final at = clock.now().toUtc();
    final next = _toSession(row).apply(TimerEvent(type, at));
    final session = next.valueOrNull;
    if (session == null) return next;
    return Result.guard(() async {
      await _db.transaction(() async {
        await (_db.update(_db.localTimerSessions)..where((t) => t.id.equals(id))).write(
          LocalTimerSessionsCompanion(
            state: Value(session.state.code),
            accumulatedMs: Value(session.accumulated.inMilliseconds),
            lastResumedAt: Value(session.lastResumedAt),
            startedAt: Value(session.startedAt),
            endedAt: Value(session.endedAt),
          ),
        );
        await _db
            .into(_db.localTimerEvents)
            .insert(LocalTimerEventsCompanion.insert(id: ids.newId(), sessionId: id, type: type.code, at: at));
      });
      return session;
    }, onError: (_) => const StorageFailure('timer_write'));
  }

  @override
  Future<Result<void>> linkLog(String id, String activityLogId) => Result.guard(
    () => (_db.update(
      _db.localTimerSessions,
    )..where((t) => t.id.equals(id))).write(LocalTimerSessionsCompanion(activityLogId: Value(activityLogId))),
    onError: (_) => const StorageFailure('timer_write'),
  );

  @override
  Stream<List<TimerSession>> watchActive() =>
      (_db.select(_db.localTimerSessions)..where((t) => t.state.isIn(const ['ready', 'running', 'paused'])))
          .watch()
          .map((rows) => [for (final r in rows) _toSession(r)]);

  @override
  Stream<List<TimerSession>> watchHistory({int limit = 50}) =>
      (_db.select(_db.localTimerSessions)
            ..where((t) => t.state.isIn(const ['completed', 'cancelled']))
            ..orderBy([(t) => OrderingTerm(expression: t.endedAt, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((rows) => [for (final r in rows) _toSession(r)]);
}
