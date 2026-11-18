import 'generated/steps.pigeon.dart';

/// A reading from the native buffer, as stored by Kotlin.
typedef BufferedStep = ({
  int id,
  int cumulativeSteps,
  int bootCount,
  int elapsedRealtimeMs,
  DateTime wallTimeUtc,
  String tz,
  int utcOffsetS,
  String source,
});

/// The phone's step sensor and native collection (05 §B3).
abstract interface class StepCounter {
  Future<bool> hasSensor();
  Future<bool> hasPermission();
  Future<bool> requestPermission();

  /// Takes and buffers one reading now; null when none arrived.
  Future<BufferedStep?> readNow();
  Future<List<BufferedStep>> pending();
  Future<void> acknowledge(int maxId);
  Future<void> setContinuous(bool enabled);
  Future<bool> isContinuous();
  Future<void> scheduleSnapshots();
}

final class DeviceStepCounter implements StepCounter {
  DeviceStepCounter([StepApi? api]) : _api = api ?? StepApi();
  final StepApi _api;

  static BufferedStep _map(StepReadingMessage m) => (
    id: m.id,
    cumulativeSteps: m.cumulativeSteps,
    bootCount: m.bootCount,
    elapsedRealtimeMs: m.elapsedRealtimeMs,
    wallTimeUtc: DateTime.fromMillisecondsSinceEpoch(m.wallTimeUtcMs, isUtc: true),
    tz: m.tz,
    utcOffsetS: m.utcOffsetS,
    source: m.source,
  );

  Future<T> _try<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Object {
      return fallback;
    }
  }

  @override
  Future<bool> hasSensor() => _try(_api.hasSensor, false);
  @override
  Future<bool> hasPermission() => _try(_api.hasPermission, false);
  @override
  Future<bool> requestPermission() => _try(_api.requestPermission, false);
  @override
  Future<BufferedStep?> readNow() => _try(() async {
    final m = await _api.readNow();
    return m == null ? null : _map(m);
  }, null);
  @override
  Future<List<BufferedStep>> pending() =>
      _try(() async => [for (final m in await _api.pendingReadings()) _map(m)], const []);
  @override
  Future<void> acknowledge(int maxId) => _try(() => _api.acknowledge(maxId), null);
  @override
  Future<void> setContinuous(bool enabled) => _try(() => _api.setContinuous(enabled), null);
  @override
  Future<bool> isContinuous() => _try(_api.isContinuous, false);
  @override
  Future<void> scheduleSnapshots() => _try(_api.scheduleSnapshots, null);
}
