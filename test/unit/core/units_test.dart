import 'package:fitbuddy/core/units/decimal_text.dart';
import 'package:fitbuddy/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decimal text', () {
    test('parses decimals into scaled integers without floating point', () {
      expect(parseScaled('91.8', 3), 91800);
      expect(parseScaled('0.1', 3), 100);
      expect(parseScaled('12', 3), 12000);
      expect(parseScaled('12,5', 3), 12500);
      expect(parseScaled('  7.25 ', 2), 725);
      expect(parseScaled('1.2345', 3), 1235); // rounds half up
      expect(parseScaled('-3.5', 1), -35);
    });

    test('rejects text that is not a plain decimal number', () {
      for (final bad in ['', 'abc', '1.2.3', '1e3', '--1', '.']) {
        expect(parseScaled(bad, 3), isNull, reason: bad);
      }
    });

    test('formats scaled integers with a fixed number of decimals', () {
      expect(formatScaled(91800, 3, decimals: 1), '91.8');
      expect(formatScaled(91850, 3, decimals: 1), '91.9');
      expect(formatScaled(91849, 3, decimals: 1), '91.8');
      expect(formatScaled(2500, 3, decimals: 0), '3');
      expect(formatScaled(-35, 1, decimals: 1), '-3.5');
      expect(formatScaled(5, 3, decimals: 2), '0.01');
    });
  });

  group('mass', () {
    test('kilograms and pounds convert to grams', () {
      expect(gramsFromText('91.8', MassUnit.kg), 91800);
      expect(gramsFromText('200', MassUnit.lb), 90718); // 200 lb = 90,718.474 g
      expect(gramsFromText('135', MassUnit.lb), 61235);
    });

    test('grams display in either unit', () {
      expect(formatMass(91800, MassUnit.kg), '91.8');
      expect(formatMass(90718, MassUnit.lb), '200.0');
      expect(formatMass(61235, MassUnit.lb), '135.0');
    });

    test('a value entered in pounds reads back as entered', () {
      for (final text in ['0.5', '45', '135', '202.4', '315']) {
        final grams = gramsFromText(text, MassUnit.lb)!;
        expect(double.parse(formatMass(grams, MassUnit.lb)), double.parse(text), reason: text);
      }
    });
  });

  group('length', () {
    test('centimetres and inches convert to millimetres', () {
      expect(millimetresFromText('172.5', LengthUnit.cm), 1725);
      expect(millimetresFromText('70', LengthUnit.inch), 1778);
    });

    test('millimetres display in either unit', () {
      expect(formatLength(1725, LengthUnit.cm), '172.5');
      expect(formatLength(1778, LengthUnit.inch), '70.0');
    });
  });

  group('volume', () {
    test('millilitres and US fluid ounces convert', () {
      expect(millilitresFromText('250', VolumeUnit.ml), 250);
      expect(millilitresFromText('8', VolumeUnit.flOz), 237); // 236.588 ml
      expect(formatVolume(237, VolumeUnit.flOz), '8.0');
      expect(formatVolume(2500, VolumeUnit.ml), '2500');
    });
  });

  test('unknown or negative input yields null', () {
    expect(gramsFromText('heavy', MassUnit.kg), isNull);
    expect(gramsFromText('-1', MassUnit.kg), isNull);
    expect(millimetresFromText('', LengthUnit.cm), isNull);
  });
}
