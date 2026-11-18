import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fitbuddy/core/database/private_database.dart';
import 'package:fitbuddy/core/database/synced_tables.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_private/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a version 1 private database upgrades to the current schema', () async {
    final connection = await verifier.startAt(1);
    final db = PrivateDatabase(connection);
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  test('no private table is ever on the sync allow-list', () {
    final db = PrivateDatabase(NativeDatabase.memory());
    final names = [for (final t in db.allTables) t.actualTableName];
    expect(names, isNotEmpty);
    expect(names.where(syncedTableNames.contains), isEmpty);
    expect(names.every((n) => n.startsWith('local_')), isTrue);
    db.close();
  });
}
