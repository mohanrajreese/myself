import 'failure.dart';

/// Outcome of an operation that can fail. Repositories return this instead of
/// throwing, so exceptions never cross the data layer.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok(transform(value)),
    Err<T>(:final failure) => Err(failure),
  };

  R when<R>({required R Function(T value) ok, required R Function(Failure failure) err}) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };

  /// Runs [body]; anything it throws becomes the failure chosen by [onError].
  /// The thrown object's message is deliberately not kept.
  static Future<Result<T>> guard<T>(
    Future<T> Function() body, {
    required Failure Function(Object error) onError,
  }) async {
    try {
      return Ok(await body());
    } on Object catch (error) {
      return Err(onError(error));
    }
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
