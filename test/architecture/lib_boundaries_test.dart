import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'boundary_rules.dart';

void main() {
  test('lib/ respects the architecture and privacy boundaries', () {
    final sources = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relative = entity.path.replaceAll(r'\', '/').substring('lib/'.length);
        sources[relative] = entity.readAsStringSync();
      }
    }
    expect(sources, isNotEmpty);
    final violations = checkBoundaries(sources);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
