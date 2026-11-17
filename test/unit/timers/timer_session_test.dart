import 'package:fitbuddy/features/timers/domain/timer_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 16, 8);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  TimerSession ready({int? targetS}) => TimerSession.ready(
    id: 's1',
    kind: targetS == null ? TimerKind.stopwatch : TimerKind.countdown,
    targetDuration: targetS == null ? null : Duration(seconds: targetS),
  );

  test('follows Ready → Running → Paused → Running → Completed', () {
    var s = ready();
    expect(s.state, TimerState.ready);
    s = s.start(at(0)).valueOrNull!;
    expect(s.state, TimerState.running);
    expect(s.elapsed(at(90)), const Duration(seconds: 90));
    s = s.pause(at(90)).valueOrNull!;
    expect(s.elapsed(at(500)), const Duration(seconds: 90), reason: 'paused time does not count');
    s = s.resume(at(600)).valueOrNull!;
    expect(s.elapsed(at(630)), const Duration(seconds: 120));
    s = s.finish(at(630)).valueOrNull!;
    expect(s.state, TimerState.completed);
    expect(s.elapsed(at(9999)), const Duration(seconds: 120));
    expect(s.endedAt, at(630));
  });

  test('impossible transitions are refused', () {
    final s = ready();
    expect(s.pause(at(0)).isOk, isFalse);
    expect(s.resume(at(0)).isOk, isFalse);
    expect(s.finish(at(0)).isOk, isFalse);
    final running = s.start(at(0)).valueOrNull!;
    expect(running.start(at(1)).isOk, isFalse);
    expect(running.resume(at(1)).isOk, isFalse);
    final done = running.finish(at(5)).valueOrNull!;
    expect(done.cancel(at(6)).isOk, isFalse);
    expect(done.start(at(6)).isOk, isFalse);
  });

  test('cancelling never counts as completed', () {
    final s = ready().start(at(0)).valueOrNull!.cancel(at(60)).valueOrNull!;
    expect(s.state, TimerState.cancelled);
    expect(s.countsAsCompleted, isFalse);
  });

  test('a countdown reports what is left and when it ends', () {
    var s = ready(targetS: 1800).start(at(0)).valueOrNull!;
    expect(s.remaining(at(600)), const Duration(seconds: 1200));
    expect(s.endsAt, at(1800));
    s = s.pause(at(600)).valueOrNull!;
    expect(s.endsAt, isNull, reason: 'a paused countdown has no end time');
    s = s.resume(at(700)).valueOrNull!;
    expect(s.endsAt, at(1900));
    expect(s.isOverdue(at(1899)), isFalse);
    expect(s.isOverdue(at(1900)), isTrue);
    expect(s.remaining(at(5000)), Duration.zero);
  });

  test('a clock set backwards never gives negative time', () {
    final s = ready().start(at(100)).valueOrNull!;
    expect(s.elapsed(at(50)), Duration.zero);
  });

  test('state can be rebuilt from the stored events alone', () {
    final events = [
      TimerEvent(TimerEventType.start, at(0)),
      TimerEvent(TimerEventType.pause, at(100)),
      TimerEvent(TimerEventType.resume, at(200)),
      TimerEvent(TimerEventType.finish, at(260)),
    ];
    final s = TimerSession.replay(ready(), events);
    expect(s.state, TimerState.completed);
    expect(s.elapsed(at(999)), const Duration(seconds: 160));
  });
}
