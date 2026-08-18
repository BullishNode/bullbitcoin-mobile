export 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart'
    show GetPaidWalletBehavior;

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

sealed class PaymentPageWalletBehaviorRead {
  const PaymentPageWalletBehaviorRead();
}

final class PaymentPageWalletBehaviorFound
    extends PaymentPageWalletBehaviorRead {
  final GetPaidWalletBehavior behavior;

  const PaymentPageWalletBehaviorFound(this.behavior);
}

final class PaymentPageWalletBehaviorAbsent
    extends PaymentPageWalletBehaviorRead {
  const PaymentPageWalletBehaviorAbsent();
}

final class PaymentPageWalletBehaviorUnavailable
    extends PaymentPageWalletBehaviorRead {
  const PaymentPageWalletBehaviorUnavailable();
}

/// Donation Page's own wrapper over the Get Paid settings boundary: read
/// the reserved wallet (102)'s display/sweep behavior.
///
/// A confirmed missing wallet and an unavailable read remain distinct so the
/// screen never hides a settings outage as though wallet 102 did not exist.
class GetPaymentPageWalletBehaviorUsecase {
  final GetPaidSettingsFacade _getPaidSettings;

  const GetPaymentPageWalletBehaviorUsecase({required this._getPaidSettings});

  Future<PaymentPageWalletBehaviorRead> execute() async {
    try {
      final behaviors = await _getPaidSettings.walletBehaviors(
        only: GetPaidWalletProduct.paymentPage,
      );
      return behaviors.isEmpty
          ? const PaymentPageWalletBehaviorAbsent()
          : PaymentPageWalletBehaviorFound(behaviors.first);
    } on Exception catch (error, stack) {
      log.warning(
        'Failed to load Donation Page wallet behavior',
        error: error,
        trace: stack,
      );
      return const PaymentPageWalletBehaviorUnavailable();
    }
  }
}
