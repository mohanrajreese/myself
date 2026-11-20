/// Unit conversions between what the user types and the integer base units
/// stored in the database (docs/blueprint/03-database.md §1.1).
///
/// All arithmetic is integer arithmetic on exact conversion factors.
library;

import 'decimal_text.dart';

enum MassUnit { kg, lb }

enum LengthUnit { cm, inch }

enum VolumeUnit { ml, flOz }

enum DistanceUnit { km, mi }

// 1 lb = 453.59237 g (exact). 1 in = 25.4 mm (exact).
// 1 US fl oz = 29.5735295625 ml (exact).
const _gramsPerLbE5 = 45359237;
const _mlPerFlOzE10 = 295735295625;

int? _nonNegative(int? value) => value == null || value < 0 ? null : value;

/// Body weight or lifted load, in grams.
int? gramsFromText(String text, MassUnit unit) {
  final milli = _nonNegative(parseScaled(text, 3));
  if (milli == null) return null;
  return switch (unit) {
    MassUnit.kg => milli,
    MassUnit.lb => divRound(milli * _gramsPerLbE5, 100000000),
  };
}

/// One decimal place in the chosen unit.
String formatMass(int grams, MassUnit unit) => switch (unit) {
  MassUnit.kg => formatScaled(grams, 3, decimals: 1),
  MassUnit.lb => formatScaled(divRound(grams * 1000000, _gramsPerLbE5), 1, decimals: 1),
};

/// Height and other body lengths, in millimetres.
int? millimetresFromText(String text, LengthUnit unit) => switch (unit) {
  LengthUnit.cm => _nonNegative(parseScaled(text, 1)),
  LengthUnit.inch => switch (_nonNegative(parseScaled(text, 3))) {
    null => null,
    final milliInches => divRound(milliInches * 254, 10000),
  },
};

String formatLength(int millimetres, LengthUnit unit) => switch (unit) {
  LengthUnit.cm => formatScaled(millimetres, 1, decimals: 1),
  LengthUnit.inch => formatScaled(divRound(millimetres * 100, 254), 1, decimals: 1),
};

/// Drink volume, in millilitres.
int? millilitresFromText(String text, VolumeUnit unit) => switch (unit) {
  VolumeUnit.ml => _nonNegative(parseScaled(text, 0)),
  VolumeUnit.flOz => switch (_nonNegative(parseScaled(text, 3))) {
    null => null,
    final milliOunces => divRound(milliOunces * _mlPerFlOzE10, 10000000000000),
  },
};

String formatVolume(int millilitres, VolumeUnit unit) => switch (unit) {
  VolumeUnit.ml => '$millilitres',
  VolumeUnit.flOz => formatScaled(divRound(millilitres * 100000000000, _mlPerFlOzE10), 1, decimals: 1),
};
