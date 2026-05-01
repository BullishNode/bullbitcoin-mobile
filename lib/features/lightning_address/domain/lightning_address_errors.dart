import 'package:bb_mobile/core/errors/bull_exception.dart';

class LightningAddressWalletAlreadyExistsException extends BullException {
  LightningAddressWalletAlreadyExistsException()
    : super('Lightning address wallet already exists');
}

class LightningAddressSweepException extends BullException {
  LightningAddressSweepException(super.message);
}

class LightningAddressNoDefaultWalletException extends BullException {
  LightningAddressNoDefaultWalletException()
    : super('No default Bitcoin wallet found');
}

class LightningAddressRegistrationException extends BullException {
  LightningAddressRegistrationException(super.message);
}
