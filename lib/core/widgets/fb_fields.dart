import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Labelled text field. [value] is the source of truth: when it changes from
/// outside (for example after "Recalculate"), the field shows the new text.
class FbTextField extends StatefulWidget {
  const FbTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.suffix,
    this.errorText,
    this.optional = false,
    this.optionalLabel,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? suffix;
  final String? errorText;
  final bool optional;
  final String? optionalLabel;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;

  /// Digits with at most one decimal separator.
  static final decimal = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}([.,]\d{0,2})?')),
  ];
  static final digits = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ];

  @override
  State<FbTextField> createState() => _FbTextFieldState();
}

class _FbTextFieldState extends State<FbTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(FbTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              text: widget.label,
              style: t.label,
              children: [
                if (widget.optional && widget.optionalLabel != null)
                  TextSpan(text: ' (${widget.optionalLabel})', style: t.caption),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            style: t.body,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            textCapitalization: widget.textCapitalization,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixText: widget.suffix,
              errorText: widget.errorText,
              errorMaxLines: 2,
            ),
          ),
        ),
      ],
    );
  }
}

/// A field that opens a picker instead of the keyboard.
class FbPickerField extends StatelessWidget {
  const FbPickerField({
    required this.label,
    required this.valueText,
    required this.onTap,
    this.hint,
    this.optionalLabel,
    this.onClear,
    this.clearLabel,
    super.key,
  });

  final String label;
  final String? valueText;
  final String? hint;
  final String? optionalLabel;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? clearLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              text: label,
              style: t.label,
              children: [
                if (optionalLabel != null) TextSpan(text: ' ($optionalLabel)', style: t.caption),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: label,
          value: valueText ?? hint,
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FbRadius.input),
              side: BorderSide(color: c.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: FbSize.field,
                child: Padding(
                  padding: const EdgeInsets.only(left: FbSpace.lg, right: FbSpace.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            valueText ?? hint ?? '',
                            style: valueText == null ? t.body.copyWith(color: c.textDisabled) : t.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (valueText != null && onClear != null)
                        IconButton(
                          onPressed: onClear,
                          tooltip: clearLabel,
                          icon: Icon(Icons.close_rounded, color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
