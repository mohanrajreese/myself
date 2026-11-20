import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/widgets/fb_states.dart';
import '../core/widgets/l10n.dart';
import '../features/activities/domain/activity.dart';
import '../features/activities/domain/activity_repository.dart';
import '../features/reminders/domain/reminder.dart';
import 'providers.dart';
import 'routine_providers.dart';

/// Logs one occurrence from a list or Home, then re-plans "if not done"
/// reminders. Returns whether it was saved.
Future<bool> quickLog(
  BuildContext context,
  WidgetRef ref,
  Activity activity, {
  int? slot,
  ActivityLogStatus status = ActivityLogStatus.completed,
  int? count,
}) async {
  final l10n = context.l10n;
  final result = await ref
      .read(activityRepositoryProvider)
      .addLog(
        activity.id,
        LogDraft(
          status: status,
          occurredAt: ref.read(clockProvider).now(),
          scheduledSlot: slot,
          countValue: count,
        ),
      );
  if (!context.mounted) return result.isOk;
  showFbSnackBar(context, result.isOk ? l10n.activityLogged(activity.name) : l10n.errSaveFailed);
  if (result.isOk) replanReminders(ref);
  return result.isOk;
}

/// "Remind me again in N minutes" for an activity shown on Home.
Future<void> snoozeActivity(
  BuildContext context,
  WidgetRef ref,
  Activity activity,
  int minutes,
) async {
  final l10n = context.l10n;
  final store = ref.read(notificationStateStoreProvider);
  final at = ref.read(clockProvider).now().add(Duration(minutes: minutes));
  final local = DateTime(
    at.year,
    at.month,
    at.day,
    at.hour,
    at.minute,
  ).toIso8601String().substring(0, 16);
  final channel = channelIdFor(NotificationChannelKey.routines.code);
  final record = await store.add(
    reminderId: 'activity:${activity.id}',
    occurrenceLocal: local,
    at: at,
    channelId: channel,
    exact: false,
    deferred: false,
  );
  await store.snooze(record.id, at);
  await ref
      .read(notificationGatewayProvider)
      .schedule(
        NotificationRequest(id: record.id, at: at, channelId: channel, title: activity.name),
      );
  if (context.mounted) showFbSnackBar(context, l10n.snoozedFor(minutes));
}

/// Asks for the notification permission in context, after a rationale
/// (rules: never at first launch). Returns whether notifications are allowed.
Future<bool> ensureNotificationPermission(BuildContext context, WidgetRef ref) async {
  final gateway = ref.read(notificationGatewayProvider);
  if (await gateway.notificationsAllowed()) return true;
  if (!context.mounted) return false;
  final l10n = context.l10n;
  final go = await showFbConfirm(
    context,
    title: l10n.notifRationaleTitle,
    message: l10n.notifRationaleBody,
    confirmLabel: l10n.allow,
    cancelLabel: l10n.notNow,
  );
  if (!go) return false;
  final granted = await gateway.requestPermission();
  ref.invalidate(reminderStatusProvider);
  if (!granted) unawaited(ref.read(alarmCapabilitiesProvider).openNotificationSettings());
  return granted;
}

/// Explains exact-alarm access and opens its settings page.
Future<void> askForExactAlarms(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final go = await showFbConfirm(
    context,
    title: l10n.exactRationaleTitle,
    message: l10n.exactRationaleBody,
    confirmLabel: l10n.openSettings,
    cancelLabel: l10n.notNow,
  );
  if (go) await ref.read(alarmCapabilitiesProvider).openExactAlarmSettings();
  ref.invalidate(reminderStatusProvider);
}
