import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';

/// Public API for the lightning_address feature.
///
/// All cross-feature access MUST go through this facade.
class LightningAddressFacade {
  // Public navigation contract while LA management currently lives in Settings.
  static const String manageRouteName = 'lightningAddress';

  final PayServicePort _payService;

  LightningAddressFacade({required PayServicePort payService})
    : _payService = payService;

  /// Returns the locally cached Lightning Address, if this device knows one.
  Future<String?> getCurrentLightningAddress() =>
      _payService.getStoredAddress();
}
