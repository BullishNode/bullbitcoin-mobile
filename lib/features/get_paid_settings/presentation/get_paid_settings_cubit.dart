import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_settings_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/set_automated_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidSettingsCubit extends Cubit<GetPaidSettingsState> {
  final GetGetPaidSettingsUsecase _getSettings;
  final SetAutomatedBackupEnabledUsecase _setAutomatedBackupEnabled;

  GetPaidSettingsCubit({
    required this._getSettings,
    required this._setAutomatedBackupEnabled,
  }) : super(const GetPaidSettingsState());

  Future<void> load() async {
    emit(state.copyWith(status: GetPaidSettingsStatus.loading));
    try {
      final settings = await _getSettings.execute();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: GetPaidSettingsStatus.loaded,
          automatedBackupEnabled: settings.automatedBackupEnabled,
          backupDisclosureAcknowledged: settings.backupDisclosureAcknowledged,
          clearFailure: true,
        ),
      );
    } on GetPaidSettingsException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: GetPaidSettingsStatus.failure, failure: e));
    }
  }

  Future<void> toggleAutomatedBackup(bool enabled) async {
    final previous = state.automatedBackupEnabled;
    // Optimistic emit; revert on failure (failures live in state).
    emit(
      state.copyWith(
        automatedBackupEnabled: enabled,
        saving: true,
        clearFailure: true,
      ),
    );
    try {
      await _setAutomatedBackupEnabled.execute(enabled);
      if (isClosed) return;
      emit(state.copyWith(saving: false, status: GetPaidSettingsStatus.loaded));
    } on GetPaidSettingsException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          automatedBackupEnabled: previous,
          saving: false,
          status: GetPaidSettingsStatus.failure,
          failure: e,
        ),
      );
    }
  }
}
