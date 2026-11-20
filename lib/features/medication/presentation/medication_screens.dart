import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/routine/schedule_editor.dart';
import '../../../app/routine_providers.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/medication.dart';

String _time(BuildContext context, int minute) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: minute ~/ 60, minute: minute % 60));

/// Medication and supplements: today's doses and the list (§5.18).
class MedicationScreen extends ConsumerWidget {
  const MedicationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final meds = ref.watch(medicationsProvider).value ?? const <Medication>[];
    final logs = ref.watch(doseLogsProvider((from: today, to: today))).value ?? const <DoseLog>[];
    final now = ref.watch(clockProvider).now();
    final doses = dosesOn(today, meds, logs, today: today, nowMinute: now.hour * 60 + now.minute);
    Future<void> record(Dose d, DoseStatus s) async {
      final r = await ref
          .read(medicationRepositoryProvider)
          .record(d.medication.id, day: today, slot: d.minute, status: s);
      if (context.mounted && !r.isOk) showFbSnackBar(context, l10n.errSaveFailed);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.medicationTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              onPressed: () => context.push(Routes.medicationEdit('new')),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.add),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSectionTitle(l10n.today),
          const SizedBox(height: FbSpace.sm),
          if (doses.isEmpty)
            FbEmptyHint(meds.isEmpty ? l10n.medicationEmpty : l10n.noDosesToday, boxed: true)
          else
            FbListCard(
              children: [
                for (final d in doses)
                  FbListRow(
                    title: '${_time(context, d.minute)} · ${d.medication.name}',
                    subtitle:
                        '${d.medication.dosageText} · ${switch (d.state) {
                          DoseState.taken => l10n.doseTaken,
                          DoseState.skipped => l10n.stateSkipped,
                          DoseState.notTaken => l10n.doseNotTaken,
                          DoseState.due => l10n.stateDue,
                        }}',
                    trailing: d.state == DoseState.taken
                        ? IconButton(
                            tooltip: l10n.undoTaken,
                            onPressed: () => record(d, DoseStatus.missed),
                            icon: Icon(Icons.check_circle_rounded, color: context.colors.primary),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(onPressed: () => record(d, DoseStatus.skipped), child: Text(l10n.skip)),
                              FilledButton(onPressed: () => record(d, DoseStatus.taken), child: Text(l10n.taken)),
                            ],
                          ),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.lg),
          FbSectionTitle(l10n.medicationList),
          const SizedBox(height: FbSpace.sm),
          if (meds.isEmpty)
            FbEmptyHint(l10n.medicationEmpty, boxed: true)
          else
            FbListCard(
              children: [
                for (final m in meds)
                  FbListRow(
                    title: m.name,
                    subtitle: [m.dosageText, if (!m.active) l10n.paused].join(' · '),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.medicationEdit(m.id)),
                  ),
              ],
            ),
          const SizedBox(height: FbSpace.md),
          Text(l10n.medicationNote, style: context.text.caption),
        ],
      ),
    );
  }
}

/// Add or edit one medicine or supplement.
class MedicationEditorScreen extends ConsumerStatefulWidget {
  const MedicationEditorScreen({this.id, super.key});
  final String? id;

  @override
  ConsumerState<MedicationEditorScreen> createState() => _MedicationEditorScreenState();
}

class _MedicationEditorScreenState extends ConsumerState<MedicationEditorScreen> {
  Medication? _existing;
  bool _loaded = false;
  String _name = '';
  String _dosage = '';
  String _notes = '';
  bool _remind = true;
  bool _active = true;
  ScheduleRule? _rule = Daily(times: const [8 * 60]);
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final id = widget.id;
    if (id == null) {
      _loaded = true;
      return;
    }
    ref.read(medicationRepositoryProvider).all().then((all) {
      final m = all.where((x) => x.id == id).firstOrNull;
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _existing = m;
        if (m != null) {
          _name = m.name;
          _dosage = m.dosageText;
          _notes = m.notes ?? '';
          _remind = m.remind;
          _active = m.active;
          _rule = m.rule;
        }
      });
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() => _tried = true);
    final rule = _rule;
    if (rule == null || _name.trim().isEmpty || _dosage.trim().isEmpty) return;
    final draft = Medication(
      id: _existing?.id ?? '',
      name: _name.trim(),
      dosageText: _dosage.trim(),
      rule: rule,
      remind: _remind,
      notes: _notes.trim().isEmpty ? null : _notes.trim(),
      active: _active,
    );
    if (draft.problems.isNotEmpty) return;
    final repo = ref.read(medicationRepositoryProvider);
    final ok = _existing == null ? (await repo.create(draft)).isOk : (await repo.update(draft)).isOk;
    if (!mounted) return;
    if (!ok) {
      showFbSnackBar(context, l10n.errSaveFailed);
      return;
    }
    replanReminders(ref);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_loaded) return Scaffold(appBar: AppBar(), body: const FbLoading());
    final today = ref.watch(todayProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? l10n.addMedication : l10n.editMedication),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: l10n.delete,
              onPressed: () async {
                final ok = await showFbConfirm(
                  context,
                  title: l10n.deleteMedicationTitle,
                  message: l10n.deleteMedicationMessage,
                  confirmLabel: l10n.delete,
                  cancelLabel: l10n.cancel,
                );
                if (!ok) return;
                await ref.read(medicationRepositoryProvider).delete(_existing!.id);
                replanReminders(ref);
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbTextField(
            label: l10n.nameLabel,
            value: _name,
            onChanged: (v) => setState(() => _name = v),
            errorText: _tried && _name.trim().isEmpty ? l10n.errNameRequired : null,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: FbSpace.md),
          FbTextField(
            label: l10n.dosageLabel,
            hint: l10n.dosageHint,
            value: _dosage,
            onChanged: (v) => setState(() => _dosage = v),
            errorText: _tried && _dosage.trim().isEmpty ? l10n.errDosageRequired : null,
          ),
          const SizedBox(height: FbSpace.lg),
          ScheduleEditor(
            initial: _rule ?? Daily(times: const [8 * 60]),
            today: today,
            label: l10n.whenLabel,
            onChanged: (r) => setState(() => _rule = r),
          ),
          const SizedBox(height: FbSpace.md),
          FbSwitchRow(
            title: l10n.remindMe,
            subtitle: l10n.medicationReminderHelp,
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
          ),
          FbSwitchRow(title: l10n.activeLabel, value: _active, onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: FbSpace.md),
          FbTextField(
            label: l10n.notesLabel,
            value: _notes,
            optional: true,
            optionalLabel: l10n.optional,
            onChanged: (v) => _notes = v,
          ),
          const SizedBox(height: FbSpace.lg),
          FbPrimaryButton(label: l10n.save, onPressed: _save),
          const SizedBox(height: FbSpace.md),
          Text(l10n.medicationNote, style: context.text.caption),
        ],
      ),
    );
  }
}
