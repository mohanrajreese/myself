import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/failure.dart';
import '../domain/account.dart';
import 'session.dart';

/// What happened when the user tried to sign in.
sealed class SignInOutcome {
  const SignInOutcome();
}

final class SignedIn extends SignInOutcome {
  const SignedIn();
}

final class SignInFailed extends SignInOutcome {
  const SignInFailed(this.failure);
  final Failure failure;
}

/// The phone already holds another account's data. Nothing has changed yet;
/// call [SessionController.replaceAccount] once the user agrees to erase it.
final class DifferentAccount extends SignInOutcome {
  const DifferentAccount({required this.existing, required this.incoming});
  final Account existing;
  final Account incoming;
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => ref.watch(initialSessionProvider);

  Future<SignInOutcome> signIn() async {
    final result = await ref.read(authRepositoryProvider).signInWithGoogle();
    final failure = result.failureOrNull;
    if (failure != null) return SignInFailed(failure);

    final incoming = result.valueOrNull!;
    final existing = state.account;
    if (existing != null && existing.id != incoming.id) {
      return DifferentAccount(existing: existing, incoming: incoming);
    }
    await _bind(incoming);
    return const SignedIn();
  }

  /// Erases everything stored for the previous account, then binds [incoming].
  Future<void> replaceAccount(Account incoming) async {
    await ref.read(appDatabaseProvider).eraseAllData();
    await _bind(incoming);
  }

  /// The user declined to replace the existing data.
  Future<void> cancelReplace() => ref.read(authRepositoryProvider).signOut();

  /// Returns to the sign-in screen. Records stay on the phone, encrypted;
  /// signing in again with the same account continues where they left off.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(settingsRepositoryProvider).write(SessionKeys.signedIn, false);
    state = SessionState(account: state.account);
  }

  Future<void> _bind(Account account) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.write(SessionKeys.account, account.toJson());
    await settings.write(SessionKeys.signedIn, true);
    state = SessionState(account: account, signedIn: true);
  }
}
