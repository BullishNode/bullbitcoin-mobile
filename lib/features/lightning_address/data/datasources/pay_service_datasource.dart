import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:dio/dio.dart';

class PayServiceDatasource {
  final Dio _dio;

  PayServiceDatasource({Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: payServiceBaseUrl));

  /// Registers a nym with the pay service.
  /// Returns the lightning address on success.
  /// Throws on nym taken, invalid signature, or network error.
  Future<String> register({
    required String nym,
    required String ctDescriptor,
    required String npubHex,
    required String signatureHex,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/register',
      data: {
        'nym': nym,
        'ct_descriptor': ctDescriptor,
        'npub': npubHex,
        'signature': signatureHex,
      },
    );

    final data = response.data!;

    // LNURL-style error: HTTP 200 with {"status": "ERROR", "reason": "..."}
    if (data['status'] == 'ERROR') {
      throw PayServiceException(data['reason'] as String? ?? 'Unknown error');
    }

    return data['lightning_address'] as String;
  }
}

class PayServiceException implements Exception {
  final String message;
  PayServiceException(this.message);

  @override
  String toString() => message;
}
