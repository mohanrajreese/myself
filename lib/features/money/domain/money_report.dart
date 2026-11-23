import '../../../core/utils/local_date.dart';
import 'loans.dart';
import 'money.dart';

/// Money analysis for a range (§5.21D). Pure: callers pass the records.
final class MoneyReport {
  MoneyReport._({
    required this.from,
    required this.to,
    required this.totalPaise,
    required this.previousTotalPaise,
    required this.byCategory,
    required this.previousByCategory,
    required this.byMethod,
    required this.daily,
    required this.budgetPaise,
    required this.categoryBudgets,
    required this.emiPaise,
    required this.foodPaise,
    required this.linkedMeals,
    required this.linkedMealPaise,
    required this.junkMeals,
    required this.junkMealPaise,
    required this.iOwePaise,
    required this.owedToMePaise,
    required this.upcomingEmis,
    required this.upcomingEmiPaise,
    required this.incomePaise,
  });

  final LocalDate from;
  final LocalDate to;
  final int totalPaise;
  final int previousTotalPaise;

  /// Category id → paise, largest first.
  final Map<String, int> byCategory;
  final Map<String, int> previousByCategory;
  final Map<PaymentMethod, int> byMethod;

  /// Every day of the range, zero included.
  final Map<LocalDate, int> daily;

  /// Overall budget in force, only when the range starts on the 1st.
  final int? budgetPaise;

  /// Category id → budget, for categories with one (range starts on the 1st).
  final Map<String, int> categoryBudgets;
  final int emiPaise;
  final int foodPaise;
  final int linkedMeals;
  final int linkedMealPaise;
  final int junkMeals;
  final int junkMealPaise;
  final int iOwePaise;
  final int owedToMePaise;
  final int upcomingEmis;
  final int upcomingEmiPaise;

  /// Income in the range (§5.22L).
  final int incomePaise;
  int get savedPaise => incomePaise - totalPaise;

  /// Saved as a whole percent of income, or null without income.
  int? get savingsRate => incomePaise <= 0 ? null : (savedPaise * 100 / incomePaise).round();

  int get days => to.daysSince(from) + 1;

  /// The same number of days just before [from].
  static ({LocalDate from, LocalDate to}) previousRange(LocalDate from, LocalDate to) {
    final days = to.daysSince(from) + 1;
    if (from.day == 1) {
      // A month (or part of one) compares with the same days of the month before.
      final start = LocalDate(
        from.month == 1 ? from.year - 1 : from.year,
        from.month == 1 ? 12 : from.month - 1,
        1,
      );
      final lastDay = DateTime.utc(start.year, start.month + 1, 0).day;
      final end = LocalDate(start.year, start.month, days.clamp(1, lastDay));
      return (from: start, to: end);
    }
    return (from: from.addDays(-days), to: from.addDays(-1));
  }

  factory MoneyReport.build({
    required LocalDate from,
    required LocalDate to,
    required LocalDate today,
    required List<Expense> expenses,
    required List<Expense> previous,
    required List<Budget> budgets,
    required List<Debt> debts,
    required List<DebtPayment> payments,
    List<LoanChange> changes = const [],
    List<InstalmentSkip> skips = const [],
    List<Income> incomes = const [],
    required String emiCategoryId,
    required Set<String> foodCategoryIds,
    Set<String> junkMealIds = const {},
  }) {
    final inRange = [
      for (final e in expenses)
        if (!e.localDate.isBefore(from) && !e.localDate.isAfter(to)) e,
    ];
    Map<String, int> sumBy(Iterable<Expense> list) {
      final m = <String, int>{};
      for (final e in list) {
        m.update(e.categoryId, (v) => v + e.amountPaise, ifAbsent: () => e.amountPaise);
      }
      return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    }

    final byMethod = <PaymentMethod, int>{};
    final daily = {for (var d = from; !d.isAfter(to); d = d.addDays(1)) d: 0};
    var linked = 0, linkedPaise = 0, junk = 0, junkPaise = 0;
    final seenMeals = <String>{}, seenJunk = <String>{};
    for (final e in inRange) {
      byMethod.update(e.method, (v) => v + e.amountPaise, ifAbsent: () => e.amountPaise);
      daily.update(e.localDate, (v) => v + e.amountPaise);
      final meal = e.mealLogId;
      if (meal != null) {
        if (seenMeals.add(meal)) linked++;
        linkedPaise += e.amountPaise;
        if (junkMealIds.contains(meal)) {
          if (seenJunk.add(meal)) junk++;
          junkPaise += e.amountPaise;
        }
      }
    }
    final byCategory = sumBy(inRange);

    int? overall;
    final perCategory = <String, int>{};
    if (from.day == 1) {
      overall = budgetFor(from, null, budgets)?.amountPaise;
      for (final id in {for (final b in budgets) ?b.categoryId}) {
        final b = budgetFor(from, id, budgets);
        if (b != null) perCategory[id] = b.amountPaise;
      }
    }

    var owe = 0, owed = 0, upcoming = 0, upcomingPaise = 0;
    final horizon = today.addDays(30);
    for (final d in debts) {
      if (d.settled) continue;
      final status = DebtStatus(
        d,
        [
          for (final p in payments)
            if (p.debtId == d.id) p,
        ],
        changes: [
          for (final c in changes)
            if (c.debtId == d.id) c,
        ],
        skips: [
          for (final s in skips)
            if (s.debtId == d.id) s,
        ],
      );
      if (d.direction == DebtDirection.iOwe) {
        owe += status.remainingPaise;
      } else {
        owed += status.remainingPaise;
      }
      final emi = d.emi;
      if (emi == null || d.direction != DebtDirection.iOwe) continue;
      for (final row in status.schedule) {
        if (row.due.isAfter(horizon)) break;
        if (row.due.isBefore(today) || status.paidInstalments.contains(row.n)) continue;
        if (status.skippedInstalments.contains(row.n)) continue;
        upcoming++;
        upcomingPaise += row.emiPaise;
      }
    }

    return MoneyReport._(
      from: from,
      to: to,
      totalPaise: inRange.fold(0, (s, e) => s + e.amountPaise),
      previousTotalPaise: previous.fold(0, (s, e) => s + e.amountPaise),
      byCategory: byCategory,
      previousByCategory: sumBy(previous),
      byMethod: Map.fromEntries(
        byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      ),
      daily: daily,
      budgetPaise: overall,
      categoryBudgets: perCategory,
      emiPaise: byCategory[emiCategoryId] ?? 0,
      foodPaise: foodCategoryIds.fold(0, (s, id) => s + (byCategory[id] ?? 0)),
      linkedMeals: linked,
      linkedMealPaise: linkedPaise,
      junkMeals: junk,
      junkMealPaise: junkPaise,
      iOwePaise: owe,
      owedToMePaise: owed,
      upcomingEmis: upcoming,
      upcomingEmiPaise: upcomingPaise,
      incomePaise: incomes
          .where((i) => !i.localDate.isBefore(from) && !i.localDate.isAfter(to))
          .fold(0, (n, i) => n + i.amountPaise),
    );
  }

  /// Whole percent of [part] in the total, or 0 when nothing was spent.
  int sharePercent(int part) => totalPaise == 0 ? 0 : (part * 100 / totalPaise).round();

  /// Descriptive facts, most useful first (§5.21D: no advice).
  List<MoneyFact> get facts => [
    if (totalPaise > 0 || previousTotalPaise > 0) SpendVsPrevious(totalPaise - previousTotalPaise),
    if (savingsRate != null) Saved(savedPaise, savingsRate!),
    if (emiPaise > 0) EmiShare(sharePercent(emiPaise)),
    if (linkedMeals > 0) FoodPerMeal(linkedMealPaise, linkedMeals),
    for (final MapEntry(:key, :value) in categoryBudgets.entries)
      if ((byCategory[key] ?? 0) > value) CategoryOverBudget(key, (byCategory[key] ?? 0) - value),
    if (budgetPaise != null) BudgetUsed(totalPaise, budgetPaise!),
  ];
}

sealed class MoneyFact {
  const MoneyFact();
}

/// Positive: more than the previous period.
final class SpendVsPrevious extends MoneyFact {
  const SpendVsPrevious(this.differencePaise);
  final int differencePaise;
}

final class EmiShare extends MoneyFact {
  const EmiShare(this.percent);
  final int percent;
}

final class FoodPerMeal extends MoneyFact {
  const FoodPerMeal(this.totalPaise, this.meals);
  final int totalPaise;
  final int meals;
  int get averagePaise => (totalPaise / meals).round();
}

final class CategoryOverBudget extends MoneyFact {
  const CategoryOverBudget(this.categoryId, this.overPaise);
  final String categoryId;
  final int overPaise;
}

final class BudgetUsed extends MoneyFact {
  const BudgetUsed(this.spentPaise, this.budgetPaise);
  final int spentPaise;
  final int budgetPaise;
  int get percent => (spentPaise * 100 / budgetPaise).round();
}

/// Saved this period: income − spending, and its share of income.
final class Saved extends MoneyFact {
  const Saved(this.savedPaise, this.percent);
  final int savedPaise;
  final int percent;
}
