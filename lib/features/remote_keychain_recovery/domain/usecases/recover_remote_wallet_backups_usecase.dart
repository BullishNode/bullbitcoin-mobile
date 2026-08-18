import 'dart:async';

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/repositories/remote_recovery_outcome_repository.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

typedef _RecoverKeychain =
    Future<RemoteKeychainRecoveryResult> Function(DateTime deadline);

enum _MetadataRecoveryStatus { complete, incomplete, timedOut }

final class RecoverRemoteWalletBackupsUsecase {
  static const defaultRecoveryBudget = Duration(seconds: 60);

  final _RecoverKeychain _recoverKeychain;
  final WalletBackupFacade _walletBackup;
  final WalletMetadataBackupFacade _metadataBackup;
  final Clock clock;
  final RemoteRecoveryOutcomeRepository? outcomeRepository;
  final Duration budget;

  const RecoverRemoteWalletBackupsUsecase(
    this._recoverKeychain,
    this._walletBackup,
    this._metadataBackup, {
    this.clock = const SystemClock(),
    this.outcomeRepository,
    this.budget = defaultRecoveryBudget,
  });

  Future<RemoteKeychainRecoveryResult> execute({
    required Set<String> defaultCreatedWalletIds,
  }) async {
    try {
      final result = await _executeWithinBudget(
        defaultCreatedWalletIds: defaultCreatedWalletIds,
      );
      _persistOutcome(result);
      return result;
    } on Exception catch (error, stack) {
      log.warning(
        'Remote wallet recovery failed before producing an outcome',
        error: error,
        trace: stack,
      );
      _persistOutcome(
        const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.localFailure,
        ),
      );
      rethrow;
    }
  }

  /// Best-effort record for the unified wallet-backup settings surface.
  void _persistOutcome(RemoteKeychainRecoveryResult result) {
    final repository = outcomeRepository;
    if (repository == null) return;
    unawaited(
      repository
          .save(
            RemoteRecoveryOutcome(
              status: result.status,
              atUnix: clock.nowUtc().millisecondsSinceEpoch ~/ 1000,
              restoredCount: result.restoredCount,
              failedCount: result.failedCount,
            ),
          )
          .catchError((Object error, StackTrace stack) {
            log.warning(
              'Could not persist the remote recovery outcome',
              error: error,
              trace: stack,
            );
          }),
    );
  }

  Future<RemoteKeychainRecoveryResult> _executeWithinBudget({
    required Set<String> defaultCreatedWalletIds,
  }) async {
    final deadline = clock.nowUtc().add(budget);
    WalletBackupLifecycleLease? lease;
    Object? keychainError;
    StackTrace? keychainStack;
    RemoteKeychainRecoveryResult? keychainResult;
    var metadataStatus = _MetadataRecoveryStatus.complete;
    WalletBackupRemoteIdentity initialRemoteIdentity;

    try {
      lease = await _walletBackup.beginRecoveryLease(
        timeout: _remaining(deadline),
      );
      _throwIfDeadlineReached(deadline);
      _requireOk(
        await _walletBackup.setRecoveryBlocked(true),
        'persist recovery block before restore',
      );
      _throwIfDeadlineReached(deadline);
      initialRemoteIdentity = _requireValue(
        await _walletBackup.fetchRemoteIdentity().timeout(_remaining(deadline)),
        'capture remote checkpoint before restore',
      );

      try {
        keychainResult = await _recoverKeychain(deadline);
      } on Exception catch (error, stack) {
        keychainError = error;
        keychainStack = stack;
      }

      final metadataPayload = keychainResult?.metadataPayload;
      if (metadataPayload != null) {
        metadataStatus = await _recoverMetadata(
          payload: metadataPayload,
          createdWalletRefs: {
            ...defaultCreatedWalletIds,
            ...?keychainResult?.createdWalletIds,
          },
          deadline: deadline,
        );
      }

      final keychainComplete =
          keychainError == null &&
          keychainResult != null &&
          switch (keychainResult.status) {
            RemoteKeychainRecoveryStatus.noBackup ||
            RemoteKeychainRecoveryStatus.nothingToRestore ||
            RemoteKeychainRecoveryStatus.restored => true,
            _ => false,
          };
      if (keychainComplete &&
          metadataStatus == _MetadataRecoveryStatus.complete) {
        _throwIfDeadlineReached(deadline);
        final finalIdentityResult = await _walletBackup
            .fetchRemoteIdentity()
            .timeout(_remaining(deadline));
        final WalletBackupRemoteIdentity finalRemoteIdentity;
        switch (finalIdentityResult) {
          case Ok(:final value):
            finalRemoteIdentity = value;
          case Err(:final failure):
            log.warning(
              'Could not revalidate remote wallet backup after recovery',
              error: failure.runtimeType,
            );
            return _withStatus(
              keychainResult,
              RemoteKeychainRecoveryStatus.unavailable,
            );
        }
        if (finalRemoteIdentity != initialRemoteIdentity) {
          log.warning('Remote wallet backup changed during recovery');
          return _withStatus(
            keychainResult,
            RemoteKeychainRecoveryStatus.conflict,
          );
        }
        _throwIfDeadlineReached(deadline);
        _requireOk(
          await _walletBackup.setRecoveryBlocked(false),
          'clear recovery block after revalidation',
        );
      } else {
        log.warning(
          'Unified wallet backup recovery remains publication-blocked',
        );
      }
    } on TimeoutException {
      return _withStatus(keychainResult, RemoteKeychainRecoveryStatus.timedOut);
    } finally {
      lease?.close();
    }

    if (keychainError != null) {
      Error.throwWithStackTrace(keychainError, keychainStack!);
    }
    if (metadataStatus != _MetadataRecoveryStatus.complete) {
      return _withStatus(
        keychainResult,
        metadataStatus == _MetadataRecoveryStatus.timedOut
            ? RemoteKeychainRecoveryStatus.timedOut
            : RemoteKeychainRecoveryStatus.partiallyRestored,
      );
    }
    return keychainResult!;
  }

  Future<_MetadataRecoveryStatus> _recoverMetadata({
    required String payload,
    required Set<String> createdWalletRefs,
    required DateTime deadline,
  }) async {
    if (_deadlineReached(deadline)) {
      return _MetadataRecoveryStatus.timedOut;
    }
    try {
      final result = await _metadataBackup.recoverSection(
        payload: payload,
        createdWalletRefs: Set.unmodifiable(createdWalletRefs),
        deadline: deadline,
      );
      if (_deadlineReached(deadline)) {
        return _MetadataRecoveryStatus.timedOut;
      }
      if (result case Err(:final failure)) {
        log.warning(
          'Remote wallet metadata recovery failed',
          error: StateError(failure.runtimeType.toString()),
        );
        return _MetadataRecoveryStatus.incomplete;
      }
      switch (result) {
        case Ok(:final value):
          return value.status == WalletMetadataRecoveryStatus.recovered ||
                  value.status == WalletMetadataRecoveryStatus.noSnapshotFound
              ? _MetadataRecoveryStatus.complete
              : _MetadataRecoveryStatus.incomplete;
        case Err():
          return _MetadataRecoveryStatus.incomplete;
      }
    } on TimeoutException {
      return _MetadataRecoveryStatus.timedOut;
    } on Exception catch (error, stack) {
      log.warning(
        'Remote wallet metadata recovery threw unexpectedly',
        error: error,
        trace: stack,
      );
      return _MetadataRecoveryStatus.incomplete;
    }
  }

  T _requireValue<T>(Result<T, WalletBackupFailure> result, String operation) {
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw _WalletBackupRecoveryException(
        '$operation failed: ${failure.runtimeType}',
      ),
    };
  }

  void _requireOk(Result<void, WalletBackupFailure> result, String operation) =>
      _requireValue(result, operation);

  RemoteKeychainRecoveryResult _withStatus(
    RemoteKeychainRecoveryResult? result,
    RemoteKeychainRecoveryStatus status,
  ) => RemoteKeychainRecoveryResult(
    status: status,
    restoredCount: result?.restoredCount ?? 0,
    failedCount: result?.failedCount ?? 0,
    createdWalletIds: result?.createdWalletIds ?? const [],
    metadataPayload: result?.metadataPayload,
  );

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(clock.nowUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _deadlineReached(DateTime deadline) =>
      !clock.nowUtc().isBefore(deadline);

  void _throwIfDeadlineReached(DateTime deadline) {
    if (_deadlineReached(deadline)) throw TimeoutException('recovery deadline');
  }
}

final class _WalletBackupRecoveryException implements Exception {
  final String message;

  const _WalletBackupRecoveryException(this.message);

  @override
  String toString() => message;
}
