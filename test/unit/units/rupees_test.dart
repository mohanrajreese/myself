import 'package:fitbuddy/core/units/rupees.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRupees', () {
    test('Indian grouping: lakhs and crores', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(99900), '₹999');
      expect(formatRupees(123456), '₹1,234.56');
      expect(formatRupees(12345600), '₹1,23,456');
      expect(formatRupees(12345650), '₹1,23,456.50');
      expect(formatRupees(150000000), '₹15,00,000');
      expect(formatRupees(25555700 * 100), '₹2,55,55,700');
    });

    test('whole rupees drop the paise unless asked', () {
      expect(formatRupees(1250000), '₹12,500');
      expect(formatRupees(1250000, alwaysPaise: true), '₹12,500.00');
      expect(formatRupees(1250050, wholeOnly: true), '₹12,501');
    });

    test('negative amounts keep the sign before the symbol', () {
      expect(formatRupees(-40000), '−₹400');
    });
  });

  group('parseRupees', () {
    test('accepts plain numbers, grouping, symbol and up to two decimals', () {
      expect(parseRupees('240'), 24000);
      expect(parseRupees('₹1,23,456.5'), 12345650);
      expect(parseRupees(' 12,500.05 '), 1250005);
      expect(parseRupees('0.5'), 50);
    });

    test('rejects empty, negative, three decimals and junk', () {
      for (final bad in ['', ' ', '-5', '1.234', 'abc', '1..2', '₹']) {
        expect(parseRupees(bad), isNull, reason: bad);
      }
    });

    test('rejects amounts above ₹1,00,00,00,000 (100 crore)', () {
      expect(parseRupees('1000000001'), isNull);
      expect(parseRupees('1000000000'), 100000000000);
    });
  });
}
