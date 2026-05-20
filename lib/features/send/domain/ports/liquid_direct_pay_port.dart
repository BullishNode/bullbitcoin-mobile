class LiquidDirectPayMetadata {
  final List<String> paymentMethods;
  final Uri callback;

  const LiquidDirectPayMetadata({
    required this.paymentMethods,
    required this.callback,
  });
}

class LiquidDirectPayCallbackResult {
  final String? status;
  final String? code;
  final String? reason;
  final String? liquidAddress;

  const LiquidDirectPayCallbackResult({
    this.status,
    this.code,
    this.reason,
    this.liquidAddress,
  });
}

abstract class LiquidDirectPayPort {
  Future<LiquidDirectPayMetadata> fetchMetadata(Uri metadataUrl);

  Future<LiquidDirectPayCallbackResult> requestLiquidPayment(
    Uri callback, {
    required Map<String, String> body,
  });
}
