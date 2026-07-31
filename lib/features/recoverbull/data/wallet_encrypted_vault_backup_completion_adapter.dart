import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/recoverbull/domain/encrypted_vault_backup_completion_port.dart';

final class WalletEncryptedVaultBackupCompletionAdapter
    implements EncryptedVaultBackupCompletionPort {
  final WalletRepository _walletRepository;

  const WalletEncryptedVaultBackupCompletionAdapter(this._walletRepository);

  @override
  Future<void> markCompleted({
    required String walletId,
    required DateTime completedAt,
  }) {
    return _walletRepository.updateEncryptedBackupTime(
      time: completedAt,
      walletId: walletId,
    );
  }
}
