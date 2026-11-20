import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../encryption/secret_store.dart';

/// User's lock choices (§7.3). Stored in Keystore-backed secure storage.
final class AppLockSettings {
  const AppLockSettings({
    this.enabled = false,
    this.biometric = false,
    this.lockAfter = const Duration(minutes: 1),
    this.wholeApp = false,
  });
  final bool enabled;
  final bool biometric;

  /// Time in the background before the lock applies again.
  final Duration lockAfter;

  /// Lock the whole app, not only private areas.
  final bool wholeApp;

  AppLockSettings copyWith({bool? enabled, bool? biometric, Duration? lockAfter, bool? wholeApp}) => AppLockSettings(
    enabled: enabled ?? this.enabled,
    biometric: biometric ?? this.biometric,
    lockAfter: lockAfter ?? this.lockAfter,
    wholeApp: wholeApp ?? this.wholeApp,
  );

  String encode() =>
      jsonEncode({'enabled': enabled, 'biometric': biometric, 'lockAfterS': lockAfter.inSeconds, 'wholeApp': wholeApp});

  static AppLockSettings decode(String? json) {
    if (json == null) return const AppLockSettings();
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      return AppLockSettings(
        enabled: m['enabled'] == true,
        biometric: m['biometric'] == true,
        lockAfter: Duration(seconds: (m['lockAfterS'] as int?) ?? 60),
        wholeApp: m['wholeApp'] == true,
      );
    } on Object {
      return const AppLockSettings();
    }
  }
}

/// PIN storage: a salted PBKDF2-HMAC-SHA256 hash, never the PIN (C8).
final class PinStore {
  PinStore(this._secrets, {this.iterations = 120000, Random? random}) : _random = random ?? Random.secure();

  final SecretStore _secrets;
  final int iterations;
  final Random _random;

  static const _pinKey = 'app_lock_pin';
  static const _settingsKey = 'app_lock_settings';

  /// 4 to 8 digits.
  static bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  Future<List<int>> _hash(String pin, List<int> salt, int iterations) async {
    final key = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  Future<bool> hasPin() async => await _secrets.read(_pinKey) != null;

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 8 digits');
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _hash(pin, salt, iterations);
    await _secrets.write(
      _pinKey,
      jsonEncode({'salt': base64Encode(salt), 'hash': base64Encode(hash), 'iterations': iterations}),
    );
  }

  Future<bool> verify(String pin) async {
    final raw = await _secrets.read(_pinKey);
    if (raw == null) return false;
    final m = jsonDecode(raw) as Map<String, Object?>;
    final expected = base64Decode(m['hash']! as String);
    final actual = await _hash(pin, base64Decode(m['salt']! as String), m['iterations']! as int);
    // Constant-time comparison.
    var diff = expected.length ^ actual.length;
    for (var i = 0; i < expected.length && i < actual.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }

  Future<void> clear() async {
    await _secrets.delete(_pinKey);
    await writeSettings(const AppLockSettings());
  }

  Future<AppLockSettings> readSettings() async => AppLockSettings.decode(await _secrets.read(_settingsKey));
  Future<void> writeSettings(AppLockSettings s) => _secrets.write(_settingsKey, s.encode());
}

/// Whether protected areas are open right now. Pure; time is passed in.
final class LockState {
  LockState(this.settings);

  AppLockSettings settings;
  DateTime? _unlockedAt;
  DateTime? _backgroundAt;
  int _failures = 0;
  DateTime? _blockedUntil;

  bool get isUnlocked => !settings.enabled || _unlockedAt != null;

  void unlocked(DateTime at) {
    _unlockedAt = at;
    _failures = 0;
    _blockedUntil = null;
  }

  void lockNow() => _unlockedAt = null;

  void movedToBackground(DateTime at) => _backgroundAt = at;

  /// Locks again when the app was away for at least `lockAfter`.
  void returnedToForeground(DateTime at) {
    final away = _backgroundAt;
    _backgroundAt = null;
    if (away != null && at.difference(away) >= settings.lockAfter) lockNow();
  }

  /// After 5 wrong PINs, waits 30 seconds, doubling each further miss
  /// (capped at 15 minutes). Returns when the next try is allowed.
  DateTime? wrongPin(DateTime at) {
    _failures++;
    if (_failures < 5) return null;
    final wait = Duration(seconds: min(30 * (1 << (_failures - 5)), 900));
    _blockedUntil = at.add(wait);
    return _blockedUntil;
  }

  Duration? blockedFor(DateTime at) {
    final until = _blockedUntil;
    if (until == null || !at.isBefore(until)) return null;
    return until.difference(at);
  }
}
