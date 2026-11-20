import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fitness_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/platform/location_tracker.dart';
import '../../../core/units/decimal_text.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/gps_track.dart';
import '../domain/workout_math.dart';
import '../domain/workouts.dart';
import 'fitness_labels.dart';

/// Parses `mm:ss`, `h:mm:ss` or plain minutes into seconds.
int? parseDuration(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length == 1) {
    final m = int.tryParse(parts.first);
    return m == null ? null : m * 60;
  }
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0)) return null;
  return parts.length == 2 ? nums[0]! * 60 + nums[1]! : nums[0]! * 3600 + nums[1]! * 60 + nums[2]!;
}

/// Log a walk, run or ride by hand, or start GPS (approved design).
class CardioLogScreen extends ConsumerStatefulWidget {
  const CardioLogScreen({required this.kind, this.existing, super.key});
  final WorkoutKind kind;
  final WorkoutSession? existing;

  @override
  ConsumerState<CardioLogScreen> createState() => _CardioLogScreenState();
}

class _CardioLogScreenState extends ConsumerState<CardioLogScreen> {
  late WorkoutKind _kind = widget.kind;
  late DateTime _start;
  late DateTime _end;
  late String _distance = widget.existing?.distanceM == null
      ? ''
      : (widget.existing!.distanceM! / 1000).toStringAsFixed(2);
  late String _notes = widget.existing?.notes ?? '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    _end =
        widget.existing?.endedAt?.toLocal() ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _start = widget.existing?.startedAt.toLocal() ?? _end.subtract(const Duration(minutes: 30));
  }

  int get _seconds => _end.difference(_start).inSeconds;
  int? get _metres {
    final v = parseScaled(_distance.trim(), 3);
    return v;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final m = _metres;
    if (m == null) return setState(() => _error = l10n.errInvalidNumber);
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(workoutRepositoryProvider);
    final result = widget.existing == null
        ? (await repo.logCardio(
            kind: _kind,
            start: _start,
            end: _end,
            distanceM: m,
            notes: _notes,
          )).map((_) {})
        : await repo.updateSession(
            widget.existing!.id,
            start: _start,
            end: _end,
            distanceM: m,
            notes: _notes,
          );
    if (!mounted) return;
    if (!result.isOk) {
      setState(() {
        _busy = false;
        _error = switch (result.failureOrNull) {
          ValidationFailure(code: 'in_future') => l10n.errInFuture,
          ValidationFailure(code: 'duration_required') => l10n.errEndBeforeStart,
          ValidationFailure() => l10n.errOutOfRange,
          _ => l10n.errSaveFailed,
        };
      });
      return;
    }
    showFbSnackBar(context, l10n.workoutSaved);
    context.pop();
  }

  Future<void> _startGps() async {
    final l10n = context.l10n;
    final tracker = ref.read(locationTrackerProvider);
    var access = await tracker.access();
    if (!mounted) return;
    if (access == LocationAccess.denied) {
      final go = await showFbConfirm(
        context,
        title: l10n.gpsRationaleTitle,
        message: l10n.gpsRationaleBody,
        confirmLabel: l10n.continueAction,
        cancelLabel: l10n.notNow,
      );
      if (!go) return;
      access = await tracker.request();
    }
    if (!mounted) return;
    switch (access) {
      case LocationAccess.granted:
        context.pushReplacement(Routes.gpsWorkout(_kind.code));
      case LocationAccess.serviceOff:
        showFbSnackBar(context, l10n.gpsServiceOff);
      case LocationAccess.denied || LocationAccess.deniedForever:
        showFbSnackBar(context, l10n.gpsDenied);
        if (access == LocationAccess.deniedForever) unawaited(tracker.openSettings());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = ref.read(clockProvider).now();
    final m = _metres ?? 0;
    final pace = paceSecondsPerKm(distanceM: m, durationS: _seconds);
    final speed = speedMetresPerHour(distanceM: m, durationS: _seconds);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.logKind(workoutKindName(l10n, _kind)) : l10n.editWorkout,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.xl, FbSpace.sm, FbSpace.xl, FbSpace.xxl),
        children: [
          if (widget.existing == null) ...[
            FbSegmented<WorkoutKind>(
              options: {
                for (final k in const [WorkoutKind.walk, WorkoutKind.run, WorkoutKind.cycle])
                  k: workoutKindName(l10n, k),
              },
              selected: _kind,
              onChanged: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: FbSpace.lg),
          ],
          if (_error != null) ...[
            FbNotice(_error!, isError: true),
            const SizedBox(height: FbSpace.md),
          ],
          FbDateTimeField(
            label: l10n.startLabel,
            value: _start,
            last: now,
            onChanged: (v) => setState(() => _start = v),
          ),
          const SizedBox(height: FbSpace.md),
          FbDateTimeField(
            label: l10n.endLabel,
            value: _end,
            last: now,
            onChanged: (v) => setState(() => _end = v),
          ),
          const SizedBox(height: FbSpace.md),
          FbTextField(
            label: l10n.distanceLabel,
            value: _distance,
            onChanged: (v) => setState(() => _distance = v),
            suffix: l10n.unitKm,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    _seconds > 0 ? clockLabel(Duration(seconds: _seconds)) : '—',
                    l10n.durationLabel,
                  ),
                ),
                Expanded(
                  child: _kind == WorkoutKind.cycle
                      ? _Metric(speed == null ? '—' : speedLabel(context, speed), l10n.averageSpeed)
                      : _Metric(pace == null ? '—' : paceLabel(context, pace), l10n.averagePace),
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          FbTextField(
            label: l10n.note,
            value: _notes,
            onChanged: (v) => _notes = v,
            optional: true,
            optionalLabel: l10n.optional,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (widget.existing == null) ...[
            const SizedBox(height: FbSpace.lg),
            FbCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.trackWithGps, style: context.text.bodyStrong),
                        Text(l10n.trackWithGpsHelp, style: context.text.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: FbSpace.sm),
                  FilledButton.tonal(onPressed: _startGps, child: Text(l10n.start)),
                ],
              ),
            ),
            const SizedBox(height: FbSpace.sm),
            Text(l10n.manualNoLocation, style: context.text.caption),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.text.bodyStrong.copyWith(fontSize: 18)),
        Text(label, style: context.text.caption),
      ],
    ),
  );
}

/// Live GPS walk, run or ride (approved design "GPS tracking").
class GpsWorkoutScreen extends ConsumerStatefulWidget {
  const GpsWorkoutScreen({required this.kind, super.key});
  final WorkoutKind kind;

  @override
  ConsumerState<GpsWorkoutScreen> createState() => _GpsWorkoutScreenState();
}

class _GpsWorkoutScreenState extends ConsumerState<GpsWorkoutScreen> {
  late final GpsTrack _track = GpsTrack(startedAt: ref.read(clockProvider).now().toUtc());
  StreamSubscription<LocationFix>? _sub;
  Timer? _tick;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = context.l10n;
      _sub = ref
          .read(locationTrackerProvider)
          .track(
            title: l10n.gpsNotificationTitle(workoutKindName(l10n, widget.kind)),
            text: l10n.gpsNotificationText,
          )
          .listen(
            (f) => setState(
              () =>
                  _track.add((latE7: f.latE7, lonE7: f.lonE7, accuracyDm: f.accuracyDm, at: f.at)),
            ),
          );
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _tick?.cancel();
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now().toUtc();

  Future<void> _finish() async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    await _sub?.cancel();
    final elapsed = _track.elapsed(_now);
    final start = _now.subtract(elapsed);
    final result = await ref
        .read(workoutRepositoryProvider)
        .logCardio(
          kind: widget.kind,
          start: start,
          end: _now,
          distanceM: _track.distanceM,
          route: _track.points,
        );
    if (!mounted) return;
    showFbSnackBar(context, result.isOk ? l10n.workoutSaved : l10n.errSaveFailed);
    context.pop();
  }

  Future<void> _discard() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.discardWorkoutTitle,
      message: l10n.discardWorkoutMessage,
      confirmLabel: l10n.discard,
      cancelLabel: l10n.keepGoing,
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final elapsed = _track.elapsed(_now);
    final pace = paceSecondsPerKm(distanceM: _track.distanceM, durationS: elapsed.inSeconds);
    final speed = speedMetresPerHour(distanceM: _track.distanceM, durationS: elapsed.inSeconds);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_discard());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.gpsInProgress(workoutKindName(l10n, widget.kind)))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
          children: [
            FbCard(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 240,
                child: Semantics(
                  label: l10n.routeSemantics(km(context, _track.distanceM)),
                  child: CustomPaint(
                    painter: RoutePainter(
                      _track.points,
                      context.colors.primary,
                      context.colors.outline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: FbSpace.lg),
            Row(
              children: [
                Expanded(child: _Metric(km(context, _track.distanceM), l10n.distanceLabel)),
                Expanded(child: _Metric(clockLabel(elapsed), l10n.timeLabel)),
                Expanded(
                  child: widget.kind == WorkoutKind.cycle
                      ? _Metric(speed == null ? '—' : speedLabel(context, speed), l10n.averageSpeed)
                      : _Metric(pace == null ? '—' : paceLabel(context, pace), l10n.averagePace),
                ),
              ],
            ),
            const SizedBox(height: FbSpace.md),
            Text(
              _track.points.isEmpty
                  ? l10n.gpsWaiting
                  : (_track.paused ? l10n.timerPaused : l10n.gpsGood),
              style: context.text.caption,
            ),
            const SizedBox(height: FbSpace.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _track.paused ? _track.resume(_now) : _track.pause(_now),
                          ),
                    child: Text(_track.paused ? l10n.resume : l10n.pause),
                  ),
                ),
                const SizedBox(width: FbSpace.md),
                Expanded(
                  flex: 2,
                  child: FbPrimaryButton(
                    label: l10n.finish,
                    busy: _saving,
                    onPressed: elapsed.inSeconds < 1 ? null : _finish,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FbSpace.sm),
            TextButton(onPressed: _discard, child: Text(l10n.discard)),
            const SizedBox(height: FbSpace.sm),
            Text(l10n.gpsNote, style: context.text.caption),
          ],
        ),
      ),
    );
  }
}

/// Draws a route as a line, fitted to the box, without map tiles (C3).
class RoutePainter extends CustomPainter {
  RoutePainter(this.points, this.color, this.grid);
  final List<RoutePoint> points;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final lats = points.map((p) => p.latE7);
    final lons = points.map((p) => p.lonE7);
    final minLat = lats.reduce((a, b) => a < b ? a : b),
        maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b),
        maxLon = lons.reduce((a, b) => a > b ? a : b);
    final span = [
      (maxLat - minLat),
      (maxLon - minLon),
      1,
    ].reduce((a, b) => a > b ? a : b).toDouble();
    const pad = 20.0;
    final scale = (size.shortestSide - pad * 2) / span;
    Offset at(RoutePoint p) => Offset(
      pad + (p.lonE7 - minLon) * scale + (size.width - pad * 2 - (maxLon - minLon) * scale) / 2,
      size.height -
          pad -
          (p.latE7 - minLat) * scale -
          (size.height - pad * 2 - (maxLat - minLat) * scale) / 2,
    );
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(points.first), 6, Paint()..color = grid);
    canvas.drawCircle(at(points.last), 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.points.length != points.length;
}
