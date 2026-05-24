import 'package:bb_mobile/core/errors/bull_exception.dart';

enum DeterministicWalletExceptionType {
  invalidRequest,
  walletMismatch,
  generic,
}

class DeterministicWalletException extends BullException {
  final DeterministicWalletExceptionType type;

  DeterministicWalletException._(this.type, super.message);

  factory DeterministicWalletException.invalidRequest(String message) {
    return DeterministicWalletException._(
      DeterministicWalletExceptionType.invalidRequest,
      message,
    );
  }

  factory DeterministicWalletException.walletMismatch(String message) {
    return DeterministicWalletException._(
      DeterministicWalletExceptionType.walletMismatch,
      message,
    );
  }

  factory DeterministicWalletException.generic() {
    return DeterministicWalletException._(
      DeterministicWalletExceptionType.generic,
      'Could not prepare deterministic wallets',
    );
  }
}
