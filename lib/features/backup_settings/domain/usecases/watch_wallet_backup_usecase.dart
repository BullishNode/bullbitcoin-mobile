import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/wallet_backup_settings_failure_mapper.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

final class WatchWalletBackupUsecase {
  final WalletBackupFacade _walletBackup;

  const WatchWalletBackupUsecase(this._walletBackup);

  Stream<Result<WalletBackupState, BackupSettingsFailure>> execute() {
    return _walletBackup.watchState().map(
      (result) => result.mapErr(mapWalletBackupSettingsFailure),
    );
  }
}
