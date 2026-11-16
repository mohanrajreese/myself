/// Application logging that cannot carry personal data.
///
/// A log line is an event code plus fields. Only integers, booleans, enums
/// and durations are written; every other value (strings, doubles, lists,
/// objects) is replaced by `<redacted>`. Record values and free text therefore
/// cannot reach the log even by mistake (PRD §7.3).
library;

enum LogLevel { info, warning, error }

typedef LogSink = void Function(String line);

final class AppLogger {
  const AppLogger({required this.sink});

  final LogSink sink;

  static final _code = RegExp(r'^[a-z][a-z0-9_]*$');

  void event(String code, [Map<String, Object?> fields = const {}]) {
    if (!_code.hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'must be a lower_snake_case event code');
    }
    final buffer = StringBuffer(code);
    fields.forEach((key, value) => buffer.write(' $key=${_safe(value)}'));
    sink(buffer.toString());
  }

  /// Logs that something failed, keeping only the error's type.
  void failure(String code, Object error) {
    if (!_code.hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'must be a lower_snake_case event code');
    }
    sink('$code error_type=${error.runtimeType}');
  }

  static String _safe(Object? value) => switch (value) {
    final int v => '$v',
    final bool v => '$v',
    final Duration v => '${v.inMilliseconds}ms',
    final Enum v => v.name,
    _ => '<redacted>',
  };
}
