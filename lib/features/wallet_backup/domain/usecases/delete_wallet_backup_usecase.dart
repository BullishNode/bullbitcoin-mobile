import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:meta/meta.dart';

final class DeleteWalletBackupUsecase {
  final WalletBackupRemoteRepository _remote;
  final WalletBackupStateRepository _state;
  final WalletBackupWalletPort _wallet;
  final DeriveWalletBackupSignerUsecase _deriveSigner;

  const DeleteWalletBackupUsecase({
    required this._remote,
    required this._state,
    required this._wallet,
    required this._deriveSigner,
  });

  @useResult
  Future<Result<void, WalletBackupFailure>> execute({
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return const Err(WalletBackupConfirmationRequiredFailure());
    }

    final walletResult = await _wallet.deriveDefaultWallet();
    final WalletBackupWallet wallet;
    switch (walletResult) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }
    final signerResult = _deriveSigner.execute(
      xprvBase58: wallet.xprvBase58,
      expectedParentFingerprint: wallet.parentFingerprint,
    );
    final WalletBackupSigner signer;
    switch (signerResult) {
      case Ok(:final value):
        signer = value;
      case Err(:final failure):
        return Err(failure);
    }
    final fetchResult = await _remote.fetch(signer);
    final WalletBackupRemoteHead current;
    switch (fetchResult) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    final deleteResult = await _remote.delete(signer: signer, current: current);
    if (deleteResult case Err(:final failure)) return Err(failure);

    return _state.clearRemoteCheckpoint();
  }
}
