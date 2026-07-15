import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/data/default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:get_it/get_it.dart';

class RemoteKeychainRecoveryLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<RemoteKeychainRecoveryDefaultWalletXprvPort>(
      () => RemoteKeychainRecoveryDefaultWalletXprvAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<CheckRemoteKeychainRecoveryUsecase>(
      () => CheckRemoteKeychainRecoveryUsecase(
        defaultWalletXprv:
            locator<RemoteKeychainRecoveryDefaultWalletXprvPort>(),
        keychainManifest: locator<KeychainManifestFacade>(),
        relayPolicy: const NostrRelayPolicyFacade(),
      ),
    );
    locator.registerFactory<RestoreRemoteKeychainManifestUsecase>(
      () => RestoreRemoteKeychainManifestUsecase(
        keychainRecovery: locator<KeychainRecoveryFacade>(),
      ),
    );
    locator.registerFactory<RemoteKeychainRecoveryCubit>(
      () => RemoteKeychainRecoveryCubit(
        checkRecovery: locator<CheckRemoteKeychainRecoveryUsecase>(),
        restoreManifest: locator<RestoreRemoteKeychainManifestUsecase>(),
      ),
    );
  }
}
