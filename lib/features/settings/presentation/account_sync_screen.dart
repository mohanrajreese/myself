import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/push_controller.dart';
import '../../../app/sync_controller.dart';
import '../../../core/sync/push_registry.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

/// Account and sync status, what is backed up, push preferences (approved
/// design "Account and sync").
class AccountSyncScreen extends ConsumerWidget {
  const AccountSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncProvider).value ?? 0;
    final online = ref.watch(onlineProvider).value ?? true;
    final account = ref.watch(currentAccountProvider);
    final pushAvailable = ref.watch(pushControllerProvider);
    final prefs = ref.watch(pushPreferencesProvider).value ?? const PushPreferences();
    final today = ref.watch(todayProvider);
    final c = context.colors;

    String? last() {
      final t = status.lastSyncedAt?.toLocal();
      if (t == null) return null;
      return l10n.lastSynced('${context.dayLabel(LocalDate.fromDateTime(t), today: today)} ${context.time(t)}');
    }

    final (IconData icon, Color color, String headline, String? detail) = switch (status.phase) {
      SyncPhase.off => (Icons.cloud_off_outlined, c.textSecondary, l10n.syncOff, l10n.syncOffHelp),
      SyncPhase.signedOut => (Icons.login_rounded, c.textSecondary, l10n.syncSignedOut, l10n.syncSignedOutHelp),
      SyncPhase.restoring => (Icons.cloud_download_outlined, c.primary, l10n.syncRestoring, null),
      SyncPhase.syncing => (Icons.sync_rounded, c.primary, l10n.syncSyncing(pending), null),
      SyncPhase.problem => (
        Icons.error_outline_rounded,
        c.warning,
        l10n.syncProblem(status.failed),
        l10n.syncProblemHelp(status.errorCode ?? '-'),
      ),
      SyncPhase.idle when pending > 0 => (
        Icons.schedule_rounded,
        c.textSecondary,
        l10n.syncWaiting(pending),
        online ? last() : l10n.syncWaitingNetwork,
      ),
      SyncPhase.idle => (Icons.check_rounded, c.success, l10n.syncUpToDate, last()),
    };
    final busy = status.phase == SyncPhase.syncing || status.phase == SyncPhase.restoring;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountAndSync)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MergeSemantics(
                  child: Row(
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(width: FbSpace.sm),
                      Expanded(
                        child: Text(headline, style: context.text.bodyStrong.copyWith(color: color)),
                      ),
                    ],
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: FbSpace.xs),
                  Text(detail, style: context.text.bodySmall),
                ],
                if (account?.email != null) ...[
                  const SizedBox(height: FbSpace.xs),
                  Text(l10n.signedInAs(account!.email!), style: context.text.bodySmall),
                ],
                if (status.phase != SyncPhase.off && status.phase != SyncPhase.signedOut) ...[
                  const SizedBox(height: FbSpace.md),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => unawaited(ref.read(syncControllerProvider.notifier).syncNow()),
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(l10n.syncNow),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.whatIsBackedUp),
          const SizedBox(height: FbSpace.sm),
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.syncedList, style: context.text.body),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.neverLeavesList, style: context.text.body),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.pushNotifications),
          const SizedBox(height: FbSpace.sm),
          if (!pushAvailable)
            Text(l10n.pushNotSetUp, style: context.text.bodySmall)
          else
            FbCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  FbSwitchRow(
                    title: l10n.pushAccount,
                    subtitle: l10n.pushAccountHelp,
                    value: prefs.account,
                    onChanged: (v) =>
                        ref.read(pushControllerProvider.notifier).setPreferences(prefs.copyWith(account: v)),
                  ),
                  FbSwitchRow(
                    title: l10n.pushSyncProblems,
                    subtitle: l10n.pushSyncProblemsHelp,
                    value: prefs.syncProblems,
                    onChanged: (v) =>
                        ref.read(pushControllerProvider.notifier).setPreferences(prefs.copyWith(syncProblems: v)),
                  ),
                  FbSwitchRow(
                    title: l10n.pushBackup,
                    subtitle: l10n.pushBackupHelp,
                    value: prefs.backupStatus,
                    onChanged: (v) =>
                        ref.read(pushControllerProvider.notifier).setPreferences(prefs.copyWith(backupStatus: v)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.pushNote, style: context.text.caption),
        ],
      ),
    );
  }
}
