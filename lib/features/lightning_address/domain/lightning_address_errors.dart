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

/// Thrown when the bullpay-side action (register / delete) succeeded but the
/// Nostr kind:0 broadcast reached zero relays. The user is in a consistent
/// server state but their Nostr profile is stale; the cubit surfaces this
/// distinctly so the UI can prompt a manual retry via "Republish to Nostr".
class LightningAddressNostrPublishFailedException extends BullException {
  LightningAddressNostrPublishFailedException(super.message);
}
