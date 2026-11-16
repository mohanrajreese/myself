/// Decimal text to and from scaled integers, with no floating point.
///
/// A value with scale 3 is stored in thousandths: `91.8` ↔ `91800`.
library;

final _decimal = RegExp(r'^(-?)(\d+)(?:[.,](\d+))?$');

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// Integer division of non-negative [a] by positive [b], rounding half up.
int divRound(int a, int b) => (a + b ~/ 2) ~/ b;

/// Parses [text] (dot or comma decimal separator) into an integer scaled by
/// 10^[scale]. Extra digits round half away from zero. Returns null when
/// [text] is not a plain decimal number.
int? parseScaled(String text, int scale) {
  final match = _decimal.firstMatch(text.trim());
  if (match == null) return null;
  final negative = match[1] == '-';
  final whole = int.parse(match[2]!);
  final fraction = match[3] ?? '';

  int scaledFraction;
  if (fraction.length <= scale) {
    scaledFraction = fraction.isEmpty ? 0 : int.parse(fraction) * _pow10(scale - fraction.length);
  } else {
    final kept = fraction.substring(0, scale);
    final roundUp = fraction.codeUnitAt(scale) >= 0x35; // '5'
    scaledFraction = (kept.isEmpty ? 0 : int.parse(kept)) + (roundUp ? 1 : 0);
  }
  final magnitude = whole * _pow10(scale) + scaledFraction;
  return negative ? -magnitude : magnitude;
}

/// Formats [value], which is scaled by 10^[scale], with exactly [decimals]
/// decimal places, rounding half away from zero.
String formatScaled(int value, int scale, {required int decimals}) {
  final negative = value < 0;
  var magnitude = value.abs();
  if (decimals < scale) {
    magnitude = divRound(magnitude, _pow10(scale - decimals));
  } else if (decimals > scale) {
    magnitude *= _pow10(decimals - scale);
  }
  final unit = _pow10(decimals);
  final whole = magnitude ~/ unit;
  final sign = negative && magnitude != 0 ? '-' : '';
  if (decimals == 0) return '$sign$whole';
  final fraction = (magnitude % unit).toString().padLeft(decimals, '0');
  return '$sign$whole.$fraction';
}
