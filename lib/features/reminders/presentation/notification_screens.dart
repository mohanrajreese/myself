import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/reminder_service.dart';
import '../../../app/routine_actions.dart';
import '../../../app/routine_labels.dart';
import '../../../app/routine_providers.dart';
import '../../../core/notifications/local_notification_gateway.dart';
import '../../../core/notifications/notification_state_store.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../activities/domain/activity.dart';
import '../domain/reminder.dart';
import 'reminder_names.dart';

/// Settings → Notifications and reminders (approved design). Shows what
/// Android allows and says honestly what cannot be guaranteed (§5.15J).
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check after returning from a system settings page.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.invalidate(reminderStatusProvider);
        replanReminders(ref);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _saveQuiet(QuietHoursSetting value) async {
    await ref.read(reminderServiceProvider).saveQuietHours(value);
    ref.invalidate(quietHoursProvider);
  }

  Future<int?> _pickTime(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(reminderStatusProvider);
    final quiet = ref.watch(quietHoursProvider).value ?? const QuietHoursSetting();
    final caps = ref.read(alarmCapabilitiesProvider);
    final s = status.value;
    Widget state(bool ok) => SlotBadgeText(ok: ok);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSectionTitle(l10n.statusTitle),
          const SizedBox(height: FbSpace.sm),
          if (s == null)
            const FbLoading()
          else
            FbListCard(
              children: [
                FbListRow(
                  title: l10n.notificationsRow,
                  subtitle: l10n.notificationsRowHelp,
                  leading: state(s.notifications),
                  trailing: s.notifications
                      ? null
                      : OutlinedButton(
                          onPressed: () => ensureNotificationPermission(context, ref),
                          child: Text(l10n.allow),
                        ),
                ),
                FbListRow(
                  title: l10n.exactAlarmsRow,
                  subtitle: s.exact ? l10n.exactAlarmsOn : l10n.exactAlarmsOff,
                  leading: state(s.exact),
                  trailing: s.exact
                      ? null
                      : OutlinedButton(onPressed: () => askForExactAlarms(context, ref), child: Text(l10n.allow)),
                ),
                FbListRow(
                  title: l10n.batteryRow,
                  subtitle: s.battery ? l10n.batteryOn : l10n.batteryOff,
                  leading: state(s.battery),
                  trailing: s.battery
                      ? null
                      : OutlinedButton(onPressed: caps.openBatterySettings, child: Text(l10n.open)),
                ),
                FbListRow(title: l10n.rebootRow, subtitle: l10n.rebootRowHelp, leading: state(true)),
              ],
            ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.quietHours),
          const SizedBox(height: FbSpace.sm),
          FbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                FbSwitchRow(
                  title: l10n.quietHours,
                  subtitle: l10n.quietHoursHelp,
                  value: quiet.enabled,
                  onChanged: (v) => _saveQuiet(QuietHoursSetting(enabled: v, start: quiet.start, end: quiet.end)),
                ),
                if (quiet.enabled) ...[
                  FbListRow(
                    title: l10n.fromLabel,
                    subtitle: minuteLabel(context, quiet.start),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final m = await _pickTime(quiet.start);
                      if (m != null) {
                        await _saveQuiet(QuietHoursSetting(enabled: true, start: m, end: quiet.end));
                      }
                    },
                  ),
                  FbListRow(
                    title: l10n.untilLabel,
                    subtitle: minuteLabel(context, quiet.end),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final m = await _pickTime(quiet.end);
                      if (m != null) {
                        await _saveQuiet(QuietHoursSetting(enabled: true, start: quiet.start, end: m));
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FbSpace.xs),
          Text(l10n.quietHoursPerReminder, style: context.text.caption),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.channelsTitle),
          const SizedBox(height: FbSpace.sm),
          FbListCard(
            children: [
              for (final c in NotificationChannelKey.values)
                FbListRow(
                  title: channelName(l10n, c),
                  subtitle: s != null && s.disabledChannels.contains(channelIdFor(c.code))
                      ? l10n.channelOff
                      : l10n.channelOn,
                  onTap: () => caps.openChannelSettings(channelIdFor(c.code)),
                  trailing: TextButton(
                    onPressed: () => caps.playTestSound(channelIdFor(c.code)),
                    child: Text(l10n.testAction, semanticsLabel: l10n.testSoundOf(channelName(l10n, c))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FbSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: caps.testVibration,
              icon: const Icon(Icons.vibration_rounded),
              label: Text(l10n.testVibration),
            ),
          ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.limitsNote, style: context.text.caption),
        ],
      ),
    );
  }
}

/// Icon plus word for an allowed / off state.
class SlotBadgeText extends StatelessWidget {
  const SlotBadgeText({required this.ok, super.key});
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: ok ? context.l10n.allowed : context.l10n.off,
      excludeSemantics: true,
      child: Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ok ? c.success : c.warning),
    );
  }
}

/// Notification centre: the last 30 days on this phone (approved design).
class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final history = ref.watch(notificationHistoryProvider);
    final reminders = {for (final r in ref.watch(remindersProvider).value ?? const <Reminder>[]) r.id: r};
    final activities = {for (final a in ref.watch(activitiesProvider).value ?? const <Activity>[]) a.id: a};
    final today = ref.watch(todayProvider);
    final list = history.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationHistory)),
      body: list == null
          ? (history.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading())
          : ListView(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
              children: [
                if (list.isEmpty)
                  FbEmptyHint(l10n.historyEmpty, boxed: true)
                else
                  FbListCard(
                    children: [
                      for (final r in list)
                        FbListRow(
                          title:
                              reminders[r.reminderId]?.title ??
                              (r.reminderId.startsWith('activity:')
                                  ? activities[r.reminderId.substring(9)]?.name ?? l10n.genericReminder
                                  : l10n.genericReminder),
                          subtitle:
                              '${context.dayLabel(LocalDate.fromDateTime(r.at.toLocal()), today: today)} '
                              '${context.time(r.at)} · ${_outcome(l10n, r)}',
                        ),
                    ],
                  ),
                const SizedBox(height: FbSpace.md),
                Text(l10n.historyNote, style: context.text.caption),
              ],
            ),
    );
  }

  static String _outcome(AppLocalizations l10n, NotificationRecord r) {
    final base = switch (r.status) {
      NotificationStatus.completed => l10n.outcomeCompleted,
      NotificationStatus.skipped => l10n.outcomeSkipped,
      NotificationStatus.snoozed => l10n.outcomeSnoozed(r.snoozeCount),
      NotificationStatus.dismissed => l10n.outcomeDismissed,
      NotificationStatus.expired => l10n.outcomeShown,
      _ => l10n.outcomeShown,
    };
    return [base, if (r.deferred) l10n.outcomeDeferred, if (!r.exact) l10n.outcomeInexact].join(' · ');
  }
}
