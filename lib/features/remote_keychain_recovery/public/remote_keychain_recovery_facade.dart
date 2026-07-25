import 'package:bb_mobile/features/remote_keychain_recovery/domain/recover_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';

export 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';

final class RemoteKeychainRecoveryFacade {
  final RecoverRemoteKeychainManifestUsecase _recoverManifest;

  const RemoteKeychainRecoveryFacade(
    RecoverRemoteKeychainManifestUsecase recoverManifest,
  ) : _recoverManifest = recoverManifest;

  Future<RemoteKeychainRecoveryResult> recover() {
    return _recoverManifest.execute();
  }
}
