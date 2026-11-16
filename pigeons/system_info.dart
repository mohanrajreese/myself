import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/system_info.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/SystemInfo.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated'),
    dartPackageName: 'fitbuddy',
  ),
)
@HostApi()
abstract class SystemInfoApi {
  /// IANA identifier of the device's current timezone, e.g. `Asia/Kolkata`.
  String timeZoneId();
}
