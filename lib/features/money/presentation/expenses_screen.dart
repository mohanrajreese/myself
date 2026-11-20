import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/labels.dart';
import '../../../app/money_labels.dart';
import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../nutrition/domain/meals.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Add or edit an expense (board P8AddExpense).
Future<void> showExpenseSheet(BuildContext context, {Expense? existing}) =>
    showFbSheet<void>(context, _ExpenseSheet(existing: existing));

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet({this.existing});
  final Expense? existing;

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  late String _amount;
  String? _categoryId;
  late PaymentMethod _method;
  late DateTime _at;
  late String _note;
  String? _mealId;
  List<int>? _newReceipt;
  bool _removeReceipt = false;
  String? _amountError;
  String? _error;
  bool _busy = false;

  static const _quickKeys = ['food', 'groceries', 'transport', 'bills', 'shopping'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = e == null ? '' : rupeesInput(e.amountPaise);
    _categoryId = e?.categoryId;
    _method = e?.method ?? PaymentMethod.upi;
    _at = (e?.occurredAt ?? ref.read(clockProvider).now()).toLocal();
    _note = e?.note ?? '';
    _mealId = e?.mealLogId;
  }

  bool get _hasReceipt => _newReceipt != null || (widget.existing?.hasReceipt == true && !_removeReceipt);

  Future<void> _pickCategory(List<FinanceCategory> all) async {
    final l10n = context.l10n;
    final id = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyCategory,
        children: [
          for (final c in all)
            FbListRow(
              title: categoryLabel(l10n, c),
              trailing: c.id == _categoryId ? Icon(Icons.check_rounded, semanticLabel: l10n.selected) : null,
              onTap: () => Navigator.of(context).pop(c.id),
            ),
        ],
      ),
    );
    if (id != null) setState(() => _categoryId = id);
  }

  Future<void> _pickReceipt() async {
    final l10n = context.l10n;
    final source = await showFbSheet<PhotoSource>(
      context,
      FbSheetBody(
        title: l10n.moneyReceiptPhoto,
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
          if (_hasReceipt)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: context.colors.error),
              title: Text(l10n.moneyRemoveReceipt),
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _newReceipt = null;
                  _removeReceipt = true;
                });
              },
            ),
        ],
      ),
    );
    if (source == null) return;
    final bytes = await ref.read(photoPickerProvider).pick(source);
    if (bytes != null && mounted) {
      setState(() {
        _newReceipt = bytes;
        _removeReceipt = false;
      });
    }
  }

  Future<void> _pickMeal(List<Meal> meals) async {
    final l10n = context.l10n;
    final chosen = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyLinkMeal,
        children: [
          FbListRow(title: l10n.moneyNotLinked, onTap: () => Navigator.of(context).pop('')),
          if (meals.isEmpty) FbEmptyHint(l10n.moneyNoMealsThatDay),
          for (final m in meals)
            FbListRow(
              title: mealName(l10n, m.category),
              subtitle: context.time(m.occurredAt),
              trailing: m.id == _mealId ? Icon(Icons.check_rounded, semanticLabel: l10n.selected) : null,
              onTap: () => Navigator.of(context).pop(m.id),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => _mealId = chosen.isEmpty ? null : chosen);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise <= 0) {
      setState(() => _amountError = l10n.errAmountInvalid);
      return;
    }
    if (_at.isAfter(ref.read(clockProvider).now())) {
      setState(() => _error = l10n.errInFuture);
      return;
    }
    final categoryId = _categoryId ?? foodCategoryIds.first;
    final linkable = foodCategoryIds.contains(categoryId);
    setState(() => _busy = true);
    final money = ref.read(moneyRepositoryProvider);
    final draft = (
      amountPaise: paise,
      categoryId: categoryId,
      method: _method,
      at: _at,
      note: _note,
      mealLogId: linkable ? _mealId : null,
    );
    final existing = widget.existing;
    String? id;
    if (existing == null) {
      id = (await money.addExpense(draft)).valueOrNull?.id;
    } else {
      id = (await money.updateExpense(existing.id, draft)).isOk ? existing.id : null;
    }
    if (id == null) {
      if (mounted) setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    final receipts = ref.read(receiptStoreProvider);
    if (_newReceipt != null) {
      await receipts.attach(id, _newReceipt!);
    } else if (_removeReceipt) {
      await receipts.remove(id);
    }
    if (!mounted) return;
    showFbSnackBar(context, l10n.moneyExpenseSaved);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFbConfirm(
      context,
      title: l10n.moneyDeleteExpenseTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final id = widget.existing!.id;
    await ref.read(receiptStoreProvider).remove(id);
    await ref.read(moneyRepositoryProvider).deleteExpense(id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cats = [
      for (final c in ref.watch(moneyCategoriesProvider).value ?? const <FinanceCategory>[])
        if (!c.archived) c,
    ];
    final selected = _categoryId ?? cats.where((c) => c.systemKey == 'food').firstOrNull?.id;
    final quick = [
      for (final k in _quickKeys) ...cats.where((c) => c.systemKey == k),
      if (selected != null && !cats.any((c) => c.id == selected && _quickKeys.contains(c.systemKey)))
        ...cats.where((c) => c.id == selected),
    ];
    final linkable = selected != null && foodCategoryIds.contains(selected);
    final day = LocalDate.fromDateTime(_at);
    final meals = linkable ? (ref.watch(mealsOnProvider(day)).value ?? const <Meal>[]) : const <Meal>[];
    final linkedMeal = meals.where((m) => m.id == _mealId).firstOrNull;
    return FbSheetBody(
      title: widget.existing == null ? l10n.moneyAddExpenseLabel : l10n.moneyEditExpense,
      trailing: widget.existing == null
          ? null
          : IconButton(
              tooltip: l10n.delete,
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
            ),
      children: [
        FbTextField(
          label: l10n.moneyAmount,
          value: _amount,
          suffix: '₹',
          errorText: _amountError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: rupeeInputFormatters,
          onChanged: (v) => setState(() => (_amount = v, _amountError = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneyCategory, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final c in quick)
              FbToggleChip(
                label: categoryLabel(l10n, c),
                selected: c.id == selected,
                onTap: () => setState(() => _categoryId = c.id),
              ),
            FbToggleChip(label: l10n.moneyMore, selected: false, onTap: () => _pickCategory(cats)),
          ],
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneyPaidWith, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final m in PaymentMethod.values)
              FbToggleChip(
                label: paymentMethodLabel(l10n, m),
                selected: m == _method,
                onTap: () => setState(() => _method = m),
              ),
          ],
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.moneyWhen,
          value: _at,
          last: ref.read(clockProvider).now(),
          onChanged: (v) => setState(() => (_at = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.note,
          value: _note,
          optional: true,
          optionalLabel: l10n.optional,
          hint: l10n.noteHint,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _note = v,
        ),
        const SizedBox(height: FbSpace.lg),
        FbFieldPair(
          first: OutlinedButton.icon(
            onPressed: _pickReceipt,
            icon: Icon(_hasReceipt ? Icons.check_rounded : Icons.receipt_long_outlined),
            label: Text(_hasReceipt ? l10n.moneyReceiptAttached : l10n.moneyReceiptPhoto),
          ),
          second: linkable
              ? OutlinedButton.icon(
                  onPressed: () => _pickMeal(meals),
                  icon: Icon(linkedMeal == null ? Icons.restaurant_outlined : Icons.check_rounded),
                  label: Text(
                    linkedMeal == null ? l10n.moneyLinkMeal : l10n.moneyLinkedTo(mealName(l10n, linkedMeal.category)),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_error != null) ...[const SizedBox(height: FbSpace.md), FbNotice(_error!, isError: true)],
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
      ],
    );
  }
}

/// All expenses, with search and filters (board P8Expenses).
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late LocalDate _month = ref.read(moneyMonthProvider);
  String? _categoryId;
  PaymentMethod? _method;
  String _query = '';

  Future<void> _chooseMonth() async {
    final l10n = context.l10n;
    final current = monthStart(ref.read(todayProvider));
    final chosen = await showFbSheet<LocalDate>(
      context,
      FbSheetBody(
        title: l10n.moneyMonth,
        children: [
          for (var i = 0; i < 24; i++)
            FbListRow(
              title: monthLabel(addMonths(current, -i)),
              trailing: addMonths(current, -i) == _month
                  ? Icon(Icons.check_rounded, semanticLabel: l10n.selected)
                  : null,
              onTap: () => Navigator.of(context).pop(addMonths(current, -i)),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => _month = chosen);
  }

  Future<void> _chooseCategory(List<FinanceCategory> cats) async {
    final l10n = context.l10n;
    final chosen = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyCategory,
        children: [
          FbListRow(title: l10n.moneyAllCategories, onTap: () => Navigator.of(context).pop('')),
          for (final c in cats)
            FbListRow(
              title: categoryLabel(l10n, c),
              trailing: c.id == _categoryId ? Icon(Icons.check_rounded, semanticLabel: l10n.selected) : null,
              onTap: () => Navigator.of(context).pop(c.id),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => _categoryId = chosen.isEmpty ? null : chosen);
  }

  Future<void> _chooseMethod() async {
    final l10n = context.l10n;
    final chosen = await showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyPaidWith,
        children: [
          FbListRow(title: l10n.moneyAnyMethod, onTap: () => Navigator.of(context).pop('')),
          for (final m in PaymentMethod.values)
            FbListRow(
              title: paymentMethodLabel(l10n, m),
              trailing: m == _method ? Icon(Icons.check_rounded, semanticLabel: l10n.selected) : null,
              onTap: () => Navigator.of(context).pop(m.code),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => _method = chosen.isEmpty ? null : PaymentMethod.fromCode(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final range = monthRange(_month, today);
    final async = ref.watch(expensesProvider(range));
    final cats = ref.watch(moneyCategoryMapProvider);
    final q = _query.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneyExpenses)),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.moneyAddExpenseLabel,
        onPressed: () => showExpenseSheet(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: switch (async) {
        AsyncError() => FbErrorState(
          message: l10n.moneyLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(expensesProvider(range)),
        ),
        AsyncData(:final value) => () {
          final shown = [
            for (final e in value)
              if ((_categoryId == null || e.categoryId == _categoryId) &&
                  (_method == null || e.method == _method) &&
                  (q.isEmpty ||
                      (e.note ?? '').toLowerCase().contains(q) ||
                      categoryLabel(l10n, cats[e.categoryId]).toLowerCase().contains(q)))
                e,
          ];
          final byDay = <LocalDate, List<Expense>>{};
          for (final e in shown) {
            byDay.putIfAbsent(e.localDate, () => []).add(e);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, 96),
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: l10n.moneySearchHint,
                  labelText: l10n.moneySearchLabel,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: FbSpace.md),
              Wrap(
                spacing: FbSpace.sm,
                runSpacing: FbSpace.sm,
                children: [
                  FbToggleChip(label: monthLabel(_month), selected: true, onTap: _chooseMonth),
                  FbToggleChip(
                    label: _categoryId == null ? l10n.moneyAllCategories : categoryLabel(l10n, cats[_categoryId]),
                    selected: _categoryId != null,
                    onTap: () => _chooseCategory(cats.values.toList()),
                  ),
                  FbToggleChip(
                    label: _method == null ? l10n.moneyAnyMethod : paymentMethodLabel(l10n, _method!),
                    selected: _method != null,
                    onTap: _chooseMethod,
                  ),
                ],
              ),
              const SizedBox(height: FbSpace.md),
              Text(
                l10n.moneyCountTotal(shown.length, formatRupees(shown.fold(0, (s, e) => s + e.amountPaise))),
                style: context.text.bodySmall,
              ),
              if (shown.isEmpty) ...[
                const SizedBox(height: FbSpace.md),
                FbEmptyHint(value.isEmpty ? l10n.moneyNothingInMonth : l10n.moneyNoMatch, boxed: true),
              ],
              for (final MapEntry(key: day, value: list) in byDay.entries) ...[
                MoneySectionHeader(
                  l10n.moneyDayTotal(
                    context.dayLabel(day, today: today),
                    formatRupees(list.fold(0, (s, e) => s + e.amountPaise)),
                  ),
                ),
                FbListCard(
                  children: [
                    for (final e in list)
                      ExpenseRow(
                        expense: e,
                        category: cats[e.categoryId],
                        onTap: () => showExpenseSheet(context, existing: e),
                      ),
                  ],
                ),
              ],
            ],
          );
        }(),
        _ => const FbLoading(),
      },
    );
  }
}
