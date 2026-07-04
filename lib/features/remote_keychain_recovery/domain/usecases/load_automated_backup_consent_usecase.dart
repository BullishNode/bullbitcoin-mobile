import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

/// Reads the persisted disclosure acknowledgement — the SAME preference the
/// creation-time consent gate writes (R2-P21c). Fail-closed toward the
/// disclosure gate: returns false on a storage error so recovery re-shows the
/// disclosure rather than silently contacting third-party relays.
class LoadAutomatedBackupConsentUsecase {
  final GetPaidSettingsFacade _getPaidSettings;

  const LoadAutomatedBackupConsentUsecase(this._getPaidSettings);

  Future<bool> execute() async {
    try {
      final settings = await _getPaidSettings.getSettings();
      return settings.backupDisclosureAcknowledged;
    } catch (_) {
      return false;
    }
  }
}
