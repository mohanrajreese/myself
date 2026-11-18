import '../core/units/units.dart';
import '../core/units/decimal_text.dart';
import '../features/body_measurements/domain/measurements.dart';
import '../l10n/generated/app_localizations.dart';

String measurementName(AppLocalizations l10n, String type) => switch (type) {
  MeasurementTypes.waist => l10n.mWaist,
  MeasurementTypes.chest => l10n.mChest,
  MeasurementTypes.hips => l10n.mHips,
  MeasurementTypes.neck => l10n.mNeck,
  MeasurementTypes.arm => l10n.mArm,
  MeasurementTypes.thigh => l10n.mThigh,
  MeasurementTypes.bodyFat => l10n.mBodyFat,
  _ => type.startsWith('custom:') ? type.substring(7) : type,
};

/// Thousandths of a centimetre (or percent) in the user's length unit.
String measurementValue(AppLocalizations l10n, int valueMilli, String type, LengthUnit length) {
  if (MeasurementTypes.isPercent(type)) {
    return '${formatScaled(valueMilli, 3, decimals: 1)} ${l10n.unitPercent}';
  }
  if (length == LengthUnit.cm) return '${formatScaled(valueMilli, 3, decimals: 1)} ${l10n.unitCm}';
  return '${formatScaled(divRound(valueMilli * 100, 254), 3, decimals: 1)} ${l10n.unitIn}';
}
