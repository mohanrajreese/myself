import '../../../core/errors/result.dart';
import 'account.dart';

/// Sign-in with Google through the backend. Failure codes:
/// `not_configured`, `cancelled`, `google_sign_in_failed`, `backend_rejected`
/// (AuthFailure) and `offline` (NetworkFailure).
abstract interface class AuthRepository {
  /// False when this build has no backend configuration.
  bool get isConfigured;

  Future<Result<Account>> signInWithGoogle();

  /// The cloud user whose session is kept on this phone, if any.
  Account? get cloudAccount;

  /// Creates a cloud user with no sign-in screen (D2 revised). Failure codes
  /// as for [signInWithGoogle].
  Future<Result<Account>> signInAnonymously();

  /// Ends the backend session. Local data is not touched.
  Future<void> signOut();
}
