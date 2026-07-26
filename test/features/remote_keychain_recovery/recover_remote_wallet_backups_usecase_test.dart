import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/recover_remote_wallet_backups_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  late _WalletBackupFacade walletBackup;
  late _MetadataBackupFacade metadataBackup;
  late _LifecycleLease lease;

  setUp(() {
    walletBackup = _WalletBackupFacade();
    metadataBackup = _MetadataBackupFacade();
    lease = _LifecycleLease();
    when(walletBackup.beginRecoveryLease).thenAnswer((_) async => lease);
    when(
      () => walletBackup.setRecoveryBlocked(any()),
    ).thenAnswer((_) async => const Ok(null));
    when(
      walletBackup.fetchRemoteIdentity,
    ).thenAnswer((_) async => Ok(_initialIdentity));
  });

  test('persists fence before restore and clears after revalidation', () async {
    final calls = <String>[];
    when(walletBackup.beginRecoveryLease).thenAnswer((_) async {
      calls.add('lease');
      return _LifecycleLease(() => calls.add('close'));
    });
    when(() => walletBackup.setRecoveryBlocked(any())).thenAnswer((
      invocation,
    ) async {
      calls.add('blocked:${invocation.positionalArguments.single}');
      return const Ok(null);
    });
    when(walletBackup.fetchRemoteIdentity).thenAnswer((_) async {
      calls.add('head');
      return Ok(_initialIdentity);
    });
    final usecase = _usecase(
      walletBackup: walletBackup,
      metadataBackup: metadataBackup,
      recover: () async {
        calls.add('keychain');
        return const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.noBackup,
        );
      },
    );

    final result = await usecase.execute(
      defaultCreatedWalletIds: const {'bitcoin-default'},
    );

    expect(result.status, RemoteKeychainRecoveryStatus.noBackup);
    expect(calls, [
      'lease',
      'blocked:true',
      'head',
      'keychain',
      'head',
      'blocked:false',
      'close',
    ]);
  });

  test('aborts before restore when durable fence cannot be written', () async {
    when(() => walletBackup.setRecoveryBlocked(true)).thenAnswer(
      (_) async => const Err(WalletBackupStorageFailure('database failed')),
    );
    var recoveryCalls = 0;
    final usecase = _usecase(
      walletBackup: walletBackup,
      metadataBackup: metadataBackup,
      recover: () async {
        recoveryCalls++;
        return const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        );
      },
    );

    await expectLater(
      usecase.execute(defaultCreatedWalletIds: const {}),
      throwsA(isA<Exception>()),
    );

    expect(recoveryCalls, 0);
    expect(lease.closeCalls, 1);
    verifyNever(walletBackup.fetchRemoteIdentity);
  });

  test('aborts when recovery lease acquisition fails', () async {
    when(
      walletBackup.beginRecoveryLease,
    ).thenAnswer((_) async => throw StateError('publication drain failed'));
    var recoveryCalls = 0;
    final usecase = _usecase(
      walletBackup: walletBackup,
      metadataBackup: metadataBackup,
      recover: () async {
        recoveryCalls++;
        return const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        );
      },
    );

    await expectLater(
      usecase.execute(defaultCreatedWalletIds: const {}),
      throwsA(isA<StateError>()),
    );

    expect(recoveryCalls, 0);
    verifyNever(() => walletBackup.setRecoveryBlocked(any()));
  });

  test('leaves fence set when remote head changes during recovery', () async {
    var fetchCalls = 0;
    when(walletBackup.fetchRemoteIdentity).thenAnswer((_) async {
      fetchCalls++;
      return Ok(fetchCalls == 1 ? _initialIdentity : _changedIdentity);
    });
    final usecase = _usecase(
      walletBackup: walletBackup,
      metadataBackup: metadataBackup,
      recover: () async => const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 1,
      ),
    );

    final result = await usecase.execute(defaultCreatedWalletIds: const {});

    expect(result.status, RemoteKeychainRecoveryStatus.conflict);
    expect(result.restoredCount, 1);
    verify(() => walletBackup.setRecoveryBlocked(true)).called(1);
    verifyNever(() => walletBackup.setRecoveryBlocked(false));
    expect(lease.closeCalls, 1);
  });

  test('leaves fence set when final remote head is unavailable', () async {
    var fetchCalls = 0;
    when(walletBackup.fetchRemoteIdentity).thenAnswer((_) async {
      fetchCalls++;
      if (fetchCalls == 1) return Ok(_initialIdentity);
      return const Err(WalletBackupRemoteUnavailableFailure('offline'));
    });
    final usecase = _usecase(
      walletBackup: walletBackup,
      metadataBackup: metadataBackup,
      recover: () async => const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.nothingToRestore,
      ),
    );

    final result = await usecase.execute(defaultCreatedWalletIds: const {});

    expect(result.status, RemoteKeychainRecoveryStatus.unavailable);
    verifyNever(() => walletBackup.setRecoveryBlocked(false));
  });

  test(
    'reports failure when the completed recovery fence cannot clear',
    () async {
      when(() => walletBackup.setRecoveryBlocked(false)).thenAnswer(
        (_) async => const Err(WalletBackupStorageFailure('database failed')),
      );
      final usecase = _usecase(
        walletBackup: walletBackup,
        metadataBackup: metadataBackup,
        recover: () async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        ),
      );

      await expectLater(
        usecase.execute(defaultCreatedWalletIds: const {}),
        throwsA(isA<Exception>()),
      );

      verify(() => walletBackup.setRecoveryBlocked(true)).called(1);
      verify(() => walletBackup.setRecoveryBlocked(false)).called(1);
      expect(lease.closeCalls, 1);
    },
  );

  test(
    'restores metadata for all created wallets before clearing fence',
    () async {
      when(
        () => metadataBackup.recoverSection(
          payload: any(named: 'payload'),
          createdWalletRefs: any(named: 'createdWalletRefs'),
        ),
      ).thenAnswer(
        (_) async => const Ok(WalletMetadataRecoveryResult.noSnapshotFound()),
      );
      final usecase = _usecase(
        walletBackup: walletBackup,
        metadataBackup: metadataBackup,
        recover: () async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
          createdWalletIds: ['get-paid-wallet'],
          metadataPayload: '{"metadata":true}',
        ),
      );

      await usecase.execute(defaultCreatedWalletIds: const {'bitcoin-default'});

      verify(
        () => metadataBackup.recoverSection(
          payload: '{"metadata":true}',
          createdWalletRefs: {'bitcoin-default', 'get-paid-wallet'},
        ),
      ).called(1);
      verify(() => walletBackup.setRecoveryBlocked(false)).called(1);
    },
  );

  test(
    'keychain exception leaves durable fence set and releases lease',
    () async {
      final usecase = _usecase(
        walletBackup: walletBackup,
        metadataBackup: metadataBackup,
        recover: () async => throw Exception('keychain database unavailable'),
      );

      await expectLater(
        usecase.execute(defaultCreatedWalletIds: const {}),
        throwsA(isA<Exception>()),
      );

      verify(() => walletBackup.setRecoveryBlocked(true)).called(1);
      verifyNever(() => walletBackup.setRecoveryBlocked(false));
      expect(lease.closeCalls, 1);
    },
  );
}

RecoverRemoteWalletBackupsUsecase _usecase({
  required WalletBackupFacade walletBackup,
  required WalletMetadataBackupFacade metadataBackup,
  required Future<RemoteKeychainRecoveryResult> Function() recover,
}) => RecoverRemoteWalletBackupsUsecase(recover, walletBackup, metadataBackup);

final _initialIdentity = WalletBackupRemoteIdentity(
  found: true,
  generation: 1,
  etag: '11' * 32,
  ciphertextSha256: '22' * 32,
);

final _changedIdentity = WalletBackupRemoteIdentity(
  found: true,
  generation: 2,
  etag: '33' * 32,
  ciphertextSha256: '44' * 32,
);

final class _WalletBackupFacade extends Mock implements WalletBackupFacade {}

final class _MetadataBackupFacade extends Mock
    implements WalletMetadataBackupFacade {}

final class _LifecycleLease implements WalletBackupLifecycleLease {
  final void Function()? _onClose;
  int closeCalls = 0;

  _LifecycleLease([this._onClose]);

  @override
  void close() {
    closeCalls++;
    _onClose?.call();
  }
}
