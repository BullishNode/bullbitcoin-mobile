import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart';
import 'package:get_it/get_it.dart';

final class GetPaidSettingsLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<GetGetPaidWalletBehaviorsUsecase>(
      () => GetGetPaidWalletBehaviorsUsecase(
        getWallets: locator<GetWalletsUsecase>(),
      ),
    );
  }
}
