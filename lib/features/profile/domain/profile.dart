import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/units/units.dart';
import '../../../core/utils/local_date.dart';

@immutable
final class UnitPreferences {
  const UnitPreferences({
    this.mass = MassUnit.kg,
    this.length = LengthUnit.cm,
    this.volume = VolumeUnit.ml,
    this.distance = DistanceUnit.km,
  });

  /// kg · cm · ml · km
  static const metric = UnitPreferences();

  /// lb · in · fl oz · mi
  static const imperial = UnitPreferences(
    mass: MassUnit.lb,
    length: LengthUnit.inch,
    volume: VolumeUnit.flOz,
    distance: DistanceUnit.mi,
  );

  final MassUnit mass;
  final LengthUnit length;
  final VolumeUnit volume;
  final DistanceUnit distance;
}

/// What the user can edit about themselves.
@immutable
final class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    this.dateOfBirth,
    this.heightMm,
    this.units = UnitPreferences.metric,
    this.wakeTime,
    this.workoutDays = const {},
  });

  final String displayName;
  final LocalDate? dateOfBirth;
  final int? heightMm;
  final UnitPreferences units;

  /// `HH:mm`, 24-hour.
  final String? wakeTime;

  /// ISO weekdays, 1 = Monday … 7 = Sunday.
  final Set<int> workoutDays;

  static final _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  /// Returns the first problem, or null when the draft can be saved.
  ValidationFailure? validate({required LocalDate today}) {
    final name = displayName.trim();
    if (name.isEmpty) return const ValidationFailure('displayName', 'required');
    if (name.length > 80) return const ValidationFailure('displayName', 'too_long');
    final height = heightMm;
    if (height != null && (height < 300 || height > 3000)) {
      return const ValidationFailure('heightMm', 'out_of_range');
    }
    final born = dateOfBirth;
    if (born != null && (born.isAfter(today) || born.year < 1900)) {
      return const ValidationFailure('dateOfBirth', 'out_of_range');
    }
    final wake = wakeTime;
    if (wake != null && !_time.hasMatch(wake)) {
      return const ValidationFailure('wakeTime', 'invalid_format');
    }
    if (workoutDays.any((day) => day < 1 || day > 7)) {
      return const ValidationFailure('workoutDays', 'out_of_range');
    }
    return null;
  }
}

@immutable
final class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.units,
    required this.timezone,
    required this.workoutDays,
    required this.onboardingCompleted,
    this.dateOfBirth,
    this.heightMm,
    this.wakeTime,
  });

  /// The signed-in account's id.
  final String id;
  final String displayName;
  final LocalDate? dateOfBirth;
  final int? heightMm;
  final UnitPreferences units;
  final String timezone;
  final String? wakeTime;
  final Set<int> workoutDays;
  final bool onboardingCompleted;
}
