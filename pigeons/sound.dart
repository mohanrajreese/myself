import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/sound.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/Sound.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated', errorClassName: 'SoundFlutterError'),
    dartPackageName: 'fitbuddy',
  ),
)
class SystemSound {
  SystemSound({required this.title, required this.uri});
  String title;
  String uri;
}

@HostApi()
abstract class SoundApi {
  /// Notification sounds installed on the phone (`RingtoneManager`).
  List<SystemSound> systemSounds();

  /// Opens the system document picker for one audio file, copies it into
  /// app-private storage and returns a content URI the notification system
  /// can read; null when cancelled or unreadable.
  @async
  String? pickAndImportSound();

  /// Plays [uri] once, stopping any earlier preview.
  void play(String uri);

  void stop();
}
