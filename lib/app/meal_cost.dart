import '../core/errors/result.dart';
import '../features/money/data/drift_money_repository.dart';
import '../features/money/domain/money.dart';

/// Keeps a meal's linked Food expense in line with its Cost field
/// (§5.21E): a cost adds or updates the expense, no cost removes it.
Future<Result<void>> syncMealCost(
  MoneyRepository money, {
  required String mealId,
  required int? costPaise,
  required PaymentMethod method,
  required DateTime at,
}) async {
  final existing = await money.expenseForMeal(mealId);
  if (costPaise == null) {
    return existing == null ? const Ok(null) : money.deleteExpense(existing.id);
  }
  final draft = (
    amountPaise: costPaise,
    categoryId: existing?.categoryId ?? DriftMoneyRepository.categoryId('food'),
    method: method,
    at: at,
    note: existing?.note,
    mealLogId: mealId,
  );
  if (existing == null) {
    final r = await money.addExpense(draft);
    return r.isOk ? const Ok(null) : Err(r.failureOrNull!);
  }
  return money.updateExpense(existing.id, draft);
}

/// After a meal is deleted: drop its expense, or keep it unlinked.
Future<void> afterMealDeleted(
  MoneyRepository money,
  Expense linked, {
  required bool deleteExpense,
}) async {
  if (deleteExpense) {
    await money.deleteExpense(linked.id);
    return;
  }
  await money.updateExpense(linked.id, (
    amountPaise: linked.amountPaise,
    categoryId: linked.categoryId,
    method: linked.method,
    at: linked.occurredAt,
    note: linked.note,
    mealLogId: null,
  ));
}
