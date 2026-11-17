import '../../../core/scheduling/reminder_planner.dart';
import '../../../core/widgets/l10n.dart';
import '../domain/reminder.dart';

String channelName(AppLocalizations l, NotificationChannelKey c) => switch (c) {
  NotificationChannelKey.alarms => l.channelAlarms,
  NotificationChannelKey.routines => l.channelRoutines,
  NotificationChannelKey.hydration => l.channelHydration,
  NotificationChannelKey.fitness => l.channelFitness,
  NotificationChannelKey.medication => l.channelMedication,
  NotificationChannelKey.sleep => l.channelSleep,
  NotificationChannelKey.system => l.channelSystem,
};

String reminderKindName(AppLocalizations l, ReminderKind k) => switch (k) {
  ReminderKind.custom => l.kindCustom,
  ReminderKind.activity => l.kindActivity,
  ReminderKind.water => l.kindWater,
  ReminderKind.workout => l.kindWorkout,
  ReminderKind.sleep => l.kindSleep,
  ReminderKind.posture => l.kindPosture,
};

String quietBehaviourName(AppLocalizations l, QuietBehaviour b) => switch (b) {
  QuietBehaviour.defer => l.quietDefer,
  QuietBehaviour.suppress => l.quietSuppress,
  QuietBehaviour.bypass => l.quietBypass,
};
