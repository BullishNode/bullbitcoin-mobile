import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';

/// Public API for the lightning_address feature.
///
/// All cross-feature access MUST go through this facade.
class LightningAddressFacade {
  // Public navigation contract while LA management currently lives in Settings.
  static const String manageRouteName = 'lightningAddress';

  final PayServicePort _payService;
  final LookupLightningAddressStatusUsecase _lookupStatus;

  LightningAddressFacade({
    required PayServicePort payService,
    required LookupLightningAddressStatusUsecase lookupStatus,
  }) : _payService = payService,
       _lookupStatus = lookupStatus;

  /// Returns the current server-owned Lightning Address for this seed's
  /// Bullnym auth key. A stale local cache must not authorize Get Paid writes.
  Future<String?> getCurrentLightningAddress() async {
    final storedAddress = await _payService.getStoredAddress();
    try {
      final lookup = await _lookupStatus.execute();
      switch (lookup) {
        case ActiveLookupResult(:final nym):
          final address = '$nym@$lightningAddressDomain';
          if (address != storedAddress) {
            await _payService.storeAddress(address);
          }
          return address;
        case InactiveLookupResult() || null:
          if (storedAddress != null) {
            await _payService.clearStoredAddress();
          }
          return null;
      }
    } on PayServiceException {
      return storedAddress;
    }
  }
}
