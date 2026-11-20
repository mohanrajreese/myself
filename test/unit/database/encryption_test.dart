import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/encrypted_connection.dart';
import 'package:fitbuddy/core/database/private_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _otherKey = 'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';
const _marker = 'FITBUDDY_PLAINTEXT_MARKER_91800';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fitbuddy_enc_');
    file = File('${dir.path}/fitbuddy.db');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  AppDatabase open(String key) => AppDatabase(NativeDatabase(file, setup: (db) => configureEncryption(db, key)));

  Future<void> writeMarker(AppDatabase db) => db.customStatement(
    'INSERT INTO local_app_settings (key, value_json, updated_at) VALUES (?, ?, ?)',
    ['marker', jsonEncode(_marker), '2026-11-16T00:00:00.000Z'],
  );

  test('the database file is not readable as plain SQLite', () async {
    final db = open(_key);
    await writeMarker(db);
    await db.close();

    final bytes = file.readAsBytesSync();
    final text = latin1.decode(bytes);
    expect(text.startsWith('SQLite format 3'), isFalse);
    expect(text.contains(_marker), isFalse);
    expect(text.contains('local_app_settings'), isFalse);
  });

  test('the same key reopens the data', () async {
    var db = open(_key);
    await writeMarker(db);
    await db.close();

    db = open(_key);
    final rows = await db.customSelect('SELECT value_json FROM local_app_settings').get();
    expect(rows.single.read<String>('value_json'), jsonEncode(_marker));
    await db.close();
  });

  test('a different key cannot open the database', () async {
    final db = open(_key);
    await writeMarker(db);
    await db.close();

    final wrong = open(_otherKey);
    await expectLater(wrong.customSelect('SELECT count(*) FROM local_app_settings').get(), throwsA(anything));
    await wrong.close();
  });

  test('uses the SQLCipher scheme, foreign keys and write-ahead logging', () async {
    final db = open(_key);
    Future<Object?> pragma(String name) async =>
        (await db.customSelect('PRAGMA $name').get()).single.data.values.single;
    expect(await pragma('cipher'), 'sqlcipher');
    expect(await pragma('foreign_keys'), 1);
    expect(await pragma('journal_mode'), 'wal');
    await db.close();
  });

  test('rejects anything that is not a 64-digit hex key', () {
    for (final bad in ['', 'abc', "x'; DROP TABLE t; --", '${_key}00', _key.toUpperCase()]) {
      expect(() => validateHexKey(bad), throwsArgumentError, reason: bad);
    }
    expect(() => validateHexKey(_key), returnsNormally);
  });

  test('the private database is encrypted with its own key', () async {
    final privateFile = File('${dir.path}/fitbuddy_private.db');
    var db = PrivateDatabase(NativeDatabase(privateFile, setup: (d) => configureEncryption(d, _otherKey)));
    await db.customSelect('SELECT 1').get();
    await db.close();
    expect(latin1.decode(privateFile.readAsBytesSync()).startsWith('SQLite format 3'), isFalse);

    db = PrivateDatabase(NativeDatabase(privateFile, setup: (d) => configureEncryption(d, _key)));
    await expectLater(db.customSelect('SELECT count(*) FROM sqlite_master').get(), throwsA(anything));
    await db.close();
  });
}
