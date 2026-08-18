import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

WalletBackupSettingsCubit _cubit(WalletBackupFacade backup) {
  return WalletBackupSettingsCubit(
    WatchWalletBackupUsecase(backup),
    SetWalletBackupEnabledUsecase(backup),
    BackupWalletNowUsecase(backup),
    DeleteWalletBackupUsecase(backup),
  );
}

WalletBackupState _state({required bool enabled, required bool dirty}) {
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
