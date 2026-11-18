import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/export.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mysticstack/fitbuddy/generated/Export.pigeon.kt',
    kotlinOptions: KotlinOptions(package: 'com.mysticstack.fitbuddy.generated', errorClassName: 'ExportFlutterError'),
    dartPackageName: 'fitbuddy',
  ),
)
@HostApi()
abstract class ExportApi {
  /// Opens the system "save as" picker (`ACTION_CREATE_DOCUMENT`) with
  /// [fileName] suggested, then writes [bytes] there. Returns false when the
  /// user cancels or the file cannot be written. Needs no permission.
  @async
  bool saveDocument(String fileName, Uint8List bytes);
}
