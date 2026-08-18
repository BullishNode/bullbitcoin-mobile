import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/recoverbull/data/wallet_encrypted_vault_backup_completion_adapter.dart';
import 'package:bb_mobile/features/recoverbull/domain/complete_encrypted_vault_backup_usecase.dart';
import 'package:bb_mobile/features/recoverbull/domain/encrypted_vault_backup_completion_port.dart';
import 'package:get_it/get_it.dart';

class RecoverBullLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<EncryptedVaultBackupCompletionPort>(
      () => WalletEncryptedVaultBackupCompletionAdapter(
        locator<WalletRepository>(),
      ),
    );
    locator.registerFactory<CompleteEncryptedVaultBackupUsecase>(
      () => CompleteEncryptedVaultBackupUsecase(
        locator<EncryptedVaultBackupCompletionPort>(),
      ),
    );
  }
}
