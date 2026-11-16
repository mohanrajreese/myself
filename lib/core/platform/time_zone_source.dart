/// The device's current IANA timezone identifier, for example `Asia/Kolkata`.
abstract interface class TimeZoneSource {
  Future<String> currentTimeZoneId();
}
