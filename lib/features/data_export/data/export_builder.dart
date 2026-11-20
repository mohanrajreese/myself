import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/private_database.dart';
import '../../../core/database/synced_tables.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../nutrition/domain/meal_photos.dart';
import '../domain/export.dart';

/// Builds the export zip on the phone (§7.3 "secure export"). Nothing is
/// written to disk or sent anywhere; the caller hands the bytes to the
/// system "save as" picker.
final class ExportBuilder {
  ExportBuilder({required this.db, required this.clock, this.privateDb, this.mealPhotos, this.readProgressPhoto});

  final AppDatabase db;
  final PrivateDatabase? privateDb;
  final MealPhotoStore? mealPhotos;
  final Future<List<int>?> Function(String id)? readProgressPhoto;
  final Clock clock;

  /// Device-only tables that hold the user's own records (not caches,
  /// cursors, raw readings or the food catalogue).
  static const localRecordTables = ['local_recovery_logs', 'local_step_daily', 'local_timer_sessions'];

  static const _dateColumns = ['local_date', 'log_date'];

  /// Child rows follow their parent's date.
  static const _childFilters = {
    'meal_food_items': 'meal_log_id IN (SELECT id FROM meal_logs WHERE local_date BETWEEN ?1 AND ?2)',
    'workout_exercises': 'session_id IN (SELECT id FROM workout_sessions WHERE local_date BETWEEN ?1 AND ?2)',
    'exercise_sets':
        'workout_exercise_id IN (SELECT we.id FROM workout_exercises we JOIN workout_sessions ws '
        'ON ws.id = we.session_id WHERE ws.local_date BETWEEN ?1 AND ?2)',
  };

  Future<Uint8List> build(ExportOptions o) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in [...syncedTableNames, ...localRecordTables]) {
      tables[t] = await _rows(db, t, o);
    }
    final p = privateDb;
    if (o.includePrivate && p != null) {
      for (final t in p.allTables) {
        tables['private.${t.actualTableName}'] = await _rows(p, t.actualTableName, o);
      }
    }

    final archive = Archive();
    void addText(String name, String text) => archive.add(ArchiveFile.bytes(name, utf8.encode(text)));
    final now = clock.now().toUtc().toIso8601String();
    final manifest = {
      'format': 'praxis-export',
      'version': 1,
      'exported_at': now,
      'from': o.from?.toString(),
      'to': o.to?.toString(),
      'includes_private': o.includePrivate && p != null,
      'units': 'Integers in base units: g, mg, ml, mm, m, s; energy in kcal × 1000',
    };
    if (o.format == ExportFormat.json) {
      addText('praxis.json', const JsonEncoder.withIndent(' ').convert({...manifest, 'tables': tables}));
    } else {
      addText('manifest.json', const JsonEncoder.withIndent(' ').convert(manifest));
      for (final e in tables.entries) {
        if (e.value.isNotEmpty) addText('${e.key}.csv', toCsv(e.value));
      }
    }

    if (o.includePhotos) {
      final store = mealPhotos;
      if (store != null) {
        for (final meal in tables['meal_logs'] ?? const <Map<String, Object?>>[]) {
          if (meal['has_photo'] != 1) continue;
          final bytes = await store.read(meal['id']! as String);
          if (bytes != null) {
            archive.add(ArchiveFile.bytes('photos/meals/${meal['id']}.jpg', bytes));
          }
        }
      }
      final read = readProgressPhoto;
      if (o.includePrivate && read != null) {
        for (final photo in tables['private.local_progress_photos'] ?? const <Map<String, Object?>>[]) {
          final bytes = await read(photo['id']! as String);
          if (bytes != null) {
            archive.add(ArchiveFile.bytes('photos/progress/${photo['id']}.jpg', bytes));
          }
        }
      }
    }
    return ZipEncoder(password: o.passphrase).encodeBytes(archive);
  }

  Future<List<Map<String, Object?>>> _rows(GeneratedDatabase d, String table, ExportOptions o) async {
    final info = d.allTables.firstWhere((t) => t.actualTableName == table);
    final child = _childFilters[table];
    if (child != null && d is AppDatabase && (o.from != null || o.to != null)) {
      final rows = await d
          .customSelect(
            'SELECT * FROM $table WHERE $child',
            variables: [
              Variable.withString((o.from ?? LocalDate(1970, 1, 1)).toString()),
              Variable.withString((o.to ?? LocalDate(9999, 12, 31)).toString()),
            ],
          )
          .get();
      return [for (final r in rows) r.data];
    }
    final dateCol = _dateColumns.where((c) => info.columnsByName.containsKey(c)).firstOrNull;
    final where = <String>[];
    final vars = <Variable<Object>>[];
    if (dateCol != null && o.from != null) {
      where.add('$dateCol >= ?');
      vars.add(Variable.withString(o.from.toString()));
    }
    if (dateCol != null && o.to != null) {
      where.add('$dateCol <= ?');
      vars.add(Variable.withString(o.to.toString()));
    }
    final sql = 'SELECT * FROM $table${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}';
    return [for (final r in await d.customSelect(sql, variables: vars).get()) r.data];
  }
}
