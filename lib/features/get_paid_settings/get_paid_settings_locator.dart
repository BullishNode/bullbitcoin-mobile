import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:get_it/get_it.dart';

final class GetPaidSettingsLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<GetGetPaidWalletBehaviorsUsecase>(
      () => GetGetPaidWalletBehaviorsUsecase(
        getWallets: locator<GetWalletsUsecase>(),
        manifest: locator<KeychainManifestFacade>(),
      ),
    );
    locator.registerFactory<GetPaidSettingsFacade>(
      () => GetPaidSettingsFacade(
        locator<GetGetPaidWalletBehaviorsUsecase>(),
        locator<UpdateWalletBehaviorUsecase>(),
      ),
    );
  }
}
