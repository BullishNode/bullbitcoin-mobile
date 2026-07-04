import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';

/// Persists the disclosure acknowledgement together with the toggle value
/// chosen in the consent dialog (one atomic row upsert).
///
/// Does NOT fire a catch-up publish: the in-flow creation trigger follows
/// immediately, and publishing here would race an empty manifest on first use.
class AcknowledgeAutomatedBackupDisclosureUsecase {
  final GetPaidSettingsRepository _repository;

  const AcknowledgeAutomatedBackupDisclosureUsecase({
    required this._repository,
  });

  Future<void> execute({required bool automatedBackupEnabled}) {
    return _repository.setBackupDisclosureAcknowledged(
      automatedBackupEnabled: automatedBackupEnabled,
    );
  }
}
