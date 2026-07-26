import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/get_last_wallet_backup_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/retry_wallet_backup_recovery_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  late _FakeWalletBackupFacade backup;
  late WalletBackupSettingsCubit cubit;

  setUp(() {
    backup = _FakeWalletBackupFacade();
    cubit = _cubit(backup);
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await backup.close();
  });

  test('watches and exposes the single unified backup state', () async {
    await cubit.load();
    backup.states.add(Ok(_state(enabled: true, dirty: true)));
    await pumpEventQueue();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.backup?.enabled, isTrue);
    expect(cubit.state.backup?.dirty, isTrue);
  });

  test('delegates enable, backup-now, and confirmed delete controls', () async {
    await cubit.setEnabled(true);
    await cubit.backupNow();
    await cubit.deleteRemoteBackup();

    expect(backup.enabledValues, [true]);
    expect(backup.backupNowCalls, 1);
    expect(backup.deleteConfirmedValues, [true]);
    expect(cubit.state.operation, WalletBackupSettingsOperation.idle);
  });

  test('maps newer-version failures without exposing diagnostics', () async {
    backup.backupNowResult = const Err(
      WalletBackupUnsupportedEnvelopeVersionFailure(2),
    );

    await cubit.backupNow();

    expect(cubit.state.failure, isA<BackupSettingsUpdateRequiredFailure>());
    expect(cubit.state.failureRevision, 1);
    expect(cubit.state.operation, WalletBackupSettingsOperation.idle);
  });

  test('programmer errors during backup propagate', () async {
    backup.backupNowFuture = Future.error(StateError('broken backup adapter'));

    await expectLater(cubit.backupNow(), throwsA(isA<StateError>()));
    expect(cubit.state.operation, WalletBackupSettingsOperation.idle);
  });

  test('does not emit after closing during a remote operation', () async {
    final result = Completer<Result<void, WalletBackupFailure>>();
    backup.backupNowFuture = result.future;

    final operation = cubit.backupNow();
    await pumpEventQueue();
    expect(cubit.state.operation, WalletBackupSettingsOperation.backingUp);

    await cubit.close();
    result.complete(const Ok(null));
    await operation;
  });

  test('does not resubscribe when closed during watch cancellation', () async {
    final cancellation = Completer<void>();
    final watched =
        StreamController<
          Result<WalletBackupState, WalletBackupFailure>
        >.broadcast(onCancel: () => cancellation.future);
    backup.watchStateStream = watched.stream;
    addTearDown(watched.close);

    await cubit.load();
    expect(watched.hasListener, isTrue);

    final reload = cubit.load();
    await pumpEventQueue();
    final closing = cubit.close();
    cancellation.complete();
    await reload;
    await closing;

    expect(watched.hasListener, isFalse);
  });

  test(
    'retry applies its returned outcome without rereading persistence',
    () async {
      final remoteRecovery = _MockRemoteRecovery();
      when(() => remoteRecovery.getLastOutcome()).thenAnswer(
        (_) async => const RemoteRecoveryOutcome(
          status: RemoteKeychainRecoveryStatus.partiallyRestored,
          atUnix: 1,
          restoredCount: 1,
          failedCount: 1,
        ),
      );
      when(
        () => remoteRecovery.recover(
          defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
        ),
      ).thenAnswer(
        (_) async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
          restoredCount: 2,
        ),
      );
      await cubit.close();
      cubit = WalletBackupSettingsCubit(
        WatchWalletBackupUsecase(backup),
        SetWalletBackupEnabledUsecase(backup),
        BackupWalletNowUsecase(backup),
        DeleteWalletBackupUsecase(backup),
        GetLastWalletBackupRecoveryOutcomeUsecase(remoteRecovery).execute,
        RetryWalletBackupRecoveryUsecase(remoteRecovery).execute,
      );
      await cubit.load();
      backup.states.add(
        Ok(_state(enabled: true, dirty: false, recoveryBlocked: true)),
      );
      await pumpEventQueue();

      await cubit.retryRecovery();

      expect(
        cubit.state.lastRecoveryOutcome?.status,
        WalletBackupRecoveryOutcomeStatus.restored,
      );
      expect(cubit.state.lastRecoveryOutcome?.restoredCount, 2);
      expect(cubit.state.operation, WalletBackupSettingsOperation.idle);
      verify(() => remoteRecovery.getLastOutcome()).called(1);
    },
  );

  test('transient recovery failure remains retryable while fenced', () async {
    final remoteRecovery = _MockRemoteRecovery();
    when(() => remoteRecovery.getLastOutcome()).thenAnswer(
      (_) async => const RemoteRecoveryOutcome(
        status: RemoteKeychainRecoveryStatus.unavailable,
        atUnix: 1,
        restoredCount: 0,
        failedCount: 1,
      ),
    );
    when(
      () => remoteRecovery.recover(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer(
      (_) async => const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.unavailable,
        failedCount: 1,
      ),
    );
    await cubit.close();
    cubit = WalletBackupSettingsCubit(
      WatchWalletBackupUsecase(backup),
      SetWalletBackupEnabledUsecase(backup),
      BackupWalletNowUsecase(backup),
      DeleteWalletBackupUsecase(backup),
      GetLastWalletBackupRecoveryOutcomeUsecase(remoteRecovery).execute,
      RetryWalletBackupRecoveryUsecase(remoteRecovery).execute,
    );
    await cubit.load();
    backup.states.add(
      Ok(_state(enabled: true, dirty: false, recoveryBlocked: true)),
    );
    await pumpEventQueue();

    expect(cubit.state.canRetryRecovery, isTrue);
    await cubit.retryRecovery();

    expect(
      cubit.state.lastRecoveryOutcome?.status,
      WalletBackupRecoveryOutcomeStatus.unavailable,
    );
    expect(cubit.state.canRetryRecovery, isTrue);
    verify(
      () => remoteRecovery.recover(defaultCreatedWalletIds: const {}),
    ).called(1);
  });

  test(
    'thrown recovery failure stays visible after the snackbar event',
    () async {
      final remoteRecovery = _MockRemoteRecovery();
      when(() => remoteRecovery.getLastOutcome()).thenAnswer((_) async => null);
      when(
        () => remoteRecovery.recover(
          defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
        ),
      ).thenThrow(Exception('recovery unavailable'));
      await cubit.close();
      cubit = WalletBackupSettingsCubit(
        WatchWalletBackupUsecase(backup),
        SetWalletBackupEnabledUsecase(backup),
        BackupWalletNowUsecase(backup),
        DeleteWalletBackupUsecase(backup),
        GetLastWalletBackupRecoveryOutcomeUsecase(remoteRecovery).execute,
        RetryWalletBackupRecoveryUsecase(remoteRecovery).execute,
      );
      await cubit.load();
      backup.states.add(
        Ok(_state(enabled: true, dirty: false, recoveryBlocked: true)),
      );
      await pumpEventQueue();

      await cubit.retryRecovery();

      expect(cubit.state.failure, isA<BackupSettingsUnexpectedFailure>());
      expect(
        cubit.state.recoveryRetryResult?.kind,
        WalletBackupRecoveryResultKind.failed,
      );
      expect(cubit.state.operation, WalletBackupSettingsOperation.idle);
    },
  );
}

WalletBackupSettingsCubit _cubit(WalletBackupFacade backup) {
  return WalletBackupSettingsCubit(
    WatchWalletBackupUsecase(backup),
    SetWalletBackupEnabledUsecase(backup),
    BackupWalletNowUsecase(backup),
    DeleteWalletBackupUsecase(backup),
    () async => null,
    () async => throw StateError('recovery is not expected in this test'),
  );
}

WalletBackupState _state({
  required bool enabled,
  required bool dirty,
  bool recoveryBlocked = false,
}) {
  return WalletBackupState(
    enabled: enabled,
    dirty: dirty,
    dirtyRevision: dirty ? 1 : 0,
    lastAttemptedAt: null,
    lastSucceededAt: null,
    remoteGeneration: 0,
    remoteEtag: null,
    contentHash: null,
    unsupportedVersion: null,
    recoveryBlocked: recoveryBlocked,
  );
}

final class _FakeWalletBackupFacade implements WalletBackupFacade {
  final states =
      StreamController<
        Result<WalletBackupState, WalletBackupFailure>
      >.broadcast();
  final enabledValues = <bool>[];
  final deleteConfirmedValues = <bool>[];
  int backupNowCalls = 0;

  Result<void, WalletBackupFailure> setEnabledResult = const Ok(null);
  Result<void, WalletBackupFailure> backupNowResult = const Ok(null);
  Result<void, WalletBackupFailure> deleteResult = const Ok(null);
  Future<Result<void, WalletBackupFailure>>? backupNowFuture;
  Stream<Result<WalletBackupState, WalletBackupFailure>>? watchStateStream;

  @override
  Stream<Result<WalletBackupState, WalletBackupFailure>> watchState() {
    return watchStateStream ?? states.stream;
  }

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    enabledValues.add(enabled);
    return setEnabledResult;
  }

  @override
  Future<Result<void, WalletBackupFailure>> backupNow() async {
    backupNowCalls++;
    final future = backupNowFuture;
    if (future != null) return future;
    return backupNowResult;
  }

  @override
  Future<Result<void, WalletBackupFailure>> deleteRemoteBackup({
    required bool confirmed,
  }) async {
    deleteConfirmedValues.add(confirmed);
    return deleteResult;
  }

  Future<void> close() => states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MockRemoteRecovery extends Mock
    implements RemoteKeychainRecoveryFacade {}
