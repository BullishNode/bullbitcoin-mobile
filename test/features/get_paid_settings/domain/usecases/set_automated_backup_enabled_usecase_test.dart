import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/publish_automated_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/set_automated_backup_enabled_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements GetPaidSettingsRepository {
  _FakeRepository(this._settings);

  GetPaidSettings _settings;

  @override
  Future<GetPaidSettings> fetch() async => _settings;

  @override
  Future<void> setAutomatedBackupEnabled(bool enabled) async {
    _settings = _settings.copyWith(automatedBackupEnabled: enabled);
  }

  @override
  Future<void> setBackupDisclosureAcknowledged({
    required bool automatedBackupEnabled,
  }) async {
    _settings = GetPaidSettings(
      automatedBackupEnabled: automatedBackupEnabled,
      backupDisclosureAcknowledged: true,
    );
  }
}

class _FakePublishUsecase implements PublishAutomatedKeychainBackupUsecase {
  int calls = 0;

  @override
  Future<void> execute() async {
    calls++;
  }
}

void main() {
  test(
    'turning ON with the disclosure acknowledged fires one catch-up publish',
    () async {
      final publish = _FakePublishUsecase();
      final usecase = SetAutomatedBackupEnabledUsecase(
        repository: _FakeRepository(
          const GetPaidSettings(
            automatedBackupEnabled: false,
            backupDisclosureAcknowledged: true,
          ),
        ),
        publishBackup: publish,
      );

      await usecase.execute(true);

      expect(publish.calls, 1);
    },
  );

  test(
    'turning ON without an acknowledged disclosure does not publish',
    () async {
      final publish = _FakePublishUsecase();
      final usecase = SetAutomatedBackupEnabledUsecase(
        repository: _FakeRepository(
          const GetPaidSettings(
            automatedBackupEnabled: false,
            backupDisclosureAcknowledged: false,
          ),
        ),
        publishBackup: publish,
      );

      await usecase.execute(true);

      expect(publish.calls, 0);
    },
  );

  test('turning OFF never publishes', () async {
    final publish = _FakePublishUsecase();
    final usecase = SetAutomatedBackupEnabledUsecase(
      repository: _FakeRepository(
        const GetPaidSettings(
          automatedBackupEnabled: true,
          backupDisclosureAcknowledged: true,
        ),
      ),
      publishBackup: publish,
    );

    await usecase.execute(false);

    expect(publish.calls, 0);
  });
}
