import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/setup_controller.dart';
import '../application/setup_draft.dart';

/// Turns a validation code into a sentence for the user.
String? fieldErrorText(AppLocalizations l10n, String? code) => switch (code) {
  null => null,
  'required' => l10n.errNameRequired,
  'invalid' || 'invalid_format' => l10n.errInvalidNumber,
  'too_long' => l10n.errTooLong,
  _ => l10n.errOutOfRange,
};

String fitnessGoalLabel(AppLocalizations l10n, String goal) => switch (goal) {
  FitnessGoalKeys.loseWeight => l10n.goalLoseWeight,
  FitnessGoalKeys.buildStrength => l10n.goalBuildStrength,
  FitnessGoalKeys.improveStamina => l10n.goalImproveStamina,
  FitnessGoalKeys.stayActive => l10n.goalStayActive,
  _ => goal,
};

String formatWakeTime(BuildContext context, String hhmm) {
  final parts = hhmm.split(':');
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// Name, birth date, height, units and (during onboarding) current weight.
class SetupProfileForm extends ConsumerWidget {
  const SetupProfileForm({
    required this.draft,
    required this.errors,
    this.showWeight = true,
    super.key,
  });

  final SetupDraft draft;
  final Map<String, String> errors;
  final bool showWeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(setupControllerProvider.notifier);
    final today = ref.watch(todayProvider);

    Future<void> pickDate() async {
      final initial = draft.dateOfBirth ?? LocalDate(today.year - 30, 1, 1);
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(initial.year, initial.month, initial.day),
        firstDate: DateTime(1900),
        lastDate: DateTime(today.year, today.month, today.day),
        initialEntryMode: DatePickerEntryMode.input,
      );
      if (picked != null) {
        controller.edit((d) => d.copyWith(dateOfBirth: () => LocalDate.fromDateTime(picked)));
      }
    }

    final height = FbTextField(
      label: l10n.heightLabel,
      optional: true,
      optionalLabel: l10n.optional,
      value: draft.heightText,
      suffix: draft.imperial ? l10n.unitIn : l10n.unitCm,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: FbTextField.decimal,
      errorText: fieldErrorText(l10n, errors['heightMm']),
      onChanged: (v) => controller.edit((d) => d.copyWith(heightText: v)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.unitsLabel, style: context.text.label),
        const SizedBox(height: 6),
        FbSegmented<bool>(
          semanticLabel: l10n.unitsLabel,
          options: {false: l10n.unitsMetric, true: l10n.unitsImperial},
          selected: draft.imperial,
          onChanged: (v) => controller.edit((d) => d.withImperial(v)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.nameLabel,
          value: draft.name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          errorText: fieldErrorText(l10n, errors['displayName']),
          onChanged: (v) => controller.edit((d) => d.copyWith(name: v)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbPickerField(
          label: l10n.dobLabel,
          optionalLabel: l10n.optional,
          hint: l10n.dobHint,
          valueText: switch (draft.dateOfBirth) {
            null => null,
            final d => DateFormat.yMMMMd().format(DateTime(d.year, d.month, d.day)),
          },
          onTap: pickDate,
          onClear: () => controller.edit((d) => d.copyWith(dateOfBirth: () => null)),
          clearLabel: l10n.clear,
        ),
        const SizedBox(height: FbSpace.lg),
        if (showWeight)
          FbFieldPair(
            first: height,
            second: FbTextField(
              label: l10n.weightLabel,
              optional: true,
              optionalLabel: l10n.optional,
              value: draft.weightText,
              suffix: draft.imperial ? l10n.unitLb : l10n.unitKg,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: FbTextField.decimal,
              textInputAction: TextInputAction.done,
              errorText: fieldErrorText(l10n, errors['weightG']),
              onChanged: (v) => controller.edit((d) => d.copyWith(weightText: v)),
            ),
          )
        else
          height,
      ],
    );
  }
}

/// Daily targets and fitness goals, with weight-based estimates (D7).
class SetupGoalsForm extends ConsumerWidget {
  const SetupGoalsForm({
    required this.draft,
    required this.errors,
    this.editing = false,
    super.key,
  });

  final SetupDraft draft;
  final Map<String, String> errors;

  /// True when opened from Settings instead of onboarding.
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(setupControllerProvider.notifier);
    final hasWeight = draft.weightG != null;
    const number = TextInputType.number;
    const decimal = TextInputType.numberWithOptions(decimal: true);

    Future<void> addOwnGoal() async {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => const _AddGoalDialog(),
      );
      final goal = text?.trim() ?? '';
      if (goal.isEmpty || draft.fitnessGoals.contains(goal)) return;
      controller.edit((d) => d.copyWith(fitnessGoals: [...d.fitnessGoals, goal]));
    }

    void toggleGoal(String goal) => controller.edit(
      (d) => d.copyWith(
        fitnessGoals: d.fitnessGoals.contains(goal)
            ? d.fitnessGoals.where((g) => g != goal).toList()
            : [...d.fitnessGoals, goal],
      ),
    );

    final customGoals = draft.fitnessGoals.where((g) => !FitnessGoalKeys.presets.contains(g));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbFieldPair(
          first: FbTextField(
            label: l10n.targetWeightLabel,
            value: draft.targetWeightText,
            hint: l10n.notSet,
            suffix: draft.imperial ? l10n.unitLb : l10n.unitKg,
            keyboardType: decimal,
            inputFormatters: FbTextField.decimal,
            errorText: fieldErrorText(l10n, errors['targetWeightG']),
            onChanged: (v) => controller.edit((d) => d.copyWith(targetWeightText: v)),
          ),
          second: FbTextField(
            label: l10n.dailyStepsLabel,
            value: draft.stepsText,
            hint: l10n.notSet,
            suffix: l10n.unitSteps,
            keyboardType: number,
            inputFormatters: FbTextField.digits,
            errorText: fieldErrorText(l10n, errors['dailySteps']),
            onChanged: (v) => controller.edit((d) => d.copyWith(stepsText: v)),
          ),
        ),
        const SizedBox(height: FbSpace.lg),
        FbFieldPair(
          first: FbTextField(
            label: l10n.dailyCaloriesLabel,
            value: draft.kcalText,
            hint: l10n.notSet,
            suffix: l10n.unitKcal,
            keyboardType: number,
            inputFormatters: FbTextField.digits,
            errorText: fieldErrorText(l10n, errors['energyKcalMilli']),
            onChanged: (v) => controller.edit((d) => d.copyWith(kcalText: v)),
          ),
          second: FbTextField(
            label: l10n.dailyProteinLabel,
            value: draft.proteinText,
            hint: l10n.notSet,
            suffix: l10n.unitG,
            keyboardType: number,
            inputFormatters: FbTextField.digits,
            errorText: fieldErrorText(l10n, errors['proteinMg']),
            onChanged: (v) => controller.edit((d) => d.copyWith(proteinText: v)),
          ),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.dailyWaterLabel,
          value: draft.waterText,
          hint: l10n.notSet,
          suffix: draft.imperial ? l10n.unitFlOz : l10n.unitMl,
          keyboardType: decimal,
          inputFormatters: FbTextField.decimal,
          textInputAction: TextInputAction.done,
          errorText: fieldErrorText(l10n, errors['dailyWaterMl']),
          onChanged: (v) => controller.edit((d) => d.copyWith(waterText: v)),
        ),
        const SizedBox(height: FbSpace.lg),
        if (hasWeight)
          FbNotice(
            l10n.estimateNotice,
            action: OutlinedButton(
              onPressed: controller.recalculate,
              child: Text(l10n.recalculate),
            ),
          )
        else
          FbNotice(editing ? l10n.estimateNeedsWeightEdit : l10n.estimateNeedsWeight),
        const SizedBox(height: FbSpace.xl),
        Text('${l10n.fitnessGoalsLabel} (${l10n.optional})', style: context.text.label),
        const SizedBox(height: FbSpace.sm),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final goal in [...FitnessGoalKeys.presets, ...customGoals])
              FbToggleChip(
                label: fitnessGoalLabel(l10n, goal),
                selected: draft.fitnessGoals.contains(goal),
                onTap: () => toggleGoal(goal),
              ),
            ActionChip(
              avatar: Icon(
                Icons.add_rounded,
                color: context.colors.textSecondary,
                size: FbSpace.xl,
              ),
              label: Text(l10n.addYourOwn),
              onPressed: addOwnGoal,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ),
      ],
    );
  }
}

class _AddGoalDialog extends StatefulWidget {
  const _AddGoalDialog();

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.addGoalTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        style: context.text.body,
        decoration: InputDecoration(hintText: l10n.addGoalHint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.add),
        ),
      ],
    );
  }
}

/// Wake-up time, sleep target, workout days and reminder choices.
class SetupDayForm extends ConsumerWidget {
  const SetupDayForm({required this.draft, required this.errors, super.key});

  final SetupDraft draft;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(setupControllerProvider.notifier);
    final narrow = DateFormat('EEEEE');
    final full = DateFormat('EEEE');
    // 5 January 2026 is a Monday.
    DateTime dayOf(int isoWeekday) => DateTime(2026, 1, 4 + isoWeekday);

    Future<void> pickTime() async {
      final current = draft.wakeTime?.split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: current == null
            ? const TimeOfDay(hour: 7, minute: 0)
            : TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])),
        initialEntryMode: TimePickerEntryMode.input,
      );
      if (picked != null) {
        final text =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        controller.edit((d) => d.copyWith(wakeTime: () => text));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbFieldPair(
          first: FbPickerField(
            label: l10n.wakeLabel,
            hint: l10n.wakeHint,
            valueText: switch (draft.wakeTime) {
              null => null,
              final t => formatWakeTime(context, t),
            },
            onTap: pickTime,
            onClear: () => controller.edit((d) => d.copyWith(wakeTime: () => null)),
            clearLabel: l10n.clear,
          ),
          second: FbTextField(
            label: l10n.sleepTargetLabel,
            value: draft.sleepHoursText,
            hint: l10n.notSet,
            suffix: l10n.unitHours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FbTextField.decimal,
            textInputAction: TextInputAction.done,
            errorText: fieldErrorText(l10n, errors['sleepTargetMin']),
            onChanged: (v) => controller.edit((d) => d.copyWith(sleepHoursText: v)),
          ),
        ),
        const SizedBox(height: FbSpace.xl),
        Text(l10n.workoutDaysLabel, style: context.text.label),
        const SizedBox(height: FbSpace.sm),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: FbSpace.sm,
          children: [
            for (var day = 1; day <= 7; day++)
              SizedBox.square(
                dimension: FbSize.touch,
                child: FbToggleChip(
                  circular: true,
                  label: narrow.format(dayOf(day)),
                  semanticLabel: full.format(dayOf(day)),
                  selected: draft.workoutDays.contains(day),
                  onTap: () => controller.edit(
                    (d) => d.copyWith(
                      workoutDays: d.workoutDays.contains(day)
                          ? d.workoutDays.difference({day})
                          : {...d.workoutDays, day},
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.xl),
        FbCard(
          padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
          child: Column(
            children: [
              FbSwitchRow(
                title: l10n.remindWaterTitle,
                subtitle: l10n.remindWaterSubtitle,
                value: draft.remindWater,
                onChanged: (v) => controller.edit((d) => d.copyWith(remindWater: v)),
              ),
              const Divider(indent: FbSpace.lg, endIndent: FbSpace.lg),
              FbSwitchRow(
                title: l10n.remindWorkoutTitle,
                subtitle: l10n.remindWorkoutSubtitle,
                value: draft.remindWorkout,
                onChanged: (v) => controller.edit((d) => d.copyWith(remindWorkout: v)),
              ),
              const Divider(indent: FbSpace.lg, endIndent: FbSpace.lg),
              FbSwitchRow(
                title: l10n.remindBedtimeTitle,
                subtitle: l10n.remindBedtimeSubtitle,
                value: draft.remindBedtime,
                onChanged: (v) => controller.edit((d) => d.copyWith(remindBedtime: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: FbSpace.md),
        Text(l10n.remindersLater, style: context.text.caption),
      ],
    );
  }
}
