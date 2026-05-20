import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';

class StartWalletManifestRestoreAfterSeedRecoveryUsecase {
  final RestoreRemoteWalletManifestUsecase _restoreRemoteManifest;

  const StartWalletManifestRestoreAfterSeedRecoveryUsecase({
    required RestoreRemoteWalletManifestUsecase restoreRemoteManifest,
  }) : _restoreRemoteManifest = restoreRemoteManifest;

  void execute({void Function()? onWalletStateMayHaveChanged}) {
    unawaited(
      _restore(onWalletStateMayHaveChanged: onWalletStateMayHaveChanged),
    );
  }

  Future<void> _restore({void Function()? onWalletStateMayHaveChanged}) async {
    try {
      final result = await _restoreRemoteManifest.execute();
      if (result == null) {
        log.fine('No remote wallet manifest found after seed recovery');
        return;
      }
      log.fine(
        'Wallet manifest restore after seed recovery finished: '
        '${result.restoredCount} restored, '
        '${result.alreadyPresentCount} already present, '
        '${result.skippedCount} skipped, '
        '${result.failedCount} failed',
      );
      if (result.walletStateMayHaveChanged) {
        onWalletStateMayHaveChanged?.call();
      }
    } catch (e, stack) {
      log.warning(
        'Wallet manifest restore after seed recovery failed',
        error: e,
        trace: stack,
      );
    }
  }
}
