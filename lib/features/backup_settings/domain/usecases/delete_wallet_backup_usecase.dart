import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/wallet_backup_settings_failure_mapper.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:meta/meta.dart';

final class DeleteWalletBackupUsecase {
  final WalletBackupFacade _walletBackup;

  const DeleteWalletBackupUsecase(this._walletBackup);

  @useResult
  Future<Result<void, BackupSettingsFailure>> execute() async {
    final result = await _walletBackup.deleteRemoteBackup(confirmed: true);
    return result.mapErr(mapWalletBackupSettingsFailure);
  }
}
