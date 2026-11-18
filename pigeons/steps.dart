import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/steps.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/Steps.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated', errorClassName: 'StepsFlutterError'),
    dartPackageName: 'fitbuddy',
  ),
)
class StepReadingMessage {
  StepReadingMessage({
    required this.id,
    required this.cumulativeSteps,
    required this.bootCount,
    required this.elapsedRealtimeMs,
    required this.wallTimeUtcMs,
    required this.tz,
    required this.utcOffsetS,
    required this.source,
  });
  int id;
  int cumulativeSteps;
  int bootCount;
  int elapsedRealtimeMs;
  int wallTimeUtcMs;
  String tz;
  int utcOffsetS;
  String source;
}

@HostApi()
abstract class StepApi {
  /// Whether the phone has `Sensor.TYPE_STEP_COUNTER`.
  bool hasSensor();

  /// `ACTIVITY_RECOGNITION` granted (always true before Android 10's prompt).
  bool hasPermission();

  /// Shows the system prompt; returns the result.
  @async
  bool requestPermission();

  /// Takes one reading now and stores it in the native buffer; null when the
  /// sensor gave no value in time.
  @async
  StepReadingMessage? readNow();

  /// Readings waiting in the native buffer, oldest first.
  List<StepReadingMessage> pendingReadings();

  /// Removes buffered readings up to and including [maxId].
  void acknowledge(int maxId);

  /// Starts or stops continuous collection (foreground service).
  void setContinuous(bool enabled);
  bool isContinuous();

  /// Schedules the 15-minute snapshot job (idempotent).
  void scheduleSnapshots();
}
