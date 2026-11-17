/// Buttons on a reminder notification. Android shows at most three (C9).
enum ReminderAction {
  complete('complete'),
  snooze('snooze'),
  skip('skip');

  const ReminderAction(this.code);
  final String code;
  static ReminderAction? fromCode(String? code) => values.where((a) => a.code == code).firstOrNull;
}

/// One notification to show now or at [at].
final class NotificationRequest {
  const NotificationRequest({
    required this.id,
    required this.channelId,
    required this.title,
    this.at,
    this.body,
    this.exact = false,
    this.withActions = true,
    this.secret = false,
    this.vibrate = true,
  });

  final int id;

  /// Null shows it now.
  final DateTime? at;
  final String channelId;
  final String title;
  final String? body;
  final bool exact;
  final bool withActions;

  /// Hidden on the lock screen (sensitive modules, §3.4 rule 14).
  final bool secret;
  final bool vibrate;
}

/// A tap on a notification or one of its buttons.
final class NotificationTap {
  const NotificationTap({required this.notificationId, this.action});
  final int notificationId;

  /// Null when the notification body was tapped.
  final ReminderAction? action;
}

/// Wraps the local notification plugin so scheduling logic can be tested.
abstract interface class NotificationGateway {
  Future<void> schedule(NotificationRequest request);
  Future<void> show(NotificationRequest request);
  Future<void> cancel(int id);

  /// Whether the user allows notifications (always true before Android 13
  /// unless switched off in system settings).
  Future<bool> notificationsAllowed();

  /// Shows the system prompt where Android has one; returns the result.
  Future<bool> requestPermission();

  /// Whether exact alarms may be scheduled (special access from Android 12).
  Future<bool> canScheduleExact();
}
