import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:meta/meta.dart';

typedef SyncWalletBackup =
    Future<Result<WalletBackupSyncResult, WalletBackupFailure>> Function({
      required String parentFingerprint,
      required String xprvBase58,
    });

final class BackupWalletNowUsecase {
  final WalletBackupStateRepository _state;
  final WalletBackupWalletPort _wallet;
  final SyncWalletBackup _sync;
  final Clock _clock;

  const BackupWalletNowUsecase({
    required this._state,
    required this._wallet,
    required this._sync,
    required this._clock,
  });

  @useResult
  Future<Result<void, WalletBackupFailure>> execute() async {
    final stateResult = await _state.get();
    final WalletBackupState state;
    switch (stateResult) {
      case Ok(:final value):
        state = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (!state.enabled) {
      return const Err(WalletBackupDisabledFailure());
    }
    if (state.unsupportedVersion case final version?) {
      return Err(WalletBackupUnsupportedEnvelopeVersionFailure(version));
    }
    if (!state.dirty) {
      return const Ok(null);
    }

    final attemptResult = await _state.recordAttempt(_clock.nowSecs());
    if (attemptResult case Err(:final failure)) return Err(failure);

    final walletResult = await _wallet.deriveDefaultWallet();
    final WalletBackupWallet wallet;
    switch (walletResult) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }
    final syncResult = await _sync(
      parentFingerprint: wallet.parentFingerprint,
      xprvBase58: wallet.xprvBase58,
    );
    final WalletBackupSyncResult sync;
    switch (syncResult) {
      case Ok(:final value):
        sync = value;
      case Err(:final failure):
        if (failure is WalletBackupUnsupportedEnvelopeVersionFailure) {
          final blockResult = await _state.blockUnsupportedVersion(
            failure.version,
          );
          if (blockResult case Err(:final failure)) return Err(failure);
        }
        return Err(failure);
    }

    return _state.recordSuccess(
      capturedDirtyRevision: state.dirtyRevision,
      succeededAt: _clock.nowSecs(),
      syncResult: sync,
    );
  }
}
