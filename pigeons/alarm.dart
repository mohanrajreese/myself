import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/alarm.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/Alarm.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated', errorClassName: 'AlarmFlutterError'),
    dartPackageName: 'fitbuddy',
  ),
)
@HostApi()
abstract class AlarmApi {
  /// `AlarmManager.canScheduleExactAlarms`; always true before Android 12.
  bool canScheduleExactAlarms();

  /// Opens the exact-alarm access page (Android 12+) or the app's settings.
  void openExactAlarmSettings();

  /// `PowerManager.isIgnoringBatteryOptimizations` for this app.
  bool isIgnoringBatteryOptimizations();

  /// Opens the battery-optimisation list. The app never asks to be exempted
  /// directly (01 §2.1).
  void openBatterySettings();

  /// Ids of this app's notification channels that the user switched off.
  List<String> disabledChannels();

  /// Opens Android's settings for one channel (sound, vibration).
  void openChannelSettings(String channelId);

  /// Opens the app's notification settings.
  void openNotificationSettings();

  /// Plays the channel's sound (or the default notification sound) once.
  void playTestSound(String channelId);

  /// Vibrates briefly.
  void testVibration();

  /// The last system event seen while the app was closed (`boot`,
  /// `timezone`, `time`, `update`, `exact_alarm`), then clears it.
  String? takePendingSystemEvent();
}
