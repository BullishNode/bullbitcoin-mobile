import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_settings_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/set_automated_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGetSettings implements GetGetPaidSettingsUsecase {
  _FakeGetSettings(this._settings, {this.throwOnExecute = false});

  final GetPaidSettings _settings;
  final bool throwOnExecute;

  @override
  Future<GetPaidSettings> execute() async {
    if (throwOnExecute) throw GetPaidSettingsStorageException();
    return _settings;
  }
}

class _FakeSetEnabled implements SetAutomatedBackupEnabledUsecase {
  _FakeSetEnabled({this.throwOnExecute = false});

  final bool throwOnExecute;
  final List<bool> calls = [];

  @override
  Future<void> execute(bool enabled) async {
    calls.add(enabled);
    if (throwOnExecute) throw GetPaidSettingsStorageException();
  }
}

void main() {
  test('load reflects the repository settings', () async {
    final cubit = GetPaidSettingsCubit(
      getSettings: _FakeGetSettings(
        const GetPaidSettings(
          automatedBackupEnabled: false,
          backupDisclosureAcknowledged: true,
        ),
      ),
      setAutomatedBackupEnabled: _FakeSetEnabled(),
    );

    await cubit.load();

    expect(cubit.state.status, GetPaidSettingsStatus.loaded);
    expect(cubit.state.automatedBackupEnabled, isFalse);
    expect(cubit.state.backupDisclosureAcknowledged, isTrue);
    await cubit.close();
  });

  test(
    'toggling persists via the usecase and clears the saving flag',
    () async {
      final setEnabled = _FakeSetEnabled();
      final cubit = GetPaidSettingsCubit(
        getSettings: _FakeGetSettings(
          const GetPaidSettings(
            automatedBackupEnabled: true,
            backupDisclosureAcknowledged: true,
          ),
        ),
        setAutomatedBackupEnabled: setEnabled,
      );
      await cubit.load();

      await cubit.toggleAutomatedBackup(false);

      expect(setEnabled.calls, [false]);
      expect(cubit.state.automatedBackupEnabled, isFalse);
      expect(cubit.state.saving, isFalse);
      await cubit.close();
    },
  );

  test('a toggle failure reverts the value and surfaces the failure', () async {
    final cubit = GetPaidSettingsCubit(
      getSettings: _FakeGetSettings(
        const GetPaidSettings(
          automatedBackupEnabled: true,
          backupDisclosureAcknowledged: true,
        ),
      ),
      setAutomatedBackupEnabled: _FakeSetEnabled(throwOnExecute: true),
    );
    await cubit.load();

    await cubit.toggleAutomatedBackup(false);

    expect(cubit.state.automatedBackupEnabled, isTrue);
    expect(cubit.state.status, GetPaidSettingsStatus.failure);
    expect(cubit.state.failure, isA<GetPaidSettingsException>());
    await cubit.close();
  });

  test('a load failure surfaces the failure state', () async {
    final cubit = GetPaidSettingsCubit(
      getSettings: _FakeGetSettings(
        const GetPaidSettings(
          automatedBackupEnabled: true,
          backupDisclosureAcknowledged: false,
        ),
        throwOnExecute: true,
      ),
      setAutomatedBackupEnabled: _FakeSetEnabled(),
    );

    await cubit.load();

    expect(cubit.state.status, GetPaidSettingsStatus.failure);
    expect(cubit.state.failure, isA<GetPaidSettingsException>());
    await cubit.close();
  });
}
