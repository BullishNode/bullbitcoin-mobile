/// Port interface for the pay service.
/// Domain use cases depend on this, not the concrete datasource.
abstract class PayServicePort {
  Future<String> register({
    required String nym,
    required String ctDescriptor,
    required String npubHex,
    required String signatureHex,
  });

  Future<void> deleteRegistration({
    required String npubHex,
    required String signatureHex,
  });

  Future<({String nym, bool active})?> lookupByNpub(String npubHex);

  Future<String?> getStoredAddress();

  Future<void> storeAddress(String address);
}

class PayServiceException implements Exception {
  final String message;
  PayServiceException(this.message);

  @override
  String toString() => message;
}
