import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/insights/data/drift_report_repository.dart';
import '../features/insights/domain/report.dart';
import '../features/screen_time/domain/screen_time.dart';
import 'private_providers.dart';
import 'providers.dart';
import 'routine_providers.dart';

final reportRepositoryProvider = Provider<DriftReportRepository>((ref) {
  ScreenTimeRepository? screen;
  try {
    screen = ref.watch(screenTimeRepositoryProvider);
  } on Object {
    screen = null; // Private database unavailable: screen time left out.
  }
  return DriftReportRepository(
    ref.watch(appDatabaseProvider),
    activities: ref.watch(activityRepositoryProvider),
    screenTime: screen,
    clock: ref.watch(clockProvider),
  );
});

/// A period's report, kept current as records change.
final periodReportProvider = StreamProvider.family<PeriodReport, DateRange>(
  (ref, range) => ref.watch(reportRepositoryProvider).watch(range),
);
