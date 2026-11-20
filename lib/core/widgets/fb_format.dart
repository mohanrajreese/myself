import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../units/units.dart';
import '../utils/local_date.dart';
import 'l10n.dart';

/// Shared display formatting, so every screen shows dates, times and
/// amounts the same way (PRD §3.4 rule 8).
extension FbFormat on BuildContext {
  String dayLabel(LocalDate date, {LocalDate? today}) {
    if (today != null && date == today) return l10n.today;
    if (today != null && date == today.addDays(-1)) return l10n.yesterday;
    return DateFormat('EEE d MMM').format(DateTime(date.year, date.month, date.day));
  }

  String shortDate(LocalDate date) => DateFormat('d MMM').format(DateTime(date.year, date.month, date.day));

  String time(DateTime instant) => MaterialLocalizations.of(this).formatTimeOfDay(
    TimeOfDay.fromDateTime(instant.toLocal()),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(this),
  );

  String duration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return l10n.durationM(minutes);
    return l10n.durationHm(minutes ~/ 60, (minutes % 60).toString().padLeft(2, '0'));
  }

  String number(int value) => NumberFormat.decimalPattern().format(value);

  String mass(int grams, MassUnit unit) =>
      unit == MassUnit.kg ? l10n.valueKg(formatMass(grams, unit)) : l10n.valueLb(formatMass(grams, unit));

  String volume(int ml, VolumeUnit unit) =>
      unit == VolumeUnit.ml ? l10n.valueMl(number(ml)) : l10n.valueFlOz(formatVolume(ml, unit));

  /// "Down 0.6 kg", "Up 0.2 kg", "No change".
  String massChange(int deltaG, MassUnit unit) {
    if (deltaG == 0) return l10n.changeSame;
    final text = mass(deltaG.abs(), unit);
    return deltaG < 0 ? l10n.changeDown(text) : l10n.changeUp(text);
  }

  /// Integer kcal-milli to whole kilocalories, grouped.
  String kcal(int kcalMilli) => l10n.valueKcal(number((kcalMilli + 500) ~/ 1000));

  /// Integer mg to whole grams.
  String grams(int mg) => l10n.valueG(number((mg + 500) ~/ 1000));
}
