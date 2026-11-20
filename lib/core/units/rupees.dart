/// Indian rupees as integer paise (PRD §5.21, D11).
library;

/// Largest amount accepted from input: ₹100 crore.
const maxRupeePaise = 100000000000;

/// "₹1,23,456.50": Indian grouping (3, then 2s). Paise are shown only when
/// not zero, unless [alwaysPaise]; [wholeOnly] rounds to whole rupees.
String formatRupees(int paise, {bool alwaysPaise = false, bool wholeOnly = false}) {
  final negative = paise < 0;
  var p = paise.abs();
  if (wholeOnly) p = ((p + 50) ~/ 100) * 100;
  final rupees = p ~/ 100;
  final rest = p % 100;
  final digits = '$rupees';
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$last3';
  }
  final tail = (rest != 0 || alwaysPaise) && !wholeOnly ? '.${'$rest'.padLeft(2, '0')}' : '';
  return '${negative ? '−' : ''}₹$grouped$tail';
}

final _amount = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');

/// Parses what the user typed ("₹1,23,456.5", "240") into paise. Null when
/// empty, negative, more than two decimals, or above [maxRupeePaise].
int? parseRupees(String text) {
  final cleaned = text.replaceAll('₹', '').replaceAll(',', '').replaceAll(' ', '').trim();
  final m = _amount.firstMatch(cleaned);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1)!);
  if (whole == null) return null;
  final frac = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0'));
  final paise = whole * 100 + frac;
  if (paise > maxRupeePaise) return null;
  return paise;
}
