import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/home_layout.dart';

/// Reorder and hide the sections of Home (PRD §4.2).
class CustomiseHomeScreen extends ConsumerWidget {
  const CustomiseHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final layout = ref.watch(homeLayoutProvider).value;
    final controller = ref.read(homeLayoutProvider.notifier);
    String name(HomeSection section) => switch (section) {
      HomeSection.progress => l10n.sectionProgress,
      HomeSection.quickAdd => l10n.sectionQuickAdd,
      HomeSection.essentials => l10n.sectionEssentials,
      HomeSection.timeline => l10n.sectionTimeline,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customiseHome)),
      body: layout == null
          ? FbLoading(semanticLabel: l10n.loading)
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: FbSpace.sm),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(FbSpace.xxl, 0, FbSpace.xxl, FbSpace.md),
                child: Text(l10n.customiseHomeHelp, style: context.text.bodySmall),
              ),
              itemCount: layout.length,
              onReorderItem: controller.move,
              itemBuilder: (context, index) {
                final item = layout[index];
                return SwitchListTile(
                  key: ValueKey(item.section),
                  contentPadding: const EdgeInsets.only(left: FbSpace.xxl, right: FbSpace.x4),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(name(item.section), style: context.text.body),
                  value: item.visible,
                  onChanged: (value) => controller.setVisible(item.section, value),
                );
              },
            ),
    );
  }
}
