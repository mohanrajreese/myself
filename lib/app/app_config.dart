/// Build-time configuration, supplied with
/// `--dart-define-from-file=env/<flavour>.json`. None of these are secrets:
/// the publishable key and client ID are safe to ship in the app.
final class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
    this.appName = 'Praxis',
    this.firebaseApiKey = '',
    this.firebaseAppId = '',
    this.firebaseProjectId = '',
    this.firebaseSenderId = '',
  });

  static const fromEnvironment = AppConfig(
    appName: String.fromEnvironment('APP_NAME', defaultValue: 'Praxis'),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    firebaseApiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    firebaseAppId: String.fromEnvironment('FIREBASE_APP_ID'),
    firebaseProjectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    firebaseSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
  );

  final String appName;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  /// Firebase client identifiers for push (not secrets; FCM sending needs
  /// the server's service account, which never ships in the app).
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseProjectId;
  final String firebaseSenderId;

  bool get hasPush =>
      hasBackend &&
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseSenderId.isNotEmpty;

  /// False for a build made without an env file; sign-in then explains that
  /// it is not set up instead of failing obscurely.
  bool get hasBackend =>
      supabaseUrl.startsWith('https://') &&
      !supabaseUrl.contains('YOUR-PROJECT') &&
      supabasePublishableKey.isNotEmpty &&
      googleWebClientId.endsWith('.apps.googleusercontent.com');
}
