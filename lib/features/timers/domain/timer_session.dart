import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';

enum TimerKind {
  stopwatch('stopwatch'),
  countdown('countdown'),
  rest('rest');

  const TimerKind(this.code);
  final String code;
  static TimerKind fromCode(String code) => values.firstWhere((k) => k.code == code);
}

enum TimerState {
  ready('ready'),
  running('running'),
  paused('paused'),
  completed('completed'),
  cancelled('cancelled');

  const TimerState(this.code);
  final String code;
  static TimerState fromCode(String code) => values.firstWhere((s) => s.code == code);
  bool get isFinal => this == completed || this == cancelled;
}

enum TimerEventType {
  start('start'),
  pause('pause'),
  resume('resume'),
  finish('finish'),
  cancel('cancel');

  const TimerEventType(this.code);
  final String code;
  static TimerEventType fromCode(String code) => values.firstWhere((t) => t.code == code);
}

final class TimerEvent {
  const TimerEvent(this.type, this.at);
  final TimerEventType type;
  final DateTime at;
}

/// A stopwatch or countdown (§5.16). Time is computed from the state and
/// timestamps, so a session survives the app closing or the phone restarting.
final class TimerSession {
  const TimerSession({
    required this.id,
    required this.kind,
    required this.state,
    this.targetDuration,
    this.activityId,
    this.accumulated = Duration.zero,
    this.lastResumedAt,
    this.startedAt,
    this.endedAt,
  });

  factory TimerSession.ready({
    required String id,
    required TimerKind kind,
    Duration? targetDuration,
    String? activityId,
  }) =>
      TimerSession(id: id, kind: kind, state: TimerState.ready, targetDuration: targetDuration, activityId: activityId);

  /// Rebuilds a session by applying [events] in order to [initial].
  factory TimerSession.replay(TimerSession initial, Iterable<TimerEvent> events) {
    var s = initial;
    for (final e in events) {
      s = s.apply(e).valueOrNull ?? s;
    }
    return s;
  }

  final String id;
  final TimerKind kind;
  final TimerState state;
  final Duration? targetDuration;
  final String? activityId;

  /// Time run before [lastResumedAt].
  final Duration accumulated;
  final DateTime? lastResumedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get countsAsCompleted => state == TimerState.completed;

  Duration elapsed(DateTime now) {
    if (state != TimerState.running || lastResumedAt == null) return accumulated;
    final run = now.difference(lastResumedAt!);
    return accumulated + (run.isNegative ? Duration.zero : run);
  }

  Duration? remaining(DateTime now) {
    final target = targetDuration;
    if (target == null) return null;
    final left = target - elapsed(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// When a running countdown reaches its target; null otherwise.
  DateTime? get endsAt {
    final target = targetDuration;
    if (target == null || state != TimerState.running || lastResumedAt == null) return null;
    return lastResumedAt!.add(target - accumulated);
  }

  bool isOverdue(DateTime now) => endsAt != null && !now.isBefore(endsAt!);

  Result<TimerSession> start(DateTime at) => apply(TimerEvent(TimerEventType.start, at));
  Result<TimerSession> pause(DateTime at) => apply(TimerEvent(TimerEventType.pause, at));
  Result<TimerSession> resume(DateTime at) => apply(TimerEvent(TimerEventType.resume, at));
  Result<TimerSession> finish(DateTime at) => apply(TimerEvent(TimerEventType.finish, at));
  Result<TimerSession> cancel(DateTime at) => apply(TimerEvent(TimerEventType.cancel, at));

  Result<TimerSession> apply(TimerEvent e) {
    final at = e.at.toUtc();
    TimerSession next(TimerState state, {Duration? accumulated, DateTime? resumed, bool clearResumed = false}) =>
        TimerSession(
          id: id,
          kind: kind,
          state: state,
          targetDuration: targetDuration,
          activityId: activityId,
          accumulated: accumulated ?? this.accumulated,
          lastResumedAt: clearResumed ? null : (resumed ?? lastResumedAt),
          startedAt: startedAt ?? (e.type == TimerEventType.start ? at : null),
          endedAt: state.isFinal ? at : null,
        );
    return switch ((state, e.type)) {
      (TimerState.ready, TimerEventType.start) => Ok(next(TimerState.running, resumed: at)),
      (TimerState.running, TimerEventType.pause) => Ok(
        next(TimerState.paused, accumulated: elapsed(at), clearResumed: true),
      ),
      (TimerState.paused, TimerEventType.resume) => Ok(next(TimerState.running, resumed: at)),
      (TimerState.running || TimerState.paused, TimerEventType.finish) => Ok(
        next(TimerState.completed, accumulated: elapsed(at), clearResumed: true),
      ),
      (TimerState.ready || TimerState.running || TimerState.paused, TimerEventType.cancel) => Ok(
        next(TimerState.cancelled, accumulated: elapsed(at), clearResumed: true),
      ),
      _ => const Err(ValidationFailure('timer', 'invalid_transition')),
    };
  }
}
