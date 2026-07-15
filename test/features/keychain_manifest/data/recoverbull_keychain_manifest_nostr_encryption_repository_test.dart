import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed 32-byte key used for the envelope tamper and golden vectors, so the
/// wire format is locked independently of key derivation (which the KI3 vector
/// covers separately).
const _fixedKeyHex =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// A frozen `base64(nonce ‖ AES-256-CBC ct ‖ HMAC-SHA256 32)` blob, produced
/// once with [_fixedKeyHex] over [_goldenManifest]. F2: this decrypt-direction
/// golden locks the post-KC-7 blob format as the frozen v1 envelope - if the
/// format ever changes, decrypting this literal fails CI. Append-only.
const _goldenEnvelope =
    'nJJJ33LKhm5jFaXyy94ed+JWguuB4XWXgEg9S2Mm7cfRiJGFGKBuq9PWGYsggDPsSyjRwX2Ng'
    'Lnds9bipCH06NErEwxFmDMQWdtqKWqueKFMq2n2Q4dQwP5dEOIEDaiDu8ce0l2HyoPfyNEXAMd'
    'TBKcciAeTDHzUYkrtTsTnm9jM7K+tXDPlzlvc0VgopEk2edGe2ck1bXpFZBsV0mkTt/h+pRIC5'
    '5hWgstp7+wWcQXQtBfZKV9uYOR3l2xEbmjCo7ml6rKFZ8FP3+VggdlhX1Bi0ermJRwetScm702'
    'kgPvd/uS0OPzuYGkK7d+WaKDH7GcI8JdZde4POifYjj7m5EsyvcOImPcuS9icjRVDRLveTL+LY'
    'ok+5jH8CUhS5DHkTItJqomZUKRSYzVN37ZU1oYsQ05Zh+TkdbYSWXeYmP//wRuqFb2Ijz87XhB'
    'AuspN0xoTMRL0svGO0X0TJxxnXsYWELyV2PXdWXJO/hgq79VZgOPnZd9mkgtnB4YjoVmg/Bmrp'
    '12+sgpVg94SVSL2NYev6SM79YILrl7qjUYoxPdJcDgZMMhPwQGkAQBf63rEC++AgD/kazpuaGL'
    'LAjvflTRILrGYefNjbFPppux/O2Wy5eoQIgF9lEfLFJUR9tcWK+fiDJN+3dmXko/neIjMajQyh'
    'X9/kWteEnpKZ+Y9jVtxHjtu/ch/QMZ8plw8pmKZ9JX8UAUw7HP7HsCHuH0yXvfWhrscFb9hkVu'
    '58Ct1jNjgkPKWtezlDTjgL+oBTSQKWcbYz/ITD9v7Z1ZLg9rrICfy2ZDwgUZ4gMHjQ/G9/N5p'
    '5ckIVB9RFzmJ2SxIak9tlLWTHB7jshGFJ36upModG1xu+obrpHmhhOmuuH6Ft12fWXE0sWXUyq'
    'ojC9UWjpJ8jx4RGqJB5fPoi4GaZPSVgQ==';

void main() {
  const repository = RecoverBullKeychainManifestNostrEncryptionRepository();
  final key = KeychainManifestNostrEncryptionKey(_fixedKeyHex);

  test('round-trips a snapshot through encrypt then decrypt', () {
    final ciphertext = repository.encryptSnapshot(
      snapshot: KeychainManifestNostrSnapshot(manifestFile: _goldenManifest()),
      key: key,
    );

    final snapshot = repository.decryptSnapshot(
      ciphertext: ciphertext,
      key: key,
    );

    expect(snapshot.manifestFile.parentFingerprint, 'fedcba98');
    expect(
      snapshot.manifestFile.entries.single.materializations.single.walletId,
      'btc-wallet',
    );
  });

  test('decrypts the frozen v1 golden envelope to the golden manifest', () {
    final snapshot = repository.decryptSnapshot(
      ciphertext: KeychainManifestNostrCiphertext(_goldenEnvelope),
      key: key,
    );

    expect(snapshot.version, KeychainManifestNostrSnapshot.currentVersion);
    expect(snapshot.manifestFile.parentFingerprint, 'fedcba98');
    expect(
      snapshot.manifestFile.entries.single.reservationId,
      'btcpay_wallet_seed',
    );
    expect(
      snapshot.manifestFile.entries.single.materializations.single.walletId,
      'btc-wallet',
    );
  });

  group('authentication (P16t)', () {
    test('a flipped ciphertext byte fails decryption', () {
      expect(
        () => repository.decryptSnapshot(
          ciphertext: _tamperedAtByteIndex(_goldenEnvelope, 40),
          key: key,
        ),
        throwsA(isA<KeychainManifestNostrEncryptionException>()),
      );
    });

    test('a flipped HMAC byte fails decryption', () {
      final bytes = base64.decode(_goldenEnvelope);
      // The HMAC is the last 32 bytes of the merged blob.
      final hmacByteIndex = bytes.length - 1;
      expect(
        () => repository.decryptSnapshot(
          ciphertext: _tamperedAtByteIndex(_goldenEnvelope, hmacByteIndex),
          key: key,
        ),
        throwsA(isA<KeychainManifestNostrEncryptionException>()),
      );
    });

    test('a different key fails decryption', () {
      final wrongKey = KeychainManifestNostrEncryptionKey(
        'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100',
      );
      expect(
        () => repository.decryptSnapshot(
          ciphertext: KeychainManifestNostrCiphertext(_goldenEnvelope),
          key: wrongKey,
        ),
        throwsA(isA<KeychainManifestNostrEncryptionException>()),
      );
    });
  });
}

/// Flips every bit of one byte of the merged blob and re-encodes it.
KeychainManifestNostrCiphertext _tamperedAtByteIndex(String blob, int index) {
  final bytes = base64.decode(blob);
  bytes[index] = bytes[index] ^ 0xff;
  return KeychainManifestNostrCiphertext(base64.encode(bytes));
}

KeychainManifestFile _goldenManifest() {
  return KeychainManifestFile(
    parentFingerprint: 'fedcba98',
    generatedAt: 20,
    entries: [
      KeychainManifestFileEntry(
        parentFingerprint: 'fedcba98',
        bip85DerivationPath: "39'/0'/12'/100'",
        reservationId: 'btcpay_wallet_seed',
        entryType: 'walletSeed',
        ownerFeature: 'btcpay',
        bip85Application: 39,
        bip85Index: 100,
        createdAt: 10,
        updatedAt: 10,
        materializations: [
          KeychainManifestFileWalletMaterialization(
            walletId: 'btc-wallet',
            entryId: "fedcba98:39'/0'/12'/100'",
            childSeedFingerprint: '0123abcd',
            network: 'bitcoinMainnet',
            scriptType: 'bip84',
            createdAt: 10,
            updatedAt: 10,
          ),
        ],
      ),
    ],
  );
}
