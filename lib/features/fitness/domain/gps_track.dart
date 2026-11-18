import 'dart:math' as math;

import 'workouts.dart';

/// Builds a GPS workout from fixes (§5.7): drops inaccurate fixes, sums
/// distance, and leaves out paused time and the jump across a pause.
final class GpsTrack {
  GpsTrack({required this.startedAt});

  final DateTime startedAt;
  final List<RoutePoint> points = [];
  int distanceM = 0;
  bool paused = false;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;
  bool _resumeGap = false;

  /// Fixes worse than 50 m are ignored.
  static const maxAccuracyDm = 500;

  /// Movement under 2 m between fixes is treated as standing still (jitter).
  static const minStepM = 2;

  void add(RoutePoint p) {
    if (paused) return;
    if (p.accuracyDm != null && p.accuracyDm! > maxAccuracyDm) return;
    if (points.isNotEmpty && !_resumeGap) {
      final d = metresBetween(points.last, p);
      if (d < minStepM) return;
      distanceM += d;
    }
    _resumeGap = false;
    points.add(p);
  }

  void pause(DateTime at) {
    if (paused) return;
    paused = true;
    _pausedAt = at;
  }

  void resume(DateTime at) {
    if (!paused) return;
    paused = false;
    _pausedTotal += at.difference(_pausedAt!);
    _pausedAt = null;
    _resumeGap = true;
  }

  Duration elapsed(DateTime now) {
    final paused = _pausedAt == null ? Duration.zero : now.difference(_pausedAt!);
    final e = now.difference(startedAt) - _pausedTotal - paused;
    return e.isNegative ? Duration.zero : e;
  }

  /// Great-circle distance in whole metres.
  static int metresBetween(RoutePoint a, RoutePoint b) {
    const r = 6371000.0;
    double rad(int e7) => e7 / 1e7 * math.pi / 180;
    final dLat = rad(b.latE7 - a.latE7);
    final dLon = rad(b.lonE7 - a.lonE7);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latE7)) * math.cos(rad(b.latE7)) * math.pow(math.sin(dLon / 2), 2);
    return (2 * r * math.asin(math.sqrt(h))).round();
  }
}
