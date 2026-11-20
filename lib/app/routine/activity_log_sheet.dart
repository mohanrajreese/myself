import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import '../routine_labels.dart';
import '../routine_providers.dart';
import '../../core/errors/failure.dart';
import '../../core/units/decimal_text.dart';
import '../../core/widgets/fb_fields.dart';
import '../../core/widgets/fb_scaffolds.dart';
import '../../core/widgets/fb_sheet.dart';
import '../../core/widgets/fb_states.dart';
import '../../core/widgets/l10n.dart';
import '../../core/widgets/tokens.dart';
import '../../features/activities/domain/activity.dart';
import '../../features/activities/domain/activity_repository.dart';

Future<void> showActivityLogSheet(BuildContext context, Activity activity, {int? slot, ActivityLog? existing}) =>
    showFbSheet<void>(context, ActivityLogSheet(activity: activity, slot: slot, existing: existing));

/// Logs (or edits) one entry, with the input that fits the tracking type
/// (approved design "Log sheet").
class ActivityLogSheet extends ConsumerStatefulWidget {
  const ActivityLogSheet({required this.activity, this.slot, this.existing, super.key});
  final Activity activity;
  final int? slot;
  final ActivityLog? existing;

  @override
  ConsumerState<ActivityLogSheet> createState() => _ActivityLogSheetState();
}

class _ActivityLogSheetState extends ConsumerState<ActivityLogSheet> {
  late DateTime _at = widget.existing?.occurredAt.toLocal() ?? ref.read(clockProvider).now();
  late int _count = widget.existing?.countValue ?? 1;
  late String _value = switch (widget.activity.trackingType) {
    TrackingType.numeric =>
      widget.existing?.numericValueMilli == null
          ? ''
          : formatScaled(widget.existing!.numericValueMilli!, 3, decimals: 2),
    TrackingType.duration ||
    TrackingType.stopwatch => widget.existing?.durationS == null ? '' : '${(widget.existing!.durationS! / 60).round()}',
    _ => '',
  };
  late final Set<String> _checked = {...?widget.existing?.checklistDone};
  late String _note = widget.existing?.notes ?? '';
  String? _error;
  bool _busy = false;

  Activity get _a => widget.activity;

  Future<void> _save(ActivityLogStatus status) async {
    final l10n = context.l10n;
    int? numeric;
    int? durationS;
    if (status == ActivityLogStatus.completed) {
      switch (_a.trackingType) {
        case TrackingType.numeric:
          numeric = parseScaled(_value.trim(), 3);
          if (numeric == null) return setState(() => _error = l10n.errInvalidNumber);
        case TrackingType.duration || TrackingType.stopwatch:
          final minutes = int.tryParse(_value.trim());
          if (minutes == null || minutes < 1 || minutes > 1440) {
            return setState(() => _error = l10n.errOutOfRange);
          }
          durationS = minutes * 60;
        case TrackingType.checklist:
          if (_checked.isEmpty) return setState(() => _error = l10n.errTickOne);
        default:
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = LogDraft(
      status: status,
      occurredAt: _at,
      scheduledSlot: widget.slot ?? widget.existing?.scheduledSlot,
      countValue: status == ActivityLogStatus.completed && _a.trackingType == TrackingType.count ? _count : null,
      numericValueMilli: numeric,
      unit: _a.targetUnit,
      durationS: durationS,
      checklistDone: _a.trackingType == TrackingType.checklist && status == ActivityLogStatus.completed
          ? _checked
          : null,
      notes: _note,
    );
    final repo = ref.read(activityRepositoryProvider);
    final result = widget.existing == null
        ? (await repo.addLog(_a.id, draft)).map((_) {})
        : await repo.updateLog(widget.existing!.id, draft);
    if (!mounted) return;
    if (!result.isOk) {
      setState(() {
        _busy = false;
        _error = switch (result.failureOrNull) {
          ValidationFailure(code: 'in_future') => l10n.errInFuture,
          ValidationFailure() => l10n.errOutOfRange,
          _ => l10n.errSaveFailed,
        };
      });
      return;
    }
    replanReminders(ref);
    showFbSnackBar(context, status == ActivityLogStatus.skipped ? l10n.skippedSaved : l10n.activityLogged(_a.name));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.deleteEntryTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (!ok || !mounted) return;
    await ref.read(activityRepositoryProvider).deleteLog(widget.existing!.id);
    replanReminders(ref);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = ref.read(clockProvider).now();
    final completedLabel = _a.trackingType == TrackingType.checklist
        ? l10n.saveChecklist(_checked.length, _a.checklistItems.length)
        : l10n.save;
    return FbSheetBody(
      title: _a.name,
      trailing: widget.existing == null
          ? (widget.slot == null
                ? null
                : Text(l10n.dueAt(minuteLabel(context, widget.slot!)), style: context.text.caption))
          : IconButton(tooltip: l10n.delete, onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
      children: [
        ...switch (_a.trackingType) {
          TrackingType.count => [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: l10n.decrease,
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl),
                  child: Text('$_count', style: context.text.displayMetric),
                ),
                IconButton.outlined(
                  tooltip: l10n.increase,
                  onPressed: _count < 999 ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
          TrackingType.numeric => [
            FbTextField(
              label: l10n.valueLabel,
              value: _value,
              onChanged: (v) => _value = v,
              suffix: _a.targetUnit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          TrackingType.duration || TrackingType.stopwatch => [
            FbTextField(
              label: l10n.minutesLabel,
              value: _value,
              onChanged: (v) => _value = v,
              suffix: l10n.unitMin,
              keyboardType: TextInputType.number,
            ),
          ],
          TrackingType.checklist => [
            FbListCard(
              children: [
                for (final item in _a.checklistItems)
                  CheckboxListTile(
                    title: Text(item.label),
                    value: _checked.contains(item.id),
                    onChanged: (v) => setState(() => v! ? _checked.add(item.id) : _checked.remove(item.id)),
                  ),
              ],
            ),
          ],
          _ => const <Widget>[],
        },
        const SizedBox(height: FbSpace.md),
        FbDateTimeField(label: l10n.timeLabel, value: _at, last: now, onChanged: (v) => setState(() => _at = v)),
        const SizedBox(height: FbSpace.md),
        FbTextField(
          label: l10n.note,
          value: _note,
          onChanged: (v) => _note = v,
          optional: true,
          optionalLabel: l10n.optional,
          textCapitalization: TextCapitalization.sentences,
        ),
        if (_error != null) ...[const SizedBox(height: FbSpace.sm), FbNotice(_error!, isError: true)],
        const SizedBox(height: FbSpace.lg),
        Row(
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _save(ActivityLogStatus.skipped),
              child: Text(l10n.actionSkip),
            ),
            const SizedBox(width: FbSpace.sm),
            Expanded(
              child: FbPrimaryButton(
                label: completedLabel,
                busy: _busy,
                onPressed: () => _save(ActivityLogStatus.completed),
              ),
            ),
          ],
        ),
        const SizedBox(height: FbSpace.sm),
        Text(l10n.logSheetNote, style: context.text.caption),
      ],
    );
  }
}
