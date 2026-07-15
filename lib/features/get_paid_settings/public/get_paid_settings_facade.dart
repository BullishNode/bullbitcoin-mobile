export 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
export 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';

import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/acknowledge_automated_backup_disclosure_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_settings_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/publish_automated_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/set_automated_backup_enabled_usecase.dart';

/// Cross-feature contract for the Get Paid automated-backup preference.
///
/// Owns the persisted toggle + disclosure ack and the single publish-side
/// entry point. Consuming features (btcpay, lightning_address,
/// remote_keychain_recovery) reach the backup pipeline only through this
/// facade; the network publish and its gates live behind
/// [publishBackupSnapshotIfEnabled].
class GetPaidSettingsFacade {
  final GetGetPaidSettingsUsecase _getSettings;
  final SetAutomatedBackupEnabledUsecase _setAutomatedBackupEnabled;
  final AcknowledgeAutomatedBackupDisclosureUsecase _acknowledgeDisclosure;
  final PublishAutomatedKeychainBackupUsecase _publishBackup;

  const GetPaidSettingsFacade({
    required this._getSettings,
    required this._setAutomatedBackupEnabled,
    required this._acknowledgeDisclosure,
    required this._publishBackup,
  });

  Future<GetPaidSettings> getSettings() => _getSettings.execute();

  Future<void> setAutomatedBackupEnabled(bool enabled) =>
      _setAutomatedBackupEnabled.execute(enabled);

  Future<void> acknowledgeBackupDisclosure({
    required bool automatedBackupEnabled,
  }) => _acknowledgeDisclosure.execute(
    automatedBackupEnabled: automatedBackupEnabled,
  );

  /// Publishes the encrypted backup snapshot iff the toggle is on and the
  /// disclosure has been acknowledged. Best-effort: never throws.
  Future<void> publishBackupSnapshotIfEnabled() => _publishBackup.execute();
}
