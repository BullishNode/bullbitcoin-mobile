import 'package:bb_mobile/core/recoverbull/domain/entity/decrypted_vault.dart';
import 'package:bb_mobile/core/recoverbull/domain/entity/encrypted_vault.dart';
import 'package:bb_mobile/core/recoverbull/domain/entity/vault_provider.dart';
import 'package:bb_mobile/core/recoverbull/domain/recoverbull_failure.dart'
    as core;
import 'package:bb_mobile/core/recoverbull/domain/usecases/check_server_connection_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/create_encrypted_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/decrypt_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/fetch_vault_key_from_server_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/connect_google_drive_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/fetch_latest_google_drive_backup_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/google_drive/save_to_google_drive_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/pick_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/restore_vault_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/save_file_to_system_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/store_vault_key_into_server_usecase.dart';
import 'package:bb_mobile/core/recoverbull/domain/usecases/update_latest_encrypted_backup_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/init_tor_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/tor_status_usecase.dart';
import 'package:bb_mobile/core/tor/domain/ports/tor_config_port.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/recoverbull/domain/recoverbull_failure.dart';
import 'package:bb_mobile/features/recoverbull/domain/complete_encrypted_vault_backup_usecase.dart';
import 'package:bb_mobile/features/recoverbull/presentation/bloc.dart';
import 'package:bb_mobile/features/recoverbull/recover_remote_keychain_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPickVault extends Mock implements PickVaultUsecase {}

class _MockSaveFile extends Mock implements SaveFileToSystemUsecase {}

class _MockCreateVault extends Mock implements CreateEncryptedVaultUsecase {}

class _MockCompleteEncryptedVaultBackup extends Mock
    implements CompleteEncryptedVaultBackupUsecase {}

class _MockStoreKey extends Mock implements StoreVaultKeyIntoServerUsecase {}

class _MockCheckConnection extends Mock
    implements CheckServerConnectionUsecase {}

class _MockFetchKey extends Mock implements FetchVaultKeyFromServerUsecase {}

class _MockDecrypt extends Mock implements DecryptVaultUsecase {}

class _MockRestore extends Mock implements RestoreVaultUsecase {}

class _MockRecoverRemoteKeychain extends Mock
    implements RecoverBullRemoteKeychainUsecase {}

class _MockRecoveryFacade extends Mock
    implements RemoteKeychainRecoveryFacade {}

class _MockConnectDrive extends Mock implements ConnectToGoogleDriveUsecase {}

class _MockSaveDrive extends Mock implements SaveVaultToGoogleDriveUsecase {}

class _MockInitTor extends Mock implements InitTorUsecase {}

class _MockWalletBloc extends Mock implements WalletBloc {}

class _MockFetchLatestDrive extends Mock
    implements FetchLatestGoogleDriveVaultUsecase {}

class _MockUpdateLatest extends Mock
    implements UpdateLatestEncryptedVaultTestUsecase {}

class _MockTorStatus extends Mock implements TorStatusUsecase {}

class _MockTorConfig extends Mock implements TorConfigPort {}

class _MockEncryptedVault extends Mock implements EncryptedVault {}

void main() {
  late _MockPickVault pickVault;
  late _MockSaveFile saveFile;
  late _MockCreateVault createVault;
  late _MockCompleteEncryptedVaultBackup completeEncryptedVaultBackup;
  late _MockStoreKey storeKey;
  late _MockCheckConnection checkConnection;
  late _MockFetchKey fetchKey;
  late _MockDecrypt decrypt;
  late _MockRestore restore;
  late _MockRecoverRemoteKeychain recoverRemoteKeychain;
  late _MockConnectDrive connectDrive;
  late _MockSaveDrive saveDrive;
  late _MockInitTor initTor;
  late _MockWalletBloc walletBloc;
  late _MockFetchLatestDrive fetchLatestDrive;
  late _MockUpdateLatest updateLatest;
  late _MockTorStatus torStatus;
  late _MockTorConfig torConfig;

  setUpAll(() {
    registerFallbackValue(_MockEncryptedVault());
    registerFallbackValue(const DecryptedVault());
    registerFallbackValue(const WalletStarted());
    registerFallbackValue(<String>{});
  });

  setUp(() {
    pickVault = _MockPickVault();
    saveFile = _MockSaveFile();
    createVault = _MockCreateVault();
    completeEncryptedVaultBackup = _MockCompleteEncryptedVaultBackup();
    when(
      () => completeEncryptedVaultBackup.execute(
        walletId: any(named: 'walletId'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    storeKey = _MockStoreKey();
    checkConnection = _MockCheckConnection();
    fetchKey = _MockFetchKey();
    decrypt = _MockDecrypt();
    restore = _MockRestore();
    recoverRemoteKeychain = _MockRecoverRemoteKeychain();
    when(
      () => recoverRemoteKeychain.execute(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer((_) async {});
    connectDrive = _MockConnectDrive();
    saveDrive = _MockSaveDrive();
    initTor = _MockInitTor();
    walletBloc = _MockWalletBloc();
    fetchLatestDrive = _MockFetchLatestDrive();
    updateLatest = _MockUpdateLatest();
    torStatus = _MockTorStatus();
    torConfig = _MockTorConfig();
  });

  // The bloc constructor does not auto-dispatch any event, so unstubbed mocks
  // stay untouched unless a test drives the matching flow.
  RecoverBullBloc buildBloc({
    required RecoverBullFlow flow,
    EncryptedVault? preSelectedVault,
    RecoverBullRemoteKeychainUsecase? recoverOverride,
  }) => RecoverBullBloc(
    flow: flow,
    preSelectedVault: preSelectedVault,
    pickVaultUsecase: pickVault,
    saveFileToSystemUsecase: saveFile,
    createEncryptedVaultUsecase: createVault,
    completeEncryptedVaultBackupUsecase: completeEncryptedVaultBackup,
    storeVaultKeyIntoServerUsecase: storeKey,
    checkKeyServerConnectionUsecase: checkConnection,
    fetchVaultKeyFromServerUsecase: fetchKey,
    decryptVaultUsecase: decrypt,
    restoreVaultUsecase: restore,
    recoverRemoteKeychainUsecase: recoverOverride ?? recoverRemoteKeychain,
    connectToGoogleDriveUsecase: connectDrive,
    saveToGoogleDriveUsecase: saveDrive,
    initializeTorUsecase: initTor,
    walletBloc: walletBloc,
    fetchLatestGoogleDriveVaultUsecase: fetchLatestDrive,
    updateLatestEncryptedVaultTestUsecase: updateLatest,
    torStatusUsecase: torStatus,
    torConfigPort: torConfig,
  );

  group('OnVaultPasswordSet guard', () {
    test('no vault set -> VaultNotSetFailure, password not stored, key never '
        'fetched', () async {
      // recoverVault hits the default branch; no preSelectedVault => null.
      final bloc = buildBloc(flow: RecoverBullFlow.recoverVault);

      bloc.add(const OnVaultPasswordSet(password: 'pw'));
      await pumpEventQueue();

      expect(bloc.state.failure, isA<VaultNotSetFailure>());
      // The guard must return before storing the password or fetching the
      // key — proving the early `return` is effective (the pre-fix code fell
      // through to `state.vault!`).
      expect(bloc.state.vaultPassword, isNull);
      verifyNever(
        () => fetchKey.execute(
          vault: any(named: 'vault'),
          password: any(named: 'password'),
        ),
      );

      await bloc.close();
    });
  });

  group('OnVaultProviderSelection (secureVault) guard', () {
    test(
      'no password set -> PasswordNotSetFailure, creation never started',
      () async {
        final bloc = buildBloc(flow: RecoverBullFlow.secureVault);

        bloc.add(
          const OnVaultProviderSelection(
            provider: VaultProvider.customLocation,
          ),
        );
        await pumpEventQueue();

        // The pre-fix code fell through to `state.vaultPassword!`, which threw and
        // surfaced as a generic RecoverBullUnexpectedFailure. The guard must keep
        // the intended typed failure and never reach vault creation.
        expect(bloc.state.failure, isA<PasswordNotSetFailure>());
        verifyNever(() => createVault.execute());

        await bloc.close();
      },
    );
  });

  group('OnVaultCreation store-key failure mapping', () {
    test(
      'local completion-marker failure does not make a stored vault retryable',
      () async {
        final vault = _MockEncryptedVault();
        when(() => vault.toFile()).thenReturn('{}');
        when(() => vault.filename).thenReturn('vault.json');
        when(() => createVault.execute()).thenAnswer(
          (_) async =>
              Ok((vault: vault, vaultKey: 'deadbeef', walletId: 'btc-wallet')),
        );
        when(() => checkConnection.execute()).thenAnswer((_) async => true);
        when(
          () => saveFile.execute(
            content: any(named: 'content'),
            filename: any(named: 'filename'),
          ),
        ).thenAnswer((_) async => const Ok(null));
        when(
          () => storeKey.execute(
            password: any(named: 'password'),
            vault: any(named: 'vault'),
            vaultKey: any(named: 'vaultKey'),
          ),
        ).thenAnswer((_) async => const Ok(null));
        when(
          () => completeEncryptedVaultBackup.execute(walletId: 'btc-wallet'),
        ).thenAnswer(
          (_) async =>
              const Err(VaultStatusPersistenceFailure('local marker failed')),
        );

        final bloc = buildBloc(flow: RecoverBullFlow.secureVault);
        addTearDown(bloc.close);
        bloc.add(
          const OnVaultCreation(
            provider: VaultProvider.customLocation,
            password: 'pw',
          ),
        );
        await pumpEventQueue();

        expect(bloc.state.vault, same(vault));
        expect(bloc.state.vaultProvider, VaultProvider.customLocation);
        expect(bloc.state.failure, isNull);
        verify(() => createVault.execute()).called(1);
        verify(
          () => storeKey.execute(
            password: 'pw',
            vault: vault,
            vaultKey: 'deadbeef',
          ),
        ).called(1);
      },
    );

    test(
      'rate-limited storeVaultKey -> VaultRateLimitedFailure (cooldown kept)',
      () async {
        const cooldown = Duration(minutes: 5);
        final vault = _MockEncryptedVault();
        when(() => vault.toFile()).thenReturn('{}');
        when(() => vault.filename).thenReturn('vault.json');

        when(() => createVault.execute()).thenAnswer(
          (_) async =>
              Ok((vault: vault, vaultKey: 'deadbeef', walletId: 'btc-wallet')),
        );
        when(() => checkConnection.execute()).thenAnswer((_) async => true);
        when(
          () => saveFile.execute(
            content: any(named: 'content'),
            filename: any(named: 'filename'),
          ),
        ).thenAnswer((_) async => const Ok(null));
        when(
          () => storeKey.execute(
            password: any(named: 'password'),
            vault: any(named: 'vault'),
            vaultKey: any(named: 'vaultKey'),
          ),
        ).thenAnswer(
          (_) async =>
              Err(const core.KeyServerRateLimitedFailure(retryIn: cooldown)),
        );

        final bloc = buildBloc(flow: RecoverBullFlow.secureVault);

        // secureVault stores the password, then provider selection triggers
        // creation.
        bloc.add(const OnVaultPasswordSet(password: 'pw'));
        await pumpEventQueue();
        bloc.add(
          const OnVaultProviderSelection(
            provider: VaultProvider.customLocation,
          ),
        );
        await pumpEventQueue();

        // The 429 cooldown must survive the create path instead of collapsing
        // into the generic VaultCreationFailure.
        expect(bloc.state.failure, isA<VaultRateLimitedFailure>());
        expect(
          (bloc.state.failure as VaultRateLimitedFailure).retryIn,
          cooldown,
        );

        await bloc.close();
      },
    );
  });

  group('recoverVault manifest recovery', () {
    test('recreates manifest wallets with the restored default ids before '
        'starting the wallet, then finishes', () async {
      final vault = _MockEncryptedVault();
      final bloc = buildBloc(
        flow: RecoverBullFlow.recoverVault,
        preSelectedVault: vault,
      );
      addTearDown(bloc.close);

      when(
        () => decrypt.execute(
          vault: any(named: 'vault'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenReturn(const Ok(DecryptedVault()));
      when(
        () =>
            updateLatest.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenAnswer((_) async => const Ok(null));
      when(
        () => restore.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenAnswer((_) async => const Ok(['btc-default', 'lbtc-default']));

      bloc.add(const OnVaultDecryption(vaultKey: 'deadbeef'));
      await pumpEventQueue();

      // The vault only restores the defaults; manifest (bip85) wallet recovery
      // must run with those default ids AND before the wallet is started, so
      // restored Donation Page / POS wallets are present on the first load.
      verifyInOrder([
        () => restore.execute(decryptedVault: any(named: 'decryptedVault')),
        () => recoverRemoteKeychain.execute(
          defaultCreatedWalletIds: {'btc-default', 'lbtc-default'},
        ),
        () => walletBloc.add(const WalletStarted()),
      ]);
      expect(bloc.state.isFlowFinished, isTrue);
      expect(bloc.state.failure, isNull);
    });

    test('a throwing recovery graph still reaches WalletStarted (recovery '
        'never blocks the restore)', () async {
      final vault = _MockEncryptedVault();
      // Real wrapper over a facade that throws an Error; the wrapper must
      // swallow it so the restore still starts the wallet.
      final facade = _MockRecoveryFacade();
      when(
        () => facade.recover(
          defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
        ),
      ).thenThrow(StateError('bug in recovery graph'));
      final bloc = buildBloc(
        flow: RecoverBullFlow.recoverVault,
        preSelectedVault: vault,
        recoverOverride: RecoverBullRemoteKeychainUsecase(facade),
      );
      addTearDown(bloc.close);

      when(
        () => decrypt.execute(
          vault: any(named: 'vault'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenReturn(const Ok(DecryptedVault()));
      when(
        () =>
            updateLatest.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenAnswer((_) async => const Ok(null));
      when(
        () => restore.execute(decryptedVault: any(named: 'decryptedVault')),
      ).thenAnswer((_) async => const Ok(['btc-default']));

      bloc.add(const OnVaultDecryption(vaultKey: 'deadbeef'));
      await pumpEventQueue();

      verify(() => walletBloc.add(const WalletStarted())).called(1);
      expect(bloc.state.isFlowFinished, isTrue);
      expect(bloc.state.failure, isNull);
    });

    test(
      'a restore failure never starts the wallet nor runs recovery',
      () async {
        final vault = _MockEncryptedVault();
        final bloc = buildBloc(
          flow: RecoverBullFlow.recoverVault,
          preSelectedVault: vault,
        );
        addTearDown(bloc.close);

        when(
          () => decrypt.execute(
            vault: any(named: 'vault'),
            vaultKey: any(named: 'vaultKey'),
          ),
        ).thenReturn(const Ok(DecryptedVault()));
        when(
          () => updateLatest.execute(
            decryptedVault: any(named: 'decryptedVault'),
          ),
        ).thenAnswer((_) async => const Ok(null));
        when(
          () => restore.execute(decryptedVault: any(named: 'decryptedVault')),
        ).thenAnswer(
          (_) async => Err(const core.RecoverBullUnexpectedCoreFailure('boom')),
        );

        bloc.add(const OnVaultDecryption(vaultKey: 'deadbeef'));
        await pumpEventQueue();

        verifyNever(
          () => recoverRemoteKeychain.execute(
            defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
          ),
        );
        verifyNever(() => walletBloc.add(const WalletStarted()));
        expect(bloc.state.failure, isA<VaultRecoveryFailure>());
      },
    );
  });
}
