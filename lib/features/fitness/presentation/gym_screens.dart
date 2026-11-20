import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fitness_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/units/decimal_text.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/workouts.dart';
import 'fitness_labels.dart';

const _restOptions = [60, 90, 120, 180];

/// A gym workout, live or finished (approved design "Gym workout in progress").
class GymWorkoutScreen extends ConsumerStatefulWidget {
  const GymWorkoutScreen({required this.id, super.key});
  final String id;

  @override
  ConsumerState<GymWorkoutScreen> createState() => _GymWorkoutScreenState();
}

class _GymWorkoutScreenState extends ConsumerState<GymWorkoutScreen> {
  Timer? _tick;
  DateTime? _restEndsAt;
  int _restLength = 90;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _restEndsAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now();

  void _startRest() => setState(() => _restEndsAt = _now.add(Duration(seconds: _restLength)));

  Future<void> _addExercise(WorkoutSession s) async {
    final picked = await showFbSheet<Exercise>(context, const ExercisePickerSheet());
    if (picked == null) return;
    final repo = ref.read(workoutRepositoryProvider);
    final we = (await repo.addExercise(s.id, picked.id)).valueOrNull;
    if (we != null) await repo.addSet(we, _blank(picked));
  }

  SetDraft _blank(Exercise e, [ExerciseSet? like]) => (
    reps: like?.reps,
    loadG: like?.loadG,
    entryUnit: 'kg',
    distanceM: like?.distanceM,
    durationS: like?.durationS,
    restS: null,
    done: false,
  );

  Future<void> _finish(WorkoutSession s) async {
    final l10n = context.l10n;
    await ref.read(workoutRepositoryProvider).finishGym(s.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.workoutSaved);
    context.pop();
  }

  Future<void> _menu(WorkoutSession s, String action) async {
    final l10n = context.l10n;
    final repo = ref.read(workoutRepositoryProvider);
    switch (action) {
      case 'duplicate':
        final id = (await repo.duplicate(s.id)).valueOrNull;
        if (id != null && mounted) context.pushReplacement(Routes.workout(id));
      case 'template':
        final name = await _askName(l10n.saveAsTemplate, s.name);
        if (name == null) return;
        final r = await repo.saveTemplate(s.id, name);
        if (mounted) showFbSnackBar(context, r.isOk ? l10n.templateSaved : l10n.errSaveFailed);
      case 'rename':
        final name = await _askName(l10n.renameWorkout, s.name);
        if (name != null && name.trim().isNotEmpty) await repo.updateSession(s.id, name: name);
      case 'delete':
        final ok = await showFbConfirm(
          context,
          title: l10n.deleteWorkoutTitle,
          message: l10n.deleteWorkoutMessage,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
        );
        if (!ok) return;
        await repo.deleteSession(s.id);
        if (mounted) {
          showFbSnackBar(context, l10n.deleted);
          context.pop();
        }
    }
  }

  Future<String?> _askName(String title, String initial) {
    final controller = TextEditingController(text: initial);
    final l10n = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(workoutProvider(widget.id));
    final s = async.value;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const FbLoading() : FbErrorState(message: l10n.workoutMissing),
      );
    }
    final rest = _restEndsAt?.difference(_now);
    final resting = rest != null && !rest.isNegative;
    final done = s.entries.where((e) => e.sets.isNotEmpty && e.sets.every((x) => x.done)).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          if (s.inProgress)
            Padding(
              padding: const EdgeInsets.only(right: FbSpace.xs),
              child: FilledButton(onPressed: () => _finish(s), child: Text(l10n.finish)),
            ),
          PopupMenuButton<String>(
            tooltip: l10n.moreActions(s.name),
            onSelected: (a) => _menu(s, a),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.renameWorkout)),
              PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicateMeal)),
              PopupMenuItem(value: 'template', child: Text(l10n.saveAsTemplate)),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Text(
            [
              l10n.startedAt(context.time(s.startedAt)),
              if (s.inProgress)
                context.duration(_now.toUtc().difference(s.startedAt))
              else
                context.duration(Duration(seconds: s.durationS)),
              l10n.exercisesDone(done, s.entries.length),
            ].join(' · '),
            style: context.text.caption,
          ),
          const SizedBox(height: FbSpace.md),
          if (s.inProgress) ...[
            FbCard(
              child: resting
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.restLeft(
                              clockLabel(rest),
                              clockLabel(Duration(seconds: _restLength)),
                            ),
                            style: context.text.bodyStrong,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => setState(
                            () => _restEndsAt = _restEndsAt!.add(const Duration(seconds: 30)),
                          ),
                          child: Text(l10n.plus30s),
                        ),
                        const SizedBox(width: FbSpace.xs),
                        OutlinedButton(
                          onPressed: () => setState(() => _restEndsAt = null),
                          child: Text(l10n.actionSkip),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: Text(l10n.restTimer, style: context.text.bodyStrong)),
                        DropdownButton<int>(
                          value: _restLength,
                          items: [
                            for (final r in _restOptions)
                              DropdownMenuItem(
                                value: r,
                                child: Text(clockLabel(Duration(seconds: r))),
                              ),
                          ],
                          onChanged: (v) => setState(() => _restLength = v!),
                        ),
                        const SizedBox(width: FbSpace.sm),
                        OutlinedButton(onPressed: _startRest, child: Text(l10n.start)),
                      ],
                    ),
            ),
            const SizedBox(height: FbSpace.md),
          ],
          if (s.entries.isEmpty) FbEmptyHint(l10n.noExercisesYet, boxed: true),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final ids = [for (final e in s.entries) e.id];
              final moved = ids.removeAt(from);
              ids.insert(to, moved);
              unawaited(ref.read(workoutRepositoryProvider).reorderExercises(s.id, ids));
            },
            children: [
              for (final (i, e) in s.entries.indexed)
                Padding(
                  key: ValueKey(e.id),
                  padding: const EdgeInsets.only(bottom: FbSpace.md),
                  child: _ExerciseCard(
                    entry: e,
                    index: i,
                    onSetDone: _startRest,
                    blank: (like) => _blank(e.exercise, like),
                  ),
                ),
            ],
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => _addExercise(s),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addExercise),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required this.entry,
    required this.index,
    required this.onSetDone,
    required this.blank,
  });
  final WorkoutEntry entry;
  final int index;
  final VoidCallback onSetDone;
  final SetDraft Function(ExerciseSet? like) blank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final e = entry.exercise;
    final progress = ref.watch(exerciseProgressProvider(e)).value;
    final best = progress?.records.where((r) => r.kind.name == 'highestLoad').firstOrNull;
    final repo = ref.read(workoutRepositoryProvider);
    return FbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  label: l10n.reorderHandle(e.name),
                  child: const SizedBox(
                    width: FbSize.touch,
                    height: FbSize.touch,
                    child: Icon(Icons.drag_indicator_rounded),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: context.text.bodyStrong),
                    Text(
                      [
                        measurementName(l10n, e.measurementKind),
                        if (best != null) l10n.recordShort(kgLabel(context, best.value)),
                      ].join(' · '),
                      style: context.text.caption,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.removeExercise(e.name),
                onPressed: () async {
                  final ok = await showFbConfirm(
                    context,
                    title: l10n.removeExerciseTitle,
                    message: l10n.removeExerciseMessage,
                    confirmLabel: l10n.remove,
                    cancelLabel: l10n.cancel,
                  );
                  if (ok) await repo.removeExercise(entry.id);
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          for (final set in entry.sets)
            _SetRow(set: set, kind: e.measurementKind, onDone: onSetDone),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => repo.addSet(entry.id, blank(entry.sets.lastOrNull)),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addSet),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetRow extends ConsumerWidget {
  const _SetRow({required this.set, required this.kind, required this.onDone});
  final ExerciseSet set;
  final MeasurementKind kind;
  final VoidCallback onDone;

  SetDraft _draft({int? reps, int? loadG, int? durationS, int? distanceM, bool? done}) => (
    reps: reps ?? set.reps,
    loadG: loadG ?? set.loadG,
    entryUnit: 'kg',
    distanceM: distanceM ?? set.distanceM,
    durationS: durationS ?? set.durationS,
    restS: set.restS,
    done: done ?? set.done,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(workoutRepositoryProvider);
    Widget field(String label, String value, String? suffix, ValueChanged<String> onChanged) =>
        Expanded(
          child: _SetField(label: label, value: value, suffix: suffix, onChanged: onChanged),
        );
    final fields = switch (kind) {
      MeasurementKind.weightReps => [
        field(
          l10n.unitKg,
          set.loadG == null ? '' : formatScaled(set.loadG!, 3, decimals: 1),
          null,
          (v) {
            final g = parseScaled(v, 3);
            if (g != null) unawaited(repo.updateSet(set.id, _draft(loadG: g)));
          },
        ),
        const SizedBox(width: FbSpace.sm),
        field(l10n.repsLabel, set.reps?.toString() ?? '', null, (v) {
          final r = int.tryParse(v);
          if (r != null) unawaited(repo.updateSet(set.id, _draft(reps: r)));
        }),
      ],
      MeasurementKind.repsOnly => [
        field(l10n.repsLabel, set.reps?.toString() ?? '', null, (v) {
          final r = int.tryParse(v);
          if (r != null) unawaited(repo.updateSet(set.id, _draft(reps: r)));
        }),
      ],
      MeasurementKind.duration => [
        field(l10n.secondsLabel, set.durationS?.toString() ?? '', null, (v) {
          final d = int.tryParse(v);
          if (d != null) unawaited(repo.updateSet(set.id, _draft(durationS: d)));
        }),
      ],
      MeasurementKind.distanceDuration => [
        field(
          l10n.unitKm,
          set.distanceM == null ? '' : formatScaled(set.distanceM!, 3, decimals: 2),
          null,
          (v) {
            final m = parseScaled(v, 3);
            if (m != null) unawaited(repo.updateSet(set.id, _draft(distanceM: m)));
          },
        ),
        const SizedBox(width: FbSpace.sm),
        field(l10n.minutesLabel, set.durationS == null ? '' : '${set.durationS! ~/ 60}', null, (v) {
          final m = int.tryParse(v);
          if (m != null) unawaited(repo.updateSet(set.id, _draft(durationS: m * 60)));
        }),
      ],
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('${set.setNumber}', style: context.text.caption)),
          ...fields,
          const SizedBox(width: FbSpace.xs),
          Checkbox(
            value: set.done,
            semanticLabel: l10n.setDoneLabel(set.setNumber),
            onChanged: (v) {
              unawaited(repo.updateSet(set.id, _draft(done: v)));
              if (v ?? false) onDone();
            },
          ),
          IconButton(
            tooltip: l10n.removeSet(set.setNumber),
            onPressed: () => repo.removeSet(set.id),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// A small numeric field that saves when editing finishes.
class _SetField extends StatefulWidget {
  const _SetField({required this.label, required this.value, required this.onChanged, this.suffix});
  final String label;
  final String value;
  final String? suffix;
  final ValueChanged<String> onChanged;

  @override
  State<_SetField> createState() => _SetFieldState();
}

class _SetFieldState extends State<_SetField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()..addListener(_commit);

  void _commit() {
    if (!_focus.hasFocus && _c.text != widget.value) widget.onChanged(_c.text.trim());
  }

  @override
  void didUpdateWidget(_SetField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _focus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => widget.onChanged(_c.text.trim()),
    decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix, isDense: true),
  );
}

/// Pick an exercise to add (search and filter as in "Exercise library").
class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  ConsumerState<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if (q.isEmpty || e.name.toLowerCase().contains(q) || e.muscleGroup.contains(q)) e,
    ];
    return FbSheetBody(
      title: l10n.addExercise,
      children: [
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.searchExercises,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: FbSpace.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in shown)
                ListTile(
                  title: Text(e.name),
                  subtitle: Text('${e.muscleGroup} · ${e.equipment}'),
                  onTap: () => Navigator.of(context).pop(e),
                ),
              if (shown.isEmpty) FbEmptyHint(l10n.noExercisesFound),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final created = await showFbSheet<Exercise>(context, const ExerciseEditorSheet());
            if (created != null && context.mounted) Navigator.of(context).pop(created);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.newExercise),
        ),
      ],
    );
  }
}

const _muscleGroups = ['chest', 'back', 'shoulders', 'arms', 'legs', 'glutes', 'core', 'full body'];

/// Create or edit one of your own exercises.
class ExerciseEditorSheet extends ConsumerStatefulWidget {
  const ExerciseEditorSheet({this.existing, super.key});
  final Exercise? existing;

  @override
  ConsumerState<ExerciseEditorSheet> createState() => _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends ConsumerState<ExerciseEditorSheet> {
  late String _name = widget.existing?.name ?? '';
  late String _muscle = widget.existing?.muscleGroup ?? 'chest';
  late String _equipment = widget.existing?.equipment ?? '';
  late String _instructions = widget.existing?.instructions ?? '';
  late MeasurementKind _kind = widget.existing?.measurementKind ?? MeasurementKind.weightReps;
  String? _error;

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.trim().isEmpty) return setState(() => _error = l10n.errRequired);
    final draft = Exercise(
      id: widget.existing?.id ?? '',
      name: _name,
      category: _kind == MeasurementKind.distanceDuration ? 'cardio' : 'strength',
      muscleGroup: _muscle,
      equipment: _equipment.trim().isEmpty ? l10n.equipmentNone : _equipment,
      instructions: _instructions,
      isCustom: true,
      measurementKind: _kind,
    );
    final repo = ref.read(workoutRepositoryProvider);
    if (widget.existing == null) {
      final r = await repo.createExercise(draft);
      if (!mounted) return;
      if (r.valueOrNull == null) return setState(() => _error = l10n.errSaveFailed);
      showFbSnackBar(context, l10n.exerciseSaved);
      Navigator.of(context).pop(r.valueOrNull);
    } else {
      final r = await repo.updateExercise(draft);
      if (!mounted) return;
      if (!r.isOk) return setState(() => _error = l10n.errSaveFailed);
      showFbSnackBar(context, l10n.exerciseSaved);
      Navigator.of(context).pop(draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: widget.existing == null ? l10n.newExercise : l10n.editExercise,
      children: [
        FbTextField(
          label: l10n.nameLabel,
          value: _name,
          onChanged: (v) => _name = v,
          errorText: _error,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: FbSpace.md),
        Text(l10n.muscleGroup, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final m in _muscleGroups)
              FbToggleChip(
                label: m,
                selected: _muscle == m,
                onTap: () => setState(() => _muscle = m),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        Text(l10n.measuredAs, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final k in MeasurementKind.values)
              FbToggleChip(
                label: measurementName(l10n, k),
                selected: _kind == k,
                onTap: () => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        FbTextField(
          label: l10n.equipmentLabel,
          value: _equipment,
          onChanged: (v) => _equipment = v,
          optional: true,
          optionalLabel: l10n.optional,
        ),
        const SizedBox(height: FbSpace.md),
        FbTextField(
          label: l10n.instructionsLabel,
          value: _instructions,
          onChanged: (v) => _instructions = v,
          optional: true,
          optionalLabel: l10n.optional,
        ),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save),
      ],
    );
  }
}

/// Exercise library (approved design).
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  String _query = '';
  String? _group;
  bool _mine = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(exercisesProvider);
    final all = async.value;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in all ?? const <Exercise>[])
        if ((q.isEmpty || e.name.toLowerCase().contains(q)) &&
            (_group == null || e.muscleGroup == _group) &&
            (!_mine || e.isCustom))
          e,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.exerciseLibrary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              onPressed: () => showFbSheet<Exercise>(context, const ExerciseEditorSheet()),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.newShort),
            ),
          ),
        ],
      ),
      body: all == null
          ? const FbLoading()
          : ListView(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.searchExercises,
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: FbSpace.sm),
                Wrap(
                  spacing: FbSpace.sm,
                  runSpacing: FbSpace.sm,
                  children: [
                    FbToggleChip(
                      label: l10n.filterAll,
                      selected: _group == null && !_mine,
                      onTap: () => setState(() {
                        _group = null;
                        _mine = false;
                      }),
                    ),
                    for (final m in const ['chest', 'back', 'legs', 'core'])
                      FbToggleChip(
                        label: m,
                        selected: _group == m,
                        onTap: () => setState(() {
                          _group = m;
                          _mine = false;
                        }),
                      ),
                    FbToggleChip(
                      label: l10n.filterMine,
                      selected: _mine,
                      onTap: () => setState(() {
                        _group = null;
                        _mine = true;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: FbSpace.md),
                if (shown.isEmpty)
                  FbEmptyHint(l10n.noExercisesFound, boxed: true)
                else
                  FbListCard(
                    children: [
                      for (final e in shown)
                        FbListRow(
                          title: e.isCustom ? l10n.yoursName(e.name) : e.name,
                          subtitle:
                              '${e.muscleGroup} · ${e.equipment} · ${measurementName(l10n, e.measurementKind)}',
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push(Routes.exercise(e.id)),
                        ),
                    ],
                  ),
                const SizedBox(height: FbSpace.md),
                Text(l10n.libraryNote, style: context.text.caption),
              ],
            ),
    );
  }
}
