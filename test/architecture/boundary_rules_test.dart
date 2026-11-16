import 'package:flutter_test/flutter_test.dart';

import 'boundary_rules.dart';

List<String> _rules(Map<String, String> sources) =>
    checkBoundaries(sources).map((v) => v.rule).toList();

void main() {
  group('domain purity', () {
    test('rejects Flutter, storage and data-layer imports', () {
      expect(
        _rules({
          'features/weight/domain/weight_entry.dart': '''
import 'package:flutter/material.dart';
import 'package:drift/drift.dart';
import '../data/weight_dao.dart';
''',
        }),
        ['domain-purity', 'domain-purity', 'domain-purity'],
      );
    });

    test('allows dart core, pure packages, other domain code and pure core', () {
      expect(
        _rules({
          'features/weight/domain/weight_entry.dart': '''
import 'dart:math';
import 'package:meta/meta.dart';
import 'package:fitbuddy/core/units/mass.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/features/profile/domain/profile.dart';
import 'weight_rules.dart';
''',
        }),
        isEmpty,
      );
    });
  });

  group('presentation', () {
    test('rejects storage packages, the data layer and platform channels', () {
      expect(
        _rules({
          'features/weight/presentation/weight_screen.dart': '''
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/weight_repository_impl.dart';
final c = MethodChannel('x');
''',
        }),
        [
          'presentation-no-storage',
          'presentation-no-data-layer',
          'presentation-no-platform-channel',
        ],
      );
    });

    test('rejects literal colours in feature UI but not in comments', () {
      expect(
        _rules({
          'features/weight/presentation/a.dart': 'final c = Color(0xFF000000);',
          'features/weight/presentation/b.dart': '// Color(0xFF000000) is banned',
        }),
        ['design-tokens'],
      );
    });
  });

  group('feature isolation', () {
    test('another feature is reachable only through its domain', () {
      expect(
        _rules({
          'features/dashboard/application/a.dart':
              "import 'package:fitbuddy/features/weight/application/weight_controller.dart';",
          'features/dashboard/application/b.dart':
              "import 'package:fitbuddy/features/weight/domain/weight_repository.dart';",
        }),
        ['feature-isolation'],
      );
    });
  });

  group('privacy', () {
    test('sync, networking and remote sources cannot import the private database', () {
      expect(
        _rules({
          'core/sync/sync_engine.dart': "import '../database/private_database.dart';",
          'core/networking/client.dart':
              "import 'package:fitbuddy/core/database/private/bowel_dao.dart';",
          'features/weight/data/weight_remote_source.dart':
              "import 'package:fitbuddy/core/database/private_database.dart';",
        }),
        ['privacy-sync-boundary', 'privacy-sync-boundary', 'privacy-sync-boundary'],
      );
    });

    test('sync may import the main database', () {
      expect(
        _rules({'core/sync/sync_engine.dart': "import '../database/app_database.dart';"}),
        isEmpty,
      );
    });
  });

  group('injected clock', () {
    test('DateTime.now() is allowed only in core/utils/clock.dart', () {
      expect(
        _rules({
          'core/utils/clock.dart': 'final n = DateTime.now();',
          'features/water/data/water_repository_impl.dart': 'final n = DateTime.now();',
          'features/water/data/other.dart': '// DateTime.now() must not be used',
        }),
        ['injected-clock'],
      );
    });
  });

  test('generated files are skipped', () {
    expect(
      _rules({'features/weight/domain/weight_entry.g.dart': "import 'package:drift/drift.dart';"}),
      isEmpty,
    );
  });
}
