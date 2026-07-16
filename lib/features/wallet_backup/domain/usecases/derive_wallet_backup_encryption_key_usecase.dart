import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:hex/hex.dart';
import 'package:meta/meta.dart';

const _walletBackupEncryptionReservationId = 'wallet_backup_encryption_key';

final class DeriveWalletBackupEncryptionKeyUsecase {
  final Bip85RegistryFacade registry;

  const DeriveWalletBackupEncryptionKeyUsecase({required this.registry});

  @useResult
  Result<WalletBackupEncryptionKey, WalletBackupFailure> execute({
    required String xprvBase58,
    required String expectedParentFingerprint,
  }) {
    try {
      final expected = _normalizeFingerprint(expectedParentFingerprint);
      final actual = bip32.Bip32Keys.fromBase58(xprvBase58).fingerprintHex;
      if (actual != expected) {
        return const Err(WalletBackupParentFingerprintMismatchFailure());
      }

      final reservation = registry.reservationById(
        _walletBackupEncryptionReservationId,
      );
      if (reservation == null ||
          reservation.owner != Bip85ReservationOwner.walletBackup ||
          reservation.purpose != Bip85ReservationPurpose.backupEncryptionKey) {
        return const Err(
          WalletBackupKeyDerivationFailure(
            'wallet backup encryption reservation is missing or invalid',
          ),
        );
      }
      final prefix = "${reservation.application.number}'/";
      if (!reservation.scope.exactPath.startsWith(prefix)) {
        return const Err(
          WalletBackupKeyDerivationFailure(
            'wallet backup encryption reservation path is invalid',
          ),
        );
      }
      final derivation = Bip85Entropy.derive(
        xprvBase58: xprvBase58,
        application: CustomApplication.fromNumber(
          reservation.application.number,
        ),
        path: reservation.scope.exactPath.substring(prefix.length),
      );
      return Ok(
        WalletBackupEncryptionKey(HEX.encode(derivation.sublist(0, 32))),
      );
    } on ArgumentError catch (error) {
      return Err(
        WalletBackupKeyDerivationFailure(error.runtimeType.toString()),
      );
    } on Exception catch (error) {
      return Err(
        WalletBackupKeyDerivationFailure(error.runtimeType.toString()),
      );
    }
  }
}

String _normalizeFingerprint(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(normalized)) {
    throw const FormatException(
      'parent fingerprint must be 8 hexadecimal characters',
    );
  }
  return normalized;
}
