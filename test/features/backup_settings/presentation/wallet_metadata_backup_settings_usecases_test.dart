import 'package:bb_mobile/core/settings/domain/repositories/settings_repository.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/entities/backup_settings_snapshot.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_metadata_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/load_backup_settings_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMetadataBackup extends Mock implements WalletMetadataBackupFacade {}

class _MockGetWallets extends Mock implements GetWalletsUsecase {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late _MockMetadataBackup metadataBackup;

  setUp(() {
    metadataBackup = _MockMetadataBackup();
  });

  test('loads metadata settings when no default wallets exist yet', () async {
    final getWallets = _MockGetWallets();
    final settingsRepository = _MockSettingsRepository();
    when(
      () => metadataBackup.getState(),
    ).thenAnswer((_) async => Ok(_state(acknowledged: true)));
    when(
      () => getWallets.execute(onlyDefaults: true),
    ).thenThrow(NoWalletsFoundException('none'));

    final result = await LoadBackupSettingsUsecase(
      getWallets,
      settingsRepository,
      metadataBackup,
    ).execute();

    final snapshot = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw TestFailure('unexpected $failure'),
    };
    expect(snapshot.isDefaultPhysicalBackupTested, isFalse);
    expect(snapshot.walletMetadata.relayDisclosureAcknowledged, isTrue);
    verifyNever(() => settingsRepository.fetch());
  });

  test(
    'acknowledges disclosure before enabling metadata publication',
    () async {
      when(
        () => metadataBackup.getState(),
      ).thenAnswer((_) async => Ok(_state()));
      when(
        () => metadataBackup.acknowledgeRelayDisclosure(),
      ).thenAnswer((_) async => Ok(_state(acknowledged: true)));
      when(() => metadataBackup.setEnabled(true)).thenAnswer(
        (_) async => Ok(_state(enabled: true, acknowledged: true, dirty: true)),
      );

      final result = await SetWalletMetadataBackupEnabledUsecase(
        metadataBackup,
      ).execute(enabled: true, disclosureAccepted: true);

      verifyInOrder([
        () => metadataBackup.getState(),
        () => metadataBackup.acknowledgeRelayDisclosure(),
        () => metadataBackup.setEnabled(true),
      ]);
      expect(_requireSettings(result).enabled, isTrue);
    },
  );

  test('does not acknowledge or enable when disclosure is declined', () async {
    when(() => metadataBackup.getState()).thenAnswer((_) async => Ok(_state()));

    final result = await SetWalletMetadataBackupEnabledUsecase(
      metadataBackup,
    ).execute(enabled: true, disclosureAccepted: false);

    verifyNever(() => metadataBackup.acknowledgeRelayDisclosure());
    verifyNever(() => metadataBackup.setEnabled(any()));
    expect(_requireSettings(result).enabled, isFalse);
  });

  test('manual backup returns publication status with refreshed state', () async {
    when(() => metadataBackup.backupNow()).thenAnswer(
      (_) async => Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.verified,
          acceptedReplicaCount: 1,
          verifiedReplicaCount: 1,
          rootEventId:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
    );
    when(
      () => metadataBackup.getState(),
    ).thenAnswer((_) async => Ok(_state(enabled: true, acknowledged: true)));

    final result = _requireBackup(
      await BackupWalletMetadataNowUsecase(metadataBackup).execute(),
    );

    expect(result.status, WalletMetadataBackupNowStatus.saved);
    expect(result.settings.dirty, isFalse);
  });

  test('unexpected facade exceptions are mapped to a typed failure', () async {
    when(
      () => metadataBackup.backupNow(),
    ).thenThrow(Exception('private transport detail'));

    final result = await BackupWalletMetadataNowUsecase(
      metadataBackup,
    ).execute();

    expect(
      result,
      isA<Err<WalletMetadataBackupNowResult, BackupSettingsFailure>>(),
    );
  });
}

WalletMetadataBackupState _state({
  bool enabled = false,
  bool acknowledged = false,
  bool dirty = false,
}) {
  return WalletMetadataBackupState(
    enabled: enabled,
    relayDisclosureAcknowledged: acknowledged,
    dirty: dirty,
    dirtyRevision: dirty ? 1 : 0,
    lastAttemptedAt: null,
    lastAcceptedAt: null,
    verifiedHead: null,
    unsupportedNewerEnvelope: null,
    recoveryBlock: null,
  );
}

WalletMetadataBackupSettingsSnapshot _requireSettings(
  Result<WalletMetadataBackupSettingsSnapshot, BackupSettingsFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure('unexpected $failure'),
  };
}

WalletMetadataBackupNowResult _requireBackup(
  Result<WalletMetadataBackupNowResult, BackupSettingsFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure('unexpected $failure'),
  };
}
