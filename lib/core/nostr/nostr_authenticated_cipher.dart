import 'dart:convert';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:recoverbull/recoverbull.dart';

final class NostrAuthenticatedCipherException implements Exception {
  final String message;
  final Object? cause;

  const NostrAuthenticatedCipherException(this.message, {this.cause});

  @override
  String toString() => 'NostrAuthenticatedCipherException: $message';
}

final class NostrAuthenticatedCipherKey {
  static final _hex32Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final String _hex;

  NostrAuthenticatedCipherKey(String hex) : _hex = hex.trim().toLowerCase() {
    if (!_hex32Pattern.hasMatch(_hex)) {
      throw const NostrAuthenticatedCipherException(
        'encryption key must be a 32-byte hex value',
      );
    }
  }
}

final class NostrAuthenticatedCiphertext {
  static const int minimumByteLength = 64;

  final String value;

  const NostrAuthenticatedCiphertext._(this.value);

  factory NostrAuthenticatedCiphertext(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const NostrAuthenticatedCipherException('ciphertext is required');
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(trimmed);
    } on FormatException catch (e) {
      throw NostrAuthenticatedCipherException(
        'ciphertext must be base64 encoded',
        cause: e,
      );
    }
    if (bytes.length < minimumByteLength) {
      throw const NostrAuthenticatedCipherException('ciphertext is too short');
    }
    return NostrAuthenticatedCiphertext._(trimmed);
  }
}

final class RecoverBullNostrAuthenticatedCipher {
  const RecoverBullNostrAuthenticatedCipher();

  NostrAuthenticatedCiphertext encrypt({
    required String plaintext,
    required NostrAuthenticatedCipherKey key,
  }) {
    try {
      final backup = RecoverBull.createBackup(
        secret: utf8.encode(plaintext),
        backupKey: HEX.decode(key._hex),
      );
      return NostrAuthenticatedCiphertext(base64.encode(backup.ciphertext));
    } on Exception catch (e) {
      throw NostrAuthenticatedCipherException(
        'failed to encrypt content',
        cause: e,
      );
    }
  }

  String decrypt({
    required NostrAuthenticatedCiphertext ciphertext,
    required NostrAuthenticatedCipherKey key,
  }) {
    try {
      final plaintext = RecoverBull.restoreBackup(
        backup: BullBackup(
          createdAt: 0,
          id: const [],
          ciphertext: base64.decode(ciphertext.value),
          salt: const [],
        ),
        backupKey: HEX.decode(key._hex),
      );
      return utf8.decode(plaintext);
    } on Exception catch (e) {
      throw NostrAuthenticatedCipherException(
        'failed to decrypt content',
        cause: e,
      );
    }
  }
}
