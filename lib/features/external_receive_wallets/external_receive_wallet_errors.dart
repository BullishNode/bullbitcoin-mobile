import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';

class ExternalReceiveWalletAlreadyExistsException extends BullException {
  ExternalReceiveWalletAlreadyExistsException()
    : super('External receive wallet already exists');
}

class ExternalReceiveWalletSweepException extends BullException {
  ExternalReceiveWalletSweepException(super.message);
}

class ExternalReceiveWalletNoDefaultWalletException extends BullException {
  ExternalReceiveWalletNoDefaultWalletException()
    : super('No default Bitcoin wallet found');
}

class ExternalReceiveWalletMetadataException extends BullException {
  final Wallet wallet;
  final Object cause;
  final bool repairedExistingWallet;

  ExternalReceiveWalletMetadataException({
    required this.wallet,
    required this.cause,
    this.repairedExistingWallet = false,
  }) : super('External receive wallet metadata update failed');
}
