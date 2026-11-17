import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database/app_database.dart';
import '../core/database/encrypted_connection.dart';
import '../core/database/settings_repository.dart';
import '../core/encryption/database_key_manager.dart';
import '../core/encryption/secure_secret_store.dart';
import '../core/utils/clock.dart';
import '../core/utils/logger.dart';
import '../features/auth/application/session.dart';
import '../features/food_database/data/catalogue_importer.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/supabase_google_auth_repository.dart';
import '../features/auth/data/unconfigured_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/settings/application/theme_mode_controller.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app.dart';
import 'app_config.dart';
import 'providers.dart';

/// Opens encrypted storage, restores the session and starts the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger(sink: kDebugMode ? debugPrint : (_) {});
  const secrets = SecureSecretStore();

  final key = await DatabaseKeyManager(secrets).keyFor(DatabaseId.app);
  final hexKey = key.valueOrNull;
  if (hexKey == null) {
    logger.event(key.failureOrNull!.code);
    runApp(const StartupErrorApp(onRetry: bootstrap));
    return;
  }

  final database = AppDatabase(
    openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: hexKey),
  );
  final settings = SettingsRepository(database, clock: systemClock);
  // Bundled food catalogues; each is imported once per version, in the background.
  final importer = CatalogueImporter(database, settings);
  unawaited(() async {
    for (final asset in const [
      'assets/catalogue/usda_sr_legacy.json',
      'assets/catalogue/indb.json',
    ]) {
      try {
        await importer.importIfNeeded(await rootBundle.loadString(asset));
      } on Object catch (error) {
        logger.failure('catalogue_import_failed', error);
      }
    }
  }());
  final session = await loadSession(settings);
  final themeMode = themeModeFromSetting(await settings.read(themeModeSettingKey));
  final auth = await _createAuth(AppConfig.fromEnvironment, secrets, logger);

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authRepositoryProvider.overrideWithValue(auth),
        initialSessionProvider.overrideWithValue(session),
        initialThemeModeProvider.overrideWithValue(themeMode),
        onlineProvider.overrideWith((ref) => _online()),
        signOutActionProvider.overrideWith(
          (ref) =>
              () => ref.read(sessionControllerProvider.notifier).signOut(),
        ),
      ],
      child: const FitBuddyApp(),
    ),
  );
}

Future<AuthRepository> _createAuth(
  AppConfig config,
  SecureSecretStore secrets,
  AppLogger logger,
) async {
  if (!config.hasBackend) return const UnconfiguredAuthRepository();
  try {
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage(secrets)),
    );
    return SupabaseGoogleAuthRepository(
      client: supabase.client,
      googleWebClientId: config.googleWebClientId,
    );
  } on Object catch (error) {
    logger.failure('backend_init_failed', error);
    return const UnconfiguredAuthRepository();
  }
}

Stream<bool> _online() async* {
  final connectivity = Connectivity();
  bool connected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
  yield connected(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(connected);
}
