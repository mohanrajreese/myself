import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

final _versionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Version, data sources and licences (attribution for the food catalogues).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(_versionProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (version != null) ...[
            Text(l10n.aboutVersion(version), style: context.text.bodySmall),
            const SizedBox(height: FbSpace.lg),
          ],
          FbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FbSectionTitle(l10n.aboutFoodData),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.aboutUsda, style: context.text.bodySmall),
                const SizedBox(height: FbSpace.sm),
                Text(l10n.aboutIndb, style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.lg),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: l10n.appName,
              applicationVersion: version,
            ),
            child: Text(l10n.aboutLicences),
          ),
        ],
      ),
    );
  }
}
