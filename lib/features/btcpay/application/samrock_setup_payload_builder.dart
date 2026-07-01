import 'package:bb_mobile/features/btcpay/application/application_errors.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';

class SamRockSetupPayloadBuilder {
  const SamRockSetupPayloadBuilder();

  Map<String, Object?> build({
    required SamRockPairingRequest request,
    required PreparedDeterministicWallets preparedWallets,
  }) {
    final byNetwork = {
      for (final prepared in preparedWallets.wallets)
        BtcpayWalletNetwork.fromSpecId(prepared.specId): prepared,
    };
    final payload = <String, Object?>{};

    if (request.supportsBitcoinChain) {
      final wallet = byNetwork[BtcpayWalletNetwork.bitcoin];
      payload['BTC'] = {'Descriptor': _descriptorOrThrow(wallet, 'BTC')};
    }

    if (request.supportsLiquidChain) {
      final wallet = byNetwork[BtcpayWalletNetwork.liquid];
      payload['LBTC'] = {'Descriptor': _descriptorOrThrow(wallet, 'LBTC')};
    }

    if (request.supportsLightning) {
      final wallet = byNetwork[BtcpayWalletNetwork.liquid];
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

  String _descriptorOrThrow(
    PreparedDeterministicWallet? wallet,
    String paymentMethod,
  ) {
    final descriptor = wallet?.externalPublicDescriptor.trim();
    if (descriptor == null || descriptor.isEmpty) {
      throw SamRockSetupPayloadException(
        'Missing $paymentMethod wallet descriptor',
      );
    }
    return descriptor;
  }
}
