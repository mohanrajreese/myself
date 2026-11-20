import 'package:fitbuddy/core/encryption/secret_store.dart';
import 'package:fitbuddy/core/security/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 18, 9);

  group('PIN', () {
    test('stores a salted hash, never the PIN, and verifies it', () async {
      final secrets = InMemorySecretStore();
      final pins = PinStore(secrets, iterations: 1000);
      await pins.setPin('2468');
      final stored = await secrets.read('app_lock_pin');
      expect(stored, isNot(contains('2468')));
      expect(await pins.verify('2468'), isTrue);
      expect(await pins.verify('2469'), isFalse);
    });

    test('the same PIN gets a different salt each time', () async {
      final a = InMemorySecretStore();
      final b = InMemorySecretStore();
      await PinStore(a, iterations: 1000).setPin('1234');
      await PinStore(b, iterations: 1000).setPin('1234');
      expect(await a.read('app_lock_pin'), isNot(await b.read('app_lock_pin')));
    });

    test('only 4 to 8 digits are accepted', () {
      expect(PinStore.isValidPin('123'), isFalse);
      expect(PinStore.isValidPin('12345678'), isTrue);
      expect(PinStore.isValidPin('12a4'), isFalse);
      expect(() => PinStore(InMemorySecretStore()).setPin('12'), throwsArgumentError);
    });

    test('settings round-trip and survive bad data', () async {
      final pins = PinStore(InMemorySecretStore(), iterations: 1000);
      await pins.writeSettings(const AppLockSettings(enabled: true, biometric: true, lockAfter: Duration(minutes: 5)));
      final s = await pins.readSettings();
      expect((s.enabled, s.biometric, s.lockAfter), (true, true, const Duration(minutes: 5)));
      expect(AppLockSettings.decode('nonsense').enabled, isFalse);
    });
  });

  group('lock state', () {
    test('with the lock off everything is open', () {
      expect(LockState(const AppLockSettings()).isUnlocked, isTrue);
    });

    test('locks again after the chosen time in the background, not before', () {
      final s = LockState(const AppLockSettings(enabled: true))..unlocked(t0);
      s
        ..movedToBackground(t0)
        ..returnedToForeground(t0.add(const Duration(seconds: 30)));
      expect(s.isUnlocked, isTrue);
      s
        ..movedToBackground(t0)
        ..returnedToForeground(t0.add(const Duration(minutes: 1)));
      expect(s.isUnlocked, isFalse);
    });

    test('five wrong PINs block for 30 s, then the wait doubles', () {
      final s = LockState(const AppLockSettings(enabled: true));
      for (var i = 0; i < 4; i++) {
        expect(s.wrongPin(t0), isNull);
      }
      expect(s.wrongPin(t0), t0.add(const Duration(seconds: 30)));
      expect(s.blockedFor(t0.add(const Duration(seconds: 10))), const Duration(seconds: 20));
      expect(s.blockedFor(t0.add(const Duration(seconds: 30))), isNull);
      expect(s.wrongPin(t0), t0.add(const Duration(seconds: 60)));
      s.unlocked(t0);
      expect(s.blockedFor(t0), isNull);
    });
  });
}
