import 'package:fitbuddy/app/providers.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/features/dashboard/application/home_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  ProviderContainer build() =>
      ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

  setUp(() {
    db = memoryDatabase();
    container = build();
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<String>> order() async => [
        for (final item in await container.read(homeLayoutProvider.future))
          '${item.section.name}${item.visible ? '' : ' (hidden)'}',
      ];

  test('default order shows every section', () async {
    expect(await order(), ['progress', 'quickAdd', 'essentials', 'timeline']);
  });

  test('hiding and reordering are remembered', () async {
    await container.read(homeLayoutProvider.future);
    final controller = container.read(homeLayoutProvider.notifier);
    await controller.setVisible(HomeSection.essentials, false);
    await controller.move(3, 0);
    expect(await order(), ['timeline', 'progress', 'quickAdd', 'essentials (hidden)']);

    container.dispose();
    container = build();
    expect(await order(), ['timeline', 'progress', 'quickAdd', 'essentials (hidden)']);
  });

  test('unknown or missing sections in stored settings are repaired', () async {
    await container.read(settingsRepositoryProvider).write('home_layout', [
      {'id': 'timeline', 'visible': true},
      {'id': 'removed_section', 'visible': true},
      {'id': 'timeline', 'visible': false},
    ]);
    expect(await order(), ['timeline', 'progress', 'quickAdd', 'essentials']);
  });
}
