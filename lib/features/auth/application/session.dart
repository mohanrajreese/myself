import 'package:meta/meta.dart';

import '../../../core/database/settings_repository.dart';
import '../domain/account.dart';

/// Who this device belongs to and whether they are currently signed in.
///
/// The app is usable whenever [active] is true. That depends only on what is
/// stored on the device, never on a live network session, so Praxis keeps
/// working offline after the first sign-in (PRD §9).
@immutable
final class SessionState {
  const SessionState({this.account, this.signedIn = false});

  final Account? account;
  final bool signedIn;

  bool get active => account != null && signedIn;
}

abstract final class SessionKeys {
  static const account = 'bound_account';
  static const signedIn = 'signed_in';
}

Future<SessionState> loadSession(SettingsRepository settings) async {
  final stored = await settings.read(SessionKeys.account);
  final signedIn = await settings.read(SessionKeys.signedIn);
  return SessionState(
    account: stored is Map<String, Object?> ? Account.fromJson(stored) : null,
    signedIn: signedIn == true,
  );
}
