import 'package:meta/meta.dart';

/// Why an operation did not succeed. A failure carries a stable [code] only,
/// never free text or record values, so it is always safe to log.
@immutable
sealed class Failure {
  const Failure(this.code);
  final String code;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is Failure &&
      other.code == code &&
      _extra == other._extra;

  Object? get _extra => null;

  @override
  int get hashCode => Object.hash(runtimeType, code, _extra);

  @override
  String toString() => '$runtimeType($code)';
}

/// User input was rejected. [field] names the form field.
final class ValidationFailure extends Failure {
  const ValidationFailure(this.field, super.code);
  final String field;

  @override
  Object? get _extra => field;
}

final class StorageFailure extends Failure {
  const StorageFailure(super.code);
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.code, {this.permanentlyDenied = false});
  final bool permanentlyDenied;

  @override
  Object? get _extra => permanentlyDenied;
}

final class PlatformFailure extends Failure {
  const PlatformFailure(super.code);
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.code);
}

final class AuthFailure extends Failure {
  const AuthFailure(super.code);
}
