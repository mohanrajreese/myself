import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/session_controller.dart';
import 'private_providers.dart';
import 'money_providers.dart';
import 'providers.dart';
import 'push_controller.dart';
import 'routine_providers.dart';
import 'sync_controller.dart';
import 'tracking_providers.dart';

/// Fixed notification ids outside the reminder store (timer, screen time,
/// push messages).
const _fixedNotificationIds = [900, 901, 902, 903, 904, 905];

/// Erases everything Praxis holds on this phone (§7.3, §11.4): scheduled
/// notifications, photos, the private database, the main database and the
/// app lock. Synced records in the cloud are untouched.
Future<void> erasePhoneData(Ref ref) async {
  final db = ref.read(appDatabaseProvider);
  final gateway = ref.read(notificationGatewayProvider);
  final pending = await db
      .customSelect(
        "SELECT notification_id AS id FROM local_notification_state WHERE status IN ('scheduled', 'snoozed')",
      )
      .get();
  for (final id in [for (final r in pending) r.read<int>('id'), ..._fixedNotificationIds]) {
    try {
      await gateway.cancel(id);
    } on Object {
      // Already gone.
    }
  }
  await ref.read(mealPhotoStoreProvider).removeAll();
  await ref.read(receiptStoreProvider).removeAll();
  try {
    final private = ref.read(privateRepositoryProvider);
    for (final p in await private.watchPhotos().first) {
      await private.deletePhoto(p.id);
    }
    final pdb = ref.read(privateDatabaseProvider);
    await pdb.transaction(() async {
      for (final t in pdb.allTables) {
        await pdb.delete(t).go();
      }
    });
  } on StateError {
    // No private database on this phone.
  }
  await db.eraseAllData();
  await ref.read(lockControllerProvider.notifier).turnOff();
}

enum DeleteAccountOutcome { deleted, offline, notConfigured, reauthFailed, failed }

/// Deletes the cloud account after the user signs in with Google again.
/// [erasePhone] also erases this phone; otherwise records stay here,
/// signed out, and nothing more is uploaded.
Future<DeleteAccountOutcome> deleteAccount(Ref ref, {required bool erasePhone}) async {
  final remote = ref.read(syncRemoteProvider);
  if (remote == null) return DeleteAccountOutcome.notConfigured;
  final online = await ref
      .read(onlineProvider.future)
      .timeout(const Duration(seconds: 2), onTimeout: () => true)
      .catchError((Object _) => true);
  if (!online) return DeleteAccountOutcome.offline;
  final session = ref.read(sessionControllerProvider.notifier);
  final current = ref.read(sessionControllerProvider).account;
  final again = await ref.read(authRepositoryProvider).signInWithGoogle();
  if (current == null || again.valueOrNull?.id != current.id) {
    return DeleteAccountOutcome.reauthFailed;
  }

  await ref.read(pushControllerProvider.notifier).stop();
  try {
    await remote.deleteAccount();
  } on Object {
    return DeleteAccountOutcome.failed;
  }
  final db = ref.read(appDatabaseProvider);
  if (erasePhone) {
    await erasePhoneData(ref);
  } else {
    // The account is gone: nothing left to upload to.
    await db.customUpdate('DELETE FROM sync_outbox', updates: {db.syncOutbox});
  }
  await session.forget();
  return DeleteAccountOutcome.deleted;
}

/// Erases this phone, then signs out. (For widgets, which hold a WidgetRef.)
final erasePhoneDataProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    // Read before the first await: providers rebuild as the data disappears.
    final session = ref.read(sessionControllerProvider.notifier);
    await erasePhoneData(ref);
    await session.forget();
  },
);

final deleteAccountProvider =
    Provider<Future<DeleteAccountOutcome> Function({required bool erasePhone})>(
      (ref) =>
          ({required bool erasePhone}) => deleteAccount(ref, erasePhone: erasePhone),
    );
