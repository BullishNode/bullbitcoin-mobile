import 'package:bb_mobile/core/errors/bull_exception.dart';

class Bip85NoDefaultWalletException extends BullException {
  Bip85NoDefaultWalletException() : super('No default Bitcoin wallet found');
}

class Bip85DerivationConflictException extends BullException {
  Bip85DerivationConflictException(super.message);
}
