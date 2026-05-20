import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/recover_lightning_address_usecase.dart';

/// Public API for the lightning_address feature.
///
/// All cross-feature access MUST go through this facade.
class LightningAddressFacade {
  // Public navigation contract while LA management currently lives in Settings.
  static const String manageRouteName = 'lightningAddress';

  final RecoverLightningAddressUsecase _recover;
  final PayServicePort _payService;

  LightningAddressFacade({
    required RecoverLightningAddressUsecase recover,
    required PayServicePort payService,
  }) : _recover = recover,
       _payService = payService;

  Future<String?> recoverIfNeeded({required Environment environment}) =>
      _recover.execute(environment: environment);

  /// Returns the locally cached Lightning Address, if this device knows one.
  Future<String?> getCurrentLightningAddress() =>
      _payService.getStoredAddress();

  Future<String?> getCurrentNym() async {
    final address = await getCurrentLightningAddress();
    return address?.split('@').firstOrNull;
  }
}
