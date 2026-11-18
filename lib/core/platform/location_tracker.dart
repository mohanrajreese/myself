import 'package:geolocator_android/geolocator_android.dart';

enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// One position fix in integer units (1e-7 degrees, decimetres).
typedef LocationFix = ({int latE7, int lonE7, int? accuracyDm, DateTime at});

/// While-in-use location for optional GPS workouts (§5.7). Manual logging
/// never touches this.
abstract interface class LocationTracker {
  Future<LocationAccess> access();
  Future<LocationAccess> request();

  /// Fixes while the workout runs; a foreground notification keeps it going
  /// with the screen off.
  Stream<LocationFix> track({required String title, required String text});
  Future<void> openSettings();
}

final class DeviceLocationTracker implements LocationTracker {
  DeviceLocationTracker([GeolocatorAndroid? plugin]) : _plugin = plugin ?? GeolocatorAndroid();
  final GeolocatorAndroid _plugin;

  LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await _plugin.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      return _map(await _plugin.checkPermission());
    } on Object {
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> request() async {
    try {
      if (!await _plugin.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      return _map(await _plugin.requestPermission());
    } on Object {
      return LocationAccess.denied;
    }
  }

  @override
  Stream<LocationFix> track({required String title, required String text}) => _plugin
      .getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 3),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            notificationChannelName: title,
          ),
        ),
      )
      .map(
        (p) => (
          latE7: (p.latitude * 1e7).round(),
          lonE7: (p.longitude * 1e7).round(),
          accuracyDm: (p.accuracy * 10).round(),
          at: p.timestamp.toUtc(),
        ),
      );

  @override
  Future<void> openSettings() async {
    try {
      await _plugin.openAppSettings();
    } on Object {
      // Nothing more to do; the screen still explains.
    }
  }
}
