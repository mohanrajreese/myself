import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/result.dart';
import '../core/utils/local_date.dart';
import '../features/money/data/drift_money_repository.dart';
import '../features/money/domain/money.dart';
import '../features/money/domain/money_report.dart';
import '../features/money/domain/receipts.dart';
import 'providers.dart';
import 'routine_providers.dart';

typedef DayRange = ({LocalDate from, LocalDate to});

LocalDate monthStart(LocalDate d) => LocalDate(d.year, d.month, 1);
LocalDate monthEnd(LocalDate d) => LocalDate.fromDateTime(DateTime.utc(d.year, d.month + 1, 0));
LocalDate addMonths(LocalDate d, int n) => LocalDate.fromDateTime(DateTime.utc(d.year, d.month + n, 1));

/// The fixed id of a seeded category.
String seededCategoryId(String key) => DriftMoneyRepository.categoryId(key);

final emiCategoryId = DriftMoneyRepository.categoryId('emi');
final foodCategoryIds = {DriftMoneyRepository.categoryId('food'), DriftMoneyRepository.categoryId('groceries')};

final moneyCategoriesProvider = StreamProvider<List<FinanceCategory>>(
  (ref) => ref.watch(moneyRepositoryProvider).watchCategories(),
);

final moneyCategoryMapProvider = Provider<Map<String, FinanceCategory>>(
  (ref) => {for (final c in ref.watch(moneyCategoriesProvider).value ?? const <FinanceCategory>[]) c.id: c},
);

final expensesProvider = StreamProvider.family<List<Expense>, DayRange>(
  (ref, r) => ref.watch(moneyRepositoryProvider).watchExpenses(from: r.from, to: r.to),
);

final junkMealIdsProvider = StreamProvider.family<Set<String>, DayRange>(
  (ref, r) => ref.watch(moneyRepositoryProvider).watchJunkMealIds(from: r.from, to: r.to),
);

final recurringProvider = StreamProvider<List<RecurringExpense>>(
  (ref) => ref.watch(moneyRepositoryProvider).watchRecurring(),
);

final budgetsProvider = StreamProvider<List<Budget>>((ref) => ref.watch(moneyRepositoryProvider).watchBudgets());
final debtsProvider = StreamProvider<List<Debt>>((ref) => ref.watch(moneyRepositoryProvider).watchDebts());
final debtPaymentsProvider = StreamProvider<List<DebtPayment>>(
  (ref) => ref.watch(moneyRepositoryProvider).watchPayments(),
);

/// The month shown on the Money tab (its first day).
final moneyMonthProvider = NotifierProvider<MoneyMonth, LocalDate>(MoneyMonth.new);

class MoneyMonth extends Notifier<LocalDate> {
  @override
  LocalDate build() => monthStart(ref.watch(todayProvider));
  void step(int months) {
    final next = addMonths(state, months);
    if (!next.isAfter(monthStart(ref.read(todayProvider)))) state = next;
  }
}

/// A month runs to today while it is the current one.
DayRange monthRange(LocalDate month, LocalDate today) {
  final end = monthEnd(month);
  return (from: month, to: end.isAfter(today) ? today : end);
}

/// The report for a range, or null while its records load.
final moneyReportProvider = Provider.family<AsyncValue<MoneyReport>, DayRange>((ref, r) {
  final prev = MoneyReport.previousRange(r.from, r.to);
  final parts = (
    ref.watch(expensesProvider(r)),
    ref.watch(expensesProvider(prev)),
    ref.watch(budgetsProvider),
    ref.watch(debtsProvider),
    ref.watch(debtPaymentsProvider),
    ref.watch(junkMealIdsProvider(r)),
  );
  final error = [parts.$1, parts.$2, parts.$3, parts.$4, parts.$5, parts.$6].where((a) => a.hasError).firstOrNull;
  if (error != null) return AsyncError(error.error!, error.stackTrace ?? StackTrace.empty);
  final (e, p, b, d, pay, junk) = parts;
  if (!e.hasValue || !p.hasValue || !b.hasValue || !d.hasValue || !pay.hasValue || !junk.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    MoneyReport.build(
      from: r.from,
      to: r.to,
      today: ref.watch(todayProvider),
      expenses: e.value!,
      previous: p.value!,
      budgets: b.value!,
      debts: d.value!,
      payments: pay.value!,
      emiCategoryId: emiCategoryId,
      foodCategoryIds: foodCategoryIds,
      junkMealIds: junk.value!,
    ),
  );
});

/// Each open debt with its status, newest first.
final debtStatusesProvider = Provider<AsyncValue<List<DebtStatus>>>((ref) {
  final debts = ref.watch(debtsProvider);
  final payments = ref.watch(debtPaymentsProvider);
  if (debts.hasError) return AsyncError(debts.error!, debts.stackTrace ?? StackTrace.empty);
  if (payments.hasError) return AsyncError(payments.error!, payments.stackTrace ?? StackTrace.empty);
  if (!debts.hasValue || !payments.hasValue) return const AsyncLoading();
  return AsyncData([
    for (final d in debts.value!.reversed)
      DebtStatus(d, [
        for (final p in payments.value!)
          if (p.debtId == d.id) p,
      ]),
  ]);
});

/// Open I-owe EMI loans by next due date.
final upcomingEmisProvider = Provider<List<DebtStatus>>((ref) {
  final all = ref.watch(debtStatusesProvider).value ?? const [];
  return [
    for (final s in all)
      if (!s.debt.settled && s.debt.direction == DebtDirection.iOwe && s.nextDue != null) s,
  ]..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
});

/// Writes that change reminders re-plan them afterwards.
final class MoneyActions {
  MoneyActions(this.ref);
  final Ref ref;

  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  Future<R> _thenReplan<R>(Future<R> f) async {
    final result = await f;
    await ref.read(reminderServiceProvider).replan();
    return result;
  }

  Future<Result<Debt>> saveDebt(Debt d, {bool markPastInstalmentsPaid = false}) =>
      _thenReplan(_repo.saveDebt(d, markPastInstalmentsPaid: markPastInstalmentsPaid));
  Future<Result<void>> deleteDebt(String id) => _thenReplan(_repo.deleteDebt(id));
  Future<Result<void>> setSettled(String id, {required bool settled}) =>
      _thenReplan(_repo.setSettled(id, settled: settled));
  Future<Result<DebtPayment>> addPayment(
    String debtId, {
    required int amountPaise,
    required DateTime at,
    int? instalmentNo,
    String? note,
  }) => _thenReplan(_repo.addPayment(debtId, amountPaise: amountPaise, at: at, instalmentNo: instalmentNo, note: note));
  Future<Result<void>> deletePayment(String id) => _thenReplan(_repo.deletePayment(id));
  Future<Result<RecurringExpense>> saveRecurring(RecurringExpense r) => _thenReplan(_repo.saveRecurring(r));
  Future<Result<void>> deleteRecurring(String id) => _thenReplan(_repo.deleteRecurring(id));
}

/// Encrypted receipt photos; set at start-up once the file key is known.
final receiptStoreProvider = Provider<ReceiptStore>((ref) => throw StateError('not provided'));

final moneyActionsProvider = Provider<MoneyActions>(MoneyActions.new);
