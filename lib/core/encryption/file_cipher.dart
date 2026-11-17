import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypts small files (photos) with AES-256-GCM. Output is
/// nonce ‖ ciphertext ‖ tag; tampering or a wrong key fails decryption.
final class FileCipher {
  FileCipher(List<int> key) : _key = SecretKey(key) {
    if (key.length != 32) throw ArgumentError('File key must be 32 bytes');
  }

  final SecretKey _key;
  static final _aes = AesGcm.with256bits();

  Future<Uint8List> encrypt(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: _key);
    return box.concatenation();
  }

  /// Throws [SecretBoxAuthenticationError] on a wrong key or altered data.
  Future<Uint8List> decrypt(List<int> sealed) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: _key));
  }
}
