import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_engine.dart';
import '../core/sync/sync_remote.dart';
import '../features/auth/application/session_controller.dart';
import 'providers.dart';
import 'push_controller.dart' show appVersionProvider;

/// The cloud side of sync. Null when the app has no backend configured.
final syncRemoteProvider = Provider<SyncRemote?>((ref) => null);

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final remote = ref.watch(syncRemoteProvider);
  if (remote == null) return null;
  return SyncEngine(
    db: ref.watch(appDatabaseProvider),
    remote: remote,
    clock: ref.watch(clockProvider),
  );
});

/// Changes waiting to be uploaded.
final pendingSyncProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .customSelect('SELECT count(*) AS n FROM sync_outbox', readsFrom: {db.syncOutbox})
      .watchSingle()
      .map((r) => r.read<int>('n'));
});

enum SyncPhase { off, idle, syncing, restoring, problem, signedOut }

final class SyncStatus {
  const SyncStatus({required this.phase, this.lastSyncedAt, this.errorCode, this.failed = 0});
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? errorCode;
  final int failed;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? errorCode, int? failed}) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        errorCode: errorCode,
        failed: failed ?? 0,
      );
}

/// Runs sync on start, on return to the app, when the network comes back,
/// and on request; restores a returning user's records at first sign-in
/// (03-database.md §6.3).
class SyncController extends Notifier<SyncStatus> {
  static const lastSyncKey = 'sync_last_success';
  static const deviceIdKey = 'sync_device_id';
  Future<void>? _running;

  @override
  SyncStatus build() {
    final engine = ref.watch(syncEngineProvider);
    if (engine == null) return const SyncStatus(phase: SyncPhase.off);
    ref.listen(onlineProvider, (prev, next) {
      if (next.value == true && prev?.value != true) unawaited(syncNow());
    });
    ref.listen(sessionControllerProvider, (prev, next) {
      if (next.active && !(prev?.active ?? false)) unawaited(restoreIfEmpty());
    });
    unawaited(_loadLast());
    final active = ref.read(sessionControllerProvider).active;
    return SyncStatus(phase: active ? SyncPhase.idle : SyncPhase.signedOut);
  }

  Future<void> _loadLast() async {
    final v = await ref.read(settingsRepositoryProvider).read(lastSyncKey);
    if (v is String && state.lastSyncedAt == null) {
      state = SyncStatus(
        phase: state.phase,
        lastSyncedAt: DateTime.tryParse(v),
        errorCode: state.errorCode,
      );
    }
  }

  /// First sign-in on this phone: pull everything before onboarding decides
  /// whether this is a new user.
  Future<void> restoreIfEmpty() async {
    final engine = ref.read(syncEngineProvider);
    final account = ref.read(sessionControllerProvider).account;
    if (engine == null || account == null) return;
    final db = ref.read(appDatabaseProvider);
    final hasProfile = await db
        .customSelect(
          'SELECT 1 FROM profiles WHERE id = ?',
          variables: [Variable.withString(account.id)],
        )
        .getSingleOrNull();
    if (hasProfile != null) return unawaited(syncNow());
    state = state.copyWith(phase: SyncPhase.restoring);
    await _run(() => engine.syncNow());
  }

  /// Push, pull, push. Calls while one is running share it.
  Future<void> syncNow() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    if (!ref.read(sessionControllerProvider).active) {
      state = state.copyWith(phase: SyncPhase.signedOut);
      return;
    }
    // Offline: wait; the network coming back starts a sync.
    final online = await ref
        .read(onlineProvider.future)
        .timeout(const Duration(seconds: 2), onTimeout: () => true)
        .catchError((Object _) => true);
    if (!online) return;
    // No sign-in (D2 revised): connect to, or create, the anonymous cloud user.
    if (!await ref.read(sessionControllerProvider.notifier).connectCloud()) {
      state = state.copyWith(phase: SyncPhase.signedOut);
      return;
    }
    if (state.phase != SyncPhase.restoring) state = state.copyWith(phase: SyncPhase.syncing);
    return _run(engine.syncNow);
  }

  Future<void> _run(Future<SyncResult> Function() work) {
    return _running ??= () async {
      try {
        final r = await work();
        if (r.authPaused) {
          state = state.copyWith(phase: SyncPhase.signedOut, errorCode: r.errorCode);
        } else if (r.failed > 0) {
          state = state.copyWith(
            phase: SyncPhase.problem,
            errorCode: r.errorCode,
            failed: r.failed,
          );
        } else {
          final now = ref.read(clockProvider).now();
          await ref
              .read(settingsRepositoryProvider)
              .write(lastSyncKey, now.toUtc().toIso8601String());
          state = state.copyWith(phase: SyncPhase.idle, lastSyncedAt: now);
          unawaited(_report(now));
        }
      } on Object {
        state = state.copyWith(phase: SyncPhase.problem, errorCode: 'unexpected');
      } finally {
        _running = null;
      }
    }();
  }

  /// This phone's id for `cloud_sync_metadata`, created once.
  Future<void> _report(DateTime at) async {
    final remote = ref.read(syncRemoteProvider);
    if (remote == null) return;
    final settings = ref.read(settingsRepositoryProvider);
    var id = await settings.read(SyncController.deviceIdKey);
    if (id is! String) {
      id = ref.read(idGeneratorProvider).newId();
      await settings.write(SyncController.deviceIdKey, id);
    }
    try {
      await remote.reportStatus(
        deviceId: id,
        syncedAt: at,
        schemaVersion: ref.read(appDatabaseProvider).schemaVersion,
        appVersion: ref.read(appVersionProvider),
      );
    } on Object {
      // Informational only; sent again after the next sync.
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
