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

/// Erases everything this phone holds for the account. Defaults to the main
/// database; the app replaces it with the full eraser (private data, photos,
/// notifications, app lock).
final localDataEraserProvider = Provider<Future<void> Function()>(
  (ref) => ref.read(appDatabaseProvider).eraseAllData,
);

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

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
    await ref.read(localDataEraserProvider)();
    await _bind(incoming);
  }

  Future<bool>? _connecting;

  /// Connects this phone to its cloud user, creating an anonymous one the
  /// first time (D2 revised). A device account made offline is moved to the
  /// cloud user's id. False when offline or not configured; call again later.
  Future<bool> connectCloud() => _connecting ??= _connectCloud().whenComplete(
    () => _connecting = null,
  );

  Future<bool> _connectCloud() async {
    final auth = ref.read(authRepositoryProvider);
    if (!auth.isConfigured) return false;
    var cloud = auth.cloudAccount;
    if (cloud == null) {
      final result = await auth.signInAnonymously();
      cloud = result.valueOrNull;
      if (cloud == null) return false;
    }
    final local = state.account;
    if (local?.id == cloud.id) return true;
    if (local != null) {
      final moved = await ref
          .read(profileRepositoryProvider)
          .moveTo(fromId: local.id, toId: cloud.id);
      if (moved.failureOrNull != null) return false;
    }
    await _bind(cloud);
    return true;
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

  /// After the phone's data is erased: unbound from the old account and
  /// started again with a new local one (no sign-in, D2 revised).
  Future<void> forget() async {
    await ref.read(authRepositoryProvider).signOut();
    await _bind(newLocalAccount());
  }

  Future<void> _bind(Account account) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.write(SessionKeys.account, account.toJson());
    await settings.write(SessionKeys.signedIn, true);
    state = SessionState(account: account, signedIn: true);
  }
}
