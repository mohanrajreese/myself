/// Composition root: the one place that knows which implementation stands
/// behind each interface. Features depend on the interfaces exposed here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/database/settings_repository.dart';
import '../core/platform/device_time_zone.dart';
import '../core/platform/time_zone_source.dart';
import '../core/utils/clock.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/local_date.dart';
import '../features/auth/application/session.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/account.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/profile/data/drift_goals_repository.dart';
import '../features/profile/data/drift_profile_repository.dart';
import '../features/profile/domain/goals.dart';
import '../features/profile/domain/goals_repository.dart';
import '../features/profile/domain/profile.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/weight/data/drift_weight_repository.dart';
import '../features/weight/domain/weight_entry.dart';
import '../features/weight/domain/weight_repository.dart';

// Supplied at start-up (lib/app/bootstrap.dart) and by tests.
final appDatabaseProvider = Provider<AppDatabase>((ref) => throw StateError('not provided'));
final authRepositoryProvider = Provider<AuthRepository>((ref) => throw StateError('not provided'));
final initialSessionProvider = Provider<SessionState>((ref) => const SessionState());

/// The account this device is bound to, or null before the first sign-in.
final currentAccountProvider = Provider<Account?>(
  (ref) => ref.watch(sessionControllerProvider).account,
);

final clockProvider = Provider<Clock>((ref) => systemClock);
final idGeneratorProvider = Provider<IdGenerator>((ref) => const UuidV7Generator());
final timeZoneSourceProvider = Provider<TimeZoneSource>((ref) => DeviceTimeZone());

/// True while the device has a network connection.
final onlineProvider = StreamProvider<bool>((ref) => Stream.value(true));

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider), clock: ref.watch(clockProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => DriftProfileRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
  ),
);

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => DriftGoalsRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final weightRepositoryProvider = Provider<WeightRepository>(
  (ref) => DriftWeightRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
  ),
);

/// The user's local calendar day.
final todayProvider = Provider<LocalDate>(
  (ref) => LocalDate.fromDateTime(ref.watch(clockProvider).now()),
);

final currentDailyGoalsProvider = StreamProvider<DailyGoals?>(
  (ref) => ref.watch(goalsRepositoryProvider).watchCurrentDailyGoals(),
);

final currentNutritionGoalsProvider = StreamProvider<NutritionTargets?>(
  (ref) => ref.watch(goalsRepositoryProvider).watchCurrentNutritionGoals(),
);

final latestWeightProvider = StreamProvider<WeightEntry?>(
  (ref) => ref.watch(weightRepositoryProvider).watchLatest(),
);

final todayWeightEntriesProvider = StreamProvider<List<WeightEntry>>(
  (ref) => ref.watch(weightRepositoryProvider).watchOn(ref.watch(todayProvider)),
);

/// The signed-in account's profile; null until onboarding has saved one.
final profileProvider = StreamProvider.family<Profile?, String>(
  (ref, accountId) => ref.watch(profileRepositoryProvider).watch(accountId),
);

/// Rows saved on this phone that have not been uploaded yet.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .customSelect('SELECT count(*) AS n FROM sync_outbox', readsFrom: {db.syncOutbox})
      .watchSingle()
      .map((row) => row.read<int>('n'));
});
