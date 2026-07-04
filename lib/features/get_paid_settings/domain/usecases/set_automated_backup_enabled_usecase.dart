import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/publish_automated_keychain_backup_usecase.dart';

/// Persists the automated-backup toggle.
///
/// When turning the toggle ON while the disclosure is already acknowledged,
/// fires a catch-up publish so a freshly re-enabled backup does not silently
/// wait until the next creation event. The publish is awaited but best-effort
/// (the chokepoint never throws).
class SetAutomatedBackupEnabledUsecase {
  final GetPaidSettingsRepository _repository;
  final PublishAutomatedKeychainBackupUsecase _publishBackup;

  const SetAutomatedBackupEnabledUsecase({
    required this._repository,
    required this._publishBackup,
  });

  Future<void> execute(bool enabled) async {
    await _repository.setAutomatedBackupEnabled(enabled);
    if (!enabled) return;
    final settings = await _repository.fetch();
    if (settings.backupDisclosureAcknowledged) {
      await _publishBackup.execute();
    }
  }
}
