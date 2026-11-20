import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/private_providers.dart';
import '../../../app/routes.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

/// Shows [child] only when the app lock allows it (§5.12: private areas
/// always need the lock). Without a PIN yet, offers to set one up.
class LockGate extends ConsumerWidget {
  const LockGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lock = ref.watch(lockControllerProvider);
    final v = lock.value;
    if (v == null) {
      return Scaffold(
        body: lock.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading(),
      );
    }
    if (!v.hasPin || !v.settings.enabled) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.privateSpace)),
        body: ListView(
          padding: const EdgeInsets.all(FbSpace.lg),
          children: [
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 32, color: context.colors.primary),
                  const SizedBox(height: FbSpace.sm),
                  Text(l10n.lockNeededTitle, style: context.text.title),
                  const SizedBox(height: FbSpace.xs),
                  Text(l10n.lockNeededBody, style: context.text.bodySmall),
                  const SizedBox(height: FbSpace.md),
                  FilledButton(
                    onPressed: () => context.push(Routes.appLock),
                    child: Text(l10n.setUpLock),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return v.unlocked ? child : const LockScreen();
  }
}

/// PIN pad with optional fingerprint (approved design "Lock screen").
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric(auto: true));
  }

  Future<void> _biometric({bool auto = false}) async {
    final v = ref.read(lockControllerProvider).value;
    if (v == null || !v.settings.biometric || !mounted) return;
    if (auto && !await ref.read(biometricsProvider).available()) return;
    if (!mounted) return;
    await ref.read(lockControllerProvider.notifier).unlockWithBiometrics(context.l10n.unlockReason);
  }

  Future<void> _digit(String d) async {
    if (_checking || _pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  /// Only a deliberate try counts towards the wrong-PIN backoff.
  Future<void> _try() async {
    if (_checking || !PinStore.isValidPin(_pin)) return;
    final l10n = context.l10n;
    setState(() => _checking = true);
    final ok = await ref.read(lockControllerProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    final blocked = ref.read(lockControllerProvider).value?.blockedFor;
    setState(() {
      _checking = false;
      if (!ok) {
        _pin = '';
        _error = blocked == null ? l10n.wrongPin : l10n.tryAgainIn(blocked.inSeconds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = ref.watch(lockControllerProvider).value;
    Widget key(String label, {VoidCallback? onTap, String? semantics}) => SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: context.colors.surfaceVariant,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(label, style: context.text.title, semanticsLabel: semantics ?? label),
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl, vertical: FbSpace.md),
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: context.colors.primary),
            const SizedBox(height: FbSpace.md),
            Text(l10n.enterPin, style: context.text.title, textAlign: TextAlign.center),
            Text(l10n.privateLocked, style: context.text.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: FbSpace.lg),
            Semantics(
              label: l10n.pinDigitsEntered(_pin.length),
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? context.colors.primary : Colors.transparent,
                        border: Border.all(color: context.colors.primary, width: 2),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FbSpace.md),
              FbNotice(_error!, isError: true),
            ],
            const SizedBox(height: FbSpace.lg),
            Center(
              child: Wrap(
                spacing: FbSpace.xl,
                runSpacing: FbSpace.md,
                alignment: WrapAlignment.center,
                children: [
                  for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                    key(d, onTap: () => _digit(d)),
                  key(
                    '⌫',
                    semantics: l10n.deleteDigit,
                    onTap: _pin.isEmpty
                        ? null
                        : () => setState(() => _pin = _pin.substring(0, _pin.length - 1)),
                  ),
                  key('0', onTap: () => _digit('0')),
                  key('✓', semantics: l10n.unlockAction, onTap: _pin.length < 4 ? null : _try),
                ],
              ),
            ),
            if (v?.settings.biometric ?? false) ...[
              const SizedBox(height: FbSpace.lg),
              OutlinedButton.icon(
                onPressed: _biometric,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(l10n.useFingerprint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Settings → App lock (approved design).
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  static const _choices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final pin = await showFbSheet<String>(context, const PinSetupSheet());
    if (pin == null) return;
    await ref.read(lockControllerProvider.notifier).setPin(pin);
    if (context.mounted) showFbSnackBar(context, context.l10n.pinSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(lockControllerProvider);
    final v = async.value;
    final c = ref.read(lockControllerProvider.notifier);
    String after(Duration d) =>
        d == Duration.zero ? l10n.lockImmediately : l10n.lockAfterMinutes(d.inMinutes);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appLock)),
      body: v == null
          ? const FbLoading()
          : ListView(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
              children: [
                FbCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      FbSwitchRow(
                        title: l10n.appLock,
                        subtitle: v.settings.enabled ? l10n.appLockOn : l10n.appLockOff,
                        value: v.settings.enabled,
                        onChanged: (on) async {
                          if (on) {
                            await _setPin(context, ref);
                          } else {
                            final ok = await showFbConfirm(
                              context,
                              title: l10n.turnOffLockTitle,
                              message: l10n.turnOffLockMessage,
                              confirmLabel: l10n.turnOff,
                              cancelLabel: l10n.cancel,
                            );
                            if (ok) await c.turnOff();
                          }
                        },
                      ),
                      if (v.settings.enabled) ...[
                        FbSwitchRow(
                          title: l10n.unlockWithFingerprint,
                          subtitle: l10n.unlockWithFingerprintHelp,
                          value: v.settings.biometric,
                          onChanged: (on) async {
                            if (on && !await ref.read(biometricsProvider).available()) {
                              if (context.mounted) showFbSnackBar(context, l10n.noFingerprint);
                              return;
                            }
                            await c.changeSettings(v.settings.copyWith(biometric: on));
                          },
                        ),
                        FbListRow(
                          title: l10n.lockAfter,
                          subtitle: after(v.settings.lockAfter),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            final picked = await showFbSheet<Duration>(
                              context,
                              FbSheetBody(
                                title: l10n.lockAfter,
                                children: [
                                  for (final d in _choices)
                                    ListTile(
                                      title: Text(after(d)),
                                      onTap: () => Navigator.of(context).pop(d),
                                    ),
                                ],
                              ),
                            );
                            if (picked != null) {
                              await c.changeSettings(v.settings.copyWith(lockAfter: picked));
                            }
                          },
                        ),
                        FbListRow(
                          title: l10n.changePin,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _setPin(context, ref),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: FbSpace.md),
                Text(l10n.appLockNote, style: context.text.caption),
              ],
            ),
    );
  }
}

/// Enter a new PIN twice.
class PinSetupSheet extends StatefulWidget {
  const PinSetupSheet({super.key});

  @override
  State<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<PinSetupSheet> {
  String _first = '';
  String _second = '';
  String? _error;

  void _save() {
    final l10n = context.l10n;
    if (!PinStore.isValidPin(_first)) return setState(() => _error = l10n.pinRules);
    if (_first != _second) return setState(() => _error = l10n.pinsDiffer);
    Navigator.of(context).pop(_first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    InputDecoration deco(String label) => InputDecoration(labelText: label, counterText: '');
    return FbSheetBody(
      title: l10n.newPin,
      children: [
        TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          enableSuggestions: false,
          autocorrect: false,
          decoration: deco(l10n.newPin),
          onChanged: (v) => _first = v,
        ),
        const SizedBox(height: FbSpace.md),
        TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          enableSuggestions: false,
          autocorrect: false,
          decoration: deco(l10n.repeatPin),
          onChanged: (v) => _second = v,
        ),
        if (_error != null) ...[
          const SizedBox(height: FbSpace.sm),
          FbNotice(_error!, isError: true),
        ],
        const SizedBox(height: FbSpace.md),
        Text(l10n.pinRules, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FilledButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}
