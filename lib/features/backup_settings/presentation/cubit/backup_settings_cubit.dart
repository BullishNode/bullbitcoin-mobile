import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/load_backup_settings_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_settings_cubit.freezed.dart';
part 'backup_settings_state.dart';

class BackupSettingsCubit extends Cubit<BackupSettingsState> {
  final LoadBackupSettingsUsecase _loadSettings;

  BackupSettingsCubit({required this._loadSettings})
    : super(BackupSettingsState());

  Future<void> checkBackupStatus() async {
    if (state.status == BackupSettingsStatus.loading) return;
    emit(state.copyWith(status: BackupSettingsStatus.loading, failure: null));
    final result = await _loadSettings.execute();
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(
            isDefaultPhysicalBackupTested: value.isDefaultPhysicalBackupTested,
            isDefaultEncryptedBackupTested:
                value.isDefaultEncryptedBackupTested,
            lastPhysicalBackup: value.lastPhysicalBackup,
            lastEncryptedBackup: value.lastEncryptedBackup,
            status: BackupSettingsStatus.success,
            failure: null,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(status: BackupSettingsStatus.error, failure: failure),
        );
    }
  }
}
