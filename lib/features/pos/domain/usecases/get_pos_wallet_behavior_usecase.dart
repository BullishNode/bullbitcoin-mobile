export 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart'
    show GetPaidWalletBehavior;

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

sealed class PosWalletBehaviorRead {
  const PosWalletBehaviorRead();
}

final class PosWalletBehaviorFound extends PosWalletBehaviorRead {
  final GetPaidWalletBehavior behavior;

  const PosWalletBehaviorFound(this.behavior);
}

final class PosWalletBehaviorAbsent extends PosWalletBehaviorRead {
  const PosWalletBehaviorAbsent();
}

final class PosWalletBehaviorUnavailable extends PosWalletBehaviorRead {
  const PosWalletBehaviorUnavailable();
}

/// Point of Sale's own wrapper over the Get Paid settings boundary: read
/// the reserved wallet (103)'s display/sweep behavior.
///
/// A confirmed missing wallet and an unavailable read remain distinct so the
/// screen never hides a settings outage as though wallet 103 did not exist.
class GetPosWalletBehaviorUsecase {
  final GetPaidSettingsFacade _getPaidSettings;

  const GetPosWalletBehaviorUsecase({required this._getPaidSettings});

  Future<PosWalletBehaviorRead> execute() async {
    try {
      final behaviors = await _getPaidSettings.walletBehaviors(
        only: GetPaidWalletProduct.pos,
      );
      return behaviors.isEmpty
          ? const PosWalletBehaviorAbsent()
          : PosWalletBehaviorFound(behaviors.first);
    } on Exception catch (error, stack) {
      log.warning(
        'Failed to load Point of Sale wallet behavior',
        error: error,
        trace: stack,
      );
      return const PosWalletBehaviorUnavailable();
    }
  }
}
