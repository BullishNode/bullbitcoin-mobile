import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';

abstract class SamRockPairingServicePort {
  Future<SamRockPairingResponse> submitSetup({
    required SamRockPairingRequest request,
    required Map<String, Object?> payload,
  });
}

class SamRockPairingResponse {
  final bool success;
  final bool serverFailure;
  final String? message;
  final Map<String, Object?> result;

  const SamRockPairingResponse({
    required this.success,
    this.serverFailure = false,
    this.message,
    this.result = const {},
  });
}
