import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';

class SamRockSetupPayloadBuilder {
  const SamRockSetupPayloadBuilder();

  Map<String, Object?> build({
    required SamRockPairingRequest request,
    required PrepareBtcpayPairingWalletsResult preparedWallets,
  }) {
    final byNetwork = {
      for (final prepared in preparedWallets.wallets)
        prepared.network: prepared,
    };
    final payload = <String, Object?>{};

    if (request.supportsBitcoinChain) {
      final wallet = byNetwork[BtcpayPairingWalletNetwork.bitcoin]?.wallet;
      payload['BTC'] = {'Descriptor': _descriptorOrThrow(wallet, 'BTC')};
    }

    if (request.supportsLiquidChain) {
      final wallet = byNetwork[BtcpayPairingWalletNetwork.liquid]?.wallet;
      payload['LBTC'] = {'Descriptor': _descriptorOrThrow(wallet, 'LBTC')};
    }

    if (request.supportsLightning) {
      final wallet = byNetwork[BtcpayPairingWalletNetwork.liquid]?.wallet;
      payload['BTCLN'] = {
        'Type': 'Boltz',
        'LBTC': {'Descriptor': _descriptorOrThrow(wallet, 'BTCLN')},
      };
    }

    if (payload.isEmpty) {
      throw SamRockSetupPayloadException(
        'SamRock setup payload has no supported payment methods',
      );
    }
    return payload;
  }

  String _descriptorOrThrow(Wallet? wallet, String paymentMethod) {
    final descriptor = wallet?.externalPublicDescriptor.trim();
    if (descriptor == null || descriptor.isEmpty) {
      throw SamRockSetupPayloadException(
        'Missing $paymentMethod wallet descriptor',
      );
    }
    return descriptor;
  }
}

class SamRockSetupPayloadException extends BullException {
  SamRockSetupPayloadException(super.message);
}
