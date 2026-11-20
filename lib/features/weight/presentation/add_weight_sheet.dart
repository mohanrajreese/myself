import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../core/units/units.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

/// Quick weight entry, opened from Home.
class AddWeightSheet extends ConsumerStatefulWidget {
  const AddWeightSheet({super.key});

  @override
  ConsumerState<AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends ConsumerState<AddWeightSheet> {
  String? _text;
  String? _errorCode;
  bool _busy = false;

  MassUnit get _unit {
    final account = ref.read(currentAccountProvider);
    final profile = account == null ? null : ref.read(profileProvider(account.id)).value;
    return profile?.units.mass ?? MassUnit.kg;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final latest = ref.read(latestWeightProvider).value;
    final text = _text ?? (latest == null ? '' : formatMass(latest.weightG, _unit));
    final grams = gramsFromText(text, _unit);
    if (grams == null) {
      setState(() => _errorCode = 'invalid');
      return;
    }
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    final result = await ref.read(weightRepositoryProvider).add(weightG: grams, entryUnit: _unit);
    if (!mounted) return;
    if (result.isOk) {
      showFbSnackBar(context, l10n.weightSaved);
      context.pop();
    } else {
      setState(() {
        _busy = false;
        _errorCode = result.failureOrNull?.code == 'out_of_range' ? 'out_of_range' : 'save_failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = _unit;
    final unitLabel = unit == MassUnit.kg ? l10n.unitKg : l10n.unitLb;
    final latest = ref.watch(latestWeightProvider).value;
    final lastText = latest == null ? null : formatMass(latest.weightG, unit);
    final text = _text ?? lastText ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(FbSpace.xl, 0, FbSpace.xl, FbSpace.xxl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(l10n.addWeightTitle, style: context.text.title)),
              ),
              if (lastText != null)
                Text(
                  l10n.lastWeight(unit == MassUnit.kg ? l10n.valueKg(lastText) : l10n.valueLb(lastText)),
                  style: context.text.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: FbSpace.xl),
          FbTextField(
            label: l10n.weightFieldLabel,
            value: text,
            suffix: unitLabel,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FbTextField.decimal,
            textInputAction: TextInputAction.done,
            errorText: switch (_errorCode) {
              null => null,
              'invalid' => l10n.errInvalidNumber,
              'out_of_range' => l10n.errOutOfRange,
              _ => l10n.errSaveFailed,
            },
            onChanged: (value) => setState(() => _text = value),
          ),
          const SizedBox(height: FbSpace.xl),
          FbPrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
