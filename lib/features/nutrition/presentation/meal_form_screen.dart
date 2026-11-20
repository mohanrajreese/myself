import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/labels.dart';
import '../../../app/meal_cost.dart';
import '../../../app/money_labels.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/units/decimal_text.dart';
import '../../../core/units/rupees.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../food_database/domain/food.dart';
import '../../money/domain/money.dart';
import '../application/meal_draft_item.dart';
import '../domain/meals.dart';
import '../domain/nutrition_math.dart';

/// Add a meal, or edit [existing] (PRD §5.4).
class MealFormScreen extends ConsumerStatefulWidget {
  const MealFormScreen({this.existing, super.key});
  final Meal? existing;

  @override
  ConsumerState<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends ConsumerState<MealFormScreen> {
  late DateTime _at;
  late MealCategory _category;
  late List<DraftItem> _items;
  late String _note;
  bool _showNote = false;
  bool _keepAsSaved = false;
  String _savedName = '';
  Uint8List? _newPhoto;
  Uint8List? _existingPhoto;
  bool _removePhoto = false;
  String _cost = '';
  String? _costError;
  PaymentMethod _method = PaymentMethod.upi;
  bool _dirty = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final meal = widget.existing;
    _at = (meal?.occurredAt ?? ref.read(clockProvider).now()).toLocal();
    _category = meal?.category ?? mealCategoryForTime(_at.hour, _at.minute);
    _items = [for (final i in meal?.items ?? const <MealItem>[]) DraftItem.fromMealItem(i)];
    _note = meal?.notes ?? '';
    _showNote = _note.isNotEmpty;
    if (meal != null) {
      ref.read(moneyRepositoryProvider).expenseForMeal(meal.id).then((e) {
        if (!mounted || e == null || _dirty) return;
        setState(() {
          _cost = rupeesInput(e.amountPaise);
          _method = e.method;
        });
      });
    }
    if (meal != null && meal.hasPhoto) {
      ref.read(mealPhotoStoreProvider).read(meal.id).then((bytes) {
        if (mounted && bytes != null) setState(() => _existingPhoto = Uint8List.fromList(bytes));
      });
    }
  }

  void _change(VoidCallback f) => setState(() {
    f();
    _dirty = true;
    _error = null;
  });

  Future<void> _addFood() async {
    final food = await context.push<Food>('${Routes.foods}?pick=1');
    if (food == null || !mounted) return;
    final portions = portionsFor(food);
    if (portions.isEmpty) return;
    final item = await showFbSheet<DraftItem>(
      context,
      QuantitySheet(
        item: DraftItem.fromFood(food, portions.first, portions.first.defaultQtyMilli),
        isNew: true,
      ),
    );
    if (item != null) _change(() => _items = [..._items, item]);
  }

  Future<void> _editItem(int index) async {
    final result = await showFbSheet<Object>(context, QuantitySheet(item: _items[index]));
    if (result is DraftItem) {
      _change(() => _items = [..._items]..[index] = result);
    } else if (result == QuantitySheet.removed) {
      _change(() => _items = [..._items]..removeAt(index));
    }
  }

  void _step(int index, int direction) {
    final item = _items[index];
    final next = item.qtyMilli + direction * item.portion.stepMilli;
    if (next <= 0) return;
    _change(() => _items = [..._items]..[index] = item.copyWith(qtyMilli: next));
  }

  Future<void> _pickPhoto() async {
    final l10n = context.l10n;
    final source = await showFbSheet<PhotoSource>(
      context,
      FbSheetBody(
        title: l10n.mealPhoto,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.takePhoto),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.choosePhoto),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
          if (_newPhoto != null || (_existingPhoto != null && !_removePhoto))
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: context.colors.error),
              title: Text(l10n.removePhoto),
              onTap: () {
                Navigator.of(context).pop();
                _change(() {
                  _newPhoto = null;
                  _removePhoto = true;
                });
              },
            ),
        ],
      ),
    );
    if (source == null) return;
    final bytes = await ref.read(photoPickerProvider).pick(source);
    if (bytes != null && mounted) {
      _change(() {
        _newPhoto = Uint8List.fromList(bytes);
        _removePhoto = false;
      });
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_items.isEmpty) {
      setState(() => _error = l10n.errAddItem);
      return;
    }
    final costPaise = _cost.trim().isEmpty ? null : parseRupees(_cost.replaceAll(',', '.'));
    if (_cost.trim().isNotEmpty && (costPaise == null || costPaise <= 0)) {
      setState(() => _costError = l10n.errAmountInvalid);
      return;
    }
    setState(() => _busy = true);
    final foods = ref.read(foodRepositoryProvider);
    final meals = ref.read(mealRepositoryProvider);
    // Catalogue foods become the user's own foods once logged.
    final items = <MealItem>[];
    for (final item in _items) {
      var id = item.foodItemId;
      final food = item.food;
      if (id == null && food != null) id = (await foods.adopt(food)).valueOrNull?.id;
      items.add(item.copyWith(foodItemId: id).toMealItem());
    }
    final draft = MealDraft(category: _category, items: items, at: _at, notes: _note);
    final existing = widget.existing;
    String? mealId;
    if (existing == null) {
      final result = await meals.add(draft);
      mealId = result.valueOrNull?.id;
      if (mealId == null) return _failed(result.failureOrNull?.code);
    } else {
      final result = await meals.update(existing.id, draft);
      if (!result.isOk) return _failed(result.failureOrNull?.code);
      mealId = existing.id;
    }
    final now = ref.read(clockProvider).now();
    for (final item in items) {
      if (item.foodItemId != null) await foods.markUsed(item.foodItemId!, now);
    }
    final costSaved = await syncMealCost(
      ref.read(moneyRepositoryProvider),
      mealId: mealId,
      costPaise: costPaise,
      method: _method,
      at: _at,
    );
    if (!costSaved.isOk) return _failed(null);
    final photos = ref.read(mealPhotoStoreProvider);
    if (_newPhoto != null) {
      await photos.attach(mealId, _newPhoto!);
    } else if (_removePhoto) {
      await photos.remove(mealId);
    }
    if (_keepAsSaved) {
      final name = _savedName.trim().isEmpty ? mealName(l10n, _category) : _savedName;
      await meals.saveAsTemplate(mealId, name);
    }
    if (!mounted) return;
    showFbSnackBar(context, l10n.mealSaved);
    _dirty = false;
    context.pop();
  }

  void _failed(String? code) {
    final l10n = context.l10n;
    setState(() {
      _busy = false;
      _error = code == 'in_future' ? l10n.errInFuture : l10n.errSaveFailed;
    });
  }

  Future<void> _duplicate() async {
    final l10n = context.l10n;
    final result = await ref.read(mealRepositoryProvider).duplicate(widget.existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, result.isOk ? l10n.mealDuplicated : l10n.errSaveFailed);
    if (result.isOk) context.pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final money = ref.read(moneyRepositoryProvider);
    final linked = await money.expenseForMeal(widget.existing!.id);
    if (!mounted) return;
    bool? deleteExpense;
    if (linked == null) {
      final agreed = await showFbConfirm(
        context,
        title: l10n.deleteMealTitle,
        message: l10n.deleteEntryMessage,
        confirmLabel: l10n.delete,
        cancelLabel: l10n.cancel,
        destructive: true,
      );
      if (!agreed || !mounted) return;
    } else {
      deleteExpense = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteMealTitle),
          content: Text(l10n.deleteMealLinkedMessage(formatRupees(linked.amountPaise))),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.deleteMealKeepExpense),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
              child: Text(l10n.deleteMealAndExpense),
            ),
          ],
        ),
      );
      if (deleteExpense == null || !mounted) return;
    }
    await ref.read(mealPhotoStoreProvider).remove(widget.existing!.id);
    await ref.read(mealRepositoryProvider).delete(widget.existing!.id);
    if (linked != null) await afterMealDeleted(money, linked, deleteExpense: deleteExpense!);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    _dirty = false;
    context.pop();
  }

  Future<void> _confirmLeave() async {
    final l10n = context.l10n;
    final leave = await showFbConfirm(
      context,
      title: l10n.discardTitle,
      message: l10n.discardMessage,
      confirmLabel: l10n.discard,
      cancelLabel: l10n.keepEditing,
      destructive: true,
    );
    if (leave && mounted) {
      _dirty = false;
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = sumNutrition(_items.map((i) => i.values));
    final now = ref.watch(clockProvider).now();
    final photo = _newPhoto ?? (_removePhoto ? null : _existingPhoto);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? l10n.addMeal : l10n.editMealTitle),
          actions: [
            if (widget.existing == null)
              IconButton(
                tooltip: l10n.savedMeals,
                onPressed: () => context.push(Routes.savedMeals),
                icon: const Icon(Icons.bookmarks_outlined),
              )
            else ...[
              IconButton(
                tooltip: l10n.duplicateMeal,
                onPressed: _duplicate,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: l10n.delete,
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    FbSpace.lg,
                    FbSpace.sm,
                    FbSpace.lg,
                    FbSpace.xxl,
                  ),
                  children: [
                    FbFieldPair(
                      first: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.mealLabel, style: context.text.label),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<MealCategory>(
                            isExpanded: true,
                            initialValue: _category,
                            style: context.text.body,
                            items: [
                              for (final c in MealCategory.values)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(mealName(l10n, c), overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (c) => _change(() => _category = c!),
                          ),
                        ],
                      ),
                      second: FbDateTimeField(
                        label: l10n.timeLabel,
                        value: _at,
                        last: now,
                        onChanged: (v) => _change(() => _at = v),
                      ),
                    ),
                    const SizedBox(height: FbSpace.sm),
                    Text(l10n.mealCategoryHint, style: context.text.caption),
                    const SizedBox(height: FbSpace.lg),
                    FbSectionTitle(l10n.itemsTitle),
                    const SizedBox(height: FbSpace.sm),
                    if (_items.isEmpty)
                      FbEmptyHint(l10n.itemsEmpty, boxed: true)
                    else
                      FbListCard(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            _ItemRow(
                              item: _items[i],
                              onTap: () => _editItem(i),
                              onLess: () => _step(i, -1),
                              onMore: () => _step(i, 1),
                            ),
                        ],
                      ),
                    const SizedBox(height: FbSpace.md),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                      onPressed: _addFood,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.addFood),
                    ),
                    const SizedBox(height: FbSpace.sm),
                    Text(l10n.itemsHelp, style: context.text.caption),
                    const SizedBox(height: FbSpace.lg),
                    _Totals(total: total),
                    const SizedBox(height: FbSpace.lg),
                    if (photo != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(FbRadius.card),
                        child: Image.memory(
                          photo,
                          height: 160,
                          fit: BoxFit.cover,
                          semanticLabel: l10n.mealPhoto,
                        ),
                      ),
                      const SizedBox(height: FbSpace.sm),
                    ],
                    FbFieldPair(
                      first: OutlinedButton(
                        onPressed: _pickPhoto,
                        child: Text(photo == null ? l10n.addPhoto : l10n.changePhoto),
                      ),
                      second: OutlinedButton(
                        onPressed: () => setState(() => _showNote = true),
                        child: Text(l10n.addNote),
                      ),
                    ),
                    if (_showNote) ...[
                      const SizedBox(height: FbSpace.lg),
                      FbTextField(
                        label: l10n.note,
                        value: _note,
                        hint: l10n.noteHint,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onChanged: (v) => _change(() => _note = v),
                      ),
                    ],
                    const SizedBox(height: FbSpace.lg),
                    FbFieldPair(
                      first: FbTextField(
                        label: l10n.mealCost,
                        value: _cost,
                        optional: true,
                        optionalLabel: l10n.optional,
                        suffix: '₹',
                        errorText: _costError,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: FbTextField.decimal,
                        onChanged: (v) => _change(() {
                          _cost = v;
                          _costError = null;
                        }),
                      ),
                      second: FbPickerField(
                        label: l10n.moneyPaidWith,
                        valueText: paymentMethodLabel(l10n, _method),
                        onTap: () async {
                          final m = await pickPaymentMethod(context, _method);
                          if (m != null) _change(() => _method = m);
                        },
                      ),
                    ),
                    const SizedBox(height: FbSpace.xs),
                    Text(l10n.mealCostHelp, style: context.text.caption),
                    const SizedBox(height: FbSpace.md),
                    CheckboxListTile(
                      value: _keepAsSaved,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l10n.keepAsSaved, style: context.text.body),
                      onChanged: (v) => setState(() => _keepAsSaved = v ?? false),
                    ),
                    if (_keepAsSaved)
                      FbTextField(
                        label: l10n.savedMealName,
                        value: _savedName,
                        hint: mealName(l10n, _category),
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (v) => _savedName = v,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      FbNotice(_error!, isError: true),
                      const SizedBox(height: FbSpace.md),
                    ],
                    FbPrimaryButton(label: l10n.saveMeal, onPressed: _save, busy: _busy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onTap,
    required this.onLess,
    required this.onMore,
  });
  final DraftItem item;
  final VoidCallback onTap;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = item.values;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.md, vertical: FbSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: context.text.bodyStrong),
                  Text(
                    [
                      item.quantityText,
                      context.kcal(v.energyKcalMilli),
                      '${context.grams(v.proteinMg)} ${l10n.macroProtein.toLowerCase()}',
                      if (item.isEstimate) l10n.estimateTag,
                      if (item.junk != null) junkLabel(l10n, item.junk),
                    ].join(' · '),
                    style: context.text.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.lessOf(item.name),
              onPressed: onLess,
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton(
              tooltip: l10n.moreOf(item.name),
              onPressed: onMore,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.total});
  final NutritionValues total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget cell(String value, String label) => Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.text.bodyStrong.copyWith(fontSize: 15)),
            Text(label, style: context.text.caption),
          ],
        ),
      ),
    );
    return FbCard(
      child: Row(
        children: [
          cell(context.number((total.energyKcalMilli + 500) ~/ 1000), l10n.unitKcal),
          cell(context.grams(total.proteinMg), l10n.macroProtein),
          cell(context.grams(total.carbsMg), l10n.macroCarbs),
          cell(context.grams(total.fatMg), l10n.macroFat),
          cell(context.grams(total.fibreMg), l10n.macroFibre),
        ],
      ),
    );
  }
}

/// Choose the quantity and unit of one item. Pops with the updated item,
/// or with [removed].
class QuantitySheet extends StatefulWidget {
  const QuantitySheet({required this.item, this.isNew = false, super.key});
  final DraftItem item;
  final bool isNew;

  static const removed = 'removed';

  @override
  State<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<QuantitySheet> {
  late DraftItem _item = widget.item;
  late String _text = formatScaled(_item.qtyMilli, 3, decimals: _item.qtyMilli % 1000 == 0 ? 0 : 2);
  String? _error;

  void _setPortion(Portion p) => setState(() {
    _item = _item.copyWith(portion: p, qtyMilli: p.defaultQtyMilli);
    _text = formatScaled(p.defaultQtyMilli, 3, decimals: 0);
  });

  void _setText(String text) {
    final qty = parseScaled(text, 3);
    setState(() {
      _text = text;
      if (qty != null && qty > 0) _item = _item.copyWith(qtyMilli: qty);
    });
  }

  void _done() {
    final qty = parseScaled(_text, 3);
    if (qty == null || qty <= 0) {
      setState(() => _error = context.l10n.errInvalidNumber);
      return;
    }
    Navigator.of(context).pop(_item.copyWith(qtyMilli: qty));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = _item.values;
    final food = _item.food;
    return FbSheetBody(
      title: _item.name,
      trailing: widget.isNew
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).pop(QuantitySheet.removed),
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
              child: Text(l10n.remove),
            ),
      children: [
        if (food != null && food.hasConflict) ...[
          FbNotice(
            l10n.conflictWarning(context.kcal(4 * v.proteinMg + 4 * v.carbsMg + 9 * v.fatMg)),
            isError: true,
          ),
          const SizedBox(height: FbSpace.md),
        ],
        if (_item.isEstimate) ...[
          Text(l10n.estimateWarning, style: context.text.caption),
          const SizedBox(height: FbSpace.md),
        ],
        if (_item.portions.length > 1) ...[
          Text(l10n.unitLabel, style: context.text.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              for (final p in _item.portions)
                FbToggleChip(
                  label: p.unit,
                  selected: p.unit == _item.portion.unit,
                  onTap: () => _setPortion(p),
                ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
        ],
        FbTextField(
          key: ValueKey(_item.portion.unit),
          label: l10n.quantityLabel,
          value: _text,
          suffix: _item.portion.unit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: FbTextField.decimal,
          errorText: _error,
          onChanged: _setText,
        ),
        const SizedBox(height: FbSpace.sm),
        Text(
          [
            context.kcal(v.energyKcalMilli),
            '${context.grams(v.proteinMg)} ${l10n.macroProtein.toLowerCase()}',
            '${context.grams(v.fibreMg)} ${l10n.macroFibre.toLowerCase()}',
          ].join(' · '),
          style: context.text.bodySmall,
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.junkLabel, style: context.text.label),
        const SizedBox(height: 6),
        DropdownButtonFormField<JunkCategory?>(
          isExpanded: true,
          initialValue: _item.junk,
          style: context.text.body,
          items: [
            for (final j in <JunkCategory?>[null, ...JunkCategory.values])
              DropdownMenuItem(value: j, child: Text(junkLabel(l10n, j))),
          ],
          onChanged: (j) => setState(() => _item = _item.copyWith(junk: () => j)),
        ),
        const SizedBox(height: FbSpace.xl),
        FbPrimaryButton(label: widget.isNew ? l10n.addToMeal : l10n.done, onPressed: _done),
      ],
    );
  }
}
