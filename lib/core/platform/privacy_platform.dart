import 'package:local_auth/local_auth.dart';

import 'generated/privacy.pigeon.dart';

/// Hides the app in recent apps and blocks screenshots while on (§7.3).
abstract interface class SecureWindow {
  Future<void> set({required bool secure});
}

final class DeviceSecureWindow implements SecureWindow {
  DeviceSecureWindow([SecurityApi? api]) : _api = api ?? SecurityApi();
  final SecurityApi _api;

  @override
  Future<void> set({required bool secure}) async {
    try {
      await _api.setSecureWindow(secure);
    } on Object {
      // Without the flag the lock still works; the device test checks it.
    }
  }
}

typedef AppUsage = ({String packageName, String label, int foregroundMs});

/// Android usage statistics (§5.17); raw per-app foreground time.
abstract interface class UsageReader {
  Future<bool> hasAccess();
  Future<void> openAccessSettings();
  Future<List<AppUsage>> usage(DateTime start, DateTime end);
}

final class DeviceUsageReader implements UsageReader {
  DeviceUsageReader([UsageApi? api]) : _api = api ?? UsageApi();
  final UsageApi _api;

  @override
  Future<bool> hasAccess() async {
    try {
      return await _api.hasAccess();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> openAccessSettings() async {
    try {
      await _api.openAccessSettings();
    } on Object {
      // The screen keeps explaining how to switch it on.
    }
  }

  @override
  Future<List<AppUsage>> usage(DateTime start, DateTime end) async {
    try {
      return [
        for (final u in await _api.usage(start.millisecondsSinceEpoch, end.millisecondsSinceEpoch))
          (packageName: u.packageName, label: u.label, foregroundMs: u.foregroundMs),
      ];
    } on Object {
      return const [];
    }
  }
}

/// Fingerprint or face unlock through the system prompt.
abstract interface class Biometrics {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

final class DeviceBiometrics implements Biometrics {
  DeviceBiometrics([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    try {
      return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } on Object {
      return false;
    }
  }
}
