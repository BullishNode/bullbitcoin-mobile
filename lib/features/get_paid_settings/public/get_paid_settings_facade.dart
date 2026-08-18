export 'package:bb_mobile/features/get_paid_settings/domain/get_paid_wallet_behavior.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_advanced_settings_sheet.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_link_qr.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_name_choice.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_nym_claim_step.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_wallet_behavior_card.dart';
export 'package:bb_mobile/features/get_paid_settings/public/get_paid_wallet_behavior_unavailable_warning.dart';

import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_wallet_behavior.dart';

/// Public boundary for the reserved Get Paid wallets' behavior controls.
///
/// Callback-injection shape (the Lightning Address / Payment Page / POS facade
/// precedent): the locator wires each callback to its use case, so this feature's
/// use cases stay internal and no consumer — production code or test — has to
/// name one to reach the boundary.
class GetPaidSettingsFacade {
  final Future<List<GetPaidWalletBehavior>> Function({
    GetPaidWalletProduct? only,
  })
  _walletBehaviorsCallback;
  final Future<void> Function({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  })
  _updateWalletBehaviorCallback;

  const GetPaidSettingsFacade({
    required Future<List<GetPaidWalletBehavior>> Function({
      GetPaidWalletProduct? only,
    })
    walletBehaviors,
    required Future<void> Function({
      required String walletId,
      bool? hideOnHome,
      bool? autoSweepEnabled,
    })
    updateWalletBehavior,
  }) : _walletBehaviorsCallback = walletBehaviors,
       _updateWalletBehaviorCallback = updateWalletBehavior;

  Future<List<GetPaidWalletBehavior>> walletBehaviors({
    GetPaidWalletProduct? only,
  }) => _walletBehaviorsCallback(only: only);

  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) => _updateWalletBehaviorCallback(
    walletId: walletId,
    hideOnHome: hideOnHome,
    autoSweepEnabled: autoSweepEnabled,
  );
}
