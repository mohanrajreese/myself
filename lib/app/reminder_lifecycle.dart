import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/notifications/notification_gateway.dart';
import 'routes.dart';
import 'router.dart';
import 'routine_providers.dart';

/// Re-plans reminders when the app starts or returns to the foreground, and
/// applies notification taps (buttons, or opening the linked activity).
class ReminderLifecycle extends ConsumerStatefulWidget {
  const ReminderLifecycle({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ReminderLifecycle> createState() => _ReminderLifecycleState();
}

class _ReminderLifecycleState extends ConsumerState<ReminderLifecycle> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => replanReminders(ref));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      replanReminders(ref);
      final launch = ref.read(launchTapProvider);
      if (launch != null) unawaited(_handle(launch));
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _handle(NotificationTap tap) async {
    final activityId = await ref.read(reminderServiceProvider).handle(tap);
    if (activityId != null && mounted) {
      unawaited(ref.read(routerProvider).push(Routes.activity(activityId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationTapsProvider, (_, next) {
      final tap = next.value;
      if (tap != null) unawaited(_handle(tap));
    });
    return widget.child;
  }
}
