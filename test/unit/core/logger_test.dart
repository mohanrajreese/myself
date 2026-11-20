import 'package:fitbuddy/core/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes the event code and safe fields', () {
    final lines = <String>[];
    final logger = AppLogger(sink: lines.add);
    logger.event('sync_push_ok', {
      'rows': 3,
      'retry': false,
      'took': const Duration(milliseconds: 120),
    });
    expect(lines.single, 'sync_push_ok rows=3 retry=false took=120ms');
  });

  test('never writes string values, so record text cannot leak', () {
    final lines = <String>[];
    final logger = AppLogger(sink: lines.add);
    logger.event('note_saved', {'note': 'felt unwell after dinner', 'length': 24});
    expect(lines.single, 'note_saved note=<redacted> length=24');
    expect(lines.single, isNot(contains('unwell')));
  });

  test('redacts doubles, lists and other objects, keeps enums', () {
    final lines = <String>[];
    final logger = AppLogger(sink: lines.add);
    logger.event('x', {
      'w': 91.8,
      'items': [1, 2],
      'level': LogLevel.warning,
    });
    expect(lines.single, 'x w=<redacted> items=<redacted> level=warning');
  });

  test('rejects event codes that are not lower_snake_case identifiers', () {
    final logger = AppLogger(sink: (_) {});
    expect(() => logger.event('User weighs 91.8 kg'), throwsArgumentError);
    expect(() => logger.event('weight_saved'), returnsNormally);
  });

  test('failure logging records only type and code', () {
    final lines = <String>[];
    AppLogger(sink: lines.add).failure('weight_write_failed', StateError('91.8 kg rejected'));
    expect(lines.single, 'weight_write_failed error_type=StateError');
  });
}
