import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Permissions the app may declare. Extend this list only together with
/// docs/permissions.md and docs/blueprint/01-architecture.md §2.1.
const _allowedPermissions = {
  'android.permission.INTERNET',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.SCHEDULE_EXACT_ALARM',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'android.permission.VIBRATE',
  'android.permission.ACTIVITY_RECOGNITION',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_HEALTH',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.FOREGROUND_SERVICE_LOCATION',
  'android.permission.PACKAGE_USAGE_STATS',
  'android.permission.USE_BIOMETRIC',
};

/// Never declared (docs/blueprint/01-architecture.md §2.1).
const _forbiddenPermissions = {
  'android.permission.USE_EXACT_ALARM',
  'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.CAMERA',
  'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
  'android.permission.SYSTEM_ALERT_WINDOW',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
};

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final declared = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
      .allMatches(manifest)
      .map((m) => m.group(1)!)
      .toSet();

  test('backups and device transfer are disabled', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));

    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules)?.group(1);
      expect(body, isNotNull, reason: section);
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(body, contains('<exclude domain="$domain"'), reason: '$section/$domain');
      }
      expect(body, isNot(contains('<include')), reason: section);
    }
  });

  test('cleartext traffic is disabled', () {
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
    final config = File('android/app/src/main/res/xml/network_security_config.xml')
        .readAsStringSync();
    expect(config, contains('cleartextTrafficPermitted="false"'));
  });

  test('Firebase analytics collection stays deactivated', () {
    expect(
      manifest,
      contains(
        RegExp(r'android:name="firebase_analytics_collection_deactivated"\s+android:value="true"'),
      ),
    );
  });

  test('only planned permissions are declared', () {
    expect(declared.difference(_allowedPermissions), isEmpty);
    expect(declared.intersection(_forbiddenPermissions), isEmpty);
  });

  test('the main activity supports the biometric prompt', () {
    final activity = File('android/app/src/main/kotlin/com/mysticstack/fitbuddy/MainActivity.kt')
        .readAsStringSync();
    expect(activity, contains('FlutterFragmentActivity'));
  });
}
