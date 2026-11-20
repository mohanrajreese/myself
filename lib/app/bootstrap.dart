import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database/app_database.dart';
import '../core/database/encrypted_connection.dart';
import '../core/database/private_database.dart';
import '../core/database/settings_repository.dart';
import '../core/encryption/database_key_manager.dart';
import '../core/encryption/file_cipher.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/platform/alarm_capabilities.dart';
import '../core/platform/device_time_zone.dart';
import '../core/utils/id_generator.dart';
import '../core/encryption/secure_secret_store.dart';
import '../core/utils/clock.dart';
import '../core/utils/logger.dart';
import '../features/auth/application/session.dart';
import '../features/food_database/data/catalogue_importer.dart';
import '../features/nutrition/data/drift_meal_repository.dart';
import '../features/money/data/drift_money_repository.dart';
import '../features/money/data/encrypted_receipt_store.dart';
import '../features/nutrition/data/encrypted_meal_photo_store.dart';
import 'money_providers.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/supabase_google_auth_repository.dart';
import '../features/auth/data/unconfigured_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/settings/application/theme_mode_controller.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app.dart';
import 'app_config.dart';
import 'background.dart';
import 'sync_controller.dart';
import 'account_actions.dart';
import 'push_controller.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/platform/push_messaging.dart';
import '../core/sync/push_registry.dart';
import '../core/sync/supabase_sync_remote.dart';
import 'notification_setup.dart';
import 'private_providers.dart';
import 'private_reminder_source.dart';
import 'providers.dart';
import 'routine_providers.dart';
import 'tracking_providers.dart';

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

  final database = AppDatabase(openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: hexKey));
  final settings = SettingsRepository(database, clock: systemClock);

  // Meal photos: encrypted files in app-private storage (never synced).
  final fileKey = (await DatabaseKeyManager(secrets).keyFor(DatabaseId.files)).valueOrNull;
  final photoStore = fileKey == null
      ? null
      : EncryptedMealPhotoStore(
          db: database,
          directory: Directory('${(await getApplicationSupportDirectory()).path}/meal_photos'),
          cipher: FileCipher([
            for (var i = 0; i < fileKey.length; i += 2) int.parse(fileKey.substring(i, i + 2), radix: 16),
          ]),
          meals: DriftMealRepository(
            database,
            clock: systemClock,
            ids: const UuidV7Generator(),
            timeZone: DeviceTimeZone(),
          ),
          clock: systemClock,
          ids: const UuidV7Generator(),
        );
  final receiptStore = fileKey == null
      ? null
      : EncryptedReceiptStore(
          db: database,
          directory: Directory('${(await getApplicationSupportDirectory()).path}/receipts'),
          cipher: FileCipher([
            for (var i = 0; i < fileKey.length; i += 2) int.parse(fileKey.substring(i, i + 2), radix: 16),
          ]),
          money: DriftMoneyRepository(
            database,
            clock: systemClock,
            ids: const UuidV7Generator(),
            timeZone: DeviceTimeZone(),
          ),
          clock: systemClock,
          ids: const UuidV7Generator(),
        );
  LicenseRegistry.addLicense(() async* {
    for (final font in const ['Inter', 'PlusJakartaSans']) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  // Bundled food catalogues; each is imported once per version, in the background.
  final importer = CatalogueImporter(database, settings);
  unawaited(() async {
    for (final asset in const ['assets/catalogue/usda_sr_legacy.json', 'assets/catalogue/indb.json']) {
      try {
        await importer.importIfNeeded(await rootBundle.loadString(asset));
      } on Object catch (error) {
        logger.failure('catalogue_import_failed', error);
      }
    }
  }());
  // Private database (§7.1): its own key; never synced.
  final privateKey = (await DatabaseKeyManager(secrets).keyFor(DatabaseId.private)).valueOrNull;
  final privateDb = privateKey == null
      ? null
      : PrivateDatabase(openEncryptedDatabase(name: PrivateDatabase.databaseName, hexKey: privateKey));
  final supportDir = await getApplicationSupportDirectory();
  final fileCipher = fileKey == null
      ? null
      : FileCipher([for (var i = 0; i < fileKey.length; i += 2) int.parse(fileKey.substring(i, i + 2), radix: 16)]);
  final l10n = deviceLocalizations();

  // Reminders: channels, taps, and the six-hourly top-up (05 §A5).
  // Lives as long as the app; never closed.
  // ignore: close_sinks
  final taps = StreamController<NotificationTap>.broadcast();
  NotificationGateway gateway = const DisabledNotificationGateway();
  NotificationTap? launchTap;
  try {
    final local = await createNotificationGateway(onTap: taps.add, onBackgroundTap: notificationTapBackground);
    launchTap = await local.launchTap();
    gateway = local;
    await DeviceAlarmCapabilities().takePendingSystemEvent();
  } on Object catch (error) {
    logger.failure('notifications_init_failed', error);
  }
  unawaited(registerBackgroundJobs().catchError((Object error) => logger.failure('reminder_top_up_failed', error)));
  final session = await loadSession(settings);
  final themeMode = themeModeFromSetting(await settings.read(themeModeSettingKey));
  final (auth, supabaseClient) = await _createAuth(AppConfig.fromEnvironment, secrets, logger);
  PushMessaging push = const DisabledPushMessaging();
  if (AppConfig.fromEnvironment.hasPush && supabaseClient != null) {
    try {
      push = await FirebasePushMessaging.create(firebaseOptions(AppConfig.fromEnvironment));
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    } on Object catch (error) {
      logger.failure('push_init_failed', error);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authRepositoryProvider.overrideWithValue(auth),
        if (supabaseClient != null) ...[
          syncRemoteProvider.overrideWithValue(SupabaseSyncRemote(supabaseClient)),
          pushRegistryProvider.overrideWithValue(SupabasePushRegistry(supabaseClient, () => systemClock.now())),
        ],
        pushMessagingProvider.overrideWithValue(push),
        localDataEraserProvider.overrideWith(
          (ref) =>
              () => erasePhoneData(ref),
        ),
        initialSessionProvider.overrideWithValue(session),
        initialThemeModeProvider.overrideWithValue(themeMode),
        onlineProvider.overrideWith((ref) => _online()),
        if (photoStore != null) mealPhotoStoreProvider.overrideWithValue(photoStore),
        if (receiptStore != null) receiptStoreProvider.overrideWithValue(receiptStore),
        notificationGatewayProvider.overrideWithValue(gateway),
        notificationTapsProvider.overrideWith((ref) => taps.stream),
        launchTapProvider.overrideWithValue(launchTap),
        if (privateDb != null) ...[
          privateDatabaseProvider.overrideWithValue(privateDb),
          privateReminderSourceProvider.overrideWith(
            (ref) => DevicePrivateReminderSource(
              medications: ref.watch(medicationRepositoryProvider),
              sensitive: ref.watch(sensitiveReminderRepositoryProvider),
              genericTitle: l10n.genericReminderTitle,
            ),
          ),
        ],
        progressPhotoDirProvider.overrideWithValue(Directory('${supportDir.path}/progress_photos')),
        fileCipherProvider.overrideWithValue(fileCipher),
        screenTimeAlertTitleProvider.overrideWithValue(l10n.genericReminderTitle),
        signOutActionProvider.overrideWith(
          (ref) => () async {
            await ref.read(pushControllerProvider.notifier).stop();
            await ref.read(sessionControllerProvider.notifier).signOut();
          },
        ),
      ],
      child: const PraxisApp(),
    ),
  );
}

Future<(AuthRepository, SupabaseClient?)> _createAuth(
  AppConfig config,
  SecureSecretStore secrets,
  AppLogger logger,
) async {
  if (!config.hasBackend) return (const UnconfiguredAuthRepository(), null);
  try {
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage(secrets)),
    );
    return (
      SupabaseGoogleAuthRepository(client: supabase.client, googleWebClientId: config.googleWebClientId),
      supabase.client,
    );
  } on Object catch (error) {
    logger.failure('backend_init_failed', error);
    return (const UnconfiguredAuthRepository(), null);
  }
}

Stream<bool> _online() async* {
  final connectivity = Connectivity();
  bool connected(List<ConnectivityResult> results) => results.any((result) => result != ConnectivityResult.none);
  yield connected(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(connected);
}
