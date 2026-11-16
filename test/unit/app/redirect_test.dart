import 'package:fitbuddy/app/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String? go(String location, {bool active = true, SetupStatus setup = SetupStatus.complete}) =>
    resolveRedirect(sessionActive: active, setup: setup, location: location);

void main() {
  test('without a signed-in account every path leads to sign-in', () {
    for (final path in [Routes.home, Routes.settings, Routes.onboardingGoals, '/']) {
      expect(go(path, active: false), Routes.signIn, reason: path);
    }
    expect(go(Routes.signIn, active: false), isNull);
  });

  test('a signed-in account that has not been set up goes to onboarding', () {
    expect(go(Routes.signIn, setup: SetupStatus.needed), Routes.onboardingProfile);
    expect(go(Routes.home, setup: SetupStatus.needed), Routes.onboardingProfile);
    expect(go(Routes.onboardingSummary, setup: SetupStatus.needed), isNull);
  });

  test('a set-up account goes straight to Home and cannot re-enter onboarding', () {
    expect(go(Routes.signIn), Routes.home);
    expect(go('/'), Routes.home);
    expect(go(Routes.onboardingProfile), Routes.home);
    expect(go(Routes.home), isNull);
    expect(go(Routes.settingsGoals), isNull);
  });

  test('while the profile is loading the user waits on the loading screen', () {
    expect(go(Routes.home, setup: SetupStatus.unknown), Routes.loading);
    expect(go(Routes.loading, setup: SetupStatus.unknown), isNull);
    expect(go(Routes.loading), Routes.home);
  });
}
