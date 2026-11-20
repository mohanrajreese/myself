import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../core/errors/failure.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../application/session_controller.dart';

/// First screen for anyone not signed in (decision D2).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(sessionControllerProvider.notifier);
    final outcome = await controller.signIn();
    if (!mounted) return;

    switch (outcome) {
      case SignedIn():
        break; // The router moves on.
      case SignInFailed(:final failure):
        setState(() => _error = _message(l10n, failure));
      case DifferentAccount(:final existing, :final incoming):
        setState(() => _busy = false);
        final agreed = await showFbConfirm(
          context,
          title: l10n.replaceTitle,
          message: l10n.replaceMessage(
            existing.email ?? existing.displayName ?? l10n.thisAccount,
            incoming.email ?? incoming.displayName ?? l10n.thisAccount,
          ),
          confirmLabel: l10n.replaceConfirm,
          cancelLabel: l10n.cancel,
          destructive: true,
        );
        if (!mounted) return;
        if (agreed) {
          setState(() => _busy = true);
          await controller.replaceAccount(incoming);
        } else {
          await controller.cancelReplace();
        }
    }
    if (mounted) setState(() => _busy = false);
  }

  String? _message(AppLocalizations l10n, Failure failure) => switch (failure) {
    AuthFailure(code: 'cancelled') => null,
    AuthFailure(code: 'not_configured') => l10n.signInNotConfigured,
    AuthFailure(code: 'backend_rejected') => l10n.signInFailedBackend,
    NetworkFailure() => l10n.signInOffline,
    _ => l10n.signInFailedGoogle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.text;
    final c = context.colors;
    final online = ref.watch(onlineProvider).value ?? true;
    final configured = ref.watch(authRepositoryProvider).isConfigured;
    final notice = !configured ? l10n.signInNotConfigured : (!online ? l10n.signInOffline : _error);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(FbSpace.xxl, FbSpace.x4, FbSpace.xxl, FbSpace.x3),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - FbSpace.x4 - FbSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: FbSpace.x3),
                      const FbLogo(),
                      const SizedBox(height: FbSpace.x3),
                      Semantics(
                        header: true,
                        child: Text(l10n.appName, style: t.headline.copyWith(fontSize: 36, height: 42 / 36)),
                      ),
                      const SizedBox(height: FbSpace.md),
                      Text(
                        l10n.signInTagline,
                        style: t.body.copyWith(fontSize: 18, height: 28 / 18, color: c.textSecondary),
                      ),
                      const SizedBox(height: FbSpace.x3),
                      for (final point in [l10n.signInPoint1, l10n.signInPoint2, l10n.signInPoint3])
                        Padding(
                          padding: const EdgeInsets.only(bottom: FbSpace.lg),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_rounded, color: c.primary),
                              const SizedBox(width: FbSpace.md),
                              Expanded(child: Text(point, style: t.body)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: FbSpace.xxl),
                      if (notice != null) ...[FbNotice(notice, isError: true), const SizedBox(height: FbSpace.lg)],
                      _GoogleButton(
                        label: l10n.continueWithGoogle,
                        busy: _busy,
                        onPressed: configured && online ? _signIn : null,
                      ),
                      const SizedBox(height: FbSpace.lg),
                      Text(l10n.signInFooter, style: t.bodySmall, textAlign: TextAlign.center),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, FbSize.primaryButton),
        textStyle: context.text.bodyStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FbRadius.card)),
      ),
      child: busy
          ? SizedBox.square(
              dimension: FbSpace.xxl,
              child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: context.l10n.loading),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: c.surfaceVariant,
                    child: Text(
                      'G',
                      style: context.text.bodySmall.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: FbSpace.md),
                Flexible(child: Text(label)),
              ],
            ),
    );
  }
}
