import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

/// Point of Sale's own wrapper over the Get Paid settings boundary: persist
/// the reserved wallet (103)'s display/sweep behavior.
///
/// Reports only whether the write landed, so the caller can restore what it
/// optimistically showed. No foreign exception reaches presentation.
class UpdatePosWalletBehaviorUsecase {
  final GetPaidSettingsFacade _getPaidSettings;

  const UpdatePosWalletBehaviorUsecase({required this._getPaidSettings});

  Future<bool> execute({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    try {
      await _getPaidSettings.updateWalletBehavior(
        walletId: walletId,
        hideOnHome: hideOnHome,
        autoSweepEnabled: autoSweepEnabled,
      );
      return true;
    } on Exception catch (error, stack) {
      log.warning(
        'Point of Sale wallet behavior update failed',
        error: error,
        trace: stack,
      );
      return false;
    }
  }
}
