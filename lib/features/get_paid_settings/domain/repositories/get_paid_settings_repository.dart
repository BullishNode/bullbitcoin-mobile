import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';

abstract interface class GetPaidSettingsRepository {
  Future<GetPaidSettings> fetch();
  Future<void> setAutomatedBackupEnabled(bool enabled);

  /// Atomically records the disclosure acknowledgement together with the
  /// toggle value chosen in the consent dialog (one row upsert).
  Future<void> setBackupDisclosureAcknowledged({
    required bool automatedBackupEnabled,
  });
}
