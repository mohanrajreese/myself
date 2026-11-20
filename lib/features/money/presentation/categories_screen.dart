import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Add, archive and restore categories (board P8Categories).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(moneyCategoriesProvider);
    final repo = ref.read(moneyRepositoryProvider);
    Widget row(FinanceCategory c) {
      final name = categoryLabel(l10n, c);
      final locked = unarchivableCategoryKeys.contains(c.systemKey);
      final kind = c.systemKey == null ? l10n.moneyYours : l10n.moneyBuiltIn;
      return FbListRow(
        title: name,
        subtitle: c.archived ? '$kind · ${l10n.moneyArchivedHint}' : kind,
        trailing: locked
            ? null
            : OutlinedButton(
                onPressed: () => repo.archiveCategory(c.id, archived: !c.archived),
                child: Text(
                  c.archived ? l10n.moneyRestore : l10n.moneyArchive,
                  semanticsLabel: c.archived
                      ? l10n.moneyRestoreA11y(name)
                      : l10n.moneyArchiveA11y(name),
                ),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moneyCategoriesTitle),
        actions: [
          TextButton.icon(
            onPressed: () => showFbSheet<void>(context, const _NewCategorySheet()),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.moneyNew, semanticsLabel: l10n.moneyNewCategory),
          ),
        ],
      ),
      body: switch (async) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
          children: [
            FbListCard(
              children: [
                for (final c in value)
                  if (!c.archived) row(c),
              ],
            ),
            if (value.any((c) => c.archived)) ...[
              MoneySectionHeader(l10n.moneyArchived),
              FbListCard(
                children: [
                  for (final c in value)
                    if (c.archived) row(c),
                ],
              ),
            ],
            const SizedBox(height: FbSpace.md),
            Text(l10n.moneyCategoriesNote, style: context.text.caption),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }
}

class _NewCategorySheet extends ConsumerStatefulWidget {
  const _NewCategorySheet();

  @override
  ConsumerState<_NewCategorySheet> createState() => _NewCategorySheetState();
}

class _NewCategorySheetState extends ConsumerState<_NewCategorySheet> {
  String _name = '';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.trim().isEmpty) {
      setState(() => _error = l10n.errRequired);
      return;
    }
    setState(() => _busy = true);
    final r = await ref.read(moneyRepositoryProvider).addCategory(_name);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyCategorySaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FbSheetBody(
      title: l10n.moneyNewCategory,
      children: [
        FbTextField(
          label: l10n.moneyDebtName,
          value: _name,
          errorText: _error,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (v) => setState(() => (_name = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}
