import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

/// Republishes the backup snapshot after a latest-manifest restore. Thin
/// pass-through; the consent/empty/toggle gates live in the single publish
/// chokepoint behind the facade (this never throws).
class PublishRestoredKeychainBackupUsecase {
  final GetPaidSettingsFacade _getPaidSettings;

  const PublishRestoredKeychainBackupUsecase(this._getPaidSettings);

  Future<void> execute() => _getPaidSettings.publishBackupSnapshotIfEnabled();
}
