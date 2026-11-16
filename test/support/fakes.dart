import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/platform/time_zone_source.dart';
import 'package:fitbuddy/core/utils/clock.dart';
import 'package:fitbuddy/core/utils/id_generator.dart';

AppDatabase memoryDatabase() {
  // Each test opens its own in-memory database; that is intended.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// A clock the test moves by hand.
class MutableClock {
  MutableClock(this.now);
  DateTime now;
  Clock get clock => Clock(() => now);
}

class SequentialIds implements IdGenerator {
  int _next = 1;
  @override
  String newId() => 'id-${_next++}';
}

class FixedTimeZone implements TimeZoneSource {
  const FixedTimeZone([this.id = 'Asia/Kolkata']);
  final String id;
  @override
  Future<String> currentTimeZoneId() async => id;
}

Future<List<({String table, String id})>> outboxEntries(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT entity_table, entity_id FROM sync_outbox ORDER BY seq')
      .get();
  return [
    for (final row in rows)
      (table: row.read<String>('entity_table'), id: row.read<String>('entity_id')),
  ];
}
