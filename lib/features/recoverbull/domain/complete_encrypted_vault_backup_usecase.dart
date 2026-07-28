import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/recoverbull/domain/encrypted_vault_backup_completion_port.dart';
import 'package:bb_mobile/features/recoverbull/domain/recoverbull_failure.dart';
import 'package:meta/meta.dart';

class CompleteEncryptedVaultBackupUsecase {
  final EncryptedVaultBackupCompletionPort _completion;

  CompleteEncryptedVaultBackupUsecase(this._completion);

  @useResult
  Future<Result<void, RecoverBullFailure>> execute({
    required String walletId,
  }) async {
    try {
      await _completion.markCompleted(
        walletId: walletId,
        completedAt: DateTime.now(),
      );
      return const Ok(null);
    } on Exception catch (e, st) {
      return _failure(e, st);
    }
  }

  Err<void, RecoverBullFailure> _failure(Object error, StackTrace trace) {
    log.warning(
      'completeEncryptedVaultBackup failed',
      error: error,
      trace: trace,
    );
    return Err(VaultStatusPersistenceFailure(error.toString()));
  }
}
