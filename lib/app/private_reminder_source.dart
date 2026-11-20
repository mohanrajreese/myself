import 'dart:convert';

import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/scheduling/reminder_planner.dart';
import '../core/scheduling/schedule_rule.dart';
import '../core/utils/local_date.dart';
import '../features/medication/domain/medication.dart';
import '../features/private_space/domain/private_records.dart';
import 'reminder_service.dart';

/// Medication doses and private reminders, scheduled with a generic title
/// and secret lock-screen visibility (§3.4 rule 14, §7.3).
final class DevicePrivateReminderSource implements PrivateReminderSource {
  DevicePrivateReminderSource({
    required this.medications,
    required this.sensitive,
    required this.genericTitle,
  });

  final MedicationRepository medications;
  final SensitiveReminderRepository sensitive;
  @override
  final String genericTitle;

  @override
  Future<List<SchedulableReminder>> reminders() async => [
    for (final m in await medications.all())
      if (m.active && m.remind)
        SchedulableReminder(
          plan: PlannerReminder(id: 'med:${m.id}', rule: m.rule),
          channelId: channelIdFor('medication'),
          title: genericTitle,
          secret: true,
        ),
    for (final r in await sensitive.enabled())
      SchedulableReminder(
        plan: PlannerReminder(
          id: 'sr:${r.id}',
          rule: ScheduleRule.fromJson((jsonDecode(r.ruleJson) as Map).cast<String, Object?>()),
        ),
        channelId: channelIdFor(r.ownerType == 'medication' ? 'medication' : 'routines'),
        title: genericTitle,
        secret: true,
      ),
  ];

  @override
  Future<void> acted(String reminderId, String occurrenceLocal, {required bool completed}) async {
    if (!reminderId.startsWith('med:')) return;
    final parts = occurrenceLocal.split('T');
    final hm = parts.last.split(':');
    await medications.record(
      reminderId.substring(4),
      day: LocalDate.parse(parts.first),
      slot: int.parse(hm[0]) * 60 + int.parse(hm[1]),
      status: completed ? DoseStatus.taken : DoseStatus.skipped,
    );
  }
}
