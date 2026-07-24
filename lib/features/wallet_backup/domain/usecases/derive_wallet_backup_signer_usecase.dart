import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:meta/meta.dart';

final class DeriveWalletBackupSignerUsecase {
  final NostrIdentityFacade _identity;

  const DeriveWalletBackupSignerUsecase(this._identity);

  @useResult
  Result<WalletBackupSigner, WalletBackupFailure> execute({
    required String xprvBase58,
    required String expectedParentFingerprint,
  }) {
    try {
      final actualFingerprint = bip32.Bip32Keys.fromBase58(
        xprvBase58,
      ).fingerprintHex;
      if (actualFingerprint != expectedParentFingerprint.trim().toLowerCase()) {
        return const Err(WalletBackupParentFingerprintMismatchFailure());
      }
      return Ok(
        WalletBackupSigner(
          publicKeyHex: _identity.deriveWalletBackupPublicKeyFromXprv(
            xprvBase58,
          ),
          signHashHex: (hash) => _identity.signWalletBackupHashFromXprv(
            xprvBase58: xprvBase58,
            messageHashHex: hash,
          ),
        ),
      );
    } on Exception catch (error) {
      return Err(
        WalletBackupKeyDerivationFailure(error.runtimeType.toString()),
      );
    }
  }
}
