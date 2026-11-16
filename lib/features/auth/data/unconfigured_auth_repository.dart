import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/account.dart';
import '../domain/auth_repository.dart';

/// Used when the build has no Supabase or Google configuration.
final class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  bool get isConfigured => false;

  @override
  Future<Result<Account>> signInWithGoogle() async => const Err(AuthFailure('not_configured'));

  @override
  Future<void> signOut() async {}
}
