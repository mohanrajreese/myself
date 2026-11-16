import 'package:material_ui/material_ui.dart';

import 'fb_card.dart';
import 'tokens.dart';

class FbLoading extends StatelessWidget {
  const FbLoading({this.semanticLabel, super.key});
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(semanticsLabel: semanticLabel));
}

class FbErrorState extends StatelessWidget {
  const FbErrorState({required this.message, this.retryLabel, this.onRetry, super.key});

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FbSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: context.colors.error, size: FbSpace.x4),
              const SizedBox(height: FbSpace.md),
              Text(message, style: context.text.body, textAlign: TextAlign.center),
              if (onRetry != null && retryLabel != null) ...[
                const SizedBox(height: FbSpace.lg),
                OutlinedButton(onPressed: onRetry, child: Text(retryLabel!)),
              ],
            ],
          ),
        ),
      );
}

/// Quiet explanation of what will appear in an empty area.
class FbEmptyHint extends StatelessWidget {
  const FbEmptyHint(this.message, {this.boxed = false, super.key});

  final String message;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final text = Text(message, style: context.text.bodySmall);
    return boxed ? FbCard(dashed: true, child: text) : text;
  }
}

/// Inline message for a form or screen: error, warning or neutral note.
class FbNotice extends StatelessWidget {
  const FbNotice(this.message, {this.isError = false, this.action, super.key});

  final String message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: isError,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? c.surface : c.primaryContainer,
          borderRadius: BorderRadius.circular(FbRadius.chip),
          border: isError ? Border.all(color: c.error) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FbSpace.md, vertical: 10),
          child: Row(
            children: [
              if (isError) ...[
                Icon(Icons.error_outline_rounded, color: c.error, size: FbSpace.xl),
                const SizedBox(width: FbSpace.sm),
              ],
              Expanded(
                child: Text(
                  message,
                  style: context.text.caption.copyWith(
                    color: isError ? c.error : c.onPrimaryContainer,
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: FbSpace.sm), action!],
            ],
          ),
        ),
      ),
    );
  }
}

void showFbSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Confirmation before a destructive or irreversible action.
Future<bool> showFbConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive ? TextButton.styleFrom(foregroundColor: context.colors.error) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
