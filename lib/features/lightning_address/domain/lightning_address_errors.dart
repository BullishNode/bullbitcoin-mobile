import 'package:bb_mobile/core/errors/bull_exception.dart';

class LightningAddressWalletAlreadyExistsException extends BullException {
  LightningAddressWalletAlreadyExistsException()
    : super('Lightning address wallet already exists');
}

class LightningAddressWalletNotFoundException extends BullException {
  LightningAddressWalletNotFoundException()
    : super('Lightning address wallet not found');
}

class LightningAddressSweepException extends BullException {
  LightningAddressSweepException(super.message);
}
