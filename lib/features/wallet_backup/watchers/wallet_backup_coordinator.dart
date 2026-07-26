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

/// Holds automatic publication while remote recovery restores local state.
///
/// A lease is intentionally owned by the coordinator so recovery cannot race
/// with a queued or in-flight publication of the same unified object.
abstract interface class WalletBackupLifecycleLease {
  void close();
}

final class _WalletBackupLifecycleLease implements WalletBackupLifecycleLease {
  final void Function() _release;
  bool _closed = false;

  _WalletBackupLifecycleLease(this._release);

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _release();
  }
}

/// Owns every automatic publication trigger for the single Bull backup.
///
/// Section owners only emit committed changes. This coordinator owns durable
/// dirtying, startup/resume/sync retries, and the single-flight publication
/// queue.
final class WalletBackupCoordinator with WidgetsBindingObserver {
  final Stream<void> manifestChanges;
  final Stream<void> metadataChanges;
  final Stream<ElectrumSyncResult> syncResults;
  final PublishWalletBackup publishBackup;
  final MarkWalletBackupDirty markDirty;

  StreamSubscription<void>? _manifestSubscription;
  StreamSubscription<void>? _metadataSubscription;
  StreamSubscription<ElectrumSyncResult>? _syncSubscription;
  Future<Result<void, WalletBackupFailure>>? _inFlight;
  Future<bool>? _dirtying;
  bool _publishRequested = false;
  bool _dirtyPending = false;
  bool _started = false;
  bool _disposed = false;
  int _publicationLeases = 0;
  Future<void> _lifecycleTail = Future.value();
  final List<Completer<Result<void, WalletBackupFailure>>>
  _deferredPublications = [];

  WalletBackupCoordinator({
    required this.manifestChanges,
    this.metadataChanges = const Stream<void>.empty(),
    required this.syncResults,
    required this.publishBackup,
    required this.markDirty,
  });

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _manifestSubscription = manifestChanges.listen(
      (_) => _scheduleDirtyChange(),
      onError: (Object error, StackTrace stack) {
        log.warning(
          'Wallet backup manifest change stream failed',
          error: error.runtimeType,
          trace: stack,
        );
      },
    );
    _metadataSubscription = metadataChanges.listen(
      (_) => _scheduleDirtyChange(),
      onError: (Object error, StackTrace stack) {
        log.warning(
          'Wallet backup metadata change stream failed',
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
    if (_publicationLeases > 0) {
      final deferred = Completer<Result<void, WalletBackupFailure>>();
      _deferredPublications.add(deferred);
      return deferred.future;
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
      final dirtying = _dirtying;
      if (dirtying != null) await dirtying;
      final running = _inFlight;
      if (running != null) {
        await running;
        continue;
      }
      if (_dirtying == null) return;
    }
  }

  /// Prevents publication until the returned lease is closed.
  ///
  /// Existing publication and dirty-state work are drained first. Changes
  /// observed while the lease is held remain durable and are retried when the
  /// lease is released.
  Future<WalletBackupLifecycleLease> beginRecoveryLease() =>
      _beginLifecycleLease();

  /// Serializes confirmed deletion with recovery and publication.
  Future<WalletBackupLifecycleLease> beginDeletionLease() =>
      _beginLifecycleLease();

  void retry() {
    if (_disposed || _publicationLeases > 0) return;
    if (_dirtying != null) return;
    if (_dirtyPending) {
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

  void _scheduleDirtyChange() {
    if (_disposed) return;
    _dirtyPending = true;
    _scheduleDirtying();
  }

  void _scheduleDirtying() {
    if (_disposed || _dirtying != null || !_dirtyPending) return;
    final operation = _drainDirtyChanges();
    _dirtying = operation;
    unawaited(
      operation
          .then<void>((succeeded) {
            if (identical(_dirtying, operation)) _dirtying = null;
            if (_disposed || !succeeded) return;
            if (_dirtyPending) {
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
    while (_dirtyPending && !_disposed) {
      _dirtyPending = false;
      final Result<void, WalletBackupFailure> dirtyResult;
      try {
        dirtyResult = await markDirty();
      } catch (_) {
        _dirtyPending = true;
        rethrow;
      }
      if (dirtyResult case Err(:final failure)) {
        _dirtyPending = true;
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
    await _metadataSubscription?.cancel();
    await _syncSubscription?.cancel();
    _manifestSubscription = null;
    _metadataSubscription = null;
    _syncSubscription = null;
    try {
      await _dirtying;
    } catch (_) {
      // The task's logging handler already recorded this failure.
    }
    await _inFlight;
    _publishRequested = false;
    for (final deferred in _deferredPublications) {
      if (!deferred.isCompleted) {
        deferred.complete(
          const Err(
            WalletBackupUnexpectedFailure('wallet backup coordinator disposed'),
          ),
        );
      }
    }
    _deferredPublications.clear();
  }

  Future<WalletBackupLifecycleLease> _beginLifecycleLease() async {
    if (_disposed) {
      throw StateError('wallet backup coordinator disposed');
    }

    _publicationLeases++;
    final predecessor = _lifecycleTail;
    final released = Completer<void>();
    _lifecycleTail = released.future;
    var closed = false;

    void release() {
      if (closed) return;
      closed = true;
      if (!released.isCompleted) released.complete();
      _releasePublicationLease();
    }

    try {
      await predecessor;
      if (_disposed) {
        throw StateError('wallet backup coordinator disposed');
      }
      await waitForIdle();
      return _WalletBackupLifecycleLease(release);
    } catch (_) {
      // Release both queue ownership and the publication block. In particular,
      // this drains callers deferred while a failing publication was being
      // awaited instead of leaving their futures stranded.
      release();
      rethrow;
    }
  }

  void _releasePublicationLease() {
    if (_publicationLeases == 0) return;
    _publicationLeases--;
    if (_publicationLeases != 0 || _disposed) return;
    final deferred = List<Completer<Result<void, WalletBackupFailure>>>.from(
      _deferredPublications,
    );
    _deferredPublications.clear();
    if (deferred.isEmpty) {
      retry();
      return;
    }
    unawaited(_publishDeferred(deferred));
  }

  Future<void> _publishDeferred(
    List<Completer<Result<void, WalletBackupFailure>>> deferred,
  ) async {
    try {
      final result = await publish();
      for (final completer in deferred) {
        if (!completer.isCompleted) completer.complete(result);
      }
    } catch (error, stack) {
      for (final completer in deferred) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    }
  }
}
