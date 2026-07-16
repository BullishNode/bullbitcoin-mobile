import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';

final class WalletMetadataBackupCoordinator {
  final MarkWalletMetadataBackupDirtyUsecase _markDirty;
  final Future<
    Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>
  >
  Function()
  _publishCurrent;
  final WalletMetadataPublicationGuard _guard;
  final List<WalletMetadataChangeSource> Function() _sources;
  final Duration _debounce;
  final List<StreamSubscription<void>> _subscriptions = [];

  Future<WalletMetadataBackupFailure?> _dirtyBarrier = Future.value(null);
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>?
  _publicationInFlight;
  Timer? _publicationTimer;
  bool _dirtyWriteQueued = false;
  bool _retryAfterPublication = false;
  bool _started = false;

  WalletMetadataBackupCoordinator({
    required this._markDirty,
    required this._publishCurrent,
    required this._guard,
    required this._sources,
    this._debounce = const Duration(seconds: 2),
  }) {
    if (_debounce.isNegative) {
      throw ArgumentError('Wallet metadata backup coordinator is invalid');
    }
  }

  Future<void> start() async {
    if (_started) return;
    final sources = _sources();
    if (sources.isEmpty) {
      throw StateError('Wallet metadata backup has no change sources');
    }

    final subscriptions = <StreamSubscription<void>>[];
    try {
      for (final source in sources) {
        subscriptions.add(
          source.changes.listen(
            (_) => _handleSourceChange(),
            onError: (Object _, StackTrace stack) {
              log.warning(
                'Wallet metadata change source failed',
                error: StateError('Wallet metadata change source unavailable'),
                trace: stack,
              );
            },
          ),
        );
      }
    } catch (_) {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      rethrow;
    }

    _subscriptions.addAll(subscriptions);
    _started = true;
    scheduleRetry();
  }

  void scheduleRetry() {
    if (!_started || _guard.isPublicationSuppressed) return;
    _publicationTimer?.cancel();
    _publicationTimer = Timer(_debounce, retryBestEffort);
  }

  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  publishNow() async {
    if (_guard.isPublicationSuppressed) {
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.notReady,
        ),
      );
    }
    _publicationTimer?.cancel();
    _publicationTimer = null;
    final dirtyFailure = await _dirtyBarrier;
    if (dirtyFailure != null) return Err(dirtyFailure);
    if (_guard.isPublicationSuppressed) {
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.notReady,
        ),
      );
    }

    final active = _publicationInFlight;
    if (active != null) return active;
    final publication = _publishCurrent();
    _publicationInFlight = publication;
    try {
      return await publication;
    } finally {
      if (identical(_publicationInFlight, publication)) {
        _publicationInFlight = null;
      }
      if (_retryAfterPublication) {
        _retryAfterPublication = false;
        scheduleRetry();
      }
    }
  }

  Future<void> retryBestEffort() async {
    try {
      final result = await publishNow();
      if (result case Err(:final failure)) {
        log.warning(
          'Wallet metadata backup attempt failed',
          error: StateError(failure.runtimeType.toString()),
        );
      }
    } on Exception catch (_, stack) {
      log.warning(
        'Wallet metadata backup attempt threw unexpectedly',
        error: StateError('Wallet metadata backup attempt failed'),
        trace: stack,
      );
    }
  }

  Future<WalletMetadataPublicationSuppression> beginRecoverySession() async {
    final suppression = _guard.beginPublicationSuppression(
      onReleased: scheduleRetry,
    );
    _publicationTimer?.cancel();
    _publicationTimer = null;
    var acquired = false;
    try {
      final active = _publicationInFlight;
      if (active != null) {
        try {
          await active;
        } on Exception catch (_, stack) {
          log.warning(
            'Wallet metadata recovery waited for a failed publication',
            error: StateError('Wallet metadata publication failed'),
            trace: stack,
          );
        }
      }
      acquired = true;
      return suppression;
    } finally {
      if (!acquired) suppression.close();
    }
  }

  Future<T> suppressPublicationWhile<T>(Future<T> Function() action) async {
    final suppression = await beginRecoverySession();
    try {
      return await action();
    } finally {
      suppression.close();
    }
  }

  Future<void> dispose() async {
    _started = false;
    _retryAfterPublication = false;
    _publicationTimer?.cancel();
    _publicationTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _handleSourceChange() {
    if (_guard.ignoresOwnerChanges) return;
    if (_publicationInFlight != null) _retryAfterPublication = true;
    if (!_dirtyWriteQueued) {
      _dirtyWriteQueued = true;
      _dirtyBarrier = _dirtyBarrier.then((_) async {
        _dirtyWriteQueued = false;
        try {
          final result = await _markDirty.execute();
          return switch (result) {
            Ok() => null,
            Err(:final failure) => failure,
          };
        } on Exception catch (_, stack) {
          log.warning(
            'Wallet metadata dirty-state update failed unexpectedly',
            error: StateError('Wallet metadata dirty-state update failed'),
            trace: stack,
          );
          return const WalletMetadataBackupStorageFailure();
        }
      });
    }
    scheduleRetry();
  }
}
