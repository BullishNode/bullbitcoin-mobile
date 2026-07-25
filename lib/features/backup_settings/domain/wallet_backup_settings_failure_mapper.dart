import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

BackupSettingsFailure mapWalletBackupSettingsFailure(
  WalletBackupFailure failure,
) {
  return switch (failure) {
    WalletBackupRemoteUnavailableFailure() =>
      const BackupSettingsUnavailableFailure(),
    WalletBackupDisabledFailure() => const BackupSettingsDisabledFailure(),
    WalletBackupRecoveryBlockedFailure() =>
      const BackupSettingsUnexpectedFailure('Backup recovery is incomplete'),
    WalletBackupUnsupportedEnvelopeVersionFailure() ||
    WalletBackupUnsupportedSectionFailure() =>
      const BackupSettingsUpdateRequiredFailure(),
    _ => BackupSettingsUnexpectedFailure(failure.runtimeType.toString()),
  };
}
