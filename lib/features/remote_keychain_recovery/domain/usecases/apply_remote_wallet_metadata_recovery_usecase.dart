import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_wallet_metadata_recovery_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

class ApplyRemoteWalletMetadataRecoveryUsecase {
  final WalletMetadataBackupFacade _metadataBackup;

  const ApplyRemoteWalletMetadataRecoveryUsecase(this._metadataBackup);

  Future<
    Result<
      WalletMetadataRecoveryApplyResult,
      RemoteWalletMetadataRecoveryFailure
    >
  >
  execute({
    required WalletMetadataRecoveryPlan plan,
    required Set<String> createdWalletRefs,
  }) async {
    return (await _metadataBackup.applyRecoveryPlan(
      plan: plan,
      createdWalletRefs: createdWalletRefs,
    )).mapErr((_) => const RemoteWalletMetadataRecoveryUnavailableFailure());
  }
}
