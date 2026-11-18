import '../core/platform/step_counter.dart';
import '../features/fitness/domain/step_attribution.dart';
import '../features/fitness/domain/step_repository.dart';

/// What the step screen shows about collection (05 §B6).
typedef StepStatus = ({bool supported, bool permission, bool continuous, DateTime? lastReading});

/// Moves readings from the native buffer into the database and manages
/// collection modes. Kotlin collects; Dart decides.
final class StepService {
  StepService({required this.counter, required this.steps});
  final StepCounter counter;
  final StepRepository steps;

  Future<StepStatus> status() async => (
    supported: await counter.hasSensor(),
    permission: await counter.hasPermission(),
    continuous: await counter.isContinuous(),
    lastReading: await steps.lastReadingAt(),
  );

  /// Asks for activity recognition and starts snapshot collection.
  Future<bool> enable() async {
    if (!await counter.hasSensor()) return false;
    final granted = await counter.requestPermission();
    if (granted) {
      await counter.scheduleSnapshots();
      await sync();
    }
    return granted;
  }

  Future<void> setContinuous(bool enabled) => counter.setContinuous(enabled);

  /// Takes a reading now (app in the foreground) and ingests the buffer.
  Future<void> sync() async {
    if (!await counter.hasSensor() || !await counter.hasPermission()) return;
    await counter.scheduleSnapshots();
    await counter.readNow();
    final pending = await counter.pending();
    if (pending.isEmpty) return;
    final result = await steps.ingest([
      for (final p in pending)
        (
          reading: StepReading(
            cumulativeSteps: p.cumulativeSteps,
            bootCount: p.bootCount,
            elapsedRealtimeMs: p.elapsedRealtimeMs,
            wallTimeUtc: p.wallTimeUtc,
            utcOffsetSeconds: p.utcOffsetS,
          ),
          tz: p.tz,
          source: p.source,
        ),
    ]);
    if (result.isOk)
      await counter.acknowledge(pending.map((p) => p.id).reduce((a, b) => a > b ? a : b));
  }
}
