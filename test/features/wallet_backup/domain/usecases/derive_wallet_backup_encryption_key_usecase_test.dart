import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usecase = DeriveWalletBackupEncryptionKeyUsecase(
    registry: Bip85RegistryFacade(),
  );

  test('freezes the unified backup encryption key at 1642/0/1', () {
    final xprv = _xprv();
    final parentFingerprint = bip32.Bip32Keys.fromBase58(xprv).fingerprintHex;

    final result = usecase.execute(
      xprvBase58: xprv,
      expectedParentFingerprint: parentFingerprint,
    );

    expect(result, isA<Ok<WalletBackupEncryptionKey, WalletBackupFailure>>());
    expect(
      (result as Ok<WalletBackupEncryptionKey, WalletBackupFailure>).value.hex,
      '321154f080538350e83f2ebf866595a778ab671e55aacfe0638305ba95a48830',
    );
  });

  test('refuses to derive for a different parent fingerprint', () {
    final result = usecase.execute(
      xprvBase58: _xprv(),
      expectedParentFingerprint: '01234567',
    );

    expect(
      result,
      isA<Err<WalletBackupEncryptionKey, WalletBackupFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<WalletBackupParentFingerprintMismatchFailure>(),
      ),
    );
  });

  test('maps a malformed xprv into the Result failure boundary', () {
    final result = usecase.execute(
      xprvBase58: 'not-an-xprv',
      expectedParentFingerprint: '01234567',
    );

    expect(
      result,
      isA<Err<WalletBackupEncryptionKey, WalletBackupFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<WalletBackupKeyDerivationFailure>(),
      ),
    );
  });
}

String _xprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about',
    bip39.Language.english,
  );
  return bip32.Bip32Keys.fromSeed(Uint8List.fromList(mnemonic.seed)).toBase58();
}
