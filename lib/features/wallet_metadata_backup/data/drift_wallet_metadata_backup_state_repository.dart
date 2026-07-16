import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

final class DriftWalletMetadataBackupStateRepository
    implements WalletMetadataBackupStateRepository {
  static const int _rowId = 1;
  static const String _unsupportedEnvelopeReason = 'unsupportedNewerEnvelope';

  final SqliteDatabase _database;

  const DriftWalletMetadataBackupStateRepository(this._database);

  @override
  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async {
    try {
      return Ok(_toEntity(await _readRow()));
    } on ArgumentError catch (error, trace) {
      return _storageFailure('load', error, trace);
    } on Exception catch (error, trace) {
      return _storageFailure('load', error, trace);
    }
  }

  @override
  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    try {
      final state = await _database.transaction(() async {
        final current = _toEntity(await _readRow());
        final next = update(current);
        if (!identical(current, next)) await _writeRow(next);
        return next;
      });
      return Ok(state);
    } on ArgumentError catch (error, trace) {
      return _storageFailure('update', error, trace);
    } on Exception catch (error, trace) {
      return _storageFailure('update', error, trace);
    }
  }

  Future<WalletMetadataBackupStateRow?> _readRow() {
    return (_database.select(
      _database.walletMetadataBackupStates,
    )..where((table) => table.id.equals(_rowId))).getSingleOrNull();
  }

  Future<void> _writeRow(WalletMetadataBackupState state) async {
    final head = state.verifiedHead;
    final blocked = state.unsupportedNewerEnvelope;
    final recoveryBlocked = state.recoveryBlock;
    await _database
        .into(_database.walletMetadataBackupStates)
        .insertOnConflictUpdate(
          WalletMetadataBackupStateRow(
            id: _rowId,
            enabled: state.enabled,
            relayDisclosureAcknowledged: state.relayDisclosureAcknowledged,
            dirty: state.dirty,
            dirtyRevision: state.dirtyRevision,
            lastAttemptedAt: state.lastAttemptedAt,
            lastAcceptedAt: state.lastAcceptedAt,
            lastVerifiedRootEventId: head?.rootEventId,
            lastVerifiedSnapshotRevision: head?.snapshotRevision,
            lastVerifiedContentHash: head?.canonicalContentHash,
            lastVerifiedAt: head?.verifiedAt,
            blockedReason: blocked == null ? null : _unsupportedEnvelopeReason,
            blockedRootEventId: blocked?.rootEventId,
            blockedEnvelopeVersion: blocked?.envelopeVersion,
            blockedEventCreatedAt: blocked?.eventCreatedAt,
            blockedObservedAt: blocked?.observedAt,
            recoveryBlockedReason: recoveryBlocked?.reason.name,
            recoveryBlockedRootEventId: recoveryBlocked?.rootEventId,
            recoveryBlockedSnapshotRevision: recoveryBlocked?.snapshotRevision,
            recoveryBlockedEventCreatedAt: recoveryBlocked?.eventCreatedAt,
            recoveryBlockedObservedAt: recoveryBlocked?.observedAt,
          ),
        );
  }

  WalletMetadataBackupState _toEntity(WalletMetadataBackupStateRow? row) {
    if (row == null) return WalletMetadataBackupState.initial;
    return WalletMetadataBackupState(
      enabled: row.enabled,
      relayDisclosureAcknowledged: row.relayDisclosureAcknowledged,
      dirty: row.dirty,
      dirtyRevision: row.dirtyRevision,
      lastAttemptedAt: row.lastAttemptedAt,
      lastAcceptedAt: row.lastAcceptedAt,
      verifiedHead: _verifiedHead(row),
      unsupportedNewerEnvelope: _unsupportedEnvelope(row),
      recoveryBlock: _recoveryBlock(row),
    );
  }

  WalletMetadataBackupVerifiedHead? _verifiedHead(
    WalletMetadataBackupStateRow row,
  ) {
    final values = [
      row.lastVerifiedRootEventId,
      row.lastVerifiedSnapshotRevision,
      row.lastVerifiedContentHash,
      row.lastVerifiedAt,
    ];
    if (values.every((value) => value == null)) return null;
    if (values.any((value) => value == null)) {
      throw const FormatException('stored verified head is incomplete');
    }
    return WalletMetadataBackupVerifiedHead(
      rootEventId: row.lastVerifiedRootEventId!,
      snapshotRevision: row.lastVerifiedSnapshotRevision!,
      canonicalContentHash: row.lastVerifiedContentHash!,
      verifiedAt: row.lastVerifiedAt!,
    );
  }

  WalletMetadataBackupUnsupportedEnvelope? _unsupportedEnvelope(
    WalletMetadataBackupStateRow row,
  ) {
    final values = [
      row.blockedReason,
      row.blockedRootEventId,
      row.blockedEnvelopeVersion,
      row.blockedEventCreatedAt,
      row.blockedObservedAt,
    ];
    if (values.every((value) => value == null)) return null;
    if (values.any((value) => value == null) ||
        row.blockedReason != _unsupportedEnvelopeReason) {
      throw const FormatException('stored blocked state is invalid');
    }
    return WalletMetadataBackupUnsupportedEnvelope(
      rootEventId: row.blockedRootEventId!,
      envelopeVersion: row.blockedEnvelopeVersion!,
      eventCreatedAt: row.blockedEventCreatedAt!,
      observedAt: row.blockedObservedAt!,
    );
  }

  WalletMetadataBackupRecoveryBlock? _recoveryBlock(
    WalletMetadataBackupStateRow row,
  ) {
    final values = [
      row.recoveryBlockedReason,
      row.recoveryBlockedRootEventId,
      row.recoveryBlockedSnapshotRevision,
      row.recoveryBlockedEventCreatedAt,
      row.recoveryBlockedObservedAt,
    ];
    if (values.every((value) => value == null)) return null;
    if (values.any((value) => value == null)) {
      throw const FormatException('stored recovery block is incomplete');
    }
    final reason = WalletMetadataRecoveryBlockReason.values
        .where((value) => value.name == row.recoveryBlockedReason)
        .firstOrNull;
    if (reason == null) {
      throw const FormatException('stored recovery block reason is invalid');
    }
    return WalletMetadataBackupRecoveryBlock(
      reason: reason,
      rootEventId: row.recoveryBlockedRootEventId!,
      snapshotRevision: row.recoveryBlockedSnapshotRevision!,
      eventCreatedAt: row.recoveryBlockedEventCreatedAt!,
      observedAt: row.recoveryBlockedObservedAt!,
    );
  }

  void _logStorageFailure(String operation, Object error, StackTrace trace) {
    log.warning(
      'Could not $operation wallet metadata backup state',
      error: error.runtimeType,
      trace: trace,
    );
  }

  Result<WalletMetadataBackupState, WalletMetadataBackupFailure>
  _storageFailure(String operation, Object error, StackTrace trace) {
    _logStorageFailure(operation, error, trace);
    return Err(
      WalletMetadataBackupStorageFailure(error.runtimeType.toString()),
    );
  }
}
