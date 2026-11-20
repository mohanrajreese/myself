import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/account_actions.dart';
import '../../../app/export_providers.dart';
import '../../../app/private_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/sync_controller.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../data_export/domain/export.dart';

/// Export (approved design): JSON or CSV, range, private data after the
/// PIN, photos, optional passphrase. Saved where the user chooses.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExportFormat _format = ExportFormat.json;
  ({LocalDate from, LocalDate to})? _range;
  bool _private = false;
  bool _photos = false;
  bool _protect = true;
  String _pass = '';
  String _repeat = '';
  String? _error;
  bool _busy = false;

  /// Including private data needs the PIN when the app lock is on.
  Future<void> _togglePrivate(bool on) async {
    if (!on) return setState(() => _private = false);
    final lock = ref.read(lockControllerProvider).value;
    if (lock != null && lock.hasPin && lock.settings.enabled) {
      final ok = await showDialog<bool>(context: context, builder: (_) => const _PinDialog());
      if (ok != true) return;
    }
    setState(() => _private = true);
  }

  Future<void> _export() async {
    final l = context.l10n;
    final pass = _protect ? _pass : null;
    if (_protect && _pass.length < ExportOptions.minPassphrase) {
      return setState(() => _error = l.passphraseShort);
    }
    if (_protect && _pass != _repeat) return setState(() => _error = l.passphrasesDiffer);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final bytes = await ref
          .read(exportBuilderProvider)
          .build(
            ExportOptions(
              format: _format,
              from: _range?.from,
              to: _range?.to,
              includePrivate: _private,
              includePhotos: _photos,
              passphrase: pass,
            ),
          );
      final today = ref.read(todayProvider);
      final saved = await ref.read(documentSaverProvider).save('praxis-export-$today.zip', bytes);
      if (mounted) showFbSnackBar(context, saved ? l.exportSaved : l.exportNotSaved);
    } on Object {
      if (mounted) showFbSnackBar(context, l.exportFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final today = ref.watch(todayProvider);
    final r = _range;
    return Scaffold(
      appBar: AppBar(title: Text(l.exportTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Text(l.formatLabel, style: context.text.label),
          const SizedBox(height: FbSpace.xs),
          FbSegmented<ExportFormat>(
            options: {ExportFormat.json: l.formatJson, ExportFormat.csv: l.formatCsv},
            selected: _format,
            onChanged: (v) => setState(() => _format = v),
          ),
          const SizedBox(height: FbSpace.md),
          FbPickerField(
            label: l.rangeLabel,
            valueText: r == null
                ? l.everything
                : '${context.shortDate(r.from)} ${r.from.year} – ${context.shortDate(r.to)} ${r.to.year}',
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(today.year, today.month, today.day),
              );
              if (picked != null) {
                setState(
                  () => _range = (from: LocalDate.fromDateTime(picked.start), to: LocalDate.fromDateTime(picked.end)),
                );
              }
            },
          ),
          if (r != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _range = null), child: Text(l.exportEverything)),
            ),
          const SizedBox(height: FbSpace.md),
          FbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                FbSwitchRow(
                  title: l.includePrivate,
                  subtitle: l.includePrivateHelp,
                  value: _private,
                  onChanged: _togglePrivate,
                ),
                FbSwitchRow(
                  title: l.includePhotos,
                  subtitle: l.includePhotosHelp,
                  value: _photos,
                  onChanged: (v) => setState(() => _photos = v),
                ),
                FbSwitchRow(
                  title: l.protectWithPassphrase,
                  subtitle: l.protectWithPassphraseHelp,
                  value: _protect,
                  onChanged: (v) => setState(() => _protect = v),
                ),
              ],
            ),
          ),
          if (_protect) ...[
            const SizedBox(height: FbSpace.md),
            _Secret(label: l.passphraseLabel, onChanged: (v) => _pass = v),
            const SizedBox(height: FbSpace.sm),
            _Secret(label: l.repeatPassphrase, onChanged: (v) => _repeat = v),
          ],
          if (_error != null) ...[const SizedBox(height: FbSpace.sm), FbNotice(_error!, isError: true)],
          const SizedBox(height: FbSpace.lg),
          FbPrimaryButton(label: l.createExport, onPressed: _busy ? null : _export, busy: _busy),
          const SizedBox(height: FbSpace.md),
          Text(l.exportNote, style: context.text.caption),
        ],
      ),
    );
  }
}

class _Secret extends StatelessWidget {
  const _Secret({required this.label, required this.onChanged});
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    enableIMEPersonalizedLearning: false,
    decoration: InputDecoration(labelText: label),
    onChanged: onChanged,
  );
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog();

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  String _pin = '';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.enterPin),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: l.pinLabel, errorText: _error, counterText: ''),
            onChanged: (v) => _pin = v,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        TextButton(
          onPressed: () async {
            final ok = await ref.read(lockControllerProvider.notifier).unlockWithPin(_pin);
            if (!context.mounted) return;
            if (ok) {
              Navigator.of(context).pop(true);
            } else {
              setState(() => _error = l.wrongPin);
            }
          },
          child: Text(l.unlockAction),
        ),
      ],
    );
  }
}

/// Delete phone data or the account (approved design).
class DeleteDataScreen extends ConsumerStatefulWidget {
  const DeleteDataScreen({super.key});

  @override
  ConsumerState<DeleteDataScreen> createState() => _DeleteDataScreenState();
}

class _DeleteDataScreenState extends ConsumerState<DeleteDataScreen> {
  bool _erasePhone = true;
  bool _busy = false;

  Future<void> _deletePhone() async {
    final l = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l.deletePhoneDataTitle,
      message: l.deletePhoneDataMessage,
      confirmLabel: l.deletePhoneData,
      cancelLabel: l.cancel,
    );
    if (!ok) return;
    setState(() => _busy = true);
    await ref.read(erasePhoneDataProvider)();
  }

  Future<void> _deleteAccount() async {
    final l = context.l10n;
    final typed = await showDialog<bool>(context: context, builder: (_) => const _TypeDeleteDialog());
    if (typed != true || !mounted) return;
    setState(() => _busy = true);
    final outcome = await ref.read(deleteAccountProvider)(erasePhone: _erasePhone);
    if (!mounted) return;
    setState(() => _busy = false);
    final message = switch (outcome) {
      DeleteAccountOutcome.deleted => null,
      DeleteAccountOutcome.offline => l.deleteNeedsNetwork,
      DeleteAccountOutcome.notConfigured => l.syncOffHelp,
      DeleteAccountOutcome.reauthFailed => l.deleteReauthFailed,
      DeleteAccountOutcome.failed => l.deleteFailed,
    };
    if (message != null) showFbSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cloud = ref.watch(syncControllerProvider).phase != SyncPhase.off;
    return Scaffold(
      appBar: AppBar(title: Text(l.deleteDataTitle)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => context.push(Routes.export), child: Text(l.exportFirst)),
            ),
            const SizedBox(height: FbSpace.sm),
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.deletePhoneData, style: context.text.bodyStrong),
                  const SizedBox(height: FbSpace.xs),
                  Text(l.deletePhoneDataHelp, style: context.text.bodySmall),
                  const SizedBox(height: FbSpace.md),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                    ),
                    onPressed: _deletePhone,
                    child: Text(l.deletePhoneData),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FbSpace.md),
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.deleteAccount, style: context.text.bodyStrong),
                  const SizedBox(height: FbSpace.xs),
                  Text(cloud ? l.deleteAccountHelp : l.deleteAccountUnavailable, style: context.text.bodySmall),
                  if (cloud) ...[
                    const SizedBox(height: FbSpace.sm),
                    Text(l.thisPhoneAfterwards, style: context.text.label),
                    RadioGroup<bool>(
                      groupValue: _erasePhone,
                      onChanged: (v) => setState(() => _erasePhone = v ?? true),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              value: true,
                              title: Text(l.eraseThisPhoneToo),
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              value: false,
                              title: Text(l.keepRecordsHere),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: FbSpace.sm),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: context.colors.error),
                      onPressed: _deleteAccount,
                      child: Text(l.deleteAccountAction),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy) ...[const SizedBox(height: FbSpace.lg), const FbLoading()],
          ],
        ),
      ),
    );
  }
}

class _TypeDeleteDialog extends StatefulWidget {
  const _TypeDeleteDialog();

  @override
  State<_TypeDeleteDialog> createState() => _TypeDeleteDialogState();
}

class _TypeDeleteDialogState extends State<_TypeDeleteDialog> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok = _text.trim() == 'DELETE';
    return AlertDialog(
      title: Text(l.confirmDeleteAccount),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.confirmDeleteAccountHelp),
          const SizedBox(height: FbSpace.sm),
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l.typeDelete),
            onChanged: (v) => setState(() => _text = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        TextButton(onPressed: ok ? () => Navigator.of(context).pop(true) : null, child: Text(l.deleteAccount)),
      ],
    );
  }
}
