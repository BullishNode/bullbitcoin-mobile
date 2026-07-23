import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/recover_remote_wallet_backups_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/get_last_remote_recovery_outcome_usecase.dart';

export 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
export 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

class RemoteKeychainRecoveryFacade {
  final RecoverRemoteWalletBackupsUsecase _recoverWalletBackups;
  final GetLastRemoteRecoveryOutcomeUsecase _getLastOutcome;

  const RemoteKeychainRecoveryFacade(
    this._recoverWalletBackups,
    this._getLastOutcome,
  );

  Future<RemoteKeychainRecoveryResult> recover({
    Set<String> defaultCreatedWalletIds = const {},
  }) {
    return _recoverWalletBackups.execute(
      defaultCreatedWalletIds: Set.unmodifiable(defaultCreatedWalletIds),
    );
  }

  Future<RemoteRecoveryOutcome?> getLastOutcome() => _getLastOutcome.execute();
}
