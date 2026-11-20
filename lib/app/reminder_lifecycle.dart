import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/notifications/notification_gateway.dart';
import '../core/widgets/l10n.dart';
import 'fitness_providers.dart';
import 'money_labels.dart';
import 'providers.dart';
import 'private_providers.dart';
import 'sync_controller.dart';
import 'push_controller.dart';
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
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(lockControllerProvider.notifier).movedToBackground(),
      onResume: () {
        ref.read(lockControllerProvider.notifier).returnedToForeground();
        replanReminders(ref);
        syncSteps(ref);
        refreshScreenTime(ref);
        unawaited(ref.read(syncControllerProvider.notifier).syncNow());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      replanReminders(ref);
      syncSteps(ref);
      unawaited(ref.read(workoutRepositoryProvider).seedExercises().catchError((Object _) {}));
      unawaited(ref.read(privateRepositoryProvider).seedHabitTypes().catchError((Object _) {}));
      unawaited(
        ref.read(moneyRepositoryProvider).seedCategories(categoryNames(context.l10n)).catchError((Object _) {}),
      );
      refreshScreenTime(ref);
      unawaited(ref.read(syncControllerProvider.notifier).syncNow());
      unawaited(ref.read(pushControllerProvider.notifier).start());
      unawaited(
        ref.read(pushMessagingProvider).initialMessage().then((m) {
          if (m != null && mounted) unawaited(ref.read(routerProvider).push(Routes.accountSync));
        }),
      );
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
    if (pushNotificationIds.contains(tap.notificationId)) {
      unawaited(ref.read(routerProvider).push(Routes.accountSync));
      return;
    }
    final target = await ref.read(reminderServiceProvider).handle(tap);
    if (target == null || !mounted) return;
    unawaited(ref.read(routerProvider).push(target.startsWith('/') ? target : Routes.activity(target)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pushOpenedProvider, (_, next) {
      if (next.value != null) unawaited(ref.read(routerProvider).push(Routes.accountSync));
    });
    ref.listen(notificationTapsProvider, (_, next) {
      final tap = next.value;
      if (tap != null) unawaited(_handle(tap));
    });
    return widget.child;
  }
}
