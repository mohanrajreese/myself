import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/setup_controller.dart';
import 'setup_forms.dart';

enum SetupSection { profile, goals, day }

/// Edits one part of the setup from Settings, using the onboarding forms.
class EditSetupScreen extends ConsumerStatefulWidget {
  const EditSetupScreen({required this.section, super.key});
  final SetupSection section;

  @override
  ConsumerState<EditSetupScreen> createState() => _EditSetupScreenState();
}

class _EditSetupScreenState extends ConsumerState<EditSetupScreen> {
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    // Start from what is saved, discarding edits abandoned on another screen.
    Future.microtask(() => ref.invalidate(setupControllerProvider));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final draft = ref.read(setupControllerProvider).value;
    if (draft == null) return;
    final errors = switch (widget.section) {
      SetupSection.profile => draft.profileErrors(today: ref.read(todayProvider)),
      SetupSection.goals => draft.goalErrors(),
      SetupSection.day => draft.dayErrors(),
    };
    setState(() {
      _errors = errors;
      _saveFailed = false;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    final result = await ref.read(setupControllerProvider.notifier).saveChanges();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saveFailed = !result.isOk;
    });
    if (result.isOk) {
      showFbSnackBar(context, l10n.changesSaved);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draftState = ref.watch(setupControllerProvider);
    final draft = draftState.isLoading ? null : draftState.value;
    final title = switch (widget.section) {
      SetupSection.profile => l10n.rowProfile,
      SetupSection.goals => l10n.rowGoals,
      SetupSection.day => l10n.rowDay,
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: draft == null
          ? FbLoading(semanticLabel: l10n.loading)
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(FbSpace.xxl),
                      children: [
                        switch (widget.section) {
                          SetupSection.profile => SetupProfileForm(draft: draft, errors: _errors, showWeight: false),
                          SetupSection.goals => SetupGoalsForm(draft: draft, errors: _errors, editing: true),
                          SetupSection.day => SetupDayForm(draft: draft, errors: _errors),
                        },
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(FbSpace.xxl, 0, FbSpace.xxl, FbSpace.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_saveFailed || _errors.isNotEmpty) ...[
                          FbNotice(_saveFailed ? l10n.errSaveFailed : l10n.errCheckFields, isError: true),
                          const SizedBox(height: FbSpace.md),
                        ],
                        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
