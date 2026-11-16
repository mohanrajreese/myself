import 'package:uuid/uuid.dart';

/// Source of new record identifiers.
abstract interface class IdGenerator {
  String newId();
}

/// Time-ordered UUIDs (version 7), generated on the device so a record keeps
/// the same identity locally and in the cloud.
final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();

  static const _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}
