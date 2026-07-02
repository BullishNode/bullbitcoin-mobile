import 'package:bb_mobile/features/btcpay/domain/btcpay_error.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';

class PreviewBtcpaySamRockPairingUsecase {
  final SamRockPairingRequestParser _parser;

  const PreviewBtcpaySamRockPairingUsecase({required this._parser});

  BtcpaySamRockPairingPreview execute(String pairingUrl) {
    final SamRockPairingRequest request;
    try {
      request = _parser.parse(pairingUrl);
    } on SamRockPairingRequestException catch (e) {
      throw BtcpayPairingException.invalidRequest(e.message);
    }
    return BtcpaySamRockPairingPreview(
      serverUrl: btcpayServerUrlFor(request),
      supportsBitcoinChain: request.supportsBitcoinChain,
      supportsLiquidChain: request.supportsLiquidChain,
      supportsLightning: request.supportsLightning,
    );
  }
}

class BtcpaySamRockPairingPreview {
  final String serverUrl;
  final bool supportsBitcoinChain;
  final bool supportsLiquidChain;
  final bool supportsLightning;

  const BtcpaySamRockPairingPreview({
    required this.serverUrl,
    required this.supportsBitcoinChain,
    required this.supportsLiquidChain,
    required this.supportsLightning,
  });
}
