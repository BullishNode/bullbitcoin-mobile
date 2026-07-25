import 'dart:async';

import 'package:bb_mobile/core/electrum/domain/value_objects/electrum_sync_result.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:flutter/widgets.dart';

typedef PublishWalletBackup =
    Future<Result<void, WalletBackupFailure>> Function();
typedef MarkWalletBackupDirty =
    Future<Result<void, WalletBackupFailure>> Function();

/// Owns every automatic publication trigger for the single Bull backup.
///
/// Section owners only emit committed changes. This coordinator owns durable
/// dirtying, startup/resume/sync retries, and the single-flight publication
/// queue.
final class WalletBackupCoordinator with WidgetsBindingObserver {
  final Stream<void> manifestChanges;
  final Stream<ElectrumSyncResult> syncResults;
  final PublishWalletBackup publishBackup;
  final MarkWalletBackupDirty markDirty;

  StreamSubscription<void>? _manifestSubscription;
  StreamSubscription<ElectrumSyncResult>? _syncSubscription;
  Future<Result<void, WalletBackupFailure>>? _inFlight;
  Future<bool>? _dirtying;
  bool _publishRequested = false;
  bool _manifestDirtyPending = false;
  bool _started = false;
  bool _disposed = false;

  WalletBackupCoordinator({
    required this.manifestChanges,
    required this.syncResults,
    required this.publishBackup,
    required this.markDirty,
  });

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _manifestSubscription = manifestChanges.listen(
      (_) => _scheduleManifestChange(),
      onError: (Object error, StackTrace stack) {
        log.warning(
          'Wallet backup manifest change stream failed',
          error: error.runtimeType,
          trace: stack,
        );
      },
    );
    _syncSubscription = syncResults
        .where((result) => result.success)
        .listen(
          (_) => retry(),
          onError: (Object error, StackTrace stack) {
            log.warning(
              'Wallet backup sync retry stream failed',
              error: error.runtimeType,
              trace: stack,
            );
          },
        );
    retry();
  }

  /// Runs publication through one queue. A trigger arriving while a store is
  /// active schedules one more pass; the durable dirty revision decides
  /// whether that pass still has work.
  Future<Result<void, WalletBackupFailure>> publish() {
    if (_disposed) {
      return Future.value(
        const Err(
          WalletBackupUnexpectedFailure('wallet backup coordinator disposed'),
        ),
      );
    }
    _publishRequested = true;
    final running = _inFlight;
    if (running != null) return running;

    final completer = Completer<Result<void, WalletBackupFailure>>();
    _inFlight = completer.future;
    unawaited(_drain(completer));
    return completer.future;
  }

  /// Used by confirmed deletion after backup has been disabled. It prevents a
  /// store that began before disablement from completing after the delete and
  /// recreating the remote object.
  Future<void> waitForIdle() async {
    while (true) {
      final running = _inFlight;
      if (running == null) return;
      await running;
    }
  }

  void retry() {
    if (_disposed) return;
    if (_dirtying != null) return;
    if (_manifestDirtyPending) {
      _scheduleDirtying();
      return;
    }
    unawaited(
      publish()
          .then((result) {
            if (result case Err(
              :final failure,
            ) when failure is! WalletBackupDisabledFailure) {
              log.warning(
                'Automatic wallet backup did not complete',
                error: failure.runtimeType,
              );
            }
          })
          .catchError((Object error, StackTrace stack) {
            log.warning(
              'Automatic wallet backup failed',
              error: error.runtimeType,
              trace: stack,
            );
          }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) retry();
  }

  Future<void> _drain(
    Completer<Result<void, WalletBackupFailure>> completer,
  ) async {
    Result<void, WalletBackupFailure> result = const Ok(null);
    try {
      while (_publishRequested && !_disposed) {
        _publishRequested = false;
        result = await publishBackup();
      }
      _inFlight = null;
      completer.complete(result);
    } catch (error, stack) {
      _inFlight = null;
      completer.completeError(error, stack);
    }
  }

  void _scheduleManifestChange() {
    if (_disposed) return;
    _manifestDirtyPending = true;
    _scheduleDirtying();
  }

  void _scheduleDirtying() {
    if (_disposed || _dirtying != null || !_manifestDirtyPending) return;
    final operation = _drainDirtyChanges();
    _dirtying = operation;
    unawaited(
      operation
          .then<void>((succeeded) {
            if (identical(_dirtying, operation)) _dirtying = null;
            if (_disposed || !succeeded) return;
            if (_manifestDirtyPending) {
              _scheduleDirtying();
            } else {
              retry();
            }
          })
          .catchError((Object error, StackTrace stack) {
            if (identical(_dirtying, operation)) _dirtying = null;
            log.warning(
              'Wallet backup dirty scheduling failed',
              error: error.runtimeType,
              trace: stack,
            );
          }),
    );
  }

  Future<bool> _drainDirtyChanges() async {
    while (_manifestDirtyPending && !_disposed) {
      _manifestDirtyPending = false;
      final Result<void, WalletBackupFailure> dirtyResult;
      try {
        dirtyResult = await markDirty();
      } catch (_) {
        _manifestDirtyPending = true;
        rethrow;
      }
      if (dirtyResult case Err(:final failure)) {
        _manifestDirtyPending = true;
        log.warning(
          'Wallet backup could not record a manifest change',
          error: failure.runtimeType,
        );
        return false;
      }
    }
    return !_disposed;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
    await _manifestSubscription?.cancel();
    await _syncSubscription?.cancel();
    _manifestSubscription = null;
    _syncSubscription = null;
    try {
      await _dirtying;
    } catch (_) {
      // The task's logging handler already recorded this failure.
    }
    await _inFlight;
    _publishRequested = false;
  }
}
