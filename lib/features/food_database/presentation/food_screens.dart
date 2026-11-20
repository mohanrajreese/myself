import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/errors/failure.dart';
import '../../../core/units/decimal_text.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../nutrition/domain/nutrition_math.dart';
import '../domain/food.dart';

String sourceName(AppLocalizations l10n, Food food) => switch (food.source) {
  FoodSources.usda => l10n.sourceUsda,
  FoodSources.indb => l10n.sourceIndb,
  _ => l10n.sourceMine,
};

/// Energy from macronutrients (4/4/9 kcal per g), in kcal-milli.
int kcalFromMacros(NutritionValues v) => 4 * v.proteinMg + 4 * v.carbsMg + 9 * v.fatMg;

/// Food search (PRD §5.4): your foods first, then the catalogue. With [pick]
/// set, tapping a food returns it to the screen that opened the search.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({this.pick = false, super.key});
  final bool pick;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _query = TextEditingController();
  FoodFilter _filter = FoodFilter.all;
  List<Food>? _results;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final results = await ref.read(foodRepositoryProvider).search(_query.text, filter: _filter);
    if (mounted && generation == _generation) setState(() => _results = results);
  }

  Future<void> _open(Food food) async {
    if (widget.pick) {
      context.pop(food);
      return;
    }
    await _edit(food);
  }

  Future<void> _edit(Food? food) async {
    final saved = await Navigator.of(
      context,
    ).push<Food>(MaterialPageRoute(builder: (_) => FoodEditorScreen(food: food)));
    await _search();
    if (saved != null && widget.pick && food == null && mounted) context.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    final mine = results?.where((f) => f.isMine).toList() ?? const <Food>[];
    final catalogue = results?.where((f) => !f.isMine).toList() ?? const <Food>[];

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          textField: true,
          label: l10n.searchFoods,
          child: TextField(
            controller: _query,
            autofocus: widget.pick,
            style: context.text.body,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (_) => _search(),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              for (final (filter, label) in [
                (FoodFilter.all, l10n.filterAll),
                (FoodFilter.recent, l10n.filterRecent),
                (FoodFilter.saved, l10n.filterSaved),
                (FoodFilter.mine, l10n.filterMine),
              ])
                FbToggleChip(
                  label: label,
                  selected: _filter == filter,
                  onTap: () {
                    setState(() => _filter = filter);
                    _search();
                  },
                ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
          if (results == null)
            FbLoading(semanticLabel: l10n.loading)
          else if (results.isEmpty)
            FbEmptyHint(l10n.noFoodsFound, boxed: true)
          else ...[
            if (mine.isNotEmpty) ...[
              Text(l10n.yourFoods, style: context.text.label),
              const SizedBox(height: FbSpace.sm),
              FbListCard(
                children: [
                  for (final f in mine)
                    _FoodRow(food: f, onTap: () => _open(f), onEdit: () => _edit(f)),
                ],
              ),
              const SizedBox(height: FbSpace.lg),
            ],
            if (catalogue.isNotEmpty) ...[
              Text(l10n.catalogue, style: context.text.label),
              const SizedBox(height: FbSpace.sm),
              FbListCard(
                children: [
                  for (final f in catalogue)
                    _FoodRow(food: f, onTap: () => _open(f), onEdit: () => _edit(f)),
                ],
              ),
            ],
          ],
          const SizedBox(height: FbSpace.md),
          Text(l10n.catalogueNote, style: context.text.caption),
          const SizedBox(height: FbSpace.lg),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, FbSize.primaryButton)),
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.createFood),
          ),
        ],
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onTap, required this.onEdit});
  final Food food;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final parts = [
      food.servingLabel,
      context.kcal(food.values.energyKcalMilli),
      '${context.grams(food.values.proteinMg)} ${l10n.macroProtein.toLowerCase()}',
      sourceName(l10n, food),
      if (food.isEstimate) l10n.estimateTag,
      if (food.hasConflict) l10n.conflictTag,
      if (food.isMine && food.useCount > 0) l10n.timesUsed(food.useCount),
    ];
    return FbListRow(
      title: food.name,
      subtitle: parts.join(' · '),
      leading: food.hasConflict
          ? Icon(Icons.warning_amber_rounded, color: context.colors.warning)
          : null,
      onTap: onTap,
      trailing: IconButton(
        tooltip: l10n.editFoodLabel(food.name),
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

/// Creates a food, or edits any food. Editing a catalogue food saves the
/// user's own copy (see FoodRepository.edit). Pops with the saved food.
class FoodEditorScreen extends ConsumerStatefulWidget {
  const FoodEditorScreen({this.food, super.key});
  final Food? food;

  @override
  ConsumerState<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends ConsumerState<FoodEditorScreen> {
  late final Food? _food = widget.food;
  late String _name = _food?.name ?? '';
  late String _serving = _food?.servingLabel ?? '';
  late String _servingGrams = switch (_food?.servingWeightMg) {
    final mg? when _food!.servingUnit != 'g' => formatScaled(mg, 3, decimals: 0),
    _ => '',
  };
  late String _kcal = _text(_food?.values.energyKcalMilli);
  late String _protein = _text(_food?.values.proteinMg);
  late String _carbs = _text(_food?.values.carbsMg);
  late String _fat = _text(_food?.values.fatMg);
  late String _fibre = _text(_food?.values.fibreMg);
  late JunkCategory? _junk = _food?.junk;
  late bool _saved = _food?.isSaved ?? true;
  Map<String, String> _errors = const {};
  bool _busy = false;

  static String _text(int? milli) =>
      milli == null ? '' : formatScaled(milli, 3, decimals: milli % 1000 == 0 ? 0 : 1);

  bool get _gramBased => _food != null && _food.servingUnit == 'g';

  Future<void> _save() async {
    final l10n = context.l10n;
    final errors = <String, String>{};
    int? value(String key, String text) {
      final v = parseScaled(text.trim().isEmpty ? '0' : text, 3);
      if (v == null || v < 0) errors[key] = l10n.errInvalidNumber;
      return v;
    }

    final kcal = value('kcal', _kcal);
    final protein = value('protein', _protein);
    final carbs = value('carbs', _carbs);
    final fat = value('fat', _fat);
    final fibre = value('fibre', _fibre);
    if (_name.trim().isEmpty) errors['name'] = l10n.errRequired;
    if (!_gramBased && _serving.trim().isEmpty) errors['serving'] = l10n.errRequired;
    final grams = _servingGrams.trim().isEmpty ? null : parseScaled(_servingGrams, 3);
    if (_servingGrams.trim().isNotEmpty && (grams == null || grams <= 0)) {
      errors['grams'] = l10n.errInvalidNumber;
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final values = NutritionValues(
      energyKcalMilli: kcal!,
      proteinMg: protein!,
      carbsMg: carbs!,
      fatMg: fat!,
      fibreMg: fibre!,
    );
    final food = _food;
    final draft = FoodDraft(
      name: _name,
      brand: food?.brand,
      category: food?.category ?? 'other',
      servingLabel: _gramBased ? food!.servingLabel : _serving,
      servingQtyMilli: _gramBased ? food!.servingQtyMilli : 1000,
      servingUnit: _gramBased ? 'g' : 'serving',
      servingWeightMg: _gramBased ? food!.servingWeightMg : grams,
      values: values,
      junk: _junk,
      isSaved: _saved,
    );
    setState(() => _busy = true);
    final repo = ref.read(foodRepositoryProvider);
    final result = food == null ? await repo.create(draft) : await repo.edit(food, draft);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isOk) {
      showFbSnackBar(context, l10n.foodSaved);
      Navigator.of(context).pop(result.valueOrNull);
    } else {
      showFbSnackBar(
        context,
        result.failureOrNull is ValidationFailure ? l10n.errCheckFields : l10n.errSaveFailed,
      );
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final agreed = await showFbConfirm(
      context,
      title: l10n.deleteFoodTitle,
      message: l10n.deleteFoodMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!agreed || !mounted) return;
    await ref.read(foodRepositoryProvider).delete(_food!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final food = _food;
    final perLabel = _gramBased
        ? food!.servingLabel
        : (_serving.trim().isEmpty ? l10n.unitServing : _serving.trim());
    Widget number(
      String key,
      String label,
      String value,
      String suffix,
      ValueChanged<String> onChanged,
    ) => FbTextField(
      label: label,
      value: value,
      suffix: suffix,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: FbTextField.decimal,
      errorText: _errors[key],
      onChanged: onChanged,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(food == null ? l10n.newFoodTitle : l10n.editFood),
        actions: [
          if (food != null && food.isMine)
            IconButton(
              tooltip: l10n.delete,
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(FbSpace.xl),
                children: [
                  if (food != null && !food.isMine) ...[
                    FbNotice(l10n.catalogueEditNote),
                    const SizedBox(height: FbSpace.md),
                  ],
                  if (food != null && food.hasConflict) ...[
                    FbNotice(
                      l10n.conflictWarning(context.kcal(kcalFromMacros(food.values))),
                      isError: true,
                    ),
                    const SizedBox(height: FbSpace.md),
                  ],
                  if (food != null && food.isEstimate) ...[
                    Text(l10n.estimateWarning, style: context.text.caption),
                    const SizedBox(height: FbSpace.md),
                  ],
                  FbTextField(
                    label: l10n.foodName,
                    value: _name,
                    textCapitalization: TextCapitalization.sentences,
                    errorText: _errors['name'],
                    onChanged: (v) => _name = v,
                  ),
                  const SizedBox(height: FbSpace.lg),
                  if (!_gramBased) ...[
                    FbFieldPair(
                      first: FbTextField(
                        label: l10n.servingLabelField,
                        value: _serving,
                        hint: l10n.servingHint,
                        errorText: _errors['serving'],
                        onChanged: (v) => setState(() => _serving = v),
                      ),
                      second: FbTextField(
                        label: l10n.servingWeight,
                        optional: true,
                        optionalLabel: l10n.optional,
                        value: _servingGrams,
                        suffix: l10n.unitGrams,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: FbTextField.decimal,
                        errorText: _errors['grams'],
                        onChanged: (v) => _servingGrams = v,
                      ),
                    ),
                    const SizedBox(height: FbSpace.lg),
                  ],
                  if (food?.householdLabel != null && food?.householdWeightMg != null) ...[
                    Text(
                      l10n.householdServing(
                        food!.householdLabel!,
                        formatScaled(food.householdWeightMg!, 3, decimals: 0),
                      ),
                      style: context.text.caption,
                    ),
                    const SizedBox(height: FbSpace.md),
                  ],
                  Text(l10n.valuesPer(perLabel), style: context.text.bodyStrong),
                  const SizedBox(height: FbSpace.md),
                  FbFieldPair(
                    first: number('kcal', l10n.energyLabel, _kcal, l10n.unitKcal, (v) => _kcal = v),
                    second: number(
                      'protein',
                      l10n.proteinLabel,
                      _protein,
                      l10n.unitG,
                      (v) => _protein = v,
                    ),
                  ),
                  const SizedBox(height: FbSpace.lg),
                  FbFieldPair(
                    first: number('carbs', l10n.carbsLabel, _carbs, l10n.unitG, (v) => _carbs = v),
                    second: number('fat', l10n.fatLabel, _fat, l10n.unitG, (v) => _fat = v),
                  ),
                  const SizedBox(height: FbSpace.lg),
                  number('fibre', l10n.fibreLabel, _fibre, l10n.unitG, (v) => _fibre = v),
                  const SizedBox(height: FbSpace.lg),
                  Text(l10n.junkLabel, style: context.text.label),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<JunkCategory?>(
                    isExpanded: true,
                    initialValue: _junk,
                    style: context.text.body,
                    items: [
                      for (final j in <JunkCategory?>[null, ...JunkCategory.values])
                        DropdownMenuItem(value: j, child: Text(junkLabel(l10n, j))),
                    ],
                    onChanged: (v) => setState(() => _junk = v),
                  ),
                  const SizedBox(height: FbSpace.md),
                  FbCard(
                    padding: EdgeInsets.zero,
                    child: FbSwitchRow(
                      title: l10n.keepSaved,
                      value: _saved,
                      onChanged: (v) => setState(() => _saved = v),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(FbSpace.xl, 0, FbSpace.xl, FbSpace.xl),
              child: SizedBox(
                width: double.infinity,
                child: FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
