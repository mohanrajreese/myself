import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/theme_mode_controller.dart';

/// Signs the user out. Supplied by the app so this feature does not depend on
/// the sign-in feature's internals.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final account = ref.watch(currentAccountProvider);
    final profile = account == null ? null : ref.watch(profileProvider(account.id)).value;
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
    final themeMode = ref.watch(themeModeProvider);
    final name = profile?.displayName ?? account?.displayName ?? '';
    final syncText = pending == 0 ? l10n.syncNothingWaiting : l10n.syncPending(pending);

    Widget group(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: FbSpace.xs, bottom: FbSpace.sm),
          child: Semantics(header: true, child: Text(title, style: context.text.label)),
        ),
        FbCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FbRadius.card),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(indent: FbSpace.lg, endIndent: FbSpace.lg),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            radius: FbRadius.hero,
            padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl, vertical: FbSpace.lg),
            child: MergeSemantics(
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: c.primary,
                      child: Text(
                        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                        style: context.text.title.copyWith(color: c.onPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: FbSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: context.text.title),
                        if (account?.email != null)
                          Text(account!.email!, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          FbCard(
            padding: EdgeInsets.zero,
            child: FbListRow(
              leading: Icon(Icons.bar_chart_rounded, color: context.colors.primary),
              title: l10n.tabInsights,
              subtitle: l10n.settingsInsightsSubtitle,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.insights),
            ),
          ),
          const SizedBox(height: FbSpace.xl),
          group(l10n.sectionYou, [
            FbNavRow(
              title: l10n.rowProfile,
              value: l10n.rowProfileValue,
              onTap: () => context.push(Routes.settingsProfile),
            ),
            FbNavRow(
              title: l10n.rowGoals,
              value: l10n.rowGoalsValue,
              onTap: () => context.push(Routes.settingsGoals),
            ),
            FbNavRow(
              title: l10n.rowDay,
              value: l10n.rowDayValue,
              onTap: () => context.push(Routes.settingsDay),
            ),
          ]),
          const SizedBox(height: FbSpace.xl),
          group(l10n.sectionApp, [
            Padding(
              padding: const EdgeInsets.all(FbSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.theme, style: context.text.body),
                  const SizedBox(height: FbSpace.sm),
                  FbSegmented<AppThemeMode>(
                    semanticLabel: l10n.theme,
                    options: {
                      AppThemeMode.system: l10n.themeSystem,
                      AppThemeMode.light: l10n.themeLight,
                      AppThemeMode.dark: l10n.themeDark,
                    },
                    selected: themeMode,
                    onChanged: ref.read(themeModeProvider.notifier).set,
                  ),
                ],
              ),
            ),
            FbNavRow(
              title: l10n.customiseHome,
              value: l10n.customiseHomeValue,
              onTap: () => context.push(Routes.settingsHome),
            ),
            FbNavRow(
              title: l10n.notificationSettingsTitle,
              onTap: () => context.push(Routes.notificationSettings),
            ),
            FbNavRow(title: l10n.appLock, onTap: () => context.push(Routes.appLock)),
            FbNavRow(title: l10n.rowAbout, onTap: () => context.push(Routes.about)),
          ]),
          const SizedBox(height: FbSpace.xl),
          group(l10n.yourData, [
            FbNavRow(
              title: l10n.accountAndSync,
              value: syncText,
              onTap: () => context.push(Routes.accountSync),
            ),
            FbNavRow(
              title: l10n.exportTitle,
              value: l10n.exportRowHelp,
              onTap: () => context.push(Routes.export),
            ),
            FbNavRow(title: l10n.deleteDataTitle, onTap: () => context.push(Routes.deleteData)),
          ]),
        ],
      ),
    );
  }
}
