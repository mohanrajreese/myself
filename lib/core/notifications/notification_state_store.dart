import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Status of one planned or shown notification (03 §3).
enum NotificationStatus {
  scheduled('scheduled'),
  snoozed('snoozed'),
  completed('completed'),
  skipped('skipped'),
  dismissed('dismissed'),
  cancelled('cancelled'),
  expired('expired');

  const NotificationStatus(this.code);
  final String code;
  static NotificationStatus fromCode(String code) => values.firstWhere((s) => s.code == code);
}

final class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.reminderId,
    required this.occurrenceLocal,
    required this.at,
    required this.status,
    required this.exact,
    required this.deferred,
    required this.snoozeCount,
    this.actedAt,
    this.channelId,
    this.store = 'main',
  });

  final int id;
  final String store;
  final String reminderId;

  /// `YYYY-MM-DDTHH:MM`, the scheduled wall-clock time.
  final String occurrenceLocal;
  final DateTime at;
  final NotificationStatus status;
  final bool exact;
  final bool deferred;
  final int snoozeCount;
  final DateTime? actedAt;
  final String? channelId;

  String get key => '$reminderId@$occurrenceLocal';
  String channelIdOr(String fallback) => channelId ?? fallback;
}

/// `local_notification_state`: stable ids and history. Device-only.
final class NotificationStateStore {
  NotificationStateStore(this._db);
  final AppDatabase _db;

  static const _maxId = 0x7fffffff;

  static NotificationRecord _toRecord(NotificationStateRow r) => NotificationRecord(
    id: r.notificationId,
    store: r.reminderStore,
    reminderId: r.reminderId,
    occurrenceLocal: r.occurrenceLocal,
    at: r.occurrenceAt.toUtc(),
    status: NotificationStatus.fromCode(r.status),
    exact: r.mode == 'exact',
    deferred: r.deferred,
    snoozeCount: r.snoozeCount,
    actedAt: r.actedAt?.toUtc(),
    channelId: r.channelId,
  );

  Future<List<NotificationRecord>> active({String store = 'main'}) async => [
    for (final r
        in await (_db.select(_db.localNotificationState)..where(
              (t) => t.reminderStore.equals(store) & t.status.isIn(const ['scheduled', 'snoozed']),
            ))
            .get())
      _toRecord(r),
  ];

  /// Keys that already have an outcome (acted on), so they are not planned again.
  Future<Set<String>> settledKeys(DateTime since, {String store = 'main'}) async => {
    for (final r
        in await (_db.select(_db.localNotificationState)..where(
              (t) =>
                  t.reminderStore.equals(store) &
                  t.occurrenceAt.isBiggerOrEqualValue(since) &
                  t.status.isIn(const ['completed', 'skipped', 'dismissed']),
            ))
            .get())
      _toRecord(r).key,
  };

  Future<NotificationRecord?> byId(int id) async {
    final row = await (_db.select(
      _db.localNotificationState,
    )..where((t) => t.notificationId.equals(id))).getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  /// The next free id: one above the highest, wrapping past 2^31 − 1.
  Future<int> _nextId() async {
    final max = _db.localNotificationState.notificationId.max();
    final row = await (_db.selectOnly(_db.localNotificationState)..addColumns([max])).getSingle();
    final next = (row.read(max) ?? 999) + 1;
    if (next <= _maxId) return next;
    var candidate = 1000;
    while (await byId(candidate) != null) {
      candidate++;
    }
    return candidate;
  }

  Future<NotificationRecord> add({
    required String reminderId,
    required String occurrenceLocal,
    required DateTime at,
    required String channelId,
    required bool exact,
    required bool deferred,
    String store = 'main',
  }) async {
    final id = await _nextId();
    await _db
        .into(_db.localNotificationState)
        .insert(
          LocalNotificationStateCompanion.insert(
            notificationId: Value(id),
            reminderStore: store,
            reminderId: reminderId,
            occurrenceAt: at.toUtc(),
            occurrenceLocal: occurrenceLocal,
            channelId: channelId,
            mode: exact ? 'exact' : 'inexact',
            status: 'scheduled',
            deferred: Value(deferred),
          ),
        );
    return (await byId(id))!;
  }

  Future<void> reschedule(
    int id, {
    required DateTime at,
    required bool exact,
    required bool deferred,
  }) => (_db.update(_db.localNotificationState)..where((t) => t.notificationId.equals(id))).write(
    LocalNotificationStateCompanion(
      occurrenceAt: Value(at.toUtc()),
      mode: Value(exact ? 'exact' : 'inexact'),
      deferred: Value(deferred),
    ),
  );

  Future<void> setStatus(int id, NotificationStatus status, {DateTime? actedAt}) =>
      (_db.update(_db.localNotificationState)..where((t) => t.notificationId.equals(id))).write(
        LocalNotificationStateCompanion(
          status: Value(status.code),
          actedAt: Value(actedAt?.toUtc()),
        ),
      );

  Future<void> snooze(int id, DateTime until) async {
    final record = await byId(id);
    if (record == null) return;
    await (_db.update(_db.localNotificationState)..where((t) => t.notificationId.equals(id))).write(
      LocalNotificationStateCompanion(
        status: const Value('snoozed'),
        occurrenceAt: Value(until.toUtc()),
        snoozeCount: Value(record.snoozeCount + 1),
      ),
    );
  }

  /// History for the notification centre, newest first, up to [until].
  Stream<List<NotificationRecord>> watchHistory({
    required DateTime since,
    required DateTime until,
  }) =>
      (_db.select(_db.localNotificationState)
            ..where(
              (t) =>
                  t.occurrenceAt.isBetweenValues(since.toUtc(), until.toUtc()) &
                  t.status.isNotIn(const ['scheduled', 'cancelled']),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.occurrenceAt, mode: OrderingMode.desc)]))
          .watch()
          .map((rows) => [for (final r in rows) _toRecord(r)]);

  /// Removes rows older than [before] (kept 30 days, 03 §8).
  Future<int> prune(DateTime before) => (_db.delete(
    _db.localNotificationState,
  )..where((t) => t.occurrenceAt.isSmallerThanValue(before.toUtc()))).go();
}
