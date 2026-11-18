import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/core/notifications/notification_gateway.dart';
import 'package:fitbuddy/core/platform/alarm_capabilities.dart';
import 'package:fitbuddy/core/database/private_database.dart';
import 'package:fitbuddy/core/platform/location_tracker.dart';
import 'package:fitbuddy/core/platform/privacy_platform.dart';
import 'package:fitbuddy/core/platform/sound_library.dart';
import 'package:fitbuddy/core/platform/step_counter.dart';
import 'package:fitbuddy/core/platform/photo_picker.dart';
import 'package:fitbuddy/core/platform/time_zone_source.dart';
import 'package:fitbuddy/core/utils/clock.dart';
import 'package:fitbuddy/core/utils/id_generator.dart';
import 'package:fitbuddy/core/platform/push_messaging.dart';
import 'package:fitbuddy/core/sync/push_registry.dart';
import 'package:fitbuddy/features/nutrition/domain/meal_photos.dart';

AppDatabase memoryDatabase() {
  // Each test opens its own in-memory database; that is intended.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// A clock the test moves by hand.
class MutableClock {
  MutableClock(this.now);
  DateTime now;
  Clock get clock => Clock(() => now);
}

class SequentialIds implements IdGenerator {
  int _next = 1;
  @override
  String newId() => 'id-${_next++}';
}

class FixedTimeZone implements TimeZoneSource {
  const FixedTimeZone([this.id = 'Asia/Kolkata']);
  final String id;
  @override
  Future<String> currentTimeZoneId() async => id;
}

Future<List<({String table, String id})>> outboxEntries(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT entity_table, entity_id FROM sync_outbox ORDER BY seq')
      .get();
  return [
    for (final row in rows)
      (table: row.read<String>('entity_table'), id: row.read<String>('entity_id')),
  ];
}

/// Meal photos kept in memory.
class MemoryPhotoStore implements MealPhotoStore {
  final Map<String, List<int>> photos = {};

  @override
  Future<Result<void>> attach(String mealId, List<int> imageBytes) async {
    photos[mealId] = imageBytes;
    return const Ok(null);
  }

  @override
  Future<List<int>?> read(String mealId) async => photos[mealId];

  @override
  Future<Result<void>> remove(String mealId) async {
    photos.remove(mealId);
    return const Ok(null);
  }
}

/// A picker that returns [next] (null means the user cancelled).
class FakePhotoPicker implements PhotoPicker {
  List<int>? next;
  PhotoSource? lastSource;

  @override
  Future<List<int>?> pick(PhotoSource source) async {
    lastSource = source;
    return next;
  }
}

/// Records what would be sent to Android.
class FakeNotificationGateway implements NotificationGateway {
  final Map<int, NotificationRequest> pending = {};
  final List<NotificationRequest> shown = [];
  bool allowed = true;
  bool exactAllowed = true;
  bool grantOnRequest = true;
  int requests = 0;

  @override
  Future<void> schedule(NotificationRequest request) async => pending[request.id] = request;
  @override
  Future<void> show(NotificationRequest request) async => shown.add(request);
  @override
  Future<void> cancel(int id) async => pending.remove(id);
  @override
  Future<bool> notificationsAllowed() async => allowed;
  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) allowed = true;
    return allowed;
  }

  @override
  Future<bool> canScheduleExact() async => exactAllowed;
}

class FakeAlarmCapabilities implements AlarmCapabilities {
  bool exact = true;
  bool batteryExempt = false;
  List<String> disabled = const [];
  String? pendingEvent;
  final List<String> opened = [];

  @override
  Future<bool> canScheduleExactAlarms() async => exact;
  @override
  Future<void> openExactAlarmSettings() async => opened.add('exact');
  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryExempt;
  @override
  Future<void> openBatterySettings() async => opened.add('battery');
  @override
  Future<List<String>> disabledChannels() async => disabled;
  @override
  Future<void> openChannelSettings(String channelId) async => opened.add('channel:$channelId');
  @override
  Future<void> openNotificationSettings() async => opened.add('notifications');
  @override
  Future<void> playTestSound(String channelId) async => opened.add('sound:$channelId');
  @override
  Future<void> testVibration() async => opened.add('vibrate');
  @override
  Future<String?> takePendingSystemEvent() async {
    final e = pendingEvent;
    pendingEvent = null;
    return e;
  }
}

class FakeSoundLibrary implements SoundLibrary {
  List<SoundOption> sounds = const [
    (title: 'Chime', uri: 'content://media/internal/audio/media/11'),
    (title: 'Bell', uri: 'content://media/internal/audio/media/12'),
  ];
  final List<String> played = [];
  String? importResult = 'content://com.mysticstack.fitbuddy.sounds/sounds/my_tone.mp3';

  @override
  Future<List<SoundOption>> systemSounds() async => sounds;
  @override
  Future<String?> pickSound() async => importResult;
  @override
  Future<void> play(String uri) async => played.add(uri);
  @override
  Future<void> stop() async {}
}

class FakeStepCounter implements StepCounter {
  bool sensor = true;
  bool permission = true;
  bool grant = true;
  bool continuous = false;
  int snapshotsScheduled = 0;
  final List<BufferedStep> buffer = [];

  @override
  Future<bool> hasSensor() async => sensor;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async {
    permission = grant;
    return grant;
  }

  @override
  Future<BufferedStep?> readNow() async => null;
  @override
  Future<List<BufferedStep>> pending() async => [...buffer];
  @override
  Future<void> acknowledge(int maxId) async => buffer.removeWhere((b) => b.id <= maxId);
  @override
  Future<void> setContinuous(bool enabled) async => continuous = enabled;
  @override
  Future<bool> isContinuous() async => continuous;
  @override
  Future<void> scheduleSnapshots() async => snapshotsScheduled++;
}

class FakeLocationTracker implements LocationTracker {
  LocationAccess current = LocationAccess.granted;
  LocationAccess onRequest = LocationAccess.granted;
  // Closed with the test process; a fake.
  // ignore: close_sinks
  final StreamController<LocationFix> fixes = StreamController.broadcast();
  int settingsOpened = 0;

  @override
  Future<LocationAccess> access() async => current;
  @override
  Future<LocationAccess> request() async => current = onRequest;
  @override
  Stream<LocationFix> track({required String title, required String text}) => fixes.stream;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeSecureWindow implements SecureWindow {
  bool secure = false;
  @override
  Future<void> set({required bool secure}) async => this.secure = secure;
}

class FakeBiometrics implements Biometrics {
  bool isAvailable = true;
  bool succeed = true;
  int prompts = 0;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

class FakeUsageReader implements UsageReader {
  bool access = true;
  int settingsOpened = 0;
  List<AppUsage> today = const [];
  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<void> openAccessSettings() async => settingsOpened++;
  @override
  Future<List<AppUsage>> usage(DateTime start, DateTime end) async => today;
}

PrivateDatabase memoryPrivateDatabase() => PrivateDatabase(NativeDatabase.memory());

class FakePushMessaging implements PushMessaging {
  bool isAvailable = false;
  String? currentToken = 'token-1';
  int deleted = 0;
  // Live for the whole test.
  // ignore: close_sinks
  final StreamController<String> refreshes = StreamController<String>.broadcast();
  // ignore: close_sinks
  final StreamController<PushMessage> messages = StreamController<PushMessage>.broadcast();
  // ignore: close_sinks
  final StreamController<PushMessage> taps = StreamController<PushMessage>.broadcast();
  @override
  bool get available => isAvailable;
  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get tokenRefresh => refreshes.stream;
  @override
  Stream<PushMessage> get foreground => messages.stream;
  @override
  Stream<PushMessage> get opened => taps.stream;
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Future<void> deleteToken() async {
    deleted++;
    currentToken = null;
  }
}

class FakePushRegistry implements PushRegistry {
  final Map<String, PushPreferences> registered = {};
  final List<String> revoked = [];
  @override
  Future<void> register(String token, PushPreferences prefs, {required String appVersion}) async =>
      registered[token] = prefs;
  @override
  Future<void> revoke(String token) async => revoked.add(token);
}
