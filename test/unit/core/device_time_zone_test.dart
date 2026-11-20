import 'package:fitbuddy/core/platform/device_time_zone.dart';
import 'package:fitbuddy/core/platform/generated/system_info.pigeon.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements SystemInfoApi {
  _Api(this._answer);
  final Future<String> Function() _answer;
  @override
  Future<String> timeZoneId() => _answer();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('returns the platform timezone id', () async {
    expect(await DeviceTimeZone(_Api(() async => 'Asia/Kolkata')).currentTimeZoneId(), 'Asia/Kolkata');
  });

  test('falls back to UTC when the platform fails or answers nothing', () async {
    expect(await DeviceTimeZone(_Api(() async => '')).currentTimeZoneId(), 'UTC');
    expect(await DeviceTimeZone(_Api(() async => throw StateError('x'))).currentTimeZoneId(), 'UTC');
  });
}
