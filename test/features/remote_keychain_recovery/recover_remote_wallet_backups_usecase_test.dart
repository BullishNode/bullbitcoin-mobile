import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/data/remote_recovery_outcome_store.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/recover_remote_wallet_backups_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  late _WalletBackupFacade walletBackup;
  late _MetadataBackupFacade metadataBackup;
  late _LifecycleLease lease;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    walletBackup = _WalletBackupFacade();
    metadataBackup = _MetadataBackupFacade();
    lease = _LifecycleLease();
    when(
      () => walletBackup.beginRecoveryLease(timeout: any(named: 'timeout')),
    ).thenAnswer((_) async => lease);
    when(
      () => walletBackup.setRecoveryBlocked(any()),
    ).thenAnswer((_) async => const Ok(null));
    when(
      walletBackup.fetchRemoteIdentity,
    ).thenAnswer((_) async => Ok(_initialIdentity));
  });

  test('persists fence before restore and clears after revalidation', () async {
    final calls = <String>[];
    when(
      () => walletBackup.beginRecoveryLease(timeout: any(named: 'timeout')),
    ).thenAnswer((_) async {
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

  test(
    'bounds a stalled initial remote identity read and releases lease',
    () async {
      when(walletBackup.fetchRemoteIdentity).thenAnswer(
        (_) =>
            Completer<Result<WalletBackupRemoteIdentity, WalletBackupFailure>>()
                .future,
      );
      var recoveryCalls = 0;
      final usecase = RecoverRemoteWalletBackupsUsecase(
        (_) async {
          recoveryCalls++;
          return const RemoteKeychainRecoveryResult(
            status: RemoteKeychainRecoveryStatus.restored,
          );
        },
        walletBackup,
        metadataBackup,
        budget: const Duration(milliseconds: 10),
      );

      final result = await usecase.execute(defaultCreatedWalletIds: const {});

      expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
      expect(recoveryCalls, 0);
      expect(lease.closeCalls, 1);
      verifyNever(() => walletBackup.setRecoveryBlocked(false));
    },
  );

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
      () => walletBackup.beginRecoveryLease(timeout: any(named: 'timeout')),
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
          deadline: any(named: 'deadline'),
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
          deadline: any(named: 'deadline'),
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
  group('persists the last unified wallet recovery outcome', () {
    test('a completed pass records status, timestamp, and counts - nothing '
        'else', () async {
      final store = RemoteRecoveryOutcomeStore(_MemoryKv());
      final usecase = RecoverRemoteWalletBackupsUsecase(
        (_) async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.partiallyRestored,
          restoredCount: 2,
          failedCount: 1,
          createdWalletIds: ['wallet-alpha'],
        ),
        walletBackup,
        metadataBackup,
        outcomeStore: store,
      );

      await usecase.execute(defaultCreatedWalletIds: {'bitcoin-default'});

      final outcome = await store.read();
      expect(outcome, isNotNull);
      expect(outcome!.status, RemoteKeychainRecoveryStatus.partiallyRestored);
      expect(outcome.restoredCount, 2);
      expect(outcome.failedCount, 1);
      expect(outcome.isIncomplete, isTrue);
      // Sanitization: the record carries exactly status/at/counts - never
      // wallet ids or manifest entries.
      expect(outcome.toJsonString(), isNot(contains('wallet-alpha')));
    });

    test('a pass that exceeds its budget records timedOut', () async {
      final store = RemoteRecoveryOutcomeStore(_MemoryKv());
      when(walletBackup.fetchRemoteIdentity).thenAnswer(
        (_) =>
            Completer<Result<WalletBackupRemoteIdentity, WalletBackupFailure>>()
                .future,
      );
      final usecase = RecoverRemoteWalletBackupsUsecase(
        (_) async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        ),
        walletBackup,
        metadataBackup,
        outcomeStore: store,
        budget: const Duration(milliseconds: 10),
      );

      await usecase.execute(defaultCreatedWalletIds: const {});

      final outcome = await store.read();
      expect(outcome!.status, RemoteKeychainRecoveryStatus.timedOut);
      expect(outcome.isIncomplete, isTrue);
    });

    test('a persistence failure never affects the recovery result', () async {
      final usecase = RecoverRemoteWalletBackupsUsecase(
        (_) async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        ),
        walletBackup,
        metadataBackup,
        outcomeStore: RemoteRecoveryOutcomeStore(_ThrowingKv()),
      );

      final result = await usecase.execute(defaultCreatedWalletIds: const {});

      expect(result.status, RemoteKeychainRecoveryStatus.restored);
    });
  });
}

class _MemoryKv implements KeyValueStorageDatasource<String> {
  final Map<String, String> _values = {};

  @override
  Future<void> saveValue({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> getValue(String key) async => _values[key];

  @override
  Future<Map<String, String>> getAll() async => Map.of(_values);

  @override
  Future<bool> hasValue(String key) async => _values.containsKey(key);

  @override
  Future<void> deleteValue(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}

final class _ThrowingKv extends _MemoryKv {
  @override
  Future<void> saveValue({required String key, required String value}) async {
    throw StateError('disk full');
  }
}

RecoverRemoteWalletBackupsUsecase _usecase({
  required WalletBackupFacade walletBackup,
  required WalletMetadataBackupFacade metadataBackup,
  required Future<RemoteKeychainRecoveryResult> Function() recover,
}) => RecoverRemoteWalletBackupsUsecase(
  (_) => recover(),
  walletBackup,
  metadataBackup,
);

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
