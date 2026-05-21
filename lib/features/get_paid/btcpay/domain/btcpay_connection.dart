import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';

class BtcpayConnection {
  final String serverUrl;
  final List<SamRockSetupCapability> capabilities;
  final List<BtcpayPairingWalletNetwork> walletNetworks;
  final DateTime pairedAt;

  const BtcpayConnection({
    required this.serverUrl,
    required this.capabilities,
    required this.walletNetworks,
    required this.pairedAt,
  });

  factory BtcpayConnection.fromPairing({
    required SamRockPairingRequest request,
    required PrepareBtcpayPairingWalletsResult preparedWallets,
    required DateTime pairedAt,
  }) {
    return BtcpayConnection(
      serverUrl: btcpayServerUrlFor(request),
      capabilities: request.setup.toList()
        ..sort((a, b) => a.value.compareTo(b.value)),
      walletNetworks: preparedWallets.wallets.map((wallet) {
        return wallet.network;
      }).toList(),
      pairedAt: pairedAt,
    );
  }
}

String btcpayServerUrlFor(SamRockPairingRequest request) {
  final uri = request.protocolUri;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
