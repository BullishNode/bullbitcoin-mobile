import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_wallet_metadata_recovery_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

class CheckRemoteWalletMetadataRecoveryUsecase {
  final RemoteKeychainRecoveryDefaultWalletXprvPort _defaultWalletXprv;
  final WalletMetadataBackupFacade _metadataBackup;

  const CheckRemoteWalletMetadataRecoveryUsecase({
    required this._defaultWalletXprv,
    required this._metadataBackup,
  });

  Future<
    Result<WalletMetadataRecoveryResult, RemoteWalletMetadataRecoveryFailure>
  >
  execute() async {
    try {
      final root = await _defaultWalletXprv.deriveDefaultWalletXprv();
      return (await _metadataBackup.fetchRecoveryPlan(
        xprvBase58: root.xprvBase58,
        parentFingerprint: root.parentFingerprint,
      )).mapErr((_) => const RemoteWalletMetadataRecoveryUnavailableFailure());
    } on Exception {
      return const Err(RemoteWalletMetadataRecoveryUnavailableFailure());
    }
  }
}
