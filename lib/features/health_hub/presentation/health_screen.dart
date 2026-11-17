import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../sleep/domain/sleep_math.dart';
import '../../weight/domain/weight_trend.dart';

/// The Health tab: one card per area, each opening its screen.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final units = ref.watch(unitsProvider);
    final week = ref.watch(weightSinceProvider(today.addDays(-7))).value ?? const [];
    final latest = ref.watch(latestWeightProvider).value;
    final target = ref.watch(currentDailyGoalsProvider).value?.targetWeightG;
    final measurements = ref.watch(latestMeasurementsProvider).value ?? const [];
    final lastNight = ref.watch(sleepOnProvider(today));
    final weekSleep =
        ref.watch(sleepBetweenProvider((from: today.addDays(-6), to: today))).value ?? const [];
    final weekAverage = averageNightLength(weekSleep.map((e) => e.period));
    final checkins = ref.watch(wellnessBetweenProvider((from: today, to: today))).value ?? const [];

    final change = weightChangeG(
      [for (final e in week) (date: e.localDate, weightG: e.weightG)],
      today: today,
      days: 7,
    );
    final weightLine = [
      if (change != null) l10n.weightChange7(context.massChange(change, units.mass)),
      if (target != null) l10n.weightTargetSuffix(context.mass(target, units.mass)),
    ].join(' · ');

    final lastMeasured = measurements.isEmpty
        ? null
        : measurements.reduce((a, b) => a.occurredAt.isAfter(b.occurredAt) ? a : b);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.healthTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          _HubCard(
            label: l10n.cardWeight,
            value: latest == null ? l10n.noWeightYet : context.mass(latest.weightG, units.mass),
            detail: weightLine.isEmpty ? null : weightLine,
            onTap: () => context.push(Routes.weight),
          ),
          _HubCard(
            label: l10n.cardMeasurements,
            value: lastMeasured == null
                ? l10n.measurementsNone
                : l10n.measurementsTracked(measurements.length),
            detail: lastMeasured == null ? null : context.shortDate(lastMeasured.localDate),
            onTap: () => context.push(Routes.measurements),
          ),
          _HubCard(
            label: l10n.cardSleep,
            value: lastNight == null ? l10n.sleepNone : context.duration(lastNight),
            detail: [
              if (lastNight != null) l10n.sleepLastNight,
              if (weekAverage != null) l10n.sleepWeeklyAverage(context.duration(weekAverage)),
            ].join(' · '),
            onTap: () => context.push(Routes.sleep),
          ),
          _HubCard(
            label: l10n.cardCheckin,
            value: checkins.isEmpty
                ? l10n.checkinNotToday
                : l10n.checkinCountToday(checkins.length),
            detail: l10n.checkinSubtitle,
            onTap: () => context.push(Routes.checkin),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.label, required this.value, required this.onTap, this.detail});

  final String label;
  final String value;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FbSpace.md),
    child: FbCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(FbRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.text.label),
                      const SizedBox(height: FbSpace.xs),
                      Text(value, style: context.text.metric),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: FbSpace.xs),
                        Text(detail!, style: context.text.caption),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
