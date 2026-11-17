import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/data/drift_activity_repository.dart';
import 'package:fitbuddy/features/activities/domain/activity.dart';
import 'package:fitbuddy/features/activities/domain/activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

int hm(int h, int m) => h * 60 + m;

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftActivityRepository repo;
  final today = LocalDate(2026, 11, 16);

  Activity draft({String name = 'Walking', TrackingType type = TrackingType.duration}) => Activity(
    id: '',
    name: name,
    category: 'movement',
    iconKey: 'walk',
    trackingType: type,
    priority: ActivityPriority.essential,
    targetMilli: type == TrackingType.duration ? 1800000 : null,
    schedule: Daily(times: [hm(8, 0)]),
    scheduleHistory: const [],
  );

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 9));
    repo = DriftActivityRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  Future<List<String>> outbox() async => [
    for (final r in await db.select(db.syncOutbox).get()) r.entityTable,
  ];

  test(
    'creating saves the activity with its schedule starting today and queues it for sync',
    () async {
      final a = (await repo.create(draft())).valueOrNull!;
      expect(a.id, isNotEmpty);
      expect(a.scheduleHistory.single.from, today);
      final listed = await repo.watchAll().first;
      expect(listed.single.name, 'Walking');
      expect(listed.single.schedule, Daily(times: [hm(8, 0)]));
      expect(await outbox(), ['activity_definitions']);
    },
  );

  test('an invalid activity is refused and nothing is stored', () async {
    final result = await repo.create(draft(name: ' '));
    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(await db.select(db.activityDefinitions).get(), isEmpty);
  });

  test('rescheduling keeps the earlier rule for past days', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    time.now = DateTime(2026, 11, 20, 9);
    await repo.update(
      a.copyWith(
        schedule: Weekdays(weekdays: {6, 7}, times: [hm(9, 0)]),
      ),
    );
    final stored = (await repo.byId(a.id))!;
    expect(stored.ruleOn(today), Daily(times: [hm(8, 0)]));
    expect(stored.ruleOn(LocalDate(2026, 11, 21)), Weekdays(weekdays: {6, 7}, times: [hm(9, 0)]));
  });

  test('a tracking type change that breaks past logs is refused', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    expect((await repo.update(a.copyWith(trackingType: TrackingType.boolean))).isOk, isTrue);
    final b = (await repo.byId(a.id))!;
    await repo.addLog(b.id, LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now));
    final refused = await repo.update(b.copyWith(trackingType: TrackingType.checklist));
    expect(refused.failureOrNull, isA<ValidationFailure>());
    expect((await repo.update(b.copyWith(trackingType: TrackingType.eventLog))).isOk, isTrue);
  });

  test('duplicate, archive, restore and reorder', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    final b = (await repo.create(draft(name: 'Brushing', type: TrackingType.boolean))).valueOrNull!;
    final copy = (await repo.duplicate(a.id, name: 'Walking (copy)')).valueOrNull!;
    expect(copy.id, isNot(a.id));
    expect(copy.trackingType, TrackingType.duration);
    await repo.setArchived(a.id, archived: true);
    var all = await repo.watchAll().first;
    expect(all.firstWhere((x) => x.id == a.id).archived, isTrue);
    await repo.setArchived(a.id, archived: false);
    await repo.reorder([copy.id, b.id, a.id]);
    all = await repo.watchAll().first;
    expect(all.map((x) => x.name), ['Walking (copy)', 'Brushing', 'Walking']);
    expect(all.every((x) => !x.archived), isTrue);
  });

  test('logs are stored per day with their values, several per day', () async {
    final a = (await repo.create(draft(type: TrackingType.count))).valueOrNull!;
    await repo.addLog(
      a.id,
      LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now, countValue: 1),
    );
    await repo.addLog(
      a.id,
      LogDraft(
        status: ActivityLogStatus.completed,
        occurredAt: time.now,
        countValue: 1,
        scheduledSlot: hm(8, 0),
      ),
    );
    final logs = await repo.watchLogsBetween(today, today).first;
    expect(logs, hasLength(2));
    expect(logs.map((l) => l.countValue), [1, 1]);
    expect(logs.last.scheduledSlot, hm(8, 0));
    expect(await repo.hasLogs(a.id), isTrue);
  });

  test('a log in the future or with a negative value is refused', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    final future = await repo.addLog(
      a.id,
      LogDraft(
        status: ActivityLogStatus.completed,
        occurredAt: time.now.add(const Duration(hours: 2)),
      ),
    );
    expect(future.failureOrNull, isA<ValidationFailure>());
    final negative = await repo.addLog(
      a.id,
      LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now, durationS: -5),
    );
    expect(negative.failureOrNull, isA<ValidationFailure>());
  });

  test('editing and deleting a log', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    final log = (await repo.addLog(
      a.id,
      LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now, durationS: 600),
    )).valueOrNull!;
    await repo.updateLog(
      log.id,
      LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now, durationS: 1200),
    );
    expect((await repo.watchLogsFor(a.id).first).single.durationS, 1200);
    await repo.deleteLog(log.id);
    expect(await repo.watchLogsFor(a.id).first, isEmpty);
    expect(await repo.hasLogs(a.id), isFalse);
  });

  test('deleting an activity removes it and its history', () async {
    final a = (await repo.create(draft())).valueOrNull!;
    await repo.addLog(a.id, LogDraft(status: ActivityLogStatus.skipped, occurredAt: time.now));
    await repo.delete(a.id);
    expect(await repo.watchAll().first, isEmpty);
    expect(await repo.watchLogsBetween(today, today).first, isEmpty);
    final rows = await db.select(db.activityLogs).get();
    expect(rows.single.deletedAt, isNotNull);
  });
}
