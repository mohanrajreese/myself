import '../units/units.dart';

/// Text codes used for units in both databases (docs/blueprint/03-database.md).
extension MassUnitCode on MassUnit {
  String get code => switch (this) {
    MassUnit.kg => 'kg',
    MassUnit.lb => 'lb',
  };
  static MassUnit parse(String code) => code == 'lb' ? MassUnit.lb : MassUnit.kg;
}

extension LengthUnitCode on LengthUnit {
  String get code => switch (this) {
    LengthUnit.cm => 'cm',
    LengthUnit.inch => 'in',
  };
  static LengthUnit parse(String code) => code == 'in' ? LengthUnit.inch : LengthUnit.cm;
}

extension VolumeUnitCode on VolumeUnit {
  String get code => switch (this) {
    VolumeUnit.ml => 'ml',
    VolumeUnit.flOz => 'fl_oz',
  };
  static VolumeUnit parse(String code) => code == 'fl_oz' ? VolumeUnit.flOz : VolumeUnit.ml;
}

extension DistanceUnitCode on DistanceUnit {
  String get code => switch (this) {
    DistanceUnit.km => 'km',
    DistanceUnit.mi => 'mi',
  };
  static DistanceUnit parse(String code) => code == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
}
