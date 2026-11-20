import '../../../core/errors/result.dart';

/// Receipt photos: encrypted on the phone, never uploaded (§5.21A, C2).
abstract interface class ReceiptStore {
  Future<Result<void>> attach(String expenseId, List<int> imageBytes);
  Future<List<int>?> read(String expenseId);
  Future<Result<void>> remove(String expenseId);
  Future<void> removeAll();
}
