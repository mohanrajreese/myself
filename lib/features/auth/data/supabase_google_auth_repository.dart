import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/encryption/secret_store.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/account.dart';
import '../domain/auth_repository.dart';

/// Keeps the Supabase session in Keystore-backed storage instead of shared
/// preferences.
final class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this._store);

  static const _key = 'supabase_session';
  final SecretStore _store;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => await _store.read(_key) != null;

  @override
  Future<String?> accessToken() => _store.read(_key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_key, persistSessionString);

  @override
  Future<void> removePersistedSession() => _store.delete(_key);
}

/// Native Google account chooser, then a Supabase session from the returned
/// ID token (docs/blueprint/01-architecture.md §7).
final class SupabaseGoogleAuthRepository implements AuthRepository {
  SupabaseGoogleAuthRepository({required this.client, required this.googleWebClientId});

  final SupabaseClient client;
  final String googleWebClientId;
  Future<void>? _googleReady;

  @override
  bool get isConfigured => true;

  @override
  Future<Result<Account>> signInWithGoogle() async {
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize(serverClientId: googleWebClientId));
      final google = await GoogleSignIn.instance.authenticate();
      final idToken = google.authentication.idToken;
      if (idToken == null) return const Err(AuthFailure('google_sign_in_failed'));

      final response = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      final user = response.user;
      if (user == null) return const Err(AuthFailure('backend_rejected'));
      return Ok(
        Account(
          id: user.id,
          email: user.email ?? google.email,
          displayName: google.displayName ?? user.userMetadata?['full_name'] as String?,
        ),
      );
    } on GoogleSignInException catch (error) {
      return Err(
        error.code == GoogleSignInExceptionCode.canceled
            ? const AuthFailure('cancelled')
            : const AuthFailure('google_sign_in_failed'),
      );
    } on SocketException {
      return const Err(NetworkFailure('offline'));
    } on AuthException {
      return const Err(AuthFailure('backend_rejected'));
    } on Object {
      return const Err(AuthFailure('google_sign_in_failed'));
    }
  }

  @override
  Account? get cloudAccount {
    final user = client.auth.currentUser;
    return user == null ? null : Account(id: user.id);
  }

  @override
  Future<Result<Account>> signInAnonymously() async {
    try {
      final user = (await client.auth.signInAnonymously()).user;
      if (user == null) return const Err(AuthFailure('backend_rejected'));
      return Ok(Account(id: user.id));
    } on SocketException {
      return const Err(NetworkFailure('offline'));
    } on AuthRetryableFetchException {
      return const Err(NetworkFailure('offline'));
    } on AuthException {
      return const Err(AuthFailure('backend_rejected'));
    } on Object {
      return const Err(AuthFailure('backend_rejected'));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut(scope: SignOutScope.local);
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Signing out must always succeed locally, including offline.
    }
  }
}
