import 'package:bb_mobile/core/recoverbull/domain/entity/decrypted_vault.dart';
import 'package:bb_mobile/core/recoverbull/domain/entity/encrypted_vault.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/check_server_connection_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/create_encrypted_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/decrypt_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/fetch_vault_key_from_server_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/connect_google_drive_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/fetch_latest_google_drive_backup_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/save_to_google_drive_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/restore_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/store_vault_key_into_server_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/update_latest_encrypted_backup_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/init_tor_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/tor_status_usecase.dart';
import 'package:bb_mobile/core/tor/domain/ports/tor_config_port.dart';
import 'package:bb_mobile/features/recoverbull/presentation/bloc.dart';
import 'package:bb_mobile/features/recoverbull/application/start_recoverbull_wallet_manifest_restore_usecase.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCreateEncryptedVaultUsecase extends Mock
    implements CreateEncryptedVaultUsecase {}

class _MockStoreVaultKeyIntoServerUsecase extends Mock
    implements StoreVaultKeyIntoServerUsecase {}

class _MockCheckServerConnectionUsecase extends Mock
    implements CheckServerConnectionUsecase {}

class _MockFetchVaultKeyFromServerUsecase extends Mock
    implements FetchVaultKeyFromServerUsecase {}

class _MockDecryptVaultUsecase extends Mock implements DecryptVaultUsecase {}

class _MockRestoreVaultUsecase extends Mock implements RestoreVaultUsecase {}

class _MockConnectToGoogleDriveUsecase extends Mock
    implements ConnectToGoogleDriveUsecase {}

class _MockSaveVaultToGoogleDriveUsecase extends Mock
    implements SaveVaultToGoogleDriveUsecase {}

class _MockInitTorUsecase extends Mock implements InitTorUsecase {}

class _MockWalletBloc extends Mock implements WalletBloc {}

class _MockFetchLatestGoogleDriveVaultUsecase extends Mock
    implements FetchLatestGoogleDriveVaultUsecase {}

class _MockUpdateLatestEncryptedVaultTestUsecase extends Mock
    implements UpdateLatestEncryptedVaultTestUsecase {}

class _MockTorStatusUsecase extends Mock implements TorStatusUsecase {}

class _MockTorConfigPort extends Mock implements TorConfigPort {}

class _MockStartWalletManifestRestore extends Mock
    implements StartRecoverBullWalletManifestRestoreUsecase {}

class _MockEncryptedVault extends Mock implements EncryptedVault {}

class _FakeDecryptedVault extends Fake implements DecryptedVault {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDecryptedVault());
    registerFallbackValue(_MockEncryptedVault());
  });

  late _MockDecryptVaultUsecase decryptVault;
  late _MockRestoreVaultUsecase restoreVault;
  late _MockUpdateLatestEncryptedVaultTestUsecase updateLatestEncryptedVault;
  late _MockWalletBloc walletBloc;
  late _MockStartWalletManifestRestore startWalletManifestRestore;
  late _MockEncryptedVault encryptedVault;

  setUp(() {
    decryptVault = _MockDecryptVaultUsecase();
    restoreVault = _MockRestoreVaultUsecase();
    updateLatestEncryptedVault = _MockUpdateLatestEncryptedVaultTestUsecase();
    walletBloc = _MockWalletBloc();
    startWalletManifestRestore = _MockStartWalletManifestRestore();
    encryptedVault = _MockEncryptedVault();

    when(
      () => decryptVault.execute(
        vault: any(named: 'vault'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenReturn(const DecryptedVault(mnemonic: ['abandon']));
    when(
      () => updateLatestEncryptedVault.execute(
        decryptedVault: any(named: 'decryptedVault'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => restoreVault.execute(decryptedVault: any(named: 'decryptedVault')),
    ).thenAnswer((_) async {});
    when(() => walletBloc.add(const WalletStarted())).thenReturn(null);
    when(() => walletBloc.add(const WalletRefreshed())).thenReturn(null);
  });

  test(
    'recover vault starts wallet manifest restore after default wallet restore',
    () async {
      final calls = <String>[];
      void Function()? capturedCallback;
      when(
        () =>
            restoreVault.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenAnswer((_) async {
        calls.add('restore-vault');
      });
      when(() => walletBloc.add(const WalletStarted())).thenAnswer((_) {
        calls.add('wallet-started');
      });
      when(
        () => startWalletManifestRestore.execute(
          onWalletStateMayHaveChanged: any(
            named: 'onWalletStateMayHaveChanged',
          ),
        ),
      ).thenAnswer((invocation) {
        calls.add('wallet-manifest');
        capturedCallback =
            invocation.namedArguments[#onWalletStateMayHaveChanged]
                as void Function()?;
      });

      final bloc = _recoverBullBloc(
        flow: RecoverBullFlow.recoverVault,
        encryptedVault: encryptedVault,
        decryptVault: decryptVault,
        restoreVault: restoreVault,
        updateLatestEncryptedVault: updateLatestEncryptedVault,
        walletBloc: walletBloc,
        startWalletManifestRestore: startWalletManifestRestore,
      );
      addTearDown(bloc.close);

      bloc.add(const OnVaultDecryption(vaultKey: 'vault-key'));

      await expectLater(
        bloc.stream,
        emitsThrough(
          isA<RecoverBullState>().having(
            (state) => state.isFlowFinished,
            'finished',
            isTrue,
          ),
        ),
      );

      expect(calls, ['restore-vault', 'wallet-started', 'wallet-manifest']);

      capturedCallback?.call();
      verify(() => walletBloc.add(const WalletRefreshed())).called(1);
    },
  );

  test(
    'recover vault does not start manifest restore when restore fails',
    () async {
      when(
        () =>
            restoreVault.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenThrow(Exception('restore failed'));
      final bloc = _recoverBullBloc(
        flow: RecoverBullFlow.recoverVault,
        encryptedVault: encryptedVault,
        decryptVault: decryptVault,
        restoreVault: restoreVault,
        updateLatestEncryptedVault: updateLatestEncryptedVault,
        walletBloc: walletBloc,
        startWalletManifestRestore: startWalletManifestRestore,
      );
      addTearDown(bloc.close);

      bloc.add(const OnVaultDecryption(vaultKey: 'vault-key'));

      await expectLater(
        bloc.stream,
        emitsThrough(
          isA<RecoverBullState>().having(
            (state) => state.error,
            'error',
            isNotNull,
          ),
        ),
      );

      verifyNever(
        () => startWalletManifestRestore.execute(
          onWalletStateMayHaveChanged: any(
            named: 'onWalletStateMayHaveChanged',
          ),
        ),
      );
    },
  );

  test('test vault does not start manifest restore', () async {
    final bloc = _recoverBullBloc(
      flow: RecoverBullFlow.testVault,
      encryptedVault: encryptedVault,
      decryptVault: decryptVault,
      restoreVault: restoreVault,
      updateLatestEncryptedVault: updateLatestEncryptedVault,
      walletBloc: walletBloc,
      startWalletManifestRestore: startWalletManifestRestore,
    );
    addTearDown(bloc.close);

    bloc.add(const OnVaultDecryption(vaultKey: 'vault-key'));

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<RecoverBullState>().having(
          (state) => state.decryptedVault,
          'decrypted vault',
          isNotNull,
        ),
      ),
    );

    verifyNever(
      () => startWalletManifestRestore.execute(
        onWalletStateMayHaveChanged: any(named: 'onWalletStateMayHaveChanged'),
      ),
    );
  });
}

RecoverBullBloc _recoverBullBloc({
  required RecoverBullFlow flow,
  required EncryptedVault encryptedVault,
  required DecryptVaultUsecase decryptVault,
  required RestoreVaultUsecase restoreVault,
  required UpdateLatestEncryptedVaultTestUsecase updateLatestEncryptedVault,
  required WalletBloc walletBloc,
  required StartRecoverBullWalletManifestRestoreUsecase
  startWalletManifestRestore,
}) {
  return RecoverBullBloc(
    flow: flow,
    preSelectedVault: encryptedVault,
    createEncryptedVaultUsecase: _MockCreateEncryptedVaultUsecase(),
    storeVaultKeyIntoServerUsecase: _MockStoreVaultKeyIntoServerUsecase(),
    checkKeyServerConnectionUsecase: _MockCheckServerConnectionUsecase(),
    fetchVaultKeyFromServerUsecase: _MockFetchVaultKeyFromServerUsecase(),
    decryptVaultUsecase: decryptVault,
    restoreVaultUsecase: restoreVault,
    connectToGoogleDriveUsecase: _MockConnectToGoogleDriveUsecase(),
    saveToGoogleDriveUsecase: _MockSaveVaultToGoogleDriveUsecase(),
    initializeTorUsecase: _MockInitTorUsecase(),
    walletBloc: walletBloc,
    fetchLatestGoogleDriveVaultUsecase:
        _MockFetchLatestGoogleDriveVaultUsecase(),
    updateLatestEncryptedVaultTestUsecase: updateLatestEncryptedVault,
    torStatusUsecase: _MockTorStatusUsecase(),
    torConfigPort: _MockTorConfigPort(),
    startWalletManifestRestore: startWalletManifestRestore,
  );
}
