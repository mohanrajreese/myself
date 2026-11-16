import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = memoryDatabase();
    settings = SettingsRepository(db, clock: MutableClock(DateTime(2026, 11, 16)).clock);
  });
  tearDown(() => db.close());

  test('reads null for a setting that was never written', () async {
    expect(await settings.read('bound_account'), isNull);
  });

  test('round-trips strings, numbers, booleans, lists and maps', () async {
    await settings.write('bound_account', 'user-1');
    await settings.write('dashboard_order', ['steps', 'water']);
    await settings.write('reminder_prefs', {'water': true, 'workout': false});
    expect(await settings.read('bound_account'), 'user-1');
    expect(await settings.read('dashboard_order'), ['steps', 'water']);
    expect(await settings.read('reminder_prefs'), {'water': true, 'workout': false});
  });

  test('overwrites and removes', () async {
    await settings.write('theme', 'dark');
    await settings.write('theme', 'light');
    expect(await settings.read('theme'), 'light');
    await settings.remove('theme');
    expect(await settings.read('theme'), isNull);
  });

  test('settings never enter the sync outbox', () async {
    await settings.write('bound_account', 'user-1');
    expect(await outboxEntries(db), isEmpty);
  });

  test('watch emits on change', () async {
    final expectation = expectLater(settings.watch('theme'), emitsInOrder([null, 'dark']));
    await Future<void>.delayed(Duration.zero);
    await settings.write('theme', 'dark');
    await expectation;
  });
}
