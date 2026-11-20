import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../l10n/generated/app_localizations.dart';

/// Channel names and descriptions in the user's language (§5.15H).
Map<String, ChannelLabels> channelLabels(AppLocalizations l) => {
  'alarms': (name: l.channelAlarms, description: l.channelAlarmsDesc),
  'routines': (name: l.channelRoutines, description: l.channelRoutinesDesc),
  'hydration': (name: l.channelHydration, description: l.channelHydrationDesc),
  'fitness': (name: l.channelFitness, description: l.channelFitnessDesc),
  'medication': (name: l.channelMedication, description: l.channelMedicationDesc),
  'sleep': (name: l.channelSleep, description: l.channelSleepDesc),
  'system': (name: l.channelSystem, description: l.channelSystemDesc),
};

AppLocalizations deviceLocalizations() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  return AppLocalizations.delegate.isSupported(locale)
      ? lookupAppLocalizations(locale)
      : lookupAppLocalizations(const Locale('en'));
}

/// A ready gateway: channels created and taps routed.
Future<LocalNotificationGateway> createNotificationGateway({
  required void Function(NotificationTap) onTap,
  required DidReceiveBackgroundNotificationResponseCallback onBackgroundTap,
}) async {
  final l = deviceLocalizations();
  final gateway = LocalNotificationGateway(
    actionLabels: (complete: l.actionComplete, snooze: l.actionSnooze, skip: l.actionSkip),
  );
  await gateway.initialize(channels: channelLabels(l), onTap: onTap, onBackgroundTap: onBackgroundTap);
  return gateway;
}
