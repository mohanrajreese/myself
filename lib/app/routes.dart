/// Route paths and the rule that decides where the user may be.
library;

abstract final class Routes {
  static const loading = '/loading';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingGoals = '/onboarding/goals';
  static const onboardingDay = '/onboarding/day';
  static const onboardingPermissions = '/onboarding/permissions';
  static const onboardingSummary = '/onboarding/summary';
  static const home = '/home';
  static const fitness = '/fitness';
  static const nutrition = '/nutrition';
  static const health = '/health';
  static const habits = '/habits';
  static const insights = '/insights';
  static const addWeight = '/add-weight';
  static const settings = '/settings';
  static const settingsProfile = '/settings/profile';
  static const settingsGoals = '/settings/goals';
  static const settingsDay = '/settings/day';
  static const settingsHome = '/settings/home-layout';

  static const onboardingSteps = [
    onboardingProfile,
    onboardingGoals,
    onboardingDay,
    onboardingPermissions,
    onboardingSummary,
  ];
}

/// Whether the signed-in account has finished onboarding.
enum SetupStatus { unknown, needed, complete }

/// Returns the path to send the user to, or null to stay at [location].
///
/// The decision uses only what is stored on the device, so it works offline:
/// no account bound or signed out → sign-in; bound but not set up →
/// onboarding; otherwise the app.
String? resolveRedirect({
  required bool sessionActive,
  required SetupStatus setup,
  required String location,
}) {
  if (!sessionActive) return location == Routes.signIn ? null : Routes.signIn;

  final inOnboarding = location.startsWith(Routes.onboarding);
  return switch (setup) {
    SetupStatus.unknown => location == Routes.loading ? null : Routes.loading,
    SetupStatus.needed => inOnboarding ? null : Routes.onboardingProfile,
    SetupStatus.complete =>
      inOnboarding || location == Routes.signIn || location == Routes.loading || location == '/'
          ? Routes.home
          : null,
  };
}
