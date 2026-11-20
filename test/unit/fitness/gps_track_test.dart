import 'package:fitbuddy/features/fitness/domain/gps_track.dart';
import 'package:fitbuddy/features/fitness/domain/workouts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 16, 6);
  // About 111 m per 0.001 degree of latitude.
  RoutePoint p(int i, {int lat = 0, int accuracy = 50}) =>
      (latE7: 129700000 + lat, lonE7: 775900000, accuracyDm: accuracy, at: t0.add(Duration(seconds: i * 10)));

  test('sums distance between accurate fixes', () {
    final t = GpsTrack(startedAt: t0)
      ..add(p(0))
      ..add(p(1, lat: 10000))
      ..add(p(2, lat: 20000));
    expect(t.distanceM, closeTo(222, 2));
    expect(t.points, hasLength(3));
  });

  test('ignores inaccurate fixes and jitter', () {
    final t = GpsTrack(startedAt: t0)
      ..add(p(0))
      ..add(p(1, lat: 50000, accuracy: 900)) // 90 m accuracy
      ..add(p(2, lat: 10)); // 0.1 m
    expect(t.distanceM, 0);
    expect(t.points, hasLength(1));
  });

  test('pausing leaves out the time and the jump across the pause', () {
    final t = GpsTrack(startedAt: t0)
      ..add(p(0))
      ..add(p(1, lat: 10000))
      ..pause(t0.add(const Duration(minutes: 5)))
      ..add(p(40, lat: 90000))
      ..resume(t0.add(const Duration(minutes: 15)))
      ..add(p(100, lat: 90000))
      ..add(p(101, lat: 100000));
    expect(t.distanceM, closeTo(222, 2));
    expect(t.elapsed(t0.add(const Duration(minutes: 20))), const Duration(minutes: 10));
  });
}
