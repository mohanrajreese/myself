import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/privacy.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/Privacy.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated', errorClassName: 'PrivacyFlutterError'),
    dartPackageName: 'fitbuddy',
  ),
)
class AppUsageMessage {
  AppUsageMessage({required this.packageName, required this.label, required this.foregroundMs});
  String packageName;
  String label;
  int foregroundMs;
}

@HostApi()
abstract class SecurityApi {
  /// `FLAG_SECURE`: hides the app in recent apps and blocks screenshots.
  void setSecureWindow(bool secure);
}

@HostApi()
abstract class UsageApi {
  /// Usage access granted (`AppOpsManager.OPSTR_GET_USAGE_STATS`).
  bool hasAccess();
  void openAccessSettings();

  /// Foreground time per app between two instants, from usage events.
  List<AppUsageMessage> usage(int startMs, int endMs);
}
