import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/routine_providers.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../reminders/domain/reminder.dart';
import '../domain/recovery.dart';

/// Posture and recovery (§5.19): rest day, ratings, break reminders.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  bool? _rest;
  int? _soreness;
  int? _recovery;
  String? _notes;
  bool _edited = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final today = ref.read(todayProvider);
    final saved = ref.read(recoveryDayProvider(today)).value;
    final r = await ref
        .read(recoveryRepositoryProvider)
        .save(
          RecoveryLog(
            date: today,
            isRestDay: _rest ?? saved?.isRestDay ?? false,
            soreness: _edited ? _soreness : saved?.soreness,
            recovery: _edited ? _recovery : saved?.recovery,
            notes: (_notes ?? saved?.notes ?? '').trim().isEmpty ? null : (_notes ?? saved?.notes)!.trim(),
          ),
        );
    if (mounted) showFbSnackBar(context, r.isOk ? l10n.saved : l10n.errSaveFailed);
  }

  /// The break reminder of [kind]: posture breaks or movement breaks, found
  /// by their preset title.
  Reminder? _find(List<Reminder> all, String title) =>
      all.where((r) => r.kind == ReminderKind.posture && r.title == title).firstOrNull;

  Future<void> _toggle(String title, int everyMinutes, bool on) async {
    final repo = ref.read(reminderRepositoryProvider);
    final existing = _find(ref.read(remindersProvider).value ?? const [], title);
    if (existing != null) {
      await repo.setEnabled(existing.id, enabled: on);
    } else if (on) {
      await repo.create(
        reminderPreset(ReminderKind.posture, title: title, today: ref.read(todayProvider)).copyWith(
          rule: IntervalRule(everyMinutes: everyMinutes, start: 9 * 60, end: 17 * 60, weekdays: const {1, 2, 3, 4, 5}),
        ),
      );
    }
    replanReminders(ref);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final saved = ref.watch(recoveryDayProvider(today)).value;
    final recent = ref.watch(recoveryRecentProvider).value ?? const <RecoveryLog>[];
    final reminders = ref.watch(remindersProvider).value ?? const <Reminder>[];
    final posture = _find(reminders, l10n.presetPosture);
    final movement = _find(reminders, l10n.movementBreak);
    final soreness = _edited ? _soreness : saved?.soreness;
    final recovery = _edited ? _recovery : saved?.recovery;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoveryTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.dayLabel(today), style: context.text.bodyStrong),
                FbSwitchRow(
                  title: l10n.restDay,
                  value: _rest ?? saved?.isRestDay ?? false,
                  onChanged: (v) => setState(() => _rest = v),
                ),
                FbScoreRow(
                  label: l10n.sorenessLabel,
                  value: soreness,
                  onChanged: (v) => setState(() {
                    _edited = true;
                    _soreness = v;
                    _recovery = recovery;
                  }),
                ),
                FbScoreRow(
                  label: l10n.recoveryLabel,
                  value: recovery,
                  onChanged: (v) => setState(() {
                    _edited = true;
                    _recovery = v;
                    _soreness = soreness;
                  }),
                ),
                const SizedBox(height: FbSpace.sm),
                FbTextField(
                  key: ValueKey(saved?.notes),
                  label: l10n.notesLabel,
                  value: _notes ?? saved?.notes ?? '',
                  optional: true,
                  optionalLabel: l10n.optional,
                  onChanged: (v) => _notes = v,
                ),
                const SizedBox(height: FbSpace.md),
                FbPrimaryButton(label: l10n.save, onPressed: _save),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.breakReminders),
          const SizedBox(height: FbSpace.sm),
          FbCard(
            child: Column(
              children: [
                FbSwitchRow(
                  title: l10n.movementBreak,
                  subtitle: l10n.movementBreakHelp,
                  value: movement?.enabled ?? false,
                  onChanged: (v) => _toggle(l10n.movementBreak, 60, v),
                ),
                FbSwitchRow(
                  title: l10n.presetPosture,
                  subtitle: l10n.postureBreakHelp,
                  value: posture?.enabled ?? false,
                  onChanged: (v) => _toggle(l10n.presetPosture, 120, v),
                ),
                if (posture != null || movement != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(Routes.editReminder((movement ?? posture)!.id)),
                      child: Text(l10n.changeTimes),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.historyTitle),
          const SizedBox(height: FbSpace.sm),
          if (recent.isEmpty)
            FbEmptyHint(l10n.noHistoryYet, boxed: true)
          else
            FbListCard(
              children: [
                for (final r in recent)
                  FbListRow(
                    title: context.dayLabel(r.date, today: today),
                    subtitle: [
                      if (r.isRestDay) l10n.restDay,
                      if (r.soreness != null) l10n.sorenessValue(r.soreness!),
                      if (r.recovery != null) l10n.recoveryValue(r.recovery!),
                    ].join(' · '),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.recoveryNote, style: context.text.caption),
        ],
      ),
    );
  }
}
