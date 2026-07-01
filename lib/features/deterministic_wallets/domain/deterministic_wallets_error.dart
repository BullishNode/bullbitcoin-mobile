import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:flutter/widgets.dart';

enum DeterministicWalletExceptionType {
  invalidRequest,
  walletMismatch,
  rollbackFailed,
  generic,
}

sealed class DeterministicWalletException extends BullException {
  final DeterministicWalletExceptionType type;

  DeterministicWalletException._(this.type, super.message);

  factory DeterministicWalletException.invalidRequest(String message) {
    return InvalidDeterministicWalletRequestException(message);
  }

  factory DeterministicWalletException.walletMismatch(String message) {
    return DeterministicWalletMismatchException(message);
  }

  factory DeterministicWalletException.rollbackFailed() {
    return DeterministicWalletRollbackException();
  }

  factory DeterministicWalletException.generic() {
    return GenericDeterministicWalletException();
  }

  String toTranslated(BuildContext context) {
    return context.loc.mempoolErrorUnexpected;
  }
}

final class InvalidDeterministicWalletRequestException
    extends DeterministicWalletException {
  InvalidDeterministicWalletRequestException(String message)
    : super._(DeterministicWalletExceptionType.invalidRequest, message);
}

final class DeterministicWalletMismatchException
    extends DeterministicWalletException {
  DeterministicWalletMismatchException(String message)
    : super._(DeterministicWalletExceptionType.walletMismatch, message);
}

final class DeterministicWalletRollbackException
    extends DeterministicWalletException {
  DeterministicWalletRollbackException()
    : super._(
        DeterministicWalletExceptionType.rollbackFailed,
        'Could not roll back deterministic wallets',
      );
}

final class GenericDeterministicWalletException
    extends DeterministicWalletException {
  GenericDeterministicWalletException()
    : super._(
        DeterministicWalletExceptionType.generic,
        'Could not prepare deterministic wallets',
      );
}
