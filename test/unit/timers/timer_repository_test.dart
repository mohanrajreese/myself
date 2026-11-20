import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/features/timers/data/drift_timer_repository.dart';
import 'package:fitbuddy/features/timers/domain/timer_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftTimerRepository repo;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 8));
    repo = DriftTimerRepository(db, clock: time.clock, ids: SequentialIds());
  });
  tearDown(() => db.close());

  void advance(int seconds) => time.now = time.now.add(Duration(seconds: seconds));

  test('a session and every transition survive reopening the store', () async {
    final s = (await repo.create(kind: TimerKind.countdown, target: const Duration(minutes: 30))).valueOrNull!;
    await repo.transition(s.id, TimerEventType.start);
    advance(300);
    await repo.transition(s.id, TimerEventType.pause);
    advance(60);
    await repo.transition(s.id, TimerEventType.resume);
    advance(60);

    final reopened = DriftTimerRepository(db, clock: time.clock, ids: SequentialIds());
    final active = (await reopened.watchActive().first).single;
    expect(active.state, TimerState.running);
    expect(active.elapsed(time.now), const Duration(seconds: 360));
    expect(await db.select(db.localTimerEvents).get(), hasLength(3));
  });

  test('finishing moves it to history; cancelling too, but not as completed', () async {
    final a = (await repo.create(kind: TimerKind.stopwatch, activityId: 'act')).valueOrNull!;
    await repo.transition(a.id, TimerEventType.start);
    advance(120);
    final done = (await repo.transition(a.id, TimerEventType.finish)).valueOrNull!;
    expect(done.elapsed(time.now), const Duration(seconds: 120));
    final b = (await repo.create(kind: TimerKind.stopwatch)).valueOrNull!;
    await repo.transition(b.id, TimerEventType.start);
    await repo.transition(b.id, TimerEventType.cancel);
    expect(await repo.watchActive().first, isEmpty);
    final history = await repo.watchHistory().first;
    expect(history.map((s) => s.state), containsAll([TimerState.completed, TimerState.cancelled]));
    await repo.linkLog(a.id, 'log1');
    expect((await db.select(db.localTimerSessions).get()).firstWhere((r) => r.id == a.id).activityLogId, 'log1');
  });

  test('an impossible transition is refused and stores nothing', () async {
    final s = (await repo.create(kind: TimerKind.stopwatch)).valueOrNull!;
    final r = await repo.transition(s.id, TimerEventType.pause);
    expect(r.failureOrNull, isA<ValidationFailure>());
    expect(await db.select(db.localTimerEvents).get(), isEmpty);
  });

  test('timers are never queued for sync', () async {
    final s = (await repo.create(kind: TimerKind.stopwatch)).valueOrNull!;
    await repo.transition(s.id, TimerEventType.start);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });
}
