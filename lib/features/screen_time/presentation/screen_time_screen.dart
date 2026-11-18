import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/screen_time_service.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/screen_time.dart';

enum _Range { day, week, month }

/// Screen time from Android's usage records, kept on the phone (§5.17).
class ScreenTimeScreen extends ConsumerStatefulWidget {
  const ScreenTimeScreen({super.key});

  @override
  ConsumerState<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends ConsumerState<ScreenTimeScreen> with WidgetsBindingObserver {
  _Range _range = _Range.day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the usage-access settings page: check again.
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    ref.invalidate(usageAccessProvider);
    if (await ref.read(usageAccessProvider.future)) {
      await ref.read(screenTimeServiceProvider).refresh(days: 31);
    }
  }

  Future<void> _write(ScreenTimeSettings s) async {
    await ref.read(screenTimeServiceProvider).write(s);
    ref.invalidate(screenTimeSettingsProvider);
  }

  Future<void> _editTarget(ScreenTimeSettings s) async {
    final l10n = context.l10n;
    var hours = (s.targetMinutes ?? 180) ~/ 60;
    var minutes = (s.targetMinutes ?? 180) % 60;
    final picked = await showTimePicker(
      context: context,
      helpText: l10n.dailyTarget,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      initialTime: TimeOfDay(hour: hours, minute: minutes),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    hours = picked.hour;
    minutes = picked.minute;
    final total = hours * 60 + minutes;
    await _write(
      ScreenTimeSettings(
        targetMinutes: total == 0 ? null : total,
        alerts: s.alerts,
        alertedOn: s.alertedOn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final access = ref.watch(usageAccessProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.screenTimeTitle)),
      body: switch (access) {
        AsyncData(value: false) => ListView(
          padding: const EdgeInsets.all(FbSpace.lg),
          children: [
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.usageAccessTitle, style: context.text.bodyStrong),
                  const SizedBox(height: FbSpace.sm),
                  Text(l10n.usageAccessBody, style: context.text.body),
                  const SizedBox(height: FbSpace.md),
                  FilledButton(
                    onPressed: () => unawaited(ref.read(usageReaderProvider).openAccessSettings()),
                    child: Text(l10n.openUsageSettings),
                  ),
                  TextButton(onPressed: _recheck, child: Text(l10n.checkAgain)),
                ],
              ),
            ),
          ],
        ),
        AsyncData() => _body(context),
        _ => const FbLoading(),
      },
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final from = switch (_range) {
      _Range.day => today,
      _Range.week => today.addDays(-6),
      _Range.month => today.addDays(-29),
    };
    final days =
        ref.watch(screenTimeDaysProvider((from: from, to: today))).value ?? const <ScreenTimeDay>[];
    final apps =
        ref.watch(screenTimeAppsProvider((from: from, to: today))).value ?? const <AppMinutes>[];
    final settings = ref.watch(screenTimeSettingsProvider).value ?? const ScreenTimeSettings();
    final total = days.fold(0, (n, d) => n + d.totalMs);
    final count = _range == _Range.day ? 1 : (_range == _Range.week ? 7 : 30);
    final byDay = {for (final d in days) d.date: d.totalMs};
    String dur(int ms) => context.duration(Duration(milliseconds: ms));
    return RefreshIndicator(
      onRefresh: () => ref.read(screenTimeServiceProvider).refresh(days: 31),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSegmented<_Range>(
            options: {_Range.day: l10n.today, _Range.week: l10n.week, _Range.month: l10n.month},
            selected: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _range == _Range.day ? l10n.screenTimeToday : l10n.dailyAverage,
                    style: context.text.bodySmall,
                  ),
                  Text(dur(total ~/ count), style: context.text.title),
                  if (settings.targetMinutes != null)
                    Text(
                      l10n.targetIs(dur(settings.targetMinutes! * 60000)),
                      style: context.text.caption,
                    ),
                ],
              ),
            ),
          ),
          if (_range != _Range.day) ...[
            const SizedBox(height: FbSpace.md),
            FbChartCard(
              summary: l10n.screenTimeChartSummary(count, dur(total ~/ count)),
              chart: FbBarChart(
                values: [for (var i = 0; i < count; i++) (byDay[from.addDays(i)] ?? 0) / 3600000],
                target: settings.targetMinutes == null ? null : settings.targetMinutes! / 60,
                bottomLabel: (i) => count == 7
                    ? context.dayLabel(from.addDays(i)).characters.take(3).toString()
                    : (i % 5 == 0 ? '${from.addDays(i).day}' : ''),
                leftLabel: (y) => l10n.hoursShort(y.round()),
              ),
            ),
          ],
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.mostUsedApps),
          const SizedBox(height: FbSpace.sm),
          if (apps.isEmpty)
            FbEmptyHint(l10n.noUsageYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final a in apps.take(10))
                  FbListRow(
                    title: a.label,
                    trailing: Text(dur(a.foregroundMs ~/ count), style: context.text.body),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.lg),
          FbCard(
            child: Column(
              children: [
                FbListRow(
                  title: l10n.dailyTarget,
                  subtitle: settings.targetMinutes == null
                      ? l10n.noTarget
                      : dur(settings.targetMinutes! * 60000),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editTarget(settings),
                ),
                FbSwitchRow(
                  title: l10n.screenTimeAlerts,
                  subtitle: l10n.screenTimeAlertsHelp,
                  value: settings.alerts,
                  onChanged: settings.targetMinutes == null
                      ? null
                      : (v) => _write(
                          ScreenTimeSettings(
                            targetMinutes: settings.targetMinutes,
                            alerts: v,
                            alertedOn: settings.alertedOn,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.screenTimeNote, style: context.text.caption),
        ],
      ),
    );
  }
}
