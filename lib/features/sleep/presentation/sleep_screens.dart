import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/sleep_math.dart';
import '../domain/sleep_repository.dart';

String _clock(BuildContext context, int minutes) => MaterialLocalizations.of(context).formatTimeOfDay(
  TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
  alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
);

/// Sleep history (PRD §5.9).
class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final month = ref.watch(sleepBetweenProvider((from: today.addDays(-29), to: today)));
    final targetMin = ref.watch(currentDailyGoalsProvider).value?.sleepTargetMin;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sleepTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
              onPressed: () => showFbSheet<void>(context, const SleepSheet()),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addEntry),
            ),
          ),
        ],
      ),
      body: month.when(
        loading: () => FbLoading(semanticLabel: l10n.loading),
        error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
        data: (entries) {
          final periods = entries.map((e) => e.period).toList();
          final week = periods.where((p) => !p.wakeDate.isBefore(today.addDays(-6)));
          final weekAvg = averageNightLength(week);
          final monthAvg = averageNightLength(periods);
          final habit = sleepConsistency(periods);
          final lastNight = entries.where((e) => e.period.kind == SleepKind.night).firstOrNull;
          final perDay = <LocalDate, int>{};
          for (final p in week.where((p) => p.kind == SleepKind.night)) {
            perDay.update(p.wakeDate, (m) => m + p.duration.inMinutes, ifAbsent: () => p.duration.inMinutes);
          }
          final start = today.addDays(-6);
          final dayNames = MaterialLocalizations.of(context).narrowWeekdays;

          return ListView(
            padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
            children: [
              FbCard(
                radius: FbRadius.hero,
                padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl, vertical: FbSpace.lg),
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.sleepLastNight, style: context.text.label),
                      const SizedBox(height: FbSpace.xs),
                      Text(
                        lastNight == null ? l10n.sleepNone : context.duration(lastNight.period.duration),
                        style: context.text.displayMetric,
                      ),
                      if (lastNight != null)
                        Text(
                          [
                            l10n.sleepRange(context.time(lastNight.period.start), context.time(lastNight.period.end)),
                            if (lastNight.quality != null) l10n.qualityValue(lastNight.quality!),
                            if (targetMin != null) l10n.sleepTargetH(_hours(targetMin)),
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FbSpace.md),
              FbFieldPair(
                first: _StatCard(
                  label: l10n.sleep7Avg,
                  value: weekAvg == null ? l10n.notSet : context.duration(weekAvg),
                  detail: monthAvg == null ? null : l10n.sleep30Avg(context.duration(monthAvg)),
                ),
                second: _StatCard(
                  label: l10n.sleepUsualTimes,
                  value: habit == null
                      ? l10n.sleepNeedTwo
                      : '${_clock(context, habit.usualBedtimeMinutes)} · ${_clock(context, habit.usualWakeMinutes)}',
                  detail: habit == null ? null : l10n.sleepSpread(habit.bedtimeSpreadMinutes),
                ),
              ),
              const SizedBox(height: FbSpace.md),
              FbChartCard(
                summary: l10n.sleepChartSummary,
                height: 150,
                chart: FbBarChart(
                  values: [for (var i = 0; i < 7; i++) (perDay[start.addDays(i)] ?? 0) / 60],
                  bottomLabel: (i) => dayNames[start.addDays(i).weekday % 7],
                  target: targetMin == null ? null : targetMin / 60,
                ),
              ),
              const SizedBox(height: FbSpace.xl),
              FbSectionTitle(l10n.history),
              const SizedBox(height: FbSpace.sm),
              if (entries.isEmpty)
                FbEmptyHint(l10n.noEntries)
              else
                FbListCard(children: [for (final e in entries) _SleepRow(entry: e)]),
              const SizedBox(height: FbSpace.md),
              Text(l10n.sleepHelp, style: context.text.caption),
            ],
          );
        },
      ),
    );
  }

  static String _hours(int minutes) => minutes % 60 == 0 ? '${minutes ~/ 60}' : (minutes / 60).toStringAsFixed(1);
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.detail});
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => FbCard(
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.label),
          const SizedBox(height: FbSpace.xs),
          Text(value, style: context.text.bodyStrong.copyWith(fontSize: 18)),
          if (detail != null) Text(detail!, style: context.text.caption),
        ],
      ),
    ),
  );
}

class _SleepRow extends StatelessWidget {
  const _SleepRow({required this.entry});
  final SleepEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = entry.period;
    final night = p.kind == SleepKind.night;
    final startDay = LocalDate.fromDateTime(p.start);
    final days = night && startDay != p.wakeDate
        ? '${context.shortDate(startDay)} → ${context.shortDate(p.wakeDate)}'
        : context.shortDate(p.wakeDate);
    return FbListRow(
      title: night ? context.duration(p.duration) : l10n.napLength(context.duration(p.duration)),
      subtitle: '$days · ${l10n.sleepRange(context.time(p.start), context.time(p.end))}',
      trailing: TextButton(
        onPressed: () => showFbSheet<void>(context, SleepSheet(existing: entry)),
        child: Text(l10n.edit, semanticsLabel: l10n.editEntryLabel(context.shortDate(p.wakeDate))),
      ),
    );
  }
}

/// Adds a sleep record or edits [existing]. Also opened from Home.
class SleepSheet extends ConsumerStatefulWidget {
  const SleepSheet({this.existing, super.key});
  final SleepEntry? existing;

  @override
  ConsumerState<SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<SleepSheet> {
  late SleepKind _kind = widget.existing?.period.kind ?? SleepKind.night;
  late DateTime _start;
  late DateTime _end;
  late int? _quality = widget.existing?.quality;
  late String _note = widget.existing?.notes ?? '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _start = existing.period.start;
      _end = existing.period.end;
      return;
    }
    final now = ref.read(clockProvider).now();
    final wake = DateTime(now.year, now.month, now.day, 7);
    _end = wake.isAfter(now) ? DateTime(now.year, now.month, now.day, now.hour, now.minute) : wake;
    _start = DateTime(now.year, now.month, now.day - 1, 23);
    if (!_start.isBefore(_end)) _start = _end.subtract(const Duration(hours: 8));
  }

  void _setKind(SleepKind kind) {
    if (widget.existing == null && kind == SleepKind.nap && kind != _kind) {
      final now = ref.read(clockProvider).now();
      _end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _start = _end.subtract(const Duration(minutes: 30));
    }
    setState(() => _kind = kind);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(sleepRepositoryProvider);
    final existing = widget.existing;
    final result = existing == null
        ? await repo.add(kind: _kind, start: _start, end: _end, quality: _quality, notes: _note)
        : (await repo.update(existing.id, kind: _kind, start: _start, end: _end, quality: _quality, notes: _note));
    if (!mounted) return;
    if (result.isOk) {
      showFbSnackBar(context, l10n.saved);
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (result.failureOrNull?.code) {
        'end_before_start' => l10n.errEndBeforeStart,
        'too_long' => l10n.errTooLong,
        'in_future' => l10n.errInFuture,
        _ => l10n.errSaveFailed,
      };
    });
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final agreed = await showFbConfirm(
      context,
      title: l10n.deleteEntryTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!agreed || !mounted) return;
    await ref.read(sleepRepositoryProvider).delete(widget.existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = ref.watch(clockProvider).now();
    return FbSheetBody(
      title: widget.existing == null ? l10n.addSleepTitle : l10n.editSleepTitle,
      trailing: widget.existing == null
          ? null
          : TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
              child: Text(l10n.delete),
            ),
      children: [
        FbSegmented<SleepKind>(
          options: {SleepKind.night: l10n.sleepNight, SleepKind.nap: l10n.sleepNap},
          selected: _kind,
          onChanged: _setKind,
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.bedtimeLabel,
          value: _start,
          last: now,
          onChanged: (v) => setState(() => _start = v),
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.wakeTimeLabel,
          value: _end,
          last: now,
          errorText: _error,
          onChanged: (v) => setState(() => _end = v),
        ),
        if (_end.isAfter(_start)) ...[
          const SizedBox(height: FbSpace.sm),
          Text(context.duration(_end.difference(_start)), style: context.text.bodyStrong),
        ],
        const SizedBox(height: FbSpace.lg),
        FbScoreRow(label: l10n.qualityLabel, value: _quality, onChanged: (v) => setState(() => _quality = v)),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.note,
          optional: true,
          optionalLabel: l10n.optional,
          value: _note,
          hint: l10n.noteHint,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (v) => _note = v,
        ),
        const SizedBox(height: FbSpace.xl),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}
