import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/merchant_payments/application/merchant_key_derivation_service.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MerchantKeyDerivationService service;
  late String xprv;

  setUp(() {
    service = MerchantKeyDerivationService();

    // Use standard test mnemonic (same as recoverbull_bip85_test)
    final mnemonic = Mnemonic.fromWords(
      words: List.generate(11, (index) => 'zoo') + ['wrong'],
    );
    xprv = Bip32Derivation.getXprvFromSeed(
      Uint8List.fromList(mnemonic.seed),
      Network.bitcoinMainnet,
    );
  });

  group('MerchantKeyDerivationService', () {
    group('deriveAesKey', () {
      test('returns 32 bytes for AES-256', () async {
        final key = await service.deriveAesKey(xprv: xprv, index: 0);

        expect(key.length, equals(32));
      });

      test('derives different keys for different indices', () async {
        final key0 = await service.deriveAesKey(xprv: xprv, index: 0);
        final key1 = await service.deriveAesKey(xprv: xprv, index: 1);
        final key2 = await service.deriveAesKey(xprv: xprv, index: 2);

        expect(key0, isNot(equals(key1)));
        expect(key0, isNot(equals(key2)));
        expect(key1, isNot(equals(key2)));
      });

      test('derives same key for same index (deterministic)', () async {
        final key1 = await service.deriveAesKey(xprv: xprv, index: 0);
        final key2 = await service.deriveAesKey(xprv: xprv, index: 0);

        expect(key1, equals(key2));
      });

      test('uses correct BIP85 path format', () {
        // Path should be: m/83696968'/128169'/256'/2026'/{index}'
        final expectedApplication = 83696968;
        final expectedSubApp = 128169;
        final expectedYear = 2026;

        // Verify path format using service's static method
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/128169'/256'/2026'/0'",
            'aes',
          ),
          isTrue,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/128169'/256'/2026'/5'",
            'aes',
          ),
          isTrue,
        );

        // Invalid paths
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/12345'/128169'/256'/2026'/0'",
            'aes',
          ),
          isFalse,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/99999'/256'/2026'/0'",
            'aes',
          ),
          isFalse,
        );
      });
    });

    group('deriveServerPassword', () {
      test('returns 21-character Base64 string', () async {
        final password = await service.deriveServerPassword(xprv: xprv);

        expect(password.length, equals(21));
        // Base64url characters: A-Z, a-z, 0-9, -, _
        expect(
          RegExp(r'^[A-Za-z0-9_-]{21}$').hasMatch(password),
          isTrue,
        );
      });

      test('derives same password for same xprv (deterministic)', () async {
        final password1 = await service.deriveServerPassword(xprv: xprv);
        final password2 = await service.deriveServerPassword(xprv: xprv);

        expect(password1, equals(password2));
      });

      test('uses correct BIP85 path format', () {
        // Path should be: m/83696968'/707764'/21'/2026'/
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/707764'/21'/2026'",
            'password',
          ),
          isTrue,
        );

        // Invalid paths
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/12345'/707764'/21'/2026'",
            'password',
          ),
          isFalse,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/99999'/21'/2026'",
            'password',
          ),
          isFalse,
        );
      });

      test('provides sufficient entropy (~120 bits)', () async {
        final password = await service.deriveServerPassword(xprv: xprv);

        // 21 base64 characters provide ~126 bits of entropy (21 * 6 = 126)
        // This exceeds the 120-bit requirement
        expect(password.length * 6, greaterThanOrEqualTo(120));
      });
    });

    group('derivePgpKeypair', () {
      test('returns map with privateKey, publicKey, and entropy', () async {
        final keypair = await service.derivePgpKeypair(
          xprv: xprv,
          bits: 2048,
        );

        expect(keypair.containsKey('privateKey'), isTrue);
        expect(keypair.containsKey('publicKey'), isTrue);
        expect(keypair.containsKey('entropy'), isTrue);
      });

      test('derives different entropy for different bit sizes', () async {
        final keypair2048 = await service.derivePgpKeypair(
          xprv: xprv,
          bits: 2048,
        );
        final keypair4096 = await service.derivePgpKeypair(
          xprv: xprv,
          bits: 4096,
        );

        expect(
          keypair2048['entropy'],
          isNot(equals(keypair4096['entropy'])),
        );
      });

      test('derives same keypair for same parameters (deterministic)', () async {
        final keypair1 = await service.derivePgpKeypair(
          xprv: xprv,
          bits: 2048,
        );
        final keypair2 = await service.derivePgpKeypair(
          xprv: xprv,
          bits: 2048,
        );

        expect(keypair1['entropy'], equals(keypair2['entropy']));
      });

      test('uses correct BIP85 path format', () {
        // Path should be: m/83696968'/828365'/{bits}'/2026'/
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/828365'/2048'/2026'",
            'pgp',
          ),
          isTrue,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/828365'/4096'/2026'",
            'pgp',
          ),
          isTrue,
        );

        // Invalid paths
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/12345'/828365'/2048'/2026'",
            'pgp',
          ),
          isFalse,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/99999'/2048'/2026'",
            'pgp',
          ),
          isFalse,
        );
      });
    });

    group('verifyDerivationPath', () {
      test('correctly validates AES paths', () {
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "83696968'/128169'/256'/2026'/0'",
            'aes',
          ),
          isTrue,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/128169'/256'/2026'/999'",
            'aes',
          ),
          isTrue,
        );
      });

      test('correctly validates password paths', () {
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "83696968'/707764'/21'/2026'",
            'password',
          ),
          isTrue,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/707764'/21'/2026'",
            'password',
          ),
          isTrue,
        );
      });

      test('correctly validates PGP paths', () {
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "83696968'/828365'/2048'/2026'",
            'pgp',
          ),
          isTrue,
        );

        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/828365'/4096'/2026'",
            'pgp',
          ),
          isTrue,
        );
      });

      test('rejects invalid key types', () {
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/83696968'/128169'/256'/2026'/0'",
            'invalid',
          ),
          isFalse,
        );
      });

      test('rejects paths with wrong application number', () {
        expect(
          MerchantKeyDerivationService.verifyDerivationPath(
            "m/12345'/128169'/256'/2026'/0'",
            'aes',
          ),
          isFalse,
        );
      });
    });
  });
}
