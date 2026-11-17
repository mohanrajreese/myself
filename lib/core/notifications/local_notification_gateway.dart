import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_gateway.dart';
import 'tz_zone.dart';

/// Channel ids are versioned: Android fixes a channel's sound once created,
/// so a sound change means a new id (R-08).
String channelIdFor(String key) => '${key}_v1';

typedef ChannelLabels = ({String name, String description});

/// Labels for the notification buttons, in the user's language.
typedef ActionLabels = ({String complete, String snooze, String skip});

/// `flutter_local_notifications` behind [NotificationGateway].
final class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({required this.actionLabels, FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final ActionLabels actionLabels;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Sets up channels and tap handling. [onBackgroundTap] must be a
  /// top-level function marked `@pragma('vm:entry-point')`.
  Future<void> initialize({
    required Map<String, ChannelLabels> channels,
    required void Function(NotificationTap) onTap,
    required DidReceiveBackgroundNotificationResponseCallback onBackgroundTap,
  }) async {
    ensureTimeZonesLoaded();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final tap = tapFrom(r);
        if (tap != null) onTap(tap);
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );
    for (final entry in channels.entries) {
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelIdFor(entry.key),
          entry.value.name,
          description: entry.value.description,
          importance: entry.key == 'alarms'
              ? Importance.max
              : (entry.key == 'system' ? Importance.low : Importance.high),
          playSound: entry.key != 'system',
          audioAttributesUsage: entry.key == 'alarms'
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
        ),
      );
    }
  }

  /// The tap that launched the app from a notification, if any.
  Future<NotificationTap?> launchTap() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) return null;
    return tapFrom(response);
  }

  static NotificationTap? tapFrom(NotificationResponse r) {
    final id = r.id ?? int.tryParse(r.payload ?? '');
    if (id == null) return null;
    return NotificationTap(notificationId: id, action: ReminderAction.fromCode(r.actionId));
  }

  NotificationDetails _details(NotificationRequest r) => NotificationDetails(
    android: AndroidNotificationDetails(
      r.channelId,
      r.channelId,
      category: r.channelId.startsWith('alarms')
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      visibility: r.secret ? NotificationVisibility.secret : NotificationVisibility.private,
      enableVibration: r.vibrate,
      actions: r.withActions
          ? [
              AndroidNotificationAction(ReminderAction.complete.code, actionLabels.complete),
              AndroidNotificationAction(ReminderAction.snooze.code, actionLabels.snooze),
              AndroidNotificationAction(ReminderAction.skip.code, actionLabels.skip),
            ]
          : null,
    ),
  );

  @override
  Future<void> schedule(NotificationRequest r) => _plugin.zonedSchedule(
    id: r.id,
    scheduledDate: tz.TZDateTime.from(r.at!.toUtc(), tz.UTC),
    notificationDetails: _details(r),
    androidScheduleMode: r.exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    title: r.title,
    body: r.body,
    payload: '${r.id}',
  );

  @override
  Future<void> show(NotificationRequest r) => _plugin.show(
    id: r.id,
    title: r.title,
    body: r.body,
    notificationDetails: _details(r),
    payload: '${r.id}',
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<bool> notificationsAllowed() async => await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<bool> canScheduleExact() async => await _android?.canScheduleExactNotifications() ?? false;
}
