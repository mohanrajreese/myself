import 'generated/system_info.pigeon.dart';
import 'time_zone_source.dart';

/// Reads the timezone from Android. Falls back to UTC if the platform call
/// fails, so a record can always be saved.
final class DeviceTimeZone implements TimeZoneSource {
  DeviceTimeZone([SystemInfoApi? api]) : _api = api ?? SystemInfoApi();

  final SystemInfoApi _api;

  @override
  Future<String> currentTimeZoneId() async {
    try {
      final id = await _api.timeZoneId();
      return id.isEmpty ? 'UTC' : id;
    } on Object {
      return 'UTC';
    }
  }
}
