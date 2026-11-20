import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../app/routine_actions.dart';
import '../../../app/routine_labels.dart';
import '../../../app/routine_providers.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import 'reminder_names.dart';

/// Reminders tab of Habits (approved design "Habits: reminders").
class ReminderList extends ConsumerWidget {
  const ReminderList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final all = ref.watch(remindersProvider);
    final list = all.value;
    final status = ref.watch(reminderStatusProvider).value;
    final quiet = ref.watch(quietHoursProvider).value;
    if (list == null) {
      return all.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading();
    }
    final hasAlarm = list.any((r) => r.alarm && r.enabled);
    return ListView(
      padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
      children: [
        if (status != null && !status.notifications && list.isNotEmpty) ...[
          FbNotice(
            l10n.notificationsOffNotice,
            isError: true,
            action: TextButton(onPressed: () => ensureNotificationPermission(context, ref), child: Text(l10n.allow)),
          ),
          const SizedBox(height: FbSpace.md),
        ] else if (status != null && !status.exact && hasAlarm) ...[
          FbNotice(
            l10n.exactOffNotice,
            action: TextButton(onPressed: () => context.push(Routes.notificationSettings), child: Text(l10n.review)),
          ),
          const SizedBox(height: FbSpace.md),
        ],
        FbListCard(
          children: [
            FbListRow(
              title: l10n.quietHours,
              subtitle: quiet == null || !quiet.enabled
                  ? l10n.quietHoursOff
                  : l10n.quietHoursOn(minuteLabel(context, quiet.start), minuteLabel(context, quiet.end)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.notificationSettings),
            ),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        if (list.isEmpty)
          FbEmptyHint(l10n.remindersEmpty, boxed: true)
        else
          FbListCard(
            children: [
              for (final r in list)
                FbListRow(
                  title: r.title,
                  subtitle: [
                    scheduleSummary(context, r.rule),
                    if (r.onlyIfIncomplete) l10n.ifNotDoneShort,
                    channelName(l10n, r.channel),
                  ].join(' · '),
                  onTap: () => context.push(Routes.editReminder(r.id)),
                  trailing: Switch(
                    value: r.enabled,
                    onChanged: (v) async {
                      if (v && !await ensureNotificationPermission(context, ref)) return;
                      await ref.read(reminderRepositoryProvider).setEnabled(r.id, enabled: v);
                      replanReminders(ref);
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: FbSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(Routes.notificationHistory),
            icon: const Icon(Icons.history_rounded),
            label: Text(l10n.notificationHistory),
          ),
        ),
      ],
    );
  }
}
