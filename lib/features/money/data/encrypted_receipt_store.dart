import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/encryption/file_cipher.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/money.dart';
import '../domain/receipts.dart';

/// One encrypted receipt per expense in [directory] (app-private, excluded
/// from backups), indexed in `local_expense_receipts`.
final class EncryptedReceiptStore implements ReceiptStore {
  EncryptedReceiptStore({
    required AppDatabase db,
    required this.directory,
    required this.cipher,
    required this.money,
    required this.clock,
    required this.ids,
  }) : _db = db;

  final AppDatabase _db;
  final Directory directory;
  final FileCipher cipher;
  final MoneyRepository money;
  final Clock clock;
  final IdGenerator ids;

  static const maxBytes = 15 * 1024 * 1024;

  File _file(String name) => File('${directory.path}/$name');

  Future<ExpenseReceiptRow?> _row(String expenseId) =>
      (_db.select(_db.localExpenseReceipts)..where((t) => t.expenseId.equals(expenseId))).getSingleOrNull();

  @override
  Future<Result<void>> attach(String expenseId, List<int> imageBytes) async {
    if (imageBytes.isEmpty || imageBytes.length > maxBytes) {
      return const Err(ValidationFailure('receipt', 'out_of_range'));
    }
    return Result.guard(() async {
      await directory.create(recursive: true);
      final id = ids.newId();
      final name = '$id.bin';
      await _file(name).writeAsBytes(await cipher.encrypt(imageBytes), flush: true);
      final previous = await _row(expenseId);
      await _db.transaction(() async {
        if (previous != null) {
          await (_db.delete(_db.localExpenseReceipts)..where((t) => t.id.equals(previous.id))).go();
        }
        await _db
            .into(_db.localExpenseReceipts)
            .insert(
              LocalExpenseReceiptsCompanion.insert(
                id: id,
                expenseId: expenseId,
                fileName: name,
                takenAt: clock.now().toUtc(),
              ),
            );
      });
      if (previous != null) await _delete(previous.fileName);
      await money.setHasReceipt(expenseId, true);
    }, onError: (_) => const StorageFailure('receipt_write'));
  }

  @override
  Future<List<int>?> read(String expenseId) async {
    final row = await _row(expenseId);
    if (row == null) return null;
    final file = _file(row.fileName);
    if (!file.existsSync()) return null;
    return cipher.decrypt(await file.readAsBytes());
  }

  @override
  Future<Result<void>> remove(String expenseId) => Result.guard(() async {
    final row = await _row(expenseId);
    if (row == null) return;
    await (_db.delete(_db.localExpenseReceipts)..where((t) => t.id.equals(row.id))).go();
    await _delete(row.fileName);
    await money.setHasReceipt(expenseId, false);
  }, onError: (_) => const StorageFailure('receipt_write'));

  @override
  Future<void> removeAll() async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await _db.delete(_db.localExpenseReceipts).go();
  }

  Future<void> _delete(String name) async {
    final f = _file(name);
    if (f.existsSync()) await f.delete();
  }
}
