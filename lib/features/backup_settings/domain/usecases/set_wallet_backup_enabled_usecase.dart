import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/wallet_backup_settings_failure_mapper.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:meta/meta.dart';

final class SetWalletBackupEnabledUsecase {
  final WalletBackupFacade _walletBackup;

  const SetWalletBackupEnabledUsecase(this._walletBackup);

  @useResult
  Future<Result<void, BackupSettingsFailure>> execute(bool enabled) async {
    final result = await _walletBackup.setEnabled(enabled);
    return result.mapErr(mapWalletBackupSettingsFailure);
  }
}
