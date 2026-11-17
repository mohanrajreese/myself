import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

/// Built-in measurement types (PRD §5.3). A custom type is stored as
/// `custom:<name>`.
abstract final class MeasurementTypes {
  static const waist = 'waist';
  static const chest = 'chest';
  static const hips = 'hips';
  static const neck = 'neck';
  static const arm = 'arm';
  static const thigh = 'thigh';
  static const bodyFat = 'body_fat';
  static const lengths = [waist, chest, hips, neck, arm, thigh];
  static const builtIn = [...lengths, bodyFat];

  static String custom(String name) => 'custom:${name.trim()}';
  static bool isPercent(String type) => type == bodyFat;
}

@immutable
final class Measurement {
  const Measurement({
    required this.id,
    required this.type,
    required this.valueMilli,
    required this.unit,
    required this.entryUnit,
    required this.occurredAt,
    required this.localDate,
    this.notes,
  });
  final String id;
  final String type;

  /// Thousandths of [unit].
  final int valueMilli;

  /// `cm` or `percent`.
  final String unit;

  /// `cm`, `in` or `percent`: what the user typed in.
  final String entryUnit;
  final DateTime occurredAt;
  final LocalDate localDate;
  final String? notes;
}

ValidationFailure? validateMeasurement(String type, int valueMilli) {
  final name = type.startsWith('custom:') ? type.substring(7) : type;
  if (name.trim().isEmpty || name.length > 40) {
    return const ValidationFailure('type', 'invalid');
  }
  final max = MeasurementTypes.isPercent(type) ? 75000 : 300000; // 75 % or 300 cm
  if (valueMilli < 1000 || valueMilli > max) {
    return const ValidationFailure('valueMilli', 'out_of_range');
  }
  return null;
}

abstract interface class MeasurementRepository {
  /// [valueMilli] is in thousandths of centimetres, or of percent for body fat.
  Future<Result<Measurement>> add({
    required String type,
    required int valueMilli,
    required String entryUnit,
    String? notes,
  });
  Future<Result<void>> update(String id, {required int valueMilli, String? notes});
  Future<Result<void>> delete(String id);

  /// The most recent entry of every type that has one.
  Stream<List<Measurement>> watchLatestPerType();

  /// All entries of one type, oldest first.
  Stream<List<Measurement>> watchHistory(String type);
}
