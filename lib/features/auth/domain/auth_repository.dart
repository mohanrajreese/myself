import '../../../core/errors/result.dart';
import 'account.dart';

/// Sign-in with Google through the backend. Failure codes:
/// `not_configured`, `cancelled`, `google_sign_in_failed`, `backend_rejected`
/// (AuthFailure) and `offline` (NetworkFailure).
abstract interface class AuthRepository {
  /// False when this build has no backend configuration.
  bool get isConfigured;

  Future<Result<Account>> signInWithGoogle();

  /// Ends the backend session. Local data is not touched.
  Future<void> signOut();
}
