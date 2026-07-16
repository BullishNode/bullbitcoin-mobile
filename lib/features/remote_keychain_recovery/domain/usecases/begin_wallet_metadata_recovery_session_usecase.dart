import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

class BeginWalletMetadataRecoverySessionUsecase {
  final WalletMetadataBackupFacade _metadataBackup;

  const BeginWalletMetadataRecoverySessionUsecase(this._metadataBackup);

  Future<WalletMetadataPublicationSuppression> execute() {
    return _metadataBackup.beginRecoverySession();
  }
}
