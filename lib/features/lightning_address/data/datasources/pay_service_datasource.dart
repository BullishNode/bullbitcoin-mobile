import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

class PayServiceDatasource {
  static const _boxName = 'lightning_address';
  static const _addressKey = 'address';

  final Dio _dio;

  PayServiceDatasource({Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: payServiceBaseUrl));

  /// Registers a nym with the pay service.
  /// Returns the lightning address on success.
  /// Persists the address locally for later retrieval.
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

    if (data['status'] == 'ERROR') {
      throw PayServiceException(data['reason'] as String? ?? 'Unknown error');
    }

    final address = data['lightning_address'] as String;

    final box = await Hive.openBox<String>(_boxName);
    await box.put(_addressKey, address);

    return address;
  }

  /// Returns the locally stored lightning address, or null if not registered.
  Future<String?> getStoredAddress() async {
    final box = await Hive.openBox<String>(_boxName);
    return box.get(_addressKey);
  }

  /// Stores a lightning address locally (for recovery without re-registering).
  Future<void> storeAddress(String address) async {
    final box = await Hive.openBox<String>(_boxName);
    await box.put(_addressKey, address);
  }

  /// Checks if an npub has an existing registration on the server.
  /// Returns (nym, active) or null if not found.
  Future<({String nym, bool active})?> lookupByNpub(String npubHex) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/register/lookup',
        queryParameters: {'npub': npubHex},
      );
      final data = response.data;
      if (data == null || data['status'] == 'ERROR') return null;
      return (nym: data['nym'] as String, active: data['active'] as bool);
    } on DioException {
      return null;
    }
  }

  /// Deletes the registration on the server and clears local storage.
  Future<void> deleteRegistration({
    required String npubHex,
    required String signatureHex,
  }) async {
    final response = await _dio.delete<dynamic>(
      '/register',
      data: {
        'npub': npubHex,
        'signature': signatureHex,
      },
    );

    if (response.data is Map && response.data['status'] == 'ERROR') {
      throw PayServiceException(
        response.data['reason'] as String? ?? 'Unknown error',
      );
    }

    final box = await Hive.openBox<String>(_boxName);
    await box.delete(_addressKey);
  }
}

class PayServiceException implements Exception {
  final String message;
  PayServiceException(this.message);

  @override
  String toString() => message;
}
