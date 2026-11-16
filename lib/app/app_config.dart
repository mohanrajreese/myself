/// Build-time configuration, supplied with
/// `--dart-define-from-file=env/<flavour>.json`. None of these are secrets:
/// the publishable key and client ID are safe to ship in the app.
final class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
  });

  static const fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  /// False for a build made without an env file; sign-in then explains that
  /// it is not set up instead of failing obscurely.
  bool get hasBackend =>
      supabaseUrl.startsWith('https://') &&
      !supabaseUrl.contains('YOUR-PROJECT') &&
      supabasePublishableKey.isNotEmpty &&
      googleWebClientId.endsWith('.apps.googleusercontent.com');
}
