// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';

class RestoreRemoteKeychainManifestUsecase {
  final KeychainRecoveryFacade _keychainRecovery;

  const RestoreRemoteKeychainManifestUsecase({
    required KeychainRecoveryFacade keychainRecovery,
  }) : _keychainRecovery = keychainRecovery;

  Future<RemoteKeychainRecoveryRestoreSummary> execute(
    KeychainManifestImportPlan importPlan,
  ) async {
    try {
      final result = await _keychainRecovery.restoreWallets(importPlan);
      return RemoteKeychainRecoveryRestoreSummary.fromResult(result);
    } catch (e) {
      throw RemoteKeychainRecoveryException(
        RemoteKeychainRecoveryErrorKind.restoreFailed,
        cause: e,
      );
    }
  }
}
