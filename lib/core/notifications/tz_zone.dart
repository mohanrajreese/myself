import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../scheduling/occurrence_calculator.dart';

bool _loaded = false;

/// Loads the bundled IANA database once.
void ensureTimeZonesLoaded() {
  if (_loaded) return;
  tzdata.initializeTimeZones();
  _loaded = true;
}

/// Offsets from the IANA database for [id]; UTC when the id is unknown.
final class IanaZone implements TimeZoneRules {
  IanaZone(String id) : location = _locate(id);
  final tz.Location location;

  static tz.Location _locate(String id) {
    ensureTimeZonesLoaded();
    try {
      return tz.getLocation(id);
    } on Object {
      return tz.UTC;
    }
  }

  @override
  Duration offsetAt(DateTime instant) => location.timeZone(instant.toUtc().millisecondsSinceEpoch).offset;
}
