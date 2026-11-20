import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routine_providers.dart';
import '../../../core/notifications/local_notification_gateway.dart';
import '../../../core/notifications/notification_gateway.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../activities/domain/activity.dart';
import '../../activities/domain/activity_repository.dart';
import '../domain/timer_session.dart';

/// Notification id for "timer finished"; one timer runs at a time.
const timerNotificationId = 900;

/// Stopwatch and timer for an activity (approved design; §5.16).
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({required this.activityId, super.key});
  final String activityId;

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  Timer? _tick;
  TimerKind _kind = TimerKind.stopwatch;
  String _minutes = '';
  bool _notify = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now();

  Future<void> _start(Activity a) async {
    final l10n = context.l10n;
    Duration? target;
    if (_kind == TimerKind.countdown) {
      final m = int.tryParse(_minutes.trim().isEmpty ? '${(a.targetMilli ?? 0) ~/ 60000}' : _minutes.trim());
      if (m == null || m < 1 || m > 1440) {
        showFbSnackBar(context, l10n.errOutOfRange);
        return;
      }
      target = Duration(minutes: m);
    }
    setState(() => _busy = true);
    final repo = ref.read(timerRepositoryProvider);
    final created = await repo.create(kind: _kind, target: target, activityId: a.id);
    final session = created.valueOrNull;
    if (session != null) {
      final started = (await repo.transition(session.id, TimerEventType.start)).valueOrNull;
      if (started != null) await _scheduleDone(a, started);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scheduleDone(Activity a, TimerSession s) async {
    final gateway = ref.read(notificationGatewayProvider);
    await gateway.cancel(timerNotificationId);
    final ends = s.endsAt;
    if (!_notify || ends == null || !mounted) return;
    final l10n = context.l10n;
    await gateway.schedule(
      NotificationRequest(
        id: timerNotificationId,
        at: ends,
        channelId: channelIdFor('fitness'),
        title: l10n.timerDoneTitle,
        body: l10n.timerDoneBody(a.name, context.duration(s.targetDuration!)),
        withActions: false,
      ),
    );
  }

  Future<void> _transition(Activity a, TimerSession s, TimerEventType type) async {
    setState(() => _busy = true);
    final next = (await ref.read(timerRepositoryProvider).transition(s.id, type)).valueOrNull;
    if (next != null) await _scheduleDone(a, next);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish(Activity a, TimerSession s) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final timers = ref.read(timerRepositoryProvider);
    final done = (await timers.transition(s.id, TimerEventType.finish)).valueOrNull;
    await ref.read(notificationGatewayProvider).cancel(timerNotificationId);
    if (done == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final elapsed = done.elapsed(_now);
    final log = await ref
        .read(activityRepositoryProvider)
        .addLog(
          a.id,
          LogDraft(
            status: ActivityLogStatus.completed,
            occurredAt: _now,
            source: LogSource.timer,
            durationS: math.min(elapsed.inSeconds, 86400),
          ),
        );
    if (log.valueOrNull != null) await timers.linkLog(s.id, log.valueOrNull!.id);
    replanReminders(ref);
    if (!mounted) return;
    showFbSnackBar(context, l10n.timerLogged(context.duration(elapsed)));
    context.pop();
  }

  Future<void> _cancel(Activity a, TimerSession s) async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.cancelTimerTitle,
      message: l10n.cancelTimerMessage,
      confirmLabel: l10n.cancelTimer,
      cancelLabel: l10n.keepGoing,
    );
    if (!ok) return;
    await ref.read(notificationGatewayProvider).cancel(timerNotificationId);
    await _transition(a, s, TimerEventType.cancel);
  }

  String _clock(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(activityProvider(widget.activityId));
    final timers = ref.watch(activeTimersProvider);
    if (a == null || timers.value == null) {
      return Scaffold(appBar: AppBar(), body: const FbLoading());
    }
    final session = timers.value!.where((t) => t.activityId == a.id).firstOrNull;
    final now = _now.toUtc();
    return Scaffold(
      appBar: AppBar(title: Text(a.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.xl, FbSpace.sm, FbSpace.xl, FbSpace.xxl),
        children: session == null ? _setup(a) : _running(a, session, now),
      ),
    );
  }

  List<Widget> _setup(Activity a) {
    final l10n = context.l10n;
    return [
      FbSegmented<TimerKind>(
        options: {TimerKind.stopwatch: l10n.stopwatch, TimerKind.countdown: l10n.timer},
        selected: _kind,
        onChanged: (k) => setState(() => _kind = k),
      ),
      const SizedBox(height: FbSpace.xl),
      if (_kind == TimerKind.countdown) ...[
        FbTextField(
          label: l10n.durationLabel,
          value: _minutes,
          hint: a.targetMilli == null ? null : '${a.targetMilli! ~/ 60000}',
          onChanged: (v) => _minutes = v,
          suffix: l10n.unitMin,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: FbSpace.md),
        FbCard(
          padding: EdgeInsets.zero,
          child: FbSwitchRow(
            title: l10n.notifyWhenDone,
            subtitle: l10n.notifyWhenDoneHelp,
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ),
        const SizedBox(height: FbSpace.lg),
      ],
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy ? null : () => _start(a),
        child: Text(l10n.start),
      ),
      const SizedBox(height: FbSpace.md),
      Text(l10n.timerNote, style: context.text.caption),
    ];
  }

  List<Widget> _running(Activity a, TimerSession s, DateTime now) {
    final l10n = context.l10n;
    final elapsed = s.elapsed(now);
    final remaining = s.remaining(now);
    final overdue = s.kind == TimerKind.countdown && remaining == Duration.zero;
    final fraction = s.targetDuration == null
        ? null
        : (elapsed.inMilliseconds / s.targetDuration!.inMilliseconds).clamp(0.0, 1.0);
    final big = remaining != null ? _clock(remaining) : _clock(elapsed);
    final caption = switch (s.state) {
      TimerState.paused => l10n.timerPaused,
      _ when overdue => l10n.timesUp,
      _ when s.targetDuration != null => l10n.leftOf(_clock(s.targetDuration!)),
      _ => l10n.elapsed,
    };
    return [
      Center(
        child: Semantics(
          label: l10n.timerSemantics(big, caption),
          excludeSemantics: true,
          child: SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: fraction ?? (s.state == TimerState.running ? null : 0),
                    strokeWidth: 12,
                    backgroundColor: context.colors.surfaceVariant,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      big,
                      style: context.text.displayMetric.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text(caption, style: context.text.caption),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: FbSpace.xl),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: _busy ? null : () => _cancel(a, s), child: Text(l10n.cancelTimer)),
          ),
          const SizedBox(width: FbSpace.md),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () =>
                        _transition(a, s, s.state == TimerState.running ? TimerEventType.pause : TimerEventType.resume),
              child: Text(s.state == TimerState.running ? l10n.pause : l10n.resume),
            ),
          ),
        ],
      ),
      const SizedBox(height: FbSpace.md),
      FilledButton.tonal(
        onPressed: _busy || elapsed.inSeconds < 1 ? null : () => _finish(a, s),
        child: Text(
          l10n.finishAndLog(context.duration(Duration(minutes: math.max(1, (elapsed.inSeconds / 60).round())))),
        ),
      ),
      const SizedBox(height: FbSpace.md),
      Text(l10n.timerNote, style: context.text.caption),
    ];
  }
}
