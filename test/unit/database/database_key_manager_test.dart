import 'dart:math';

import 'package:fitbuddy/core/encryption/database_key_manager.dart';
import 'package:fitbuddy/core/encryption/secret_store.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemorySecretStore store;
  late DatabaseKeyManager manager;

  setUp(() {
    store = InMemorySecretStore();
    manager = DatabaseKeyManager(store, random: Random(7));
  });

  test('creates a 256-bit hex key on first use and stores it', () async {
    final key = (await manager.keyFor(DatabaseId.app)).valueOrNull!;
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await store.read('db_key_app'), key);
  });

  test('returns the same key on later calls', () async {
    final first = (await manager.keyFor(DatabaseId.app)).valueOrNull;
    final second = (await DatabaseKeyManager(store).keyFor(DatabaseId.app)).valueOrNull;
    expect(second, first);
  });

  test('the private database has its own key', () async {
    final app = (await manager.keyFor(DatabaseId.app)).valueOrNull;
    final private = (await manager.keyFor(DatabaseId.private)).valueOrNull;
    expect(private, isNot(app));
    expect(await store.read('db_key_private'), private);
  });

  test('a damaged stored key is reported, never silently replaced', () async {
    await store.write('db_key_app', 'not-a-key');
    final result = await manager.keyFor(DatabaseId.app);
    expect(result.failureOrNull, const StorageFailure('database_key_corrupt'));
    expect(await store.read('db_key_app'), 'not-a-key');
  });

  test('a secure-storage error becomes a failure', () async {
    final result = await DatabaseKeyManager(_ThrowingStore()).keyFor(DatabaseId.app);
    expect(result.failureOrNull, const StorageFailure('database_key_unavailable'));
  });

  test('destroying keys removes both', () async {
    await manager.keyFor(DatabaseId.app);
    await manager.keyFor(DatabaseId.private);
    await manager.destroyAll();
    expect(await store.read('db_key_app'), isNull);
    expect(await store.read('db_key_private'), isNull);
  });
}

class _ThrowingStore implements SecretStore {
  @override
  Future<String?> read(String key) => throw StateError('keystore unavailable');
  @override
  Future<void> write(String key, String value) => throw StateError('keystore unavailable');
  @override
  Future<void> delete(String key) => throw StateError('keystore unavailable');
}
