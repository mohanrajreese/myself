import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/money.dart';

final class DriftMoneyRepository implements MoneyRepository {
  DriftMoneyRepository(this._db, {required this.clock, required this.ids, required this.timeZone});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  static const _uuid = Uuid();
  static const _fail = StorageFailure('money_write');

  /// Same id on every phone, so seeded categories never duplicate on sync.
  static String categoryId(String key) => _uuid.v5(Namespace.url.value, 'https://fitbuddy.app/finance-category/$key');

  DateTime get _now => clock.now().toUtc();
  Future<void> _sync(String table, String id) => _db.enqueueForSync(table, id, _now);

  static bool _validAmount(int paise) => paise > 0 && paise <= maxRupeePaise;

  // ---- mapping ----

  static FinanceCategory _category(FinanceCategoryRow r) => FinanceCategory(
    id: r.id,
    name: r.name,
    iconKey: r.iconKey,
    systemKey: r.systemKey,
    archived: r.archived,
    sortOrder: r.sortOrder,
  );

  static Expense _expense(ExpenseRow r) => Expense(
    id: r.id,
    amountPaise: r.amountPaise,
    categoryId: r.categoryId,
    method: PaymentMethod.fromCode(r.method),
    occurredAt: r.occurredAt,
    localDate: r.localDate,
    note: r.note,
    mealLogId: r.mealLogId,
    debtPaymentId: r.debtPaymentId,
    recurringExpenseId: r.recurringExpenseId,
    hasReceipt: r.hasReceipt,
  );

  static Debt _debt(DebtRow r) => Debt(
    id: r.id,
    direction: DebtDirection.values.firstWhere((d) => d.code == r.direction),
    name: r.name,
    counterparty: r.counterparty,
    kind: DebtKind.values.firstWhere((k) => k.code == r.kind, orElse: () => DebtKind.other),
    principalPaise: r.principalPaise,
    startDate: r.startDate,
    interestRateBp: r.interestRateBp,
    dueDate: r.dueDate,
    emi: r.emiPaise == null
        ? null
        : EmiPlan(emiPaise: r.emiPaise!, day: r.emiDay!, count: r.emiCount!, first: r.firstEmiDate!),
    remind: r.remind,
    remindDaysBefore: r.remindDaysBefore,
    recordAsExpense: r.recordAsExpense,
    settled: r.status == 'settled',
    notes: r.notes,
  );

  static DebtPayment _payment(DebtPaymentRow r) => DebtPayment(
    id: r.id,
    debtId: r.debtId,
    amountPaise: r.amountPaise,
    paidAt: r.paidAt,
    localDate: r.localDate,
    instalmentNo: r.instalmentNo,
    note: r.note,
  );

  static RecurringExpense _recurring(RecurringExpenseRow r) => RecurringExpense(
    id: r.id,
    name: r.name,
    amountPaise: r.amountPaise,
    categoryId: r.categoryId,
    method: PaymentMethod.fromCode(r.method),
    rule: ScheduleRule.fromJson((jsonDecode(r.schedule) as Map).cast<String, Object?>()),
    remind: r.remind,
    active: r.active,
  );

  // ---- categories ----

  @override
  Future<void> seedCategories(Map<String, String> namesByKey) => _db.transaction(() async {
    final now = _now;
    for (final (i, (key, icon)) in defaultCategoryKeys.indexed) {
      final id = categoryId(key);
      final exists = await (_db.select(_db.financeCategories)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (exists != null) continue;
      await _db
          .into(_db.financeCategories)
          .insert(
            FinanceCategoriesCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              name: namesByKey[key] ?? key,
              systemKey: Value(key),
              iconKey: icon,
              sortOrder: Value(i),
            ),
          );
      await _sync('finance_categories', id);
    }
  });

  @override
  Stream<List<FinanceCategory>> watchCategories() =>
      (_db.select(_db.financeCategories)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map((rows) => rows.map(_category).toList());

  @override
  Future<Result<FinanceCategory>> addCategory(String name, {String iconKey = 'other'}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(ValidationFailure('name', 'name_required'));
    return Result.guard(() async {
      final id = ids.newId();
      final now = _now;
      await _db.transaction(() async {
        await _db
            .into(_db.financeCategories)
            .insert(
              FinanceCategoriesCompanion.insert(
                id: id,
                createdAt: now,
                updatedAt: now,
                name: trimmed,
                iconKey: iconKey,
                sortOrder: const Value(1000),
              ),
            );
        await _sync('finance_categories', id);
      });
      return FinanceCategory(id: id, name: trimmed, iconKey: iconKey, sortOrder: 1000);
    }, onError: (_) => _fail);
  }

  @override
  Future<Result<void>> archiveCategory(String id, {required bool archived}) => Result.guard(
    () => _db.transaction(() async {
      final now = _now;
      final n = await (_db.update(_db.financeCategories)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        FinanceCategoriesCompanion(archived: Value(archived), updatedAt: Value(now)),
      );
      if (n > 0) await _sync('finance_categories', id);
    }),
    onError: (_) => _fail,
  );

  // ---- expenses ----

  @override
  Future<Result<Expense>> addExpense(ExpenseDraft draft, {String? debtPaymentId, String? recurringExpenseId}) async {
    if (!_validAmount(draft.amountPaise)) return const Err(ValidationFailure('amount', 'amount_invalid'));
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: draft.at);
      final id = ids.newId();
      await _db.transaction(() => _insertExpense(id, draft, stamp, debtPaymentId, recurringExpenseId));
      return Expense(
        id: id,
        amountPaise: draft.amountPaise,
        categoryId: draft.categoryId,
        method: draft.method,
        occurredAt: stamp.occurredAt,
        localDate: stamp.localDate,
        note: _note(draft.note),
        mealLogId: draft.mealLogId,
        debtPaymentId: debtPaymentId,
        recurringExpenseId: recurringExpenseId,
      );
    }, onError: (_) => _fail);
  }

  static String? _note(String? n) => (n == null || n.trim().isEmpty) ? null : n.trim();

  Future<void> _insertExpense(
    String id,
    ExpenseDraft draft,
    LogStamp stamp,
    String? debtPaymentId,
    String? recurringExpenseId,
  ) async {
    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            createdAt: stamp.nowUtc,
            updatedAt: stamp.nowUtc,
            amountPaise: draft.amountPaise,
            categoryId: draft.categoryId,
            method: draft.method.code,
            occurredAt: stamp.occurredAt,
            localDate: stamp.localDate,
            tz: stamp.tz,
            note: Value(_note(draft.note)),
            mealLogId: Value(draft.mealLogId),
            debtPaymentId: Value(debtPaymentId),
            recurringExpenseId: Value(recurringExpenseId),
          ),
        );
    await _sync('expenses', id);
  }

  @override
  Future<Result<void>> updateExpense(String id, ExpenseDraft draft) async {
    if (!_validAmount(draft.amountPaise)) return const Err(ValidationFailure('amount', 'amount_invalid'));
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: draft.at);
      await _db.transaction(() async {
        final n = await (_db.update(_db.expenses)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
          ExpensesCompanion(
            updatedAt: Value(stamp.nowUtc),
            amountPaise: Value(draft.amountPaise),
            categoryId: Value(draft.categoryId),
            method: Value(draft.method.code),
            occurredAt: Value(stamp.occurredAt),
            localDate: Value(stamp.localDate),
            tz: Value(stamp.tz),
            note: Value(_note(draft.note)),
            mealLogId: Value(draft.mealLogId),
          ),
        );
        if (n == 0) throw StateError('missing');
        await _sync('expenses', id);
      });
    }, onError: (_) => _fail);
  }

  Future<void> _tombstone<T extends Table, R>(
    TableInfo<T, R> table,
    String name,
    Expression<bool> Function(T t) where,
    Insertable<R> Function(DateTime now) companion,
    String Function(R row) idOf,
  ) async {
    final now = _now;
    final rows = await (_db.select(table)..where(where)).get();
    if (rows.isEmpty) return;
    await (_db.update(table)..where(where)).write(companion(now));
    for (final r in rows) {
      await _db.enqueueForSync(name, idOf(r), now);
    }
  }

  Future<void> _deleteExpenseRows(Expression<bool> Function($ExpensesTable t) where) => _tombstone(
    _db.expenses,
    'expenses',
    (t) => where(t) & t.deletedAt.isNull(),
    (now) => ExpensesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    (r) => r.id,
  );

  @override
  Future<Result<void>> deleteExpense(String id) => Result.guard(
    () => _db.transaction(() async {
      await _deleteExpenseRows((t) => t.id.equals(id));
      await (_db.delete(_db.localExpenseReceipts)..where((t) => t.expenseId.equals(id))).go();
    }),
    onError: (_) => _fail,
  );

  @override
  Stream<List<Expense>> watchExpenses({required LocalDate from, required LocalDate to}) =>
      (_db.select(_db.expenses)
            ..where(
              (t) =>
                  t.localDate.isBiggerOrEqualValue(from.toString()) &
                  t.localDate.isSmallerOrEqualValue(to.toString()) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch()
          .map((rows) => rows.map(_expense).toList());

  @override
  Future<Expense?> expenseForMeal(String mealLogId) async {
    final row =
        await (_db.select(_db.expenses)
              ..where((t) => t.mealLogId.equals(mealLogId) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _expense(row);
  }

  @override
  Future<Result<void>> setHasReceipt(String expenseId, bool value) => Result.guard(
    () => _db.transaction(() async {
      final now = _now;
      final n = await (_db.update(_db.expenses)..where((t) => t.id.equals(expenseId) & t.deletedAt.isNull())).write(
        ExpensesCompanion(hasReceipt: Value(value), updatedAt: Value(now)),
      );
      if (n > 0) await _sync('expenses', expenseId);
    }),
    onError: (_) => _fail,
  );

  @override
  Stream<Set<String>> watchJunkMealIds({required LocalDate from, required LocalDate to}) {
    final items = _db.mealFoodItems;
    final meals = _db.mealLogs;
    final q = _db.selectOnly(items).join([innerJoin(meals, meals.id.equalsExp(items.mealLogId))])
      ..addColumns([items.mealLogId])
      ..where(
        items.junkCategory.isNotNull() &
            items.deletedAt.isNull() &
            meals.deletedAt.isNull() &
            meals.localDate.isBiggerOrEqualValue(from.toString()) &
            meals.localDate.isSmallerOrEqualValue(to.toString()),
      );
    return q.watch().map((rows) => {for (final r in rows) r.read(items.mealLogId)!});
  }

  // ---- budgets ----

  @override
  Future<Result<void>> setBudget({required String? categoryId, required int amountPaise, required LocalDate from}) {
    if (amountPaise < 0 || amountPaise > maxRupeePaise) {
      return Future.value(const Err(ValidationFailure('amount', 'amount_invalid')));
    }
    return Result.guard(
      () => _db.transaction(() async {
        final now = _now;
        Expression<bool> same($BudgetsTable t) =>
            t.effectiveFrom.equalsValue(from) &
            t.deletedAt.isNull() &
            (categoryId == null ? t.categoryId.isNull() : t.categoryId.equals(categoryId));
        final existing = await (_db.select(_db.budgets)..where(same)).getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.budgets)..where((t) => t.id.equals(existing.id))).write(
            BudgetsCompanion(amountPaise: Value(amountPaise), updatedAt: Value(now)),
          );
          await _sync('budgets', existing.id);
          return;
        }
        final id = ids.newId();
        await _db
            .into(_db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: id,
                createdAt: now,
                updatedAt: now,
                effectiveFrom: from,
                categoryId: Value(categoryId),
                amountPaise: amountPaise,
              ),
            );
        await _sync('budgets', id);
      }),
      onError: (_) => _fail,
    );
  }

  @override
  Future<Result<void>> removeBudget({required String? categoryId, required LocalDate from}) =>
      setBudget(categoryId: categoryId, amountPaise: 0, from: from);

  @override
  Stream<List<Budget>> watchBudgets() => (_db.select(_db.budgets)..where((t) => t.deletedAt.isNull())).watch().map(
    (rows) => [
      for (final r in rows)
        Budget(id: r.id, effectiveFrom: r.effectiveFrom, categoryId: r.categoryId, amountPaise: r.amountPaise),
    ],
  );

  // ---- debts ----

  DebtsCompanion _debtCompanion(Debt d, DateTime now) => DebtsCompanion(
    updatedAt: Value(now),
    direction: Value(d.direction.code),
    name: Value(d.name.trim()),
    counterparty: Value(d.counterparty.trim()),
    kind: Value(d.kind.code),
    principalPaise: Value(d.principalPaise),
    interestRateBp: Value(d.interestRateBp),
    startDate: Value(d.startDate),
    dueDate: Value(d.emi == null ? d.dueDate : null),
    emiPaise: Value(d.emi?.emiPaise),
    emiDay: Value(d.emi?.day),
    emiCount: Value(d.emi?.count),
    firstEmiDate: Value(d.emi?.first),
    remind: Value(d.remind),
    remindDaysBefore: Value(d.remindDaysBefore),
    recordAsExpense: Value(d.recordAsExpense),
    status: Value(d.settled ? 'settled' : 'open'),
    notes: Value(_note(d.notes)),
  );

  @override
  Future<Result<Debt>> saveDebt(Debt debt, {bool markPastInstalmentsPaid = false}) async {
    final problems = debt.problems;
    if (problems.isNotEmpty || debt.principalPaise > maxRupeePaise) {
      return Err(ValidationFailure('debt', problems.isEmpty ? 'amount_required' : problems.first));
    }
    return Result.guard(() async {
      final tz = await timeZone.currentTimeZoneId();
      final now = _now;
      final today = LocalDate.fromDateTime(clock.now().toLocal());
      final id = debt.id.isEmpty ? ids.newId() : debt.id;
      await _db.transaction(() async {
        final existing = await (_db.select(_db.debts)..where((t) => t.id.equals(id))).getSingleOrNull();
        final values = _debtCompanion(debt, now);
        if (existing == null) {
          await _db.into(_db.debts).insert(values.copyWith(id: Value(id), createdAt: Value(now)));
        } else {
          await (_db.update(_db.debts)..where((t) => t.id.equals(id))).write(values);
        }
        await _sync('debts', id);
        final emi = debt.emi;
        if (markPastInstalmentsPaid && emi != null) {
          final paid = {
            for (final p in await (_db.select(
              _db.debtPayments,
            )..where((t) => t.debtId.equals(id) & t.deletedAt.isNull() & t.instalmentNo.isNotNull())).get())
              p.instalmentNo!,
          };
          final due = emi.dueBy(today.addDays(-1)).clamp(0, emi.count); // before today
          for (var n = 1; n <= due; n++) {
            if (paid.contains(n)) continue;
            final day = emi.dueDate(n);
            final pid = ids.newId();
            await _db
                .into(_db.debtPayments)
                .insert(
                  DebtPaymentsCompanion.insert(
                    id: pid,
                    createdAt: now,
                    updatedAt: now,
                    debtId: id,
                    amountPaise: emi.emiPaise,
                    paidAt: DateTime(day.year, day.month, day.day, 12).toUtc(),
                    localDate: day,
                    tz: tz,
                    instalmentNo: Value(n),
                  ),
                );
            await _sync('debt_payments', pid);
          }
        }
      });
      return Debt(
        id: id,
        direction: debt.direction,
        name: debt.name.trim(),
        counterparty: debt.counterparty.trim(),
        kind: debt.kind,
        principalPaise: debt.principalPaise,
        startDate: debt.startDate,
        interestRateBp: debt.interestRateBp,
        dueDate: debt.emi == null ? debt.dueDate : null,
        emi: debt.emi,
        remind: debt.remind,
        remindDaysBefore: debt.remindDaysBefore,
        recordAsExpense: debt.recordAsExpense,
        settled: debt.settled,
        notes: _note(debt.notes),
      );
    }, onError: (e) => e is Failure ? e : _fail);
  }

  @override
  Future<Result<void>> deleteDebt(String id) => Result.guard(
    () => _db.transaction(() async {
      // Expenses already recorded from payments stay: the money was spent.
      await _tombstone(
        _db.debtPayments,
        'debt_payments',
        (t) => t.debtId.equals(id) & t.deletedAt.isNull(),
        (now) => DebtPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        (r) => r.id,
      );
      await _tombstone(
        _db.debts,
        'debts',
        (t) => t.id.equals(id) & t.deletedAt.isNull(),
        (now) => DebtsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        (r) => r.id,
      );
    }),
    onError: (_) => _fail,
  );

  @override
  Future<Result<void>> setSettled(String id, {required bool settled}) => Result.guard(
    () => _db.transaction(() async {
      final now = _now;
      final n = await (_db.update(_db.debts)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        DebtsCompanion(status: Value(settled ? 'settled' : 'open'), updatedAt: Value(now)),
      );
      if (n > 0) await _sync('debts', id);
    }),
    onError: (_) => _fail,
  );

  SimpleSelectStatement<$DebtsTable, DebtRow> get _liveDebts => _db.select(_db.debts)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

  @override
  Stream<List<Debt>> watchDebts() => _liveDebts.watch().map((rows) => rows.map(_debt).toList());

  @override
  Future<List<Debt>> debts() async => (await _liveDebts.get()).map(_debt).toList();

  // ---- payments ----

  @override
  Future<Result<DebtPayment>> addPayment(
    String debtId, {
    required int amountPaise,
    required DateTime at,
    int? instalmentNo,
    String? note,
  }) async {
    if (!_validAmount(amountPaise)) return const Err(ValidationFailure('amount', 'amount_invalid'));
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: at);
      final id = ids.newId();
      await _db.transaction(() async {
        final row = await (_db.select(_db.debts)..where((t) => t.id.equals(debtId) & t.deletedAt.isNull())).getSingle();
        if (instalmentNo != null) {
          final dup = await (_db.select(
            _db.debtPayments,
          )..where((t) => t.debtId.equals(debtId) & t.instalmentNo.equals(instalmentNo) & t.deletedAt.isNull())).get();
          if (dup.isNotEmpty) throw const ValidationFailure('instalment', 'instalment_paid');
        }
        await _db
            .into(_db.debtPayments)
            .insert(
              DebtPaymentsCompanion.insert(
                id: id,
                createdAt: stamp.nowUtc,
                updatedAt: stamp.nowUtc,
                debtId: debtId,
                amountPaise: amountPaise,
                paidAt: stamp.occurredAt,
                localDate: stamp.localDate,
                tz: stamp.tz,
                instalmentNo: Value(instalmentNo),
                note: Value(_note(note)),
              ),
            );
        await _sync('debt_payments', id);
        if (row.direction == DebtDirection.iOwe.code && row.recordAsExpense) {
          await _insertExpense(
            ids.newId(),
            (
              amountPaise: amountPaise,
              categoryId: categoryId('emi'),
              method: PaymentMethod.other,
              at: at,
              note: row.name,
              mealLogId: null,
            ),
            stamp,
            id,
            null,
          );
        }
      });
      return DebtPayment(
        id: id,
        debtId: debtId,
        amountPaise: amountPaise,
        paidAt: stamp.occurredAt,
        localDate: stamp.localDate,
        instalmentNo: instalmentNo,
        note: _note(note),
      );
    }, onError: (e) => e is Failure ? e : _fail);
  }

  @override
  Future<Result<void>> deletePayment(String id) => Result.guard(
    () => _db.transaction(() async {
      // The expense recorded from this payment goes with it.
      await _deleteExpenseRows((t) => t.debtPaymentId.equals(id));
      await _tombstone(
        _db.debtPayments,
        'debt_payments',
        (t) => t.id.equals(id) & t.deletedAt.isNull(),
        (now) => DebtPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        (r) => r.id,
      );
    }),
    onError: (_) => _fail,
  );

  SimpleSelectStatement<$DebtPaymentsTable, DebtPaymentRow> _livePayments(String? debtId) =>
      _db.select(_db.debtPayments)
        ..where((t) => t.deletedAt.isNull() & (debtId == null ? const Constant(true) : t.debtId.equals(debtId)))
        ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]);

  @override
  Stream<List<DebtPayment>> watchPayments({String? debtId}) =>
      _livePayments(debtId).watch().map((rows) => rows.map(_payment).toList());

  @override
  Future<List<DebtPayment>> payments({String? debtId}) async =>
      (await _livePayments(debtId).get()).map(_payment).toList();

  // ---- recurring ----

  @override
  Future<Result<RecurringExpense>> saveRecurring(RecurringExpense r) async {
    if (r.name.trim().isEmpty) return const Err(ValidationFailure('name', 'name_required'));
    if (!_validAmount(r.amountPaise)) return const Err(ValidationFailure('amount', 'amount_invalid'));
    return Result.guard(() async {
      final now = _now;
      final id = r.id.isEmpty ? ids.newId() : r.id;
      final values = RecurringExpensesCompanion(
        updatedAt: Value(now),
        name: Value(r.name.trim()),
        amountPaise: Value(r.amountPaise),
        categoryId: Value(r.categoryId),
        method: Value(r.method.code),
        schedule: Value(jsonEncode(r.rule.toJson())),
        remind: Value(r.remind),
        active: Value(r.active),
      );
      await _db.transaction(() async {
        final existing = await (_db.select(_db.recurringExpenses)..where((t) => t.id.equals(id))).getSingleOrNull();
        if (existing == null) {
          await _db.into(_db.recurringExpenses).insert(values.copyWith(id: Value(id), createdAt: Value(now)));
        } else {
          await (_db.update(_db.recurringExpenses)..where((t) => t.id.equals(id))).write(values);
        }
        await _sync('recurring_expenses', id);
      });
      return RecurringExpense(
        id: id,
        name: r.name.trim(),
        amountPaise: r.amountPaise,
        categoryId: r.categoryId,
        method: r.method,
        rule: r.rule,
        remind: r.remind,
        active: r.active,
      );
    }, onError: (_) => _fail);
  }

  @override
  Future<Result<void>> deleteRecurring(String id) => Result.guard(
    () => _db.transaction(
      () => _tombstone(
        _db.recurringExpenses,
        'recurring_expenses',
        (t) => t.id.equals(id) & t.deletedAt.isNull(),
        (now) => RecurringExpensesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        (r) => r.id,
      ),
    ),
    onError: (_) => _fail,
  );

  SimpleSelectStatement<$RecurringExpensesTable, RecurringExpenseRow> get _liveRecurring =>
      _db.select(_db.recurringExpenses)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name)]);

  @override
  Stream<List<RecurringExpense>> watchRecurring() =>
      _liveRecurring.watch().map((rows) => rows.map(_recurring).toList());

  @override
  Future<List<RecurringExpense>> recurring() async => (await _liveRecurring.get()).map(_recurring).toList();
}
