import '../core/database/settings_repository.dart';
import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/platform/privacy_platform.dart';
import '../core/utils/clock.dart';
import '../core/utils/local_date.dart';
import '../features/screen_time/domain/screen_time.dart';

/// Daily target and alerts. No package names here (they stay private).
final class ScreenTimeSettings {
  const ScreenTimeSettings({this.targetMinutes, this.alerts = false, this.alertedOn});
  final int? targetMinutes;
  final bool alerts;
  final String? alertedOn;

  static const key = 'screen_time_settings';
  Map<String, Object?> toJson() => {'target': targetMinutes, 'alerts': alerts, 'alertedOn': alertedOn};
  static ScreenTimeSettings fromJson(Object? j) => switch (j) {
    {'target': final int? t, 'alerts': final bool a} => ScreenTimeSettings(
      targetMinutes: t,
      alerts: a,
      alertedOn: j['alertedOn'] as String?,
    ),
    _ => const ScreenTimeSettings(),
  };
}

/// Pulls usage from Android into the private database (§5.17).
final class ScreenTimeService {
  ScreenTimeService({
    required this.reader,
    required this.repo,
    required this.settings,
    required this.gateway,
    required this.clock,
    required this.alertTitle,
  });
  final UsageReader reader;
  final ScreenTimeRepository repo;
  final SettingsRepository settings;
  final NotificationGateway gateway;
  final Clock clock;
  final String alertTitle;

  static const alertNotificationId = 902;

  Future<ScreenTimeSettings> read() async => ScreenTimeSettings.fromJson(await settings.read(ScreenTimeSettings.key));
  Future<void> write(ScreenTimeSettings s) => settings.write(ScreenTimeSettings.key, s.toJson());

  /// Refreshes the last [days] days (Android keeps detailed events only a
  /// few days, so older days keep their stored totals).
  Future<void> refresh({int days = 7}) async {
    if (!await reader.hasAccess()) return;
    final now = clock.now();
    final today = LocalDate.fromDateTime(now);
    for (var i = days - 1; i >= 0; i--) {
      final day = today.addDays(-i);
      final start = DateTime(day.year, day.month, day.day);
      final end = i == 0 ? now : DateTime(day.year, day.month, day.day + 1);
      final usage = await reader.usage(start, end);
      if (usage.isEmpty && i > 0) continue;
      await repo.store(day, usage, partial: i == 0);
    }
    await _maybeAlert(today);
  }

  Future<void> _maybeAlert(LocalDate today) async {
    final s = await read();
    final target = s.targetMinutes;
    if (!s.alerts || target == null || s.alertedOn == today.toString()) return;
    final days = await repo.watchDays(from: today, to: today).first;
    final total = days.isEmpty ? 0 : days.single.totalMs;
    if (total < target * 60000) return;
    await gateway.show(
      NotificationRequest(
        id: alertNotificationId,
        channelId: channelIdFor('system'),
        title: alertTitle,
        withActions: false,
        secret: true,
      ),
    );
    await write(ScreenTimeSettings(targetMinutes: target, alerts: true, alertedOn: today.toString()));
  }
}
