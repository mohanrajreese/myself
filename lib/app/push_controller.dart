import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/platform/push_messaging.dart';
import '../core/sync/push_registry.dart';
import '../features/reminders/domain/reminder.dart';
import '../features/auth/application/session_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'notification_setup.dart';
import 'providers.dart';
import 'routine_providers.dart';

final pushMessagingProvider = Provider<PushMessaging>((ref) => const DisabledPushMessaging());
final pushRegistryProvider = Provider<PushRegistry?>((ref) => null);

/// Push messages tapped while the app was in the background.
final pushOpenedProvider = StreamProvider<PushMessage>(
  (ref) => ref.watch(pushMessagingProvider).opened,
);

final appVersionProvider = Provider<String>((ref) => '0.6.0');

final pushPreferencesProvider = FutureProvider<PushPreferences>((ref) async {
  return PushPreferences.fromJson(
    await ref.watch(settingsRepositoryProvider).read(PushPreferences.key),
  );
});

/// Notification ids used for push messages; tapping one opens Account and sync.
const pushNotificationIds = {903, 904, 905};

/// Message types the server may send (03-database.md §5.5), each with fixed
/// generic text. Unknown types are ignored.
const pushTypes = {'account_security', 'sync_problem', 'backup_status'};

bool pushAllowed(String type, PushPreferences p) => switch (type) {
  'account_security' => p.account,
  'sync_problem' => p.syncProblems,
  'backup_status' => p.backupStatus,
  _ => false,
};

/// The text shown for a push message, from the type code alone.
NotificationRequest? pushNotification(PushMessage m, AppLocalizations l) {
  final (id, body) = switch (m.type) {
    'account_security' => (903, l.pushAccountBody),
    'sync_problem' => (904, l.pushSyncProblemBody),
    'backup_status' => (905, l.pushBackupBody),
    _ => (0, ''),
  };
  if (id == 0) return null;
  return NotificationRequest(
    id: id,
    channelId: channelIdFor(NotificationChannelKey.system.code),
    title: l.pushTitle,
    body: body,
    withActions: false,
  );
}

/// Token lifecycle, preferences and incoming messages (§5.15I).
class PushController extends Notifier<bool> {
  final _subs = <StreamSubscription<Object?>>[];
  String? _token;

  @override
  bool build() {
    ref.onDispose(() {
      for (final s in _subs) {
        unawaited(s.cancel());
      }
    });
    ref.listen(sessionControllerProvider, (prev, next) {
      if (next.active && !(prev?.active ?? false)) unawaited(start());
    });
    return ref.read(pushMessagingProvider).available;
  }

  PushMessaging get _m => ref.read(pushMessagingProvider);

  Future<void> start() async {
    if (!_m.available || !ref.read(sessionControllerProvider).active) return;
    if (_subs.isEmpty) {
      _subs
        ..add(_m.tokenRefresh.listen((t) => unawaited(_register(t))))
        ..add(_m.foreground.listen((m) => unawaited(_show(m))));
    }
    try {
      final t = await _m.token();
      if (t != null) await _register(t);
    } on Object {
      // No token yet (no network or Play services); retried on next start.
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    final registry = ref.read(pushRegistryProvider);
    if (registry == null) return;
    final prefs = await ref.read(pushPreferencesProvider.future);
    try {
      await registry.register(token, prefs, appVersion: ref.read(appVersionProvider));
    } on Object {
      // Retried on next start or token refresh.
    }
  }

  Future<void> _show(PushMessage m) async {
    final prefs = await ref.read(pushPreferencesProvider.future);
    if (!pushAllowed(m.type, prefs)) return;
    final request = pushNotification(m, deviceLocalizations());
    if (request != null) await ref.read(notificationGatewayProvider).show(request);
  }

  Future<void> setPreferences(PushPreferences p) async {
    await ref.read(settingsRepositoryProvider).write(PushPreferences.key, p.toJson());
    ref.invalidate(pushPreferencesProvider);
    final t = _token;
    if (t != null) await _register(t);
  }

  /// Before sign-out or account deletion: the server stops sending here.
  Future<void> stop() async {
    final t = _token ?? (_m.available ? await _m.token().catchError((Object _) => null) : null);
    if (t == null) return;
    try {
      await ref.read(pushRegistryProvider)?.revoke(t);
      await _m.deleteToken();
    } on Object {
      // The server marks the token revoked when FCM reports it unregistered.
    }
    _token = null;
  }
}

final pushControllerProvider = NotifierProvider<PushController, bool>(PushController.new);
