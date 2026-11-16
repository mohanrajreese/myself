import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ok exposes its value and maps', () {
    const Result<int> result = Ok(2);
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, 2);
    expect(result.map((v) => v * 2).valueOrNull, 4);
    expect(result.when(ok: (v) => 'ok $v', err: (f) => 'err'), 'ok 2');
  });

  test('Err carries a failure and skips map', () {
    const Result<int> result = Err(ValidationFailure('weight', 'out_of_range'));
    expect(result.isOk, isFalse);
    expect(result.valueOrNull, isNull);
    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.map((v) => v * 2).failureOrNull, isA<ValidationFailure>());
  });

  test('guard converts a thrown error into a StorageFailure without its message', () async {
    final result = await Result.guard<int>(
      () async => throw StateError('secret detail 91.8 kg'),
      onError: (error) => const StorageFailure('weight_write'),
    );
    expect(result.failureOrNull, const StorageFailure('weight_write'));
    expect(result.failureOrNull.toString(), isNot(contains('secret')));
  });

  test('failures are value-equal and never embed free text', () {
    expect(const NetworkFailure('timeout'), const NetworkFailure('timeout'));
    expect(
      const PermissionFailure('activity_recognition', permanentlyDenied: true).code,
      'activity_recognition',
    );
  });
}
