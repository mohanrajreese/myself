import '../../../core/utils/local_date.dart';

enum ExportFormat { json, csv }

final class ExportOptions {
  const ExportOptions({
    this.format = ExportFormat.json,
    this.from,
    this.to,
    this.includePrivate = false,
    this.includePhotos = false,
    this.passphrase,
  });
  final ExportFormat format;

  /// Inclusive; null means everything.
  final LocalDate? from;
  final LocalDate? to;

  /// Private space, bowel log, medication, screen time (§7.1). Off unless the
  /// user includes it after unlocking.
  final bool includePrivate;
  final bool includePhotos;

  /// At least 8 characters; null leaves the file unencrypted.
  final String? passphrase;

  static const minPassphrase = 8;

  List<String> get problems => [
    if (passphrase != null && passphrase!.length < minPassphrase) 'passphrase_short',
    if (from != null && to != null && to!.isBefore(from!)) 'range_reversed',
  ];
}

/// Fields as CSV text (RFC 4180): quoted when needed, quotes doubled.
String csvField(Object? v) {
  if (v == null) return '';
  final s = '$v';
  if (s.contains(RegExp('[",\r\n]')) || s.startsWith(' ') || s.endsWith(' ')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String toCsv(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return '';
  final cols = rows.first.keys.toList();
  final out = StringBuffer()..writeln(cols.map(csvField).join(','));
  for (final r in rows) {
    out.writeln(cols.map((c) => csvField(r[c])).join(','));
  }
  return out.toString();
}
