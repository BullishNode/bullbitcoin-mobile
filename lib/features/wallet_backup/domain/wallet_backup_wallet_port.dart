import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletBackupWalletPort {
  @useResult
  Future<Result<WalletBackupWallet, WalletBackupFailure>> deriveDefaultWallet();
}
