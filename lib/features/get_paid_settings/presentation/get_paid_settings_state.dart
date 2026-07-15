import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';

enum GetPaidSettingsStatus { initial, loading, loaded, failure }

class GetPaidSettingsState {
  final GetPaidSettingsStatus status;
  final bool automatedBackupEnabled;
  final bool backupDisclosureAcknowledged;
  final bool saving;
  final GetPaidSettingsException? failure;

  const GetPaidSettingsState({
    this.status = GetPaidSettingsStatus.initial,
    this.automatedBackupEnabled = true,
    this.backupDisclosureAcknowledged = false,
    this.saving = false,
    this.failure,
  });

  GetPaidSettingsState copyWith({
    GetPaidSettingsStatus? status,
    bool? automatedBackupEnabled,
    bool? backupDisclosureAcknowledged,
    bool? saving,
    GetPaidSettingsException? failure,
    bool clearFailure = false,
  }) {
    return GetPaidSettingsState(
      status: status ?? this.status,
      automatedBackupEnabled:
          automatedBackupEnabled ?? this.automatedBackupEnabled,
      backupDisclosureAcknowledged:
          backupDisclosureAcknowledged ?? this.backupDisclosureAcknowledged,
      saving: saving ?? this.saving,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}
