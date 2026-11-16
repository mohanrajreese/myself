import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/setup_controller.dart';
import '../application/setup_draft.dart';
import 'setup_forms.dart';

/// The steps after sign-in. Sign-in is step 1 of [_total].
enum OnboardingStep { profile, goals, day, permissions, summary }

const _total = 6;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.step, super.key});
  final OnboardingStep step;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.step == OnboardingStep.goals) {
      // Fill weight-based targets once the draft has loaded.
      ref.read(setupControllerProvider.future).then((_) {
        if (mounted) ref.read(setupControllerProvider.notifier).prepareGoals();
      });
    }
  }

  String get _path => Routes.onboardingSteps[widget.step.index];

  Future<void> _continue() async {
    // Read the draft now, not when the button was built: the latest
    // keystroke may not have been painted yet.
    final draft = ref.read(setupControllerProvider).value;
    if (draft == null) return;
    final controller = ref.read(setupControllerProvider.notifier);
    final errors = switch (widget.step) {
      OnboardingStep.profile => draft.profileErrors(today: ref.read(todayProvider)),
      OnboardingStep.goals => draft.goalErrors(),
      OnboardingStep.day => draft.dayErrors(),
      _ => const <String, String>{},
    };
    setState(() {
      _errors = errors;
      _saveFailed = false;
    });
    if (errors.isNotEmpty) return;

    if (widget.step == OnboardingStep.summary) {
      setState(() => _busy = true);
      final result = await controller.finishOnboarding();
      if (!mounted) return;
      // On success the router leaves onboarding by itself.
      setState(() {
        _busy = false;
        _saveFailed = !result.isOk;
      });
      return;
    }

    final next = Routes.onboardingSteps[widget.step.index + 1];
    await controller.persistDraft(nextPath: next);
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draftState = ref.watch(setupControllerProvider);
    final draft = draftState.value;
    if (draft == null) {
      return Scaffold(body: FbLoading(semanticLabel: l10n.loading));
    }

    final (title, subtitle) = switch (widget.step) {
      OnboardingStep.profile => (l10n.profileTitle, l10n.profileSubtitle),
      OnboardingStep.goals => (l10n.goalsTitle, l10n.goalsSubtitle),
      OnboardingStep.day => (l10n.dayTitle, l10n.daySubtitle),
      OnboardingStep.permissions => (l10n.permTitle, l10n.permSubtitle),
      OnboardingStep.summary => (l10n.summaryTitle, l10n.summarySubtitle),
    };

    return FbStepScaffold(
      key: ValueKey(_path),
      current: widget.step.index + 2,
      total: _total,
      title: title,
      subtitle: subtitle,
      onBack: widget.step == OnboardingStep.profile
          ? null
          : () => context.go(Routes.onboardingSteps[widget.step.index - 1]),
      primaryLabel: widget.step == OnboardingStep.summary ? l10n.finishSetup : l10n.continueLabel,
      onPrimary: _continue,
      busy: _busy,
      notice: _saveFailed
          ? FbNotice(l10n.errSaveFailed, isError: true)
          : (_errors.isNotEmpty ? FbNotice(l10n.errCheckFields, isError: true) : null),
      child: switch (widget.step) {
        OnboardingStep.profile => SetupProfileForm(draft: draft, errors: _errors),
        OnboardingStep.goals => SetupGoalsForm(draft: draft, errors: _errors),
        OnboardingStep.day => SetupDayForm(draft: draft, errors: _errors),
        OnboardingStep.permissions => const _PermissionsList(),
        OnboardingStep.summary => _Summary(draft: draft),
      },
    );
  }
}

/// Explains each permission. Nothing is requested here (PRD §4.1).
class _PermissionsList extends StatelessWidget {
  const _PermissionsList();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (Icons.directions_walk_rounded, l10n.permActivityTitle, l10n.permActivityBody),
      (Icons.notifications_none_rounded, l10n.permNotificationsTitle, l10n.permNotificationsBody),
      (Icons.alarm_rounded, l10n.permAlarmsTitle, l10n.permAlarmsBody),
      (Icons.smartphone_rounded, l10n.permUsageTitle, l10n.permUsageBody),
      (Icons.place_outlined, l10n.permLocationTitle, l10n.permLocationBody),
      (Icons.photo_camera_outlined, l10n.permCameraTitle, l10n.permCameraBody),
    ];
    return Column(
      children: [
        for (final (icon, title, body) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: FbSpace.sm),
            child: FbCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Icon(icon, color: context.colors.primary),
                    const SizedBox(width: FbSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.text.bodyStrong.copyWith(fontSize: 15)),
                          Text(body, style: context.text.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.draft});
  final SetupDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String orNotSet(String text, [String? unit]) =>
        text.trim().isEmpty ? l10n.notSet : (unit == null ? text.trim() : '${text.trim()} $unit');
    final mass = draft.imperial ? l10n.unitLb : l10n.unitKg;
    final length = draft.imperial ? l10n.unitIn : l10n.unitCm;
    final volume = draft.imperial ? l10n.unitFlOz : l10n.unitMl;
    final reminders = [
      if (draft.remindWater) l10n.reminderWaterShort,
      if (draft.remindWorkout) l10n.reminderWorkoutShort,
      if (draft.remindBedtime) l10n.reminderBedtimeShort,
    ];
    final days = [...draft.workoutDays]..sort();
    final dayNames = MaterialLocalizations.of(context).narrowWeekdays;

    return Column(
      children: [
        _SummaryCard(
          title: l10n.summaryProfile,
          editPath: Routes.onboardingProfile,
          rows: {
            l10n.nameLabel: orNotSet(draft.name),
            l10n.unitsLabel: draft.imperial ? l10n.unitsImperial : l10n.unitsMetric,
            l10n.heightLabel: orNotSet(draft.heightText, length),
            l10n.weightLabel: orNotSet(draft.weightText, mass),
          },
        ),
        const SizedBox(height: FbSpace.md),
        _SummaryCard(
          title: l10n.summaryGoals,
          editPath: Routes.onboardingGoals,
          rows: {
            l10n.targetWeightLabel: orNotSet(draft.targetWeightText, mass),
            l10n.dailyStepsLabel: orNotSet(draft.stepsText),
            l10n.dailyCaloriesLabel: orNotSet(draft.kcalText, l10n.unitKcal),
            l10n.dailyProteinLabel: orNotSet(draft.proteinText, l10n.unitG),
            l10n.dailyWaterLabel: orNotSet(draft.waterText, volume),
            if (draft.fitnessGoals.isNotEmpty)
              l10n.fitnessGoalsLabel: draft.fitnessGoals
                  .map((g) => fitnessGoalLabel(l10n, g))
                  .join(', '),
          },
        ),
        const SizedBox(height: FbSpace.md),
        _SummaryCard(
          title: l10n.dayTitle,
          editPath: Routes.onboardingDay,
          rows: {
            l10n.wakeLabel: switch (draft.wakeTime) {
              null => l10n.notSet,
              final t => formatWakeTime(context, t),
            },
            l10n.sleepTargetLabel: draft.sleepHoursText.trim().isEmpty
                ? l10n.notSet
                : l10n.hoursValue(draft.sleepHoursText.trim()),
            // narrowWeekdays starts on Sunday; ISO weekday 7 is Sunday.
            l10n.workoutDaysLabel: days.isEmpty
                ? l10n.none
                : days.map((d) => dayNames[d % 7]).join(' '),
            l10n.summaryReminders: reminders.isEmpty ? l10n.none : reminders.join(', '),
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.editPath, required this.rows});

  final String title;
  final String editPath;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => FbCard(
    padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.xs, FbSpace.xs, FbSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(title, style: context.text.title)),
            ),
            TextButton(
              onPressed: () => context.go(editPath),
              child: Text(context.l10n.edit, semanticsLabel: context.l10n.editSection(title)),
            ),
          ],
        ),
        for (final row in rows.entries)
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.md, top: FbSpace.xs),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: Text(row.key, style: context.text.caption)),
                  const SizedBox(width: FbSpace.sm),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.value,
                      style: context.text.bodySmall.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
