export 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart'
    show GetPaidWalletBehavior, GetPaidWalletProduct;

import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart';

/// Public boundary for the reserved Get Paid wallets' behavior controls.
class GetPaidSettingsFacade {
  final GetGetPaidWalletBehaviorsUsecase _getWalletBehaviors;
  final UpdateWalletBehaviorUsecase _updateWalletBehavior;

  const GetPaidSettingsFacade(
    this._getWalletBehaviors,
    this._updateWalletBehavior,
  );

  Future<List<GetPaidWalletBehavior>> walletBehaviors({
    GetPaidWalletProduct? only,
  }) => _getWalletBehaviors.execute(only: only);

  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) => _updateWalletBehavior.execute(
    walletId: walletId,
    hideOnHome: hideOnHome,
    autoSweepEnabled: autoSweepEnabled,
  );
}
