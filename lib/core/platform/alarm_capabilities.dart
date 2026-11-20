import 'generated/alarm.pigeon.dart';

/// What Android allows for reminders right now (05 §A3 `AndroidAlarmService`).
abstract interface class AlarmCapabilities {
  Future<bool> canScheduleExactAlarms();
  Future<void> openExactAlarmSettings();
  Future<bool> isIgnoringBatteryOptimizations();
  Future<void> openBatterySettings();
  Future<List<String>> disabledChannels();
  Future<void> openChannelSettings(String channelId);
  Future<void> openNotificationSettings();
  Future<void> playTestSound(String channelId);
  Future<void> testVibration();

  /// `boot`, `timezone`, `time`, `update` or `exact_alarm`, then cleared.
  Future<String?> takePendingSystemEvent();
}

/// Platform errors become safe answers: a failed check reports the
/// restrictive state, so the UI explains rather than over-promises.
final class DeviceAlarmCapabilities implements AlarmCapabilities {
  DeviceAlarmCapabilities([AlarmApi? api]) : _api = api ?? AlarmApi();
  final AlarmApi _api;

  Future<T> _try<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Object {
      return fallback;
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() => _try(_api.canScheduleExactAlarms, false);
  @override
  Future<void> openExactAlarmSettings() => _try(_api.openExactAlarmSettings, null);
  @override
  Future<bool> isIgnoringBatteryOptimizations() => _try(_api.isIgnoringBatteryOptimizations, false);
  @override
  Future<void> openBatterySettings() => _try(_api.openBatterySettings, null);
  @override
  Future<List<String>> disabledChannels() => _try(_api.disabledChannels, const <String>[]);
  @override
  Future<void> openChannelSettings(String channelId) => _try(() => _api.openChannelSettings(channelId), null);
  @override
  Future<void> openNotificationSettings() => _try(_api.openNotificationSettings, null);
  @override
  Future<void> playTestSound(String channelId) => _try(() => _api.playTestSound(channelId), null);
  @override
  Future<void> testVibration() => _try(_api.testVibration, null);
  @override
  Future<String?> takePendingSystemEvent() => _try(_api.takePendingSystemEvent, null);
}
