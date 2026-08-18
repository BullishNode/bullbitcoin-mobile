import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_manifest_import.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:meta/meta.dart';

final class FetchWalletBackupManifestImportUsecase {
  final WalletBackupWalletPort _wallet;
  final DeriveWalletBackupSignerUsecase _deriveSigner;
  final WalletBackupRemoteRepository _remote;
  final DeriveWalletBackupEncryptionKeyUsecase _deriveEncryptionKey;
  final WalletBackupEncryptionRepository _encryption;
  final KeychainManifestFacade _keychainManifest;
  final WalletBackupStateRepository _state;

  const FetchWalletBackupManifestImportUsecase({
    required this._wallet,
    required this._deriveSigner,
    required this._remote,
    required this._deriveEncryptionKey,
    required this._encryption,
    required this._keychainManifest,
    required this._state,
  });

  @useResult
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>
  execute() async {
    final walletResult = await _wallet.deriveDefaultWallet();
    final WalletBackupWallet wallet;
    switch (walletResult) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }

    final signerResult = _deriveSigner.execute(
      xprvBase58: wallet.xprvBase58,
      expectedParentFingerprint: wallet.parentFingerprint,
    );
    final WalletBackupSigner signer;
    switch (signerResult) {
      case Ok(:final value):
        signer = value;
      case Err(:final failure):
        return Err(failure);
    }

    final fetchResult = await _remote.fetch(signer);
    final WalletBackupRemoteHead remote;
    switch (fetchResult) {
      case Ok(:final value):
        remote = value;
      case Err(:final failure):
        return Err(failure);
    }
    final ciphertext = remote.ciphertext;
    if (ciphertext == null) return const Ok(null);

    final keyResult = _deriveEncryptionKey.execute(
      xprvBase58: wallet.xprvBase58,
      expectedParentFingerprint: wallet.parentFingerprint,
    );
    final WalletBackupEncryptionKey key;
    switch (keyResult) {
      case Ok(:final value):
        key = value;
      case Err(:final failure):
        return Err(failure);
    }

    final decryptResult = _encryption.decrypt(
      ciphertext: ciphertext,
      key: key,
      expectedParentFingerprint: wallet.parentFingerprint,
    );
    switch (decryptResult) {
      case Err(
        failure: final WalletBackupUnsupportedEnvelopeVersionFailure failure,
      ):
        final blockResult = await _state.blockUnsupportedVersion(
          failure.version,
        );
        if (blockResult case Err(:final failure)) return Err(failure);
        return Err(failure);
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        try {
          final plan = _keychainManifest.parseManifestFilePayload(
            value.manifest.payload,
            expectedParentFingerprint: wallet.parentFingerprint,
            allowEmpty: true,
          );
          return Ok(
            WalletBackupManifestImport(
              payload: value.manifest.payload,
              parentFingerprint: plan.parentFingerprint,
            ),
          );
        } on KeychainManifestException catch (error) {
          return Err(WalletBackupManifestFailure(error.runtimeType.toString()));
        } on Exception catch (error) {
          return Err(
            WalletBackupUnexpectedFailure(error.runtimeType.toString()),
          );
        }
    }
  }
}
