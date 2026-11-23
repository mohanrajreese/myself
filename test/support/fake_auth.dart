import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/features/auth/domain/account.dart';
import 'package:fitbuddy/features/auth/domain/auth_repository.dart';

const testAccount = Account(id: 'user-1', email: 'asha@example.com', displayName: 'Asha Rao');
const otherAccount = Account(id: 'user-2', email: 'ravi@example.com', displayName: 'Ravi');

/// Scripted sign-in: no test talks to Google or Supabase.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.next = const Ok(testAccount), this.isConfigured = true});

  Result<Account> next;
  int signIns = 0;
  int signOuts = 0;

  /// The cloud session kept on the phone; null means none yet.
  @override
  Account? cloudAccount = testAccount;
  Result<Account> nextAnonymous = const Ok(testAccount);
  int anonymousSignIns = 0;

  @override
  bool isConfigured;

  @override
  Future<Result<Account>> signInWithGoogle() async {
    signIns++;
    return next;
  }

  @override
  Future<Result<Account>> signInAnonymously() async {
    anonymousSignIns++;
    final r = nextAnonymous;
    if (r.valueOrNull != null) cloudAccount = r.valueOrNull;
    return r;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    cloudAccount = null;
  }

  void failWith(Failure failure) => next = Err(failure);
}
