import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote_identity.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:meta/meta.dart';

final class FetchWalletBackupRemoteIdentityUsecase {
  final WalletBackupWalletPort _wallet;
  final DeriveWalletBackupSignerUsecase _deriveSigner;
  final WalletBackupRemoteRepository _remote;

  const FetchWalletBackupRemoteIdentityUsecase(
    this._wallet,
    this._deriveSigner,
    this._remote,
  );

  @useResult
  Future<Result<WalletBackupRemoteIdentity, WalletBackupFailure>>
  execute() async {
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

    return (await _remote.fetch(
      signer,
    )).map(WalletBackupRemoteIdentity.fromHead);
  }
}
