import 'package:supabase_flutter/supabase_flutter.dart';

/// Which server messages the user wants (Settings → Account and sync).
final class PushPreferences {
  const PushPreferences({this.account = true, this.syncProblems = true, this.backupStatus = false});
  final bool account;
  final bool syncProblems;
  final bool backupStatus;

  static const key = 'push_preferences';

  Map<String, Object?> toJson() => {'account': account, 'sync_problems': syncProblems, 'backup_status': backupStatus};

  static PushPreferences fromJson(Object? j) => switch (j) {
    {'account': final bool a, 'sync_problems': final bool s, 'backup_status': final bool b} => PushPreferences(
      account: a,
      syncProblems: s,
      backupStatus: b,
    ),
    _ => const PushPreferences(),
  };

  PushPreferences copyWith({bool? account, bool? syncProblems, bool? backupStatus}) => PushPreferences(
    account: account ?? this.account,
    syncProblems: syncProblems ?? this.syncProblems,
    backupStatus: backupStatus ?? this.backupStatus,
  );
}

/// The device's FCM token and preferences in `device_notification_tokens`.
abstract interface class PushRegistry {
  Future<void> register(String token, PushPreferences prefs, {required String appVersion});
  Future<void> revoke(String token);
}

final class SupabasePushRegistry implements PushRegistry {
  SupabasePushRegistry(this._client, this._clock);
  final SupabaseClient _client;
  final DateTime Function() _clock;

  @override
  Future<void> register(String token, PushPreferences prefs, {required String appVersion}) async {
    if (_client.auth.currentSession == null) return;
    await _client.from('device_notification_tokens').upsert({
      'fcm_token': token,
      'device_label': 'Android',
      'app_version': appVersion,
      'last_seen_at': _clock().toUtc().toIso8601String(),
      'revoked_at': null,
      'preferences': prefs.toJson(),
    }, onConflict: 'fcm_token');
  }

  @override
  Future<void> revoke(String token) async {
    if (_client.auth.currentSession == null) return;
    // Removed rather than marked, so another account may use this phone later.
    await _client.from('device_notification_tokens').delete().eq('fcm_token', token);
  }
}
