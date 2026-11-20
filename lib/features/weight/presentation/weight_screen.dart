import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/units/units.dart';
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
import '../domain/weight_entry.dart';
import '../domain/weight_trend.dart';

String rangeName(AppLocalizations l10n, ChartRange r) => switch (r) {
  ChartRange.week => l10n.range7,
  ChartRange.month => l10n.range30,
  ChartRange.quarter => l10n.range90,
  ChartRange.year => l10n.range365,
};

/// Weight history (PRD §5.2): current, target, change, chart, entries.
class WeightScreen extends ConsumerStatefulWidget {
  const WeightScreen({super.key});

  @override
  ConsumerState<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends ConsumerState<WeightScreen> {
  static const _pageSize = 30;
  ChartRange _range = ChartRange.month;
  List<WeightEntry> _entries = const [];
  bool _hasMore = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final page = await ref.read(weightRepositoryProvider).page(limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _entries = page;
      _hasMore = page.length == _pageSize;
      _loading = false;
    });
  }

  Future<void> _more() async {
    final page = await ref
        .read(weightRepositoryProvider)
        .page(limit: _pageSize, before: _entries.last.occurredAt);
    if (!mounted) return;
    setState(() {
      _entries = [..._entries, ...page];
      _hasMore = page.length == _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final units = ref.watch(unitsProvider);
    final latest = ref.watch(latestWeightProvider).value;
    final target = ref.watch(currentDailyGoalsProvider).value?.targetWeightG;
    final start = rangeStart(today, _range.days);
    final inRange = ref.watch(weightSinceProvider(start)).value ?? const <WeightEntry>[];
    ref.listen(latestWeightProvider, (_, _) => unawaited(_reload()));

    final points = [for (final e in inRange) (date: e.localDate, weightG: e.weightG)];
    final change = weightChangeG(points, today: today, days: _range.days);
    final chartPoints = [
      for (final e in inRange)
        if (!e.localDate.isBefore(start))
          (x: dayOffset(start, e.localDate), y: double.parse(formatMass(e.weightG, units.mass))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.weightTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
              onPressed: () => context.push(Routes.addWeight),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addEntry),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              _Stat(
                l10n.statCurrent,
                latest == null ? l10n.notSet : context.mass(latest.weightG, units.mass),
              ),
              _Stat(
                l10n.statTarget,
                target == null ? l10n.notSet : context.mass(target, units.mass),
              ),
              _Stat(
                l10n.statChange(_range.days),
                change == null ? l10n.notSet : context.massChange(change, units.mass),
              ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          FbSegmented<ChartRange>(
            semanticLabel: l10n.rangeLabel,
            options: {for (final r in ChartRange.values) r: rangeName(l10n, r)},
            selected: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: FbSpace.md),
          if (chartPoints.length < 2)
            FbEmptyHint(l10n.weightChartEmpty, boxed: true)
          else
            FbChartCard(
              summary: l10n.weightChartSummary(
                _range.days,
                context.mass(
                  inRange.firstWhere((e) => !e.localDate.isBefore(start)).weightG,
                  units.mass,
                ),
                context.mass(inRange.last.weightG, units.mass),
              ),
              chart: FbLineChart(
                points: chartPoints,
                minX: 0,
                maxX: _range.days.toDouble(),
                bottomInterval: _range.days / 3,
                bottomLabel: (x) => context.shortDate(start.addDays(x.round())),
                leftLabel: (y) => y.toStringAsFixed(0),
                target: target == null ? null : double.parse(formatMass(target, units.mass)),
              ),
              footer: Text(l10n.weightFluctuationNote, style: context.text.caption),
            ),
          const SizedBox(height: FbSpace.xl),
          FbSectionTitle(l10n.entriesTitle),
          const SizedBox(height: FbSpace.sm),
          if (_loading)
            FbLoading(semanticLabel: l10n.loading)
          else if (_entries.isEmpty)
            FbEmptyHint(l10n.noEntries)
          else
            FbListCard(
              children: [
                for (final e in _entries)
                  FbListRow(
                    title: context.mass(e.weightG, e.entryUnit),
                    subtitle: [
                      '${context.dayLabel(e.localDate)} · ${context.time(e.occurredAt)}',
                      ?e.notes,
                    ].join(' · '),
                    trailing: TextButton(
                      onPressed: () => showFbSheet<void>(context, WeightEditSheet(entry: e)),
                      child: Text(
                        l10n.edit,
                        semanticsLabel: l10n.editEntryLabel(context.shortDate(e.localDate)),
                      ),
                    ),
                  ),
              ],
            ),
          if (_hasMore && _entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FbSpace.md),
              child: OutlinedButton(onPressed: _more, child: Text(l10n.loadMore)),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 104),
    child: FbCard(
      padding: const EdgeInsets.all(FbSpace.md),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: context.text.label),
            const SizedBox(height: FbSpace.xs),
            Text(value, style: context.text.bodyStrong.copyWith(fontSize: 18)),
          ],
        ),
      ),
    ),
  );
}

/// Change or delete one weight entry.
class WeightEditSheet extends ConsumerStatefulWidget {
  const WeightEditSheet({required this.entry, super.key});
  final WeightEntry entry;

  @override
  ConsumerState<WeightEditSheet> createState() => _WeightEditSheetState();
}

class _WeightEditSheetState extends ConsumerState<WeightEditSheet> {
  late String _text = formatMass(widget.entry.weightG, widget.entry.entryUnit);
  late DateTime _at = widget.entry.occurredAt.toLocal();
  late String _note = widget.entry.notes ?? '';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final grams = gramsFromText(_text, widget.entry.entryUnit);
    if (grams == null) {
      setState(() => _error = l10n.errInvalidNumber);
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(weightRepositoryProvider)
        .update(widget.entry.id, weightG: grams, occurredAt: _at, notes: _note);
    if (!mounted) return;
    if (result.isOk) {
      showFbSnackBar(context, l10n.saved);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = switch (result.failureOrNull?.code) {
          'out_of_range' => l10n.errOutOfRange,
          'in_future' => l10n.errInFuture,
          _ => l10n.errSaveFailed,
        };
      });
    }
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
    await ref.read(weightRepositoryProvider).delete(widget.entry.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = widget.entry.entryUnit;
    return FbSheetBody(
      title: l10n.editWeightTitle,
      trailing: TextButton(
        onPressed: _delete,
        style: TextButton.styleFrom(foregroundColor: context.colors.error),
        child: Text(l10n.delete),
      ),
      children: [
        FbTextField(
          label: l10n.weightFieldLabel,
          value: _text,
          suffix: unit == MassUnit.kg ? l10n.unitKg : l10n.unitLb,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: FbTextField.decimal,
          errorText: _error,
          onChanged: (v) => setState(() => _text = v),
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.dateLabel,
          value: _at,
          last: ref.read(clockProvider).now(),
          onChanged: (v) => setState(() => _at = v),
        ),
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

/// [LocalDate] helper for tests and other screens.
LocalDate weightRangeStart(LocalDate today, ChartRange range) => rangeStart(today, range.days);
